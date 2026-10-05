# Changelog

All notable changes to AI Maestro Plugins are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.4.0] - 2026-10-05

### Changed
- **Status line row 2 matches the dashboard header** (`amp-statusline.sh`, from agentmessaging/claude-plugin#38): `model | ctx (+ /compact hint) | $cost | effort | cache warm Nm or cold | last turn Nm/h/d ago`, each part shown only when known. The line refreshes every 60 s while idle (`refreshInterval`, set by `--install`, existing installs updated without a prompt).
- **The status line reports the live session values** (session cost, context, effort, cache) to AI Maestro at `POST /api/agents/<id>/status-snapshot`, at most every 10 s, so the dashboard shows the same numbers as the terminal.

## [1.3.2] - 2026-10-05

### Changed
- **Status line row 1 shows the agent's name, address and folder** (`amp-statusline.sh`, from agentmessaging/claude-plugin#37): `name · address · folder | N unread`, with the home directory as `~`, shortened to fit the pane width (folder to its last two parts, then dropped, then the name). Row 2 is unchanged.

## [1.3.1] - 2026-10-05

### Added
- **AFP attachments in AMP.** `amp-send.sh --attach-afp` sends a `storage: "afp"` attachment (a reference to a file in an Agent Files Protocol space, no bytes through the provider). `amp-read`, `amp-inbox` and `amp-download` show AFP references and print the `afp-get.sh` hint. From agentmessaging/claude-plugin#36.

## [1.3.0] - 2026-10-05

### Added
- **agent-files skill and `afp-*.sh` scripts** (Agent Files Protocol, from agentmessaging/agent-files): put, get, ls, link, rm and capabilities against an S3-compatible store such as Garage.

## [1.0.1] - 2026-02-20

### Changed
- **Modular CLI architecture** -- Split `aimaestro-agent.sh` (3,879 lines) into 6 focused modules:
  - `agent-core.sh` -- Shared infrastructure: security scanning, validation, JSON editing, Claude CLI helpers
  - `agent-commands.sh` -- CRUD: list, show, create, delete, update, rename, export, import
  - `agent-session.sh` -- Session lifecycle: add, remove, exec, hibernate, wake, restart
  - `agent-skill.sh` -- Skill management: list, add, remove, install, uninstall
  - `agent-plugin.sh` -- Plugin management (10 subcommands) + marketplace (4 subcommands)
  - `aimaestro-agent.sh` -- Thin 108-line dispatcher that sources all modules
- Each module has a double-source guard and uses the fallback path pattern (`SCRIPT_DIR` then `~/.local/bin/`)
- No functional changes -- all commands work identically

## [1.0.0] - 2026-02-09

### Added
- Initial plugin release with 6 skills and CLI scripts
- Agent lifecycle management (create, delete, hibernate, wake, rename, export, import)
- Plugin and marketplace management (install, uninstall, update, enable, disable)
- Skill management (list, add, remove, install, uninstall)
- AMP messaging integration
- Code graph querying
- Memory search
- Documentation search
- Planning skill with persistent task tracking
- ToxicSkills security scanner for skill installation
- Auto-trust mechanism for agent creation
- `AIM_AGENT_*` environment variables (replacing `CLAUDE_AGENT_*` with backward compat)
