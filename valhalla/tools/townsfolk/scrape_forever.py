#!/usr/bin/env python3
# Valhalla 1.2.39: Wowhead WoW Forever service NPCs and mailboxes.
# www.wowhead.com list pages answer with an AWS WAF challenge (HTTP 202, no data).
# The tooltip API does answer: https://nether.wowhead.com/forever/tooltip/{npc|object}/<id>
# This walks id ranges, keeps a record only when that Forever tooltip names a phase-1
# service and gives a spawn. Nothing is filled in from classic or from Questie.
#
#   scrape_forever.py
# Resumes from tools/townsfolk-data/forever-1239/state.json.
import json, os, re, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, '..', 'townsfolk-data', 'forever-1239'))
UA = 'Mozilla/5.0 (compatible; ValhallaAddonResearch; user-directed)'
WORKERS = 16

# id ranges actually probed. High Forever creature ids seen on dungeon pages start near 261000.
NPC_RANGES = [(1, 25001), (260000, 262501)]
# mailboxes are game objects. The tooltip name "Mailbox" is what keeps one.
OBJECT_RANGES = [(1, 200001)]

ALLIANCE = {
    'stormwind', 'ironforge', 'gnomeregan exiles', 'darnassus', 'alliance',
    'silverwing sentinels', 'stormpike guard',
}
HORDE = {
    'orgrimmar', 'darkspear trolls', 'undercity', 'thunder bluff', 'horde',
    'the forsaken', 'warsong outriders', 'frostwolf clan',
}
CLASS_TITLE = {
    'warrior trainer': 'WARRIOR', 'paladin trainer': 'PALADIN', 'hunter trainer': 'HUNTER',
    'rogue trainer': 'ROGUE', 'priest trainer': 'PRIEST', 'shaman trainer': 'SHAMAN',
    'mage trainer': 'MAGE', 'warlock trainer': 'WARLOCK', 'druid trainer': 'DRUID',
    'portal trainer': 'MAGE', 'pet trainer': 'HUNTER', 'demon trainer': 'WARLOCK',
}
# The craft named by a Forever title. Longer keys first so "leatherworking" wins over nothing shorter.
PROF_KEYS = (
    ('blacksmith', 'blacksmithing'), ('enchant', 'enchanting'), ('engineer', 'engineering'),
    ('leather', 'leatherworking'), ('tailor', 'tailoring'), ('alchem', 'alchemy'),
    ('herbal', 'herbalism'), ('skinning', 'skinning'), ('skinner', 'skinning'),
    ('mining', 'mining'), ('miner', 'mining'), ('fishing', 'fishing'), ('fisherman', 'fishing'),
    ('cooking', 'cooking'), ('cook', 'cooking'), ('first aid', 'firstaid'),
)
# The whole title, when Forever does not say "Trainer" but this is the trainer.
CRAFT_NAME = {
    'herbalist': 'herbalism', 'miner': 'mining', 'skinner': 'skinning',
    'cook': 'cooking', 'fisherman': 'fishing',
}
RANK = ('journeyman ', 'expert ', 'artisan ', 'master ')
# Merchants that stay vendors and use the Repair icon. Not blacksmithing supplies (those are the profession).
REPAIR_VENDOR = (
    'weapon merchant', 'weapons merchant', 'weapon vendor', 'weapons vendor',
    'bow merchant', 'bow & gun', 'bow & arrow', 'bowyer', 'gunsmith', 'thrown weapon',
    'armor crafter', 'armorer', 'armorsmith', 'weaponsmith', 'light armor & weapons',
    'two handed weapon', 'two-handed weapon',
)
SKIP_TITLE = (
    'flight master', 'gryphon master', 'wind rider', 'bat handler', 'hippogryph',
    'dragonhawk master', 'weapon master',
)

