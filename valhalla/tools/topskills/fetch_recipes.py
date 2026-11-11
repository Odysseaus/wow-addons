# Polite fetch of Wowhead Forever item tooltips for recipe items (resumable). 1.5 s between requests.
import json, os, time, urllib.request, datetime
U = json.load(open('universe.json'))
RAW = '/workspace/valhalla/top10-skill-data/raw/tooltips'
os.makedirs(RAW, exist_ok=True)
UA = 'Mozilla/5.0 (compatible; ValhallaAddonResearch; user-directed)'
log = open('fetch_recipes.log', 'a')
for n, i in enumerate(U['cands']):
    p = f'{RAW}/item-{i}.json'
    if os.path.exists(p): continue
    url = f'https://nether.wowhead.com/forever/tooltip/item/{i}'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode('utf-8'); code = r.status
    except Exception as e:
        body, code = None, str(e)
    stamp = datetime.datetime.now().astimezone().isoformat(timespec='seconds')
    if body and code == 200:
        json.dump({'url': url, 'fetched': stamp, 'data': json.loads(body)}, open(p, 'w'))
    log.write(f'{stamp} {n+1}/{len(U["cands"])} {i} {code}\n'); log.flush()
    if code not in (200,) and ('403' in str(code) or '429' in str(code)):
        log.write('stopping: blocked/throttled\n'); break
    time.sleep(1.5)
log.write('done\n')
