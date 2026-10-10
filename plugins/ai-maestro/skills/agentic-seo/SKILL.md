---
name: agentic-seo
description: Audit, implement and optimize SEO for a website following Google's AI optimization guide, covering meta tags, Open Graph, Twitter Cards, JSON-LD structured data, canonical URLs, llms.txt, sitemap and AI-discoverability. Use when auditing a site's SEO, adding or fixing meta tags or structured data, or making a site easier for search engines and AI assistants to find.
allowed-tools: Read Write Edit Bash Glob Grep WebFetch
compatibility: The build audit script needs Python 3 (standard library only)
user-invocable: true
argument-hint: "[audit|implement|structured-data|llms-txt|checklist] [target]"
metadata:
  author: 23blocks
  version: 2.1.1
---

# Agentic SEO

Repeatable workflow for auditing and implementing SEO on any web page. Covers Google's AI optimization guide, structured data, and modern SEO best practices.

## First-Time Setup: Gather Site Configuration

**Before running any sub-command for the first time in a session**, ask the user for their website details if not already known. Store these as working context:

| Setting | Ask For | Example |
|---------|---------|---------|
| **Site Name** | "What is your site/company name?" | `Acme Corp` |
| **Domain** | "What is your website domain?" | `https://acme.com` |
| **Twitter Handle** | "What is your Twitter/X handle?" (optional) | `@acme_corp` |
| **Social Image Path** | "Where are your social sharing images stored?" | `/assets/social/` |
| **Social Links** | "Any social profile URLs?" (optional) | Twitter, GitHub, LinkedIn URLs |
| **Framework** | "What framework is your site built with?" | Angular, React, Next.js, etc. |
| **Build Output Path** | "Where does your built/prerendered HTML output to?" | `dist/apps/web/browser/` |
| **Sitemap Path** | "Where is your sitemap.xml?" | `public/sitemap.xml` |

If the project has a CLAUDE.md with SEO patterns already defined, read it and extract these values automatically instead of asking.

Use these values as `{SITE_NAME}`, `{DOMAIN}`, `{TWITTER_HANDLE}`, `{SOCIAL_IMAGE_PATH}`, `{BUILD_OUTPUT}`, `{SITEMAP_PATH}` throughout all sub-commands.

## When to use this skill

Trigger this skill when:
- A **new page** is created and needs SEO implementation
- An **SEO audit** is requested on an existing page
- **Structured data** (JSON-LD) needs to be added or updated
- **llms.txt** or **llms-full.txt** needs maintenance
- A quick **checklist** verification is needed before deploying
- A page is missing meta tags, OG tags, canonical URL, or sitemap entry

## Google AI Optimization Principles

Key rules from Google's official guide for AI-era SEO:

### Crawlability
- No `robots.txt` blocks on important content
- Proper canonical URLs on every page
- Pages must return correct HTTP status codes (200, 301, 404)
- Prerendered pages must contain full content in the HTML source

### Content Quality
- Unique, descriptive `<title>` and `<meta description>` per page
- Semantic HTML: proper `h1`-`h6` hierarchy, one `h1` per page
- Internal linking between related pages
- Content must be useful to humans first, machines second

### Structured Data
- JSON-LD in `<head>`, rendered server-side during SSR/SSG
- At least 2 schema types per page (e.g., SoftwareApplication + BreadcrumbList)
- CRITICAL for SSR frameworks: JSON-LD must NOT be wrapped in browser-only guards (e.g., `isPlatformBrowser` in Angular)

### Technical
- Fast load times (prerendered static HTML)
- Mobile-friendly responsive design
- Valid HTML, no broken links

### What NOT to Do
- Don't create special hidden content for Google AI (that's cloaking)
- Don't stuff keywords unnaturally
- Don't duplicate content across pages
- `llms.txt` is for non-Google agents; Google uses standard crawling

## SEO Implementation Pattern (Angular Example)

Every routable page component must implement these patterns. Adapt for your framework.

### Required Imports (Angular)

```typescript
import { Component, OnInit, OnDestroy, Inject, PLATFORM_ID } from '@angular/core';
import { CommonModule, isPlatformBrowser, DOCUMENT } from '@angular/common';
import { Title, Meta } from '@angular/platform-browser';
```

### Required Constructor Dependencies

```typescript
constructor(
  private titleService: Title,
  private metaService: Meta,
  @Inject(DOCUMENT) private document: Document,
  @Inject(PLATFORM_ID) private platformId: Object
) {}
```

### Lifecycle Hooks

```typescript
private jsonLdScript: HTMLScriptElement | null = null;

ngOnInit() {
  this.setMetaTags();
  this.addStructuredData();
}

ngOnDestroy() {
  this.removeStructuredData();
}
```

### setMetaTags() Pattern

Must include all of:
1. Title (50-60 chars, includes primary keyword)
2. Meta description (150-160 chars, includes CTA)
3. Keywords, robots, author
4. Canonical URL via `updateCanonicalLink()`
5. 8+ Open Graph tags
6. 6+ Twitter Card tags

### updateCanonicalLink() Helper

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

### addStructuredData() -- NO Browser-Only Guard

```typescript
private addStructuredData() {
  const schemas = [ /* ... schema objects ... */ ];
  this.jsonLdScript = this.document.createElement('script');
  this.jsonLdScript.type = 'application/ld+json';
  this.jsonLdScript.text = JSON.stringify(schemas);
  this.document.head.appendChild(this.jsonLdScript);
}
```

### removeStructuredData()

```typescript
private removeStructuredData() {
  if (this.jsonLdScript && this.jsonLdScript.parentNode) {
    this.jsonLdScript.parentNode.removeChild(this.jsonLdScript);
  }
}
```

## Sub-Commands

| Command | Description | Reference |
|---------|-------------|-----------|
| `audit [path]` | Full SEO audit of a page -- produces pass/fail table | `reference/audit.md` |
| `implement [path]` | Implement SEO on a new page from scratch | `reference/implement.md` |
| `structured-data [path]` | Add or update JSON-LD structured data | `reference/structured-data.md` |
| `llms-txt` | Maintain llms.txt and llms-full.txt files | `reference/llms-txt.md` |
| `checklist [path]` | Quick 15-item verification against prerendered HTML | `reference/checklist.md` |
| `audit-build [dir]` | Audit every page of a built site, optionally diffed against the live build; framework-agnostic | `reference/audit-build.md` |

When no sub-command is given, default to `audit` on the target path. Use `audit-build` when a change touches many pages (a rebuild, a migration, a redesign) or when you need to know what it does to pages that already rank.

## Anti-Patterns

- **Browser-only guard on JSON-LD**: Never guard structured data with browser checks (e.g., `isPlatformBrowser` in Angular) -- it must render during SSR/SSG
- **Missing cleanup**: Always remove JSON-LD scripts on component destroy to prevent duplication during SPA navigation
- **Hardcoded dates**: Use the current date for `dateModified` in schemas
- **Generic descriptions**: Every page needs a unique, specific meta description
- **Missing sitemap entry**: Every new page must be added to the sitemap
- **Missing prerender config**: Every new page must be configured for prerendering (e.g., routes.txt in Angular SSG)
