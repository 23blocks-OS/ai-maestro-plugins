# agentic-sql

Claude Code skill for **library-first SQL investigations**. Curated read-only query library + 3-layer safety gate (Postgres role isolation, SQLGlot AST check, LIMIT injection) + a forced post-investigation curation step that keeps the library from rotting.

Works with any Postgres, any framework, any backend that you investigate via psql.

> Based on:
> - Vanna AI's saved-query RAG pattern
> - AutoLink (arxiv 2511.17190) and LinkAlign (arxiv 2503.18596) — schema-as-retrieval
> - LangChain SQL Toolkit's two-tier safety layer (LLM checker + AST gate)
> - SQLGlot AST primer
> - Cemri et al. (arxiv 2503.13657) — multi-agent failure modes (specifically "diffusion of responsibility" → why curation must be a workflow step, not "everyone's job")

## Why this exists

Every team with a Postgres production database has the same problem: AI agents (and humans) keep re-deriving the same queries. A support ticket lands, someone reaches for psql, writes a query, runs it, reports back, and the query dies in a terminal history file. The next ticket reaches for the same query and re-derives it from scratch — sometimes with a different join key, sometimes missing a known gotcha, sometimes touching a column that was renamed three months ago.

Curated SQL libraries solve this — they're standard practice in mature data orgs — but they only work if the agent CONSULTS the library before writing new SQL and CURATES new findings after the investigation succeeds. Without enforcement, both steps get skipped under time pressure. The library freezes; ad-hoc scripts pile up in `scripts/audit_*.py`; the next incident the team can't find the query they wrote three months ago.

This skill makes both steps a non-negotiable part of the workflow: `find` before writing, `curate` before reporting back. Plus a 3-layer safety model that prevents the most common production accidents (running a query as the app role, executing a hallucinated DELETE, returning millions of rows by mistake).

## First-Time Setup

On first invocation, the skill auto-extracts these from `CLAUDE.md` if present and asks for any missing values:

| Variable | Purpose | Default if missing |
|---|---|---|
| `{QUERY_DIR}` | Where saved queries live (relative to project root) | `sql_library/queries/` |
| `{INDEX_PATH}` | Markdown index of the library | `sql_library/INDEX.md` |
| `{SCHEMA_DOC_PATH}` | Schema reference doc | `sql_library/SCHEMA.md` |
| `{DB_ENVS}` | Named environments and their connection variables | (asks) |
| `{READ_ONLY_ROLE}` | Postgres role with SELECT-only grants | `agentic_sql_ro` |
| `{SAFE_PSQL_WRAPPER}` | Wrapper script that AST-gates + LIMIT-injects | `bin/safe_psql.sh` |
| `{MAX_ROWS}` | Default LIMIT injected when query has none | `1000` |

Values persist to `.claude/agentic-sql.yml` for the session.

## Install

```bash
git clone https://github.com/23blocks-OS/agentic-sql.git ~/.claude/skills/agentic-sql
```

Then in any project:

```
/agentic-sql audit
```

Run once after install to verify the library / schema doc paths and surface any orphan files or missing schema references.

## Sub-Commands

| Command | What it does |
|---|---|
| `/agentic-sql find <topic>` | Search the library index for queries matching `<topic>`. Returns ranked matches with their purpose, schema references, and parameters. **Always run this first.** |
| `/agentic-sql audit` | Health-check the library: count queries, flag orphan `.sql` files not in the index, flag queries with no schema reference, list queries last touched > 90 days ago. |
| `/agentic-sql add` | Guided workflow for saving a new query: prompts for purpose, business case, environment, schema reference, parameters; formats the header; saves to `{QUERY_DIR}` with `kebab-case-name.sql`; updates `{INDEX_PATH}`. |
| `/agentic-sql run <query-id-or-path>` | Execute a saved query (by ID like `Q12`) or a freshly-written one. Wraps the call in `{SAFE_PSQL_WRAPPER}` which runs the AST gate, injects `LIMIT`, and connects as `{READ_ONLY_ROLE}`. |
| `/agentic-sql curate` | Post-investigation review. Surface any SQL run during this session that wasn't from the library, decide which are reusable, promote them via `add`. **Run before ending the conversation.** |
| `/agentic-sql schema <table-or-section>` | View or update `{SCHEMA_DOC_PATH}` for a specific table or section. When adding a new query that touches a previously-undocumented table, run this FIRST to document the table, then add the query. |

## Query categories the library should cover

These are the categories that tend to recur in real production work. Use them as the taxonomy when seeding a fresh library.