def cells(html):
    out = []
    for raw in re.findall(r'<td>(.*?)</td>', html or '', re.S):
        t = re.sub(r'<[^>]+>', '', raw).strip()
        if t:
            out.append(re.sub(r'\s+', ' ', t))
    return out

def faction_of(lines):
    a = h = False
    for line in lines:
        k = line.lower()
        if k in ALLIANCE: a = True
        if k in HORDE: h = True
    if a and h: return 'AH'
    if a: return 'A'
    if h: return 'H'
    return 'AH'

def junk_name(name):
    n = (name or '').lower()
    return any(s in n for s in ('[ph]', '[unused]', 'unused]', 'placeholder', 'temp ', 'pissed ', 'test npc'))

def classify(name, lines):
    """A phase-1 type, or None. The decision uses only this Forever tooltip."""
    name = name or ''
    if junk_name(name): return None
    low = name.lower()
    title = ''
    for line in lines[1:]:
        k = line.lower()
        if k.startswith('level ') or k in ('friendly', 'hostile'): continue
        if k in ALLIANCE or k in HORDE: continue
        if 'humanoid' in k or k.endswith('(normal)') or k.endswith('(elite)'): continue
        title = line
        break
    blob = (title + ' ' + name).lower()
    for s in SKIP_TITLE:
        if s in blob: return None
    if 'unused' in low or low.startswith('placeholder'): return None
    tl = title.lower()
    if tl == 'innkeeper' or low.startswith('innkeeper '):
        return 'innkeeper', title or 'Innkeeper', None
    if tl == 'banker':
        return 'banker', title, None
    if tl == 'auctioneer' or low.startswith('auctioneer '):
        return 'auctioneer', title or 'Auctioneer', None
    if tl == 'stable master':
        return 'stable', title, None
    if tl == 'mailbox' or low == 'mailbox':
        return 'mailbox', title or 'Mailbox', None
    if tl == 'spirit healer' or low == 'spirit healer':
        return 'spirit', title or 'Spirit Healer', None
    if 'repair' in tl:
        return 'repair', title, None
    if 'reagent' in tl:
        return 'reagent', title, None
    if 'food' in tl or 'drink' in tl or tl in ('bartender', 'baker', 'butcher'):
        return 'food', title, None
    if tl in CLASS_TITLE:
        return 'classTrainer', title, CLASS_TITLE[tl], None
    prof = None
    for key, name in PROF_KEYS:
        if key in tl:
            prof = name
            break
    trainer = tl.endswith(' trainer') or ' trainer' in tl or any(tl.startswith(r) for r in RANK) or tl in CRAFT_NAME
    if prof and trainer:
        return prof, title, None, None
    if prof == 'blacksmithing' and ('suppl' in tl):
        return 'blacksmithing', title, None, 'repair'
    if prof and any(w in tl for w in ('suppl', 'vendor', 'merchant', 'goods')):
        return prof, title, None, None
    if any(w in tl for w in REPAIR_VENDOR):
        return 'vendor', title, None, 'repair'
    # the title itself has to say they sell something. A name that merely contains "vendor" does not.
    if any(w in tl for w in ('vendor', 'merchant', 'supplier', 'supplies', 'goods')):
        return 'vendor', title, None, None
    return None

def points(data):
    mp = data.get('map') or {}
    zone = mp.get('zone')
    coords = mp.get('coords') or {}
    pts = []
    if isinstance(coords, dict):
        for group in coords.values():
            if not isinstance(group, list): continue
            for c in group:
                if isinstance(c, (list, tuple)) and len(c) >= 2:
                    try:
                        x, y = float(c[0]), float(c[1])
                    except (TypeError, ValueError):
                        continue
                    if x == x and y == y and 0 <= x <= 100 and 0 <= y <= 100:
                        pts.append([round(x, 2), round(y, 2)])
    return zone, pts

