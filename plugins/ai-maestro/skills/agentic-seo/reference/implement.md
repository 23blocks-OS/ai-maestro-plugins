Implement full SEO on a page component from scratch. Follow this step-by-step process to bring a page from zero to fully SEO-optimized.

**Important**: Use the site configuration gathered during first-time setup (`{SITE_NAME}`, `{DOMAIN}`, `{TWITTER_HANDLE}`, etc.). If not yet gathered, ask the user first per SKILL.md instructions.

## Inputs

- **Target**: Component path (e.g., `src/app/pages/about/about.component.ts`)
- **Page title**: The primary keyword/topic of the page
- **Route path**: The URL path (e.g., `/about`)

## Step 1 -- Add Required Imports

Ensure the component has the necessary imports for your framework.

**Angular example:**
```typescript
import { Component, OnInit, OnDestroy, Inject, PLATFORM_ID } from '@angular/core';
import { CommonModule, isPlatformBrowser, DOCUMENT } from '@angular/common';
import { Title, Meta } from '@angular/platform-browser';
```

If the component uses routing links, also include:
```typescript
import { RouterModule } from '@angular/router';
```

## Step 2 -- Add Constructor Dependencies

Add to the component's constructor:

```typescript
private jsonLdScript: HTMLScriptElement | null = null;

constructor(
  private titleService: Title,
  private metaService: Meta,
  @Inject(DOCUMENT) private document: Document,
  @Inject(PLATFORM_ID) private platformId: Object
) {}
```

Ensure the component implements `OnInit, OnDestroy`:
```typescript
export class MyComponent implements OnInit, OnDestroy {
```

## Step 3 -- Add Lifecycle Hooks

```typescript
ngOnInit() {
  this.setMetaTags();
  this.addStructuredData();
}

ngOnDestroy() {
  this.removeStructuredData();
}
```

## Step 4 -- Implement setMetaTags()

Create the method with ALL required tags. Replace `{SITE_NAME}`, `{DOMAIN}`, and `{TWITTER_HANDLE}` with the user's actual values.

```typescript
private setMetaTags() {
  // Title: 50-60 chars, primary keyword first, end with "| {SITE_NAME}"
  this.titleService.setTitle('Primary Keyword - Descriptor | {SITE_NAME}');

  // Description: 150-160 chars, include CTA, unique to this page
  this.metaService.updateTag({
    name: 'description',
    content: 'Compelling description with primary keyword. Explain the value. Include a call-to-action.'
  });

  // Keywords: 5-15 relevant terms
  this.metaService.updateTag({
    name: 'keywords',
    content: 'keyword1, keyword2, keyword3, {SITE_NAME}, related-term'
  });

  this.metaService.updateTag({ name: 'robots', content: 'index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1' });
  this.metaService.updateTag({ name: 'author', content: '{SITE_NAME}' });

  // Canonical URL -- MUST match the page's route
  this.updateCanonicalLink('{DOMAIN}/ROUTE_PATH');

  // Open Graph (8+ tags)
  this.metaService.updateTag({ property: 'og:type', content: 'website' });
  this.metaService.updateTag({ property: 'og:site_name', content: '{SITE_NAME}' });
  this.metaService.updateTag({ property: 'og:title', content: 'Same as title tag' });
  this.metaService.updateTag({ property: 'og:description', content: 'Same as meta description' });
  this.metaService.updateTag({ property: 'og:url', content: '{DOMAIN}/ROUTE_PATH' });
  this.metaService.updateTag({ property: 'og:image', content: '{DOMAIN}{SOCIAL_IMAGE_PATH}PAGE_NAME-og.png' });
  this.metaService.updateTag({ property: 'og:image:width', content: '1200' });
  this.metaService.updateTag({ property: 'og:image:height', content: '630' });
  this.metaService.updateTag({ property: 'og:image:alt', content: 'Descriptive alt text for the social image' });
  this.metaService.updateTag({ property: 'og:locale', content: 'en_US' });

  // Twitter Card (6+ tags)
  this.metaService.updateTag({ name: 'twitter:card', content: 'summary_large_image' });
  this.metaService.updateTag({ name: 'twitter:site', content: '{TWITTER_HANDLE}' });
  this.metaService.updateTag({ name: 'twitter:creator', content: '{TWITTER_HANDLE}' });
  this.metaService.updateTag({ name: 'twitter:title', content: 'Same as title tag' });
  this.metaService.updateTag({ name: 'twitter:description', content: 'Same as meta description' });
  this.metaService.updateTag({ name: 'twitter:image', content: '{DOMAIN}{SOCIAL_IMAGE_PATH}PAGE_NAME-og.png' });
  this.metaService.updateTag({ name: 'twitter:image:alt', content: 'Same alt text as OG image' });

  // Theme color (adjust to match your brand)
  this.metaService.updateTag({ name: 'theme-color', content: '#111827' });
}
```

