#!/usr/bin/env python3
"""safe_psql.py - the SQL gate for the agentic-sql skill.

Runs ONE read-only query against a Postgres database after checking it:

  1. the query must be exactly one statement, a SELECT (or a UNION of SELECTs);
  2. the WHOLE parse tree is walked: no INSERT/UPDATE/DELETE/MERGE, DDL, SELECT INTO, locking
     clauses, COPY, SET, transaction control or unparsed commands anywhere in it;
  3. every function call must be on an allow-list (dangerous Postgres functions are never typed
     by the parser, so they arrive as unknown calls and are refused unless listed);
  4. what is sent to the server is the statement REGENERATED from the validated tree, never the
     raw text, with a row limit enforced, parameters bound by the server (never spliced in), and
     a connection that is read-only with its timeouts set at connect time.

It also refuses to run as a role that could do damage anyway (superuser, bypassrls, createrole,
createdb, or a member of a write/file/program predefined role). The connection URL is read from an
environment variable, never from the command line, and never printed.

Usage:
  safe_psql.py --env ACME_DATABASE_URL --sql "SELECT count(*) FROM users WHERE id = :id" --param id=7
  safe_psql.py --check-only --sql "SELECT 1"        # gate only, no database, prints the SQL it would send

Exit codes: 0 ok · 2 refused by the gate (reasons on stderr) · 3 the role is not safe to use ·
4 connection or execution error · 5 usage or missing dependency.

Dependencies: pip install -r requirements.txt  (sqlglot, psycopg 3)
"""

import argparse
import csv
import io
import json
import os
import re
import secrets
import sys
import time

try:
    import sqlglot
    from sqlglot import exp
except ImportError:  # pragma: no cover
    sys.exit("safe_psql: sqlglot is not installed. Run: pip install -r requirements.txt")

DEFAULT_MAX_ROWS = 1000
DEFAULT_DISPLAY_ROWS = 50
DEFAULT_STATEMENT_TIMEOUT_MS = 30_000
LOCK_TIMEOUT_MS = 5_000
IDLE_IN_TX_TIMEOUT_MS = 30_000

# Functions allowed by default. Unknown calls are refused; a project extends this with
# --allowed-functions FILE (one name per line). Names are compared lower-case, without quotes
# and without schema qualification.
DEFAULT_ALLOWED_FUNCTIONS = frozenset("""
count sum avg min max bool_and bool_or every array_agg string_agg json_agg jsonb_agg
json_object_agg jsonb_object_agg coalesce nullif greatest least
lower upper initcap length char_length character_length octet_length trim ltrim rtrim btrim
substring substr replace concat concat_ws left right position strpos split_part regexp_replace
regexp_match regexp_matches starts_with reverse repeat lpad rpad md5 encode decode to_char
abs round trunc ceil ceiling floor mod power sqrt sign div
now current_date current_time current_timestamp localtime localtimestamp date_trunc date_part extract
age make_date make_timestamp to_date to_timestamp date
generate_series unnest row_number rank dense_rank ntile lag lead first_value last_value nth_value
percent_rank cume_dist
json_build_object jsonb_build_object json_build_array jsonb_build_array jsonb_array_elements
jsonb_array_elements_text jsonb_array_length json_array_length json_extract_path json_extract_path_text
jsonb_extract_path jsonb_extract_path_text jsonb_typeof json_typeof jsonb_object_keys jsonb_each
jsonb_each_text to_json to_jsonb
array_length array_to_string string_to_array cardinality array_position array_remove
cast try_cast case if exists any all
""".split())

# Typed (parser-known) functions are allowed unless listed here. This is a belt-and-braces list:
# the tests assert that the dangerous Postgres functions are NOT typed by the parser at all.
TYPED_DENY = frozenset("nextval setval pg_sleep set_config".split())

STATEMENT_NODES = ("Insert", "Update", "Delete", "Merge", "Create", "Alter", "Drop", "TruncateTable",
                   "Grant", "Copy", "Set", "Transaction", "Commit", "Rollback", "Command", "Into",
                   "Lock", "Use", "Analyze", "Comment", "Refresh", "Revoke", "Kill")
FORBIDDEN_CLASSES = tuple(getattr(exp, n) for n in STATEMENT_NODES if hasattr(exp, n))
for _base in ("DML", "DDL"):
    if hasattr(exp, _base):
        FORBIDDEN_CLASSES += (getattr(exp, _base),)
ROOT_CLASSES = (exp.Select, exp.Union) if hasattr(exp, "Union") else (exp.Select,)
SET_OPERATION_ROOTS = tuple(c for c in (getattr(exp, n, None) for n in ("Union", "Intersect", "Except")) if c)

PREDEFINED_DANGEROUS_ROLES = ("pg_write_all_data", "pg_read_server_files", "pg_write_server_files",
                              "pg_execute_server_program", "pg_signal_backend", "pg_database_owner")


class Refused(Exception):
    def __init__(self, reasons):
        super().__init__("; ".join(reasons))
        self.reasons = reasons