def fetch(kind, i):
    url = 'https://nether.wowhead.com/forever/tooltip/%s/%d' % (kind, i)
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            body = r.read().decode('utf-8', 'replace')
            if r.status != 200: return i, r.status, None
            return i, 200, json.loads(body)
    except Exception as e:
        code = getattr(e, 'code', None)
        return i, code or 0, str(e)[:160]

def load_state():
    p = os.path.join(OUT, 'state.json')
    if os.path.exists(p):
        return json.load(open(p, encoding='utf-8'))
    return {'npc_through': 0, 'object_through': 0, 'kept': {}, 'errors': 0, 'blocked': False, 'notes': []}

def save_state(st):
    json.dump(st, open(os.path.join(OUT, 'state.json'), 'w'), indent=2, sort_keys=True)

def scan(kind, ranges, through_key, st, outfh):
    done = st.get(through_key, 0)
    # flatten remaining ids in order
    ids = []
    for a, b in ranges:
        for i in range(a, b):
            if i > done: ids.append(i)
    if not ids: return
    print('scan', kind, 'from', ids[0], 'count', len(ids), flush=True)
    step = 400
    for off in range(0, len(ids), step):
        if st.get('blocked'): return
        chunk = ids[off:off + step]
        with ThreadPoolExecutor(WORKERS) as ex:
            rows = list(ex.map(lambda i: fetch(kind, i), chunk))
        for i, code, data in rows:
            if code in (403, 429, 202):
                st['blocked'] = True
                st['blocked_at'] = {'kind': kind, 'id': i, 'code': code}
                save_state(st)
                print('blocked', code, 'at', kind, i, flush=True)
                return
            if code == 200 and isinstance(data, dict):
                got = classify(data.get('name'), cells(data.get('tooltip')))
                zone, pts = points(data)
                if got and pts and zone and not (kind == 'npc' and got[0] == 'mailbox') and not (kind == 'object' and got[0] != 'mailbox'):
                    typ, title, tag = got[0], got[1], got[2]
                    icon = got[3] if len(got) > 3 else None
                    rec = {
                        'kind': kind, 'id': i, 'name': data.get('name'), 'title': title,
                        'type': typ, 'trainerTag': tag, 'icon': icon,
                        'faction': faction_of(cells(data.get('tooltip'))),
                        'zone': zone, 'points': pts,
                        'url': 'https://nether.wowhead.com/forever/tooltip/%s/%d' % (kind, i),
                        'tooltip': data.get('tooltip'),
                    }
                    outfh.write(json.dumps(rec, ensure_ascii=False) + '\n')
                    st['kept'][typ] = st['kept'].get(typ, 0) + 1
                elif got and (not pts or not zone):
                    ns = st.setdefault('no_spawn', {})
                    ns[got[0]] = ns.get(got[0], 0) + 1
            elif code not in (200, 404, None) and code != 0:
                st['errors'] = st.get('errors', 0) + 1
        st[through_key] = chunk[-1]
        save_state(st)
        outfh.flush()
        print('  %s through %d kept %s' % (kind, chunk[-1], st['kept']), flush=True)
        time.sleep(0.15)

def main():
    os.makedirs(OUT, exist_ok=True)
    st = load_state()
    st['source'] = 'https://nether.wowhead.com/forever/tooltip/{npc|object}/<id>'
    st['list_pages'] = 'www.wowhead.com/forever/npcs returned HTTP 202 (AWS WAF challenge, empty of NPC rows)'
    mode = 'a' if os.path.exists(os.path.join(OUT, 'results.jsonl')) else 'w'
    with open(os.path.join(OUT, 'results.jsonl'), mode, encoding='utf-8') as fh:
        scan('npc', NPC_RANGES, 'npc_through', st, fh)
        if not st.get('blocked'):
            scan('object', OBJECT_RANGES, 'object_through', st, fh)
    st['finished'] = not st.get('blocked')
    save_state(st)
    print('done', json.dumps(st.get('kept'), sort_keys=True), 'blocked', st.get('blocked'))

if __name__ == '__main__':
    main()
