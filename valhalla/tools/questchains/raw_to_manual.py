#!/usr/bin/env python3
# Valhalla 1.1.0: Wowhead WoW Forever Series boxes read in the box browser (chain-data/batches/*-raw.txt) ->
# manual-format series files (chain-data/manual-wowhead/quest-<page>.tsv) that build_chains.py reads, plus
# chain-data/manual-wowhead/pages-read.tsv (every page and what it showed) and chain-data/report/raw-conflicts.txt.
# Box only.
#
# Raw line:  <page id> | <HH:MM CT> | <side>[, [class ]<Class>[/<Class>]] | 1 <id> <name>; 2 <id> <name>; ...
#   the same number twice: alternatives (the first is the main quest; "(alt)" after a name is dropped);
#   "1 66; 2 67 (all <name>)" / "(both <name>)" / "(2-6 <name>)": every quest without a name (at those positions) has it;
#   two Series boxes on a page: " || " between them.
#   Other 4th columns: "no series", "(same series as <page>)". Two-column lines: "<id> | load failed" / "not found" / "?".
#   side: A, H, B / both (both factions), None.
# Each file's "# ... read <Mon> <d>[-<d>] <yyyy> [~]HH:MM-HH:MM CT" header gives the date (a range over midnight:
# 12:00 and later the first day); "~" (batch 8): the line times are not per page, the fetch time is the range.
# Files are read in order (batch1 .. batch10, then retry1, retry2, ...); a later reading of a page that failed
# replaces the failure; a retry pass's reading of a page read before replaces that reading (a careful re-read). Series are compared by their quest ids: one seen again on another page is the same series;
# one sharing a quest with a series already kept but different (order, members, alternatives) is a CONFLICT: the
# first reading is kept (the hand-typed manual/ files are first, then the batches in order) and the others are
# listed, never merged or guessed. A reading without the page's own quest in it is incomplete: covered when a full
# reading of the same series was kept, else held back (not shipped) and listed to be read again.
import collections, datetime, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_chains as B

