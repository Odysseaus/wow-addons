# Cross-checks every catalog entry against Wowhead's public Classic tooltip endpoint
# (https://nether.wowhead.com/classic/tooltip/item/<id>): name, quality, icon. Facts only; output kept as a source record.
import json, re, os, time, urllib.request
D = os.path.dirname(os.path.abspath(__file__)) + '/'
LUA = os.path.join(D, '..', '..', 'DarkMatter', 'Data_FishingCatches.lua')
s = open(LUA).read()
E = [(int(m.group(1)), m.group(2).replace('\\"', '"'), m.group(3), m.group(4)) for m in re.finditer(r'\{ itemId = (\d+), name = "((?:[^"\\]|\\.)*)", cat = "(\w+)"(.*?)\},', s)]
out = {}
cache = D + 'wowhead_classic.json'
if os.path.exists(cache): out = json.load(open(cache))
for iid, name, cat, rest in E:
    k = str(iid)
    if k not in out:
        req = urllib.request.Request('https://nether.wowhead.com/classic/tooltip/item/%d' % iid, headers={'User-Agent': 'Mozilla/5.0'})
        try:
            j = json.loads(urllib.request.urlopen(req, timeout=20).read())
            out[k] = {'name': j.get('name'), 'quality': j.get('quality'), 'icon': j.get('icon'), 'offhand': 'Held In Off-hand' in (j.get('tooltip') or '')}
        except Exception as ex:
            out[k] = {'error': str(ex)}
        time.sleep(0.15)
json.dump(out, open(cache, 'w'), indent=1, sort_keys=True)
bad = 0
for iid, name, cat, rest in E:
    w = out[str(iid)]
    q = re.search(r'quality = (\d)', rest)
    q = int(q.group(1)) if q else None
    issues = []
    if w.get('error') or not w.get('name'): issues.append('missing on Wowhead Classic: %s' % w.get('error'))
    else:
        if w['name'] != name: issues.append('name: ours %r, wowhead %r' % (name, w['name']))
        if q is not None and q != w['quality']: issues.append('quality: ours %s, wowhead %s' % (q, w['quality']))
    if issues:
        bad += 1
        print(iid, cat, name, '|', '; '.join(issues))
print('entries', len(E), 'with issues', bad)
