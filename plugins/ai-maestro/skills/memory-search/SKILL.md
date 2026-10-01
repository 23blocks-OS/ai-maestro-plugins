---
name: memory-search
description: "Search this agent's long-term memory of past sessions: decisions, facts, corrections, and what depends on an entity. Use when a task touches something with history (a repo, service, environment or decision from earlier sessions), before deploying, moving, deleting or reconfiguring something to see what depends on it (memory-search.sh --about <entity>), and when the user asks \"what did we discuss\", \"remember when\", \"search memory\", \"find previous conversation\" or \"check history\"."
allowed-tools: Bash
compatibility: Requires AI Maestro (aimaestro.dev) with Bash shell access
metadata:
  author: 23blocks
  version: 1.2.0
---

# Memory Search

Your context window holds only this session. AI Maestro keeps your long-term memory, rebuilt nightly from your own past conversations (including ones Claude Code has already deleted). It is yours alone; other agents have their own.

- **Memory cards**: one-sentence statements of durable knowledge (decisions and why, facts about systems, preferences, lessons), each backed by the passages it came from. "Seen in N sessions" is weight: more sessions, more established.
- **Entity graph**: the things you work with (services, hosts, buckets, repos, files, people) and directed relations between them, such as `runs_on`, `depends_on`, `stores_data_in`, `deploys_to`, `breaks`. A relation marked **(no longer)** was reported as ended in a later session.

## Read what is already injected

AI Maestro adds `## Memory:` blocks to your context: standing decisions and preferences at session start, and with each prompt, what you know about the entities it names. Read those before searching; search when they don't cover the question. Memory can be out of date, so confirm against the current files or system before acting on it.

## Commands

```bash
memory-search.sh --about "<entity>"          # relations (current first, ended marked) + cards that mention it
memory-search.sh "<query>"                   # memory cards first, then matching conversation passages
memory-search.sh "<query>" --mode semantic   # related concepts, different wording
memory-search.sh "<query>" --mode term       # exact text
memory-search.sh "<query>" --mode symbol     # code identifiers (function, class, constant names)
memory-search.sh "<query>" --role user       # only what the user said (or: --role assistant)
memory-search.sh "<query>" --limit 5         # default 10
```

Default mode is `hybrid`, which suits most searches.

Before deploying, moving, deleting, migrating or reconfiguring something, run `--about` on it: it shows what runs on it, stores data in it and depends on it, which is the part of a change that is easy to miss from the files alone. Files show the current state; memory shows why it is that way and what broke last time.

No results is a real answer: the topic is probably new to this agent.

## If the command fails

`command not found` or `common.sh not found`: the tools are not installed in `~/.local/bin`. Run `./install-memory-tools.sh` from the AI Maestro checkout (`update-aimaestro.sh` also reinstalls them).
