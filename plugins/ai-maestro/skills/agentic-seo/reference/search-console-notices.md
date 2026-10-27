How to investigate a Search Console notice about markup or URLs you do not recognize, for example "Merchant listings structured data issues" on a site that sells nothing. Agents cannot read Search Console; the property owner reads it and pastes what it shows.

## Contents

- What a notice covers
- Merchant listings notices
- Investigate an unknown URL
- Ask Google to hide URLs you do not own
- What not to do
- Report the evidence

## What a notice covers

A **Domain property** covers every host under the domain: the bare domain, `www`, every subdomain, `http` and `https`. Your source repository is one origin among several. A notice can describe a page your current site never had: an old origin, a forgotten subdomain, or content someone else injected. Treat "our code does not emit it" and "Google does not hold it" as two separate questions.

## Merchant listings notices

Merchant listings are Google's product listings. The notice means Google found `Product` markup with an `Offer` on some URL of the property. Its items ("missing `shippingDetails`", "missing `hasMerchantReturnPolicy`", "not a globally valid GTIN") are suggestions for a store that sells physical goods. Google's page: https://developers.google.com/search/docs/appearance/structured-data/merchant-listing

- **The site sells products:** complete the fields from your real shipping and returns terms, per Google's page.
- **The site sells no products:** no page should carry `Product`, `Offer`, `gtin`, `shippingDetails` or `hasMerchantReturnPolicy`. Do not add the missing fields. A shipping time and a return policy are commitments; writing them to clear a notice invents terms. Find the page and remove it from Google.

## Investigate an unknown URL

Do these in order. Each step names its control.

1. **Get the example URLs.** In Search Console open the report, the issue, then **Examples**. Ask the owner to paste them. A notice without a URL cannot be searched for.
2. **Fetch the URL on every host variant:** bare domain, `www`, `http`, `https`, each known subdomain. Do it twice: with a normal user agent, and with a Googlebot user agent plus a Google referrer (a cloaking test). Control: fetch a page you know exists, and a path you know is wrong. A 404 today does not show the page was never served. Google may last have crawled it weeks ago.
3. **Search your source and its history.** `git grep` for a distinctive string, and `git log --all -S"string"` for every past revision. Control: search for a string you know is there. No hit means your repository never held it.
4. **Scan the live site for the markup.** Fetch the sitemap URLs plus the pages your hub pages link to; search for `shippingDetails`, `hasMerchantReturnPolicy`, `gtin`, `"Product"`, `"Offer"`, `priceCurrency`. Say it is a floor: pages that nothing links to are not in it.
5. **Enumerate hostnames.** List the DNS records you can read; try common names (`store`, `shop`, `wp`, `blog`, `old`, `app`). Compare the response bodies: identical hashes mean one origin answers for several names. Look up the owner of any address outside your CDN. An old origin that still answers is the first place to ask for logs.
6. **Read the URL Inspection panel.** Fields that matter: last crawl date, crawled as, page fetch, user-declared canonical, **referring page** (another unrelated URL on the site means a catalog, not one page), the sitemap line, and the structured-data panels. A **Review snippets** item on a site that has no reviews is a strong spam signal.
7. **Check the Internet Archive** (`archive.org/wayback/available?url=...`). Say if the archive is unreachable from your tool; no snapshot is not proof.
8. **Say what you cannot settle.** Who served the page, and when, needs the hosting logs and the CDN rule list. Name the owner who can read them.

## Ask Google to hide URLs you do not own

The owner presses this; it is reversible. Steps checked against Google's Removals help page (https://support.google.com/webmasters/answer/9689846):

1. Search Console, **Indexing**, **Removals**, tab **Temporary Removals**.
2. **New Request**, **Temporarily remove URL**, **Remove all URLs with this prefix**.
3. Type the exact prefix, for example `https://example.com/products/`. Never submit the site root. The prefix covers http, https, www and non-www.
4. **Next**, **Submit request**. The history table shows "Processing request", "Temporarily removed", "Request denied" or "Removal expired". Google says a request usually takes up to a day and is not guaranteed.

The block lasts about six months. It is not permanent: the URL must return 404 or 410, or carry `noindex`. The help page does not say whether Domain properties accept the tool; if the option is missing, report what the screen shows.

After it: check Performance (filter by page, URL contains the prefix), Pages, and **Security issues** and **Manual actions**. A property added a day ago has no data for several days. Re-check after three days and after a week.

## What not to do

- Do not add fields to satisfy a notice about pages you do not want.
- Do not block the prefix in `robots.txt`. Google then cannot fetch the 404 or `noindex` that removes the page.
- Do not change DNS records for old subdomains without the account owner. Ask first.
- Do not read a clean Security report as proof of no compromise. It means Google has not flagged the site.

## Report the evidence

Lead with the answer: is it your site, or an origin you do not control. Give the method inside each number ("fetched 50 sitemap URLs and 129 linked pages, none carry the markup; a floor"). Mark every claim VERIFIED, REASONED or OPEN, and name the owner of each OPEN item.
