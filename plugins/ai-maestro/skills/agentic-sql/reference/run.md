# `/agentic-sql run <query-id-or-path>`

Execute a saved query (by ID like `Q17`) or a freshly-written one through the SQL gate.

## Contents

- Purpose
- When to run
- The SQL gate (layers 1-3)
- The wrapper: scripts/safe_psql.py
- Procedure
- Patterns to follow
- Anti-patterns
- Example flow

## Purpose

Every SQL execution against a production or staging database goes through the SQL gate: a read-only role, a parser that allows one plain SELECT, and a row limit plus timeouts. Each layer alone has been bypassed. Read-only transactions alone have been bypassed: Anthropic's archived reference Postgres MCP server accepted multiple statements, so `COMMIT; <write>` in one string ended the read-only transaction (Datadog Security Labs, 2025-08-21, https://securitylabs.datadoghq.com/articles/mcp-vulnerability-case-study-SQL-injection-in-the-postgresql-mcp-server/). Together the layers make the common accidents impossible.

## When to run

- Every time you would otherwise reach for `psql -c "..."`.
- After `/agentic-sql find` returns an exact-match query and you have supplied the parameters.
- During investigation, in dry-run mode (parse and gate only, no execution), to validate a new query.

## The SQL gate

### Layer 1: the read-only role

The guard is a role with no write grants. Create it once per database:

```sql
CREATE ROLE {READ_ONLY_ROLE} LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB
  CONNECTION LIMIT 5;
GRANT CONNECT ON DATABASE "<database>" TO {READ_ONLY_ROLE};
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA "<schema>" TO {READ_ONLY_ROLE};
GRANT SELECT ON ALL TABLES IN SCHEMA "<schema>" TO {READ_ONLY_ROLE};
ALTER DEFAULT PRIVILEGES IN SCHEMA "<schema>" GRANT SELECT ON TABLES TO {READ_ONLY_ROLE};

ALTER ROLE {READ_ONLY_ROLE} SET statement_timeout = '{STATEMENT_TIMEOUT}';
ALTER ROLE {READ_ONLY_ROLE} SET lock_timeout = '5s';
ALTER ROLE {READ_ONLY_ROLE} SET idle_in_transaction_session_timeout = '30s';
```

