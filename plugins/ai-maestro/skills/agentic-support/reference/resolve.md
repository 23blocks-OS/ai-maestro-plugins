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
- Moves: `inbound/S005-checkout-500.md` → `customers/acme-language-school/S005-checkout-500.md`
- Updates INDEX: `| S005 | ... | ✅ RESOLVED (2026-01-15) |`
- Adds to customer info: `- S005 - Checkout returns 500 - ✅ RESOLVED (2026-01-15)`

## Resolve checklist

Copy and complete before resolving:

```
- [ ] Root cause verified
- [ ] Solution documented (commits, PRs, changes)
- [ ] Verification done; Date Resolved filled
- [ ] Customer informed (or no contact needed, stated in the case)
- [ ] Runbook decision made: create, update, or none
- [ ] Follow-up owner named
- [ ] P0/P1 only: impact, timeline, root cause and follow-up recorded in the case
```

Show the message to the customer and wait for approval before sending it.

## Customer info template

If the customer folder has no `_customer-info.md`, create it:

```markdown
# Customer Name

**Customer Type:** End Client / Partner / Internal  
**Industry:** Industry/Sector  
**Product:** Product they use

## Contacts

(only as needed to resolve cases)
- Name / Role / Email: (to be filled)

## Technical Details

- **Tenant:** tenant_name
- **Schema:** schema_name
- **Company ID:** 123
- **Platform:** iOS / Android / Web
- **Environment:** Production / Staging

## Support History

- S001 - Case description - STATUS (date)

## Notes

Special considerations, quirks, or context. No secrets; name where they live.
```

## Post-resolution

After resolving:

1. **Runbook decision** — If this is a recurring pattern, run `/agentic-support runbook-create`; if a runbook was used, update it
2. **Update documentation** — If this revealed a knowledge gap, update docs
3. **Update the customer** — Through your support channel, after the approval above
4. **Clean up** — Remove any temporary investigation files

## Notes

- Cases cannot be resolved without a filled Resolution section
- Keep one folder per customer so a data-subject request can be answered from it
- Customer name is extracted from the case file's Customer field
- Customer folder names use kebab-case (e.g., `acme-language-school`)
- Support history in customer info stays in chronological order
