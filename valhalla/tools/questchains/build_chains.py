#!/usr/bin/env python3
# Valhalla 1.1.0: the quest chains (Data/Forever/QuestChains.lua) from Wowhead WoW Forever's "Series" boxes.
# Box only. Nothing from QuestieDB is shipped: it only says which pages to read (candidates), and is
# compared against (report), and links two Wowhead series end to end where it agrees (D2b).
#
#   build_chains.py urls   -> chain-data/urls.txt (pass 1: one page per QuestieDB chain start) and
#                             chain-data/urls-all.txt (every candidate quest, the upper bound)
#   build_chains.py check  -> every saved page read: good / not a quest page (captcha, error) / no series
#   build_chains.py next   -> chain-data/urls-next.txt: candidates no saved page's Series box has covered yet
#                             and not saved themselves (pass 2, 3, ... until empty)
#   build_chains.py current -> chain-data/urls-current.txt: one page per QuestieDB chain holding a quest in
#                             chain-data/current-log.tsv (the log quest's own page: its Series box shows that quest's
#                             series), and urls-current-maybe.txt (log quests in no chain but pre-quest linked)
#   build_chains.py next [--current] -> as next, only the chains of current-log.tsv's quests with --current
#   build_chains.py build [out.lua] -> the data file (default: the repo's Data/Forever/QuestChains.lua) and
#                             chain-data/report/{coverage.txt, disagree.csv, quickfacts.txt}
#
# Pages: chain-data/pages/quest-<id>.html, the page's full HTML (page source or document.documentElement.outerHTML),
# one per quest page; chain-data/pages/index.tsv lines "<id>\t<url>\t<fetched, ISO 8601 with offset>\t<status>"
# (the file's modified time is used, and said so, for a page missing there).
#
# Or typed in by hand from the page (the Series box read on screen): chain-data/manual/quest-<page id>.tsv
# (a page with two Series boxes: quest-<page id>-2.tsv for the second), tab separated, '#' lines ignored, a header
# line allowed:
#   pos  id  name  flags  url  fetched
#   pos: the number Wowhead shows (1, 2, ...); two lines with the same pos: one Series row ('or'), the first is the
#        main quest. id: the quest ID from the link (required; '?' = not read yet: the file is skipped and listed).
#   flags (optional, comma separated): opt (Wowhead's Quick Facts say breadcrumb), alt (the same row as the line
#        before, for a pos left blank), side=A|H, class=DRUID|class=DRUID+SHAMAN (from that quest's Quick Facts).
#   A page read with no Series box: one line "none<TAB><TAB><TAB><TAB>url<TAB>fetched" (recorded: no chain, no button).
#   url, fetched: the page read (https://www.wowhead.com/forever/quest=<id>) and when, ISO 8601 with offset
#        (2026-11-11T20:15:00-06:00); needed on the first line, later lines blank = the same.
import html, json, os, re, sys, datetime, collections

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
DATA = os.environ.get('CHAIN_DATA', '/workspace/valhalla/chain-data')
# D2b joins two Wowhead series where QuestieDB links them: OFF until the owner approves (build --join, or CHAIN_JOIN=1);
# off, each Wowhead series is its own chain
JOIN = os.environ.get('CHAIN_JOIN') == '1' or '--join' in sys.argv
PAGES = os.path.join(DATA, 'pages')
QDB = os.path.join(DATA, 'questiedb', 'quests.json')
OUT_LUA = os.path.join(REPO, 'Valhalla', 'Data', 'Forever', 'QuestChains.lua')
URL = 'https://www.wowhead.com/forever/quest=%d'
CLASSES = {1: 'WARRIOR', 2: 'PALADIN', 3: 'HUNTER', 4: 'ROGUE', 5: 'PRIEST', 6: 'DEATHKNIGHT', 7: 'SHAMAN', 8: 'MAGE',
           9: 'WARLOCK', 10: 'MONK', 11: 'DRUID', 12: 'DEMONHUNTER', 13: 'EVOKER'}
