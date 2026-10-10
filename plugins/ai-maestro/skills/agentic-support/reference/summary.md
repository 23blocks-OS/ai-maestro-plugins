# summary — Generate end-of-session summary

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
**Date:** 2026-10-10  
**Duration:** 4 hours

## Cases Resolved (2)

### S005 - Agent 204 responses - Intercambio (CCEnglish)
- **Root Cause:** Missing agents:execute scope in Auth DB
- **Solution:** Auth team added scopes Oct 9, OpenAI account funded
- **Commits:** 986bce51, f48f52d0
- **Runbook Created:** R001 - Missing scopes cause 204 responses
- **Status:** ✅ RESOLVED

### S002 - Identity registration 403 - Intercambio (CCEnglish)  
- **Root Cause:** identities:write scope not granted to GUEST role
- **Solution:** Auth team verified scope exists and granted
- **Status:** ✅ RESOLVED

## Cases Pending (1)

### S004 - Identity registration 403 - Verilog
- **Status:** 🔴 OPEN
- **Next Steps:** Verify Verilog GUEST role has identities:write
- **Assigned:** Pending Auth team response
- **Priority:** P1

## Runbooks Created (1)

### R001 - Missing scopes cause 204 responses
- **Category:** Authentication
- **Based on:** S005
- **Applicable to:** Any 204 empty response with scope checks

## Knowledge Captured

- **Documentation Updated:** 
  - Created docs/REQUIRED_SCOPES.md
  - Updated support/customers/intercambio-ccenglish/_customer-info.md

- **Learnings:**
  - Jarvis defines scope requirements; Auth implements them
  - Never remove scope checks to match Auth DB
  - OpenAI debt causes 429 rate limits system-wide

## Next Session Priorities

1. Follow up on S004 (Verilog) - waiting for Auth
2. Monitor CCEnglish for recurring issues
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
