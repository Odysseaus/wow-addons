# Builds Valhalla/Data/Forever/Recipes.lua from the client's DB2 tables (wago.tools CSV, build 1.60.1.70888).
# Usage: put the CSVs (SkillLine, SkillLineAbility, SpellEffect, Item, ItemSparse) from
#   https://wago.tools/db2/<Table>/csv?build=<version> (robots-allowed CSV route) in the current directory, then
#   python3 build_bundle.py <date> <path to Valhalla/Data/Forever/Recipes.lua>
import csv, sys
csv.field_size_limit(10**9)
PROFS = [(171,"Alchemy"),(164,"Blacksmithing"),(333,"Enchanting"),(202,"Engineering"),(182,"Herbalism"),(165,"Leatherworking"),
         (186,"Mining"),(393,"Skinning"),(197,"Tailoring"),(185,"Cooking"),(129,"First Aid"),(356,"Fishing")]
SECONDARY = {185,129,356}
CHILD = {}
for r in csv.DictReader(open('SkillLine.csv')):
    if r['ParentSkillLineID'] in [str(p) for p,_ in PROFS]: CHILD[int(r['ID'])] = int(r['ParentSkillLineID'])
ids = {p:set() for p,_ in PROFS}
for r in csv.DictReader(open('SkillLineAbility.csv')):
    sk = int(r['SkillLine']); sk = CHILD.get(sk, sk)
    if sk in ids and r['TradeSkillCategoryID'] != '0': ids[sk].add(int(r['Spell']))
outputs = {}
allspells = set().union(*ids.values())
for r in csv.DictReader(open('SpellEffect.csv')):
    s = int(r['SpellID'])
    if s in allspells and r['Effect'] == '24' and r['EffectItemType'] not in ('', '0'):
        outputs.setdefault(s, set()).add(int(r['EffectItemType']))
names = {}
for r in csv.DictReader(open('ItemSparse.csv')): names[int(r['ID'])] = r['Display_lang']
bad = ('test', 'deprecated', '[ph]', 'unused', 'dnt', 'qa ', 'monster -', 'old ')
sub = {}
for r in csv.DictReader(open('Item.csv')):
    if r['ClassID'] == '7':
        i = int(r['ID']); n = names.get(i, '')
        if not n or any(b in n.lower() for b in bad): continue
        sub.setdefault(int(r['SubclassID']), []).append(i)
def outs(p): return set().union(*[outputs.get(s, set()) for s in ids[p]]) if ids[p] else set()
GATHER = [(182, "Herbs", [9], None), (186, "Ores, stone and gems", [7], 186), (393, "Hides and leather", [6], 165), (356, "Raw meat and fish", [8], 185)]
gather = {}
ALLOUT = set().union(*[outs(p) for p, _ in PROFS])
for p, label, subs, minus in GATHER:
    items = sorted(set(i for s in subs for i in sub.get(s, [])) - ALLOUT)
    gather[p] = (label, items)
L = []
L.append('-- Valhalla: every recipe and gathered item ID of the professions in this client, from the client\'s own data tables')
L.append('-- (DB2 SkillLine, SkillLineAbility, SpellEffect, Item, ItemSparse of WoW Forever 1.60.1.70888, the CSV exports of')
L.append('-- wago.tools, read %s). IDs only: each recipe\'s output, quantity and reagents always come from the game' % sys.argv[1])
L.append('-- (C_TradeSkillUI.GetRecipeSchematic); an ID the game doesn\'t answer for is counted "unknown to this client".')
L.append('-- A profession\'s window, when opened, replaces its list here (the game\'s own list wins).')
L.append('-- Format: ns.Recipes.professions[<skill line ID>] = { name = "<English name>", secondary = true|nil, ids = "<recipe spell ID>,..." }')
L.append('--         ns.Recipes.gather[<skill line ID>] = { label = "<what>", ids = "<item ID>,..." } (Herbalism, Mining, Skinning, Fishing:')
L.append('--         Trade Goods of the matching subclass, less every item a recipe makes: bars, leathers, cooked food).')
L.append('-- Rebuilt by valhalla/tools/recipes/build_bundle.py from the CSVs (not shipped with the add-on).')
L.append('local _, ns = ...')
L.append('ns.Recipes = {')
L.append('\tsource = "client DB2 1.60.1.70888 (wago.tools CSV, %s)",' % sys.argv[1])
L.append('\tbuild = 70888,')
L.append('\tprofessions = {')
total = 0
for p, n in PROFS:
    s = sorted(ids[p]); total += len(s)
    L.append('\t\t[%d] = { name = "%s",%s ids = "%s" },' % (p, n, ' secondary = true,' if p in SECONDARY else '', ','.join(map(str, s))))
L.append('\t},')
L.append('\tgather = {')
for p, (label, items) in gather.items():
    L.append('\t\t[%d] = { label = "%s", ids = "%s" },' % (p, label, ','.join(map(str, items))))
L.append('\t},')
L.append('}')
open(sys.argv[2], 'w').write('\n'.join(L) + '\n')
print('recipes', total, {n: len(ids[p]) for p, n in PROFS})
print('gather', {p: len(v[1]) for p, v in gather.items()})
for p,(label,items) in gather.items(): print(label, [names.get(i) for i in items][:80])
