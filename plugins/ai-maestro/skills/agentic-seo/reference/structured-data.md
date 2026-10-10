Guide for adding and updating JSON-LD structured data on web pages. Each schema type includes a complete template — replace `{SITE_NAME}`, `{DOMAIN}`, and `{SOCIAL_LINKS}` with the user's actual values from the site configuration.

## Contents

- Critical Rules
- Schema Types and When to Use Them (SoftwareApplication, Organization, BreadcrumbList, FAQPage, WebPage, Article)
- Combining Schemas
- Choosing the Right Schema Combination
- Validation

**Important**: Use the site configuration gathered during first-time setup. If not yet gathered, ask the user first per SKILL.md instructions.

## Critical Rules

1. **SSR-safe**: JSON-LD must NOT be wrapped in browser-only guards (e.g., `isPlatformBrowser` in Angular). It must render during SSG/SSR so search engines see it in the HTML source.
2. **Match the visible content**: add only structured data that describes what is on the page; never add a schema just to reach a count. Google says structured data isn't required for generative AI search and there is no special schema.org markup to add (guide last updated 2026-07-10: https://developers.google.com/search/docs/fundamentals/ai-optimization-guide).
3. **Single script tag**: Combine all schemas into one `<script type="application/ld+json">` using a JSON array.
4. **Cleanup on destroy**: Always remove the script on component destroy to prevent duplication during SPA navigation.

## Schema Types and When to Use Them

### SoftwareApplication

**Use on**: Product pages, feature pages, tool pages

```typescript
const schema = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  'name': '{SITE_NAME} [Product Name]',
  'applicationCategory': 'DeveloperApplication',
  'operatingSystem': 'Web',
  'description': 'Description of the product/feature',
  'url': '{DOMAIN}/products/PRODUCT_NAME',
  'datePublished': 'YYYY-MM-DD',
  'dateModified': 'YYYY-MM-DD',
  'author': {
    '@type': 'Organization',
    'name': '{SITE_NAME}',
    'url': '{DOMAIN}'
  },
  // OPTIONAL. Delete this block unless the offer is real and published.
  // 'price': '0' and 'Free tier available' are placeholders; shipping them states a price and a free tier you may not have.
  'offers': {
    '@type': 'Offer',
    'price': '0',
    'priceCurrency': 'USD',
    'description': 'Free tier available'
  },
  'featureList': [
    'Feature 1',
    'Feature 2',
    'Feature 3'
  ]
};
```

### Organization

**Use on**: All pages (can be combined with any other schema). Include at minimum on homepage, about, and contact pages.

```typescript
const schema = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
  'name': '{SITE_NAME}',
  'url': '{DOMAIN}',
  'logo': '{DOMAIN}/assets/logo.png',
  'sameAs': [
    // Include the user's social profile URLs here
    // e.g., 'https://twitter.com/{handle}',
    // 'https://github.com/{org}',
    // 'https://linkedin.com/company/{company}'
  ]
};
```

### BreadcrumbList

**Use on**: Pages that sit in a hierarchy.

```typescript
const schema = {
  '@context': 'https://schema.org',
  '@type': 'BreadcrumbList',
  'itemListElement': [
    {
      '@type': 'ListItem',
      'position': 1,
      'name': 'Home',
      'item': '{DOMAIN}'
    },
    {
      '@type': 'ListItem',
      'position': 2,
      'name': 'Section Name',
      'item': '{DOMAIN}/section'
    },
    {
      '@type': 'ListItem',
      'position': 3,
      'name': 'Page Name',
      'item': '{DOMAIN}/section/page'
    }
  ]
};
```

### FAQPage (optional, no Google rich result)

Google's FAQ rich results "will no longer appear in Google Search starting May 7, 2026", and its FAQPage documentation page was removed on 2026-06-15 (https://developers.google.com/search/docs/appearance/structured-data/faqpage). FAQPage remains valid schema.org markup that other consumers may read. Add it only if the owner wants it and the page shows the same questions and answers visibly. HowTo rich results were removed in 2023; this skill no longer provides a HowTo template.

### WebPage

**Use on**: Generic pages that don't fit other types (about, contact, legal). WebPage markup produces no rich result; use it only if the owner wants the data.

```typescript
const schema = {
  '@context': 'https://schema.org',
  '@type': 'WebPage',
  'name': 'Page Title',
  'description': 'Page description',
  'url': '{DOMAIN}/page-path',
  'datePublished': 'YYYY-MM-DD',
  'dateModified': 'YYYY-MM-DD',
  'publisher': {
    '@type': 'Organization',
    'name': '{SITE_NAME}',
    'url': '{DOMAIN}'
  }
};
```

### Article

**Use on**: Blog posts, case studies, news articles.

```typescript
const schema = {
  '@context': 'https://schema.org',
  '@type': 'Article',
  'headline': 'Article Title (max 110 chars)',
  'description': 'Article description',
  'url': '{DOMAIN}/blog/article-slug',
  'datePublished': 'YYYY-MM-DD',
  'dateModified': 'YYYY-MM-DD',
  'author': {
    '@type': 'Organization',
    'name': '{SITE_NAME}',
    'url': '{DOMAIN}'
  },
  'publisher': {
    '@type': 'Organization',
    'name': '{SITE_NAME}',
    'url': '{DOMAIN}',
    'logo': {
      '@type': 'ImageObject',
      'url': '{DOMAIN}/assets/logo.png'
    }
  },
  'image': '{DOMAIN}{SOCIAL_IMAGE_PATH}article-og.png'
};
```

## Combining Schemas

Always combine all schemas for a page into a single JSON array:

```typescript
private addStructuredData() {
  const schemas = [contentSchema, breadcrumbSchema]; // etc.

  this.jsonLdScript = this.document.createElement('script');
  this.jsonLdScript.type = 'application/ld+json';
  this.jsonLdScript.text = JSON.stringify(schemas);
  this.document.head.appendChild(this.jsonLdScript);
}
```

## Choosing the Right Schema Combination

| Page Type | Primary Schema | Additional Schemas |
|-----------|---------------|-------------------|
| Product/feature page | SoftwareApplication | BreadcrumbList, Organization |
| Getting started | WebPage (no rich result) | BreadcrumbList |
| About/company | Organization | BreadcrumbList, WebPage |
| Legal pages | WebPage | BreadcrumbList |
| Blog post | Article | BreadcrumbList, Organization |
| Homepage | Organization | WebPage |

## Validation

Before reporting done: run Google's Rich Results Test (https://search.google.com/test/rich-results) and the Schema Markup Validator (https://validator.schema.org) on a built page and fix every error.

Then verify structured data appears in prerendered HTML:

```bash
grep 'application/ld+json' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```

The JSON-LD should be present in the `<head>` of the prerendered file. If it's missing, the `addStructuredData()` method is likely guarded by a browser-only check or not being called during SSR.
