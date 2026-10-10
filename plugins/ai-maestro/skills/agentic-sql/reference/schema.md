# `/agentic-sql schema <table-or-section>`

View or update the schema reference doc.

## Contents

- Purpose
- When to run
- What the schema doc captures
- Procedure (read mode)
- Procedure (write mode: add new table)
- Procedure (write mode: update gotcha)
- Patterns to follow
- Anti-patterns
- Example flow (read)
- Example flow (add)

## Purpose

`{SCHEMA_DOC_PATH}` is the source of truth for which tables exist, what columns they have, how to join across databases, and what gotchas you'd never derive from a `\d table` in psql. Every saved library query links to it via the `Schema reference:` header line.

This command is the read AND write interface for that doc:

- **Read mode** (default): surface the section(s) relevant to a topic. Retrieve only what the agent needs, never paste the whole catalog.
- **Write mode** (`--add` or `--update`): add a new table section or update an existing one when an investigation surfaces something new.

## When to run

- Before writing any new SQL: read the relevant sections to ground the query in real columns / join keys.
- When `/agentic-sql add` flags that a query touches an undocumented table: STOP and document the table first.
- When an investigation surfaces a previously-unknown gotcha (denormalized counter drift, leading-space discriminator, NULL semantics, name field that desyncs from another field): record it before it's forgotten.
- Periodically as part of `/agentic-sql audit` follow-up.

## What the schema doc captures

For each table, the doc records:

- **Canonical purpose** (one line — "the junction table between projects/characters and talents")
- **Key columns** — not all of them, just the ones queries reach for. Each with:
  - Name + type
  - Semantic meaning ("This is the talent's Gateway-canonical UUID, not the local one")
  - Cross-block join role if applicable ("=== Search `entity_identities.entity_unique_id`")
  - Known traps (denormalized, snapshot, leading-space, drifts under X)
- **Status / enabled / type fields** with their allowed value sets
- **FK conventions** (especially across tables in the same DB)

For each cross-block join key:

- Which identifier
- Where it lives (table.column in each block)
- What it joins to
- Whether it's stable forever, regenerated per tenant, etc.

For each environment:

- DB name + host + default schema name
- Connection variable in `.env`
- Quirks (apartment gem multi-tenancy, schema-per-block, etc.)

## Procedure (read mode)

```
input: topic (table name, or freeform "I'm investigating X")

1. parse topic → candidate table names
2. grep {SCHEMA_DOC_PATH} for matching section anchors
3. return the matched section(s) verbatim, including:
   - the table's column listing
   - any cross-block join rules that reference its columns
   - the relevant env's connection info
4. if no match: return "no documented section for <X>" and suggest /agentic-sql schema --add
```

## Procedure (write mode: add new table)

```
input: table name, environment

1. connect to {READ_ONLY_ROLE} on the target DB
2. run information_schema.columns for the table; capture columns + types
3. ask the agent (or user) to annotate:
   - which columns are the "key" ones queries reach for
   - any gotchas observable from current data or known incidents
   - any cross-block join role (uses an ID that matches another block's column?)
4. format as a section under the right env header in {SCHEMA_DOC_PATH}
5. if cross-block join discovered: also update the "Cross-environment join rules" table
6. write the file, show the diff
```

## Procedure (write mode: update gotcha)

```
input: table.column, gotcha text

1. locate the section in {SCHEMA_DOC_PATH}
2. append the gotcha as a bullet under the column or in the section's "Gotchas" subsection
3. surface examples if the agent has them (a past incident, an INDEX.md query that hit this trap)
4. write the file, show the diff
```

## Patterns to follow

- **Sections describe how the table IS USED, not just what columns it has.** A `\d` from psql gives you syntax; the schema doc gives you semantics. The bar for "worth recording" is: would the next person be misled without this note?
- **Cross-block join rules are CRITICAL.** Get one wrong and the resulting query produces silently bad data. These get their own section at the top of the doc and a link from every relevant table.
- **Gotchas come from real incidents.** "This counter drifts under condition X" is worth recording because something broke once that way. "This column might be NULL" is not worth recording unless there's a specific code path that breaks on NULL.
- **Use stable anchors.** Each section gets a markdown anchor (e.g. `#### project-character-users-pcus`) that the `Schema reference:` line in queries links to. Don't rename anchors casually — they're referenced from `.sql` headers.

## Anti-patterns

- **Dumping the entire schema.** This is the failure mode the skill exists to prevent. The doc is curated, not exhaustive. Columns that no library query references don't need to be in the doc.
- **Stale gotchas.** If a gotcha is fixed (the denormalized counter is now reliable, the leading-space discriminator was removed), update the doc — don't leave the trap warning lying around to scare future readers.
- **Schema doc updates that happen "later".** Same anti-pattern as curate. If the investigation touched a new table, document the table NOW or it never gets done.
- **Writing the schema doc as a static reference without business context.** A column listing is worth less than half of what the doc should provide. The institutional knowledge ("this field is set by service Y at event Z and not by anyone else") is what makes the doc indispensable.

## Example flow (read)

```
agent: /agentic-sql schema project_character_users

skill: ## acme — project_character_users (PCUs)
       The junction table between projects/characters and talents.

       - unique_id (uuid) — canonical PCU ID. Also reused as the context.unique_id
         on the Conversations block for the PCU's chat thread.
       - id (bigint) — numeric ID. Used as project_character_user_id FK on
         pcu_notes / pcu_tests / pcu_precontracts / pcu_comments / pcu_contracts.
       - user_unique_id (uuid) — the talent
       - project_unique_id (uuid)
       - character_unique_id (uuid)
       - status (varchar) — pending / saved / selected / rejected / preselection
       - batch_unique_id, batch_label, batch_status, batch_date — populated when
         the PCU is added to a batch send. NOT set at PCU creation; the join
         column does not represent a creation-path discriminator.
       - user_name, user_avatar_url, character_summary, project_summary —
         denormalized snapshots from the related rows at PCU-create time.
         CAN DRIFT from the source (e.g. user_identity.name edited after the
         PCU was created → snapshot stale).

       Cross-block join: PCU.unique_id === conv.context.unique_id (for the
       chat thread wrapping the PCU). See "Cross-environment join rules" at
       top of doc.

       Queries that reference this section:
         Q03 (pcus-on-character)
         Q12 (pcu-conversation-coverage-by-project)
         Q14 (email-collision-groups-for-triage)
         Q16 (handler-minors-with-pcus)
```

## Example flow (add)

```
agent: /agentic-sql schema --add company_features

skill: Connecting to acme as agentic_sql_ro to introspect...

       Columns from information_schema:
         id, unique_id, company_unique_id, feature_name, enabled, created_at,
         updated_at, payload

       Suggested section format:

         #### company_features
         Per-company feature flags.
         - unique_id (uuid)
         - company_unique_id (uuid) — FK to companies.unique_id
         - feature_name (varchar) — e.g. 'new_inbox', 'precontract_v2'
         - enabled (varchar 'true'/'false' — NOT boolean)
         - payload (jsonb) — feature-specific config

       Any gotchas to record? (past incidents, known traps)
user:   `enabled` is varchar 'true'/'false', not boolean — same as elsewhere in
        this schema. Don't use `WHERE enabled = TRUE`.

skill: [writes section to {SCHEMA_DOC_PATH}, shows diff]
```
