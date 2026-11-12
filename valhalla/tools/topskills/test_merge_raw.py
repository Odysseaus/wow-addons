# Box tests for merge_raw.py (Valhalla 1.2.1). Run: python3 test_merge_raw.py
import json, os, sys, tempfile, subprocess, io, contextlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import merge_raw
P = F = 0
def ok(c, name, detail=''):
    global P, F
    if c: P += 1; print('PASS  ' + name)
    else: F += 1; print('FAIL  ' + name + ('  -- ' + str(detail) if detail else ''))
tmp = tempfile.mkdtemp()
CRAFT = [171, 164, 333, 202, 165, 197, 185, 129]
profs = {str(p): {'name': 'P%d' % p, 'items': {}} for p in CRAFT + [182, 186, 393, 356]}
profs['171'] = {'name': 'Alchemy', 'items': {'3383': {'skill': None, 'spells': [3171]}, '2455': {'skill': None, 'spells': [2331]},
    '6371': {'skill': None, 'spells': [7837]}, '2459': {'skill': 60, 'spell': 2335, 'sources': []}, '3577': {'skill': None, 'spells': [11479]}}}
profs['164'] = {'name': 'Blacksmithing', 'items': {'2844': {'skill': None, 'spells': [2663]}}}
cov = [{'profession': profs[str(p)]['name'], 'skill_line': p, 'kind': 'craft' if p in CRAFT else 'harvest', 'known': 0, 'unknown': 0} for p in CRAFT + [182, 186, 393, 356]]
skills = os.path.join(tmp, 'skills.json')
json.dump({'professions': profs, 'coverage': cov}, open(skills, 'w'))
raw = os.path.join(tmp, 'batch1-raw.txt')
open(raw, 'w').write('''# read 2026-11-12T13:05-06:00/2026-11-12T13:40-06:00
3383 | 90 | created-by | 13:06
2455 | 25 | recipe=2553
6371 | ? | created-by
3577 | 120-130 | created-by
2459 | 75 | created-by
2844 | 15 | created-by
2844 | 20 | created-by
99999 | 10 | created-by
this is not a line
6371 | 0 | created-by
''')
out, lua = os.path.join(tmp, 'merged.json'), os.path.join(tmp, 'TopSkills.lua')
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rep, bad = merge_raw.main([raw, '--skills', skills, '--out', out, '--lua', lua])
text = buf.getvalue()
m = json.load(open(out))
A = m['professions']['171']['items']
ok(A['3383']['skill'] == 90 and A['3383']['sources'][0]['url'] == 'https://www.wowhead.com/forever/item=3383#created-by'
   and A['3383']['sources'][0]['date'].startswith('2026-11-12T13:06'), 'created-by: the value, the crafted page URL, the line\'s time')
ok(A['2455']['skill'] == 25 and A['2455']['sources'][0]['url'] == 'https://www.wowhead.com/forever/item=2553'
   and A['2455']['sources'][0]['date'] == '2026-11-12T13:05-06:00/2026-11-12T13:40-06:00', 'recipe=: the recipe page URL, the header\'s read time')
ok(A['6371']['skill'] is None and A['3577']['skill'] is None, 'unreadable values ("?", a range, 0) skipped: still unknown')
ok(len(bad) == 4 and 'not a raw line' in text, 'skipped lines reported (3 values, 1 malformed)', len(bad))
ok(A['2459']['skill'] == 60 and len(rep['conflicts']) == 1 and 'conflict 2459' in text, 'a known value is never replaced: reported as a conflict')
ok(m['professions']['164']['items']['2844']['skill'] == 15 and len(rep['dupes']) == 1 and 'read twice 2844: 15 kept, 20' in text, 'read twice differently: the first kept, reported')
ok(len(rep['noitem']) == 1 and 'not a craft item in the data: 99999' in text, 'an item not in the data: reported, nothing added')
c = {x['skill_line']: x for x in m['coverage']}
ok(c[171]['known'] == 3 and c[171]['unknown'] == 2 and c[164]['known'] == 1, 'coverage counts updated', c[171])
L = open(lua).read()
ok('[171] = { -- Alchemy: 3 known, 2 unknown' in L and '2455:25' in L and '3383:90' in L and 'unknown = "3577,6371"' in L, 'TopSkills.lua rebuilt: values in known, the rest unknown')
ok('Added (2026-11-12T13:05-06:00/2026-11-12T13:40-06:00): 3 craft values' in L and 'batch1-raw.txt' in L, 'TopSkills.lua names the added read and its file')
r = subprocess.run(['luac', '-p', lua], capture_output=True) if subprocess.run(['which', 'luac'], capture_output=True).returncode == 0 else None
ok(r is None or r.returncode == 0, 'TopSkills.lua compiles (luac)')
# untouched input
ok(json.load(open(skills))['professions']['171']['items']['3383']['skill'] is None, 'the input skills.json is not changed (a merged copy is written)')
print('\n%d passed, %d failed' % (P, F))
sys.exit(1 if F else 0)
