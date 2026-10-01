---
name: graph-query
description: Query the code graph for callers, dependencies and the blast radius of a change. Use before changing the signature or behaviour of a function, class or module that other code uses, when the user asks "find callers", "what uses this" or "check dependencies", and when exploring an unfamiliar codebase.
allowed-tools: Bash
compatibility: Requires AI Maestro (aimaestro.dev) with Bash shell access
metadata:
  author: 23blocks
  version: 1.1.0
---

# Code Graph Query

AI Maestro keeps a graph of your agent's project: functions, classes and their calls, inheritance, includes, model associations and serializers. It answers "what breaks if I change this" faster and more completely than grep, which misses indirect callers, subclasses and serializers. The scripts find your agent from the tmux session; names are case-sensitive.

```bash
graph-describe.sh <name>               # summary: callers, callees, extends/extended by, includes, serializers
graph-find-callers.sh <function>       # who calls it: check before changing a signature
graph-find-callees.sh <function>       # what it calls
graph-find-related.sh <component>      # extends, includes and other relationships
graph-find-path.sh <from> <to>         # call path between two functions (up to 5 hops)
graph-find-by-type.sh <type>           # model | serializer | controller | service | job | mailer | concern | component | hook
graph-find-associations.sh <model>     # belongs_to / has_many etc.
graph-find-serializers.sh <model>      # serializers to update when a model changes
```

For a change to shared code, `graph-describe.sh` usually answers the question in one call; use the narrower scripts when you need the full list.

## Keeping the graph current

```bash
graph-index-delta.sh [project-path]
```

Re-indexes only new, modified and deleted files (seconds); the first run on a project does the full index. Without a path it uses the agent's working directory. Run it after significant code changes if results look stale.

## If the command fails

- `command not found` or `common.sh not found`: run `./install-graph-tools.sh` from the AI Maestro checkout (`update-aimaestro.sh` also reinstalls the tools).
- Empty results: check the exact name, list candidates with `graph-find-by-type.sh`, or index with `graph-index-delta.sh`.
- AI Maestro unreachable: fall back to grep and tell the user the dependency check was manual.
