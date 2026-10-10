Guide for adding and updating JSON-LD structured data on web pages. Each schema type includes a complete template — replace `{SITE_NAME}`, `{DOMAIN}`, and `{SOCIAL_LINKS}` with the user's actual values from the site configuration.

**Important**: Use the site configuration gathered during first-time setup. If not yet gathered, ask the user first per SKILL.md instructions.

## Critical Rules

1. **SSR-safe**: JSON-LD must NOT be wrapped in browser-only guards (e.g., `isPlatformBrowser` in Angular). It must render during SSG/SSR so search engines see it in the HTML source.
2. **Minimum 2 schemas**: Every page needs at least one content schema + BreadcrumbList.
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

**Use on**: Every page (required as one of the minimum 2 schemas).

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

### FAQPage

**Use on**: Any page with FAQ content. Produces rich snippets in Google search results (expandable Q&A).

```typescript
const schema = {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  'mainEntity': [
    {
      '@type': 'Question',
      'name': 'Question text here?',
      'acceptedAnswer': {
        '@type': 'Answer',
        'text': 'Plain text answer (strip HTML tags from any rich content)'
      }
    }
  ]
};
```

**Dynamic FAQ from component data**:
```typescript
const faqSchema = {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  'mainEntity': this.faqs.map(faq => ({
    '@type': 'Question',
    'name': faq.question,
    'acceptedAnswer': {
      '@type': 'Answer',
      'text': faq.answer.replace(/<[^>]*>/g, '')  // Strip HTML
    }
  }))
};
```

### HowTo

**Use on**: Installation guides, setup pages, getting-started pages.

```typescript
const schema = {
  '@context': 'https://schema.org',
  '@type': 'HowTo',
  'name': 'How to Set Up [Feature] with {SITE_NAME}',
  'description': 'Step-by-step guide to...',
  'step': [
    {
      '@type': 'HowToStep',
      'position': 1,
      'name': 'Create an Account',
      'text': 'Sign up and create your first application.',
      'url': '{DOMAIN}/getting-started'
    },
    {
      '@type': 'HowToStep',
      'position': 2,
      'name': 'Install the SDK',
      'text': 'Install the SDK package in your project.',
      'url': '{DOMAIN}/docs/installation'
    }
  ],
  'totalTime': 'PT5M'
};
```

### WebPage

**Use on**: Generic pages that don't fit other types (about, contact, legal).

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
  const schemas = [contentSchema, breadcrumbSchema, faqSchema]; // etc.

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
| Product page with FAQ | SoftwareApplication | BreadcrumbList, FAQPage |
| Getting started | HowTo | BreadcrumbList, Organization |
| About/company | Organization | BreadcrumbList, WebPage |
| Legal pages | WebPage | BreadcrumbList |
| Blog post | Article | BreadcrumbList, Organization |
| Feature page with FAQ | SoftwareApplication | BreadcrumbList, FAQPage, Organization |
| Homepage | Organization | WebPage |

## Validation

After implementing, verify structured data appears in prerendered HTML:

```bash
grep 'application/ld+json' {BUILD_OUTPUT}/ROUTE_PATH/index.html
```

The JSON-LD should be present in the `<head>` of the prerendered file. If it's missing, the `addStructuredData()` method is likely guarded by a browser-only check or not being called during SSR.
