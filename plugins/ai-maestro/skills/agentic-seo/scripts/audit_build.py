#!/usr/bin/env python3
"""audit_build.py - audit a whole BUILT site (static HTML) and, optionally, diff it against a baseline.

Python 3 standard library only. Reads files. Sends nothing. Writes only what --csv names.

  audit_build.py BUILD_DIR --domain https://acme.com [--baseline BASE_DIR]
                 [--twitter-handle @acme] [--csv out.csv] [--strict-claims]
  audit_build.py --self-test

BUILD_DIR   the built output (dist/, out/, public/ ...), one index.html per route.
--baseline  another build of the CURRENT live site (for example `git archive main`, then build).
            The diff answers "what does this change do to what already ranks?"
--strict-claims   fail JSON-LD that carries price, rating, review, availability or opening-hours
            fields. Use it when the business has no consented reviews and no published price.

Hard checks FAIL a page. Advisory checks never do; they are counted and listed apart.
"""
import argparse, csv, json, os, re, sys, tempfile, collections
from html.parser import HTMLParser

CLAIMS = re.compile(r'aggregateRating|ratingValue|"review"|"Review"|priceRange|"price"|"offers"|availability|openingHours', re.I)


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = ''; self._t = False
        self.meta = {}; self.canonical = None
        self.headings = []; self._h = None; self._hb = ''
        self.ld = []; self._ld = False; self._lb = ''
        self.links = []; self.imgs = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'title': self._t = True
        elif tag == 'meta':
            k = a.get('name') or a.get('property')
            if k: self.meta.setdefault(k, a.get('content', ''))
        elif tag == 'link' and (a.get('rel') or '').lower() == 'canonical': self.canonical = a.get('href')
        elif tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'): self._h = int(tag[1]); self._hb = ''
        elif tag == 'script' and a.get('type') == 'application/ld+json': self._ld = True; self._lb = ''
        elif tag == 'a' and a.get('href'): self.links.append(a['href'])
        elif tag == 'img': self.imgs.append(a)

    def handle_endtag(self, tag):
        if tag == 'title': self._t = False
        elif self._h and tag == 'h%d' % self._h: self.headings.append((self._h, self._hb.strip())); self._h = None
        elif tag == 'script' and self._ld: self.ld.append(self._lb); self._ld = False

    def handle_data(self, data):
        if self._t: self.title += data
        if self._h: self._hb += data
        if self._ld: self._lb += data


def load(root):
    """Map route -> parsed page. '/about/index.html' -> '/about/'."""
    pages = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.endswith('.html'):
                rel = os.path.relpath(os.path.join(dp, f), root).replace(os.sep, '/')
                route = '/' + rel[:-len('index.html')] if rel.endswith('index.html') else '/' + rel
                p = Page(); p.feed(open(os.path.join(dp, f), encoding='utf-8', errors='replace').read())
                pages[route] = p
    return pages


def robots(p): return p.meta.get('robots', '').lower()
def indexable(p): return 'noindex' not in robots(p)


def sitemap_urls(root):
    f = os.path.join(root, 'sitemap.xml')
    return set(re.findall(r'<loc>\s*([^<\s]+)\s*</loc>', open(f, encoding='utf-8').read())) if os.path.exists(f) else None


def redirects(root):
    f = os.path.join(root, '_redirects'); out = []
    if os.path.exists(f):
        for l in open(f, encoding='utf-8'):
            t = l.split()
            if len(t) >= 2 and not l.lstrip().startswith('#'): out.append((t[0], t[1]))
    return out


def exists(root, pages, path):
    path = path.split('#')[0].split('?')[0]
    if path in pages or path.rstrip('/') + '/' in pages: return True
    return os.path.isfile(os.path.join(root, path.lstrip('/')))


