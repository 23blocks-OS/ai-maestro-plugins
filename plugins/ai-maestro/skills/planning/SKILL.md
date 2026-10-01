---
name: planning
description: Creates and manages persistent markdown planning files (task_plan.md, findings.md, progress.md) for complex task execution. Use when starting multi-step tasks, research projects, or any task requiring >5 tool calls. Solves the EXECUTION problem - staying focused during long-running tasks.
allowed-tools: Read Write Edit Bash Glob Grep
compatibility: Requires Bash shell access for file operations
user-invocable: true
metadata:
  author: 23blocks
  version: 1.1.0
---

# Planning Files

The context window is lost on `/clear`, compaction or a new session; files on disk are not. For a long task, keep the goal, what you have learned and where you are in three files, so you (or the next session) can pick up from them. This is about the current task; the memory-search skill covers what happened in earlier sessions.

Your in-session todo list is still the right place for step-by-step tracking. The files hold what must survive the session.

## Where the files go

`$AIMAESTRO_PLANNING_DIR` if set, otherwise `docs_dev/` in the project root (keeps the root clean). Start from the templates next to this file:

```bash
PLAN_DIR="${AIMAESTRO_PLANNING_DIR:-docs_dev}"
mkdir -p "$PLAN_DIR"
cp "${CLAUDE_SKILL_DIR}"/templates/{task_plan,findings,progress}.md "$PLAN_DIR"/
```

`${CLAUDE_SKILL_DIR}` is this skill's folder. If your agent does not expand it, the templates are in `templates/` beside this SKILL.md. If the files already exist, you are resuming: read them instead of overwriting.

| File | Holds | Update |
|------|-------|--------|
| `task_plan.md` | Goal, phases with checkboxes, decisions and why, errors and how they were resolved | When a phase completes or a decision is made |
| `findings.md` | What you learned: requirements, research, code facts, sources | When you learn something you would need after losing context |
| `progress.md` | Session log: actions, files changed, test results | At phase boundaries and before stopping |

Cut the template sections the task does not need, and replace the generic phases with the task's real ones.

## Using them

- **Starting a phase or resuming after a gap:** read `task_plan.md` (and the other two when resuming). This puts the goal back in context.
- **After viewing images, PDFs or browser pages:** write the relevant facts into `findings.md`; that content is the first to be lost when context is compacted.
- **When an attempt fails:** add it to the errors table with what you tried, so a later session does not repeat it. After three different failed approaches, stop and ask the user, listing what you tried.
- **Before stopping:** update `progress.md` and the phase checkboxes so the next session starts from the right place.

A quick way to see where things stand:

```bash
grep -nE '^\s*-\s*\[' "${AIMAESTRO_PLANNING_DIR:-docs_dev}/task_plan.md"
```

Skip this skill for questions, quick lookups and single-file edits.