| Category | Example queries | Why it's worth saving |
|---|---|---|
| **Entity lookup** | "Find project / user / order by name pattern" | First step of every support ticket |
| **Identity reconciliation** | Cross-block identity joins (e.g. talent in tenant DB vs. search index vs. auth provider) | Catches drift between microservice copies |
| **Audit (read-only)** | Whitespace pollution, duplicate emails, forged document numbers, denormalized counter drift | Health checks before / after cleanups |
| **Cross-block joins** | When data spans multiple databases / tenants and the join key is `api_access_key` or similar | Pre-derived join paths avoid hallucinating columns |
| **Aggregation by time bucket** | Daily failure-rate breakdowns, regression-onset detection | Standard shape for "when did X start" investigations |
| **Magic-link / token resolution** | Resolve a customer's broken link back to who issued it, when, where | Recurring support ticket shape |
| **Test-fixture selection** | Find a test account / project / PCU with a specific shape for E2E tests | QA team asks for these repeatedly |
| **Collision / deduplication triage** | "All rows sharing canonical email/document with activity per row" | Required BEFORE any cleanup that might merge |

## What matters

1. **The library is a search corpus, not a folder.** If `find` doesn't surface the right query, the library failed even if the query exists.
2. **The schema doc is the source of truth, not the live DB schema.** A `\d table` in psql gives you columns but no gotchas, no join keys, no "this counter drifts under condition X" notes. The doc accumulates institutional knowledge; the live schema only gives you syntax.
3. **The 3-layer safety model is non-negotiable.** Read-only role at the Postgres level + AST gate at the application level + LIMIT injection at the wrapper level. Any one alone has been broken in production (CVE-2025-67644, recent LangGraph SQL injection).
4. **Curation runs before the final report.** Cemri et al. (arxiv 2503.13657) call this out as the #1 multi-agent failure: "diffusion of responsibility" — if curation isn't an explicit step, it becomes everyone's job and therefore nobody's job. The skill makes it a step.

## What NOT to do

- Do NOT use this skill for application code changes. It's an investigation tool.
- Do NOT use this skill for destructive operations (UPDATE / DELETE / INSERT). Those belong in `scripts/` as explicit one-off scripts with dry-run gating.
- Do NOT skip `find` because "I already know the query." You don't. Run it.
- Do NOT save a query without a schema reference line in the header. The next person can't tell which tables it touches.
- Do NOT defer curation to "end of week." The session ends, the context dies, the queries don't get saved.

## File Structure

```
agentic-sql/
├── LICENSE                 # MIT
├── README.md               # this file
├── SKILL.md                # skill manifest (YAML frontmatter + body)
└── reference/              # one playbook per sub-command
    ├── audit.md
    ├── find.md
    ├── add.md
    ├── run.md
    ├── curate.md
    └── schema.md
```

## Key Principles

1. **Library-first lookup is mandatory** — `find` always runs before new SQL gets written.
2. **Three-layer safety, all required** — Postgres role + AST gate + LIMIT injection.
3. **Schema doc is the source of truth** — never guess columns; read the doc first.
4. **Curation is part of the investigation** — it runs before the final report, not "later."
5. **No field fallbacks** — never use one column as a substitute for another inside a query.

## Works With

- Postgres (primary target — wrapper uses SQLGlot's PostgreSQL dialect)
- Any framework (Rails, Django, Node.js, etc.) — the skill is the investigation discipline, not application code
- Multi-DB / multi-tenant setups (built specifically for shared-cluster microservice architectures)
- 23blocks platform (the original motivating context — 6 microservice DBs sharing a tenant)

Should also work with MySQL / Snowflake / BigQuery with minor wrapper changes (SQLGlot supports all of them).

## References

- [Vanna.AI](https://vanna.ai/) — saved-query RAG pattern
- [AutoLink (arxiv 2511.17190)](https://arxiv.org/pdf/2511.17190) — iterative schema linking
- [LinkAlign (arxiv 2503.18596)](https://arxiv.org/pdf/2503.18596) — multi-database schema retrieval
- [SQLGlot](https://github.com/tobymao/sqlglot) — SQL parser / AST library used by the safety wrapper
- [LangChain SQL Toolkit](https://docs.langchain.com/oss/javascript/langchain/sql-agent) — two-tier safety layer pattern
- [Cemri et al., "Why Do Multi-Agent LLM Systems Fail?" (arxiv 2503.13657)](https://arxiv.org/pdf/2503.13657) — multi-agent failure mode taxonomy
- [Anthropic — Writing Tools for Agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Anthropic — Equipping Agents with Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)

## License

MIT — see [LICENSE](LICENSE).

---

Built by [23blocks](https://23blocks.com) — the backend-as-a-service with composable microservice blocks and agent-ready skills.
