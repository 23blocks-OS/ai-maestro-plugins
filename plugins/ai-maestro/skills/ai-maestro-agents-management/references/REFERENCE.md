# AI Maestro Agent Management — Detailed Reference

This document contains detailed output formats, scenarios, troubleshooting, and architecture information for the `aimaestro-agent.sh` CLI. For the command quick-reference, see the parent [SKILL.md](../SKILL.md).

---

## Detailed Output Formats

### List Output (table)

```
┌────────────────────┬──────────┬─────────────────────────────────┬──────────────┐
│ Agent              │ Status   │ Working Directory               │ Tags         │
├────────────────────┼──────────┼─────────────────────────────────┼──────────────┤
│ backend-api        │ online   │ /Users/dev/projects/backend     │ api, prod    │
│ frontend-dev       │ online   │ /Users/dev/projects/frontend    │ ui           │
│ data-processor     │ hibernated│ /Users/dev/projects/data       │              │
└────────────────────┴──────────┴─────────────────────────────────┴──────────────┘
```

### Show Output (pretty)

```
Agent: backend-api
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ID:          a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Status:      online
  Program:     claude-code
  Model:       sonnet
  Created:     2025-01-15T10:30:00Z

  Working Directory:
    /Users/dev/projects/backend

  Sessions (1):
    [0] backend-api (online)

  Task:
    Implement REST API endpoints for user management

  Skills (2):
    - git-workflow
    - agent-messaging

  Tags: api, production, critical
```

**Notes:**
- The header line ("Agent: ...") is displayed in bold cyan
- The separator uses `━` (U+2501 BOX DRAWINGS HEAVY HORIZONTAL)
- "Working Directory:" and "Task:" are on their own lines with values indented below
- Skills and Tags sections only appear if the agent has at least one skill or tag

---

## Create Agent — What It Does

1. Checks if agent name already exists (fails if duplicate)
2. Creates the project folder at specified path (unless --no-folder)
3. Initializes git repo in the folder
4. Creates CLAUDE.md template
5. Registers agent in AI Maestro
6. Creates tmux session (unless --no-session)

**Error handling:**
- Exits with error if name already exists
- Exits with error if --dir is not specified
- Exits with error if folder exists (unless --force-folder)

---

## Delete Agent — What It Does

1. Validates agent exists
2. Kills tmux session if running
3. Removes agent from registry
4. (Future: Optionally preserves folder/data based on flags)

**Note:** The `--keep-folder` and `--keep-data` flags are reserved for future API support. Currently the API doesn't support these options.

---

## Plugin Install — Restart Behavior

- **Remote agent**: Automatically hibernates and wakes the agent to apply changes
- **Current agent (self)**: Shows instructions to manually restart Claude Code
- If plugin is already installed, the command continues without error

## Plugin Load — Session Only

- Does NOT install the plugin — it is only available while the session runs
- Session-only plugins don't appear in `plugin list` and won't persist across restarts
- For persistent installation, use `plugin install`

## Plugin Clean — What It Does

- Validates all installed plugins for the agent
- Identifies plugins that fail validation
- Reports or removes orphaned cache directories
- Cleans up stale entries in config files

## Marketplace Add — Restart Behavior

- **Remote agent**: Automatically hibernates and wakes the agent to apply changes
- **Current agent (self)**: Shows instructions to manually restart Claude Code
- If marketplace is already installed, the command continues without error

---

## Skill Management: Registry vs Filesystem

There are two ways to manage skills:

1. **Registry commands** (`list`, `add`, `remove`) — Manage skills tracked in the AI Maestro agent registry. These update the agent's metadata via the API but do not copy files.
2. **Filesystem commands** (`install`, `uninstall`) — Install or remove skill files on disk (`.skill` archives or skill directories). These copy files into the appropriate `.claude/skills/` directory.

Both can be used independently or together. Use `add`/`remove` when AI Maestro tracks which skills an agent has. Use `install`/`uninstall` when you need to actually place skill files on disk.

