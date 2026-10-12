# `/agentic-sql write <what to change>`

## Contents

- When to use it
- One-time setup
- The flow
- What the person sees
- Refusals and exit codes
- What this does not protect against

## When to use it

A support case or a data fix needs a row changed: set a plan, correct an email, add a note, mark rows reviewed. The read door (`safe-psql`) cannot do this and never will. This door can, with a person approving each change. If no settings file exists, nothing is writable and every request is refused.

## One-time setup

1. **A settings file** lists what may change. Copy `examples/write.example.yaml` to `.safe-psql/write.yaml` in the project (or `~/.safe-psql/write.yaml`) and edit it. Tables and columns not listed cannot change. `allow_hard_delete` is `false` unless the person who sets this up turns it on, and a table also needs `delete: true`.
2. **A separate write login.** Never the read login. It must not be a superuser, and it may write only the tables in the settings file. Example:

```sql
CREATE ROLE agentic_sql_rw LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB CONNECTION LIMIT 5 PASSWORD '...';
GRANT CONNECT ON DATABASE app TO agentic_sql_rw;
GRANT USAGE ON SCHEMA public TO agentic_sql_rw;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO agentic_sql_rw;        -- needed to evaluate WHERE
GRANT UPDATE (plan, email) ON customers TO agentic_sql_rw;            -- column-level is best
GRANT INSERT, UPDATE, DELETE ON notes TO agentic_sql_rw;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO agentic_sql_rw;      -- for inserts into serial/identity columns
ALTER ROLE agentic_sql_rw SET statement_timeout = '30s';
ALTER ROLE agentic_sql_rw SET lock_timeout = '5s';
ALTER ROLE agentic_sql_rw SET idle_in_transaction_session_timeout = '60s';
```

3. **Keep the write URL out of files and command lines.** Put it in an environment variable such as `ACME_WRITE_URL`, ideally from the `aim-secret-management` skill (`aim-secret exec --use ACME_WRITE_URL -- <command>`).

The write command refuses to run if the login is a superuser (or can create roles or databases, or bypass row security), belongs to a powerful built-in role, can write any table not in the settings file, or cannot write at all. The read command refuses a login that can write. So the two logins cannot be swapped by mistake.

## The flow

Four steps. Step 3 is only ever done by a person.

```
1. propose   safe-psql-write propose --env ACME_WRITE_URL --environment staging \
               --sql "UPDATE customers SET plan = :p WHERE id = :id" --param p=pro --param id=7 \
               --reason "support case S012"
2. (agent)   Tell the person: which table, how many rows, why, and the request id. Then wait.
3. approve   The PERSON runs  safe-psql-write approve w-1a2b3c4d5e6f  in their own terminal window.
4. apply     safe-psql-write apply w-1a2b3c4d5e6f
```

`propose` checks the statement against the settings, runs it inside a transaction, records how many rows it touched and the before and after, rolls everything back, and stores a request. **Nothing has changed after `propose`.** Its output has counts and column names only, never values. Values go in with `--param`, never into the SQL text.

`apply` re-checks that the request is exactly what was approved, runs it in a transaction, and rolls back if the number of rows differs from the dry run. A request works once.

Other commands: `status <id>`, `reject <id>`, `list`. `--check-only` on `propose` prints the checked SQL without touching a database.

Approval can also come from the AI Maestro chat card or a Claude Code card when those are set up; the terminal is the one that always works.

## What the person sees

```
Request w-1a2b3c4d5e6f from agent 'support-bot'
  environment : production
  statement   : UPDATE on public.customers, 1 row(s), limit 25
  SQL         : UPDATE public.customers SET plan = %(p)s WHERE id = %(id)s
  values      : {"p": "pro", "id": "7"}
  reason      : support case S012
  what changes:
    row (key [7]): plan: 'free' -> 'pro'

Type 'production' to approve, anything else rejects:
```

Staging asks for `yes`. Production (and `prod`) asks for the environment name. The answer is read from the real terminal, so a command run by an agent, or piped input, cannot answer. Inside an agent session (Claude Code, AI Maestro, Codex) `approve` refuses even with a terminal: open a separate terminal window.

## Refusals and exit codes

| Code | Meaning |
|---|---|
| 0 | Done |
| 2 | Refused by the rules or settings. The reasons are printed. Do not retry with a wider statement |
| 3 | The database login is not safe for this door |
| 4 | Connection or query error |
| 5 | Usage error |
| 6 | Approval missing, wrong, expired or already used |
| 7 | The row count changed since the dry run. Rolled back. Propose again |

The rules in short: one statement; `INSERT` or `UPDATE`, and `DELETE` only when allowed; `UPDATE` and `DELETE` need a `WHERE`; only listed tables and columns; no `RETURNING`, `UPDATE ... FROM`, `DELETE ... USING` or `ON CONFLICT DO UPDATE`; no writes inside `WITH`; functions on the allow-list only; more than the row limit is refused.

## What this does not protect against

- A wrong change that a person approves. The before and after are shown so it is visible, but it is still their decision.
- Triggers and side effects in the database. The dry run runs them too and rolls them back, but they can take locks or call out. List only tables whose triggers you know.
- Someone who deliberately works around the tool. The agent and the person share one user account, so this stops an agent using the sanctioned path (including one steered by text in a customer report), not a determined attacker on the same machine. The write login's own limits are the real backstop.
- Sequence numbers. A dry run that inserts uses up a sequence value even though the row is rolled back.
