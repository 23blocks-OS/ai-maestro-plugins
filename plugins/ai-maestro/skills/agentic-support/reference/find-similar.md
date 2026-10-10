# find-similar — Find related cases and runbooks

## Contents

- Usage
- What it does
- Example
- Search locations
- Use cases
- Output format
- Pattern detection
- Notes

The first step of every case: search INDEX.md, customer case history, and runbooks before investigating. If a runbook matches, reuse it and link it from the case; if it was wrong or incomplete, fix the runbook.

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
/agentic-support find-similar "checkout 500 error"
```

Returns:
```
Related Cases:
- S005 - Checkout returns 500 - Acme Language School (✅ RESOLVED)
- S001 - API 500 - [customer B] (✅ RESOLVED)

Applicable Runbooks:
- R001 - Missing scope causes checkout 500

Customer History for Acme Language School:
- S005 - Checkout 500 (scope issue)
- S002 - Login 403 (scope issue)
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

**Before investigating (always):**
```bash
/agentic-support find-similar "authentication failed"
```
→ Check if we've seen this before

**Before creating a runbook:**
```bash
/agentic-support find-similar "scope missing"
```
→ See if runbook already exists

**Customer pattern analysis:**
```bash
/agentic-support find-similar "acme"
```
→ View customer's issue history

## Output format

```markdown
## Search Results for: "query terms"

### Related Cases (3 found)
1. S005 - Checkout returns 500 - Acme Language School (✅ RESOLVED 2026-01-15)
   Root cause: Missing orders:write scope
   Location: customers/acme-language-school/S005-checkout-500.md

2. S001 - Similar issue - Customer (🔴 OPEN)
   Status: Under investigation
   Location: inbound/S001-description.md

### Applicable Runbooks (1 found)
1. R001 - Missing scope causes checkout 500
   Category: Authentication
   When to use: checkout 500 errors, authorization failures
   Location: runbooks/R001-missing-scope-checkout-500.md

### Customer Patterns (other customers anonymized)
- Acme Language School: 2 scope-related issues in past month
- [customer B]: 1 authentication issue
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
- Anonymize customer names, ids and contacts in the output when it is shared outside the customer's own folder; never name other customers
- Runbooks are prioritized in results (proven solutions)
