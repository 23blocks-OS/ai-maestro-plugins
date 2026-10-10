Run a systematic SEO audit on a target page and generate a comprehensive pass/fail report. Don't fix issues; document them for the `implement` or `structured-data` sub-commands to address.

**Important**: Use the site configuration gathered during first-time setup (`{SITE_NAME}`, `{DOMAIN}`, `{TWITTER_HANDLE}`, etc.). If not yet gathered, ask the user first per SKILL.md instructions.

## Inputs

- **Target**: Component path (e.g., `src/app/pages/about.component.ts`) or route path (e.g., `/about`)
- If a route path is given, resolve it to the component file via the app routing configuration

## Audit Steps

### Step 1 -- Read the Component

Read the target component's source file. Identify:
- Meta tag setup method (e.g., `setMetaTags()`)
- Structured data method (e.g., `addStructuredData()`)
- Canonical URL method (e.g., `updateCanonicalLink()`)
- Cleanup on destroy (e.g., `ngOnDestroy()`)
- Framework-specific dependencies (Title, Meta services, etc.)

### Step 2 -- Check Meta Tags

Verify each tag exists and meets quality standards:

| # | Check | Requirement | Pass Criteria |
|---|-------|-------------|---------------|
| 1 | Title tag | Title is set programmatically | 50-60 chars, includes primary keyword, ends with `\| {SITE_NAME}` |
| 2 | Meta description | `name: 'description'` | 150-160 chars, includes CTA, unique to page |
| 3 | Meta keywords | `name: 'keywords'` | Relevant terms, not stuffed (5-15 keywords) |
| 4 | Meta robots | `name: 'robots'` | `index, follow` at minimum |
| 5 | Meta author | `name: 'author'` | `{SITE_NAME}` |
| 6 | Canonical URL | Canonical link set | Full URL `{DOMAIN}/...`, matches page route |

### Step 3 -- Check Open Graph Tags

All 8+ required:

| # | Check | Tag | Pass Criteria |
|---|-------|-----|---------------|
| 7 | OG type | `og:type` | `website` (or `article` for blog posts) |
| 8 | OG site_name | `og:site_name` | `{SITE_NAME}` |
| 9 | OG title | `og:title` | Same as or similar to title tag |
| 10 | OG description | `og:description` | Same as or similar to meta description |
| 11 | OG url | `og:url` | Matches canonical URL |
| 12 | OG image | `og:image` | Full URL to 1200x630 image |
| 13 | OG image:width | `og:image:width` | `1200` |
| 14 | OG image:height | `og:image:height` | `630` |
| 15 | OG locale | `og:locale` | `en_US` (or appropriate locale) |

### Step 4 -- Check Twitter Card Tags

All 6+ required:

| # | Check | Tag | Pass Criteria |
|---|-------|-----|---------------|
| 16 | Twitter card | `twitter:card` | `summary_large_image` |
| 17 | Twitter site | `twitter:site` | `{TWITTER_HANDLE}` |
| 18 | Twitter creator | `twitter:creator` | `{TWITTER_HANDLE}` |
| 19 | Twitter title | `twitter:title` | Same as or similar to title tag |
| 20 | Twitter description | `twitter:description` | Same as or similar to meta description |
| 21 | Twitter image | `twitter:image` | Same as OG image |

### Step 5 -- Check Structured Data (JSON-LD)

| # | Check | Requirement | Pass Criteria |
|---|-------|-------------|---------------|
| 22 | JSON-LD present | Structured data method exists | Creates `<script type="application/ld+json">` |
| 23 | Schema count | At least 2 schemas | Array or multiple scripts with distinct `@type` values |
| 24 | SSR-safe | NOT wrapped in browser-only guard | Called directly in init lifecycle without browser check |
| 25 | Cleanup | Removed on destroy | Removes script element from DOM on component destroy |
| 26 | Schema types | Appropriate types used | At minimum: one content schema + BreadcrumbList |

### Step 6 -- Check Infrastructure

| # | Check | Requirement | Pass Criteria |
|---|-------|-------------|---------------|
| 27 | Sitemap entry | Entry in sitemap.xml | `<url>` with correct `<loc>`, appropriate `<priority>` |
| 28 | Prerender config | Listed for prerendering | Route path configured for static generation |
| 29 | Social image | Image file exists | Image file referenced by OG/Twitter tags exists in the project |

### Step 7 -- Check HTML Template

Read the component's template file and verify:

| # | Check | Requirement | Pass Criteria |
|---|-------|-------------|---------------|
| 30 | H1 tag | Exactly one `<h1>` per page | One `h1` in template |
| 31 | Heading hierarchy | Logical h1 > h2 > h3 progression | No skipped levels (e.g., h1 then h3) |
| 32 | Image alt text | All `<img>` tags have descriptive `alt` | No empty or missing alt attributes |
| 33 | Internal links | Links to related pages | At least 1 internal link to another page |

## Judgement calls

- **Check 3 (`keywords`)** is advisory. Google ignores the tag. Report it; do not let it lower the score of a page that is otherwise right.
- **Checks 17 and 18 (`twitter:site`, `twitter:creator`)** apply only when the site has a handle. If `{TWITTER_HANDLE}` is empty, mark them N/A, not FAIL.
- **Check 23 (schema count)** is advisory. Never add a schema to reach two.
- **Check 32 (image alt)**: a missing `alt` fails. `alt=""` is valid for decoration (and is the right markup for it); list those for a human to confirm rather than failing them.
- To audit many pages at once, or to compare a build against the live site, use `audit-build`.

## Generate Report

### SEO Audit Report: [Page Name]

**Component**: `path/to/component`
**Route**: `/route-path`
**Site**: `{DOMAIN}`
**Date**: YYYY-MM-DD

| # | Check | Status | Detail |
|---|-------|--------|--------|
| 1 | Title tag | PASS/FAIL | [actual value or what's missing] |
| 2 | Meta description | PASS/FAIL | [char count, content preview] |
| ... | ... | ... | ... |
| 33 | Internal links | PASS/FAIL | [count of internal links found] |

### Summary

- **Total checks**: 33
- **Passed**: X
- **Failed**: Y
- **Score**: X/33 (XX%)

### Critical Issues (Fix First)

List any FAIL items that affect crawlability or indexing:
- Missing canonical URL
- No JSON-LD structured data
- Not in sitemap
- Not configured for prerendering

### Recommendations

Ordered list of what to fix, with the appropriate sub-command:
1. `agentic-seo implement /path` -- if multiple meta tags are missing
2. `agentic-seo structured-data /path` -- if JSON-LD is missing or incomplete
3. `agentic-seo checklist /path` -- after fixes, to verify against built HTML

**NEVER**:
- Report a PASS when the check is partially met
- Skip checking the HTML template
- Ignore the sitemap and prerender config checks
- Assume structured data is SSR-safe without verifying the code path
