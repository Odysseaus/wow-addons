#!/usr/bin/env python3
# Valhalla 1.2.39: Data/Forever/Townsfolk.lua from tools/townsfolk-data/forever-1239/results.jsonl.
# A Wowhead zone id is kept only when its Forever tooltip name matches a map Valhalla already
# draws (Levels.lua, Fishing.lua, Banners.lua). No classic coordinates are copied in.
import json, os, re, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
PACK = os.path.join(HERE, '..', 'townsfolk-data', 'forever-1239')
OUT = os.path.join(REPO, 'Valhalla', 'Data', 'Forever', 'Townsfolk.lua')
UA = 'Mozilla/5.0 (compatible; ValhallaAddonResearch; user-directed)'
DATA_LUA = [
    os.path.join(REPO, 'Valhalla', 'Data', 'Forever', 'Levels.lua'),
    os.path.join(REPO, 'Valhalla', 'Data', 'Forever', 'Fishing.lua'),
    os.path.join(REPO, 'Valhalla', 'Data', 'Forever', 'Banners.lua'),
]

def norm(s):
    s = (s or '').lower().strip()
    s = re.sub(r'\s*\(.*', '', s)
    s = re.sub(r'[^a-z0-9 ]+', '', s)
    s = re.sub(r'\s+', ' ', s).strip()
    if s.startswith('the '): s = s[4:]
    return s

def valhalla_maps():
    found = {}
    for path in DATA_LUA:
        text = open(path, encoding='utf-8').read()
        for m in re.finditer(r'\[(\d+)\].*?--\s*([^\n]+)', text):
            name = re.sub(r'\s*\(.*', '', m.group(2)).strip()
            if not name or name[0].isdigit(): continue
            found.setdefault(norm(name), set()).add(int(m.group(1)))
    return found

def zone_name(zone, cache):
    if zone in cache: return cache[zone]
    url = 'https://nether.wowhead.com/forever/tooltip/zone/%d' % zone
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=20) as r:
            data = json.loads(r.read().decode())
            name = data.get('name')
    except Exception:
        name = None
    cache[zone] = name
    return name

def cluster(pts, eps=1.0):
    left = [tuple(p) for p in pts]
    groups = []
    while left:
        g = [left.pop()]
        grew = True
        while grew:
            grew = False
            i = 0
            while i < len(left):
                q = left[i]
                if any((q[0] - a[0]) ** 2 + (q[1] - a[1]) ** 2 <= eps * eps for a in g):
                    g.append(left.pop(i))
                    grew = True
                else:
                    i += 1
        groups.append(g)
    reps = []
    for g in groups:
        reps.append((round(sum(p[0] for p in g) / len(g), 2), round(sum(p[1] for p in g) / len(g), 2)))
    return reps

def place(pts, spirit):
    reps = cluster(pts)
    if not spirit and len(reps) > 6:
        sx = sum(p[0] for p in reps) / len(reps)
        sy = sum(p[1] for p in reps) / len(reps)
        best = min(reps, key=lambda p: (p[0] - sx) ** 2 + (p[1] - sy) ** 2)
        return [best], True
    return reps, False

def lua_str(s):
    return '"' + (s or '').replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'

def main():
    maps = valhalla_maps()
    cache = {}
    cache_path = os.path.join(PACK, 'zones.json')
    if os.path.exists(cache_path):
        cache = {int(k): v for k, v in json.load(open(cache_path, encoding='utf-8')).items()}
    seen = {}
    rows = []
    for line in open(os.path.join(PACK, 'results.jsonl'), encoding='utf-8'):
        if line.strip():
            rec = json.loads(line)
            seen[(rec['kind'], rec['id'])] = rec
    failures = {'no_map': 0, 'unmapped_zone': {}, 'records': 0}
    zone_of = {}
    for rec in seen.values():
        z = rec.get('zone')
        if z not in zone_of:
            zone_of[z] = zone_name(z, cache)
    json.dump({str(k): v for k, v in cache.items()}, open(cache_path, 'w'), indent=2, sort_keys=True)
    out_recs = []
    for rec in sorted(seen.values(), key=lambda r: (r['type'], r['id'])):
        name = zone_of.get(rec.get('zone'))
        uis = maps.get(norm(name or ''))
        if not name or not uis or len(uis) != 1:
            failures['no_map'] += 1
            key = '%s (%s)' % (name or '?', rec.get('zone'))
            failures['unmapped_zone'][key] = failures['unmapped_zone'].get(key, 0) + 1
            continue
        ui = next(iter(uis))
        pts, walked = place(rec.get('points') or [], rec['type'] == 'spirit')
        if not pts:
            failures['no_map'] += 1
            continue
        for x, y in pts:
            out_recs.append({
                'id': rec['id'], 'name': rec['name'], 'title': rec.get('title') or '',
                'faction': rec.get('faction') or 'AH', 'map': ui, 'x': x, 'y': y,
                'type': rec['type'], 'trainerTag': rec.get('trainerTag') or '',
                'icon': rec.get('icon') or '',
                'kind': rec['kind'], 'walked': walked,
            })
    counts = {}
    for r in out_recs:
        counts[r['type']] = counts.get(r['type'], 0) + 1
    failures['placed'] = counts
    failures['npcs'] = len(seen)
    json.dump(failures, open(os.path.join(PACK, 'build.json'), 'w'), indent=2, sort_keys=True)
    lines = [
        '-- Townsfolk for the world map (inns, vendors, trainers, mailboxes).',
        '-- Generated by tools/townsfolk/build_townsfolk.py; regenerate rather than edit.',
        '-- Source: Wowhead WoW Forever tooltips, https://nether.wowhead.com/forever/tooltip/{npc|object}/<id>.',
        '-- A point is kept only when that tooltip names the service and gives a spawn, and the',
        '-- tooltip\'s zone name is one of Valhalla\'s maps. Points within 1 map-percent are one',
        '-- spot. An NPC with more than 6 spots in a zone, other than a spirit healer, keeps the',
        '-- spot nearest the middle (the same walk rule as Map/Townsfolk.lua).',
        '',
        'local _, ns = ...',
        '',
        'ns.TownsfolkData = {',
        '\trecords = {',
    ]
    for r in out_recs:
        tag = (', trainerTag = %s' % lua_str(r['trainerTag'])) if r['trainerTag'] else ''
        icon = (', icon = %s' % lua_str(r['icon'])) if r.get('icon') else ''
        lines.append('\t\t{ id = %d, name = %s, title = %s, faction = %s, map = %d, x = %s, y = %s, type = %s%s%s },' % (
            r['id'], lua_str(r['name']), lua_str(r['title']), lua_str(r['faction']),
            r['map'], ('%g' % r['x']), ('%g' % r['y']), lua_str(r['type']), tag, icon))
    lines.append('\t},')
    lines.append('}')
    open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    print('records', len(out_recs))
    print('counts', json.dumps(counts, sort_keys=True))
    print('unmapped', json.dumps(failures['unmapped_zone'], sort_keys=True))

if __name__ == '__main__':
    main()