def load_allowed(path=None):
    allowed = set(DEFAULT_ALLOWED_FUNCTIONS)
    if path:
        with open(path) as f:
            for line in f:
                line = line.split("#", 1)[0].strip().lower()
                if line:
                    allowed.add(line)
    return allowed


def _function_name(node):
    """The name Postgres will see. Anonymous calls carry it; typed calls (date_trunc, count, ...) are
    rendered to Postgres SQL and the leading identifier is read back, because the parser's own class
    names differ (date_trunc is TimestampTrunc). Returns None for operators, which render without a name."""
    if isinstance(node, exp.Anonymous):
        return str(node.name).lower().strip('"')
    m = re.match(r'\s*(?:"?[A-Za-z_][A-Za-z0-9_$]*"?\.)*"?([A-Za-z_][A-Za-z0-9_$]*)"?\s*\(', node.sql(dialect="postgres"))
    return m.group(1).lower() if m else None


def gate(sql, allowed=None, max_rows=DEFAULT_MAX_ROWS):
    """Validate `sql`. Returns (sql_to_send, parameter_names). Raises Refused with every reason."""
    allowed = allowed if allowed is not None else set(DEFAULT_ALLOWED_FUNCTIONS)
    reasons = []
    if not isinstance(sql, str) or not sql.strip():
        raise Refused(["empty query"])
    try:
        parsed = [t for t in sqlglot.parse(sql, read="postgres") if t is not None and not isinstance(t, exp.Semicolon)]
    except Exception as e:  # the parser could not read it: refuse, never guess
        raise Refused([f"could not parse the query ({type(e).__name__}); refusing"])
    if len(parsed) != 1:
        raise Refused([f"exactly one statement is allowed, found {len(parsed)}"])
    tree = parsed[0]

    if not isinstance(tree, ROOT_CLASSES):
        reasons.append(f"the statement must be a SELECT, got {type(tree).__name__}")
    for node in tree.walk():
        node = node[0] if isinstance(node, tuple) else node
        if isinstance(node, FORBIDDEN_CLASSES):
            reasons.append(f"{type(node).__name__} is not allowed anywhere in the query")
        elif isinstance(node, exp.Func):
            if isinstance(node, SYNTAX_FUNCS):
                continue
            name = _function_name(node)
            if name is None:
                continue  # an operator (AND, ->>, ::), not a call by name; real calls render as name(...)
            if name in TYPED_DENY or name not in allowed:
                reasons.append(f"function {name}() is not on the allow-list")
    if reasons:
        raise Refused(sorted(set(reasons)))

    # parameters: :name placeholders become server-bound parameters
    marker = f"__aim{secrets.token_hex(4)}_"
    names = []
    for ph in list(tree.find_all(exp.Placeholder)):
        n = str(ph.this)
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", n):
            raise Refused([f"unsupported placeholder {n!r}"])
        names.append(n)
        ph.replace(exp.Var(this=f"{marker}{n}"))

    _enforce_limit(tree, max_rows)
    out = tree.sql(dialect="postgres")
    out = out.replace("%", "%%")
    for n in set(names):
        out = out.replace(f"{marker}{n}", f"%({n})s")
    return out, sorted(set(names))


# parser nodes that are syntax, not named functions (no way to call a Postgres function through them)
SYNTAX_FUNCS = tuple(getattr(exp, n) for n in ("Cast", "TryCast", "Case", "If", "Exists", "Any", "All", "Coalesce",
                                                "Nullif", "Greatest", "Least", "Extract", "Paren", "Tuple", "Array",
                                                "Bracket", "Window", "Filter", "Ordered", "Alias") if hasattr(exp, n))


def _enforce_limit(tree, max_rows):
    limit = tree.args.get("limit")
    if limit is None:
        tree.set("limit", exp.Limit(expression=exp.Literal.number(max_rows)))
        return
    expr = limit.args.get("expression")
    if isinstance(expr, exp.Literal) and expr.is_int:
        if int(expr.this) > max_rows:
            limit.set("expression", exp.Literal.number(max_rows))
    else:
        limit.set("expression", exp.Literal.number(max_rows))


def _scrub(message, url):
    message = str(message).strip().splitlines()[0] if str(message).strip() else "error"
    if url:
        message = message.replace(url, "<url>")
    return re.sub(r"(postgres(?:ql)?://)[^\s]+", r"\1<redacted>", message)[:300]


