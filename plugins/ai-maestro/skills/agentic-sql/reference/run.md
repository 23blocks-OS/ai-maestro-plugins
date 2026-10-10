# `/agentic-sql run <query-id-or-path>`

Execute a saved query (by ID like `Q17`) or a freshly-written one, with the three-layer safety gate.

## Purpose

Make every SQL execution against a production / staging database go through three independent safety layers. Each layer alone has been broken in production (CVE-2025-67644 is a recent text-to-SQL example); together they make the most common accidents impossible.

## When to run

- Every time you would otherwise reach for `psql -c "..."`.
- After `/agentic-sql find` returns an exact-match query and you've supplied the parameters.
- During investigation when you've written a new query and want to validate the AST before executing.

## The three layers

### Layer 1 — Postgres read-only role

A dedicated role (e.g. `{READ_ONLY_ROLE}`) with these grants and nothing else:

```sql
GRANT USAGE ON SCHEMA "<schema>" TO {READ_ONLY_ROLE};
GRANT SELECT ON ALL TABLES IN SCHEMA "<schema>" TO {READ_ONLY_ROLE};
ALTER ROLE {READ_ONLY_ROLE} SET default_transaction_read_only = on;
ALTER ROLE {READ_ONLY_ROLE} SET statement_timeout = '30s';
```

Even if every other layer fails, the DB refuses any write. `default_transaction_read_only` is the belt-and-suspenders catch: any accidental UPDATE/DELETE comes back with `ERROR: cannot execute UPDATE in a read-only transaction`.

### Layer 2 — SQLGlot AST gate

Before psql ever sees the query, parse it with SQLGlot's PostgreSQL dialect, walk the AST, and:

1. **Reject any non-SELECT root node.** No `Update`, `Delete`, `Insert`, `Drop`, `Truncate`, `Alter`, `Create`, `Grant`, `Revoke`, `Vacuum`, `Reindex`, or `Copy` (with TO). Return a clear error: "Skill is read-only; refusing to execute <root_node_type>."
2. **Reject `pg_*` admin function calls** that could exfiltrate or modify state (`pg_terminate_backend`, `pg_cancel_backend`, `pg_read_binary_file`, etc.). Whitelist the introspection functions you actually need (`current_database`, `current_schema`, `version`, etc.).
3. **Validate column references** against `{SCHEMA_DOC_PATH}` if possible. Hallucinated columns get rejected before they hit the DB. (This is a best-effort layer — the schema doc may not be exhaustive — but it catches the obvious cases.)

If any check fails, return the error to the agent for self-healing (rewrite the query, then re-submit). Bird-Interact (arxiv 2510.05318) formalizes this as a "dynamic interaction loop" — feed the error back, let the agent fix, re-validate.

### Layer 3 — LIMIT injection + statement timeout

Wrap every executed query in:

```sql
SET statement_timeout = '30s';
<the query>
LIMIT {MAX_ROWS};  -- only if the query has no LIMIT clause
```

The LIMIT injection prevents an accidental `SELECT * FROM huge_table` from returning gigabytes. Don't inject if the query already has one — the author may have meant the larger result.

Statement timeout makes runaway queries die instead of hanging the connection or saturating the DB.

## Procedure

```
input: query (saved by ID or inline SQL) + parameters dict
output: rows + schema, OR safety-gate rejection with reason

1. resolve(query) → SQL string
   - if id: read from {QUERY_DIR}/<file>.sql, substitute :placeholders with parameters
   - if inline: use as-is
2. parse(SQL) with SQLGlot postgres dialect
   - on parse error: return error to agent for fix
3. ast_gate(parsed)
   - root node must be SELECT or WITH (CTE)
   - no banned function calls
   - on rejection: return reason, agent can rewrite
4. inject_limit(parsed) → SQL'
   - if no LIMIT in outermost SELECT, append LIMIT {MAX_ROWS}
5. connect as {READ_ONLY_ROLE}
6. execute "SET statement_timeout = '30s'; <SQL'>"
7. return rows + column headers
```

## Patterns to follow

- **Show the agent the parametrized SQL before execution.** Don't hide the substitution; let the user verify "yes, look up uid `ae5bda69-...`."
- **Show the agent the AST-gated SQL before execution.** If the gate appended a LIMIT, show it. Transparency builds trust.
- **On rejection, return a STRUCTURED error.** "AST gate rejected: root node is Update, but skill is read-only." Not "error 500." The agent must be able to act on the message.
- **Cap result display at ~50 rows.** Even with the LIMIT injection, dumping 1000 rows into the agent's context is wasteful. Return the count, the first 50, and let the user ask for more.
- **Log every executed query** to a session log (e.g. `.claude/agentic-sql.session.log`) so `/agentic-sql curate` can list them at the end. Include: query ID or "ad-hoc", parametrized SQL, row count, duration.

## Anti-patterns

- **Connecting as the Rails app role / production superuser.** Every layer downstream assumes read-only; if the role can write, you've defeated the model.
- **Skipping the AST gate "because the query is obviously a SELECT."** "Obviously" has been wrong in production. Always parse.
- **Pasting raw user input into the SQL.** Parameters go through the placeholder substitution, which is itself validated. Never `f"SELECT ... WHERE x = {user_input}"`.
- **Returning the full result set to the agent.** Hundreds of rows is a context-budget bomb. Cap display.
- **Suppressing AST errors.** If the gate rejects, surface it. Don't silently fall through to raw execution.

## Example flow

```
agent: /agentic-sql run Q13

skill: Q13 — Email whitespace pollution audit (tenant-wide)
       Reading sql_library/queries/email-whitespace-pollution-audit.sql
       No parameters required. Optional :sample_limit for drilldown.

       Parsing SQL via SQLGlot (postgres dialect)...
       AST root: SELECT — gate passed.
       LIMIT injection: query has GROUP BY, no LIMIT — appending LIMIT 1000.
       Connecting as agentic_sql_ro to zoom_prod.

       Executing:
         SET statement_timeout = '30s';
         SET search_path TO "fff363a5";
         SELECT 'user_identities' AS tbl, ... LIMIT 1000;

       Returned 2 rows in 0.18s.

       tbl              | total_rows | with_whitespace | trailing | leading | tab_or_newline
       -----------------+------------+-----------------+----------+---------+----------------
       user_identities  |  38,100    |     0           |    0     |   0     |     0
       user_profiles    |  38,073    |     0           |    0     |   0     |     0

       (Logged to .claude/agentic-sql.session.log)
```

## On the wrapper script

In a project that adopts this skill, the actual implementation of the three layers belongs in a small wrapper script (e.g. `bin/safe_psql.sh` or a Ruby / Python equivalent) checked into the repo. The skill calls the wrapper; the wrapper does the parse + gate + inject + execute. Keeping the implementation in code (not in the skill's markdown) means:

- The wrapper can be unit-tested.
- The wrapper can be invoked outside the skill (from CI, from a one-off script, from a human in psql).
- The skill stays focused on the WORKFLOW, not the mechanics.

A reference wrapper is in the works as a sibling repo (`agentic-sql-wrapper`) — this skill assumes the wrapper exists and is on the path; it doesn't reimplement it.

## Related

- [reference/find.md](find.md) — the step that hands `run` a query ID
- [reference/add.md](add.md) — save a successful run as a reusable library entry
- [reference/curate.md](curate.md) — uses the session log this command writes
