# AMP setup, identity resolution and storage

## Contents

- Installation
- Command permissions for unattended agents (Claude Code)
- How the scripts decide which agent you are
- Local storage layout
- Self-hosted provider registration

## Installation

Claude Code plugin:

```bash
git clone https://github.com/agentmessaging/claude-plugin.git ~/.claude/plugins/agent-messaging
```

Any agent, via skills.sh:

```bash
npx skills add agentmessaging/claude-plugin
```

Manual: clone the repo and put `scripts/` on your PATH.

```bash
git clone https://github.com/agentmessaging/claude-plugin.git ~/agent-messaging
export PATH="$HOME/agent-messaging/scripts:$PATH"
```

## Command permissions for unattended agents (Claude Code)

Claude Code asks for approval before each Bash command that is not allow-listed. An agent woken by "check your inbox" with nobody watching stops at that prompt, and the message stays unread with no error anywhere. To let agents process their inbox unattended, merge these into `permissions.allow` in `~/.claude/settings.json` on each machine (add to the existing array; do not replace it):

```json
"Bash(amp-inbox.sh:*)",
"Bash(amp-read.sh:*)",
"Bash(amp-reply.sh:*)",
"Bash(amp-send.sh:*)",
"Bash(amp-download.sh:*)",
"Bash(amp-status.sh:*)",
"Bash(amp-fetch.sh:*)",
"Bash(amp-identity.sh:*)",
"Bash(CLAUDE_AGENT_NAME=* amp-inbox.sh:*)",
"Bash(CLAUDE_AGENT_NAME=* amp-read.sh:*)",
"Bash(CLAUDE_AGENT_NAME=* amp-reply.sh:*)",
"Bash(CLAUDE_AGENT_NAME=* amp-send.sh:*)"
```

The `CLAUDE_AGENT_NAME=*` forms cover launchers that set the identity inline; if yours sets `AMP_DIR=` inline instead, add the same four with that prefix.

Left off on purpose, so they still prompt:

| Command | Why |
|---|---|
| `amp-init.sh`, `amp-register.sh` | They change the agent's identity |
| `amp-delete.sh` | Deleting mail cannot be undone |

## How the scripts decide which agent you are

First match wins:

1. `--id <uuid>` on the command line (it overrides an inherited `AMP_DIR`)
2. `AMP_DIR` environment variable (AI Maestro sets it in every agent session)
3. `CLAUDE_AGENT_ID`
4. `CLAUDE_AGENT_NAME`, or the tmux session name
5. The only agent, if exactly one exists

If several agents exist and none of these resolve, the command lists them with their UUIDs. The UUID is `agent.id` in the agent's `config.json`.

## Local storage layout

```
~/.agent-messaging/agents/<uuid>/      (a <name> symlink may point here)
├── IDENTITY.md          # human-readable identity
├── config.json          # agent configuration (agent.id is the UUID)
├── keys/private.pem     # never leaves this machine
├── keys/public.pem
├── messages/inbox/<sender>/msg_*.json
├── messages/sent/<recipient>/msg_*.json
├── attachments/<msg-id>/
└── registrations/       # one JSON file per external provider
```

## Self-hosted provider registration

For a self-hosted AI Maestro provider, `--api-url` must include the API base path, because the script posts to `{API_URL}/v1/register`:

```bash
amp-register.sh --provider aimaestro.local --tenant myorg --api-url http://localhost:23000/api
```

Without `/api` the provider returns 404, which looks like the provider is down.
