# Valhalla 1.2.1: merge a browser reading of Wowhead Forever (recipe-urls.txt's pages) into skills.json, then rebuild
# Valhalla/Data/Forever/TopSkills.lua with build_topskills.py.
# Raw file: a header "# read <time or range, e.g. 2026-11-12T13:05-06:00/2026-11-12T13:40-06:00>", then one line a page:
#   craftedItemId | skill | source [| HH:MM]
#   source: "recipe=<recipe item id>" (the recipe item's "Requires <Profession> (N)") or "created-by" (the crafted
#   item's Created by tab, the recipe's skill). HH:MM: that line's read time (else the header's).
# Only whole numbers 1-450 are taken; anything else ("?", "none", "120-130", blank) is skipped and reported. A value
# only fills an item that is unknown (never replaces a known one: a different value is reported as a conflict). The
# same item read twice with different values: the first kept, the other reported. Never estimated.
# (1.2.4) A line may end in "# note" (e.g. "# timeout", "# noexist"). A "?" line never blocks a later file's value for
# the same item (a retry fills it). "# multiple: a,b" (several recipes make the item, from more than one profession or
# rank): which one is this profession's can't be told from the line, so it is skipped and reported (read it from the
# recipe item instead: recipe=<id>).
# Usage: merge_raw.py <raw.txt>... [--skills skills.json] [--out skills-merged.json] [--lua TopSkills.lua]
import json, re, sys, os, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
LINE = re.compile(r'^\s*(\d+)\s*\|\s*([^|#]*?)\s*\|\s*(recipe=\d+|created-by)\s*(?:\|\s*(\d{1,2}:\d{2}))?\s*(?:#\s*(.*?))?\s*$')
HEAD = re.compile(r'^#\s*read\s+(\S+)')
CRAFT = [171, 164, 333, 202, 165, 197, 185, 129]

def parse(path):
    read, rows, bad = None, [], []
    for n, raw in enumerate(open(path, encoding='utf-8'), 1):
        s = raw.rstrip('\n')
        if not s.strip(): continue
        h = HEAD.match(s)
        if h: read = h.group(1); continue
        if s.lstrip().startswith('#'): continue
        m = LINE.match(s)
        if not m: bad.append((path, n, s, 'not a raw line')); continue
        iid, skill, src, hhmm, note = m.groups()
        if not re.fullmatch(r'\d+', skill) or not (1 <= int(skill) <= 450):
            bad.append((path, n, s, 'skill not a whole number 1-450')); continue
        if note and note.lower().startswith('multiple'):
            bad.append((path, n, s, 'several recipes make it: not told which is this profession\'s')); continue
        rows.append({'item': iid, 'skill': int(skill), 'src': src, 'time': hhmm, 'read': read, 'line': n, 'file': path})
    return rows, bad

def url_of(r):
    if r['src'].startswith('recipe='): return 'https://www.wowhead.com/forever/item=' + r['src'][7:]
    return 'https://www.wowhead.com/forever/item=%s#created-by' % r['item']

def date_of(r):
    if r['time'] and r['read']:
        return '%sT%s (read %s)' % (r['read'][:10], r['time'], r['read'])
    return r['read'] or 'unknown'

def merge(d, rows):
    report = {'added': [], 'conflicts': [], 'dupes': [], 'notunknown': [], 'noitem': []}
    seen = {}
    for r in rows:
        if r['item'] in seen:
            if seen[r['item']]['skill'] != r['skill']: report['dupes'].append((seen[r['item']], r))
            continue
        seen[r['item']] = r
        hit = False
        for p in CRAFT:
            items = d['professions'][str(p)]['items']
            e = items.get(r['item'])
            if e is None: continue
            hit = True
            if e.get('skill') is None:
                e['skill'] = r['skill']
                e.setdefault('sources', []).append({'url': url_of(r), 'date': date_of(r),
                    'how': 'recipe item page "Requires (N)"' if r['src'].startswith('recipe=') else 'crafted item page, Created by tab (skill)'})
                report['added'].append((p, r))
            elif e['skill'] != r['skill']:
                report['conflicts'].append((p, e['skill'], r))
            else:
                report['notunknown'].append((p, r))
        if not hit: report['noitem'].append(r)
    for c in d['coverage']:
        if str(c['skill_line']) in d['professions'] and c['skill_line'] in CRAFT:
            items = d['professions'][str(c['skill_line'])]['items']
            c['known'] = sum(1 for e in items.values() if e.get('skill') is not None)
            c['unknown'] = sum(1 for e in items.values() if e.get('skill') is None)
    return report

def main(argv):
    files, opts, i = [], {'--skills': '/workspace/valhalla/top10-skill-data/skills.json',
        '--out': '/workspace/valhalla/topskill-data/skills-merged.json',
        '--lua': os.path.join(HERE, '../../Valhalla/Data/Forever/TopSkills.lua')}, 0
    while i < len(argv):
        if argv[i] in opts: opts[argv[i]] = argv[i + 1]; i += 2
        else: files.append(argv[i]); i += 1
    d = json.load(open(opts['--skills']))
    rows, bad = [], []
    for f in files:
        r, b = parse(f); rows += r; bad += b
    rep = merge(d, rows)
    if rep['added']:
        d.setdefault('extra_reads', []).append({'files': [os.path.basename(f) for f in files], 'values': len(rep['added']),
            'read': sorted({r['read'] for _, r in rep['added'] if r['read']})})
    os.makedirs(os.path.dirname(os.path.abspath(opts['--out'])), exist_ok=True)
    json.dump(d, open(opts['--out'], 'w'), indent=1)
    subprocess.check_call([sys.executable, os.path.join(HERE, 'build_topskills.py'), opts['--out'], opts['--lua']], stdout=subprocess.DEVNULL)
    print('added %d values; skipped %d unreadable lines; %d conflicts with a known value; %d read twice differently; %d not a craft item'
          % (len(rep['added']), len(bad), len(rep['conflicts']), len(rep['dupes']), len(rep['noitem'])))
    for f, n, s, why in bad: print('  skipped %s:%d %s (%s)' % (os.path.basename(f), n, s, why))
    for p, old, r in rep['conflicts']: print('  conflict %s (skill line %d): known %d, read %d (%s:%d)' % (r['item'], p, old, r['skill'], os.path.basename(r['file']), r['line']))
    for a, b in rep['dupes']: print('  read twice %s: %d kept, %d (%s:%d) not' % (a['item'], a['skill'], b['skill'], os.path.basename(b['file']), b['line']))
    for r in rep['noitem']: print('  not a craft item in the data: %s' % r['item'])
    return rep, bad

if __name__ == '__main__':
    main(sys.argv[1:])
