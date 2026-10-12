#!/usr/bin/env python3
"""safe_psql_write.py - the write door of the agentic-sql skill (F037).

Changes data only with a person's approval. The read-only door (safe_psql.py) is untouched.

  propose  check one INSERT / UPDATE / DELETE against the settings file, dry-run it inside a transaction
           that is rolled back, and store a request. Prints counts and column NAMES, never values.
  approve  a PERSON shows the full before/after and answers on the real terminal. Refused without one.
  apply    run the approved request once, in a transaction; roll back if the row count differs.
  reject / status / list

Rules: exactly one statement; INSERT or UPDATE (DELETE only if settings allow_hard_delete AND the table
allows it); UPDATE/DELETE need a WHERE; only tables and columns on the write list; no RETURNING, no
UPDATE ... FROM / DELETE ... USING, no ON CONFLICT DO UPDATE, no functions off the allow-list; values are
bound by the server. The database login must not be a superuser (or similar) and must not be able to write
any table that is not on the write list.

Exit codes: 0 ok · 2 refused by the rules or settings · 3 unsafe database login · 4 connection or query
error · 5 usage error · 6 approval missing, wrong, expired or already used · 7 row count changed, rolled back.

Honest limit: the agent and the person share one user account, so this stops an agent that uses the
sanctioned path, not someone who deliberately works around the tool. The database login's own limits are
the real backstop. See backlog F037 / reference/write.md.
"""

import argparse
import hashlib
import json
import os
import re
import secrets
import sys
import time
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import sqlglot
    from sqlglot import exp
    import safe_psql as sp
except ImportError as e:  # pragma: no cover
    sys.exit(f"safe_psql_write: a package is missing ({e}). Run: pip install -r requirements.txt")

Refused = sp.Refused
DEFAULT_MAX_ROWS = 25
DEFAULT_TTL_MINUTES = 10
DEFAULT_DISPLAY_ROWS = 10
AGENT_ENV_MARKERS = ("CLAUDECODE", "AIM_AGENT_ID", "AIM_AGENT_NAME", "CODEX_SANDBOX", "CODEX_THREAD_ID")
DML = (exp.Insert, exp.Update, exp.Delete, exp.Merge)
# everything the read door forbids, except the write statements themselves and their parser base class
# (Insert inherits from both DML and DDL in this parser, so both base classes are dropped; Create, Alter, Drop and the
# rest stay in the list individually, and the count of write statements guards nesting.)
FORBIDDEN = tuple(c for c in sp.FORBIDDEN_CLASSES if c not in (exp.DML, exp.DDL) and not issubclass(c, DML))


# ---------------------------------------------------------------- settings
def home_dir():
    return os.environ.get("SAFE_PSQL_HOME") or os.path.join(os.path.expanduser("~"), ".safe-psql")


def find_settings(path=None):
    for p in (path, os.environ.get("SAFE_PSQL_WRITE_SETTINGS"), os.path.join(os.getcwd(), ".safe-psql", "write.yaml"),
              os.path.join(home_dir(), "write.yaml")):
        if p and os.path.isfile(p):
            return p
    return None


def norm_table(name):
    n = name.strip().replace('"', "").lower()
    return n if "." in n else f"public.{n}"


def load_settings(path=None):
    import yaml
    p = find_settings(path)
    if not p:
        raise Refused(["no settings file: nothing is writable. Create .safe-psql/write.yaml (see reference/write.md)"])
    with open(p) as f:
        raw = yaml.safe_load(f) or {}
    if not isinstance(raw, dict):
        raise Refused([f"{p}: the settings file must be a mapping"])
    tables = {}
    for k, v in (raw.get("tables") or {}).items():
        v = v or {}
        tables[norm_table(str(k))] = {
            "insert": bool(v.get("insert", False)),
            "update": v.get("update", False),  # True | False | [columns]
            "delete": bool(v.get("delete", False)),
            "max_rows": int(v.get("max_rows", raw.get("default_max_rows", DEFAULT_MAX_ROWS))),
        }
    envs = raw.get("environments") or {}
    return {
        "path": p,
        "allow_hard_delete": bool(raw.get("allow_hard_delete", False)),
        "approval_ttl_minutes": int(raw.get("approval_ttl_minutes", DEFAULT_TTL_MINUTES)),
        "tables": tables,
        "environments": envs,
        "log": raw.get("log"),
    }