## Step 5 -- Implement updateCanonicalLink()

```typescript
private updateCanonicalLink(url: string) {
  const existingLink = this.document.querySelector('link[rel="canonical"]');
  if (existingLink) {
    existingLink.setAttribute('href', url);
  } else {
    const link = this.document.createElement('link');
    link.setAttribute('rel', 'canonical');
    link.setAttribute('href', url);
    this.document.head.appendChild(link);
  }
}
```

## Step 6 -- Implement addStructuredData()

CRITICAL: This method must NOT be wrapped in a browser-only guard (e.g., `isPlatformBrowser` in Angular). It must execute during SSR/SSG so that the JSON-LD appears in the prerendered HTML.

Choose appropriate schema types based on the page content (see `reference/structured-data.md` for the full guide).

Minimum schemas per page:
1. One content-specific schema (SoftwareApplication, WebPage, FAQPage, etc.)
2. BreadcrumbList

```typescript
private addStructuredData() {
  const contentSchema = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',  // or SoftwareApplication, FAQPage, etc.
    'name': 'Page Name',
    'description': 'Same as meta description',
    'url': '{DOMAIN}/ROUTE_PATH',
    'datePublished': 'YYYY-MM-DD',
    'dateModified': 'YYYY-MM-DD',
    'author': {
      '@type': 'Organization',
      'name': '{SITE_NAME}',
      'url': '{DOMAIN}'
    }
  };

  const breadcrumbSchema = {
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
        'name': 'Page Name',
        'item': '{DOMAIN}/ROUTE_PATH'
      }
    ]
  };

  this.jsonLdScript = this.document.createElement('script');
  this.jsonLdScript.type = 'application/ld+json';
  this.jsonLdScript.text = JSON.stringify([contentSchema, breadcrumbSchema]);
  this.document.head.appendChild(this.jsonLdScript);
}
```

## Step 7 -- Implement removeStructuredData()

```typescript
private removeStructuredData() {
  if (this.jsonLdScript && this.jsonLdScript.parentNode) {
    this.jsonLdScript.parentNode.removeChild(this.jsonLdScript);
  }
}
```

## Step 8 -- Update Sitemap

Add entry to sitemap.xml (at `{SITEMAP_PATH}`):

```xml
<url>
  <loc>{DOMAIN}/ROUTE_PATH</loc>
  <lastmod>YYYY-MM-DD</lastmod>
  <changefreq>weekly</changefreq>
  <priority>0.7</priority>
</url>
```

Priority guidelines:
- `1.0` -- Homepage only
- `0.9` -- Main product pages
- `0.8` -- Major feature pages
- `0.7` -- Feature sub-pages, marketing pages
- `0.6` -- Use cases, company pages
- `0.5` -- Support, partners
- `0.3` -- Legal pages

## Step 9 -- Update Prerender Configuration

Verify the route is listed for static generation (e.g., `routes.txt` in Angular SSG, or equivalent for your framework).

## Step 10 -- Verify HTML Template

Check the component's template file for:
- Exactly one `<h1>` tag
- Logical heading hierarchy (h1 > h2 > h3, no skipped levels)
- All `<img>` tags have descriptive `alt` attributes
- Internal links to related pages

## Step 11 -- Social Sharing Image

Note: A 1200x630 PNG should exist at the social image path for this page. If it doesn't exist, flag it as a TODO but don't block the implementation.

## Post-Implementation

After implementing, run:
```
/agentic-seo audit /ROUTE_PATH
```
to verify all 33 checks pass.

## Checklist Before Done

- [ ] All imports added
- [ ] Constructor dependencies injected
- [ ] `setMetaTags()` with all tags (using site config values)
- [ ] `updateCanonicalLink()` helper
- [ ] `addStructuredData()` with 2+ schemas, SSR-safe
- [ ] `removeStructuredData()` on destroy
- [ ] Sitemap entry added
- [ ] Route configured for prerendering
- [ ] HTML template has proper h1, heading hierarchy, alt text
- [ ] Social image noted (exists or flagged as TODO)