CLASS_NAMES = {v.lower().replace('deathknight', 'death knight').replace('demonhunter', 'demon hunter'): v for v in CLASSES.values()}

# ---------------------------------------------------------------- QuestieDB (box only: candidates, comparison)
def questie():
    if not os.path.exists(QDB): return {}
    return {int(k): v for k, v in json.load(open(QDB)).items()}

def candidates(qs):
    nxt = {q: a['nextQuestInChain'] for q, a in qs.items() if a.get('nextQuestInChain')}
    nodes = set(nxt) | set(nxt.values())
    roots = sorted(q for q in nodes if q not in set(nxt.values()))
    # (a ring with no start: its lowest quest)
    seen = set()
    for r in roots:
        q = r
        while q not in seen:
            seen.add(q)
            if q not in nxt: break
            q = nxt[q]
    for q in sorted(nodes - seen):
        if q in seen: continue
        roots.append(q)
        while q not in seen:
            seen.add(q); q = nxt.get(q, q)
    return sorted(nodes), sorted(set(roots)), nxt

# ---------------------------------------------------------------- a saved page
def unesc(s):
    return html.unescape(s.replace('\\/', '/').replace('\\"', '"'))

def page_text(path):
    b = open(path, 'rb').read()
    if b[:2] == b'\x1f\x8b':
        import gzip; b = gzip.decompress(b)
    return b.decode('utf-8', 'ignore')

ITEM = re.compile(r'<a[^>]+href="(?:https?://www\.wowhead\.com)?/(\w+)/quest=(\d+)[^"]*"[^>]*>(.*?)</a>|<b>(.*?)</b>', re.S)
def parse(path, qid):
    s = page_text(path)
    out = {'id': qid, 'ok': False, 'series': [], 'facts': [], 'side': None, 'classes': None, 'name': None, 'why': None, 'flavors': set()}
    if 'infobox' not in s or ('quest=%d' % qid not in s and 'Quest - Forever' not in s):
        out['why'] = 'not a Wowhead Forever quest page (captcha, error or another site?)'
        return out
    m = re.search(r'<h1[^>]*class="heading-size-1"[^>]*>(.*?)</h1>', s, re.S)
    if m: out['name'] = html.unescape(re.sub('<[^>]+>', '', m.group(1))).strip()
    if not out['name']:
        m = re.search(r'<title>(.*?) - Quest - ', s, re.S)
        if m: out['name'] = html.unescape(m.group(1)).strip()
    # Quick Facts: the markup the page prints (page source), else the printed list (a saved DOM)
    m = re.search(r'WH\.markup\.printHtml\("(\[ul\].*?)",\s*"infobox-contents', s, re.S)
    if m:
        facts = [unesc(x) for x in re.findall(r'\[li\](.*?)\[\\?/li\]', m.group(1).replace('\\/', '/'))]
    else:
        m = re.search(r'id="infobox-contents-0"[^>]*>(.*?)</div>', s, re.S)
        facts = [html.unescape(re.sub('<[^>]+>', '', x)).strip() for x in re.findall(r'<li[^>]*>(.*?)</li>', m.group(1), re.S)] if m else []
    out['facts'] = facts
    for f in facts:
        t = re.sub(r'\[[^\]]*\]', '', f).strip()
        if t.startswith('Side:'):
            v = t[5:].strip().lower()
            out['side'] = 'A' if v.startswith('alliance') else 'H' if v.startswith('horde') else None
        if t.startswith('Class:') or t.startswith('Classes:'):
            ids = [int(x) for x in re.findall(r'\[class=(\d+)\]', f)]
            names = [CLASSES[i] for i in ids if i in CLASSES]
            if not names:
                for w in re.split(r',\s*', t.split(':', 1)[1].strip()):
                    if w.lower() in CLASS_NAMES: names.append(CLASS_NAMES[w.lower()])
            out['classes'] = names or None
    out['breadcrumb'] = any('breadcrumb' in f.lower() for f in facts)
    # Series boxes (a quest can be in more than one): rows in order; a row with more than one quest: alternatives
    for tm in re.finditer(r'<table class="series">(.*?)</table>', s, re.S):
        rows = []
        for rm in re.finditer(r'<tr>\s*<th>\s*(\d+)\.\s*</th>\s*<td>(.*?)</td>\s*</tr>', tm.group(1), re.S):
            items = []
            for im in ITEM.finditer(rm.group(2)):
                if im.group(2):
                    out['flavors'].add(im.group(1))
                    items.append((int(im.group(2)), html.unescape(re.sub('<[^>]+>', '', im.group(3))).strip()))
                else:
                    items.append((qid, html.unescape(re.sub('<[^>]+>', '', im.group(4))).strip()))   # (this page's quest, in bold)
            if items: rows.append(items)
        if rows: out['series'].append(rows)
    out['ok'] = True
    return out

