#!/usr/bin/env python3
"""Fetch each seeded boss's Wowhead Classic NPC page and cache only what we need:
page title (to verify the NPC ID matches the boss name) and the 'drops' list (id, name, quality,
class, count/outof, commondrop). Cached to wowhead_npc.json; re-run with --refresh to refetch."""
import json, re, sys, time, urllib.request
from pathlib import Path
HERE = Path(__file__).resolve().parent
SEED = json.loads((HERE / "seed.json").read_text())
OUT = HERE / "wowhead_npc.json"
UA = {"User-Agent": "Mozilla/5.0 (DarkMatter catalog check)"}

def listview(html, lvid):
    i = html.find("id: '%s'" % lvid)
    if i < 0: return []
    j = html.index("data:", i) + 5
    k = html.index("[", j); d = 0
    for m in range(k, len(html)):
        if html[m] == "[": d += 1
        elif html[m] == "]":
            d -= 1
            if d == 0: return json.loads(html[k:m + 1])
    return []

def main():
    cache = json.loads(OUT.read_text()) if OUT.exists() and "--refresh" not in sys.argv else {}
    for dg in SEED["dungeons"]:
        if not dg.get("drops", True): continue  # 0.3.2: boss lists only (raids, Forever-only instances)
        for b in dg["bosses"]:
            npc = str(b[1])
            if npc in cache: continue
            req = urllib.request.Request("https://www.wowhead.com/classic/npc=%s" % npc, headers=UA)
            try:
                html = urllib.request.urlopen(req, timeout=30).read().decode("utf8", "replace")
            except Exception as e:  # noqa: BLE001
                print("fetch failed", npc, b[0], e); continue
            t = re.search(r"<title>([^<]*?) - NPC", html)
            drops = []
            for it in listview(html, "drops"):
                drops.append({k: it.get(k) for k in ("id", "name", "quality", "classs", "subclass", "slot", "count", "outof", "commondrop")})
            cache[npc] = {"title": t.group(1) if t else None, "drops": drops}
            print(npc, cache[npc]["title"], len(drops)); time.sleep(0.6)
    OUT.write_text(json.dumps(cache, indent=0, sort_keys=True))
    print("cached", len(cache), "npcs")

if __name__ == "__main__":
    main()
