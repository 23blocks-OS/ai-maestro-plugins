---
name: memory-search
description: PROACTIVELY search your long-term memory BEFORE starting new work and BEFORE changing anything. Use at the START of any non-trivial task to recall prior decisions and facts, and before deploying, moving, deleting or reconfiguring something to see what depends on it (memory-search.sh --about <entity>). Also use when the user asks to "search memory", "what did we discuss", "remember when", "find previous conversation", or "check history". Your memory is valuable — check it first rather than starting from scratch.
allowed-tools: Bash
compatibility: Requires AI Maestro (aimaestro.dev) with Bash shell access
metadata:
  author: 23blocks
  version: 1.1.0
---

# AI Maestro Memory Search

## CRITICAL: AUTOMATIC BEHAVIOR - READ THIS FIRST

**THIS IS NOT OPTIONAL. THIS IS YOUR DEFAULT BEHAVIOR.**

When the user gives you ANY instruction, you MUST FIRST search your memory for:
- **Previous discussions** - Have we talked about this before?
- **Past decisions** - What did we decide last time?
- **Prior context** - What does the user expect based on history?
- **Earlier work** - Did we already start on this?

**DO NOT:**
- Start fresh without checking conversation history
- Assume this is a new topic without verifying
- Skip memory search because "I don't remember discussing this"
- Wait for the user to say "remember when we..."

**ALWAYS:**
- Search memory IMMEDIATELY when you receive a task
- Search for terms and concepts the user mentions
- Check for previous decisions on similar topics
- Look for context that informs current work

### The Rule: Receive Instruction → Search Memory → Then Proceed

```
1. User asks you to do something
2. IMMEDIATELY search memory for relevant context
3. NOW you know what was discussed before
4. NOW you can build on previous work, not start over
```

### What your memory is

Your context window is your **short-term memory**: this session, and gone when
it ends. AI Maestro keeps your **long-term memory**, built every night from
your own conversations, including the ones Claude Code deleted after 30 days
(they are rebuilt from your message index):

- **Memory cards**: one-sentence statements of durable knowledge (decisions
  and why, facts about systems and the environment, preferences, lessons),
  each backed by the passages it came from. "Seen in N sessions" means the
  same knowledge came up that often; more sessions, more weight.
- **The entity graph**: the specific things you work with (services, hosts,
  buckets, repos, files, people) and directed relations between them:
  `X runs_on Y`, `X depends_on Y`, `X stores_data_in Y`, `X deploys_to Y`,
  `X breaks Y`... A relation marked **(no longer)** was said to have ended in
  a later session.

The memory is yours alone; other agents have their own.

### Memory before files, relations before changes

You often already have memory in context. AI Maestro injects `## Memory:`
blocks: at session start (your standing decisions and preferences), and with
each prompt (what you know about the entities the prompt names, and past notes
on the topic). **Read them first.** They can be outdated: verify anything you
act on.

Before you change something (deploy, move, delete, migrate, reconfigure),
check what it relates to:

```bash
memory-search.sh --about "<the thing you are about to change>"
```

It lists what runs on it, stores data in it, depends on it and what it depends
on, and the memory cards that mention it. Consider everything a change
affects before making it. Check memory before opening files to re-learn
something: files show the current state, memory shows why it is that way and
what broke last time.

`memory-search.sh "<query>"` shows memory cards first, then matching raw
conversation history.

---

## Available Commands

| Command | Description |
|---------|-------------|
| `memory-search.sh "<query>"` | Hybrid search (recommended) |
| `memory-search.sh --about "<entity>"` | Everything memory knows about one host, agent, service, file or person: its relations (current first, ended ones marked) and memory cards. Use before changing that thing. |
| `memory-search.sh "<query>" --mode semantic` | Find conceptually related |
| `memory-search.sh "<query>" --mode term` | Exact term matching |
| `memory-search.sh "<query>" --role user` | Only user messages |
| `memory-search.sh "<query>" --role assistant` | Only your responses |

## What to Search Based on User Instruction

| User Says | IMMEDIATELY Search |
|-----------|-------------------|
| "Continue working on X" | `memory-search.sh "X"` |
| "Fix the issue we discussed" | `memory-search.sh "issue"`, `memory-search.sh "bug"` |
| "Use the approach we agreed on" | `memory-search.sh "approach"`, `memory-search.sh "decision"` |
| "Like we did before" | `memory-search.sh "<topic> implementation"` |
| Any specific feature/component | `memory-search.sh "<feature>"` |
| References to past work | `memory-search.sh "<reference>" --mode semantic` |

## Quick Examples

```bash
# User asks to continue previous work
memory-search.sh "authentication"
memory-search.sh "last session"

# User mentions a component we discussed
memory-search.sh "PaymentService" --mode term

# Find what the user previously asked for
memory-search.sh "user request" --role user

# Find your previous solutions
memory-search.sh "implementation" --role assistant

# Conceptual search for related discussions
memory-search.sh "error handling patterns" --mode semantic
```

## Search Modes

| Mode | Use When |
|------|----------|
| `hybrid` (default) | General search, best for most cases |
| `semantic` | Looking for related concepts, different wording |
| `term` | Looking for exact function/class names |
| `symbol` | Looking for code symbols mentioned |

### Symbol Mode Examples

The `symbol` mode is optimized for finding code symbols (function names, class names, variable names) mentioned in past conversations. Unlike `term` mode which does exact text matching, `symbol` mode understands code identifiers and matches them across different contexts.

```bash
# Find discussions where a specific function was mentioned
memory-search.sh "processPayment" --mode symbol

# Find conversations about a class
memory-search.sh "AuthenticationService" --mode symbol

# Find references to a variable or constant
memory-search.sh "MAX_RETRY_COUNT" --mode symbol
```

**When to use `symbol` vs `term`:**
- Use `--mode symbol` when searching for code identifiers (functions, classes, variables)
- Use `--mode term` when searching for exact phrases or non-code text

## Why This Matters

Without searching memory first, you will:
- Repeat explanations the user already heard
- Contradict previous decisions
- Miss context that changes the approach
- Start over instead of continuing

**Memory search takes 1 second. Frustrating the user is much worse.**

## Combining with Doc Search

For complete context, use BOTH:
```bash
# User asks about creating a new feature
memory-search.sh "feature"       # What did we discuss?
docs-search.sh "feature"         # What do docs say?
```

## Helper Scripts

This skill relies on an internal helper script that provides shared utility functions:

- **`memory-helper.sh`** - Sourced by the `memory-*.sh` tool scripts. Provides memory-specific API functions (`memory_query`, `init_memory`) and initialization logic. Located alongside the tool scripts in `~/.local/bin/` (installed) or `plugin/src/scripts/` (source). If tool scripts fail with "common.sh not found", re-run the installer (`./install-memory-tools.sh`).

## Error Handling

If no results found, that's valuable information too:
"No previous discussions found about X - this appears to be a new topic. Let me search the documentation..."

Then search docs as fallback.

**Script not found:**
- Check PATH: `which memory-search.sh`
- Verify scripts installed: `ls -la ~/.local/bin/memory-*.sh`
- Scripts are installed to `~/.local/bin/` which should be in your PATH

## Installation

If commands are not found:
```bash
./install-memory-tools.sh
```

This installs scripts to `~/.local/bin/`.
