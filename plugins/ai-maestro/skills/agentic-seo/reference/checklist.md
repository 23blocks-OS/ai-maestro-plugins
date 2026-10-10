Quick 15-item verification checklist to run against the prerendered HTML of one page. Use after implementing SEO or before deploying changes.

## Contents

- Prerequisites
- The 15-Point Checklist (meta tags, social tags, structured data, infrastructure)
- Sitemap fields
- Quick Bulk Check
- Interpreting Results
- After Fixing Issues

**Important**: Use the site configuration gathered during first-time setup (`{SITE_NAME}`, `{DOMAIN}`, `{BUILD_OUTPUT}`, `{SITEMAP_PATH}`, etc.). If not yet gathered, ask the user first per SKILL.md instructions.

## Prerequisites

The web app must be built first. Run your framework's build command (e.g., `npx nx build web`, `npm run build`, etc.).

Identify the build output directory from the site configuration (`{BUILD_OUTPUT}`).

## The 15-Point Checklist

For a page at route `/ROUTE_PATH`, the prerendered file is at:
`{BUILD_OUTPUT}/ROUTE_PATH/index.html`

### Meta Tags (5 checks)

**1. Title tag**
```bash
grep '<title>' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: 50-60 chars, includes primary keyword, ends with `| {SITE_NAME}`

**2. Meta description**
```bash
grep 'name="description"' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: 150-160 chars, unique, includes CTA

**3. Canonical URL**
```bash
grep 'rel="canonical"' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: `<link rel="canonical" href="{DOMAIN}/ROUTE_PATH">`

**4. Robots meta**
```bash
grep 'name="robots"' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: `content="index, follow"`

**5. OG URL**
```bash
grep 'og:url' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: Same URL as the canonical

### Social Tags (4 checks)

**6. OG title**
```bash
grep 'og:title' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: Matches or is similar to title tag

**7. OG image**
```bash
grep 'og:image' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: Full URL to social sharing image

**8. X/Twitter card**
```bash
grep 'twitter:card' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: `content="summary_large_image"`

**9. X/Twitter image**
```bash
grep 'twitter:image' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: Same as OG image URL

### Structured Data (3 checks)

**10. JSON-LD present**
```bash
grep 'application/ld+json' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: At least one `<script type="application/ld+json">` tag in the HTML

**11. Schema types**
```bash
grep -o '"@type":"[^"]*"' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: Types that match the visible content (e.g., SoftwareApplication, Article). No minimum count; never add a schema to reach one

**12. BreadcrumbList present (where the page has a hierarchy)**
```bash
grep 'BreadcrumbList' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: BreadcrumbList schema with correct page hierarchy

### Infrastructure (3 checks)

**13. Sitemap entry**
```bash
grep 'ROUTE_PATH' {SITEMAP_PATH}
```
Expected: `<loc>{DOMAIN}/ROUTE_PATH</loc>`. Add `<lastmod>` only if it is accurate (Google uses it if it is consistently and verifiably accurate)

**14. Prerender config**
```bash
# Check your framework's prerender configuration (e.g., routes.txt, next.config.js, etc.)
grep 'ROUTE_PATH' path/to/prerender-config
```
Expected: Route path listed for static generation

**15. H1 tag**
```bash
grep -o '<h1[^>]*>[^<]*</h1>' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: Exactly one `<h1>` per page

## Sitemap fields

Google ignores `<priority>` and `<changefreq>` values; do not add them. It uses `<lastmod>` "if it's consistently and verifiably (for example by comparing to the last modification of the page) accurate" ([Build a sitemap](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)). Set it only when the page content really changed.

## Quick Bulk Check

Run all 15 checks for a single page at once (adapt paths to your project):

```bash
PAGE="ROUTE_PATH"
FILE="{BUILD_OUTPUT}/${PAGE}/index.html"

echo "=== SEO Checklist: /${PAGE} ==="
echo "1. Title:       $(grep -c '<title>' $FILE) found"
echo "2. Description: $(grep -c 'name=\"description\"' $FILE) found"
echo "3. Canonical:   $(grep -c 'rel=\"canonical\"' $FILE) found"
echo "4. Robots:      $(grep -c 'name=\"robots\"' $FILE) found"
echo "5. OG URL:      $(grep -c 'og:url' $FILE) found"
echo "6. OG title:    $(grep -c 'og:title' $FILE) found"
echo "7. OG image:    $(grep -c 'og:image' $FILE) found"
echo "8. Twitter card: $(grep -c 'twitter:card' $FILE) found"
echo "9. Twitter img: $(grep -c 'twitter:image' $FILE) found"
echo "10. JSON-LD:    $(grep -c 'application/ld+json' $FILE) found"
echo "11. Schema:     $(grep -o '"@type":"[^"]*"' $FILE | sort -u | wc -l) types (check they match the page)"
echo "12. Breadcrumb: $(grep -c 'BreadcrumbList' $FILE) found"
echo "13. Sitemap:    $(grep -c "${PAGE}" {SITEMAP_PATH}) entries"
echo "14. Prerender:  [check your framework config]"
echo "15. H1 tag:     $(grep -c '<h1' $FILE) found"
echo "=== Done ==="
```

## Interpreting Results

- **All 15 pass**: Page is fully SEO-optimized
- **10-14 pass**: Minor gaps -- use `/agentic-seo audit` for details
- **5-9 pass**: Significant gaps -- use `/agentic-seo implement` to fill
- **0-4 pass**: Page needs full SEO implementation from scratch

## After Fixing Issues

1. Rebuild: Run your framework's build command
2. Re-run checklist to verify fixes appear in prerendered HTML
3. Run `/agentic-seo audit` for a comprehensive review
4. Run Google's Rich Results Test and the Schema Markup Validator on the built page and fix errors before reporting done
