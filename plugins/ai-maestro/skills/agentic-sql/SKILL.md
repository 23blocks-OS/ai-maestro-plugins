---
name: agentic-sql
description: Run SQL against a production or staging database safely. Check the saved query library first, run only read-only queries (read-only role, SQL check, LIMIT added), and save findings worth keeping back to the library. Use when a task needs data from a real database, such as a customer lookup, a support-ticket investigation or a data audit. Not for sandbox databases or for code that merely builds queries.
allowed-tools: Bash Read Write Edit Glob Grep
compatibility: Needs psql, a read-only Postgres role, and a safe-psql wrapper in the project (set up on first use)
user-invocable: true
argument-hint: "[audit|find|add|run|curate|schema] [target]"
metadata:
  author: 23blocks
  version: 1.0.1
---

## First-Time Setup

On first invocation in a project, the skill auto-extracts these from `CLAUDE.md` if present, then asks for any missing values. Persist them to `.claude/agentic-sql.yml` for the session.

| Variable | Purpose | Example |
|---|---|---|
| `{QUERY_DIR}` | Where saved queries live | `sql_library/queries/` |
| `{INDEX_PATH}` | Markdown index of the library | `sql_library/INDEX.md` |
| `{SCHEMA_DOC_PATH}` | Schema reference doc | `sql_library/SCHEMA.md` |
| `{DB_ENVS}` | Named environments + connection variables | `zoom (ZOOM_DATABASE_URL), files (FILES_DATABASE_URL), …` |
| `{READ_ONLY_ROLE}` | Postgres role with SELECT-only grants the agent connects as | `agentic_sql_ro` |
| `{SAFE_PSQL_WRAPPER}` | Path to the AST-gating wrapper script | `bin/safe_psql.sh` |
| `{MAX_ROWS}` | Default LIMIT injected when query has none | `1000` |

## When to use this skill

- A user reports a support ticket and you need to look up a record.
- An audit / health-check / pre-deploy data sanity check.
- "Why is X showing on the website / inbox / report?" → almost always a DB question.
- A migration / cleanup is being planned and needs a pre-cleanup count + collision check.
- ANY time you would otherwise reach for `psql -c` or a one-off `scripts/audit_*.py`.

Do NOT use this skill for:
- Schema migrations or DDL changes (those are application work, not investigation).
- Production data writes (UPDATE/DELETE/INSERT). Those go in `scripts/` as explicit one-off scripts with dry-run gating, NOT in the library. This skill is read-only by design.
- Application code changes. The skill produces investigation output, not feature work.

## Five Principles

1. **Library-first lookup is mandatory.** Before writing any new SQL, run `/agentic-sql find <topic>` and review the top matches. If a near-match exists, parametrize it instead of writing a new one. The library is worthless if it gets skipped under pressure — and it WILL get skipped if the skill doesn't enforce the check.
2. **Read-only at three layers, all required.** (a) Connect as a Postgres role with only `SELECT` + `USAGE` granted; `default_transaction_read_only = on`. (b) Parse every candidate query with SQLGlot; reject any non-`SELECT` root node before psql sees it. (c) Auto-append `LIMIT {MAX_ROWS}` if missing, plus `SET statement_timeout = '30s'`. Defense in depth — any one layer alone has been broken in production.
3. **The schema doc is the source of truth.** `{SCHEMA_DOC_PATH}` documents tables, key columns, join keys, and gotchas. Read the relevant section BEFORE writing a query — never guess columns. When a new table is touched during an investigation, the section gets added before the query gets saved.
4. **Curation is part of the investigation, not "later."** Before reporting back to the user, decide if any SQL run this session is reusable. If yes, save it via `/agentic-sql add`. Do NOT defer ("I'll add it later"); that's how libraries die. Cemri et al. (arxiv 2503.13657) catalog "diffusion of responsibility" as the #1 multi-agent failure mode — make curation a step in this workflow so no one else owns it.
5. **No field fallbacks.** Never use one column as a substitute for another (`name || alias`, `user_unique_id || entity_unique_id`, etc.) inside a query. Each field has one meaning and one source. If the right field is NULL, that's a data integrity finding to surface, not paper over.

