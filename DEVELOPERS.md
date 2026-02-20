# AI Maestro Plugin Builder — Developer Guide

Advanced documentation for building, customizing, and contributing to AI Maestro plugins.

## How It Works

```
plugin.manifest.json          Your recipe — what goes into the plugin
       |
  build-plugin.sh             The assembler — fetches sources, applies mappings
       |
  plugins/ai-maestro/         The output — a ready-to-install Claude Code plugin
```

**`plugin.manifest.json`** defines your sources. Each source can be:
- **`local`** — Your own skills and scripts in `src/`
- **`git`** — Any public (or private) Git repo

The builder clones each git source, copies files according to the `map` rules, and produces a single self-contained plugin in `plugins/ai-maestro/`.

**GitHub Actions** runs the build automatically when you push changes to `src/`, `plugin.manifest.json`, or `build-plugin.sh`. The built output is committed back to the repo, so `plugins/ai-maestro/` is always up to date.

## Quick Start: Build Your Own Plugin

### 1. Fork this repo

```bash
# Fork on GitHub, then clone your fork
git clone https://github.com/YOUR-USERNAME/ai-maestro-plugins.git
cd ai-maestro-plugins
```

### 2. Edit `plugin.manifest.json`

This is the default manifest — it pulls from local `src/` and the AMP messaging repo:

```json
{
  "name": "ai-maestro",
  "version": "1.0.0",
  "output": "./plugins/ai-maestro",
  "sources": [
    {
      "name": "core",
      "type": "local",
      "path": "./src",
      "map": {
        "skills/*": "skills/",
        "scripts/*": "scripts/",
        "hooks/*": "hooks/"
      }
    },
    {
      "name": "amp-messaging",
      "type": "git",
      "repo": "https://github.com/agentmessaging/claude-plugin.git",
      "ref": "main",
      "map": {
        "skills/messaging": "skills/agent-messaging",
        "scripts/*.sh": "scripts/"
      }
    }
  ]
}
```

Add, remove, or modify sources to build exactly the plugin you want.

### 3. Build

```bash
./build-plugin.sh --clean
```

### 4. Install

```bash
# Install the built plugin into Claude Code
claude plugin install ./plugins/ai-maestro
```

Or push to your fork and let CI build it — then install directly from GitHub.

## Examples

### Add a skill from any GitHub repo

Say someone published a `code-review` skill at `github.com/alice/claude-skills`. Add it as a source:

```json
{
  "sources": [
    { "...existing sources..." },
    {
      "name": "alice-code-review",
      "type": "git",
      "repo": "https://github.com/alice/claude-skills.git",
      "ref": "main",
      "map": {
        "skills/code-review": "skills/code-review"
      }
    }
  ]
}
```

Build, and now your plugin includes Alice's code-review skill alongside everything else.

### Pull scripts from a private repo

For teams with internal tools:

```json
{
  "name": "acme-deploy-tools",
  "type": "git",
  "repo": "git@github.com:acme-corp/claude-deploy-scripts.git",
  "ref": "v2.1.0",
  "map": {
    "scripts/*.sh": "scripts/",
    "skills/deploy": "skills/deploy"
  }
}
```

Pin to a tag (`v2.1.0`) for stability, or use `main` to track latest.

### Remove skills you don't need

Don't use memory search or graph queries? Delete them from `src/skills/` and rebuild. Your plugin only includes what you keep.

```bash
rm -rf src/skills/memory-search src/skills/graph-query
./build-plugin.sh --clean
```

### Compose multiple third-party sources

Build a plugin from 5 different repos:

