# Valhalla 1.2.1: the Wowhead Forever reading list for Top 10's unknown craft levels.
# One line per unknown crafted item (per profession):  craftedItemId | profession | recipe item id | url
# The recipe item: a recipe item whose Wowhead tooltip (top10-skill-data/raw/tooltips, all 1630 Recipe-class items of the
# client) teaches the item's recipe spell (skills.json "spells"). None known: "?" and the crafted item's own page
# (its "Created by" tab has the skill). Never guessed. Gathered items (Herbalism, Mining, Skinning, Fishing) are not
# crafts: left out.
import json, re, glob, os, sys
DATA = sys.argv[1] if len(sys.argv) > 1 else '/workspace/valhalla/top10-skill-data'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/workspace/valhalla/topskill-data/recipe-urls.txt'
CRAFT = [171, 164, 333, 202, 165, 197, 185, 129]
d = json.load(open(os.path.join(DATA, 'skills.json')))
teach = {}
for p in glob.glob(os.path.join(DATA, 'raw/tooltips/item-*.json')):
    rid = int(re.search(r'item-(\d+)\.json$', p).group(1))
    tip = json.load(open(p))['data'].get('tooltip', '')
    for s in set(re.findall(r'/spell=(\d+)', tip)): teach.setdefault(int(s), set()).add(rid)
lines, counts = [], {}
for prof in CRAFT:
    e = d['professions'][str(prof)]
    for iid in sorted(e['items'], key=int):
        v = e['items'][iid]
        if v.get('skill') is not None: continue
        spells = v.get('spells') or ([v['spell']] if v.get('spell') else [])
        recipes = sorted({r for s in spells for r in teach.get(s, ())})
        if recipes:
            for r in recipes: lines.append('%s | %s | %d | https://www.wowhead.com/forever/item=%d' % (iid, e['name'], r, r))
        else:
            lines.append('%s | %s | ? | https://www.wowhead.com/forever/item=%s' % (iid, e['name'], iid))
        counts[e['name']] = counts.get(e['name'], 0) + 1
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'w').write('\n'.join(lines) + '\n')
for k in sorted(counts): print('%-15s %d' % (k, counts[k]))
print('total', len(lines), 'lines;', sum(1 for l in lines if ' | ? | ' not in l), 'with a recipe item')