def page_checks(route, p, root, pages, domain, handle, strict, redir_src):
    hard, adv = [], []
    t = p.title.strip(); d = p.meta.get('description', '')
    if not t: hard.append('no title')
    elif not 50 <= len(t) <= 60: adv.append('title %d chars' % len(t))
    if not d: hard.append('no description')
    elif not 150 <= len(d) <= 160: adv.append('description %d chars' % len(d))
    want = domain + route
    if p.canonical != want: hard.append('canonical %r, want %r' % (p.canonical, want))
    if not p.meta.get('robots'): adv.append('no meta robots')
    if not p.meta.get('keywords'): adv.append('no meta keywords')      # Google ignores it
    if not p.meta.get('author'): adv.append('no meta author')
    for k in ('og:type', 'og:site_name', 'og:title', 'og:description', 'og:url', 'og:image',
              'og:image:width', 'og:image:height', 'og:locale', 'twitter:card', 'twitter:title',
              'twitter:description', 'twitter:image'):
        if not p.meta.get(k): hard.append('missing ' + k)
    if p.meta.get('og:url') and p.meta['og:url'].rstrip('/') != want.rstrip('/'): hard.append('og:url != canonical')
    img = p.meta.get('og:image', '')
    if img.startswith(domain) and not os.path.isfile(os.path.join(root, img[len(domain):].lstrip('/'))):
        hard.append('og:image file not in build')
    if handle:
        for k in ('twitter:site', 'twitter:creator'):
            if not p.meta.get(k): adv.append('missing ' + k)
    if not p.ld: hard.append('no JSON-LD')
    types = set()
    for b in p.ld:
        try:
            j = json.loads(b)
            for n in (j.get('@graph', [j]) if isinstance(j, dict) else j):
                ty = n.get('@type') if isinstance(n, dict) else None
                types.update(ty if isinstance(ty, list) else [ty])
        except Exception: hard.append('JSON-LD does not parse')
        if strict and CLAIMS.search(b): hard.append('JSON-LD carries a price/rating/review/availability term')
    if p.ld and len(types - {None}) < 2: adv.append('fewer than 2 schema types')   # advisory, never a target
    h1 = [t for lv, t in p.headings if lv == 1]
    if len(h1) != 1: hard.append('%d H1' % len(h1))
    last = 0
    for l, x in p.headings:
        if last and l > last + 1: hard.append('heading skip h%d->h%d' % (last, l)); break
        last = l
    for i in p.imgs:
        if 'alt' not in i: hard.append('img without alt'); break
        if i['alt'].strip() == '' and not (i.get('aria-hidden') == 'true' or i.get('role') in ('presentation', 'none')):
            adv.append('img with empty alt: confirm it is decoration'); break   # alt="" is valid for decoration; the tool cannot tell
    internal = [a for a in p.links if a.startswith('/') or a.startswith(domain)]
    if not internal: hard.append('no internal link')
    for a in internal:
        path = a[len(domain):] if a.startswith(domain) else a
        if path.startswith('//') or not path.startswith('/'): continue
        if not exists(root, pages, path) and path.split('#')[0].split('?')[0] not in redir_src:
            hard.append('broken internal link ' + a); break
    return hard, adv


