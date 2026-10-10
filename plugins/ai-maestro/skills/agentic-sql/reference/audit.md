# `/agentic-sql audit`

Health-check the library. Run weekly, or before any large refactor.

## Contents

- Purpose
- When to run
- Procedure
- Output shape
- Patterns to follow
- Anti-patterns
- Implementation hints

## Purpose

Surface library decay before it bites: orphan files, missing schema references, stale queries, env-coverage gaps, broken anchors. Not a destructive command — `audit` reports, the human decides what to fix.

## When to run

- On a weekly cadence as a hygiene pass.
- After a large incident that spawned new queries — verify they were properly indexed.
- Before a refactor of the library, schema doc, or DB structure.
- After install of the skill in a new project — sanity check the starting state.

## Procedure

```
1. read {INDEX_PATH} — parse the query table, capture all referenced .sql paths
2. list {QUERY_DIR} — capture all actual .sql files
3. compute:
   - orphan_files = files in {QUERY_DIR} not in {INDEX_PATH}
   - missing_files = paths in {INDEX_PATH} that don't exist on disk
   - duplicates = INDEX rows where two queries claim the same purpose
4. for each .sql file:
   - parse header
   - check for required fields: Purpose, Business case, Environment, Schema reference, Parameters
   - check Schema reference link resolves to a real anchor in {SCHEMA_DOC_PATH}
   - capture last-modified date
5. compute env coverage:
   - count queries per environment tag
   - flag envs with 0 queries (gap)
   - flag envs with > 50% of total queries (concentration risk)
6. compute staleness:
   - queries with last-modified > 90 days ago AND not referenced in any session log from the last 90 days
7. report a structured summary
```

## Output shape

```
SQL Library Audit — sql_library/

OVERVIEW
  Total queries in INDEX:       16
  Total .sql files on disk:     16
  Orphan files (on disk, not in INDEX):    0
  Missing files (in INDEX, not on disk):   0
  Duplicate purposes flagged:              0

HEADER COMPLIANCE
  Queries with full header:     16 / 16  ✓
  Schema references resolved:   16 / 16  ✓
  Anchors found in SCHEMA.md:   15 / 16  — Q11 references a section that has been renamed

ENVIRONMENT COVERAGE
  acme:            12 queries
  acme + search:    1
  acme + conv:      1
  acme + gateway:   1
  search + acme:    1
  conv:             1   (only Q06)
  files:            1
  gateway:          1

  No queries cover:  crm   ← consider seeding from common CRM patterns

STALENESS
  Queries unmodified > 90 days:   11 / 16
  Of those, never referenced in session logs:  3
    - Q07 (magic-link-by-token)         — last touched 2026-05-20
    - Q09 (forged-document-number-audit) — last touched 2026-05-20
    - Q11 (test-account-by-role)        — last touched 2026-05-20
  (Cold queries aren't bad — they're insurance. Just confirm they still describe
   the current schema reality.)

RECOMMENDED ACTIONS
  - Fix Q11's Schema reference anchor (renamed)
  - Consider seeding 1-2 CRM queries to close env-coverage gap
  - Verify Q07 / Q09 / Q11 still match current schema; if not, refresh
```

## Patterns to follow

- **Report counts, not opinions.** Audit surfaces facts ("11 queries unmodified > 90 days") and lets the human decide ("is that fine, or should we refresh?"). Don't editorialize.
- **Specifically check the cross-link integrity.** `Schema reference: ../SCHEMA.md#xxx` lines that point at non-existent anchors are the most common silent rot. Catch them.
- **Flag concentration but don't alarm.** If 75% of queries are against one environment, that may just reflect where the investigations happen — not a problem. Show the percentage, let the human judge.
- **Use a session-log heuristic for staleness.** A query untouched on disk for 90 days but used in last week's investigation is fresh. A query untouched for 90 days AND never used in any session log is a candidate for review.

## Anti-patterns

- **Auto-deleting orphans.** Audit is read-only. If a file is orphaned (in `queries/` but not in `INDEX.md`), report it and let the human decide whether to delete or index it. Auto-delete is how teams lose work.
- **Flagging every cold query as "stale."** Cold doesn't mean stale. Some queries are insurance — rarely run, critical when needed (e.g. `forged-document-number-audit`). Use the combined "cold + never referenced" heuristic.
- **Auditing the schema doc separately.** The audit should cross-check the link integrity between queries and schema sections. A query's schema reference is half the value; a broken link is a real bug.
- **Treating the audit as a checklist that "passes" or "fails."** It's a state summary, not a CI gate. There's no single number that defines "library health."

## Implementation hints

The audit is mostly file I/O and string parsing — keep it in the wrapper script (or a small Python / Ruby helper) called from the skill. No DB connection required for the basic audit; only the staleness check might benefit from cross-referencing the session log file.
