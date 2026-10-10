# audit — Health-check the support system

Audits the support system for common issues: orphan files, missing customer info, stale inbound cases, broken links, and runbook coverage.

## Usage

```
/agentic-support audit
```

## What it does

1. **Checks INDEX.md** — Verifies all cases listed exist as files
2. **Scans inbound/** — Flags cases older than threshold (default 7 days)
3. **Validates customer info** — Ensures `_customer-info.md` exists for all customers
4. **Checks runbook links** — Verifies case ↔ runbook references are bidirectional
5. **Reports orphans** — Finds case files not in INDEX.md
6. **Suggests cleanup** — Recommends actions to fix issues

## Example output

```markdown
# Support System Audit
**Date:** 2026-10-10

## Health Score: 85/100

### ✅ Good (3)
- INDEX.md format valid
- All case files exist
- Customer folders properly structured

### ⚠️  Warnings (2)
- 1 case in inbound >7 days old
- 2 customers missing contact information

### ❌ Issues (1)
- 1 orphan case file (not in INDEX)

---

## Detailed Findings

### Stale Inbound Cases
Cases in inbound/ older than 7 days:

- **S004** - Verilog identity registration (14 days old)
  → Action: Resolve or escalate

### Missing Customer Info
Customers missing fields in _customer-info.md:

- **verilog/_customer-info.md**
  → Missing: Technical Contact, Company ID, Schema

### Orphan Files
Case files not listed in INDEX.md:

- **inbound/debug-session-notes.md**
  → Action: Remove or create case for it

### Broken Links
Missing runbook references:

- S005 references R001 ✅
- R001 references S005 ✅
- No broken links found

### Runbook Coverage
Runbooks by category:

- Authentication: 1 runbook
- Database: 0 runbooks
- API: 0 runbooks
- Deployment: 0 runbooks

→ Consider creating runbooks for common database/API issues

---

## Recommended Actions

1. **High Priority**
   - Resolve S004 (Verilog) - 14 days in inbound
   - Remove orphan file: debug-session-notes.md

2. **Medium Priority**
   - Fill customer info for Verilog
   - Create runbook for database connection issues (seen 3 times)

3. **Low Priority**
   - Add deployment runbook template
   - Archive resolved cases older than 90 days

## Auto-Fix Available

Run `/agentic-support audit --fix` to automatically:
- Remove orphan files
- Update INDEX.md with missing entries
- Create customer info templates
```

## Audit checks

### 1. INDEX.md integrity
- ✅ All cases in INDEX exist as files
- ✅ All case files are in INDEX
- ✅ Case numbers are sequential
- ✅ No duplicate case numbers
- ✅ Status markers are valid (🔴/✅)

### 2. Inbound hygiene
- ⚠️  Cases older than 7 days
- ⚠️  Cases older than 30 days (critical)
- ✅ All inbound cases have Customer field
- ✅ All inbound cases have Severity set

### 3. Customer data quality
- ✅ Every customer folder has `_customer-info.md`
- ⚠️  Missing contact information
- ⚠️  Missing technical details (tenant, schema)
- ✅ Support history matches case files

### 4. Runbook health
- ✅ All runbook references resolve
- ✅ Cases link back to runbooks used
- ⚠️  Runbooks without recent usage (>90 days)
- ⚠️  Common issues without runbooks

### 5. File system
- ✅ No files outside expected structure
- ✅ Naming conventions followed
- ✅ No duplicate file names

## Scheduling

Run audit:
- **Weekly** — Regular health check
- **Before migration** — Ensure data quality
- **After bulk changes** — Verify integrity
- **When onboarding new person** — Show system state

## Auto-fix mode

```bash
/agentic-support audit --fix
```

Auto-fixes:
- Creates missing INDEX entries
- Removes orphan files
- Creates customer info templates
- Fixes broken case numbers

Does NOT auto-fix (requires review):
- Stale inbound cases (need resolution)
- Missing customer details (need research)
- Runbook gaps (need creation)

## Notes

- Audit is read-only by default
- Health score helps track improvement over time
- Warnings are suggestions, not requirements
- Use audit before quarterly reviews or migrations
