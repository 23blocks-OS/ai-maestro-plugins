Guide for maintaining an `llms.txt` file, only when the site owner wants one.

## Contents

- Status (dated)
- When to add one
- Format (llmstxt.org)
- Editing workflow
- Validation

## Status (dated)

Dated 2026-10-10. Google's guide on generative AI features (https://developers.google.com/search/docs/fundamentals/ai-optimization-guide, last updated 2026-07-10) says Google Search itself doesn't use llms.txt files, and that having one "will neither harm nor help your site's visibility or rankings in Google Search". I could not find documentation from any major AI vendor saying its crawler or assistant reads llms.txt; re-check the vendors' pages (see `reference/crawler-controls.md`) before relying on this.

## When to add one

Add it only if the owner wants it and the cost is low (a short hand-written file). Never claim a ranking or citation benefit. If the site already has good docs and a sitemap, skipping it is a reasonable choice.

**Important**: Use the site configuration gathered during first-time setup (`{SITE_NAME}`, `{DOMAIN}`). If not yet gathered, ask the user first per SKILL.md instructions.

## Format (llmstxt.org)

From https://llmstxt.org (fetched 2026-10-10): the file is Markdown named `llms.txt` at the site root (or a subpath). The only required element is an H1 with the name of the project or site. After it, in order: an optional blockquote summary, zero or more Markdown sections without headings, and zero or more H2-delimited file lists. Each list item has a required link `[name](url)`, optionally followed by `:` and notes. An H2 section named `Optional` marks secondary links an agent can skip when it needs a shorter context. The spec sets no size limit beyond staying small enough to fit in context, and does not define `llms-full.txt`.

```
# {SITE_NAME}

> Short description

## Docs

- [Link Title]({DOMAIN}/path): what this link covers

## Optional

- [Link Title]({DOMAIN}/path): secondary link
```

## Editing workflow

1. Read the current file before editing.
2. Add or change links in the matching section; keep descriptions in the style of existing entries.
3. Use full URLs (`{DOMAIN}/...`). Do not duplicate the sitemap; the file is a curated summary.
4. If the site also publishes a longer companion file, update it in the same change. That file is the owner's own convention, not part of the spec.

## Validation

```bash
head -5 path/to/llms.txt          # starts with "# Name", then "> summary"
grep -c '^- \[' path/to/llms.txt  # every list item is a link
```
