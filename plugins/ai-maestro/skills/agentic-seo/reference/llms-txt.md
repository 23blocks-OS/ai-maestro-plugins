Guide for maintaining `llms.txt` and `llms-full.txt` files for AI agent discoverability. These files follow the llmstxt.org specification and help non-Google AI agents understand what your site offers.

**Important**: Use the site configuration gathered during first-time setup (`{SITE_NAME}`, `{DOMAIN}`, etc.). If not yet gathered, ask the user first per SKILL.md instructions.

## File Locations

Identify where these files live in the user's project:
- **llms.txt**: Concise summary (~65 lines)
- **llms-full.txt**: Comprehensive reference (~600 lines)
- **Live URLs**: `{DOMAIN}/llms.txt` and `{DOMAIN}/llms-full.txt`

## llmstxt.org Format Specification

### Structure

```
# {SITE_NAME}

> Short description (blockquote)

## Section Name

- [Link Title]({DOMAIN}/path): Brief description of what this link covers

## Optional

- [Link Title]({DOMAIN}/path): Non-essential links
```

### Rules

1. Start with `# {SITE_NAME}` as H1
2. Follow with a `> blockquote` summary
3. Organize links into `## Sections`
4. Each link: `- [Title](url): description`
5. Put non-essential links under `## Optional`
6. Keep descriptions concise (one line per link)
7. Use full URLs (`{DOMAIN}/...`)

## When to Update

### llms.txt (concise version)

Update when:
- A new major product/feature is added
- A new major page is created
- Key URLs change
- The product description changes

Content to include:
- Product overview
- Key product/feature descriptions (one line each)
- Documentation link
- Getting started link
- API reference link

### llms-full.txt (comprehensive version)

Update when:
- New API endpoints are added
- Detailed feature descriptions change
- New integration guides are published
- Product capabilities expand

Content to include:
- Everything in llms.txt PLUS:
- Detailed product/feature descriptions
- All API endpoints
- Integration instructions
- Authentication details
- Code examples (brief)

## Editing Workflow

1. **Read current file**: Check what's already there before editing
2. **Identify the change**: New product? New feature? Updated description?
3. **Find the right section**: Add new links to the appropriate `## Section`
4. **Maintain alphabetical order**: Within each section, keep links sorted
5. **Keep descriptions consistent**: Match the style of existing entries
6. **Update both files**: If the change affects llms.txt, it likely affects llms-full.txt too

## robots.txt Reference

Both files should be referenced in the site's `robots.txt`:

```
# AI Agent Discovery
# llms.txt: {DOMAIN}/llms.txt
# llms-full.txt: {DOMAIN}/llms-full.txt
```

Verify this reference exists when updating the llms files.

## Important Notes

- **llms.txt is NOT for Google**: Google uses standard crawling and structured data (JSON-LD). llms.txt is for non-Google AI agents (Claude, GPT, etc.)
- **Don't duplicate sitemap**: llms.txt is a curated summary, not a comprehensive URL list
- **Keep llms.txt concise**: It should be scannable by an AI in one pass (~65 lines max)
- **llms-full.txt can be detailed**: This is where you put comprehensive API and feature documentation
- **Test readability**: The content should make sense to an AI agent that has no prior context about the site

## Validation

After updating, verify:

```bash
# Check file exists and has content
wc -l path/to/llms.txt
wc -l path/to/llms-full.txt

# Verify format starts correctly
head -5 path/to/llms.txt

# Check robots.txt references
grep 'llms' path/to/robots.txt
```
