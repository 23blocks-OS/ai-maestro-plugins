---
name: agentic-support
description: Manage customer support cases with a written trail. Open a numbered case per customer report, record what was found, resolve it, and turn recurring problems into runbooks that are reused next time. Use when a customer reports a bug or problem, when documenting an incident, when creating a runbook for a recurring issue, or when checking a customer's support history.
allowed-tools: Read Write Edit Bash Glob Grep
user-invocable: true
metadata:
  author: 23blocks
  version: 1.0.1
---

# agentic-support

A skill for managing software support cases with systematic documentation, runbook creation, and knowledge capture. Cases are tracked in a file-based system with customer folders, sequential numbering, and reusable runbooks for common issues.

## First-Time Setup

On first invocation in a project, the skill auto-extracts these from `CLAUDE.md` if present, then asks for any missing values. Persist them to `.claude/agentic-support.yml` for the session.

| Variable | Purpose | Example |
|---|---|---|
| `{SUPPORT_DIR}` | Root directory for support cases | `support/` |
| `{INDEX_PATH}` | Case index file | `support/INDEX.md` |
| `{CUSTOMERS_DIR}` | Customer-specific case folders | `support/customers/` |
| `{INBOUND_DIR}` | Active/incoming issues | `support/inbound/` |
| `{RUNBOOKS_DIR}` | Reusable solution patterns | `support/runbooks/` |
| `{NEXT_CASE_NUMBER}` | Next available case number | `S005` |

## When to use this skill

- A customer reports a bug, issue, or support request
- You're investigating a production problem
- An incident needs to be documented
- A recurring issue needs a runbook
- You need to track support history per customer
- Post-mortem documentation after resolving an issue

Do NOT use this skill for:
- Feature requests (those go in product backlog)
- Internal code reviews (use code review process)
- General documentation (use project docs)

## Five Principles

1. **Every issue gets a case number.** From the moment you start investigating, create a case file. The sequential number (S001, S002...) becomes the permanent reference. No "I'll document it later" — the case file IS your working notes.

2. **Customer context is sacred.** Every customer folder has `_customer-info.md` with technical details, contacts, and schema/tenant info. When you touch a customer's case, read their info first — never assume configuration or deployment details.

3. **Runbooks capture institutional knowledge.** When you solve a problem that will happen again, create a runbook. The pattern isn't "fix and forget" — it's "fix, document, automate". Future incidents become "run runbook R003" instead of "re-derive the solution".

4. **Case lifecycle is explicit.** Cases flow: `inbound/` (investigating) → `customers/<name>/` (documented) → closed in INDEX.md. The location tells you the state. Never leave cases in inbound after resolution.

5. **Documentation is evidence, not narrative.** Record what you observed, what you tried, what worked. Timestamps, error messages, commit hashes. "Fixed the bug" is noise; "Commit a1b2c3d removed agents:execute check causing 204 responses" is signal.

## The Support Workflow

Pseudocode:

```
on customer issue reported:
  1. /agentic-support create
     → generates case number (e.g. S005)
     → creates inbound/S005-description.md
     → updates INDEX.md
  
  2. investigate and document findings in the case file
     → error messages, stack traces, reproduction steps
     → what you tried, what worked, what didn't
     → link to commits, PRs, logs
  
  3. /agentic-support find-similar
     → search INDEX.md and runbooks for related cases
     → if pattern exists, link to runbook
  
  4. if recurring pattern:
     /agentic-support runbook-create
     → captures solution pattern
     → adds to runbooks/ directory
     → future cases can reference it
  
  5. /agentic-support resolve
     → moves case from inbound/ to customers/<name>/
     → updates INDEX.md status
     → creates customer info if new customer
  
  6. /agentic-support summary
     → generates end-of-session summary
     → lists what was fixed, what's pending
```

## Sub-Commands

| Verb | Purpose | Reference |
|---|---|---|
| `create` | Create a new support case with sequential numbering, add to INDEX.md, place in inbound/ | [reference/create.md](reference/create.md) |
| `find-similar` | Search INDEX.md and runbooks for related cases or known patterns | [reference/find-similar.md](reference/find-similar.md) |
| `resolve` | Move case from inbound/ to customer folder, update status, create customer info if needed | [reference/resolve.md](reference/resolve.md) |
| `runbook-create` | Create a reusable runbook from a resolved case pattern | [reference/runbook-create.md](reference/runbook-create.md) |
| `runbook-run` | Execute a runbook's solution steps for a new case | [reference/runbook-run.md](reference/runbook-run.md) |
| `summary` | Generate end-of-session summary of cases worked | [reference/summary.md](reference/summary.md) |
| `audit` | Health-check the support system: orphan files, missing customer info, stale inbound cases | [reference/audit.md](reference/audit.md) |