def confirm_by_typing(settings, environment):
    e = (settings["environments"].get(environment) or {})
    if "confirm_by_typing" in e:
        return bool(e["confirm_by_typing"])
    return environment.lower() in ("production", "prod")


# ---------------------------------------------------------------- the rules
def _table_of(node):
    t = node.this
    if isinstance(t, exp.Schema):
        t = t.this
    if not isinstance(t, exp.Table):
        raise Refused(["could not read the target table"])
    return t


def _qualified(t):
    name = t.name.lower()
    db = (t.db or "public").lower()
    return f"{db}.{name}"


def gate_write(sql, settings, allowed=None):
    """Validate one write statement. Returns a dict: kind, table, columns, tree (placeholders still :name)."""
    allowed = allowed if allowed is not None else set(sp.DEFAULT_ALLOWED_FUNCTIONS)
    if not isinstance(sql, str) or not sql.strip():
        raise Refused(["empty statement"])
    try:
        parsed = [t for t in sqlglot.parse(sql, read="postgres") if t is not None and not isinstance(t, exp.Semicolon)]
    except Exception as e:
        raise Refused([f"could not parse the statement ({type(e).__name__}); refusing"])
    if len(parsed) != 1:
        raise Refused([f"exactly one statement is allowed, found {len(parsed)}"])
    tree = parsed[0]
    reasons = []
    if not isinstance(tree, (exp.Insert, exp.Update, exp.Delete)):
        raise Refused([f"only INSERT, UPDATE or DELETE can go through the write door, got {type(tree).__name__}"])
    kind = type(tree).__name__.upper()

    dml_nodes = [n for n in tree.walk() if isinstance(n[0] if isinstance(n, tuple) else n, DML)]
    if len(dml_nodes) != 1:
        reasons.append("exactly one write statement is allowed; writes inside WITH or subqueries are refused")
    for node in tree.walk():
        node = node[0] if isinstance(node, tuple) else node
        if isinstance(node, FORBIDDEN):
            reasons.append(f"{type(node).__name__} is not allowed anywhere in the statement")
        elif isinstance(node, exp.Func) and not isinstance(node, sp.SYNTAX_FUNCS):
            name = sp._function_name(node)
            if name is not None and (name in sp.TYPED_DENY or name not in allowed):
                reasons.append(f"function {name}() is not on the allow-list")
    if tree.args.get("returning"):
        reasons.append("RETURNING is not allowed (the dry run adds its own)")
    if kind == "UPDATE" and (tree.args.get("from_") or tree.args.get("from")):
        reasons.append("UPDATE ... FROM is not supported; use a subquery in WHERE")
    if kind == "DELETE" and tree.args.get("using"):
        reasons.append("DELETE ... USING is not supported; use a subquery in WHERE")
    if kind in ("UPDATE", "DELETE") and not tree.args.get("where"):
        reasons.append(f"{kind} needs a WHERE clause")
    conflict = tree.args.get("conflict")
    if conflict is not None:
        action = (conflict.args.get("action") or conflict.args.get("expressions"))
        text = conflict.sql("postgres").upper()
        if "DO UPDATE" in text or "DO  UPDATE" in text:
            reasons.append("ON CONFLICT DO UPDATE is not supported; use a plain INSERT or an UPDATE")
    if reasons:
        raise Refused(sorted(set(reasons)))

    table = _qualified(_table_of(tree))
    cfg = settings["tables"].get(table)
    if cfg is None:
        raise Refused([f"table {table} is not on the write list"])
    columns = []
    if kind == "INSERT":
        if not cfg["insert"]:
            reasons.append(f"INSERT is not allowed on {table}")
        if not isinstance(tree.this, exp.Schema) or not tree.this.expressions:
            reasons.append("INSERT must name its columns")
        else:
            columns = [c.name.lower() for c in tree.this.expressions]
    elif kind == "UPDATE":
        if not cfg["update"]:
            reasons.append(f"UPDATE is not allowed on {table}")
        columns = [e.this.name.lower() for e in tree.expressions if isinstance(e, exp.EQ)]
        if len(columns) != len(tree.expressions):
            reasons.append("could not read the SET list")
        if isinstance(cfg["update"], list):
            ok = {str(c).lower() for c in cfg["update"]}
            bad = [c for c in columns if c not in ok]
            if bad:
                reasons.append(f"column(s) not allowed to change on {table}: {', '.join(bad)}")
    else:  # DELETE
        if not settings["allow_hard_delete"]:
            reasons.append("DELETE is off: hard delete is not enabled in the settings (allow_hard_delete). Use an UPDATE that sets a flag")
        elif not cfg["delete"]:
            reasons.append(f"DELETE is not allowed on {table}")
    if reasons:
        raise Refused(sorted(set(reasons)))
    return {"kind": kind, "table": table, "columns": columns, "tree": tree, "max_rows": cfg["max_rows"]}


