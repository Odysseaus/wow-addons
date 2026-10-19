#!/usr/bin/env python3
"""Validate the Adventure Guide seed against Wowhead's WoW Forever data (primary source).
Uses Wowhead's Forever tooltip API (https://nether.wowhead.com/forever/tooltip/{npc|item}/<id>);
the Forever HTML pages (https://www.wowhead.com/forever/npc=<id>, /forever/item=<id>) are the
citation URLs. Caches to wowhead_forever.json. Exit 1 on any NPC/item that is missing in Forever
or whose name differs from the seed / Classic fallback."""
import json, sys, time, urllib.request, urllib.error
from pathlib import Path
HERE = Path(__file__).resolve().parent
OUT = HERE / "wowhead_forever.json"
UA = {"User-Agent": "Mozilla/5.0 (DarkMatter catalog check)"}

def fetch(kind, i):
    url = "https://nether.wowhead.com/forever/tooltip/%s/%s" % (kind, i)
    try:
        d = json.loads(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read())
    except (urllib.error.HTTPError, ValueError):
        return None
    if not d or not d.get("name"): return None
    return {k: d.get(k) for k in ("name", "quality", "icon")}

def load():
    return json.loads(OUT.read_text()) if OUT.exists() else {"npc": {}, "item": {}}

def ensure(cache, kind, ids, refresh=False):
    for i in ids:
        k = str(i)
        if k in cache[kind] and not refresh: continue
        cache[kind][k] = fetch(kind, i); time.sleep(0.25)
    OUT.write_text(json.dumps(cache, indent=0, sort_keys=True))
    return cache

if __name__ == "__main__":
    sys.path.insert(0, str(HERE))
    from gen_dungeons import build  # noqa
    seed, picked = build(validate=False)
    cache = load()
    npcs = [b[1] for d in seed["dungeons"] for b in d["bosses"]]
    items = sorted({it["id"] for d in picked for b in d["bosses"] for it in b["drops"]})
    cache = ensure(cache, "npc", npcs, "--refresh" in sys.argv)
    cache = ensure(cache, "item", items, "--refresh" in sys.argv)
    bad = 0
    for d in seed["dungeons"]:
        for b in d["bosses"]:
            f = cache["npc"].get(str(b[1]))
            if not f or f["name"] != b[0]:
                bad += 1; print("NPC", b[1], b[0], "-> Forever:", f and f["name"])
    for d in picked:
        for b in d["bosses"]:
            for it in b["drops"]:
                f = cache["item"].get(str(it["id"]))
                if not f:
                    bad += 1; print("ITEM missing in Forever", it["id"], it["name"])
                elif f["name"] != it["name"]:
                    bad += 1; print("ITEM name", it["id"], it["name"], "-> Forever:", f["name"])
    print("checked %d npcs, %d items against Wowhead Forever: %d issue(s)" % (len(npcs), len(items), bad))
    sys.exit(1 if bad else 0)
