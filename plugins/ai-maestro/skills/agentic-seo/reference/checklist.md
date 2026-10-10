Quick 15-item verification checklist to run against prerendered HTML. Use after implementing SEO or before deploying changes.

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

**5. Keywords**
```bash
grep 'name="keywords"' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: 5-15 relevant keywords

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

**8. Twitter card**
```bash
grep 'twitter:card' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: `content="summary_large_image"`

**9. Twitter image**
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
Expected: At least 2 types (e.g., SoftwareApplication, BreadcrumbList)

**12. BreadcrumbList present**
```bash
grep 'BreadcrumbList' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```
Expected: BreadcrumbList schema with correct page hierarchy

### Infrastructure (3 checks)

**13. Sitemap entry**
```bash
grep 'ROUTE_PATH' {SITEMAP_PATH}
```
Expected: `<loc>{DOMAIN}/ROUTE_PATH</loc>` with appropriate priority

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

## Sitemap Priority Guidelines

| Priority | Page Type | Examples |
|----------|-----------|---------|
| `1.0` | Homepage | `/` |
| `0.9` | Main product pages | `/products`, `/pricing` |
| `0.8` | Major feature pages | `/features/auth`, `/docs` |
| `0.7` | Feature sub-pages | `/features/auth/sso`, `/integrations` |
| `0.6` | Use cases, company | `/use-cases`, `/about` |
| `0.5` | Support, partners | `/support`, `/partners` |
| `0.3` | Legal pages | `/privacy`, `/terms`, `/cookies` |

## Changefreq Guidelines

| Frequency | When to Use |
|-----------|-------------|
| `daily` | Homepage, frequently updated pages |
| `weekly` | Product pages, feature pages |
| `monthly` | Company pages, use cases |
| `yearly` | Legal pages |

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
echo "5. Keywords:    $(grep -c 'name=\"keywords\"' $FILE) found"
echo "6. OG title:    $(grep -c 'og:title' $FILE) found"
echo "7. OG image:    $(grep -c 'og:image' $FILE) found"
echo "8. Twitter card: $(grep -c 'twitter:card' $FILE) found"
echo "9. Twitter img: $(grep -c 'twitter:image' $FILE) found"
echo "10. JSON-LD:    $(grep -c 'application/ld+json' $FILE) found"
echo "11. Schema:     $(grep -o '"@type":"[^"]*"' $FILE | sort -u | wc -l) types"
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