def check_role(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT rolsuper, rolbypassrls, rolcreaterole, rolcreatedb FROM pg_roles WHERE rolname = current_user")
        row = cur.fetchone()
        problems = []
        if row:
            for flag, label in zip(row, ("superuser", "bypassrls", "createrole", "createdb")):
                if flag:
                    problems.append(label)
        cur.execute("SELECT rolname FROM pg_roles WHERE rolname = ANY(%s)", (list(PREDEFINED_DANGEROUS_ROLES),))
        for (rolname,) in cur.fetchall():
            cur.execute("SELECT pg_has_role(current_user, %s, 'member')", (rolname,))
            if cur.fetchone()[0]:
                problems.append(f"member of {rolname}")
    conn.rollback()
    return problems


def render(columns, rows, fmt, total, display_rows):
    shown = rows[:display_rows]
    if fmt == "json":
        body = json.dumps([dict(zip(columns, r)) for r in shown], default=str, indent=2)
    elif fmt == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(columns)
        w.writerows([["" if v is None else v for v in r] for r in shown])
        body = buf.getvalue().rstrip("\n")
    else:
        lines = ["\t".join(columns)] + ["\t".join("NULL" if v is None else str(v) for v in r) for r in shown]
        body = "\n".join(lines)
    if total > len(shown):
        body += f"\n({len(shown)} of {total} rows shown; raise --display-rows to see more)"
    return body


def main(argv=None):
    ap = argparse.ArgumentParser(description="Run one read-only SELECT through the SQL gate.")
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--sql", help="the query")
    src.add_argument("--file", help="read the query from a file")
    ap.add_argument("--env", default="DATABASE_URL", help="environment variable that holds the connection URL")
    ap.add_argument("--param", action="append", default=[], metavar="NAME=VALUE")
    ap.add_argument("--allowed-functions", metavar="FILE", help="extra allowed function names, one per line")
    ap.add_argument("--max-rows", type=int, default=DEFAULT_MAX_ROWS)
    ap.add_argument("--display-rows", type=int, default=DEFAULT_DISPLAY_ROWS)
    ap.add_argument("--timeout-ms", type=int, default=DEFAULT_STATEMENT_TIMEOUT_MS)
    ap.add_argument("--format", choices=("table", "json", "csv"), default="table")
    ap.add_argument("--log", metavar="FILE", help="append one JSON line per run: query id, parameter names, rows, ms, status")
    ap.add_argument("--query-id", default="adhoc")
    ap.add_argument("--check-only", action="store_true", help="run the gate only; print the SQL that would be sent")
    a = ap.parse_args(argv)

    sql = a.sql if a.sql is not None else (open(a.file).read() if a.file else sys.stdin.read())
    try:
        allowed = load_allowed(a.allowed_functions)
        send, names = gate(sql, allowed, a.max_rows)
    except Refused as r:
        _log(a, "refused", 0, 0, [])
        for reason in r.reasons:
            print(f"refused: {reason}", file=sys.stderr)
        return 2
    except OSError as e:
        print(f"safe_psql: {e}", file=sys.stderr)
        return 5

    params = {}
    for item in a.param:
        k, sep, v = item.partition("=")
        if not sep or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k):
            print(f"safe_psql: bad --param {k!r}; use NAME=VALUE", file=sys.stderr)
            return 5
        params[k] = v
    missing = [n for n in names if n not in params]
    if missing:
        print(f"safe_psql: missing --param for: {', '.join(missing)}", file=sys.stderr)
        return 5
    extra = [k for k in params if k not in names]
    if extra:
        print(f"safe_psql: --param not used by the query: {', '.join(extra)}", file=sys.stderr)
        return 5

    if a.check_only:
        print(send.replace("%%", "%"))
        return 0

    try:
        import psycopg
    except ImportError:
        print("safe_psql: psycopg is not installed. Run: pip install -r requirements.txt", file=sys.stderr)
        return 5
    url = os.environ.get(a.env)
    if not url:
        print(f"safe_psql: environment variable {a.env} is not set", file=sys.stderr)
        return 5

    options = (f"-c statement_timeout={a.timeout_ms} -c lock_timeout={LOCK_TIMEOUT_MS} "
               f"-c idle_in_transaction_session_timeout={IDLE_IN_TX_TIMEOUT_MS} -c default_transaction_read_only=on")
    t0 = time.time()
    try:
        conn = psycopg.connect(url, options=options, autocommit=False)
    except Exception as e:
        print(f"safe_psql: could not connect: {_scrub(e, url)}", file=sys.stderr)
        return 4
    try:
        conn.read_only = True
        problems = check_role(conn)
        if problems:
            print("safe_psql: refusing to run as this role: " + ", ".join(problems) +
                  ". Use a role with SELECT only (see reference/run.md).", file=sys.stderr)
            _log(a, "unsafe-role", 0, int((time.time() - t0) * 1000), names)
            return 3
        with conn.cursor() as cur:
            cur.execute(send, params or None)
            columns = [d.name for d in cur.description] if cur.description else []
            rows = cur.fetchall() if cur.description else []
        conn.rollback()
    except Exception as e:
        print(f"safe_psql: query failed: {_scrub(e, url)}", file=sys.stderr)
        _log(a, "error", 0, int((time.time() - t0) * 1000), names)
        return 4
    finally:
        try:
            conn.close()
        except Exception:
            pass
    ms = int((time.time() - t0) * 1000)
    print(render(columns, rows, a.format, len(rows), a.display_rows))
    _log(a, "ok", len(rows), ms, names)
    return 0


def _log(a, status, rows, ms, names):
    if not getattr(a, "log", None):
        return
    try:
        with open(a.log, "a") as f:
            f.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "query_id": a.query_id,
                                "params": names, "status": status, "rows": rows, "ms": ms}) + "\n")
    except OSError:
        pass


if __name__ == "__main__":
    sys.exit(main())
