# `/agentic-sql add`

Guided workflow for saving a new query to the library after it has proven its worth.

## Purpose

Take a freshly-written-and-executed SQL query and turn it into a library entry: standard header, parametrized, schema-referenced, indexed, ready for the next person to find via `/agentic-sql find`.

## When to run

- After `/agentic-sql run` on a new query produced useful results AND the pattern is likely to recur.
- During `/agentic-sql curate` when reviewing ad-hoc SQL from the session and deciding what to promote.
- NOT before running the query — only save things that actually worked.

## Procedure

1. **Confirm reusability.** Before formalizing, the agent should be able to answer: "When would someone else want to run this?" If the answer is "this exact incident only," do NOT save it — it belongs as a one-off note in the support ticket, not in the library. Reusable queries describe a PATTERN ("find any project by name", "audit any field for whitespace pollution"), not an INCIDENT.

2. **Get the next query ID.** Read `{INDEX_PATH}`, find the highest existing `QNN` number, increment by 1. Example: if highest is `Q16`, next is `Q17`.

3. **Pick a kebab-case file name.** Should be 3-6 words describing the query's purpose. Examples that work:
   - `pcu-conversation-coverage-by-project.sql`
   - `email-whitespace-pollution-audit.sql`
   - `handler-minors-with-pcus.sql`

   Examples that don't:
   - `query1.sql` (no semantic content)
   - `find-the-thing.sql` (too vague)
   - `audit-email-whitespace-pollution-in-user-identities-and-profiles.sql` (overlong)

4. **Format the header.** Every query MUST start with this exact section structure, as a SQL comment block:

```sql
-- Q17 — <One-line title>
--
-- Purpose: <What the query does, mechanically. 1-2 sentences max.>
-- Business case: <When/why someone runs this. Tie to a real incident or recurring
--                support ticket pattern if possible.>
-- Environment: <env tag(s) from the Environments table, e.g. "zoom" or "zoom + conv">
-- Schema reference: ../SCHEMA.md#<section-anchor> (tables touched)
-- Parameters:
--   :param_name   <type>   <one-line description>
--
-- Gotchas:
--   - <Any known trap. Leading-space discriminators, denormalized counters that
--     drift, mixed-case email semantics, etc.>
--   - <Another one if applicable.>
```

   Then a blank line, then the SQL itself.

5. **Parametrize the query.** Replace every literal value the user supplied with a `:placeholder`. Example: `WHERE unique_id = 'ae5bda69-...'` becomes `WHERE unique_id = ':project_unique_id'`. The placeholders should match the Parameters section of the header.

6. **Add an explicit `SET search_path TO "<schema>";`** at the top of the SQL body. Even if the connection defaults to that schema, make the dependency explicit so the query is portable.

7. **If the query touches a table not yet in `{SCHEMA_DOC_PATH}`:** STOP. Run `/agentic-sql schema <table>` first to add the table to the schema doc. The `Schema reference:` line in the header MUST link to an existing section. Save the query AFTER the schema doc is updated.

8. **Save the file** to `{QUERY_DIR}/<kebab-case-name>.sql`.

9. **Update `{INDEX_PATH}`.** Add a row to the query index table with:
   - Query ID (`Q17`)
   - Purpose (one line, paraphrased from the header)
   - Environments (env tag from the header)
   - File link (relative path to the new `.sql`)

   Update the "Recent additions" section at the bottom with a one-line note dated today, naming the incident or ticket that motivated the query.

10. **Commit + (optionally) push.** The index file and the query file ship together. Do NOT commit one without the other — an unindexed query is unreachable.

## Patterns to follow

- **Headers describe the WHY, not the WHAT.** "Purpose: counts PCUs vs contexts" is what the code does; "Business case: customer reports no conversations are being created, run this on a sample to discriminate one-project bug from tenant-wide regression" is why someone reaches for it. Future-you wants the business case.
- **Gotchas earn their weight.** Every project has known traps (leading-space source_type, denormalized counters, NULL vs blank semantics). Capture them as you discover them. If you ever caught a bug AFTER running a query because of a column quirk, write that quirk into the Gotchas of the next query that uses the column.
- **Schema reference is non-negotiable.** No exceptions. If the table isn't documented, document it FIRST.

## Anti-patterns

- **"I'll add the header later."** No. Save the file with no header or with a stub header, and the library is already polluted.
- **Skipping parametrization.** A query with `'1070020564'` hardcoded as a Cédula number can't be reused. Replace with `:identity_number`.
- **Saving incident-specific queries.** "All PCUs created on 2026-05-14 between 14:00 and 18:00 UTC for project XYZ" is a one-off investigation, not a library entry. The reusable shape is the BROADER pattern (group PCUs by hour for a project window); save that instead.
- **Saving without updating the index.** An unindexed query is invisible to `find`. The two changes are atomic.
- **Long-winded headers.** Two paragraphs is too much. The header is a hand-off note, not a treatise.

## Example flow

```
agent: /agentic-sql add

skill: What's the query's purpose? (one sentence)
user:  Count PCUs vs conversation contexts for a list of project UUIDs

skill: Business case? (when does someone run this?)
user:  Customer reports "no conversations are being created on project X."
       Run this on a sample of recent + older projects to size the gap and
       discriminate "this one project is broken" from "tenant-wide regression."

skill: Which environments?
user:  zoom + conv (two DBs)

skill: Tables touched (will check SCHEMA.md):
       - zoom.project_character_users        [documented ✓]
       - conv.context                        [documented ✓]

skill: Any gotchas the next person should know?
user:  source_type must use LIKE '%PCU%' to catch both 'PCU' and ' PCU' (leading
       space, admin's legacy writer). projects.total_pcus is denormalized — trust
       COUNT(*) from project_character_users.

skill: Suggested file name: pcu-conversation-coverage-by-project.sql
       Suggested ID:        Q17
       OK?
user:  yes

skill: [writes file with formatted header + parametrized SQL]
       [updates INDEX.md with new row + Recent additions note]
       Saved sql_library/queries/pcu-conversation-coverage-by-project.sql as Q17.
       Ready to commit.
```

## Related

- [reference/find.md](find.md) — the lookup this query will be discoverable from
- [reference/schema.md](schema.md) — required before saving a query that touches an undocumented table
- [reference/curate.md](curate.md) — the workflow that triggers `add` for ad-hoc queries
