# `/agentic-sql curate`

Post-investigation review. The discipline that prevents library decay.

## Contents

- Purpose
- When to run
- Procedure
- Patterns to follow
- Anti-patterns
- Example flow
- On the bigger picture

## Purpose

Before ending an investigation, review every SQL query that was executed during the session, decide which ones are reusable patterns, and promote those to library entries via `/agentic-sql add`. The remainder either go into a project-specific incident note or get discarded.

This is the step that fails silently in every team that "intends to keep a SQL library." When curation is nobody's explicit step, it becomes everyone's job and so nobody's. The skill makes curation a step in the workflow so no one else owns it.

## When to run

- Before reporting the final answer to the user at the end of an investigation.
- During a planned "library review" session (weekly / before a refactor).
- After a major incident, when the investigation produced multiple novel queries.
- On user-invoked `/agentic-sql curate`, anytime.

## Procedure

1. **Read the session log.** `/agentic-sql run` writes every executed query to `.claude/agentic-sql.session.log`. Parse it: which queries came from the library (with their `QNN` ID), which were ad-hoc.

2. **Group the ad-hoc queries by intent.** If the agent ran 5 variations of "count missing PCU contexts by project," those are one pattern, not five. Pick the most general / most parametrized variation as the canonical version.

3. **For each unique ad-hoc query, apply the reusability test:**

   | Test | Save as library entry? |
   |---|---|
   | Same shape will recur on future tickets (the WHO/WHAT change, the structure doesn't) | YES |
   | Hardcoded incident-specific values (specific UIDs, dates, status codes) | Parametrize first, then YES if shape is reusable |
   | Truly one-off ("I needed to count rows where x=42 just this once") | NO — drop or note in the incident file |
   | Already covered by an existing library query but in a slightly different shape | DEFER — consider updating the existing query header to note the variant |

4. **For each YES decision, invoke `/agentic-sql add`** with the canonical version. The add workflow handles header, schema reference, parametrization, INDEX.md update.

5. **For each NO decision, log the rejection reason** to the session log ("ad-hoc, incident-specific, dropped") so the next reviewer doesn't relitigate.

6. **Surface a one-line summary to the user.** "Promoted 3 queries to library (Q17, Q18, Q19); dropped 2 as incident-specific. Library now at 19 queries."

7. **(Optional) Open the changes for review.** If the project uses pull requests, the new queries + INDEX.md row can ship as a small "library: add Q17-Q19 from <ticket>" PR.

## Patterns to follow

- **Run curate BEFORE the final user-facing summary.** The agent's last action in the session is the user-facing report; curate is the second-to-last. Make it part of the wrap-up routine.
- **Prefer YES over NO when uncertain.** Disk is cheap; curation is the only way the library grows. A marginal save is worse than a marginal miss (the next person can delete a query; they can't conjure one that was thrown away).
- **Combine variations aggressively.** 5 ad-hoc queries from one investigation often reduce to 1 reusable + 4 incident-specific. The 1 is what gets saved.
- **Tie each saved query to the incident in the "Recent additions" note** at the bottom of INDEX.md. "2026-05-28 — Q17 added after support-001 (Jane Doe) — email whitespace tenant-wide audit." Six months later, the context is recoverable.

## Anti-patterns

- **"I'll curate at the end of the week."** No, you won't. The session ends, the context dies, the queries don't get saved. The week passes. The library freezes.
- **Saving every ad-hoc query as-is.** Without the reusability test, the library fills with one-off junk and `find` returns noise. Apply the filter.
- **Curating in silence.** The user should see "promoted N, dropped M" — transparency keeps the discipline honest. Hidden curation drifts.
- **Curating without parametrizing.** A saved query with `'2026-05-14'` hardcoded won't match the next investigation's pattern. Parametrize before saving.
- **Curating to a "personal" or scratch library.** The library is project-shared. If a query is only useful to one person, it doesn't belong in the library; it belongs in their notes.

## Example flow

```
agent: /agentic-sql curate

skill: Reading .claude/agentic-sql.session.log...
       Found 7 queries executed this session:
         - Q01 (project-by-name)        × 1   [library]
         - Q08 (identities-by-email)    × 1   [library]
         - ad-hoc                       × 5

       Grouping ad-hoc queries by intent...
       Reduced to 4 unique patterns:

       1. Count PCUs vs contexts per project (5 variations of one pattern)
          → REUSABLE. Will promote as Q17.

       2. Email whitespace pollution counts (3 variations)
          → REUSABLE. Will promote as Q18.

       3. Collision groups under canonical email
          → REUSABLE. Will promote as Q19.

       4. "PCUs created on 2026-05-14 between 14:00-18:00 UTC for project XYZ"
          → INCIDENT-SPECIFIC (date + project hardcoded). Drop.

       Run /agentic-sql add for each REUSABLE pattern? [Y/n]
user:  Y

skill: [walks through add for Q17, Q18, Q19]
       [updates INDEX.md with 3 new rows + a single "Recent additions" entry]

       Curation complete:
         Promoted to library: Q17, Q18, Q19
         Dropped: 1 (incident-specific)
         Library now at: 19 queries

       Ready to ship the library changes as part of your usual commit flow.
```

## On the bigger picture

The pattern this skill enforces — write-and-execute → review → promote → index — is the same shape Wikipedia editors use, software engineers use for tests, scientists use for lab notebooks. The discipline is universal; what changes is how strictly it's enforced. Without a forced step at the end of every investigation, the discipline collapses into "I'll add things when I have time," and time never comes.

`/agentic-sql curate` is the forced step. It's the most boring command in the skill and the most important.
