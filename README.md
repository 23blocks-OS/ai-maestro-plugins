# AI Maestro Plugins for Claude Code

Official plugin marketplace for [AI Maestro](https://github.com/23blocks-OS/ai-maestro) — the AI agent orchestration platform.

## Quick Install

```bash
# Add marketplace
/install 23blocks-OS/ai-maestro-plugins

# Install the plugin
/install ai-maestro@ai-maestro-plugins
```

## What's Included

### Skills (6)

| Skill | Description | Requires AI Maestro Service? |
|-------|-------------|------------------------------|
| `memory-search` | Search conversation history for previous discussions | YES |
| `docs-search` | Search auto-generated documentation for APIs | YES |
| `graph-query` | Query code graph to understand relationships | YES |
| `agent-messaging` | Send and receive messages between AI agents (AMP) | YES |
| `ai-maestro-agents-management` | Manage AI agents (list, export, import) | YES |
| `planning` | Complex task execution with persistent markdown files | **NO - Standalone** |

### Hooks (3)

| Event | Purpose |
|-------|---------|
| `SessionStart` | Check for unread messages, broadcast session status |
| `Stop` | Update session status when Claude finishes |
| `Notification` | Track idle/permission prompts for Chat UI |

### CLI Scripts (39)

All scripts are bundled in `plugins/ai-maestro/scripts/`. Install to your PATH with:

```bash
# From AI Maestro app repo
./install-messaging.sh -y
```

**Categories:**
- **AMP Messaging** (13): `amp-send`, `amp-inbox`, `amp-read`, `amp-reply`, `amp-delete`, `amp-init`, `amp-status`, `amp-register`, `amp-fetch`, `amp-download`, `amp-identity`, `amp-security`, `amp-helper`
- **Code Graph** (9): `graph-describe`, `graph-find-callers`, `graph-find-callees`, `graph-find-related`, `graph-find-associations`, `graph-find-by-type`, `graph-find-path`, `graph-find-serializers`, `graph-index-delta`
- **Documentation** (8): `docs-search`, `docs-index`, `docs-index-delta`, `docs-list`, `docs-get`, `docs-find-by-type`, `docs-stats`, `docs-helper`
- **Memory** (2): `memory-search`, `memory-helper`
- **Agent Management** (4): `aimaestro-agent`, `agent-helper`, `list-agents`, `export-agent`, `import-agent`
- **Hooks** (1): `ai-maestro-hook.cjs`

## Full AI Maestro Installation

For the complete experience (dashboard + service + all skills working):

```bash
curl -fsSL https://raw.githubusercontent.com/23blocks-OS/ai-maestro/main/scripts/remote-install.sh | sh
```

## Learn More

- [AI Maestro](https://github.com/23blocks-OS/ai-maestro)
- [AMP Protocol](https://agentmessaging.org)
- [Claude Code Plugins](https://docs.anthropic.com/en/docs/claude-code/plugins)

## License

MIT
