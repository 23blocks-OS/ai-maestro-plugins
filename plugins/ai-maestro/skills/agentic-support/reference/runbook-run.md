# runbook-run — Execute a runbook for a case

Applies a runbook's solution steps to a new case, documenting the execution and results.

## Usage

```
/agentic-support runbook-run <runbook-number> <case-number>
```

## What it does

1. **Loads runbook** — Reads `{RUNBOOKS_DIR}/R###-title.md`
2. **Verifies applicability** — Checks if symptoms match current case
3. **Executes steps** — Follows Solution Steps, documenting each
4. **Records results** — Updates case file with what worked
5. **Links runbook** — Adds runbook reference to case Related section
6. **Updates runbook** — Adds case to runbook's Related Cases

## Example

```bash
/agentic-support runbook-run R001 S012
```

This:
- Follows R001's steps to resolve S012
- Documents execution in S012's case file
- Links S012 → R001 and R001 → S012

## Execution workflow

1. **Read "When to Use"** — Verify symptoms match
2. **Follow Solution Steps** — Execute each step
3. **Document results** — Record output of each step in case file
4. **Run Verification** — Confirm fix worked
5. **Note deviations** — If steps needed modification, note why

## Case file updates

After running runbook, case file shows:

```markdown
## Resolution

### Solution

Applied runbook R001 - Missing scopes cause 204 responses

Step 1: Verified scopes in Auth DB
```sql
SELECT * FROM permissions WHERE name LIKE '%agents%'
```
Result: Found agents:read, agents:execute

Step 2: Checked GUEST role assignments
Result: All scopes present

Step 3: (runbook was sufficient, issue was different)

**Actual fix:** Different root cause - see investigation

### Verification

(results of verification steps)

## Related

- Runbook attempted: R001
- Actual solution: ...
```

## When runbook doesn't fit

If runbook steps don't resolve the issue:

1. **Document what you tried** — Record which steps ran
2. **Note the deviation** — Why didn't it work this time?
3. **Continue investigation** — Find the actual root cause
4. **Consider runbook update** — Should runbook cover this case?

## Updating runbooks based on execution

After running a runbook:

- ✅ **Worked perfectly** — Add case to Related Cases
- ⚠️ **Worked with tweaks** — Update runbook with improvements
- ❌ **Didn't work** — Document why, consider splitting runbook

## Notes

- Not every case needs a runbook — only use when pattern matches
- Runbooks are guides, not automation — use judgment
- If you modify steps, update the runbook for next time
- Failed runbook application is valuable data for runbook improvement
