# `/agentic-sql find <topic>`

The library-first lookup. Run this BEFORE writing any new SQL.

## Purpose

Surface saved queries whose purpose, business case, or table coverage matches the topic the user just asked about. Returns ranked matches with their schema references and parameters so the agent can decide: exact match (just parametrize and run), near miss (clone and modify), or true gap (write new + save).

## When to run

Always, before writing any new SQL. No exceptions. The library is the cheap path; re-deriving is the expensive one.

## Procedure

1. **Read `{INDEX_PATH}`.** It's a markdown table — purpose / business case / environment / file path per row. Parse it.
2. **Tokenize the user's topic.** Strip stopwords, lemmatize. "Find Jane Doe's email and see if there's whitespace" → tokens: `email, whitespace, lookup`.
3. **Score each row.** Match topic tokens against (a) the Purpose column, (b) the Business case column, (c) the file name. Boost matches on table names mentioned in the topic if the schema doc lists which tables each query touches.
4. **Return top 5 ranked matches.** Each result includes:
   - Query ID (e.g. `Q12`)
   - File path
   - One-line purpose
   - Schema sections it references (from the `Schema reference:` header line)
   - Required parameters (from the `Parameters:` header section)
   - Match score and which fields contributed
5. **Format the recommendation as a decision matrix:**
   - **Exact match (score ≥ 0.8):** Parametrize + run. No new query needed.
   - **Near miss (score 0.5-0.8):** Open the file, read header gotchas, decide clone-and-modify or write fresh.
   - **No match (score < 0.5):** Write new. Note this gap; it's a candidate for `/agentic-sql add` after the investigation succeeds.

## Patterns to follow

- **Surface the top 3 by default.** More than that is noise; the agent should drill in on the obvious leader.
- **Always show the `Schema reference:` line** for each result. Knowing which tables a query touches is half the disambiguation.
- **Show parameters as a checklist.** If the user's topic doesn't include a value for one of them, prompt: "This query needs `:talent_unique_id` — do you have a UUID, or do I look one up first?"
- **Be explicit when no match is found.** Don't hallucinate adjacency. "No queries in the library match X" is a valid output — it triggers `add` after the investigation.

## Anti-patterns

- **Don't just grep for one keyword.** Score across multiple fields with weights. Pure grep produces false positives and misses near-matches that use different vocabulary.
- **Don't skip this step "because you already know the query."** You may know an ad-hoc query you wrote before; `find` checks whether a more canonical version exists in the library that someone else added since.
- **Don't return more than 5 matches.** If 5 isn't enough, the topic is too broad — ask the user to narrow.
- **Don't run a returned query without showing the user which one you picked.** Transparency in the lookup is what builds trust in the discipline.

## Example output shape

```
Found 3 matches in sql_library/INDEX.md for "email whitespace audit":

  ★ Q13 — Email whitespace pollution audit (tenant-wide)
    File:     sql_library/queries/email-whitespace-pollution-audit.sql
    Schema:   user_identities, user_profiles (acme)
    Parameters: none (optional :sample_limit for drilldown)
    Score:    0.92 — exact match on "whitespace" + "email" + tables

    Q14 — Duplicate-account collision groups under a canonical email
    File:     sql_library/queries/email-collision-groups-for-triage.sql
    Schema:   user_identities, user_profiles, project_character_users (acme)
    Parameters: :min_group_size, :require_atsign
    Score:    0.61 — adjacent (collision triage, not the audit itself)

    Q08 — All Gateway/identity rows for an email pattern
    File:     sql_library/queries/identities-by-email-pattern.sql
    Schema:   user_identities (acme), users (gateway)
    Parameters: :email_pattern
    Score:    0.42 — partial match on "email"

Recommendation: parametrize and run Q13 first. If the audit surfaces collisions
that need triage, follow up with Q14.
```

## Implementation hints

While the library has fewer than ~30 queries, scoring can be a simple keyword-match function over the INDEX.md columns. Past that, swap in an embedding-based retriever: embed each row's purpose + business case + schema reference into a vector store, retrieve top-k by cosine similarity to the topic embedding. The skill should not require the embedding store on day one; it's an upgrade path, not a prerequisite.
