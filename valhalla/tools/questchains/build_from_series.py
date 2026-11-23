#!/usr/bin/env python3
# Valhalla 1.2.37: Data/Forever/QuestChains.lua from the Wowhead Forever series.json
# (tools/chain-data/forever-1233/). No QuestieDB and no other chain source.
# Each Wowhead Series box is its own chain. A one-step box is not a chain.
# A series that is only a stretch of a longer series is dropped.
# A quest that still sits in two series stays in the longer one.
#
#   build_from_series.py [out.lua]
import json, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
PACK = os.path.join(HERE, '..', 'chain-data', 'forever-1233')
OUT = os.path.join(REPO, 'Valhalla', 'Data', 'Forever', 'QuestChains.lua')
FACTIONS = ('A', 'H')
CLASSES = ('WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID')

def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'

def load():
    series = json.load(open(os.path.join(PACK, 'series.json'), encoding='utf-8'))
    nos = []
    for line in open(os.path.join(PACK, 'results.tsv'), encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        if len(f) >= 5 and f[0].isdigit() and f[4] == 'no series':
            nos.append(int(f[0]))
    forever = [int(x) for x in open(os.path.join(PACK, 'forever-ids.txt'), encoding='utf-8') if x.strip().isdigit()]
    return series, nos, forever

def flat_ids(steps):
    return [it['id'] for row in steps for it in row]

def is_subslice(short, long):
    n, m = len(short), len(long)
    if n >= m or n == 0: return False
    for i in range(m - n + 1):
        if long[i:i + n] == short: return True
    return False

def chain_side_class(steps):
    """The chain's side / class when every step that shows one agrees. Steps that don't show one inherit it."""
    sides = {it.get('side') for row in steps for it in row if it.get('side')}
    classes = {tuple(it.get('classes') or []) for row in steps for it in row if it.get('classes')}
    side = sides.pop() if len(sides) == 1 else None
    cls = list(classes.pop()) if len(classes) == 1 else None
    return side, cls

def fits(item, chain_side, chain_class, side, cls):
    sd = item.get('side') or chain_side
    cl = item.get('classes') or chain_class
    if sd and sd != side: return False
    if cl:
        return cls in cl
    return True

def kept_steps(steps, chain_side, chain_class, side, cls):
    n = 0
    for row in steps:
        if any(fits(it, chain_side, chain_class, side, cls) for it in row):
            n += 1
    return n

def some_character(steps):
    side, cls = chain_side_class(steps)
    for fac in FACTIONS:
        for c in CLASSES:
            if kept_steps(steps, side, cls, fac, c) >= 2:
                return True
    return False

def drop_claimed(steps, claimed):
    out = []
    for row in steps:
        left = [it for it in row if it['id'] not in claimed]
        if left: out.append(left)
    return out

def prepare(series_doc):
    chains = []
    for rec in series_doc['series']:
        steps = [list(row) for row in rec['steps'] if row]
        if len(steps) < 2: continue
        chains.append({'steps': steps, 'read_on': list(rec.get('read_on') or []), 'flat': flat_ids(steps)})
    longer = []
    for a in chains:
        if any(is_subslice(a['flat'], b['flat']) for b in chains): continue
        longer.append(a)
    # identical series: keep one
    seen, uniq = set(), []
    for c in longer:
        key = tuple(c['flat'])
        if key in seen: continue
        seen.add(key)
        uniq.append(c)
    # a quest in two series: the longer series keeps it
    uniq.sort(key=lambda c: (-len(c['steps']), -len(c['flat']), c['flat'][0] if c['flat'] else 0))
    claimed = set()
    kept = []
    for c in uniq:
        steps = drop_claimed(c['steps'], claimed)
        if len(steps) < 2: continue
        if not some_character(steps): continue
        for it in (it for row in steps for it in row):
            claimed.add(it['id'])
        c = dict(c)
        c['steps'] = steps
        c['flat'] = flat_ids(steps)
        kept.append(c)
    kept.sort(key=lambda c: (c['steps'][0][0]['id'], tuple(c['flat'])))
    return kept

def step_lua(item, chain_side, chain_class):
    parts = ['%d' % item['id'], lua_str(item.get('name') or '')]
    if item.get('breadcrumb'): parts.append('opt = true')
    if item.get('side') and item['side'] != chain_side:
        parts.append('side = "%s"' % item['side'])
    cl = item.get('classes') or None
    if cl and cl != chain_class:
        if len(cl) == 1: parts.append('class = %s' % lua_str(cl[0]))
        else: parts.append('class = { ' + ', '.join(lua_str(c) for c in cl) + ' }')
    return parts

def chain_lua(c, when):
    steps = c['steps']
    side, cls = chain_side_class(steps)
    body = []
    for row in steps:
        main, alts = row[0], row[1:]
        parts = step_lua(main, side, cls)
        if alts:
            al = ['{ ' + ', '.join(step_lua(a, side, cls)) + ' }' for a in alts]
            parts.append('alt = { ' + ', '.join(al) + ' }')
        body.append('{ ' + ', '.join(parts) + ' }')
    tail = []
    if side: tail.append('side = "%s"' % side)
    if cls:
        if len(cls) == 1: tail.append('class = %s' % lua_str(cls[0]))
        else: tail.append('class = { ' + ', '.join(lua_str(x) for x in cls) + ' }')
    page = c['read_on'][0] if c['read_on'] else steps[0][0]['id']
    tail.append('src = { %s }' % lua_str('%d@%s' % (page, when)))
    return '\t\t{ ' + ', '.join(body) + ', ' + ', '.join(tail) + ' },'

def main(out_path):
    doc, nos, forever = load()
    chains = prepare(doc)
    when = doc.get('generated') or datetime.datetime.now().astimezone().isoformat(timespec='seconds')
    in_chain = {i for c in chains for i in c['flat']}
    nos = sorted(q for q in set(nos) if q not in in_chain)
    qset = set(in_chain)
    lines = [chain_lua(c, when) for c in chains]
    head = [
        '-- Valhalla: the quest log\'s Chain quest view (Objectives/QuestChains.lua). GENERATED by',
        '-- tools/questchains/build_from_series.py; regenerate rather than edit.',
        '-- Source: Wowhead WoW Forever quest pages, their "Series" box: https://www.wowhead.com/forever/quest=<quest>,',
        '-- from tools/chain-data/forever-1233/series.json (built %s). No QuestieDB.' % when,
        '-- A chain: { step, ... , side = "A"/"H", class = "DRUID" (every step that shows one agrees), src }. A step:',
        '-- { questID, "Name", opt = true (Wowhead says breadcrumb), side / class (this step differs), alt = { step, ... }',
        '-- (the other quests in that Series row) }. Joins: off (each Wowhead series is its own chain).',
        '-- Never estimated: a quest in no Series box read here is in no chain (no button); noSeries: the pages read that',
        '-- had none. forever: every quest id Wowhead\'s WoW Forever list returned (coverage: "unread" is not in this list).',
        '',
        'local _, ns = ...',
        '',
        'ns.QuestChainData = {',
        '\tmeta = { source = "Wowhead WoW Forever (Series)", built = %s, pages = %d, chains = %d, quests = %d },' % (lua_str(when), doc.get('pages_parsed') or 0, len(lines), len(qset)),
        '\tnoSeries = { %s },   -- pages read with no Series box: those quests are in no chain (no button)' % ', '.join(map(str, nos)),
        '\tforever = { %s },   -- Wowhead WoW Forever\'s quest list (an id not here was not on that list)' % ', '.join(map(str, forever)),
        '\tchains = {',
    ]
    open(out_path, 'w', encoding='utf-8').write('\n'.join(head + lines + ['\t},', '}', '']))
    print('wrote %s: %d chains, %d quests, %d noSeries, %d forever ids' % (out_path, len(lines), len(qset), len(nos), len(forever)))

if __name__ == '__main__':
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else OUT)