def bind(tree):
    """Replace :name placeholders; returns (sql with %(name)s, [names])."""
    tree = tree.copy()
    marker = f"__aimw{secrets.token_hex(4)}_"
    names = []
    for ph in list(tree.find_all(exp.Placeholder)):
        n = str(ph.this)
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", n):
            raise Refused([f"unsupported placeholder {n!r}"])
        names.append(n)
        ph.replace(exp.Var(this=f"{marker}{n}"))
    out = tree.sql(dialect="postgres").replace("%", "%%")
    for n in set(names):
        out = out.replace(f"{marker}{n}", f"%({n})s")
    return out, sorted(set(names))


# ---------------------------------------------------------------- storage and log
def req_dir():
    d = os.path.join(home_dir(), "requests")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def req_path(rid):
    if not re.fullmatch(r"w-[0-9a-f]{12}", rid or ""):
        raise Refused([f"bad request id {rid!r}"])
    return os.path.join(req_dir(), rid + ".json")


def load_req(rid):
    p = req_path(rid)
    if not os.path.isfile(p):
        raise Refused([f"no such request {rid}"])
    with open(p) as f:
        return json.load(f)


def save_req(req):
    p = req_path(req["id"])
    tmp = p + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(req, f, default=str)
    os.replace(tmp, p)


def scrub(req):
    """After a request is finished, drop the values it held."""
    req["params"] = None
    req["diff"] = None
    return req


def fingerprint(req):
    body = json.dumps([req["environment"], req["env_var"], req["table"], req["kind"], req["sql"],
                       sorted((req.get("params") or {}).items()), req["rows"]], default=str, sort_keys=True)
    return hashlib.sha256(body.encode()).hexdigest()


def clean(text, limit=300):
    """Make text safe to print on the approval screen: no control or escape characters, bounded length."""
    t = "".join(c if (c.isprintable() and unicodedata.category(c)[0] != "C") else "?" for c in str(text))
    return t if len(t) <= limit else t[:limit] + "..."


