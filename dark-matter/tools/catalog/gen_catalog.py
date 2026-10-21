# Generates DarkMatter/Data_FishingCatches.lua from facts researched on public pages (see SOURCES).
# Not derived from any addon's tables.
import json, re
import os
D = os.path.dirname(os.path.abspath(__file__)) + '/'
OUT = os.path.join(D, '..', '..', 'DarkMatter', 'Data_FishingCatches.lua')
WH = json.load(open(D+'wowhead_classic.json'))  # verify_wowhead.py: Wowhead Classic tooltip facts per id
res = json.load(open(D+'res.json')); res2 = json.load(open(D+'res2.json')); loc = json.load(open(D+'loc.json'))
def iid(n):
    for r in (res2.get(n, {}), res.get(n, {})):
        if r.get('ids'): return int(r['ids'][0])
    raise SystemExit('no id for '+n)
EXTRA_IDS = {'32 Pound Catfish': 6364, '18 Pound Salmon': 13902, 'Sealed Crate': 6357}  # from wiki item pages fetched separately
NON_CLASSIC_ZONES = {"Eversong Woods","Ghostlands","Azuremyst Isle","Bloodmyst Isle","Isle of Quel'Danas","Twilight Highlands","Lost Isles","Gilneas","Kezan","Vashj'ir"}
ZONE_FIX = {"Northern Barrens":"The Barrens","Southern Barrens":"The Barrens","Northern Stranglethorn":"Stranglethorn Vale","The Cape of Stranglethorn":"Stranglethorn Vale"}
def waters_of(name, n=3):
    e = loc.get(name); 
    if not e: return None, None
    zs = []
    for z in e['zones']:
        z = ZONE_FIX.get(z, z)
        if z not in NON_CLASSIC_ZONES and z not in zs: zs.append(z)
    return (", ".join(zs[:n]) if zs else None), e['skill']
# Existing 0.2.6 icon paths kept only where the id->name mapping is unchanged (13888 was mislabelled; dropped).
OLD_ICONS = {6291:"INV_Misc_Fish_07",6303:"INV_Misc_Fish_24",6289:"INV_Misc_Fish_32",6317:"INV_Misc_Fish_03",6361:"INV_Misc_Fish_25",6308:"INV_Misc_Fish_30",6362:"INV_Misc_Fish_04",21071:"INV_Misc_Fish_11",21153:"INV_Misc_Fish_20",6358:"INV_Misc_MonsterHead_04",6359:"INV_Misc_MonsterHead_01",13422:"INV_Misc_Fish_11",4603:"INV_Misc_Fish_01",8365:"INV_Misc_Fish_02",13754:"INV_Misc_Fish_06",13756:"INV_Misc_Fish_03",13758:"INV_Misc_Fish_06",13760:"INV_Misc_Fish_22",13889:"INV_Misc_Fish_22",13893:"INV_Misc_Fish_06",13876:"INV_Misc_Fish_02",13877:"INV_Misc_Fish_02",13878:"INV_Misc_Fish_02",13879:"INV_Misc_Fish_02",13880:"INV_Misc_Fish_02",6360:"INV_Misc_Fish_04",19808:"INV_Misc_Fish_08",6292:"INV_Misc_Fish_32",6294:"INV_Misc_Fish_32",6295:"INV_Misc_Fish_32",6299:"INV_Misc_Fish_08",6307:"INV_Misc_Note_06",6651:"INV_Drink_10",5523:"INV_Misc_Shell_01",5524:"INV_Misc_Shell_02",7973:"INV_Misc_Shell_01"}
# Confirmed on a live Forever 1.60.1 (Interface 16001) client: caught and shown in Odysseaus's Dark Matter 0.2.5 screenshot (2026-10-19).
FOREVER_CONFIRMED = {6291, 6289, 6308}

W = 'https://warcraft.wiki.gg/wiki/'
SECTIONS = []
def sec(title, cat, sources, items):
    SECTIONS.append((title, cat, sources, items))