### Skill Install Scopes

| Scope | Location | Who has access | Available where |
|-------|----------|----------------|-----------------|
| `user` | `~/.claude/skills/<name>/` | Only you | All your projects |
| `project` | `<agent-dir>/.claude/skills/<name>/` | All collaborators | Only this project |
| `local` | `<agent-dir>/.claude/skills/<name>/` | Only you (gitignored) | Only this project |

### Skill Install Source Types

- `.skill` or `.zip` file — Zip archive containing SKILL.md and optional resources
- Directory — Folder containing SKILL.md at the top level

**Note:** Plugin-based skills (installed via `plugin install`) should be managed with the `plugin` commands instead.

---

## Decision Guide

**Use `create` when:**
- Starting a new project/agent
- Need isolated working environment
- Want git-initialized folder

**Use `hibernate` when:**
- Agent not needed for a while
- Want to free system resources
- Need to preserve agent state

**Use `wake` when:**
- Resuming work on hibernated agent
- Need agent context back

**Use `update` when:**
- Changing task focus
- Managing tags for organization

**Use `plugin install` when:**
- Adding Claude Code extensions to agent
- Need agent-specific tools

**Use `export/import` when:**
- Backing up agent configuration
- Moving agent to another machine
- Sharing agent setup with team

---

## Script Architecture

The CLI is split into focused modules, all sourced by the main dispatcher:

- **`aimaestro-agent.sh`** - Thin dispatcher (~108 lines). Sources all modules below, sets up cleanup trap, and routes commands.
- **`agent-helper.sh`** - Shared utilities: colors, `print_*`, `resolve_agent`, `get_api_base`, API URL resolution, agent name/ID lookups.
- **`agent-core.sh`** - Shared infrastructure: security scanning (ToxicSkills), validation, Claude CLI helpers, `safe_json_edit`, temp file management.
- **`agent-commands.sh`** - CRUD commands: `list`, `show`, `create`, `delete`, `update`, `rename`, `export`, `import`.
- **`agent-session.sh`** - Session lifecycle: `session add/remove/exec`, `hibernate`, `wake`, `restart`.
- **`agent-skill.sh`** - Skill management: `skill list/add/remove/install/uninstall`.
- **`agent-plugin.sh`** - Plugin management (10 subcommands) + marketplace (4 subcommands).

All modules are located alongside the CLI script in `~/.local/bin/` (installed) or `plugin/src/scripts/` (source). Each module has a double-source guard to prevent re-sourcing. If the CLI fails with sourcing errors, verify all `agent-*.sh` files are present in the same directory.

---

## Examples by Scenario

### Scenario 1: Set Up New Development Environment

```bash
aimaestro-agent.sh create backend-api \
  --dir ~/projects/my-app/backend \
  --task "Build REST API with Node.js and TypeScript" \
  --tags "api,typescript,backend"

aimaestro-agent.sh create frontend-ui \
  --dir ~/projects/my-app/frontend \
  --task "Build React dashboard" \
  --tags "react,frontend,ui"

aimaestro-agent.sh list
```

### Scenario 2: End of Day — Save Resources

```bash
aimaestro-agent.sh hibernate frontend-ui
aimaestro-agent.sh hibernate data-processor
aimaestro-agent.sh list --status hibernated
```

### Scenario 3: Resume Work Next Day

```bash
aimaestro-agent.sh wake frontend-ui --attach
```

### Scenario 4: Backup Before Major Changes

```bash
aimaestro-agent.sh export backend-api \
  -o backups/backend-$(date +%Y%m%d).json

# If needed, delete and reimport
aimaestro-agent.sh delete backend-api --confirm
aimaestro-agent.sh import backups/backend-20250201.json
```

### Scenario 5: Share Agent Configuration

```bash
aimaestro-agent.sh export template-api -o team/api-template.json

# Team member imports
aimaestro-agent.sh import team/api-template.json \
  --name my-new-api \
  --dir ~/projects/my-api
```