def settings_fingerprint(settings):
    try:
        with open(settings["path"], "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()[:16]
    except OSError:
        return "unreadable"


def purge_old(settings):
    """Drop the values of requests nobody approved in time, and delete old finished ones."""
    d = req_dir()
    now = time.time()
    for name in os.listdir(d):
        if not name.endswith(".json"):
            continue
        path = os.path.join(d, name)
        try:
            with open(path) as f:
                r = json.load(f)
            if r.get("status") in ("pending", "approved") and now > r.get("apply_by", r.get("expires", 0)):
                _finish(settings, r, "expired")
            elif r.get("status") not in ("pending", "approved") and now - os.path.getmtime(path) > 7 * 86400:
                os.remove(path)
                lock = path + ".lock"
                if os.path.exists(lock):
                    os.remove(lock)
        except (OSError, ValueError, KeyError):
            continue


def who():
    return os.environ.get("AIM_AGENT_NAME") or os.environ.get("AIM_AGENT_ID") or os.environ.get("USER") or "unknown"


def log_event(settings, event, req, **extra):
    path = (settings or {}).get("log") or os.path.join(home_dir(), "write.log")
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "event": event, "request": req.get("id"),
           "agent": req.get("agent"), "environment": req.get("environment"), "table": req.get("table"),
           "kind": req.get("kind"), "param_names": sorted((req.get("params") or {}).keys()) or req.get("param_names"),
           "rows": req.get("rows"), **extra}
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a") as f:
            f.write(json.dumps({k: v for k, v in rec.items() if v is not None}, default=str) + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------- database
def connect(url_env, timeout_ms=30000):
    import psycopg
    url = os.environ.get(url_env)
    if not url:
        raise Refused([f"environment variable {url_env} is not set"])
    opts = f"-c statement_timeout={timeout_ms} -c lock_timeout=5000 -c idle_in_transaction_session_timeout=60000"
    try:
        return psycopg.connect(url, options=opts, autocommit=False), url
    except Exception as e:
        raise DbError(f"could not connect: {sp._scrub(e, url)}")


class DbError(Exception):
    pass


class UnsafeRole(Exception):
    pass


def check_write_role(conn, settings):
    """The login may write only tables on the write list, and must not be powerful in other ways."""
    with conn.cursor() as cur:
        cur.execute("SELECT rolsuper, rolbypassrls, rolcreaterole, rolcreatedb FROM pg_roles WHERE rolname = current_user")
        row = cur.fetchone()
        problems = [l for f, l in zip(row or (), ("superuser", "bypassrls", "createrole", "createdb")) if f]
        cur.execute("SELECT rolname FROM pg_roles WHERE rolname = ANY(%s)", (list(sp.PREDEFINED_DANGEROUS_ROLES),))
        for (r,) in cur.fetchall():
            cur.execute("SELECT pg_has_role(current_user, %s, 'member')", (r,))
            if cur.fetchone()[0]:
                problems.append(f"member of {r}")
        cur.execute("""SELECT n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                       WHERE c.relkind IN ('r','p') AND n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname !~ '^pg_toast'
                         AND (has_any_column_privilege(current_user, c.oid, 'INSERT') OR has_any_column_privilege(current_user, c.oid, 'UPDATE')
                              OR has_table_privilege(current_user, c.oid, 'DELETE') OR has_table_privilege(current_user, c.oid, 'TRUNCATE'))""")
        writable = sorted(r[0].lower() for r in cur.fetchall())
    conn.rollback()
    extra = [t for t in writable if t not in settings["tables"]]
    if extra:
        problems.append("can write tables that are not on the write list: " + ", ".join(extra[:8]))
    if not writable:
        problems.append("has no write privilege on any table, so it is not a write login")
    if problems:
        raise UnsafeRole(", ".join(problems))
    return writable


def pk_columns(cur, table):
    schema, name = table.split(".", 1)
    cur.execute("""SELECT a.attname FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid JOIN pg_namespace n ON n.oid = c.relnamespace
                   JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(i.indkey)
                   WHERE i.indisprimary AND n.nspname = %s AND c.relname = %s ORDER BY a.attnum""", (schema, name))
    return [r[0] for r in cur.fetchall()]


def dry_run(conn, info, sql, params, cap):
    """Run the statement, capture before/after, roll everything back. Returns (rows, diff, has_pk)."""
    tree = info["tree"]
    kind = info["kind"]
    diff = []
    with conn.cursor() as cur:
        pk = pk_columns(cur, info["table"])
        before = {}
        if kind in ("UPDATE", "DELETE"):
            sel = exp.select("*").from_(_table_of(tree).copy()).where(tree.args["where"].this.copy()).limit(cap + 1)
            bsql, bnames = bind(sel)
            cur.execute(bsql, {k: params[k] for k in bnames})
            cols = [d.name for d in cur.description]
            brows = cur.fetchall()
            if len(brows) > cap:
                raise Refused([f"the WHERE matches more than {cap} rows (the limit for {info['table']}); narrow it"])
            for r in brows:
                d = dict(zip(cols, r))
                before[tuple(d[c] for c in pk) if pk else id(r)] = d
        wtree = tree.copy()
        wtree.set("returning", exp.Returning(expressions=[exp.Star()]))
        wsql, wnames = bind(wtree)
        cur.execute(wsql, {k: params[k] for k in wnames})
        cols = [d.name for d in cur.description] if cur.description else []
        arows = cur.fetchall() if cur.description else []
        rows = cur.rowcount
        if rows > cap:
            raise Refused([f"the statement would change {rows} rows, above the limit of {cap} for {info['table']}"])
        if kind == "DELETE":
            for d in before.values():
                diff.append({"key": [d[c] for c in pk] if pk else None, "deleted": d})
        else:
            for r in arows:
                d = dict(zip(cols, r))
                key = tuple(d[c] for c in pk) if pk else None
                if kind == "UPDATE" and key is not None and key in before:
                    changes = {c: [before[key].get(c), d[c]] for c in d if str(before[key].get(c)) != str(d[c])}
                    diff.append({"key": list(key), "changes": changes})
                else:
                    diff.append({"key": list(key) if key else None, "new": d})
    conn.rollback()
    return rows, diff, bool(pk)


# ---------------------------------------------------------------- commands
def cmd_propose(a):
    settings = load_settings(a.settings)
    allowed = sp.load_allowed(a.allowed_functions)
    info = gate_write(a.sql, settings, allowed)
    sql, names = bind(info["tree"])
    params = {}
    for item in a.param:
        k, sep, v = item.partition("=")
        if not sep or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k):
            raise UsageError(f"bad --param {k!r}; use NAME=VALUE")
        params[k] = v
    missing = [n for n in names if n not in params]
    extra = [k for k in params if k not in names]
    if missing:
        raise UsageError("missing --param for: " + ", ".join(missing))
    if extra:
        raise UsageError("--param not used by the statement: " + ", ".join(extra))
    if a.check_only:
        print(sql.replace("%%", "%"))
        return 0
    purge_old(settings)
    conn, url = connect(a.env)
    try:
        try:
            check_write_role(conn, settings)
        except UnsafeRole as e:
            print(f"safe_psql_write: refusing to run as this login: {e}", file=sys.stderr)
            return 3
        try:
            rows, diff, has_pk = dry_run(conn, info, sql, params, info["max_rows"])
        except Refused:
            raise
        except Exception as e:
            raise DbError(f"dry run failed: {sp._scrub(e, url)}")
    finally:
        try:
            conn.close()
        except Exception:
            pass
    if rows == 0:
        print("nothing to do: the statement would change 0 rows", file=sys.stderr)
        return 2
    now = time.time()
    ttl = settings["approval_ttl_minutes"] * 60
    req = {"id": "w-" + secrets.token_hex(6), "created": now, "expires": now + ttl, "status": "pending",
           "environment": a.environment, "env_var": a.env, "table": info["table"], "kind": info["kind"],
           "columns": info["columns"], "sql": sql, "params": params, "param_names": names, "rows": rows,
           "diff": diff[:DEFAULT_DISPLAY_ROWS], "diff_truncated": len(diff) > DEFAULT_DISPLAY_ROWS, "has_pk": has_pk,
           "reason": a.reason, "agent": who(), "ttl": ttl, "max_rows": info["max_rows"],
           "settings_path": settings["path"], "settings_sha256": settings_fingerprint(settings)}
    req["fingerprint"] = fingerprint(req)
    save_req(req)
    log_event(settings, "proposed", req)
    cols = ", ".join(info["columns"]) or "(all)"
    print(f"request {req['id']}: {info['kind']} {info['table']}, {rows} row(s) would change, columns: {cols}")
    print(f"environment: {a.environment} · valid for {settings['approval_ttl_minutes']} minutes · nothing has been changed yet")
    print(f"A PERSON must approve it: run `safe-psql-write approve {req['id']}` in a terminal (not from this agent session),")
    print(f"or approve it on the AI Maestro / Claude Code card. Then run `safe-psql-write apply {req['id']}`.")
    return 0


