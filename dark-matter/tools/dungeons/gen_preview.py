#!/usr/bin/env python3
"""Emit the Adventure Guide seed as compact JS for the addon previewer (same data as Data_Dungeons.lua).
Writes between /*AG-SEED-BEGIN*/ and /*AG-SEED-END*/ in the previewer's darkmatter.js."""
import json, re, sys
from pathlib import Path
from gen_dungeons import build
SLOT = {1: 'head', 2: 'neck', 3: 'shoulder', 5: 'chest', 20: 'chest', 4: 'chest', 6: 'waist', 7: 'legs', 8: 'feet', 9: 'wrist',
        10: 'hands', 11: 'finger', 12: 'trinket', 14: 'shield', 16: 'back', 23: 'orb', 15: 'bow', 26: 'wand', 25: 'dagger'}
WEAP = {0: 'axe', 1: 'axe', 2: 'bow', 3: 'bow', 4: 'mace', 5: 'mace', 6: 'staff', 7: 'sword', 8: 'sword', 10: 'staff', 13: 'hands',
        15: 'dagger', 16: 'dagger', 18: 'bow', 19: 'wand'}
SLOTN = {1: 'Head', 2: 'Neck', 3: 'Shoulder', 4: 'Shirt', 5: 'Chest', 20: 'Chest', 6: 'Waist', 7: 'Legs', 8: 'Feet', 9: 'Wrist', 10: 'Hands',
         11: 'Finger', 12: 'Trinket', 13: 'One-Hand', 14: 'Off Hand', 15: 'Ranged', 16: 'Back', 17: 'Two-Hand', 21: 'Main Hand',
         22: 'Off Hand', 23: 'Held In Off-hand', 25: 'Thrown', 26: 'Ranged'}
def glyph(it):
    if it.get('classs') == 2: return WEAP.get(it.get('subclass'), 'sword')
    return SLOT.get(it.get('slot'), 'trinket')
seed, picked = build(True)
out = []
for d in picked:
    out.append({'n': d['name'], 's': d['short'], 'z': d['zone'], 'lv': d['levels'], 'w': d['wiki'],
                'b': [{'n': b['name'], 'npc': b['npc'], 'r': 1 if b['rare'] else 0,
                       'd': [{'id': it['id'], 'n': it['name'], 'q': it['fq'], 'p': it['pct'], 'g': glyph(it), 'sl': SLOTN.get(it.get('slot'), '')}
                             for it in b['drops']]} for b in d['bosses']]})
js = 'var AG_SEED=' + json.dumps(out, separators=(',', ':')) + ';'
p = Path(sys.argv[1]); s = p.read_text()
new = re.sub(r'/\*AG-SEED-BEGIN\*/.*?/\*AG-SEED-END\*/', lambda m: '/*AG-SEED-BEGIN*/' + js + '/*AG-SEED-END*/', s, flags=re.S)
assert new != s or js in s, 'markers missing'
p.write_text(new); print('AG_SEED', len(js), 'bytes')