FLAGS = {}   # quest id -> {'opt', 'side', 'classes'} typed in a manual file (for quests other than the page's)
MANUAL = os.path.join(DATA, 'manual')
# the series read in the box browser in batches (tools/questchains/raw_to_manual.py writes them, the same format)
MANUAL_DIRS = [MANUAL, os.path.join(DATA, 'manual-wowhead')]
_T = r'\d{4}-\d\d-\d\dT\d\d:\d\d(:\d\d)?([+-]\d\d:?\d\d|Z)'
# a time, or "~<time>/<time>": read some time in that range (a batch whose per-page times were not kept)
ISO = re.compile(r'^(%s|~%s/%s)$' % (_T, _T, _T))

def parse_manual(path, qid):
    out = {'id': qid, 'ok': False, 'series': [], 'facts': [], 'side': None, 'classes': None, 'name': None, 'why': None,
           'flavors': {'forever'}, 'breadcrumb': False, 'manual': True, 'url': None, 'fetched': None}
    rows, flags, last_pos, url, fetched, errs = [], {}, None, None, None, []
    for n, line in enumerate(open(path, encoding='utf-8-sig'), 1):
        if not line.strip() or line.lstrip().startswith('#'): continue
        f = [x.strip() for x in line.rstrip('\n').split('\t')] + [''] * 6
        if f[0].lower() == 'pos': continue
        pos, i, name, fl, u, t = f[:6]
        if u: url = u
        if t: fetched = t
        if pos.lower() == 'none': out['noseries'] = True; continue   # (the page read has no Series box)
        if not i.isdigit(): errs.append('line %d: no quest id (%r)' % (n, i)); continue
        i = int(i)
        fs = [x.strip() for x in fl.split(',') if x.strip()]
        alt = 'alt' in fs or not pos or (pos == last_pos)
        if alt and rows: rows[-1].append((i, name))
        elif alt: errs.append('line %d: alt with no row before it' % n); continue
        else: rows.append([(i, name)])
        if pos: last_pos = pos
        e = {}
        for x in fs:
            if x == 'opt': e['opt'] = True
            elif x.startswith('side='): e['side'] = 'A' if x[5:].upper().startswith('A') else 'H' if x[5:].upper().startswith('H') else None
            elif x.startswith('class='): e['classes'] = [c.strip().upper() for c in re.split(r'[+/ ]', x[6:]) if c.strip()]
            elif x != 'alt': errs.append('line %d: unknown flag %r' % (n, x))
        if e: flags[i] = e
        if i == qid: out['name'] = name
    if not url: errs.append('no url')
    if not fetched or not ISO.match(fetched): errs.append('fetched missing or not ISO 8601 with offset (%r)' % fetched)
    if rows and out.get('noseries'): errs.append('both rows and a none line')
    if rows and not any(i == qid for r in rows for i, _ in r): errs.append('the page quest %d is not in its own series' % qid)
    if errs:
        out['why'] = 'manual: ' + '; '.join(errs)
        return out
    out['series'] = [rows] if len(rows) > 0 else []
    own = flags.get(qid, {})
    out['side'], out['classes'], out['breadcrumb'] = own.get('side'), own.get('classes'), bool(own.get('opt'))
    for i, e in flags.items(): FLAGS.setdefault(i, {}).update(e)
    out['url'], out['fetched'], out['when_from'], out['ok'] = url, fetched, 'manual', True
    return out