fish = ["Raw Brilliant Smallfish","Raw Slitherskin Mackerel","Raw Longjaw Mud Snapper","Raw Rainbow Fin Albacore","Raw Loch Frenzy","Raw Sagefish","Raw Bristle Whisker Catfish","Raw Greater Sagefish","Raw Mithril Head Trout","Raw Rockscale Cod","Raw Sunscale Salmon","Raw Nightfin Snapper","Raw Glossy Mightfish","Large Raw Mightfish","Winter Squid","Raw Summer Bass","Raw Redgill","Raw Spotted Yellowtail","Darkclaw Lobster","Raw Whitescale Salmon"]
sec("Food fish (Eastern Kingdoms and Kalimdor)", "fish", [W+"Fishing_items#Eastern_Kingdoms_and_Kalimdor", W+"Fishing_locations"], [(n,{}) for n in fish])
special = [("Sickly Looking Fish",{"waters":"Tirisfal Glades, Undercity, Blackfathom Deeps"}),("Oil Covered Fish",{"waters":"The Barrens oil spills (Sludge Fen)"}),("Darkshore Grouper",{"waters":"Darkshore coast (Auberdine)"}),("Oily Blackmouth",{}),("Firefin Snapper",{}),("Stonescale Eel",{}),("Deviate Fish",{"waters":"The Barrens oases, Wailing Caverns"}),("Lightning Eel",{}),("Threshadon Fang",{"waters":"Dustwallow Marsh (Theramore)","quality":0})]
sec("Special and alchemy fish", "special", [W+"Fishing_items#Alchemic_fish", W+"Fishing_locations"], special)
quest = [("Feralas Ahi",{"waters":"Feralas"}),("Misty Reed Mahi Mahi",{"waters":"Swamp of Sorrows"}),("Sar'theris Striker",{"waters":"Desolace"}),("Savage Coast Blue Sailfin",{"waters":"Stranglethorn Vale"}),("Speckled Tastyfish",{"waters":"Stranglethorn Vale (Fishing Extravaganza)"}),("Brownell's Blue Striped Racer",{"waters":"Stranglethorn Vale (Fishing Extravaganza)"}),("Dezian Queenfish",{"waters":"Stranglethorn Vale (Fishing Extravaganza)"}),("Keefer's Angelfish",{"waters":"Stranglethorn Vale (Fishing Extravaganza)"}),("Zulian Mudskunk",{"waters":"Zul'Gurub"})]
sec("Quest and event fish", "quest", [W+"Fishing_items#Quest_fish", W+"Stranglethorn_Fishing_Extravaganza"], quest)
trophy_fam = [("Mud Snapper",["10","12","15"],"Raw Longjaw Mud Snapper"),("Catfish",["17","19","22","26","32"],"Raw Bristle Whisker Catfish"),("Redgill",["34","37","42","45","49","52"],"Raw Redgill"),("Grouper",["40","47","53","59","68"],None),("Salmon",["15","18","22","25","29","32"],None),("Mightfish",["70","85","92","103"],None),("Lobster",["7","9","12","15","19","21","22"],None)]
trophies = []
for fam, sizes, base in trophy_fam:
    wt = waters_of(base)[0] if base else None
    for s in sizes:
        o = {"quality":2}
        if wt: o["waters"] = wt
        trophies.append((f"{s} Pound {fam}", o))