def audit(root, domain, base=None, handle=None, strict=False):
    pages = load(root); domain = domain.rstrip('/')
    sm = sitemap_urls(root); reds = redirects(root); rsrc = {s for s, _ in reds}
    rows = {}; site = []
    for r, p in sorted(pages.items()):
        if r == '/404.html': continue
        h, a = page_checks(r, p, root, pages, domain, handle, strict, rsrc)
        if sm is not None:
            if indexable(p) and domain + r not in sm: h.append('indexable, not in sitemap')
            if not indexable(p) and domain + r in sm: h.append('noindex, but in sitemap')
        rows[r] = [h, a]
    if sm is not None:
        for u in sorted(sm):
            if u.startswith(domain) and u[len(domain):] not in pages: site.append('sitemap lists %s, no page built' % u)
    for s, t in reds:
        if exists(root, pages, s) and s not in ('/*',): site.append('redirect source %s is still built; the static page wins' % s)
        if t.startswith('/') and not exists(root, pages, t): site.append('redirect target %s is not built' % t)
    titles = collections.defaultdict(list)
    for r, p in pages.items():
        if r != '/404.html' and p.title.strip(): titles[p.title.strip()].append(r)
    for t, rs in titles.items():
        if len(rs) > 1: site.append('duplicate title %r: %s' % (t, ', '.join(sorted(rs))))
    diff = None
    if base:
        bp = load(base); diff = {
            'removed': sorted(set(bp) - set(pages)), 'added': sorted(set(pages) - set(bp)),
            'index_state': sorted(r for r in bp if r in pages and indexable(bp[r]) != indexable(pages[r])),
            'canonical': sorted(r for r in bp if r in pages and bp[r].canonical != pages[r].canonical),
            'title': sorted(r for r in bp if r in pages and bp[r].title.strip() != pages[r].title.strip()),
            'description': sorted(r for r in bp if r in pages and bp[r].meta.get('description') != pages[r].meta.get('description')),
            'jsonld': sorted(r for r in bp if r in pages and [json.loads(x) if x.strip().startswith(('{', '[')) else x for x in bp[r].ld] != [json.loads(x) if x.strip().startswith(('{', '[')) else x for x in pages[r].ld]),
            'redirects_changed': redirects(base) != reds, 'sitemap_changed': sitemap_urls(base) != sm,
            'base_pages': len(bp),
        }
        bsm = sitemap_urls(base)
        # "inherited" = the same hard failure already exists on the baseline
        brs = {s for s, _ in redirects(base)}
        for r, (h, a) in rows.items():
            if r in bp:
                bh, _ = page_checks(r, bp[r], base, bp, domain, handle, strict, brs)
                if bsm is not None:
                    if indexable(bp[r]) and domain + r not in bsm: bh.append('indexable, not in sitemap')
                    if not indexable(bp[r]) and domain + r in bsm: bh.append('noindex, but in sitemap')
                rows[r].append(sorted(set(h) - set(bh)))
            else: rows[r].append(list(h))
    return pages, rows, site, diff


def report(rows, site, diff, csv_path=None):
    n = len(rows); fails = {r for r, v in rows.items() if v[0]}
    new = {r for r, v in rows.items() if len(v) > 2 and v[2]}
    print('# Build audit: %d pages checked (404 excluded)' % n)
    print('PASS %d | FAIL %d | advisory notes on %d pages' % (n - len(fails), len(fails), sum(1 for v in rows.values() if v[1])))
    if diff is not None:
        print('FAIL that the baseline does not already have (new): %d' % len(new))
        print('NUMBERS: %d of %d baseline URLs survive | removed %d | added %d | index state changed %d | canonical changed %d | title changed %d | description changed %d | JSON-LD changed %d | redirects changed %s | sitemap changed %s'
              % (diff['base_pages'] - len(diff['removed']), diff['base_pages'], len(diff['removed']), len(diff['added']),
                 len(diff['index_state']), len(diff['canonical']), len(diff['title']), len(diff['description']),
                 len(diff['jsonld']), diff['redirects_changed'], diff['sitemap_changed']))
        for k in ('removed', 'added', 'index_state', 'canonical'):
            if diff[k]: print('  %s: %s' % (k, diff[k]))
    for s in site: print('SITE:', s)
    for r in sorted(new if diff is not None else fails): print('  FAIL%s %s: %s' % (' (new)' if diff is not None else '', r, '; '.join(rows[r][2] if diff is not None else rows[r][0])))
    print('Method: counts come from the files in the build directory. They are totals for this build, not a sample.')
    if csv_path:
        with open(csv_path, 'w', newline='') as f:
            w = csv.writer(f); w.writerow(['route', 'verdict', 'new_vs_baseline', 'hard_failures', 'advisory'])
            for r in sorted(rows):
                v = rows[r]; w.writerow([r, 'FAIL' if v[0] else 'PASS', ('NEW' if v[2] else 'inherited' if v[0] else '') if len(v) > 2 else '', '; '.join(v[0]), '; '.join(v[1])])
    return 1 if fails or site else 0


