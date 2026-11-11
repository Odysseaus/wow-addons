# Parse Wowhead Forever profession guides (markup saved in ../raw/guide-*.txt) into skill rows.
import re, json, glob, os
BASE = 'https://www.wowhead.com/forever/guide/'
FETCHED = '2026-11-11 10:58-10:59 CST'
rows = []
for f in sorted(glob.glob('../raw/guide-*.txt')):
    slug = os.path.basename(f)[6:-4].replace('_', '/')
    url = BASE + slug
    t = open(f).read()
    for ti, tab in enumerate(re.findall(r'\[table[^\]]*\](.*?)\[/table\]', t, re.S)):
        trs = re.findall(r'\[tr[^\]]*\](.*?)\[/tr\]', tab, re.S)
        if not trs: continue
        head = [re.sub(r'\[[^\]]*\]', '', c).strip().lower() for c in re.findall(r'\[td[^\]]*\](.*?)\[/td\]', trs[0], re.S)]
        skillcol = next((k for k, h in enumerate(head) if 'skill' in h), None)
        for tr in trs[1:]:
            cells = re.findall(r'\[td[^\]]*\](.*?)\[/td\]', tr, re.S)
            orange = re.search(r'\[color=skill-orange\](\d+)\[/color\]', tr)
            if orange:   # gathering node rows: node(s) + orange skill; loot in the next cell
                nodes = [int(x) for x in re.findall(r'\[object=(\d+)\]', cells[0])] if cells else []
                loot = [int(x) for x in re.findall(r'\[item=(\d+)\]', ' '.join(cells[1:2]))]
                rows.append({'kind': 'node', 'guide': url, 'table': ti, 'nodes': nodes, 'skill': int(orange.group(1)), 'items': loot})
            elif skillcol is not None and skillcol < len(cells):
                m = re.match(r'\s*(\d+)\s*$', re.sub(r'\[[^\]]*\]', '', cells[skillcol]))
                if not m: continue
                spells = [int(x) for x in re.findall(r'\[spell=(\d+)\]', cells[0])]
                items = []
                for k, c in enumerate(cells):
                    if k in (0, skillcol) or 'materials' in (head[k] if k < len(head) else ''): continue
                    items += [int(x) for x in re.findall(r'\[item=(\d+)\]', c)]
                rows.append({'kind': 'table', 'guide': url, 'table': ti, 'header': head, 'spells': spells, 'items': items,
                             'skill': int(m.group(1)), 'first': re.findall(r'\[(\w+)=(\d+)\]', cells[0])[:1]})
json.dump({'fetched': FETCHED, 'rows': rows}, open('guide_rows.json', 'w'), indent=0)
from collections import Counter
print(Counter((r['kind'], r['guide'].split('/')[-1][:30]) for r in rows))
