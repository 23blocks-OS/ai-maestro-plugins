# resolve — Resolve a support case

Moves a case from inbound/ to the customer's folder, updates INDEX.md status, creates customer info if needed, and marks the case as resolved.

## Usage

```
/agentic-support resolve <case-number>
```

## What it does

1. **Verifies resolution** — Checks that the case file has Resolution section filled
2. **Creates customer folder** — If new customer, creates `{CUSTOMERS_DIR}/<customer-name>/`
3. **Creates customer info** — If missing, creates `_customer-info.md` template
4. **Moves case file** — Moves from `inbound/` to `customers/<name>/S###-description.md`
5. **Updates INDEX** — Changes status to ✅ RESOLVED with resolution date
6. **Updates customer info** — Adds case to customer's support history

## Example

```bash
/agentic-support resolve S005
```

Result:
- Moves: `inbound/S005-agent-204.md` → `customers/intercambio-ccenglish/S005-agent-204.md`
- Updates INDEX: `| S005 | ... | ✅ RESOLVED (2026-10-10) |`
- Adds to customer info: `- S005 - Agent 204 responses - ✅ RESOLVED (2026-10-10)`

## Prerequisites

Before resolving, ensure the case file has:

- ✅ **Root Cause** identified
- ✅ **Solution** documented (commits, PRs, changes)
- ✅ **Verification** steps completed
- ✅ Date Resolved field filled

## Customer info creation

If the customer folder doesn't exist, creates:

```markdown
# Customer Name

**Customer Type:** (to be filled)  
**Industry:** (to be filled)  
**Product:** (to be filled)

## Contacts

**Technical Contact:** (to be filled)

## Technical Details

- **Tenant:** (from case context)
- **Schema:** (from case context)

## Support History

- S### - Issue description - ✅ RESOLVED (date)

## Notes

(to be filled)
```

## Post-resolution

After resolving:

1. **Check for runbook opportunity** — If this is a recurring pattern, run `/agentic-support runbook-create`
2. **Update documentation** — If this revealed a knowledge gap, update docs
3. **Notify customer** — Close the ticket in your ticketing system
4. **Clean up** — Remove any temporary investigation files

## Notes

- Cases cannot be resolved without a filled Resolution section
- Customer name is extracted from the case file's Customer field
- Customer folder names use kebab-case (e.g., `intercambio-ccenglish`)
- Support history in customer info stays in chronological order
