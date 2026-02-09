# AI Maestro Plugins for Claude Code

Official plugin marketplace for [AI Maestro](https://github.com/23blocks-OS/ai-maestro) — the AI agent orchestration platform.

## Quick Install

```bash
# Add marketplace and install in one step
/install 23blocks-OS/ai-maestro-plugins
/install ai-maestro@ai-maestro-plugins
```

That's it. You get 6 skills, 39 scripts, and 3 hooks.

## What's Included

| Skill | Description | Standalone? |
|-------|-------------|-------------|
| `memory-search` | Search conversation history | No |
| `docs-search` | Search auto-generated documentation | No |
| `graph-query` | Query code graph relationships | No |
| `agent-messaging` | AMP messaging between agents | No |
| `ai-maestro-agents-management` | Manage AI agents | No |
| `planning` | Task planning with persistent markdown files | **Yes** |

Skills marked "No" require the AI Maestro service running on localhost:23000.

## Build Your Own Plugin

This repo is also a **build system**. The pre-built plugin at `plugins/ai-maestro/` is assembled from sources declared in `plugin.manifest.json`.

### How it works

```
plugin.manifest.json     declares sources (local dirs, git repos)
        |
  build-plugin.sh        fetches sources, assembles output
        |
  plugins/ai-maestro/    self-contained plugin (what users install)
```

### Build from source

```bash
git clone https://github.com/23blocks-OS/ai-maestro-plugins.git
cd ai-maestro-plugins
./build-plugin.sh --clean
```

### Customize it

Fork this repo, edit `plugin.manifest.json` to pick the skills you want:

```json
{
  "name": "my-custom-agents",
  "version": "1.0.0",
  "output": "./plugins/my-custom-agents",
  "plugin": {
    "name": "my-custom-agents",
    "version": "1.0.0",
    "author": { "name": "you" }
  },
  "sources": [
    {
      "name": "ai-maestro-planning",
      "type": "git",
      "repo": "https://github.com/23blocks-OS/ai-maestro-plugins.git",
      "ref": "main",
      "map": {
        "src/skills/planning": "skills/planning"
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
    },
    {
      "name": "my-skills",
      "type": "local",
      "path": "./my-stuff",
      "map": {
        "skills/*": "skills/",
        "scripts/*": "scripts/"
      }
    }
  ]
}
```

Then `./build-plugin.sh --clean` and you have a custom plugin.

### Repo structure

```
ai-maestro-plugins/
├── plugin.manifest.json           # what to build (sources + mappings)
├── build-plugin.sh                # assembles plugins/ from manifest
├── .github/workflows/             # CI: auto-rebuild on push
│
├── src/                           # OUR source files
│   ├── skills/                    #   5 skills (graph, memory, docs, planning, agents)
│   ├── scripts/                   #   26 scripts (graph, docs, memory, agent mgmt)
│   └── hooks/                     #   session tracking hooks
│
├── .claude-plugin/marketplace.json  # makes this a valid marketplace
└── plugins/ai-maestro/              # BUILD OUTPUT (pre-built, committed)
    ├── .claude-plugin/plugin.json
    ├── skills/                      # all 6 skills assembled
    ├── scripts/                     # all 39 scripts assembled
    └── hooks/
```

`src/` = our code. `plugins/` = build output. CI keeps them in sync.

External sources (like AMP messaging) are fetched from their repos at build time — no manual copying, no stale snapshots.

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