## The investigation workflow

Pseudocode:

```
on user request to investigate X:
  1. /agentic-sql find <topic-from-X>
     → review top 3 matches; pick exact-match, near-miss, or "none found"
  2. if exact match:
       parametrize, run via {SAFE_PSQL_WRAPPER}, report
       go to step 6
  3. if near-miss:
       read the .sql header (purpose, business case, gotchas, schema refs)
       decide: clone+modify, or write new
  4. if write new:
       a. read relevant {SCHEMA_DOC_PATH} sections
       b. draft query with explicit schema (SET search_path TO ...)
       c. validate with {SAFE_PSQL_WRAPPER} dry-run (AST check only, no exec)
       d. run, report
  5. for any meaningfully new query:
       /agentic-sql add → header, parametrize, save to {QUERY_DIR}, update {INDEX_PATH}
  6. report to user; mention which query was used + (if step 5 ran) the new query ID
```

## Sub-Commands

| Verb | Purpose | Reference |
|---|---|---|
| `audit` | Health-check the library: orphan files, missing schema refs, stale queries, env coverage. Run weekly or before any large refactor. | [reference/audit.md](reference/audit.md) |
| `find` | Search `{INDEX_PATH}` for queries matching a topic. THE library-first lookup. | [reference/find.md](reference/find.md) |
| `add` | Guided workflow for adding a new query: header template, schema-ref requirement, save + index update. | [reference/add.md](reference/add.md) |
| `run` | Execute a saved query (by ID) or a freshly-written one, with the 3-layer safety gate. | [reference/run.md](reference/run.md) |
| `curate` | Post-investigation review: surface ad-hoc SQL run this session, promote reusable ones via `add`, archive the rest. The discipline that prevents library decay. | [reference/curate.md](reference/curate.md) |
| `schema` | View or update `{SCHEMA_DOC_PATH}`: add a new table section, document a new column, record a newly-discovered gotcha. | [reference/schema.md](reference/schema.md) |

## Anti-Patterns

These are the failure shapes that motivated this skill. Do not do them.

- **Skipping the library check.** "I'll just write the query quickly" → 10 minutes later you're re-deriving a query that already exists, and your version has a different join key. The library only works if `find` runs first.
- **Pasting the full schema into the prompt.** Six DBs × hundreds of tables × jsonb payloads = your context is gone. Use `/agentic-sql schema <table>` to retrieve only the relevant section.
- **Running raw `psql -c` instead of the wrapper.** The 3-layer safety model exists because each layer has been broken in production (CVE-2025-67644 is a recent text-to-SQL example). Always go through `{SAFE_PSQL_WRAPPER}`.
- **"I'll save the query later."** No, you won't. End-of-session curation is the failure mode that motivated the entire skill. Save it now or it dies.
- **Writing UPDATE/DELETE/INSERT through this skill.** Destructive operations belong in `scripts/` as explicit one-off scripts with dry-run gating, NOT in the read-only investigation library.
- **Treating the index file as a separate artifact.** Adding a query without updating `{INDEX_PATH}` makes it unreachable for the next `find`. The two changes ship together or neither ships.
- **Guessing columns.** If the column isn't in `{SCHEMA_DOC_PATH}`, look at the actual schema (`information_schema.columns`) and ADD it to the doc before you use it in a query. Memory beats re-derivation every time.

## Implementation reference

The patterns behind these principles, with primary sources, are documented in:
- [`reference/schema.md`](reference/schema.md) — schema-as-RAG (AutoLink arxiv 2511.17190, LinkAlign arxiv 2503.18596)
- [`reference/find.md`](reference/find.md) — query-library retrieval (Vanna AI pattern)
- [`reference/run.md`](reference/run.md) — three-layer safety (SQLGlot AST gate, Postgres role isolation, LIMIT injection)
- [`reference/curate.md`](reference/curate.md) — post-investigation curation (Cemri et al. arxiv 2503.13657 on multi-agent failure modes)