class UsageError(Exception):
    pass


def _looks_like_agent():
    return [k for k in AGENT_ENV_MARKERS if os.environ.get(k)]


class _Tty:
    """The real controlling terminal, as separate read and write handles (a text file cannot be opened r+)."""

    def __init__(self, tin, tout):
        self.tin, self.tout = tin, tout

    def write(self, text):
        self.tout.write(text)
        self.tout.flush()

    def flush(self):
        self.tout.flush()

    def readline(self):
        return self.tin.readline()


def _tty():
    try:
        tin = open("/dev/tty", "r")
        tout = open("/dev/tty", "w")
    except Exception:
        return None
    if not (tin.isatty() and tout.isatty()):
        return None
    return _Tty(tin, tout)


def render_for_person(req):
    c = clean
    lines = [f"Request {c(req['id'])} from agent '{c(req['agent'])}'", f"  environment : {c(req['environment'])}",
             f"  statement   : {c(req['kind'])} on {c(req['table'])}, {int(req['rows'])} row(s), limit {int(req['max_rows'])}",
             f"  SQL         : {c(req['sql'].replace('%%', '%'), 600)}", f"  values      : {c(json.dumps(req['params'], default=str), 600)}"]
    if req.get("reason"):
        lines.append(f"  reason      : {c(req['reason'], 200)}")
    lines.append(f"  settings    : {c(req.get('settings_path'))} (sha256 {c(req.get('settings_sha256'))})")
    lines.append("  what changes:")
    for d in req.get("diff") or []:
        key = f" (key {c(d['key'])})" if d.get("key") else ""
        if "changes" in d:
            lines.append(f"    row{key}: " + c("; ".join(f"{col}: {o!r} -> {n!r}" for col, (o, n) in d["changes"].items()), 400))
        elif "deleted" in d:
            lines.append(f"    DELETE row{key}: {c(d['deleted'], 400)}")
        else:
            lines.append(f"    INSERT row{key}: {c(d['new'], 400)}")
    if req.get("diff_truncated"):
        lines.append(f"    ... and {int(req['rows']) - len(req['diff'])} more")
    if not req.get("has_pk"):
        lines.append("    (the table has no primary key, so rows are not matched before/after)")
    return "\n".join(lines)