sec("Trophy fish (uncommon, very rare)", "trophy", [W+"Fishing_items#Trophy_fish"], trophies)
bloated = [("Bloated Smallfish","Raw Brilliant Smallfish"),("Bloated Mud Snapper","Raw Longjaw Mud Snapper"),("Bloated Oily Blackmouth","Oily Blackmouth"),("Bloated Catfish","Raw Bristle Whisker Catfish"),("Bloated Rockscale Cod","Raw Rockscale Cod"),("Bloated Trout","Raw Mithril Head Trout"),("Bloated Mightfish",None),("Bloated Redgill","Raw Redgill"),("Bloated Salmon",None)]
sec("Container fish (bloated: same waters as the normal fish)", "container", [W+"Fishing_items#Container_fish"], [(n, ({"waters":waters_of(b)[0]} if b and waters_of(b)[0] else {})) for n,b in bloated])
sec("Clams", "clam", [W+"Fishing_items#Clams"], [(n,{}) for n in ["Small Barnacled Clam","Thick-Shelled Clam","Big-Mouth Clam"]])
sec("Venture Company crates", "crate", [W+"Fishing_items#Venture_Company_crates"], [(n,{}) for n in ["Dented Crate","Waterlogged Crate","Sealed Crate","Heavy Crate"]])
sec("Trunks (Floating Wreckage)", "trunk", [W+"Fishing_items#Trunks_&_Crates"], [(n,{"waters":"Floating Wreckage pools"}) for n in ["Tightly Sealed Trunk","Watertight Trunk","Iron Bound Trunk","Mithril Bound Trunk"]])
sec("Locked chests", "chest", [W+"Fishing_items#Locked_chests"], [(n,{}) for n in ["Small Locked Chest","Sturdy Locked Chest","Ironbound Locked Chest","Reinforced Locked Chest"]])
misc = [("Message in a Bottle",{"waters":"Ocean, zones level 20-40"}),("Rumsey Rum Light",{"waters":"Floating Wreckage pools"}),("Rumsey Rum Dark",{"waters":"Floating Wreckage pools"}),("Rumsey Rum Black Label",{"waters":"Floating Wreckage pools"})]
sec("Bottles and rum", "misc", [W+"Fishing_items#Other", W+"Fishing_items#Rumsey_Rums"], misc)
reag = [("Stranglekelp",{"waters":"Coastal waters, worldwide"}),("Deviate Scale",{"waters":"The Barrens oases, Wailing Caverns"}),("Elemental Water",{"waters":"Azshara elemental water pools"}),("Essence of Water",{"waters":"Azshara elemental water pools"}),("Globe of Water",{"waters":"Azshara elemental water pools"}),("Elemental Fire",{"waters":"Un'Goro Crater (Fire Plume Ridge)"}),("Essence of Fire",{"waters":"Un'Goro Crater (Fire Plume Ridge)"}),("Heart of Fire",{"waters":"Un'Goro Crater (Fire Plume Ridge)"})]
sec("Crafting and elemental reagents", "reagent", [W+"Fishing_items#Crafting_ingredients", W+"Fishing_items#Elemental_goods"], reag)
gear = [("The 1 Ring",{"waters":"Low-level waters, very rare"}),("Broken Wine Bottle",{"waters":"The Barrens (Sludge Fen)"}),("Steelscale Crushfish",{"waters":"Wetlands, Hillsbrad Foothills coast"}),("Rockhide Strongfish",{"waters":"Speckled Tastyfish pools (Stranglethorn)"}),("Darkwood Fishing Pole",{"waters":"Very rare, fishing only"})]
sec("Weapons, armor and equipment", "gear", [W+"Fishing_items#Weapons_and_armor", W+"Fishing_items#Fishing_equipment"], gear)
junk = ["Old Skull","Old Teamster's Skull","Old Wagonwheel","Acidic Slime","Rusted Engineering Parts","Seaweed"]
sec("Junk (vendor-quality catches; post-3.1 junk ids excluded)", "junk", [W+"Fishing_items#Vendor_Quality_Items"], [(n,{"quality":0,"junk":True}) for n in junk])