def info(i, ps):
    """(side, classes, opt, known) for quest i: its own page read, else what a manual file typed for it"""
    p, e = ps.get(i), FLAGS.get(i, {})
    if p and p['ok'] and not p.get('manual'): return p['side'], p['classes'], bool(p.get('breadcrumb')), True
    if p and p['ok']: return p['side'], p['classes'], bool(p.get('breadcrumb')), True
    if e: return e.get('side'), e.get('classes'), bool(e.get('opt')), ('side' in e or 'classes' in e)
    return None, None, False, False

def read_pages():
    """the pages read in the batches (chain-data/manual-wowhead/pages-read.tsv), any outcome but a failed load"""
    p = os.path.join(DATA, 'manual-wowhead', 'pages-read.tsv')
    out = set()
    if os.path.exists(p):
        for l in open(p, encoding='utf-8'):
            f = l.rstrip('\n').split('\t')
            if f[0].isdigit() and f[1] in ('series', 'no series', 'same series'): out.add(int(f[0]))
    return out

def fetched_index():
    idx = {}
    p = os.path.join(PAGES, 'index.tsv')
    if os.path.exists(p):
        for line in open(p, encoding='utf-8'):
            f = line.rstrip('\n').split('\t')
            if len(f) >= 3 and f[0].strip().isdigit(): idx[int(f[0])] = {'url': f[1], 'fetched': f[2], 'status': f[3] if len(f) > 3 else ''}
    return idx

def pages():
    idx = fetched_index()
    out = {}
    for fn in sorted(os.listdir(PAGES)) if os.path.isdir(PAGES) else []:   # (no saved pages: the typed ones only)
        m = re.match(r'quest-(\d+)\.(html?|txt)$', fn)
        if not m: continue
        qid = int(m.group(1)); path = os.path.join(PAGES, fn)
        p = parse(path, qid)
        e = idx.get(qid)
        if e: p['url'], p['fetched'], p['when_from'] = e['url'], e['fetched'], 'index.tsv'
        else:
            p['url'] = URL % qid
            p['fetched'] = datetime.datetime.fromtimestamp(os.path.getmtime(path)).astimezone().isoformat(timespec='seconds')
            p['when_from'] = 'file time'
        out[qid] = p
    for d in MANUAL_DIRS:
        if not os.path.isdir(d): continue
        for fn in sorted(os.listdir(d)):
            m = re.match(r'quest-(\d+)(?:-(\d+))?\.tsv$', fn)
            if not m: continue
            qid = int(m.group(1))
            p = parse_manual(os.path.join(d, fn), qid)
            if qid in out and out[qid]['ok'] and p['ok']:
                out[qid]['series'] += p['series']   # (a second box, or the same page saved and typed: both read)
            elif qid in out and out[qid]['ok']:
                print('warning: manual/%s: %s' % (fn, p['why']), file=sys.stderr)
            else:
                p['file'] = fn
                out[qid] = p
    return out

# ---------------------------------------------------------------- series -> chains
def series_of(ps):
    """every distinct series (tuple of rows; a row = tuple of (id, name)), with the pages that showed it"""
    found = collections.OrderedDict()
    for qid, p in sorted(ps.items()):
        if not p['ok']: continue
        for rows in p['series']:
            key = tuple(tuple(i for i, _ in r) for r in rows)
            if key not in found: found[key] = {'rows': rows, 'pages': []}
            found[key]['pages'].append(qid)
    return found