def cmd_approve(a):
    settings = load_settings(a.settings)
    agent_markers = _looks_like_agent()
    if agent_markers:
        print("safe_psql_write: this looks like an agent session (" + ", ".join(agent_markers) + "). Approval must be given by a person "
              "in a separate terminal window.", file=sys.stderr)
        return 6
    tty = _tty()
    if tty is None:
        print("safe_psql_write: approval needs a real terminal. Run this yourself in a terminal window.", file=sys.stderr)
        return 6
    req = load_req(a.id)
    if req["status"] != "pending":
        print(f"request {a.id} is {req['status']}, not pending", file=sys.stderr)
        return 6
    if time.time() > req["expires"]:
        _finish(settings, req, "expired")
        print(f"request {a.id} expired", file=sys.stderr)
        return 6
    if fingerprint(req) != req["fingerprint"]:
        print("safe_psql_write: the request was changed after it was proposed; refusing", file=sys.stderr)
        return 6
    tty.write("\n" + render_for_person(req) + "\n\n")
    need = req["environment"] if confirm_by_typing(settings, req["environment"]) else "yes"
    tty.write(f"Type '{need}' to approve, anything else rejects: ")
    tty.flush()
    answer = tty.readline().strip()
    if answer != need:
        _finish(settings, req, "rejected", by=os.environ.get("USER"))
        tty.write("Rejected.\n")
        return 6
    req["status"] = "approved"
    req["approved_by"] = os.environ.get("USER") or "unknown"
    req["approved_at"] = time.time()
    req["apply_by"] = req["approved_at"] + req["ttl"]
    req["approved_fingerprint"] = req["fingerprint"]
    save_req(req)
    log_event(settings, "approved", req, approver=req["approved_by"])
    tty.write(f"Approved. The agent can now run: safe-psql-write apply {req['id']}\n")
    return 0


def _finish(settings, req, status, **extra):
    req["status"] = status
    scrub(req)
    save_req(req)
    log_event(settings, status, req, **extra)


def cmd_reject(a):
    settings = load_settings(a.settings)
    req = load_req(a.id)
    if req["status"] in ("pending", "approved"):
        _finish(settings, req, "rejected", by=who())
    print(f"request {a.id}: {req['status']}")
    return 0


def cmd_status(a):
    req = load_req(a.id)
    left = int(req.get("apply_by", req["expires"]) - time.time())
    print(f"request {a.id}: {req['status']} · {req['kind']} {req['table']} · {req['rows']} row(s) · {'expires in %ds' % left if left > 0 else 'expired'}")
    return 0


