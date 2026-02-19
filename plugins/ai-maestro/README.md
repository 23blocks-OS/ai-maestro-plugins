# AI Maestro Plugin

**Version:** 1.0.0
**Skills:** 6 | **Scripts:** 39

The AI Maestro plugin provides Claude Code skills, CLI scripts, and session hooks for the [AI Maestro](https://github.com/23blocks-OS/agents-web) agent orchestration platform. It installs into any Claude Code agent and connects it to the AI Maestro ecosystem.

## What This Plugin Does

This plugin gives Claude Code agents access to:

- **Agent Messaging Protocol (AMP)** -- Send and receive messages between agents
- **Memory Search** -- Semantic search across conversation history
- **Code Graph** -- Query code relationships and dependencies
- **Documentation Search** -- Search auto-generated code documentation
- **Task Planning** -- Persistent task tracking with markdown files
- **Agent Management** -- Create, list, hibernate, wake, export agents

## Relationship to Cerebellum

The plugin and the Cerebellum subsystem are **complementary but separate systems** that work together inside AI Maestro:

```
┌──────────────────────────────────────────────────────────┐
│                     AI Maestro                           │
│                                                          │
│  ┌─────────────────────┐   ┌──────────────────────────┐ │
│  │   Cerebellum        │   │   Plugin                  │ │
│  │   (Server-side)     │   │   (Agent-side)            │ │
│  │                     │   │                            │ │
│  │  - Voice narration  │   │  - AMP messaging          │ │
│  │  - Memory indexing  │   │  - Code graph queries     │ │
│  │  - Terminal buffer  │   │  - Memory search          │ │
│  │  - Activity state   │   │  - Doc search             │ │
│  │  - TTS pipeline     │   │  - Agent management CLI   │ │
│  │                     │   │  - Task planning           │ │
│  └────────┬────────────┘   └────────────┬──────────────┘ │
│           │                             │                 │
│           └──────────┬──────────────────┘                 │
│                      │                                    │
│               ┌──────▼──────┐                             │
│               │  server.mjs │                             │
│               │  (bridge)   │                             │
│               └─────────────┘                             │
└──────────────────────────────────────────────────────────┘
```

**Cerebellum** runs server-side inside AI Maestro's Node.js process. It manages autonomous background tasks per agent -- buffering terminal output, detecting idle states, calling Claude Haiku to generate voice summaries, and streaming speech events to the companion browser. It is infrastructure that the agent never interacts with directly.

**Plugin** runs agent-side inside Claude Code sessions. It provides skills (natural language capabilities) and scripts (CLI tools) that agents use directly. When an agent says "check my messages" or "search my memory", the plugin handles it.

**How they connect:**
- Plugin hooks (`hooks.json`) report session lifecycle events to AI Maestro's API
- AI Maestro's server tracks which agents are active and manages their Cerebellum instances
- AMP messages can trigger tmux notifications that agents see in their terminal (which Cerebellum can then narrate via voice)
- The plugin's memory-search skill queries the same CozoDB database that Cerebellum's memory subsystem indexes

### What Lives Where

| Component | Location | Runs In | Purpose |
|-----------|----------|---------|---------|
| Voice Subsystem | `lib/cerebellum/voice-subsystem.ts` | AI Maestro server | LLM summarization of terminal output |
| Terminal Buffer | `lib/cerebellum/terminal-buffer.ts` | AI Maestro server | 8KB ring buffer for PTY data |
| Memory Subsystem | `lib/cerebellum/memory-subsystem.ts` | AI Maestro server | Background conversation indexing |
| Companion UI | `app/companion/page.tsx` | Browser | Voice playback and controls |
| TTS Providers | `lib/tts.ts` | Browser | Web Speech / OpenAI / ElevenLabs |
| AMP Scripts | `scripts/amp-*.sh` | Agent terminal | Inter-agent messaging CLI |
| Memory Search | `scripts/memory-*.sh` | Agent terminal | Semantic memory queries |
| Graph Query | `scripts/graph-*.sh` | Agent terminal | Code relationship analysis |
| Session Hooks | `hooks/hooks.json` | Claude Code | Lifecycle event reporting |

For full Cerebellum documentation, see [docs/CEREBELLUM.md](https://github.com/23blocks-OS/agents-web/blob/main/docs/CEREBELLUM.md) in the main repo.

## Installation

### As Part of AI Maestro

The plugin is bundled as a git submodule at `plugin/` in the main AI Maestro repo:

```bash
git submodule update --init --recursive
```

### AMP Messaging Only

To install just the messaging system on any machine:

```bash
./install-messaging.sh      # Interactive
./install-messaging.sh -y   # Non-interactive
```

This installs:
- AMP scripts (`amp-*.sh`) to `~/.local/bin/`
- AMP skill to `~/.claude/skills/agent-messaging/`
- Message storage at `~/.agent-messaging/`

## Skills

### 1. Agent Messaging (`agent-messaging/`)

Inter-agent communication via the Agent Messaging Protocol:

```
"Check my messages"           → amp-inbox.sh
"Send alice a message"        → amp-send.sh alice "Subject" "Body"
"Reply to the last message"   → amp-reply.sh <id> "Response"
```

- Local-first with optional federation to external providers (CrabMail)
- Ed25519 cryptographic message signing
- Push notifications via tmux

### 2. Agent Management (`ai-maestro-agents-management/`)

Full agent lifecycle management:

```
"Create a new agent called backend-api"  → agent creation flow
"List all agents"                        → aimaestro-agents.sh list
"Hibernate backend-api"                  → agent hibernation
"Install the graph plugin"               → plugin marketplace
```

### 3. Memory Search (`memory-search/`)

Semantic search across agent conversation history:

```
"Search my memory for authentication"    → memory-search.sh "authentication"
"What did we discuss about the API?"     → semantic vector search
```

Uses CozoDB for vector storage and retrieval.

### 4. Code Graph (`graph-query/`)

Query code relationships and dependencies:

```
"What depends on the auth module?"       → graph-query.sh dependents auth
"Show the import graph for agent.ts"     → graph-query.sh imports agent.ts
```

### 5. Documentation Search (`docs-search/`)

Search auto-generated code documentation:

```
"Find the API for session management"    → docs-search.sh "session management"
"How does the WebSocket handler work?"   → docs-search.sh "websocket handler"
```

### 6. Planning (`planning/`)

Persistent task tracking with markdown files:

```
"Create a plan for the refactor"         → Creates task_plan.md, findings.md, progress.md
"Update the progress"                    → Updates progress.md
```

## Scripts

### AMP Messaging (13 scripts)

| Script | Description |
|--------|-------------|
| `amp-init.sh` | Initialize agent identity (Ed25519 keys) |
| `amp-status.sh` | Show agent status and registrations |
| `amp-inbox.sh` | Check inbox for messages |
| `amp-read.sh` | Read a specific message |
| `amp-send.sh` | Send a message to another agent |
| `amp-reply.sh` | Reply to a message |
| `amp-delete.sh` | Delete a message |
| `amp-register.sh` | Register with an external provider |
| `amp-fetch.sh` | Fetch messages from external providers |
| `amp-forward.sh` | Forward a message |
| `amp-contacts.sh` | Manage contact list |
| `amp-search.sh` | Search messages |
| `amp-export.sh` | Export message archive |

### Agent Tools (3 scripts)

| Script | Description |
|--------|-------------|
| `aimaestro-agents.sh` | Agent lifecycle management CLI |
| `agent-export.sh` | Export agent configuration and data |
| `agent-import.sh` | Import agent from backup |

### Code Tools (16 scripts)

| Script | Description |
|--------|-------------|
| `graph-*.sh` (8) | Code graph queries, indexing, visualization |
| `docs-*.sh` (8) | Documentation generation, search, indexing |

### Memory Tools (4 scripts)

| Script | Description |
|--------|-------------|
| `memory-search.sh` | Semantic search across conversations |
| `memory-index.sh` | Index new conversations |
| `memory-consolidate.sh` | Long-term memory consolidation |
| `export-conversations.sh` | Export conversation history |

## Hooks

Session lifecycle hooks that report agent state to AI Maestro:

| Hook | Trigger | Purpose |
|------|---------|---------|
| `Notification` | idle_prompt, permission_prompt | Track agent state changes |
| `Stop` | Agent exits | Cleanup and sync |
| `SessionStart` | Agent starts | Initialize session tracking |

Hooks are defined in `hooks/hooks.json` and execute `ai-maestro-hook.cjs`.

## Building

The plugin is built from `plugin.manifest.json` which merges two sources:

1. **Core** (local): Skills, scripts, hooks from `./src/`
2. **AMP Messaging** (git): External AMP plugin from `https://github.com/agentmessaging/claude-plugin.git`

```bash
./build-plugin.sh
```

## Development

- **Plugin repo:** [23blocks-OS/ai-maestro-plugins](https://github.com/23blocks-OS/ai-maestro-plugins)
- **Main repo:** [23blocks-OS/agents-web](https://github.com/23blocks-OS/agents-web)
- **AMP spec:** [agentmessaging.org](https://agentmessaging.org)

The plugin is mounted as a git submodule in the main repo at `plugin/`. Update with:

```bash
git submodule update --remote plugin
```