def links_to(qs, last_ids, first_ids):
    """QuestieDB says the series after one of last_ids starts with one of first_ids"""
    for L in last_ids:
        a = qs.get(L) or {}
        if a.get('nextQuestInChain') in first_ids: return True
    for F in first_ids:
        a = qs.get(F) or {}
        pre = (a.get('preQuestSingle') or []) + (a.get('preQuestGroup') or [])
        if any(L in pre for L in last_ids) and len(a.get('preQuestSingle') or []) <= 1: return True
    return False

def chains(ps, qs):
    ser = series_of(ps)
    keys = list(ser)
    # drop a series that is just a run inside a longer one (a page can show a shorter box)
    def flat(k): return [i for r in k for i in r]
    longer = set()
    for a in keys:
        fa = flat(a)
        for b in keys:
            if a is b: continue
            fb = flat(b)
            if len(fb) > len(fa) and any(fb[i:i + len(fa)] == fa for i in range(len(fb) - len(fa) + 1)): longer.add(a)
    keys = [k for k in keys if k not in longer]
    nxt = collections.defaultdict(list); prv = collections.defaultdict(list)
    for a in keys:
        for b in keys:
            if a is b: continue
            if JOIN and links_to(qs, a[-1], b[0]): nxt[a].append(b); prv[b].append(a)
    out = []
    starts = [k for k in keys if not prv[k]]
    for k in keys:   # (a ring of series: start anywhere once)
        if prv[k] and not any(k in c for c in out): pass
    def walk(k, path):
        path = path + [k]
        if not nxt[k] or len(path) > 12: out.append(path); return
        for b in nxt[k]:
            if b in path: out.append(path); continue
            walk(b, path)
    for k in starts: walk(k, [])
    covered = set(x for c in out for x in c)
    for k in keys:
        if k not in covered: walk(k, [])
    return out, ser

def side_class(ps, ids):
    known = [info(i, ps) for i in ids]
    known = [k for k in known if k[3]]
    sides = {k[0] for k in known}
    cls = {tuple(k[1] or ()) for k in known}
    return (sides.pop() if len(sides) == 1 else None), (list(cls.pop()) if len(cls) == 1 and () not in cls else None)

def lua_str(s): return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'

def step_lua(item, ps, sside, sclass, opt):
    i, name = item
    ps_side, ps_cls, _, known = info(i, ps)
    side = ps_side if known else sside
    cls = ps_cls if known else sclass
    parts = ['%d' % i, lua_str(name)]
    if opt: parts.append('opt = true')
    if side and side != sside: parts.append('side = "%s"' % side)
    if cls and cls != sclass: parts.append('class = ' + (lua_str(cls[0]) if len(cls) == 1 else '{ ' + ', '.join(lua_str(c) for c in cls) + ' }'))
    return parts

