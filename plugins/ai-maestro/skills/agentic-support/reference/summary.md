# summary — Generate end-of-session summary

## Contents

- Usage
- What it does
- Example output
- When to generate
- Summary sections
- Uses for summaries
- Notes

Generates a summary of cases worked during the session, including what was resolved, what's pending, and what runbooks were created or used.

## Usage

```
/agentic-support summary
```

## What it does

1. **Lists cases worked** — All cases touched this session
2. **Shows resolutions** — Cases moved from inbound to customers
3. **Tracks runbooks** — Runbooks created or applied
4. **Flags pending** — Cases still in inbound
5. **Suggests next steps** — What needs follow-up

## Example output

```markdown
# Support Session Summary
**Date:** 2026-01-15  
**Duration:** 4 hours

## Cases Resolved (2)

### S005 - Checkout returns 500 - Acme Language School
- **Root Cause:** Missing orders:write scope in Auth DB
- **Solution:** Auth team added scopes Jan 14, payment gateway account funded
- **Commits:** a1b2c3d, e4f5a6b
- **Runbook Created:** R001 - Missing scope causes checkout 500
- **Status:** ✅ RESOLVED

### S002 - Login 403 - Acme Language School  
- **Root Cause:** sessions:write scope not granted to GUEST role
- **Solution:** Auth team verified scope exists and granted
- **Status:** ✅ RESOLVED

## Cases Pending (1)

### S004 - Login 403 - Globex Retail
- **Status:** 🔴 OPEN
- **Next Steps:** Verify Globex Retail GUEST role has sessions:write
- **Assigned:** Pending Auth team response
- **Priority:** P1

## Runbooks Created (1)

### R001 - Missing scope causes checkout 500
- **Category:** Authentication
- **Based on:** S005
- **Applicable to:** Any checkout 500 error with scope checks

## Knowledge Captured

- **Documentation Updated:** 
  - Created docs/REQUIRED_SCOPES.md
  - Updated support/customers/acme-language-school/_customer-info.md

- **Learnings:**
  - The API defines scope requirements; Auth implements them
  - Never remove scope checks to match Auth DB
  - An unpaid payment-gateway balance causes 429 rate limits system-wide

## Next Session Priorities

1. Follow up on S004 (Globex Retail) - waiting for Auth
2. Monitor Acme Language School for recurring issues
3. Consider preventive scopes audit for other customers
```

## When to generate

Generate summary:
- **End of work session** — Before signing off
- **Handoff to another person** — Context transfer
- **Weekly review** — Track resolution patterns
- **Post-mortem** — After major incident

## Summary sections

### Cases Resolved
- Case number, description, customer
- Root cause (one line)
- Solution (key changes)
- Links to commits, PRs, runbooks
- Status with resolution date

### Cases Pending  
- Case number, description, customer
- Current status
- Next steps needed
- Who's handling it
- Priority

### Runbooks Created/Used
- Runbook number and title
- What pattern it captures
- Which cases it applies to

### Knowledge Captured
- Documentation updated
- Key learnings
- Patterns discovered

### Next Steps
- Outstanding follow-ups
- Monitoring needed
- Preventive work identified

## Uses for summaries

1. **Handoff** — Next person knows exactly where things stand
2. **Metrics** — Track resolution time, recurring issues
3. **Learning** — Review what worked, what didn't
4. **Reporting** — Share progress with stakeholders
5. **Retrospectives** — Identify process improvements

## Notes

- Summaries are NOT committed to the repo (they're point-in-time)
- They can be shared via Slack, email, or standup
- Track time spent per case for capacity planning
- Note if cases took longer than expected (process issue?)
