# Valhalla v0.4.2.3: writes Valhalla/Data/Forever/TopSkills.lua (Top 10's level filter) from the Wowhead Forever read
# in top10-skill-data/skills.json (fetch: work/fetch_recipes.py, parse_guides.py, build_skills.py on the box).
# Never estimates: a value not read from Wowhead stays unknown (false in the add-on).
import json, sys, os
SRC = sys.argv[1] if len(sys.argv) > 1 else '/workspace/valhalla/top10-skill-data/skills.json'
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '../../Valhalla/Data/Forever/TopSkills.lua')
d = json.load(open(SRC))
CRAFT = [171, 164, 333, 202, 165, 197, 185, 129]
HARVEST = [182, 186, 393, 356]
guides = sorted({s['url'] for p in d['professions'].values() for e in p['items'].values() for s in e.get('sources', []) if '/guide/' in s['url']})
tips = sum(1 for p in d['professions'].values() for e in p['items'].values() for s in e.get('sources', []) if 'tooltip' in s['url'])
L = []
w = L.append
w('-- Valhalla: Top 10\'s level filter. Each item\'s required skill per profession, read from Wowhead Forever on')
w('-- 2026-11-11 (CT). Never estimated: an item with no value read is unknown (hidden from a level bracket, counted).')
w('-- Sources (each value\'s URL and fetch time: top10-skill-data/skills.json on the build box, not shipped):')
w('--   Crafts: the required (orange) skill of the recipe that makes the item, the lowest of its recipes:')
w('--     recipe item tooltips https://nether.wowhead.com/forever/tooltip/item/<recipe item> "Requires <Profession> (N)"')
w('--     (%d values), and the profession guides\' recipe tables (skill level column):' % tips)
for g in guides:
    if not any(x in g for x in ('herbalism', 'mining')): w('--       ' + g)
w('--   Herbalism, Mining: the node\'s orange skill (guide node tables), the lowest node that drops the item:')
for g in guides:
    if any(x in g for x in ('herbalism', 'mining')): w('--       ' + g)
w('--   Skinning (creature level) and Fishing (zone skill): not readable (item pages blocked); all unknown.')
for x in d.get('extra_reads', []):
    w('--   Added (%s): %d craft values from Wowhead Forever item pages (recipe item "Requires (N)", or the crafted' % (', '.join(x['read']) or 'read time not given', x['values']))
    w('--     item\'s Created by tab), https://www.wowhead.com/forever/item=<id> (merge_raw.py; %s).' % ', '.join(x['files']))
w('--   Which recipe makes which item: the client\'s DB2 (as Data/Forever/Recipes.lua). Mining: Harvested only.')
w('-- Format: ns.TopSkills.<craft|harvest>[<skill line>] = { known = "<item>:<skill>,...", unknown = "<item>,..." }')
w('-- Rebuilt by valhalla/tools/topskills/build_topskills.py; regenerate rather than edit.')
w('local _, ns = ...')
w('ns.TopSkills = {')
w('\tsource = "Wowhead Forever, read 2026-11-11 (CT)",')
cov = {c['skill_line']: c for c in d['coverage']}
for kind, profs in (('craft', CRAFT), ('harvest', HARVEST)):
    w('\t%s = {' % kind)
    for p in profs:
        items = d['professions'][str(p)]['items']
        kn = sorted((int(i), e['skill']) for i, e in items.items() if e['skill'] is not None)
        un = sorted(int(i) for i, e in items.items() if e['skill'] is None)
        c = cov[p]
        w('\t\t[%d] = { -- %s: %d known, %d unknown' % (p, c['profession'], c['known'], c['unknown']))
        w('\t\t\tknown = "%s",' % ','.join('%d:%d' % x for x in kn))
        w('\t\t\tunknown = "%s",' % ','.join(map(str, un)))
        w('\t\t},')
    w('\t},')
w('}')
open(OUT, 'w').write('\n'.join(L) + '\n')
print('wrote', OUT)