def build(out_lua):
    qs = questie(); ps = pages()
    paths, ser = chains(ps, qs)
    # a series of one step (Wowhead's box with one quest) is no chain: not shipped (the loader drops it anyway), listed
    one = [p for p in paths if sum(len(ser[k]['rows']) for k in p) < 2]
    paths = [p for p in paths if p not in one]
    os.makedirs(os.path.join(DATA, 'report'), exist_ok=True)
    with open(os.path.join(DATA, 'report', 'one-step.txt'), 'w') as f:
        for p in one: f.write('%s (page %d)\n' % (' '.join('%d' % i for k in p for r in ser[k]['rows'] for i, _ in r), ser[p[0]]['pages'][0]))
    lines, nquests, qset = [], 0, set()
    # (a "~<from>/<to>" range: sorted by its start, shown whole)
    times = sorted((p['fetched'] for p in ps.values() if p['ok']), key=lambda t: t.lstrip('~').split('/')[0])
    for path in paths:
        rows_all, breaks, src = [], [], []
        for k in path:
            rows_all += [(r, ser[k]) for r in ser[k]['rows']]
            breaks.append(len(rows_all))
            pg = ser[k]['pages'][0]
            src.append('%d@%s' % (pg, ps[pg]['fetched']))
        ids = [i for r, _ in rows_all for i, _ in r]
        # side / class: the chain's when every page read in it agrees (the steps not read take it); a step's own
        # where its page says otherwise
        sside, sclass = side_class(ps, ids)
        body = []
        for r, _ in rows_all:
            main, alts = r[0], r[1:]
            parts = step_lua(main, ps, sside, sclass, info(main[0], ps)[2])
            if alts:
                al = ['{ ' + ', '.join(step_lua(a, ps, sside, sclass, info(a[0], ps)[2])) + ' }' for a in alts]
                parts.append('alt = { ' + ', '.join(al) + ' }')
            body.append('{ ' + ', '.join(parts) + ' }')
            for i, _ in r: qset.add(i)
        b = breaks[:-1]
        tail = []
        if sside: tail.append('side = "%s"' % sside)
        if sclass: tail.append('class = ' + (lua_str(sclass[0]) if len(sclass) == 1 else '{ ' + ', '.join(lua_str(c) for c in sclass) + ' }'))
        if b: tail.append('breaks = { ' + ', '.join(str(x) for x in b) + ' }')
        tail.append('src = { ' + ', '.join(lua_str(x) for x in src) + ' }')
        lines.append('\t\t{ ' + ', '.join(body) + ', ' + ', '.join(tail) + ' },')
    now = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
    head = [
        '-- Valhalla: the quest log\'s Chain quest view (Objectives/QuestChains.lua). GENERATED by',
        '-- tools/questchains/build_chains.py on the build box; regenerate rather than edit.',
        '-- Source: Wowhead WoW Forever quest pages, their "Series" box: ' + (URL % 0).replace('=0', '=<quest>') + ',',
        '-- each read on the box (src: "<page quest>@<fetched>", fetched %s .. %s).' % ((times[0] if times else '-'), (times[-1] if times else '-')),
        '-- A chain: { step, ... , side = "A"/"H", class = "DRUID" (every page read in it agrees), breaks, src }. A step:',
        '-- { questID, "Name", opt = true (Wowhead says breadcrumb), side / class (its own page differs), alt = { step, ... }',
        '-- (the other quests in that Series row) }; breaks = { i }: two Wowhead series joined after step i (where QuestieDB',
        '-- links the last quest of one to the first of the next; QuestieDB itself is not in this file). Joins: %s.' % ('on' if JOIN else 'off (each Wowhead series is its own chain)'),
        '-- Never estimated: a quest in no Series box read here is in no chain (no button); noSeries: the pages read that',
        '-- had none.',
        '',
        'local _, ns = ...',
        '',
        'ns.QuestChainData = {',
        '\tmeta = { source = "Wowhead WoW Forever (Series)", built = %s, pages = %d, chains = %d, quests = %d },' % (lua_str(now), sum(1 for p in ps.values() if p['ok']), len(lines), len(qset)),
    ]
    nos = sorted(q for q, p in ps.items() if p['ok'] and not p['series'])
    head.append('\tnoSeries = { %s },   -- pages read with no Series box: those quests are in no chain (no button)' % ', '.join(map(str, nos)))
    head.append('\tchains = {')
    open(out_lua, 'w').write('\n'.join(head + lines + ['\t},', '}', '']))
    report(ps, qs, ser, paths, qset)
    print('wrote %s: %d chains, %d quests, from %d pages' % (out_lua, len(lines), len(qset), sum(1 for p in ps.values() if p['ok'])))