- `ALTER DEFAULT PRIVILEGES` runs as the role that creates the tables (add `FOR ROLE <owner>` if that is not you), so new tables are covered.
- Do not rely on `default_transaction_read_only` or `SET TRANSACTION READ ONLY`: a session can change them. The guard is a role with no write grants (https://www.postgresql.org/docs/current/sql-set-transaction.html).
- Shortcut on PostgreSQL 14+: `GRANT pg_read_all_data TO {READ_ONLY_ROLE};` replaces the per-schema grants. Caveat: it bypasses row-level security on every table (https://www.postgresql.org/docs/current/predefined-roles.html), so skip it when RLS separates tenants.
- Never grant `pg_read_server_files`, `pg_write_server_files` or `pg_execute_server_program`.

### Layer 2: the parser (allow-list)

Before psql sees the query, parse it with SQLGlot using the `postgres` dialect and apply an allow-list:

1. **Exactly one statement per call.** Reject any input that parses to more than one statement, or that contains a trailing or embedded semicolon-separated statement.
2. **The root must be SELECT** (a `WITH ... SELECT` counts; its root is still the SELECT).
3. **Walk the whole tree** and reject, anywhere in it: INSERT, UPDATE, DELETE, MERGE; CREATE, ALTER, DROP, TRUNCATE, GRANT, REVOKE; SELECT INTO; locking clauses (`FOR UPDATE`, `FOR SHARE`); COPY; SET, RESET, DO, CALL; transaction control (BEGIN, COMMIT, ROLLBACK); and `EXPLAIN ANALYZE` of anything but a SELECT.
4. **Reject every function call that is not on the function allow-list** kept in the project. Compare names after removing quotes and ignoring schema qualification, so `"pg_catalog"."Pg_Read_File"(...)` and `pg_read_file(...)` are the same name.

Why an allow-list and not a deny-list of functions: Postgres has too many functions that read files, kill sessions or change state, and new ones ship with each release. Examples of what the allow-list keeps out: `pg_terminate_backend`, `pg_cancel_backend`, `pg_read_file`, `pg_read_binary_file`, `dblink*`, `lo_import`, `lo_export`, `set_config`, `nextval`, `setval`, `query_to_xml`.

**Quality check (not a safety layer):** validate column references against `{SCHEMA_DOC_PATH}` where possible. Hallucinated columns get rejected before they hit the DB. The schema doc may not be exhaustive, so this only catches the obvious cases.

On any rejection, return the reason to the agent so it can rewrite the query and re-submit.

### Layer 3: LIMIT, timeouts, one statement per round trip

- Send ONE statement per round trip. Never prefix the query with a `SET`.
- Timeouts live on the role (layer 1), so they apply to every connection without extra statements.
- Open a fresh connection per query, so no session state survives between queries.
- Inject `LIMIT {MAX_ROWS}` on the outermost SELECT when it has none. Do not inject when the author wrote one; they may have meant the larger result.

## The wrapper: `scripts/safe_psql.py`

The skill ships a wrapper that does everything below. Usage:

```bash
export ACME_DATABASE_URL=...   # or: aim-secret exec --use ACME_DATABASE_URL -- <command>
python3 scripts/safe_psql.py --env ACME_DATABASE_URL --query-id Q12 \
  --sql "SELECT id, email FROM users WHERE id = :id" --param id=7
python3 scripts/safe_psql.py --check-only --sql "..."   # gate only, no database
```

Exit codes: 0 ok, 2 refused by the gate (reasons on stderr), 3 the role is not safe, 4 connection or query error, 5 usage error. Extra allowed functions go in a file passed with `--allowed-functions` (one name per line); the default list covers counting, text, dates, JSON, windows and `generate_series`. The wrapper also:

- sends the statement it regenerated from the checked tree, never your original text;
- binds `:name` parameters on the server, so values are never spliced into the SQL;
- refuses to run as a superuser, or a role with bypassrls, createrole, createdb or membership in `pg_write_all_data`, `pg_read_server_files`, `pg_write_server_files`, `pg_execute_server_program`, `pg_signal_backend`;
- never prints the connection URL, and with `--log` writes only the query id, parameter names, row count and duration.

A different wrapper must keep this behavior:

- Parse and gate the SQL as in layer 2, and support a dry-run mode that stops after the gate.
- Inject the LIMIT as in layer 3.
- Connect as `{READ_ONLY_ROLE}`, with a connection string taken from an environment variable, one fresh connection per query.
- Send the gated statement alone, and print the final SQL and a structured rejection reason when it refuses.
- Live in the repository as code, so it can be unit-tested and called from CI or by a human. The skill stays focused on the workflow.

## Procedure

```
input: query (saved by ID or inline SQL) + parameters dict
output: rows + column headers, OR a gate rejection with reason

1. resolve(query) -> SQL string
   - if id: read from {QUERY_DIR}/<file>.sql, substitute :placeholders with parameters
   - if inline: use as-is
2. parse(SQL) with SQLGlot postgres dialect
   - on parse error: return error to agent for fix
3. gate(parsed): one statement, root SELECT, whole-tree check, function allow-list
   - on rejection: return reason, agent can rewrite
4. inject_limit(parsed) -> SQL'
   - if no LIMIT in outermost SELECT, append LIMIT {MAX_ROWS}
5. open a fresh connection as {READ_ONLY_ROLE}
6. execute SQL' as the only statement of the round trip
7. return rows + column headers
```

## Patterns to follow

- **Show the agent the parametrized SQL before execution.** Do not hide the substitution; let the user verify "yes, look up uid `00000000-0000-0000-0000-000000000000`."
- **Show the gated SQL before execution.** If the gate appended a LIMIT, show it.
- **On rejection, return a structured error.** "SQL gate rejected: root node is Update, but the skill is read-only." Not "error 500."
- **Cap result display at {DISPLAY_ROWS} rows.** Even with the LIMIT injection, dumping {MAX_ROWS} rows into the agent's context is wasteful. Return the count, the first {DISPLAY_ROWS}, and let the user ask for more.
- **Log every executed query** to a session log (e.g. `.claude/agentic-sql.session.log`) so `/agentic-sql curate` can list them. Log only query ID or "ad-hoc", parameter names (not values), row count and duration. Never log result rows.

## Anti-patterns

- **Connecting as the application role or a superuser.** Every layer assumes read-only; if the role can write, the model is defeated.
- **Skipping the gate "because the query is obviously a SELECT."** "Obviously" has been wrong in production. Always parse.
- **Pasting raw user input into the SQL.** Parameters go through the placeholder substitution. Never `f"SELECT ... WHERE x = {user_input}"`.
- **Returning the full result set to the agent.** Cap display.
- **Suppressing gate errors.** If the gate rejects, surface it. Never fall through to raw execution.
- **Prefixing the query with `SET ...;` in one string.** That is the multi-statement shape the gate exists to reject. Set timeouts on the role.

## Example flow

```
agent: /agentic-sql run Q13

skill: Q13 — Email whitespace pollution audit (tenant-wide)
       Reading sql_library/queries/email-whitespace-pollution-audit.sql
       No parameters required. Optional :sample_limit for drilldown.

       Environment: acme_prod (production). No read replica configured.
       Parsing SQL via SQLGlot (postgres dialect)...
       One statement, root SELECT, no banned nodes, functions on the allow-list: gate passed.
       LIMIT injection: query has GROUP BY, no LIMIT — appending LIMIT 1000.
       Connecting as agentic_sql_ro to acme_prod (fresh connection).

       Executing (single statement):
         SELECT 'user_identities' AS tbl, ... LIMIT 1000;

       Returned 2 rows in 0.18s.

       tbl              | total_rows | with_whitespace | trailing | leading | tab_or_newline
       -----------------+------------+-----------------+----------+---------+----------------
       user_identities  |  38,100    |     0           |    0     |   0     |     0
       user_profiles    |  38,073    |     0           |    0     |   0     |     0

       (Logged to .claude/agentic-sql.session.log: Q13, no params, 2 rows, 0.18s)
```
