#!/usr/bin/env python3
"""Resolve catalog.json against Wowhead WoW Forever (primary source).
- Instance name / level range / type / location: Forever zone tooltip (https://nether.wowhead.com/forever/tooltip/zone/<id>),
  cited as https://www.wowhead.com/forever/zone=<id>.
- Boss NPC IDs: Forever search (https://www.wowhead.com/forever/search/suggestions-template?q=<name>), exact-name NPC hits;
  then the Forever NPC tooltip confirms the name. Cited as https://www.wowhead.com/forever/npc=<id>.
Caches in wowhead_forever.json ("zone", "search"). Writes seed.json (generated) for gen_dungeons.py.
Exit 1 when an instance or boss cannot be confirmed on Forever."""
import json, re, sys, time, urllib.parse, urllib.request, urllib.error
from pathlib import Path
HERE = Path(__file__).resolve().parent
CACHE = HERE / "wowhead_forever.json"
UA = {"User-Agent": "Mozilla/5.0 (DarkMatter catalog check)"}

def get(url):
    try:
        return json.loads(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read())
    except (urllib.error.HTTPError, ValueError):
        return None

def zone(cache, zid):
    k = str(zid)
    if k not in cache["zone"]:
        d = get("https://nether.wowhead.com/forever/tooltip/zone/%d" % zid); time.sleep(0.2)
        z = None
        if d and d.get("name"):
            t = d.get("tooltip", "")
            lv = re.search(r"Level (\d+)(?:-(\d+))?", t)
            ty = re.search(r"Type: ([A-Za-z ]+)", t)
            loc = re.search(r"Location: ([^<]+)", t)
            z = {"name": d["name"], "levels": [int(lv.group(1)), int(lv.group(2) or lv.group(1))] if lv else None,
                 "type": ty.group(1).strip() if ty else None, "location": loc.group(1).strip() if loc else None}
        cache["zone"][k] = z
    return cache["zone"][k]

def search(cache, name):
    if name not in cache["search"]:
        d = get("https://www.wowhead.com/forever/search/suggestions-template?q=" + urllib.parse.quote(name)); time.sleep(0.25)
        cache["search"][name] = [{"id": r["id"], "boss": bool(r.get("boss"))} for r in (d or {}).get("results", [])
                                 if r.get("type") == 1 and r.get("name") == name]
    return cache["search"][name]

def npc_tip(cache, i):
    k = str(i)
    if k not in cache["npc"]:
        d = get("https://nether.wowhead.com/forever/tooltip/npc/%d" % i); time.sleep(0.2)
        cache["npc"][k] = {"name": d["name"], "quality": None, "icon": None} if d and d.get("name") else None
    return cache["npc"][k]

def main():
    cat = json.loads((HERE / "catalog.json").read_text())
    old = {}
    try:
        for d in json.loads((HERE / "seed.json").read_text())["dungeons"]:
            for b in d["bosses"]: old[b[0]] = b[1]
    except (OSError, KeyError, ValueError):
        pass
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    for k in ("npc", "item", "zone", "search"): cache.setdefault(k, {})
    out, bad, notes = [], 0, []
    for ins in cat["instances"]:
        z = zone(cache, ins["zoneId"])
        if not z:
            bad += 1; print("ZONE not on Forever", ins["zoneId"], ins["name"]); continue
        levels = ins.get("levels") or z["levels"]
        if not levels:
            bad += 1; print("no level range", ins["name"]); continue
        d = {"name": ins["name"], "short": ins["short"], "kind": ins["kind"], "zone": ins.get("zone") or z["location"] or "",
             "levels": levels, "zoneId": ins["zoneId"], "forever": bool(ins.get("forever")), "foreverZone": z["name"],
             "src": "https://www.wowhead.com/forever/zone=%d" % ins["zoneId"],
             "levelSrc": ins.get("levelSrc") or "https://www.wowhead.com/forever/zone=%d" % ins["zoneId"],
             "bossSrc": ins.get("bossSrc"), "aliases": ins.get("aliases", []), "size": ins.get("size", 5),
             "drops": bool(ins.get("drops")), "wing": ins.get("wing"), "parent": ins.get("parent"), "bosses": []}
        for b in ins["bosses"]:
            name, rare = (b[0], True) if isinstance(b, list) else (b, False)
            hits = search(cache, name)
            ids = [h["id"] for h in hits]
            pick = None
            ov = cat.get("npcOverride", {}).get(name)
            if isinstance(ov, int): pick = ov
            elif old.get(name) in ids: pick = old[name]
            elif hits:
                boss = [h["id"] for h in hits if h["boss"]]
                pool = boss or ids
                pick = max(pool) if ins.get("forever") else min(pool)
                if len(ids) > 1: notes.append("%s: %d Forever NPCs named %r -> %d %s" % (ins["short"], len(ids), name, pick, ids))
            if pick is None:
                bad += 1; print("BOSS not found on Forever:", ins["name"], "/", name); continue
            t = npc_tip(cache, pick)
            if not t or t["name"] != name:
                bad += 1; print("BOSS tooltip mismatch", name, pick, t); continue
            d["bosses"].append([name, pick, "rare"] if rare else [name, pick])
        out.append(d)
    CACHE.write_text(json.dumps(cache, indent=0, sort_keys=True))
    seed = {"_comment": "GENERATED by resolve_forever.py from catalog.json (hand-authored) + Wowhead WoW Forever lookups; do not edit.", "dungeons": out}
    (HERE / "seed.json").write_text(json.dumps(seed, indent=1, ensure_ascii=False) + "\n")
    for n in notes: print("note:", n)
    print("instances %d, bosses %d, unresolved %d" % (len(out), sum(len(d["bosses"]) for d in out), bad))
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