def report(ps, qs, ser, paths, qset):
    R = os.path.join(DATA, 'report')
    nodes, roots, nxt = candidates(qs) if qs else ([], [], {})
    bad = [q for q, p in ps.items() if not p['ok']]
    noser = [q for q, p in ps.items() if p['ok'] and not p['series']]
    other = [q for q, p in ps.items() if p['ok'] and (p['flavors'] - {'forever'})]
    miss = [q for q in nodes if q not in qset]
    with open(os.path.join(R, 'coverage.txt'), 'w') as f:
        f.write('pages: %d (good %d, not a quest page %d, no Series box %d, links to another flavour %d)\n' % (len(ps), len(ps) - len(bad), len(bad), len(noser), len(other)))
        f.write('series: %d distinct; chains (joined): %d; quests in chains: %d\n' % (len(ser), len(paths), len(qset)))
        f.write('QuestieDB candidates: %d; in a Wowhead chain: %d; not (no Series box, or not read yet): %d\n' % (len(nodes), len(nodes) - len(miss), len(miss)))
        f.write('not a quest page: %s\n' % ' '.join(map(str, bad)))
        f.write('links to another flavour (check): %s\n' % ' '.join(map(str, other)))
        f.write('candidates with no chain: %s\n' % ' '.join(map(str, miss)))
    with open(os.path.join(R, 'disagree.csv'), 'w') as f:
        f.write('kind,quest,detail\n')
        for path in paths:
            ids = [r[0][0] for k in path for r in ser[k]['rows']]
            for a, b in zip(ids, ids[1:]):
                qa = qs.get(a, {})
                if qa and qa.get('nextQuestInChain') and qa['nextQuestInChain'] != b:
                    f.write('order,%d,"Wowhead next %d, QuestieDB next %d"\n' % (a, b, qa['nextQuestInChain']))
            for k in path:
                for r in ser[k]['rows']:
                    for i, _ in r:
                        q = qs.get(i, {})
                        if q.get('breadcrumbForQuestId') and not info(i, ps)[2]:
                            f.write('optional,%d,"QuestieDB: a breadcrumb (for %s); Wowhead page %s: not shipped as optional"\n' % (i, q['breadcrumbForQuestId'], 'read, no' if i in ps else 'not read'))
                    if len(r) > 1:
                        ex = set(qs.get(r[0][0], {}).get('exclusiveTo') or [])
                        for i, _ in r[1:]:
                            if i not in ex: f.write('alternative,%d,"Wowhead: or %d; QuestieDB exclusiveTo %s"\n' % (r[0][0], i, sorted(ex)))
                    elif qs.get(r[0][0], {}).get('exclusiveTo'):
                        f.write('exclusive,%d,"QuestieDB exclusiveTo %s; Wowhead row has one quest"\n' % (r[0][0], qs[r[0][0]]['exclusiveTo']))
    labels = collections.Counter()
    for p in ps.values():
        for x in p['facts']: labels[re.sub(r'\[[^\]]*\]', '', x).split(':')[0].strip()[:40]] += 1
    with open(os.path.join(R, 'quickfacts.txt'), 'w') as f:
        for k, n in labels.most_common(): f.write('%6d  %s\n' % (n, k))

# ---------------------------------------------------------------- the quests in the log now (chain-data/current-log.tsv)
def current_ids():
    p = os.path.join(DATA, 'current-log.tsv')
    return [int(l.split('\t')[0]) for l in open(p, encoding='utf-8') if l[:1].isdigit()] if os.path.exists(p) else []

def chain_of(q, nxt):
    prev = collections.defaultdict(list)
    for a, b in nxt.items(): prev[b].append(a)
    r, seen = q, set()
    while prev.get(r) and r not in seen: seen.add(r); r = min(prev[r])
    c = [r]
    while c[-1] in nxt and nxt[c[-1]] not in c: c.append(nxt[c[-1]])
    return c