def selftest():
    """Positive and negative control. A clean fixture must pass; each planted defect must fire."""
    dom = 'https://t.example'
    def page(route, extra='', robots='index, follow', title=None, canon=None, h='<h1>One</h1>'):
        c = canon if canon is not None else dom + route
        title = title or 'Page %s title' % route
        ld = '<script type="application/ld+json">{"@graph":[{"@type":"Organization"},{"@type":"WebSite"}]}</script>'
        m = ''.join('<meta property="%s" content="x">' % k for k in ('og:type', 'og:site_name', 'og:title', 'og:description', 'og:image', 'og:image:width', 'og:image:height', 'og:locale'))
        m += '<meta property="og:url" content="%s">' % c
        m += ''.join('<meta name="%s" content="x">' % k for k in ('twitter:card', 'twitter:title', 'twitter:description', 'twitter:image'))
        return '<html><head><title>%s</title><meta name="description" content="d"><meta name="robots" content="%s"><link rel="canonical" href="%s">%s%s</head><body>%s<a href="/">home</a>%s</body></html>' % (title, robots, c, m, ld, h, extra)
    with tempfile.TemporaryDirectory() as t:
        for sub, files in (('good', {'index.html': page('/'), 'a/index.html': page('/a/'), 'og.png': 'x'}),):
            for f, c in files.items():
                os.makedirs(os.path.dirname(os.path.join(t, sub, f)), exist_ok=True); open(os.path.join(t, sub, f), 'w').write(c)
        open(os.path.join(t, 'good/sitemap.xml'), 'w').write('<urlset><url><loc>%s/</loc></url><url><loc>%s/a/</loc></url></urlset>' % (dom, dom))
        for f in ('good/index.html', 'good/a/index.html'):
            s = open(os.path.join(t, f)).read().replace('content="x">', 'content="x">', 1); open(os.path.join(t, f), 'w').write(s)
        # make og:image resolvable
        for f in ('good/index.html', 'good/a/index.html'):
            p = os.path.join(t, f); s = open(p).read().replace('<meta property="og:image" content="x">', '<meta property="og:image" content="%s/og.png">' % dom); open(p, 'w').write(s)
        _, rows, site, _ = audit(os.path.join(t, 'good'), dom)
        assert not any(v[0] for v in rows.values()) and not site, ('negative control failed', rows, site)
        bad = {'index.html': page('/', robots='noindex, follow'), 'a/index.html': page('/a/', canon=dom + '/wrong/', h='<h1>One</h1><h3>skip</h3><img src="x.png">'),
               'b/index.html': page('/b/', robots='noindex, follow')}
        for f, c in bad.items():
            p = os.path.join(t, 'bad', f); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w').write(c.replace('content="x">', 'content="x">'))
        open(os.path.join(t, 'bad/sitemap.xml'), 'w').write('<urlset><url><loc>%s/</loc></url><url><loc>%s/b/</loc></url><url><loc>%s/gone/</loc></url></urlset>' % (dom, dom, dom))
        open(os.path.join(t, 'bad/_redirects'), 'w').write('/a/ /nowhere/ 301\n')
        _, rows, site, diff = audit(os.path.join(t, 'bad'), dom, base=os.path.join(t, 'good'))
        want = ['canonical', 'heading skip', 'img without alt', 'indexable, not in sitemap', 'noindex, but in sitemap']
        got = ' | '.join(sum((v[0] for v in rows.values()), []))
        for w in want: assert w in got, ('positive control: did not fire', w, got)
        assert any('no page built' in s for s in site) and any('still built' in s for s in site) and any('not built' in s for s in site), site
        assert diff['canonical'] == ['/a/'] and diff['index_state'] == ['/'] and diff['added'] == ['/b/'], diff
    print('self-test passed: clean fixture raised 0 failures; every planted defect fired.')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('build', nargs='?'); ap.add_argument('--domain'); ap.add_argument('--baseline')
    ap.add_argument('--twitter-handle'); ap.add_argument('--csv'); ap.add_argument('--strict-claims', action='store_true')
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args()
    if a.self_test: return selftest()
    if not a.build or not a.domain: ap.error('BUILD_DIR and --domain are required')
    _, rows, site, diff = audit(a.build, a.domain, a.baseline, a.twitter_handle, a.strict_claims)
    return report(rows, site, diff, a.csv)


if __name__ == '__main__':
    sys.exit(main())
