---
name: ai-maestro-agents-management
description: Creates, manages, and orchestrates AI agents using the AI Maestro CLI, including which account, subscription token or API key each agent runs on. Use when the user asks to "create agent", "list agents", "delete agent", "rename agent", "hibernate agent", "wake agent", "install plugin", "show agent", "export agent", "restart agent", "install marketplace", "run doctor" or "check agent health", to move agents to another account or key, or for any agent lifecycle management task.
allowed-tools: Bash
compatibility: Requires AI Maestro (aimaestro.dev) with Bash shell access
metadata:
  author: 23blocks
  version: 2.2.0
---

# AI Maestro Agent Management

`aimaestro-agent.sh` manages agents on this AI Maestro host: lifecycle, sessions, plugins, skills, export/import. `<agent>` accepts a name or an id. To talk to another agent, use the agent-messaging skill instead. Every command takes `-h` for its full options.

## Lifecycle

```bash
aimaestro-agent.sh list [--status online|offline|hibernated|all] [--format table|json|names] [-q] [--json]
aimaestro-agent.sh show <agent> [--format pretty|json]

aimaestro-agent.sh create <name> --dir <absolute-path> [-p <program>] [-m <model>] [-t "<task>"] \
    [--tags a,b] [-T <trust-level>] [--credential <kind> ...] [--no-session] [--no-folder] [--force-folder] [-- <program-args>...]
aimaestro-agent.sh update <agent> [-t "<task>"] [-m <model>] [--tags a,b] [--add-tag x] [--remove-tag x] [--args "<program-args>"] [--credential <kind> ...]
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

## Model access: which account an agent uses

Each Claude Code agent has a model access setting. AI Maestro applies it when it starts the agent, reading the key from the vault (`aim-secret`), so the value is never in a file or in the terminal.

| `--credential` | Uses | Also needs |
|---|---|---|
| `host-login` | this computer's own `/login` (the default) | nothing |
| `oauth-token` | a subscription token from `claude setup-token` | `--secret NAME` |
| `api-key` | an Anthropic API key | `--secret NAME` |
| `gateway` | a bearer key on another endpoint (OpenRouter and similar) | `--secret NAME --base-url https://... [--cred-model <id>]` |
| `config-dir` | a separate Claude config folder logged in to another account | `--dir <path>` on `update` and `credential switch`, `--cred-dir <path>` on `create` |

`--account "<text>"` records whose account or plan it is; people see it on the card. `--secret` is always the vault entry's NAME. If the key is not in the vault yet, have the user store it (aim-secret-management skill); never ask for the value.

```bash
aimaestro-agent.sh create ops-1 --dir ~/Code/ops --credential oauth-token --secret ACME_MAX_TOKEN --account "Acme Max plan"
aimaestro-agent.sh update ops-1 --credential api-key --secret ACME_API_KEY          # applied at its next wake
aimaestro-agent.sh credential switch ops-1 ops-2 --credential host-login --restart
aimaestro-agent.sh credential switch --crew team:ops --credential oauth-token --secret ACME_MAX_TOKEN --restart
```

- A change takes effect only when the agent starts again. `--restart` restarts idle agents at once; an agent at work is skipped and named, and keeps its old account until it is restarted. To reset an agent onto its account, `restart` it (or `hibernate` then `wake`).
- Claude Code ignores `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CONFIG_DIR` in a project's `.claude/settings*.json` `env` block, and an old `ANTHROPIC_API_KEY` there wins over the setting. Never put a credential there. `create`, `update` and `wake` print a warning when such a file would defeat the choice; remove the entry.
- Check what the running session really uses, not what a file says:

```bash
curl -s "http://localhost:23000/api/agents/<agent-id>/credential" | jq '{description, warnings, check}'
```

`check.state` is `match` (running on the chosen account), `mismatch` (the session uses another account; restart it and read the warnings), `unverified` (AI Maestro did not start this session with the setting; restart it), or null when the agent is not running. An agent's own report of its settings file is not proof.

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

## Health check

```bash
aimaestro-agent.sh doctor [--all] [--json]   # this host's checks (agents, install, peers); --all: every enabled host
```

It exits 1 when a check fails. Fixes are offered in Settings → Doctor, not by the CLI.

## Troubleshooting

- Agent not found: check `aimaestro-agent.sh list --status all`.
- `command not found`: run `./install-agent-cli.sh` from the AI Maestro checkout; the script and its `agent-*.sh` modules live in `~/.local/bin`.
- API errors: AI Maestro must be running on this host (port 23000).

Output formats, scope locations, scenarios and an error table are in [references/REFERENCE.md](references/REFERENCE.md).