def current_chains(qs):
    """log quest -> its QuestieDB chain (start first), for the log quests in one"""
    nodes, _, nxt = candidates(qs)
    ns = set(nodes)
    return {q: chain_of(q, nxt) for q in current_ids() if q in ns}

def current(qs):
    ids = current_ids()
    ch = current_chains(qs)
    seen, urls, lines = set(), [], []
    for q in ids:
        if q not in ch: continue
        key = tuple(ch[q])
        if key in seen: lines.append('%d\tsame chain as an earlier log quest' % q); continue
        seen.add(key); urls.append(q)
        lines.append('%d\tchain start %d, %d quests: %s' % (q, key[0], len(key), ' '.join(map(str, key))))
    linked = set()
    for a in qs.values():
        for x in (a.get('preQuestSingle') or []) + (a.get('preQuestGroup') or []): linked.add(x)
    maybe = [q for q in ids if q not in ch and (q in linked or (qs.get(q) or {}).get('preQuestSingle') or (qs.get(q) or {}).get('preQuestGroup'))]
    open(os.path.join(DATA, 'urls-current.txt'), 'w').write(''.join(URL % q + '\n' for q in urls))
    open(os.path.join(DATA, 'urls-current-maybe.txt'), 'w').write(''.join(URL % q + '\n' for q in maybe))
    open(os.path.join(DATA, 'current-chains.txt'), 'w').write('\n'.join(lines) + '\n')
    print('log quests %d; in a QuestieDB chain %d (%d distinct chains); urls-current.txt: %d; urls-current-maybe.txt: %d (no chain, but pre-quest linked)'
          % (len(ids), len(ch), len(seen), len(urls), len(maybe)))

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'check'
    qs = questie()
    if cmd == 'urls':
        nodes, roots, _ = candidates(qs)
        open(os.path.join(DATA, 'urls.txt'), 'w').write(''.join(URL % q + '\n' for q in roots))
        open(os.path.join(DATA, 'urls-all.txt'), 'w').write(''.join(URL % q + '\n' for q in nodes))
        print('urls.txt: %d (pass 1, one per QuestieDB chain start); urls-all.txt: %d (every candidate)' % (len(roots), len(nodes)))
    elif cmd == 'check':
        ps = pages()
        bad = [q for q, p in ps.items() if not p['ok']]
        noser = [q for q, p in ps.items() if p['ok'] and not p['series']]
        for q in bad:
            if ps[q].get('manual'): print('manual/%s: %s' % (ps[q].get('file'), ps[q]['why']))
        print('pages %d: good %d, not a quest page %d %s, no Series box %d' % (len(ps), len(ps) - len(bad), len(bad), bad[:20], len(noser)))
        for q in sorted(ps)[:3] if '-v' in sys.argv else []:
            p = ps[q]; print(q, p['name'], p['side'], p['classes'], [[i for i, _ in r] for r in (p['series'][0] if p['series'] else [])], p['when_from'])
    elif cmd == 'current':
        current(qs)
    elif cmd == 'next':
        nodes, _, _ = candidates(qs)
        if '--current' in sys.argv: nodes = sorted({q for c in current_chains(qs).values() for q in c})
        ps = pages()
        seen = {q for q, p in ps.items() if p['ok']}
        seen |= read_pages()   # (pages read in the batches: a series, none, or the same series as another page)
        for p in ps.values():
            for rows in p['series']:
                for r in rows:
                    for i, _ in r: seen.add(i)
        need = [q for q in nodes if q not in seen]
        open(os.path.join(DATA, 'urls-next.txt'), 'w').write(''.join(URL % q + '\n' for q in need))
        print('urls-next.txt: %d still needed (candidates in no Series box read so far, and not read themselves)' % len(need))
    elif cmd == 'build':
        args = [a for a in sys.argv[2:] if not a.startswith('--')]
        build(args[0] if args else OUT_LUA)
    else:
        print(__doc__ or 'urls | check | next | build [out.lua]')

if __name__ == '__main__':
    main()
