# AI Maestro Plugin Builder

**Build the exact set of skills your AI agent needs.**

Remember when Neo sat in that chair and Trinity uploaded Kung Fu straight into his brain? Ten seconds later: *"I know Kung Fu."*

That's what this does for your Claude Code agents.

You pick the skills. You pick the scripts. You build a custom plugin. You install it. Your agent wakes up knowing everything you gave it.

## What's a Skill?

A skill is a capability you load into your agent. Out of the box, AI Maestro comes with:

| Skill | What your agent can do |
|-------|----------------------|
| **Agent Messaging** | Send and receive messages to other agents |
| **Agent Management** | Create, rename, hibernate, wake up other agents |
| **Memory Search** | Search through past conversations and remember context |
| **Code Graph** | Understand how your codebase is connected |
| **Docs Search** | Search auto-generated documentation |
| **Planning** | Break down complex tasks and track progress |

But here's the thing — **you're not stuck with this list.**

## The Idea

This repo is not a plugin you install as-is. It's a **plugin builder**.

Fork it. Edit one file. Pick the skills you want from anywhere — your own, your team's, some random genius on GitHub. The builder assembles them into one plugin, tailored to your agent.

**Your agent. Your skills. Your call.**

## How It Works

```
1. Fork this repo
2. Edit plugin.manifest.json    ← pick your skills
3. Push (or run ./build-plugin.sh)
4. Install the plugin
5. Your agent knows Kung Fu
```

The manifest is your recipe. Want to add a code-review skill someone published on GitHub? Add three lines. Don't need memory search? Delete one line. Want to pull in your company's private deploy scripts? Add three lines.

CI builds automatically on push. You never run a build command if you don't want to.

## Quick Start

```bash
# 1. Fork on GitHub, then:
git clone https://github.com/YOUR-USERNAME/ai-maestro-plugins.git
cd ai-maestro-plugins

# 2. (Optional) Edit plugin.manifest.json to customize

# 3. Build
./build-plugin.sh --clean

# 4. Install into Claude Code
claude plugin install ./plugins/ai-maestro
```

That's it. Your agent now has every skill in the manifest.

## Want to Add a Skill from GitHub?

Say someone published an amazing `code-review` skill. Open `plugin.manifest.json` and add:

```json
{
  "name": "code-review",
  "type": "git",
  "repo": "https://github.com/alice/claude-skills.git",
  "ref": "main",
  "map": { "skills/code-review": "skills/code-review" }
}
```

Build. Install. Now your agent reviews code.

## Want to Remove a Skill?

Delete the folder from `src/skills/` and rebuild. Your plugin only includes what you keep.

## Want to Create Your Own Skill?

Create a folder in `src/skills/` with a `SKILL.md` file that tells Claude what to do. Push. CI builds. Done.

This is how every skill works — it's just a markdown file with instructions. No SDK. No framework. Just words that tell your agent what it's capable of.

## The Big Picture

Every AI agent is different because every project is different. A backend agent needs deploy scripts and database tools. A frontend agent needs design systems and accessibility checkers. A research agent needs web search and document analysis.

One-size-fits-all plugins don't work.

This builder lets you assemble exactly the right set of capabilities for each agent you run. Mix skills from open source repos, private team repos, and your own `src/` folder — all into one plugin.

Same builder. Different agents. Different superpowers.

## Requirements

- macOS or Linux
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 4.0+, git, jq

## Learn More

- **[DEVELOPERS.md](./DEVELOPERS.md)** — Manifest reference, CI/CD setup, CLI architecture, advanced customization
- **[CHANGELOG.md](./CHANGELOG.md)** — Release history

## License

MIT