```json
{
  "sources": [
    { "name": "core", "type": "local", "path": "./src", "map": { "skills/*": "skills/", "scripts/*": "scripts/", "hooks/*": "hooks/" } },
    { "name": "amp", "type": "git", "repo": "https://github.com/agentmessaging/claude-plugin.git", "ref": "main", "map": { "skills/messaging": "skills/agent-messaging", "scripts/*.sh": "scripts/" } },
    { "name": "devops-skills", "type": "git", "repo": "https://github.com/someorg/devops-skills.git", "ref": "main", "map": { "skills/*": "skills/" } },
    { "name": "security-scanner", "type": "git", "repo": "https://github.com/another/security-tools.git", "ref": "v1.0", "map": { "skills/scanner": "skills/security-scanner" } },
    { "name": "team-scripts", "type": "git", "repo": "git@github.com:mycompany/internal-scripts.git", "ref": "main", "map": { "scripts/*.sh": "scripts/" } }
  ]
}
```

Each person on the team can fork and adjust — one developer adds the security scanner, another swaps in different devops skills. Same builder, different plugins.

### Create your own skills

Create a skill in `src/skills/`:

```bash
mkdir -p src/skills/my-custom-skill
cat > src/skills/my-custom-skill/SKILL.md << 'EOF'
---
name: my-custom-skill
description: Does something useful for my workflow
allowed-tools: Bash, Read, Write
---

# My Custom Skill

Instructions for Claude on how to use this skill...
EOF
```

Push, CI builds, your skill is now part of the plugin.

## Manifest Reference

### Source types

| Type | Description | Required fields |
|------|-------------|-----------------|
| `local` | Files from your repo | `path`, `map` |
| `git` | Clone from any Git repo | `repo`, `map`, optional `ref` |

### Map rules

Maps control what files from each source end up in the plugin:

```json
"map": {
  "skills/*": "skills/",           // Copy all skill dirs to skills/
  "scripts/*.sh": "scripts/",      // Copy all .sh files to scripts/
  "skills/foo": "skills/bar",      // Rename: foo -> bar
  "hooks/*": "hooks/"              // Copy hooks
}
```

- **Glob patterns** (`*`) copy matching files into the target directory
- **Direct paths** copy or rename a single directory/file
- Source paths are relative to the source root
- Target paths are relative to the plugin output directory

## CI/CD

The GitHub Actions workflow (`.github/workflows/build-plugin.yml`) triggers on:
- Push to `main` that changes `src/`, `plugin.manifest.json`, or `build-plugin.sh`
- Manual trigger via `workflow_dispatch`

It runs `./build-plugin.sh --clean`, verifies the output, and commits `plugins/ai-maestro/` back to the repo. This means the built plugin in the repo is always in sync with the manifest.

**For forks:** The workflow runs in your fork too. Push a manifest change, CI builds your custom plugin, and commits the result. No local build needed.

## Default Plugin Contents

The official manifest produces a plugin with:

**6 Skills:** agent-messaging, agents-management, docs-search, graph-query, memory-search, planning

**44 Scripts** including:
- Agent CLI (`aimaestro-agent.sh` + 6 modules) — create, manage, hibernate, wake agents
- AMP messaging (`amp-*.sh`) — inter-agent communication
- Code graph, docs search, memory search tools

**1 Hook** — session tracking

## CLI Module Structure

The `aimaestro-agent.sh` CLI is split into focused modules:

| Module | Purpose |
|--------|---------|
| `aimaestro-agent.sh` | Thin dispatcher, sources all modules |
| `agent-helper.sh` | Colors, print helpers, agent resolution, API base |
| `agent-core.sh` | Security scanning, validation, JSON editing, Claude CLI |
| `agent-commands.sh` | CRUD: list, show, create, delete, update, rename, export, import |
| `agent-session.sh` | Session add/remove/exec, hibernate, wake, restart |
| `agent-skill.sh` | Skill list/add/remove/install/uninstall |
| `agent-plugin.sh` | Plugin (10 subcommands) + marketplace (4 subcommands) |

## Requirements

- macOS or Linux
- Bash 4.0+, jq, curl, git
- tmux 3.0+ (for agent management)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## License

MIT
