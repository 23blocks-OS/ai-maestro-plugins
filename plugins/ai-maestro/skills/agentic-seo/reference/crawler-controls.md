Neutral guide to crawler controls. It takes no position: the site owner decides between appearing in AI answers and having content used for model training. Ask the owner; do not change robots.txt on your own.

## Contents

- Google: what decides appearance in AI features
- Google-Extended
- Vendor crawler tokens (OpenAI, Anthropic, Perplexity, Common Crawl, Apple)
- Example robots.txt
- Re-check before relying on this

Facts below were fetched 2026-10-10. Tokens and policies change; re-check each page before acting.

## Google: what decides appearance in AI features

Google's page on AI features (https://developers.google.com/search/docs/appearance/ai-features, last updated 2025-12-10) says: "To limit the information shown from your pages in Search, use `nosnippet`, `data-nosnippet`, `max-snippet`, or `noindex` controls." These are page-level controls in the page's robots meta tag, an `X-Robots-Tag` header, or the `data-nosnippet` attribute on an element. `noindex` removes the page from Search entirely, so it is the strongest of the four.

## Google-Extended

Google's crawler documentation (https://developers.google.com/search/docs/crawling-indexing/google-common-crawlers, last updated 2026-07-14) says: "Google-Extended is a standalone product token that web publishers can use to manage whether content Google crawls from their sites may be used for training future generations of Gemini models." and "Google-Extended does not impact a site's inclusion in Google Search nor is it used as a ranking signal in Google Search." So it does not control AI Overviews; the controls in the previous section do. The page as fetched speaks of training; check it for any grounding wording before telling the owner what Google-Extended covers beyond that.

## Vendor crawler tokens

Each row cites the vendor's own page.

| Token | Vendor | What the vendor's page says | Source |
|-------|--------|-----------------------------|--------|
| `GPTBot` | OpenAI | Crawls to make generative AI foundation models "more useful and safe"; disallowing it keeps content out of model training | https://developers.openai.com/api/docs/bots (no date shown) |
| `OAI-SearchBot` | OpenAI | "used to surface websites in search results in ChatGPT's search features"; disallowing it excludes the site from those results | same page |
| `ClaudeBot` | Anthropic | Collects web content for generative AI models (training) | https://support.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler (2026-04-07) |
| `Claude-SearchBot` | Anthropic | Navigates the web "to improve search result quality for users" | same page |
| `Claude-User` | Anthropic | Retrieves pages when a person asks Claude a question (user-initiated) | same page |
| `PerplexityBot` | Perplexity | "designed to surface and link websites in search results on Perplexity"; "not used to crawl content for AI foundation models"; respects robots.txt | https://docs.perplexity.ai/guides/bots (no date shown) |
| `CCBot` | Common Crawl | Crawler of a non-profit that maintains an open repository of web crawl data; control with `User-agent: CCBot` | https://commoncrawl.org/ccbot (no date shown) |
| `Applebot-Extended` | Apple | Does not crawl; disallowing it opts content out of training Apple's general-purpose foundation models; pages can still appear in search through Applebot | https://support.apple.com/en-us/119829 (2026-09-04) |

Notes from the same pages: Anthropic says its bots honor robots.txt directives and that blocking by IP address "may not work correctly". OpenAI says robots.txt rules may not apply to `ChatGPT-User`, which acts on a user's request. Perplexity says `Perplexity-User` generally ignores robots.txt because a user requested the fetch, and that robots.txt changes can take up to 24 hours to apply.

Not verified, check the vendor's page: any token not in the table, and any behavior beyond the quoted sentences.

## Example robots.txt

An example only, not a recommendation. Choose lines per owner decision.

```
# Example: allow search and user-initiated fetches, opt out of model training
User-agent: GPTBot
Disallow: /

User-agent: ClaudeBot
Disallow: /

User-agent: CCBot
Disallow: /

User-agent: Applebot-Extended
Disallow: /

User-agent: Google-Extended
Disallow: /

# Search-oriented crawlers stay allowed
User-agent: OAI-SearchBot
Allow: /

User-agent: Claude-SearchBot
Allow: /

User-agent: PerplexityBot
Allow: /
```

Reverse every line to opt in instead. robots.txt is a request that well-behaved crawlers honor, not access control.

## Re-check before relying on this

Vendor tokens are added, renamed and re-scoped. Fetch each cited page again, note its date, and update this file when they differ.
