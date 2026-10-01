---
name: ai-maestro-agents-management
description: Creates, manages, and orchestrates AI agents using the AI Maestro CLI. Use when the user asks to "create agent", "list agents", "delete agent", "rename agent", "hibernate agent", "wake agent", "install plugin", "show agent", "export agent", "restart agent", "install marketplace", or any agent lifecycle management task.
allowed-tools: Bash
compatibility: Requires AI Maestro (aimaestro.dev) with Bash shell access
metadata:
  author: 23blocks
  version: 2.1.0
---

# AI Maestro Agent Management

`aimaestro-agent.sh` manages agents on this AI Maestro host: lifecycle, sessions, plugins, skills, export/import. `<agent>` accepts a name or an id. To talk to another agent, use the agent-messaging skill instead. Every command takes `-h` for its full options.

## Lifecycle

```bash
aimaestro-agent.sh list [--status online|offline|hibernated|all] [--format table|json|names] [-q] [--json]
aimaestro-agent.sh show <agent> [--format pretty|json]

aimaestro-agent.sh create <name> --dir <absolute-path> [-p <program>] [-m <model>] [-t "<task>"] \
    [--tags a,b] [-T <trust-level>] [--no-session] [--no-folder] [--force-folder] [-- <program-args>...]
aimaestro-agent.sh update <agent> [-t "<task>"] [-m <model>] [--tags a,b] [--add-tag x] [--remove-tag x] [--args "<program-args>"]
aimaestro-agent.sh rename <old> <new> [--rename-session] [--rename-folder] [-y]
aimaestro-agent.sh delete <agent> --confirm

aimaestro-agent.sh hibernate <agent>
aimaestro-agent.sh wake <agent> [--attach] [-T <trust-level>]
aimaestro-agent.sh restart <agent> [--wait <seconds>]     # hibernate, wait (default 3s), wake

aimaestro-agent.sh session add <agent> [--role <role>]
aimaestro-agent.sh session remove <agent> [--index <n>] [--all]
aimaestro-agent.sh session exec <agent> <command...>
```

- `create` makes the folder, runs `git init`, writes a CLAUDE.md template, registers the agent and starts its tmux session. `--dir` is required, and `create` fails if the folder already exists unless you pass `--force-folder` (use it for an existing project). Program defaults to Claude Code.
- Trust levels: `supervised` (default), `planOnly`, `trustEdits`, `smartAuto`, `fullAutonomy`. On `wake`, `-T` applies to that session only.
- `delete` kills the agent's sessions, marks it deleted in the registry and removes its AMP messaging directory; the project folder stays. `--keep-folder` and `--keep-data` are accepted but not yet honoured by the server. Confirm with the user before deleting.
- `restart` cannot restart the session you are running in.

## Plugins and marketplaces

```bash
aimaestro-agent.sh plugin install|uninstall|update|reinstall|enable|disable <agent> <plugin> [-s user|project|local]
aimaestro-agent.sh plugin list <agent>
aimaestro-agent.sh plugin load <agent> <path>...          # this session only; not persisted, not in `list`
aimaestro-agent.sh plugin validate <agent> <plugin-path>
aimaestro-agent.sh plugin clean <agent> [-n]              # remove orphaned caches; -n = dry run
aimaestro-agent.sh plugin marketplace list <agent>
aimaestro-agent.sh plugin marketplace add <agent> <source> [--no-restart]
aimaestro-agent.sh plugin marketplace remove <agent> <name> [-f]
aimaestro-agent.sh plugin marketplace update <agent> [<name>]
```

`install` also accepts `--no-restart`; `uninstall` accepts `-f`. Marketplace sources: `owner/repo`, `github:owner/repo`, an HTTPS or SSH git URL (optionally `#branch` or `#tag`), a local directory, or a URL. Installing a plugin or marketplace on another agent restarts that agent so the change loads; on your own agent the script prints instructions instead, and Claude Code has to be restarted by hand.

## Skills

```bash
aimaestro-agent.sh skill install <agent> <.skill|.zip|folder> [-s user|project|local] [--name <name>]
aimaestro-agent.sh skill uninstall <agent> <skill-name> [-s user|project|local]
aimaestro-agent.sh skill list <agent>
aimaestro-agent.sh skill add <agent> <skill-id> [--type marketplace|custom] [--path <path>]
aimaestro-agent.sh skill remove <agent> <skill-id>
```

`install`/`uninstall` place files under `.claude/skills/`; `list`/`add`/`remove` only change what the AI Maestro registry records. Skills that came with a plugin are managed through `plugin`.

## Export and import

```bash
aimaestro-agent.sh export <agent> [-o <file>]             # default <agent>.agent.json, configuration only
aimaestro-agent.sh import <file> [--name <new-name>] [--dir <new-dir>]
```

## Troubleshooting

- Agent not found: check `aimaestro-agent.sh list --status all`.
- `command not found`: run `./install-agent-cli.sh` from the AI Maestro checkout; the script and its `agent-*.sh` modules live in `~/.local/bin`.
- API errors: AI Maestro must be running on this host (port 23000).

Output formats, scope locations, scenarios and an error table are in [references/REFERENCE.md](references/REFERENCE.md).
