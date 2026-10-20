"""Dump Dark Matter's own achievement definitions (DarkMatter/Achievements.lua, criteria resolved against
Data_Dungeons.lua / Data_FishingCatches.lua) as the previewer's ACH_DM JSON, so the mockup lists the same set.
usage: python gen_preview.py <addon dir>   (needs lupa; tools/stubtest/venv has it)"""
import json, os, sys
from lupa.lua51 import LuaRuntime
d = sys.argv[1]
L = LuaRuntime(unpack_returned_tuples=True)
ns = L.eval('{}')
L.execute('date = os.date')
for f in ('Data_Dungeons.lua', 'Data_FishingCatches.lua', 'Achievements.lua'):
    L.eval('function(src, name, ns) return assert(loadstring(src, name))("DarkMatter", ns) end')(open(os.path.join(d, f)).read(), '@' + f, ns)
ACH = ns.Ach
assert len(list(ACH.Broken().values())) == 0, 'unresolved criteria'
out = []
for a in ACH.Defs().values():
    e = {'id': a.id, 'cat': a.cat, 'n': a.name, 'd': a.desc, 'p': a.points, 'k': a.kind, 'need': a.need}
    if a.key2: e['key'] = a.key2
    if a.money: e['money'] = True
    if a.crit:
        e['crit'] = [{'n': c.name, **({'npc': c.npc} if c.npc else {}), **({'item': c.item} if c.item else {})} for c in a.crit.values()]
    out.append(e)
cats = list(ACH.CATS.values())
print(json.dumps({'cats': cats, 'defs': out}, ensure_ascii=False, separators=(',', ':')))