### Scenario 6: Install Marketplace and Plugins on Remote Agent

```bash
aimaestro-agent.sh plugin marketplace add data-processor github:my-org/ai-plugins
aimaestro-agent.sh plugin install data-processor data-analysis-tool
aimaestro-agent.sh show data-processor
```

### Scenario 7: Install Marketplace on Current Agent (Self)

```bash
# When installing on the current agent, manual restart is needed
aimaestro-agent.sh plugin marketplace add current-agent github:my-org/plugins

# Script will show restart instructions:
#   "Claude Code restart required for the marketplace to be available"
#   1. Exit Claude Code with '/exit' or Ctrl+C
#   2. Run 'claude' again in your terminal

# After restarting, install plugins
aimaestro-agent.sh plugin install current-agent my-plugin
```

---

## Troubleshooting

### Plugin/Marketplace Issues

**Plugin not available after install:**
```bash
# For remote agents, restart manually
aimaestro-agent.sh restart backend-api

# For current agent (self), exit and restart Claude Code
# Type '/exit' or Ctrl+C, then run 'claude' again
```

**Marketplace already installed error (non-blocking):**
The script handles this gracefully and continues. If you see "Marketplace appears to be already configured", subsequent operations will still work.

**Failed to add marketplace:**
```bash
# Common issues:
# 1. Invalid URL or GitHub path
# 2. Network connectivity issues
# 3. Marketplace repository doesn't exist

# Try manually:
cd /path/to/agent/working/dir
claude plugin marketplace add github:owner/repo
```

**Plugin install fails silently:**
```bash
which claude
claude --version
cd /path/to/agent/working/dir
claude plugin install my-plugin --scope local 2>&1
```

### Restart Issues

**Agent not restarting properly:**
```bash
aimaestro-agent.sh show backend-api
aimaestro-agent.sh hibernate backend-api
sleep 5
aimaestro-agent.sh wake backend-api
tmux ls
```

**Cannot restart current session:**
This is expected. You cannot restart your own session from within it.
- Exit Claude Code with `/exit` or Ctrl+C
- Run `claude` again in your terminal

**Wake fails after hibernate:**
```bash
tmux ls
curl http://localhost:23000/api/agents
tmux new-session -s backend-api
```

### API Issues

**API not responding:**
```bash
curl http://localhost:23000/api/hosts/identity
pm2 status ai-maestro
pm2 restart ai-maestro
```

**Agent not found:**
```bash
aimaestro-agent.sh list
curl http://localhost:23000/api/agents | jq '.agents[].name'
```

### Permission Issues

**Permission denied on agent directory:**
```bash
ls -la /path/to/agent/dir
sudo chown -R $(whoami) /path/to/agent/dir
```

**tmux session access denied:**
```bash
ls -la /tmp/tmux-*/
whoami
tmux ls
```

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| "Agent name required" | Missing agent argument | Add agent name/ID: `cmd <agent>` |
| "Agent working directory not found" | Directory deleted or moved | Update agent or recreate |
| "Working directory does not exist" | Directory path invalid | Check path exists |
| "Claude CLI is required" | claude not installed | Install: `npm i -g @anthropic-ai/claude-code` |
| "Failed to add marketplace" | Invalid source or network error | Check URL/path and network |
| "Session index must be a non-negative integer" | Invalid --index value | Use 0, 1, 2, etc. |
| "Cannot restart the current session" | Trying to restart self | Exit and restart manually |
| "Failed to get API base URL" | API configuration issue | Check AI Maestro is running |

---

## References

- [AI Maestro Documentation](https://github.com/23blocks-OS/ai-maestro)
- [Agent Registry Architecture](https://github.com/23blocks-OS/ai-maestro/blob/main/docs/AGENT-REGISTRY.md)
- [Plugin Development](https://github.com/23blocks-OS/ai-maestro/blob/main/docs/PLUGIN-DEVELOPMENT.md)
