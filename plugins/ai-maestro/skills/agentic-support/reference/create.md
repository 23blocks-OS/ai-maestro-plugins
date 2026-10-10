# create — Create a new support case

Creates a new support case with sequential numbering, adds it to INDEX.md, and places the case file in the inbound directory for investigation.

## Usage

```
/agentic-support create <customer-name> <brief-description>
```

## What it does

1. **Generates case number** — Reads `{INDEX_PATH}` to find the next available case number (e.g., S005)
2. **Creates case file** — Creates `{INBOUND_DIR}/S###-description.md` with template
3. **Updates INDEX** — Adds entry to `{INDEX_PATH}` with status 🔴 OPEN
4. **Returns case number** — Outputs the case number for reference

## Example

```bash
/agentic-support create intercambio-ccenglish "Agent responses returning 204"
```

Creates:
- File: `support/inbound/S005-agent-204-responses.md`
- INDEX entry: `| S005 | 2026-10-10 | Intercambio (CCEnglish) | Agent 204 responses | 🔴 OPEN |`

## Case file template

The created file follows this structure:

```markdown
# S### - Brief Description

**Status:** 🔴 OPEN  
**Customer:** Customer Name  
**Date Created:** YYYY-MM-DD  
**Severity:** P1 (set appropriately)

## Issue Description

(Paste customer's report here)

## Investigation

### Findings

(Document your investigation here)

### Root Cause

(To be determined)

## Resolution

(To be filled when resolved)
```

## After creation

1. **Fill in details** — Add customer's exact report to Issue Description
2. **Set severity** — P0 (critical), P1 (high), P2 (medium), P3 (low)
3. **Document as you investigate** — Use the case file as your working notes
4. **Search for similar** — Run `/agentic-support find-similar` to check for related cases

## Notes

- Case numbers are sequential and never reused
- Cases start in `inbound/` and move to `customers/<name>/` when resolved
- The case file name is derived from the description (kebab-case)
- Always include customer name for proper organization
