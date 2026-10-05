# Changelog

All notable changes to AI Maestro Plugins are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

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
