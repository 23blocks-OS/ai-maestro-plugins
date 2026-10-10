# find-similar — Find related cases and runbooks

Searches INDEX.md, customer case history, and runbooks for similar issues to help identify patterns and existing solutions.

## Usage

```
/agentic-support find-similar <search-terms>
```

## What it does

1. **Searches INDEX.md** — Finds cases with matching keywords
2. **Searches runbooks** — Checks runbook titles and "When to Use"
3. **Searches customer history** — Looks for patterns in specific customer
4. **Ranks results** — Most relevant first
5. **Returns** — List of related cases and applicable runbooks

## Example

```bash
/agentic-support find-similar "204 empty response"
```

Returns:
```
Related Cases:
- S005 - Agent 204 responses - Intercambio (✅ RESOLVED)
- S001 - API 204 - Verilog (✅ RESOLVED)

Applicable Runbooks:
- R001 - Missing scopes cause 204 responses

Customer History for Intercambio:
- S005 - Agent 204 (scope issue)
- S002 - Identity registration 403 (scope issue)
→ Pattern: Scope-related issues
```

## Search locations

### 1. INDEX.md
- Case numbers and descriptions
- Customer names
- Status and dates

### 2. Runbooks
- Titles
- "When to Use" section
- Symptoms and error messages

### 3. Customer folders
- `_customer-info.md` support history
- Previous case files for same customer
- Recurring patterns

## Use cases

**Starting investigation:**
```bash
/agentic-support find-similar "authentication failed"
```
→ Check if we've seen this before

**Creating runbook:**
```bash
/agentic-support find-similar "scope missing"
```
→ See if runbook already exists

**Customer pattern analysis:**
```bash
/agentic-support find-similar "intercambio"
```
→ View customer's issue history

## Output format

```markdown
## Search Results for: "query terms"

### Related Cases (3 found)
1. S005 - Agent 204 responses - Intercambio (✅ RESOLVED 2026-10-10)
   Root cause: Missing agents:execute scope
   Location: customers/intercambio-ccenglish/S005-agent-204.md

2. S001 - Similar issue - Customer (🔴 OPEN)
   Status: Under investigation
   Location: inbound/S001-description.md

### Applicable Runbooks (1 found)
1. R001 - Missing scopes cause 204 responses
   Category: Authentication
   When to use: 204 empty responses, authorization failures
   Location: runbooks/R001-missing-scopes-204.md

### Customer Patterns
- Intercambio: 2 scope-related issues in past month
- Verilog: 1 authentication issue
```

## Pattern detection

When multiple cases share:
- Same customer → Customer-specific configuration issue
- Same error message → System-wide pattern (runbook candidate)
- Same service/component → Service health issue
- Same time period → Deployment or infrastructure change

## Notes

- Search is case-insensitive
- Searches descriptions, error messages, and symptoms
- Closed cases are included (they have solutions)
- Runbooks are prioritized in results (proven solutions)