DATA = B.DATA
BATCHES = os.path.join(DATA, 'batches')
OUT = os.path.join(DATA, 'manual-wowhead')
URL = B.URL
MON = {m: i for i, m in enumerate(['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], 1)}
TZ = '-06:00'

def order_key(fn):
    m = re.match(r'(batch|retry)(\d+)([a-z]?)-raw\.txt$', fn)
    return (0 if m.group(1) == 'batch' else 1, int(m.group(2)), m.group(3))

def raw_files():
    return sorted((f for f in os.listdir(BATCHES) if re.match(r'(batch|retry)\d+[a-z]?-raw\.txt$', f)), key=order_key)

HEAD = re.compile(r'(?:read )?(\w{3}) (\d+)(?:-(\d+))? (\d{4}) (~?)(\d\d):(\d\d)-(\d\d):(\d\d) CT')
def header_clock(text, fn):
    m = HEAD.search(text)
    if not m: raise SystemExit('%s: no "read <Mon> <d> <yyyy> HH:MM-HH:MM CT" header' % fn)
    mon, d1, d2, yr, approx = MON[m.group(1)], int(m.group(2)), m.group(3), int(m.group(4)), m.group(5) == '~'
    def at(hh, mm):
        day = d1 if not d2 or hh >= 12 else int(d2)
        return '%04d-%02d-%02dT%02d:%02d:00%s' % (yr, mon, day, hh, mm, TZ)
    rng = None
    if approx:
        rng = '~%s/%s' % (at(int(m.group(6)), int(m.group(7))), at(int(m.group(8)), int(m.group(9))))
    return at, rng

CLASS = {c.lower(): c for c in ['WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID']}
def side_class(col):
    parts = [p.strip() for p in re.split(r',\s*|\s+(?=[A-Z][a-z])', col.strip(), maxsplit=1)]
    s = parts[0].lower()
    side = 'A' if s == 'a' else 'H' if s == 'h' else None   # (B, both, None: no faction of its own)
    if s not in ('a', 'h', 'b', 'both', 'none'): raise ValueError('side %r' % col)
    cls = None
    if len(parts) > 1 and parts[1]:
        names = re.sub(r'^class\s+', '', parts[1], flags=re.I)
        cls = [CLASS[x.strip().lower()] for x in names.split('/')]
    return side, cls

ITEM = re.compile(r'^(\d+)\s+(\d+)(?:\s+(.*?))?$')
def series_of(text):
    """one Series box's text -> rows [[(id, name), ...], ...] or raises ValueError"""
    items = [x.strip() for x in text.split(';') if x.strip()]
    shared, lo, hi = None, 1, 10 ** 6
    m = re.search(r'\s*\((all|both|\d+-\d+) ([^)]*)\)\s*$', items[-1]) if items else None
    if m:
        shared, items[-1] = m.group(2).strip(), items[-1][:m.start()].strip()
        if '-' in m.group(1): lo, hi = (int(x) for x in m.group(1).split('-'))
    rows, last = [], None
    for it in items:
        m = ITEM.match(it)
        if not m: raise ValueError('item %r' % it)
        pos, qid, name = int(m.group(1)), int(m.group(2)), (m.group(3) or '').strip()
        name = re.sub(r'\s*\(alt\)$', '', name).strip() or (shared if lo <= pos <= hi else None)
        if not name: raise ValueError('no name for %d' % qid)
        if pos == last: rows[-1].append((qid, name))
        elif pos == len(rows) + 1: rows.append([(qid, name)]); last = pos
        else: raise ValueError('position %d after %s' % (pos, last))
    if not rows: raise ValueError('empty series')
    return rows

def ids_of(rows): return tuple(tuple(i for i, _ in r) for r in rows)
def key_of(rows): return tuple(tuple(sorted(i for i, _ in r)) for r in rows)   # (the order of a row's alternatives: not meaningful)
def members(rows): return {i for r in rows for i, _ in r}

def read_raw():
    """pages: id -> {'status', 'side', 'classes', 'fetched', 'src', 'boxes': [rows], 'same': page} (the reading that
    counts), readings: [(page, box n, rows, fetched, src)] in reading order, problems: [str]"""
    pages, readings, problems, extra = {}, [], [], []
    global replaced
    replaced = []
    for fn in raw_files():
        text = open(os.path.join(BATCHES, fn), encoding='utf-8').read()
        at, rng = header_clock(text, fn)
        for n, line in enumerate(text.splitlines(), 1):
            if not line.strip() or line.startswith('#'): continue
            f = [x.strip() for x in line.split(' | ')]
            src = '%s:%d' % (fn, n)
            if not f[0].isdigit(): problems.append('%s: no page id: %r' % (src, line[:80])); continue
            pid = int(f[0])
            if len(f) == 2:
                st = f[1].lower()
                if st not in ('load failed', 'not found', '?'): problems.append('%s: %r' % (src, line[:80]))
                if pid not in pages or pages[pid]['status'] in ('load failed', 'not found', '?'):
                    pages[pid] = {'status': st, 'src': src}
                continue
            if len(f) != 4: problems.append('%s: %d columns' % (src, len(f))); continue
            hh, mm = (int(x) for x in f[1].split(':'))
            fetched = rng or at(hh, mm)
            try:
                side, cls = side_class(f[2])
            except (ValueError, KeyError) as e:
                problems.append('%s: side/class %r (%s)' % (src, f[2], e)); continue
            rec = {'status': None, 'side': side, 'classes': cls, 'fetched': fetched, 'src': src, 'boxes': [], 'same': None}
            body = f[3]
            m = re.match(r'^\(same series as (\d+)\)$', body)
            if body.lower() == 'no series': rec['status'] = 'no series'
            elif m: rec['status'], rec['same'] = 'same series', int(m.group(1))
            else:
                try:
                    rec['boxes'] = [series_of(b) for b in body.split(' || ')]
                    rec['status'] = 'series'
                except ValueError as e:
                    problems.append('%s: page %d: %s' % (src, pid, e)); continue
            old = pages.get(pid)
            retry = fn.startswith('retry')
            if old and old['status'] not in ('load failed', 'not found', '?') and retry:
                # a retry pass re-reads a page carefully: its reading replaces the earlier one (listed)
                readings[:] = [r for r in readings if r[0] != pid]
                replaced.append('page %d: %s (%s) replaced by the re-read %s (%s)' % (pid, old['status'], old['src'], rec['status'], src))
                pages[pid] = rec
            elif old and old['status'] not in ('load failed', 'not found', '?'):
                extra.append((pid, rec))      # (read twice in the batches: compared below, the first kept)
            else:
                pages[pid] = rec
            for k, rows in enumerate(rec['boxes'], 1):
                readings.append((pid, k, rows, fetched, src))
    return pages, readings, problems, extra

def hand_readings():
    """the hand-typed manual/ files (read 2026-11-11 20:02-20:05 CT): readings first"""
    out, info = [], {}
    d = os.path.join(DATA, 'manual')
    if not os.path.isdir(d): return out, info
    for fn in sorted(os.listdir(d)):
        m = re.match(r'quest-(\d+)(?:-(\d+))?\.tsv$', fn)
        if not m: continue
        p = B.parse_manual(os.path.join(d, fn), int(m.group(1)))
        info[int(m.group(1))] = p
        for rows in p['series']:
            out.append((int(m.group(1)), int(m.group(2) or 1), rows, p['fetched'], 'manual/' + fn))
    B.FLAGS.clear()
    return out, info

def describe(a, b):
    ia, ib = ids_of(a), ids_of(b)
    fa, fb = [i for r in ia for i in r], [i for r in ib for i in r]
    if set(fa) == set(fb):
        return 'same quests, different order or alternatives'
    sa, sb = set(fa), set(fb)
    if sb < sa: return 'a shorter run (%d of %d quests)' % (len(sb), len(sa))
    if sa < sb: return 'longer (%d quests; kept has %d): extra %s' % (len(sb), len(sa), ' '.join(map(str, sorted(sb - sa))))
    return 'different members (shared %s; only here %s)' % (' '.join(map(str, sorted(sa & sb))), ' '.join(map(str, sorted(sb - sa))))

def fmt_named(rows): return '; '.join('%d %s' % (n, ' / '.join('%d %s' % (i, nm) for i, nm in r)) for n, r in enumerate(rows, 1))
def fmt(rows): return '; '.join('%d %s' % (n, ' / '.join('%d' % i for i, _ in r)) for n, r in enumerate(rows, 1))

def main():
    pages, readings, problems, extra = read_raw()
    hand, hand_info = hand_readings()
    kept = []            # [{'rows', 'page', 'box', 'fetched', 'src', 'pages': [..], 'hand': bool}]
    by_id = {}           # quest id -> kept index
    conflicts, names, incomplete, held = [], [], [], []
    # a FULL reading has the page's own quest in it; one without it (the reader missed the page's own quest, e.g.
    # an alternative in bold) is INCOMPLETE: the full readings first (in reading order), then the incomplete ones:
    # the same quests in the same order as a series kept (less the page's quest): covered; no series kept shares
    # a quest: kept as read (flagged); else a conflict
    allr = hand + readings
    full = [r for r in allr if r[0] in members(r[2])]
    part = [r for r in allr if r[0] not in members(r[2])]
    def sub_of(K, rows):
        a = [tuple(sorted(i for i in r if i in members(rows))) for r in ids_of(K['rows'])]
        return tuple(r for r in a if r) == key_of(rows)
    for (pid, k, rows, fetched, src) in full + part:
        mem = members(rows)
        hit = sorted({by_id[i] for i in mem if i in by_id})
        if pid not in mem:
            if len(hit) == 1 and sub_of(kept[hit[0]], rows):
                K = kept[hit[0]]
                incomplete.append('page %d (%s): its own quest is missing from its reading; the rest is the series kept from page %d (%s): covered' % (pid, src, K['page'], K['src']))
                if pid not in K['pages']: K['pages'].append(pid)
                continue
            # no full reading of it: held back, not shipped (the reader may have put another id on the page's own
            # quest, e.g. page 615 read as "1 8553 The Captain's Cutlass"): the page needs reading again
            held.append('page %d (%s, %s): %s%s' % (pid, src, fetched, fmt_named(rows),
                ('  [overlaps the series kept from page %s]' % ', '.join(str(kept[h]['page']) for h in hit)) if hit else ''))
            continue
        if not hit:
            kept.append({'rows': rows, 'page': pid, 'box': k, 'fetched': fetched, 'src': src, 'pages': [pid], 'hand': src.startswith('manual/')})
            for i in mem: by_id[i] = len(kept) - 1
            continue
        if len(hit) == 1 and key_of(kept[hit[0]]['rows']) == key_of(rows):
            K = kept[hit[0]]
            if pid not in K['pages']: K['pages'].append(pid)
            na = [n for r in K['rows'] for _, n in r]; nb = [n for r in rows for _, n in r]
            if na != nb: names.append('page %d (%s): names differ from page %d (%s): %s' % (pid, src, K['page'], K['src'],
                '; '.join('%r vs %r' % (x, y) for x, y in zip(na, nb) if x != y)))
            continue
        for h in hit:
            K = kept[h]
            conflicts.append('page %d (%s, %s)\n    kept:  page %d (%s): %s\n    other: %s\n    -> %s' % (
                pid, src, fetched, K['page'], K['src'], fmt(K['rows']), fmt(rows), describe(K['rows'], rows)))
    # a page read twice (a retry of a page read before): compare
    for pid, rec in extra:
        first = pages[pid]
        if first['status'] != rec['status'] or [key_of(r) for r in first['boxes']] != [key_of(r) for r in rec['boxes']] or first.get('same') != rec.get('same'):
            conflicts.append('page %d read twice: %s (%s) vs %s (%s); the first kept' % (pid, first['status'], first['src'], rec['status'], rec['src']))
    # page facts (side / class) for every quest whose page was read
    info = {pid: (p.get('side'), p.get('classes')) for pid, p in pages.items() if p['status'] in ('series', 'no series', 'same series')}
    side_notes = []
    for pid, p in hand_info.items():
        if pid in info and info[pid][0] != p['side']:
            side_notes.append('page %d: hand file side %s, batch side %s (%s)' % (pid, p['side'], info[pid][0] or 'both/none', pages[pid]['src']))
    # pages that say "no series" but whose quest is in a series read on another page; "same series as" checks
    notes = []
    for pid, p in sorted(pages.items()):
        if p['status'] == 'no series' and pid in by_id:
            K = kept[by_id[pid]]
            notes.append('page %d (%s): no series, but quest %d is in the series read on page %d (%s)' % (pid, p['src'], pid, K['page'], K['src']))
        if p['status'] == 'same series':
            x = pages.get(p['same'])
            if not x or x['status'] != 'series':
                notes.append('page %d (%s): same series as %d, which has no series read (%s)' % (pid, p['src'], p['same'], x['status'] if x else 'not read'))
            elif pid not in by_id:
                notes.append('page %d (%s): same series as %d, but quest %d is not in it' % (pid, p['src'], p['same'], pid))
    # write: one file per kept series (the hand files are already in manual/), the pages read, the report
    os.makedirs(OUT, exist_ok=True)
    for fn in os.listdir(OUT):
        if re.match(r'quest-\d+(-\d+)?\.tsv$', fn) or fn == 'pages-read.tsv': os.remove(os.path.join(OUT, fn))
    written = 0
    for K in kept:
        if K['hand']: continue
        name = 'quest-%d.tsv' % K['page'] if K['box'] == 1 else 'quest-%d-%d.tsv' % (K['page'], K['box'])
        with open(os.path.join(OUT, name), 'w', encoding='utf-8') as f:
            f.write('# Wowhead WoW Forever Series box on %s, read in the box browser (%s); also on pages %s\n' % (
                URL % K['page'], K['src'], ' '.join(map(str, K['pages'][1:])) or '-'))
            f.write('pos\tid\tname\tflags\turl\tfetched\n')
            first = True
            for n, r in enumerate(K['rows'], 1):
                for j, (i, nm) in enumerate(r):
                    side, cls = info.get(i, (None, None))
                    fl = []
                    if side: fl.append('side=' + side)
                    if cls: fl.append('class=' + '+'.join(cls))
                    f.write('%s\t%d\t%s\t%s\t%s\t%s\n' % (n, i, nm, ','.join(fl), URL % K['page'] if first else '', K['fetched'] if first else ''))
                    first = False
        written += 1
    # pages with no Series box: recorded (no chain, no button); a page whose quest is in a series kept is not
    nos = 0
    for pid, p in sorted(pages.items()):
        if p['status'] == 'no series' and pid not in by_id and not os.path.exists(os.path.join(DATA, 'manual', 'quest-%d.tsv' % pid)):
            with open(os.path.join(OUT, 'quest-%d.tsv' % pid), 'w', encoding='utf-8') as f:
                f.write('# %s: no Series box (%s)\npos\tid\tname\tflags\turl\tfetched\nnone\t\t\t\t%s\t%s\n' % (URL % pid, p['src'], URL % pid, p['fetched']))
            nos += 1
    with open(os.path.join(OUT, 'pages-read.tsv'), 'w', encoding='utf-8') as f:
        f.write('page\tstatus\tside\tclass\tsame_as\tfetched\tsource\n')
        for pid, p in sorted(pages.items()):
            f.write('%d\t%s\t%s\t%s\t%s\t%s\t%s\n' % (pid, p['status'], p.get('side') or '', '+'.join(p.get('classes') or []),
                p.get('same') or '', p.get('fetched') or '', p['src']))
    os.makedirs(os.path.join(DATA, 'report'), exist_ok=True)
    st = collections.Counter(p['status'] for p in pages.values())
    failed = sorted(pid for pid, p in pages.items() if p['status'] in ('load failed', 'not found', '?'))
    with open(os.path.join(DATA, 'report', 'raw-conflicts.txt'), 'w', encoding='utf-8') as f:
        f.write('raw files: %s\n' % ' '.join(raw_files()))
        f.write('pages: %d (%s)\n' % (len(pages), ', '.join('%s %d' % kv for kv in sorted(st.items()))))
        f.write('series readings: %d (+ %d hand); distinct series kept: %d (%d hand, %d written to manual-wowhead/); no-series files: %d\n' % (
            len(readings), len(hand), len(kept), sum(1 for K in kept if K['hand']), written, nos))
        f.write('\nCONFLICTS (%d): the first reading kept, the other not used\n' % len(conflicts))
        for c in conflicts: f.write(c + '\n')
        f.write('\nINCOMPLETE READINGS (%d): the page\'s own quest missing from its Series reading\n' % len(incomplete))
        for c in incomplete: f.write(c + '\n')
        f.write('\nHELD BACK, NOT SHIPPED (%d): the page\'s own quest is not in its reading and no other page read this series in full; read these pages again\n' % len(held))
        for c in held: f.write(c + '\n')
        f.write('\nRE-READ IN A RETRY PASS, REPLACING THE EARLIER READING (%d)\n' % len(replaced))
        for c in replaced: f.write(c + '\n')
        f.write('\nNOTES (%d)\n' % len(notes))
        for c in notes: f.write(c + '\n')
        f.write('\nHAND FILE SIDE vs BATCH SIDE (%d)\n' % len(side_notes))
        for c in side_notes: f.write(c + '\n')
        f.write('\nSAME QUESTS, NAMES DIFFER (%d)\n' % len(names))
        for c in names: f.write(c + '\n')
        f.write('\nLINE PROBLEMS (%d)\n' % len(problems))
        for c in problems: f.write(c + '\n')
        f.write('\nSTILL NOT READ (load failed / not found / ?) (%d): %s\n' % (len(failed), ' '.join(map(str, failed))))
    print('pages %d (%s); series readings %d + %d hand -> %d kept (%d written); no-series files %d; conflicts %d; incomplete covered %d; held back %d; replaced by re-reads %d; notes %d; side notes %d; name diffs %d; line problems %d; still not read %d'
          % (len(pages), ', '.join('%s %d' % kv for kv in sorted(st.items())), len(readings), len(hand), len(kept), written, nos,
             len(conflicts), len(incomplete), len(held), len(replaced), len(notes), len(side_notes), len(names), len(problems), len(failed)))

if __name__ == '__main__':
    main()
