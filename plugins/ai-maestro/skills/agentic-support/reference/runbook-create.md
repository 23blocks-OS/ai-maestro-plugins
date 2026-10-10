# runbook-create — Create a reusable runbook

Creates a runbook from a resolved case that represents a recurring pattern. Runbooks capture institutional knowledge so future incidents can be resolved faster.

## Usage

```
/agentic-support runbook-create <case-number> <runbook-title>
```

## What it does

1. **Verifies case is resolved** — Only resolved cases become runbooks
2. **Generates runbook number** — Sequential numbering (R001, R002...)
3. **Extracts pattern** — Pulls Root Cause and Solution from case file
4. **Creates runbook file** — Creates `{RUNBOOKS_DIR}/R###-title.md`
5. **Links back to case** — References original case in "Related Cases"
6. **Updates runbook index** — Adds to `{RUNBOOKS_DIR}/INDEX.md`

## Example

```bash
/agentic-support runbook-create S005 "Missing scopes cause 204 responses"
```

Creates: `support/runbooks/R001-missing-scopes-204.md`

## When to create a runbook

Create a runbook when:

- ✅ **Pattern will recur** — Same issue will likely happen again
- ✅ **Multiple steps involved** — Not a single command fix
- ✅ **Domain knowledge required** — Future responder needs context
- ✅ **Common symptom** — Specific error message or behavior pattern

Do NOT create runbooks for:

- ❌ One-off bugs in code (fix the code instead)
- ❌ Trivial fixes (one command, no context needed)
- ❌ Customer-specific configuration (belongs in customer notes)

## Runbook template

Generated runbook structure:

```markdown
# R### - Runbook Title

**Category:** (extracted from case)  
**Frequency:** Common / Occasional / Rare  
**Last Updated:** YYYY-MM-DD

## When to Use

Symptoms that indicate this runbook applies:
- (extracted from case Investigation)
- Specific error messages
- Behavior patterns

## Root Cause

(extracted from case Root Cause section)

## Solution Steps

(extracted from case Resolution section, formatted as steps)

1. **Step description**
   ```bash
   # Commands
   ```

2. **Next step**
   ```ruby
   # Code changes
   ```

## Verification

(extracted from case Verification section)

## Prevention

How to prevent this in the future:
- (suggestions based on case)

## Related Cases

- S### - Original case

## See Also

- Related documentation
- Related runbooks
```

## After creating

1. **Edit for clarity** — Remove case-specific details, generalize
2. **Add prevention** — How to avoid this issue
3. **Test the steps** — Ensure runbook can be followed without the case
4. **Link from case** — Update original case with runbook reference

## Updating runbooks

When the same pattern occurs again:

1. Run the runbook for the new case
2. Document what worked / what didn't
3. Update the runbook with improvements
4. Add new case to "Related Cases"

## Notes

- Runbooks are living documents — update them as you learn
- Each runbook should be self-contained (no "see case S###" for critical steps)
- Include both the fix AND how to verify it worked
- Prevention section prevents runbook proliferation
