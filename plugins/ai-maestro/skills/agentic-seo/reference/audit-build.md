Audit a whole **built** site, and optionally diff it against the build that is live now. Use it for rebuilds, migrations, redesigns and any change that touches many pages. `audit` reads one component's source; this reads the HTML crawlers get, for every page, in one run. It works for any framework that writes static HTML.

Run it with `python3 scripts/audit_build.py` (Python 3 standard library only). It reads files, sends nothing, and writes only the CSV you name.

## Steps

1. **Build the candidate** to a clean directory. Build from `git archive <commit>`, not from a working tree with uncommitted edits. A stale or dirty `dist/` gives you a verdict on code nobody committed.
2. **Build the baseline**: the code that is live now (for example `git archive main`), built the same way.
3. **Prove the baseline is the live site.** Compare its `sitemap.xml` to `{DOMAIN}/sitemap.xml`. If they differ, the diff measures the wrong thing.
4. Run the tool:

   ```bash
   python3 scripts/audit_build.py CANDIDATE_DIR --domain {DOMAIN} \
       --baseline BASELINE_DIR --csv audit.csv [--twitter-handle {TWITTER_HANDLE}] [--strict-claims]
   ```
5. Read the output, then report (see "Report the evidence").

`python3 scripts/audit_build.py --self-test` runs the tool against a fixture. A clean fixture must raise zero failures, and every planted defect must fire. Run it once after you change the tool.

## What it checks

**Per page, hard (fails the page):** title and description present · canonical equals `{DOMAIN}` + route · all nine Open Graph tags and the four required Twitter tags · `og:url` matches the canonical · the `og:image` file exists in the build · JSON-LD present and parses · exactly one `h1` · no skipped heading level · every `img` has an `alt` attribute · at least one internal link · no broken internal link (a redirect source counts as served) · an indexable page is in the sitemap · a `noindex` page is not.

**Per page, advisory (counted and listed, never a fail):** title length outside 50–60 · description length outside 150–160 · `keywords` (Google ignores it) · `author` · `twitter:site` and `twitter:creator` (only when you pass `--twitter-handle`) · fewer than two schema types (a quota is never a target) · an `img` with `alt=""` (valid for decoration; confirm by eye).

**Site-wide:** sitemap lists a URL with no built page · a `_redirects` source is still built (the static page wins over the rule, so the redirect never fires; the spec must say which pages stop being built) · a redirect target is not built · duplicate titles.

**Against the baseline:** URLs removed and added · pages whose index state (`noindex`) changed · canonical, title, description and JSON-LD changes · whether `_redirects` or `sitemap.xml` changed. A hard failure that the baseline already has is **inherited**; one it does not have is **new**. Fix new failures first; they are the ones this change caused.

`--strict-claims` fails any JSON-LD that carries `price`, `priceRange`, `offers`, `availability`, `openingHours`, `aggregateRating` or `review`. Turn it on when the business has no published price policy and no consented reviews. Structured data must not claim what the page cannot back.

## Report the evidence

Write findings so a reader can test them.

- **Lead with the numbers line** the tool prints, then the failures.
- **Say how you measured.** "146 pages, built from commit `abc123`, baseline built from `main`, whose sitemap matches the live sitemap." Say whether a number is a total or a floor.
- **Mark every claim.** VERIFIED (you ran it; here is the number), REASONED (it follows from a verified fact), or OPEN (you do not know; say who does).
- **A negative result needs a positive control.** A check that finds nothing proves nothing until you know it would have fired. `--self-test` is the control for the tool; for a live-site fetch, fetch a URL you know is wrong too.
- **Do not audit a baseline you have not proven.** Step 3 exists for this.
- **Keep copy out of the verdict.** Titles, descriptions and on-page claims belong to the people who own the words. Report them; do not rewrite them.