def cmd_list(a):
    d = req_dir()
    for f in sorted(os.listdir(d)):
        if f.endswith(".json"):
            r = json.load(open(os.path.join(d, f)))
            print(f"{r['id']}  {r['status']:9}  {r['kind']} {r['table']}  rows={r['rows']}  {r['environment']}")
    return 0


def cmd_apply(a):
    settings = load_settings(a.settings)
    req = load_req(a.id)
    if req["status"] != "approved":
        print(f"request {a.id} is {req['status']}; a person must approve it first", file=sys.stderr)
        return 6
    if time.time() > req.get("apply_by", 0):
        _finish(settings, req, "expired")
        print(f"request {a.id} expired before it was applied", file=sys.stderr)
        return 6
    if fingerprint(req) != req["fingerprint"] or req.get("approved_fingerprint") != req["fingerprint"]:
        print("safe_psql_write: the request differs from what was approved; refusing", file=sys.stderr)
        return 6
    lock = req_path(a.id) + ".lock"
    try:
        os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
    except FileExistsError:
        print(f"request {a.id} is already being applied or was applied", file=sys.stderr)
        return 6
    conn = None
    try:
        conn, url = connect(req["env_var"])
        try:
            check_write_role(conn, settings)
        except UnsafeRole as e:
            print(f"safe_psql_write: refusing to run as this login: {e}", file=sys.stderr)
            _finish(settings, req, "failed", reason="unsafe login")
            return 3
        with conn.cursor() as cur:
            cur.execute(req["sql"], req["params"])
            rows = cur.rowcount
        if rows != req["rows"] or rows > req["max_rows"]:
            conn.rollback()
            _finish(settings, req, "failed", reason="row count changed", expected=req["rows"], got=rows)
            print(f"safe_psql_write: the statement would now change {rows} row(s), not the {req['rows']} that was approved. Rolled back; propose again.", file=sys.stderr)
            return 7
        conn.commit()
        _finish(settings, req, "applied", approver=req.get("approved_by"))
        print(f"applied request {a.id}: {rows} row(s) changed on {req['table']} ({req['environment']})")
        return 0
    except DbError as e:
        _finish(settings, req, "failed", reason="connection")
        print(f"safe_psql_write: {e}", file=sys.stderr)
        return 4
    except Exception as e:
        try:
            conn and conn.rollback()
        except Exception:
            pass
        _finish(settings, req, "failed", reason="database error")
        print(f"safe_psql_write: the change failed and was rolled back: {sp._scrub(e, os.environ.get(req['env_var']))}", file=sys.stderr)
        return 4
    finally:
        try:
            conn and conn.close()
        except Exception:
            pass


def main(argv=None):
    ap = argparse.ArgumentParser(description="Change data through the approval-gated write door.")
    ap.add_argument("--settings", help="path to write.yaml")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("propose")
    p.add_argument("--sql", required=True)
    p.add_argument("--env", default="DATABASE_WRITE_URL", help="environment variable holding the WRITE connection URL")
    p.add_argument("--environment", default="staging", help="label shown to the approver (staging, production, ...)")
    p.add_argument("--param", action="append", default=[], metavar="NAME=VALUE")
    p.add_argument("--reason", default="")
    p.add_argument("--allowed-functions")
    p.add_argument("--check-only", action="store_true")
    for name in ("approve", "reject", "status", "apply"):
        sp_ = sub.add_parser(name)
        sp_.add_argument("id")
    sub.add_parser("list")
    a = ap.parse_args(argv)
    try:
        return {"propose": cmd_propose, "approve": cmd_approve, "reject": cmd_reject, "status": cmd_status,
                "list": cmd_list, "apply": cmd_apply}[a.cmd](a)
    except Refused as r:
        for reason in r.reasons:
            print(f"refused: {reason}", file=sys.stderr)
        return 2
    except DbError as e:
        print(f"safe_psql_write: {e}", file=sys.stderr)
        return 4
    except UsageError as e:
        print(f"safe_psql_write: {e}", file=sys.stderr)
        return 5


if __name__ == "__main__":
    sys.exit(main())
