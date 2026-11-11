# Build top10-skill-data/skills.json and coverage from what was read from Wowhead Forever. Never estimates:
# an item with no value read stays unknown.
import json, re, glob, os
from collections import defaultdict
U = json.load(open('universe.json'))
G = json.load(open('guide_rows.json'))
OUT = '/workspace/valhalla/top10-skill-data/'
NAMES = {171: 'Alchemy', 164: 'Blacksmithing', 333: 'Enchanting', 202: 'Engineering', 165: 'Leatherworking', 197: 'Tailoring',
         185: 'Cooking', 129: 'First Aid', 182: 'Herbalism', 186: 'Mining', 393: 'Skinning', 356: 'Fishing'}
CRAFT = [171, 164, 333, 202, 165, 197, 185, 129]
HARVEST = [182, 186, 393, 356]
CRAFT_GUIDES = ('alchemy', 'blacksmithing', 'cooking', 'enchanting', 'engineering', 'first-aid', 'leatherworking', 'tailoring')
made = {int(k): [tuple(x) for x in v] for k, v in U['made'].items()}           # item -> [(prof, spell)]
spell_prof = {}
for it, lst in made.items():
    for p, s in lst: spell_prof.setdefault(s, set()).add(p)
# 1. recipe spell -> required skill
spell_skill = defaultdict(list)    # spell -> [(skill, source)]
for r in G['rows']:
    if r['kind'] != 'table' or not any(g in r['guide'] for g in CRAFT_GUIDES): continue
    for s in r['spells']:
        spell_skill[s].append((r['skill'], {'url': r['guide'], 'date': G['fetched'], 'how': 'guide table skill level'}))
tt = 0
for f in glob.glob(OUT + 'raw/tooltips/item-*.json'):
    d = json.load(open(f)); t = d['data'].get('tooltip', '')
    m = re.search(r'Requires <a href="/forever/skill=(\d+)[^"]*"[^>]*>[^<]*</a>\s*\((\d+)\)', t)
    if not m: continue
    prof, rank = int(m.group(1)), int(m.group(2))
    taught = [int(x) for x in re.findall(r'/forever/spell=(\d+)', t)]
    sp = next((s for s in taught if prof in spell_prof.get(s, ())), None)
    if sp is None: continue
    tt += 1
    spell_skill[sp].append((rank, {'url': d['url'], 'date': d['fetched'], 'how': 'recipe item tooltip "Requires %s (%d)"' % (NAMES.get(prof, prof), rank)}))
conflicts = []
spell_final = {}
for s, vals in spell_skill.items():
    ranks = sorted(set(v for v, _ in vals))
    tip = [v for v, src in vals if 'tooltip' in src['how']]
    spell_final[s] = (tip[0] if tip else ranks[0], [src for _, src in vals])
    if len(ranks) > 1: conflicts.append({'spell': s, 'values': ranks, 'chosen': spell_final[s][0]})
# 2. items per crafting profession: the lowest known recipe skill
data = {}
for p in CRAFT:
    items = {}
    for it, lst in made.items():
        rec = [s for q, s in lst if q == p]
        if not rec: continue
        known = [(spell_final[s][0], s) for s in rec if s in spell_final]
        if known:
            v, s = min(known)
            items[it] = {'skill': v, 'spell': s, 'sources': spell_final[s][1]}
        else:
            items[it] = {'skill': None, 'spells': rec}
    data[p] = items
# 3. gathering: node rows (lowest node skill listing the item); membership = the bundled gather list
node_skill = defaultdict(list)
for r in G['rows']:
    if r['kind'] != 'node': continue
    p = 182 if 'herbalism' in r['guide'] else 186 if 'mining' in r['guide'] else None
    if not p: continue
    for it in r['items']:
        node_skill[(p, it)].append((r['skill'], {'url': r['guide'], 'date': G['fetched'], 'how': 'guide node table: object %s, orange %d' % (','.join(map(str, r['nodes'])), r['skill'])}))
for p in HARVEST:
    items = {}
    for it in U['gather'].get(str(p), []):
        v = node_skill.get((p, it))
        if v:
            items[it] = {'skill': min(x for x, _ in v), 'sources': [s for _, s in v]}
        else:
            items[it] = {'skill': None}
    data[p] = items
# 4. write
cov = []
for p in CRAFT + HARVEST:
    k = sum(1 for e in data[p].values() if e['skill'] is not None); n = len(data[p])
    b = defaultdict(int)
    for e in data[p].values():
        v = e['skill']
        if v is None: continue
        b['1-150' if v <= 150 else '151-225' if v <= 225 else '226-300' if v <= 300 else '301-375+'] += 1
    cov.append({'profession': NAMES[p], 'skill_line': p, 'kind': 'craft' if p in CRAFT else 'harvest', 'items': n, 'known': k, 'unknown': n - k, 'brackets': dict(b)})
json.dump({'note': 'Required skill per item, from Wowhead Forever only (URLs and fetch times per value). skill null = unknown (not read; never estimated).',
           'professions': {str(p): {'name': NAMES[p], 'items': {str(i): e for i, e in data[p].items()}} for p in data},
           'conflicts': conflicts, 'coverage': cov, 'recipe_tooltips_used': tt}, open(OUT + 'skills.json', 'w'), indent=1)
with open(OUT + 'coverage.csv', 'w') as f:
    f.write('profession,kind,items,known,unknown,1-150,151-225,226-300,301-375+\n')
    for c in cov: f.write('%s,%s,%d,%d,%d,%d,%d,%d,%d\n' % (c['profession'], c['kind'], c['items'], c['known'], c['unknown'], *[c['brackets'].get(x, 0) for x in ('1-150', '151-225', '226-300', '301-375+')]))
# a Lua table for the preview driver
with open(OUT + 'skills_preview.lua', 'w') as f:
    f.write('return {\n')
    for p in data:
        f.write(' [%d] = {' % p + ','.join('[%s]=%s' % (i, e['skill'] if e['skill'] is not None else 'false') for i, e in data[p].items()) + '},\n')
    f.write('}\n')
for c in cov: print(c)
print('conflicts', len(conflicts), 'tooltips used', tt)
