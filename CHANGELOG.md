# Changelog

All notable changes to AI Maestro Plugins are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.7.1] - 2026-10-10

### Fixed
- **The three skills added in 1.7.0 were audited** against Anthropic's current skill guidance and the current primary sources for their domains, and corrected at the source (their own repositories), which this plugin pulls in:
  - `agentic-sql` 1.1.0: removed a wrong CVE reference and added the real read-only bypass (Datadog, 2025-08-21); the SQL gate is a single-statement allow-list over the whole query; timeouts are set on the role instead of sent as a prefix; role hardening; the wrapper script is a stated prerequisite; data-handling rules; examples scrubbed.
  - `agentic-support` 1.1.0: **removed real customer names from the public examples**; customer text is treated as untrusted data; sensitive-data rules; search before investigating; severities defined; `audit --fix` needs approval.
  - `agentic-seo` 2.2.0: Google's AI-features guidance is summarized with its date instead of misattributed rules; FAQ and HowTo markup are no longer recommended (Google stopped showing FAQ rich results on 2026-05-07); `llms.txt` claims corrected; sitemap `priority` and `changefreq` removed; a neutral crawler-controls reference added.
  - All three: a contents list on every long reference file, one term per concept, copyable checklists.

## [1.7.0] - 2026-10-10

### Added
- **Three skills from their own repositories, pulled in at build time** (`plugin.manifest.json`, sources of type `git`), so one install gets them. Nothing is copied by hand; the next build picks up what is on each repository's `main`, as it does for the AMP skills.
  - **`agentic-sql`** (`23blocks-OS/agentic-sql`): run SQL against a production or staging database safely. Check the saved query library first, run only read-only queries, and save findings worth keeping.
  - **`agentic-support`** (`23blocks-OS/agentic-support`): manage customer support cases with a written trail, and turn recurring problems into runbooks.
  - **`agentic-seo`** (`23blocks-OS/agentic-seo`): audit, implement and optimize SEO, including structured data, llms.txt and a build audit script.
- Trigger evals for all three (11 cases): should-fire for a production lookup, a data audit, a customer-reported bug, a runbook request, an SEO audit and structured data; should-not-fire for counting files, looking up a function signature, explaining a JOIN or SEO, and a plain rename.

### Changed
- The skills' descriptions now say what each skill does and when to use it. `agentic-sql` no longer lists generic phrases such as "look up", "how many" and "audit" as triggers, which would have pulled a production-database skill into everyday requests. The fix is in each skill's own repository.
- The "no skill should fire" graders know the new skill names.

### Notes
- If you installed any of these by hand in `~/.claude/skills`, remove that copy so only one version is offered to the model.

## [1.6.0] - 2026-10-10

### Added
- **`aim-secret-management` skill.** Teaches an agent to use credentials without seeing them: ask the user with `aim-secret request NAME` (a card appears in the AI Maestro chat with a masked field; in Claude Code the secrets mod opens a form), end the turn, get told when it is stored, then run commands with `aim-secret exec --use NAME -- <command>`. Also covers what to do when a value is pasted into the conversation, and what never to do (read the vault, write a secret to a file, run `aim-secret set`). Needs AI Maestro 0.65.0 or later.
- Trigger evals for it: three should-fire cases (a key that is not set up, a pasted key, a stored token), a second pasted-credential case, and a should-not-fire case. On Sonnet, 5 runs each: 5/5 for the pasted-credential cases, 3/3 for the others. The first description fired on 2 of 3 pasted keys, so it now names that situation.

### Changed
- The "no skill should fire" graders know the new skill's name.

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