## Case File Format

Every case file follows this structure:

```markdown
# S### - Brief Description

**Status:** 🔴 OPEN / ✅ RESOLVED  
**Customer:** Customer Name  
**Date Created:** YYYY-MM-DD  
**Date Resolved:** YYYY-MM-DD (if resolved)  
**Severity:** P0 (Critical) / P1 (High) / P2 (Medium) / P3 (Low)

## Issue Description

What the customer reported, in their words.

## Investigation

### Findings

What you discovered during investigation:
- Error messages (exact text)
- Log excerpts (with timestamps)
- Database queries and results
- Stack traces
- Reproduction steps

### Root Cause

The actual underlying problem, verified.

## Resolution

### Solution

What fixed it:
- Code changes (commit hashes, PR links)
- Configuration changes
- Database migrations
- Deployment steps

### Verification

How you confirmed it's fixed:
- Test results
- Customer confirmation
- Monitoring data

## Related

- Similar cases: S001, S012
- Runbooks used: R003
- Documentation updated: docs/troubleshooting.md
```

## Customer Info Format

Every customer folder has `_customer-info.md`:

```markdown
# Customer Name

**Customer Type:** End Client / Partner / Internal  
**Industry:** Industry/Sector  
**Product:** Product they use

## Contacts

**Technical Contact:**
- Name: Full Name
- Company: Company Name
- Email: email@example.com
- Role: Title/Role

## Technical Details

- **Tenant:** tenant_name
- **Schema:** schema_name
- **Company ID:** 123
- **Platform:** iOS / Android / Web
- **Environment:** Production / Staging

## Support History

- S001 - Issue description - STATUS (date)
- S002 - Issue description - STATUS (date)

## Notes

Any special considerations, quirks, or context.
```

## Runbook Format

Runbooks capture reusable solution patterns:

```markdown
# R### - Runbook Title

**Category:** Authentication / Database / API / Deployment  
**Frequency:** Common / Occasional / Rare  
**Last Updated:** YYYY-MM-DD

## When to Use

Describe the symptoms that indicate this runbook applies:
- Specific error messages
- Behavior patterns
- Log indicators

## Root Cause

The underlying problem this runbook addresses.

## Solution Steps

1. **Step 1**: What to do
   ```bash
   # Example command
   ```

2. **Step 2**: Next action
   ```ruby
   # Example code
   ```

3. **Verification**: How to confirm it worked
   ```bash
   # Verification command
   ```

## Prevention

How to prevent this issue in the future:
- Code changes
- Monitoring additions
- Documentation updates

## Related Cases

- S001 - Original case that discovered this pattern
- S015 - Another instance of this issue

## See Also

- Related runbooks: R004
- Documentation: docs/auth.md
```

## Anti-Patterns

These are the failure shapes that motivated this skill. Do not do them.

- **"I'll document it later."** No, you won't. Create the case file NOW and use it as your working notes. The act of writing clarifies thinking.
- **Skipping customer context.** Every customer has different configuration. Read `_customer-info.md` before touching anything.
- **Leaving cases in inbound forever.** Inbound is for active investigation. Resolve or close cases daily. Stale inbound is invisible broken windows.
- **"The fix is obvious, no runbook needed."** Today's obvious fix is tomorrow's forgotten tribal knowledge. If it happened once, it'll happen again.
- **Copy-pasting error messages without context.** Include timestamps, which user, what operation, what state. Raw error text alone is useless.
- **Treating runbooks as scripts.** Runbooks are guides with judgment calls, not automation. If it's fully automatable, make it a script and link it from the runbook.

## Implementation reference

The patterns behind these principles are documented in:
- [`reference/create.md`](reference/create.md) — Case creation and numbering
- [`reference/find-similar.md`](reference/find-similar.md) — Pattern matching
- [`reference/resolve.md`](reference/resolve.md) — Case resolution workflow
- [`reference/runbook-create.md`](reference/runbook-create.md) — Capturing reusable patterns
- [`reference/runbook-run.md`](reference/runbook-run.md) — Applying runbooks to new cases
