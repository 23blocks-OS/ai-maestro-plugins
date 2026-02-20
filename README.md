# AI Maestro Plugins

Official Claude Code plugins for [AI Maestro](https://github.com/23blocks-OS/ai-maestro) -- the browser-based dashboard for managing multiple Claude Code agents.

## Quick Install

```bash
# From the AI Maestro repo
./install-messaging.sh -y
```

This installs all scripts to `~/.local/bin/` and skills to `~/.claude/skills/`.

## What's Included

### Skills (6)

| Skill | Description |
|-------|-------------|
| **agent-messaging** | Send and receive messages between agents via AMP |
| **ai-maestro-agents-management** | Create, delete, hibernate, wake, rename, and manage agents |
| **docs-search** | Search auto-generated documentation for functions and APIs |
| **graph-query** | Query the code graph database for dependencies and relationships |
| **memory-search** | Search conversation history for previous decisions and context |
| **planning** | Persistent markdown-based task tracking for complex work |

### CLI Scripts

**Agent Management** (`aimaestro-agent.sh`) -- Modular CLI for full agent lifecycle:

```
aimaestro-agent.sh list                          # List all agents
aimaestro-agent.sh show <agent>                  # Show agent details
aimaestro-agent.sh create <name> --dir <path>    # Create new agent
aimaestro-agent.sh delete <agent> --confirm      # Delete agent
aimaestro-agent.sh hibernate <agent>             # Hibernate agent
aimaestro-agent.sh wake <agent>                  # Wake agent
aimaestro-agent.sh plugin install <agent> <pkg>  # Install plugin
aimaestro-agent.sh skill install <agent> <src>   # Install skill
```

**AMP Messaging** -- Inter-agent communication:

```
amp-send.sh <to> <subject> <message>    # Send a message
amp-inbox.sh                            # Check inbox
amp-read.sh <id>                        # Read a message
amp-reply.sh <id> <message>             # Reply to a message
```

**Code Graph, Docs, Memory** -- Search and query tools for agents.

## Architecture

```
plugin/
  plugin.manifest.json    # Build manifest (2 sources)
  build-plugin.sh         # Assembles plugin from sources
  CHANGELOG.md            # Release history
  src/                    # Source files
    scripts/              # CLI scripts (31 files)
    skills/               # 6 skill definitions
    hooks/                # Session tracking hooks
  plugins/ai-maestro/     # Built output (committed, ready to install)
    .claude-plugin/       # Plugin metadata
    scripts/              # 44 scripts (core + AMP)
    skills/               # 6 skills
    hooks/                # Hook definitions
```

The build merges two sources defined in `plugin.manifest.json`:
1. **core** (local) -- Agent management, graph, docs, memory, planning
2. **amp-messaging** (git) -- [AMP protocol](https://github.com/agentmessaging/claude-plugin) scripts and skill

## Building

```bash
./build-plugin.sh              # Build from manifest
./build-plugin.sh --clean      # Clean rebuild
./build-plugin.sh --dry-run    # Preview without changes
```

The built output in `plugins/ai-maestro/` is committed so users get a working plugin without running the build.

## CLI Module Structure

The `aimaestro-agent.sh` CLI is split into focused modules:

| Module | Lines | Purpose |
|--------|-------|---------|
| `aimaestro-agent.sh` | 108 | Thin dispatcher, sources all modules |
| `agent-helper.sh` | 980 | Colors, print helpers, agent resolution, API base |
| `agent-core.sh` | 728 | Security scanning, validation, JSON editing, Claude CLI |
| `agent-commands.sh` | 991 | CRUD: list, show, create, delete, update, rename, export, import |
| `agent-session.sh` | 323 | Session add/remove/exec, hibernate, wake, restart |
| `agent-skill.sh` | 471 | Skill list/add/remove/install/uninstall |
| `agent-plugin.sh` | 1,358 | Plugin (10 subcommands) + marketplace (4 subcommands) |

## Requirements

- macOS or Linux
- Bash 4.0+
- tmux 3.0+
- jq, curl
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## License

MIT