def lua_str(s): return '"' + s.replace('\\','\\\\').replace('"','\\"') + '"'
out = []
out.append("-- Static catalog of fishing catches for Dark Matter Show all (generated by tools/catalog/gen_catalog.py).")
out.append("-- Facts (item id, name, quality, typical waters, skill hint) were researched on public pages and entered here;")
out.append("-- 0.2.11: every id cross-checked on https://nether.wowhead.com/classic/tooltip/item/<id> (tools/catalog/wowhead_classic.json);")
out.append("--   name spelling, quality and icon come from that check; ids whose name differs fail the generator.")
out.append("-- nothing is copied from another addon's loot tables.")
out.append("--")
out.append("-- Item ids: each item's own page on warcraft.wiki.gg (its Wowhead item link), e.g. " + W + "Raw_Longjaw_Mud_Snapper")
out.append("-- Waters / skill: " + W + "Fishing_locations (modern table; skill = lowest '100% catch' zone skill listed, a hint only).")
out.append("-- Forever: Wowhead Forever (https://www.wowhead.com/forever) refused automated fetches (HTTP 403) and no public Forever")
out.append("--   fishing loot table or Forever patch note on fishing could be found (" + W + "World_of_Warcraft:_Forever).")
out.append("--   So every entry is classicOnly = true (shown only when C_Item.DoesItemExistByID confirms it on this client),")
out.append("--   except items confirmed on a live Forever 1.60.1 client (caught in Dark Matter 0.2.5, 2026-10-19): forever = true.")
out.append("-- Excluded as added after Classic per their wiki patch notes: Old Crafty / Old Ironjaw (2.3.0), Stendel's Bane (4.1.0),")
out.append("--   Driftwood and the other 3.1.0 junk, Steam Pump Debris (2.0.3), Broken Engine Part (2.3.0), Water Snail (10.0.2),")
out.append("--   Electropeller / Gaffer Jack (4.0.3 quests). 0.2.6 entries with no fishing source (Oozing Bag, Ruined Pelt, Damp Diary")
out.append("--   Page, Schematic: Field Repair Bot 74A, Dark Iron Ore, Essence of Undeath) were removed. 13888 is Darkclaw Lobster")
out.append("--   (0.2.6 labelled it Darkshore Grouper, which is 12238).")
out.append("--")
out.append("-- Fields: itemId, name, cat, quality? (0 poor .. 5 legendary), junk?, waters?, skill?, icon?, forever?, classicOnly?")
out.append("local _, NS = ...")
out.append("")
out.append("NS.FishingCatchCatalog = {")
seen = set(); seen_names = set(); count = 0
for title, cat, sources, items in SECTIONS:
    out.append(f"  -- {title}")
    for s in sources: out.append(f"  -- source: {s}")
    for name, o in items:
        i = EXTRA_IDS.get(name) or iid(name)
        assert i not in seen, (name, i); seen.add(i); count += 1
        wh = WH.get(str(i)) or {}
        # id must resolve to the same item on the second source; take its exact spelling, quality and icon
        assert wh.get('name') and wh['name'].lower() == name.lower(), ('id/name mismatch', i, name, wh.get('name'))
        name = wh['name']
        assert name.lower() not in seen_names, ('duplicate name', name); seen_names.add(name.lower())
        o = dict(o); o['quality'] = int(wh['quality'])
        w, sk = waters_of(name)
        waters = o.get("waters", w)
        f = [f"itemId = {i}", f"name = {lua_str(name)}", f'cat = "{cat}"']
        if "quality" in o: f.append(f"quality = {o['quality']}")
        if o.get("junk"): f.append("junk = true")
        if waters: f.append(f"waters = {lua_str(waters)}")
        if cat in ("fish","special") and sk: f.append(f"skill = {sk}")
        if wh.get('icon'): f.append('icon = "Interface\\\\Icons\\\\' + wh['icon'] + '"')
        f.append("forever = true" if i in FOREVER_CONFIRMED else "classicOnly = true")
        out.append("  { " + ", ".join(f) + " },")
out.append("}")
out.append("")
out.append("""local byId, byName
local function Index()
  if byId then return end
  byId, byName = {}, {}
  for _, e in ipairs(NS.FishingCatchCatalog) do
    byId[e.itemId] = e
    byName[e.name] = e
  end
end

function NS.FishingCatalogById()
  Index()
  return byId
end

function NS.FishingCatalogByName()
  Index()
  return byName
end""")
open(OUT,'w').write("\n".join(out) + "\n")
print("entries:", count, " forever-confirmed:", len(FOREVER_CONFIRMED & seen))
from collections import Counter
print(Counter(c for _,c,_,its in SECTIONS for _ in its))
