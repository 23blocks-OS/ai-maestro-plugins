---
name: docs-search
description: Search this codebase's generated documentation for function signatures, APIs and established patterns. Use before calling or extending a function, class or API you have not read in this session, so the call matches what exists, and when the user asks to "search docs", "find function" or "check API".
allowed-tools: Bash
compatibility: Requires AI Maestro (aimaestro.dev) with Bash shell access
metadata:
  author: 23blocks
  version: 1.1.0
---

# Docs Search

AI Maestro indexes the doc comments of your agent's project (JSDoc, RDoc, Python docstrings, TypeScript interfaces, READMEs, markdown guides) and serves them per agent. The scripts find your agent from the tmux session.

```bash
docs-search.sh "<query>"              # semantic search (default limit 10; --limit N)
docs-search.sh --keyword "<name>"     # exact name match, best for a known function or class
docs-get.sh <doc-id>                  # full document for an id from the search results
docs-find-by-type.sh <type>           # function | class | module | interface | component | constant | readme | guide
docs-list.sh [--limit N]              # all indexed documents (default 50)
docs-stats.sh                         # index size; 0 documents means the project was never indexed
```

A result gives the documented intent and signature; the source file is still the authority on current behaviour.

## Keeping the index current

```bash
docs-index-delta.sh [project-path]    # new and modified files only; use after code changes
docs-index.sh [project-path]          # full re-index
```

Without a path, both use the agent's working directory.

## If the command fails

- `command not found` or `common.sh not found`: run `./install-doc-tools.sh` from the AI Maestro checkout (`update-aimaestro.sh` also reinstalls the tools).
- Connection errors: AI Maestro is not reachable on this host.
- No results and `docs-stats.sh` shows an empty index: run `docs-index.sh`, or tell the user the project has no generated docs and read the code instead.
