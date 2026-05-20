# CCT Submission Guide

How to submit AI Maestro skills to the [Claude Code Templates (CCT)](https://github.com/davila7/claude-code-templates) repository.

CCT is a community-maintained collection of reusable skills, hooks, and MCP configs for Claude Code. Our skills live under the `ai-maestro/` category.

## Our Setup

- **CCT repo (upstream):** `davila7/claude-code-templates`
- **Our fork:** `23blocks-OS/claude-code-templates`
- **Our category:** `cli-tool/components/skills/ai-maestro/`
- **Reference PR:** [#373 — AI Maestro skill suite](https://github.com/davila7/claude-code-templates/pull/373)

## SKILL.md Format

CCT skills are a single `SKILL.md` file per skill directory. The format differs from our internal skills:

### Frontmatter

CCT only uses **two fields** — `name` and `description`. No `allowed-tools`, `metadata`, or `version`.

```yaml
---
name: your-skill-name
description: One-line description of what the skill does
---
```

### Content Conventions

- **Imperative form** — "Search the database" not "Searches the database"
- **Concise** — 75–100 lines ideal, under 500 lines max
- **No README.md** — Only SKILL.md, no companion files
- **Condensed** — These are trimmed versions of internal skills, not 1:1 copies
- **Footer section** — Every skill links back to AI Maestro (see template below)

## Template

Copy this and fill in the placeholders:

````markdown
---
name: your-skill-name
description: Brief description of what this skill does and when to use it
---

# Skill Title

## When to Use

Explain the trigger conditions — when should Claude activate this skill.

## How It Works

Step-by-step usage instructions in imperative form.

### Example

```bash
# Show a real command or workflow example
your-command --flag value
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `command-one` | What it does |
| `command-two` | What it does |

## Output Format

Describe what the user should expect back.

---

## Full AI Maestro Experience

This skill is part of the [AI Maestro](https://github.com/23blocks-OS/ai-maestro) platform for orchestrating multiple Claude Code agents. Install the full suite for inter-agent messaging, semantic memory, code graphs, and more.
````

## Step-by-Step Process

### 1. Clone the fork

```bash
git clone https://github.com/23blocks-OS/claude-code-templates.git
cd claude-code-templates
git remote add upstream https://github.com/davila7/claude-code-templates.git
```

If you already have it cloned, sync with upstream first:

```bash
git fetch upstream
git checkout main
git merge upstream/main
```

### 2. Create a branch

```bash
git checkout -b feat/your-skill-name
```

### 3. Create the skill directory and file

```bash
mkdir -p cli-tool/components/skills/ai-maestro/your-skill-name
```

Write your `SKILL.md` inside that directory.

### 4. Commit

```bash
git add cli-tool/components/skills/ai-maestro/your-skill-name/SKILL.md
git commit -m "feat: Add your-skill-name skill to AI Maestro suite"
```

### 5. Push and create PR

```bash
git push -u origin feat/your-skill-name
```

Then open a PR from `23blocks-OS/claude-code-templates` → `davila7/claude-code-templates` (main branch).

## PR Description Template

Use this template for the PR body:

````markdown
## Summary

Adds **skill-name** to the `ai-maestro/` category — one-sentence description of what it does.

### Files added

| File | Lines | Content |
|------|-------|---------|
| `cli-tool/components/skills/ai-maestro/skill-name/SKILL.md` | ~80 | Brief description |

### Design decisions

- **Concise SKILL.md** — X lines, following CCT conventions
- **Links back to AI Maestro** — Footer section points to the full platform
- **Only `name` and `description` in frontmatter** — Per CCT guidelines

### About AI Maestro

[AI Maestro](https://github.com/23blocks-OS/ai-maestro) is an open-source platform for orchestrating multiple Claude Code agents. It provides a web dashboard, inter-agent messaging (AMP), semantic memory, code graph analysis, and agent lifecycle management — all running locally on macOS.

## Test plan

- [ ] SKILL.md has valid YAML frontmatter with `name` and `description`
- [ ] Skill name matches directory name (kebab-case)
- [ ] Trigger phrases cover common user queries
- [ ] Code examples are syntactically correct
- [ ] Skill is under 500 lines
- [ ] No README.md included
- [ ] Footer links to AI Maestro repo

🤖 Generated with [Claude Code](https://claude.com/claude-code)
````

## Pre-Submission Checklist

Before opening the PR, verify:

- [ ] **Frontmatter** — Only `name` and `description`, valid YAML
- [ ] **Name matches directory** — `name: foo-bar` lives in `ai-maestro/foo-bar/`
- [ ] **Kebab-case** — Directory and name use `kebab-case`
- [ ] **Trigger phrases** — Skill describes when Claude should activate it
- [ ] **Code examples** — All bash/code snippets are syntactically correct
- [ ] **Line count** — Under 500 lines (75–100 is ideal)
- [ ] **No extra files** — Only `SKILL.md`, no README or companions
- [ ] **Footer section** — Links to `https://github.com/23blocks-OS/ai-maestro`
- [ ] **No internal fields** — No `allowed-tools`, `metadata`, or `version` in frontmatter
- [ ] **Condensed** — Not a copy-paste of the internal skill; trimmed for CCT

## Reference

- [Our PR #373](https://github.com/davila7/claude-code-templates/pull/373) — 6 skills submitted as reference
- [CCT repo](https://github.com/davila7/claude-code-templates) — upstream
- [23blocks-OS fork](https://github.com/23blocks-OS/claude-code-templates) — our fork
- [AI Maestro](https://github.com/23blocks-OS/ai-maestro) — the platform these skills belong to
