#!/usr/bin/env python3
# Box test for raw_to_manual.py (batch lines read in the box browser -> manual-format series) and build_chains.py
# reading them (no saved pages at all). Run: python3 tools/questchains/test_raw.py
import json, os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
LUA = os.environ.get('LUA', '/workspace/valhalla/bin/lua')
T = tempfile.mkdtemp(prefix='qcraw-')
for d in ('batches', 'manual', 'questiedb'): os.makedirs(os.path.join(T, d))
json.dump({}, open(T + '/questiedb/quests.json', 'w'))
W = lambda name, text: open(os.path.join(T, name), 'w', encoding='utf-8').write(text)
# a hand-typed file (read first): 500 -> 504
W('manual/quest-500.tsv', 'pos\tid\tname\tflags\turl\tfetched\n1\t500\tCrushridge Bounty\tside=A\thttps://www.wowhead.com/forever/quest=500\t2026-11-11T20:02:18-06:00\n2\t504\tCrushridge Warmongers\tside=A\t\t\n')
W('batches/batch1-raw.txt', '\n'.join([
    '# Batch 1, read Nov 11-12 2026 23:50-00:10 CT from https://www.wowhead.com/forever/quest=<id>; format ...',
    '10 | 23:50 | A | 1 10 One; 1 11 One B(alt); 2 12 Two',              # an 'or' row
    '12 | 23:55 | A | (same series as 10)',
    '20 | 00:01 | H, class Druid | 1 20; 2 21; 3 22 (all Moon)',            # one name for all, after midnight
    '21 | 00:02 | H, class Druid | 1 20 Moon; 2 21 Moon; 3 22 Moon',        # the same series again
    '30 | 00:03 | B | 1 30 Start; 2 31; 3 32 (2-3 Middle)',               # a range of names; both factions
    '40 | 00:04 | A | no series',
    '50 | load failed',
    '504 | 00:05 | A | 1 500 Crushridge Bounty; 2 504 Crushridge Warmongers',   # the hand file's series again
    '60 | 00:06 | A | 1 60 Six; 2 61 Seven',
    '61 | 00:07 | A | 1 61 Seven; 2 60 Six',                                # CONFLICT: another order
    '70 | 00:08 | A | 1 71 Seventy-one; 2 72 Seventy-two',                  # INCOMPLETE: 70 not in it, nothing full: held
    '81 | 00:09 | A | 1 80 Eighty; 2 82 Eighty-two',                        # INCOMPLETE, covered by 80 below
    '80 | 00:10 | A | 1 80 Eighty; 1 81 Eighty-one; 2 82 Eighty-two',
    '90 | 00:10 | A, Warlock/Druid | 1 90 Ninety; 2 91 Ninety-one',
    '']))
W('batches/batch8-raw.txt', '# Batch 8, read Nov 12 2026 ~02:27-03:08 CT, ... NOTE: every line 02:27.\n'
  '100 | 02:27 | A | 1 100 Hundred; 2 101 Hundred-one\n')
W('batches/retry1-raw.txt', '# Retry pass 1, read Nov 12 2026 04:36-05:14 CT\n50 | 04:36 | A | 1 50 Fifty; 2 51 Fifty-one\n')
env = dict(os.environ, CHAIN_DATA=T)
r = subprocess.run([sys.executable, os.path.join(HERE, 'raw_to_manual.py')], env=env, capture_output=True, text=True)
print(r.stdout.strip(), r.stderr.strip())
fails = 0
def ok(c, name, extra=''):
    global fails
    print(('PASS  ' if c else 'FAIL  ') + name + (('  ' + str(extra)) if not c and extra else ''))
    if not c: fails += 1
rep = open(T + '/report/raw-conflicts.txt').read()
out = os.listdir(T + '/manual-wowhead')
ok('conflicts 1' in r.stdout and 'page 61 (batch1-raw.txt:11' in rep, 'conflict: the same quests in another order: listed, the first kept', r.stdout)
ok('held back 1' in r.stdout and 'page 70 (' in rep, 'incomplete with no full reading: held back, listed')
ok('incomplete covered 1' in r.stdout and 'page 81 (' in rep, 'incomplete covered by a full reading')
ok('quest-504.tsv' not in out and 'quest-21.tsv' not in out, 'the same series on another page (and the hand file): not written twice')
ok('quest-40.tsv' in out and 'none\t' in open(T + '/manual-wowhead/quest-40.tsv').read(), 'no series: recorded')
ok('quest-50.tsv' in out, 'a retry replaces a failed load')
t20 = open(T + '/manual-wowhead/quest-20.tsv').read()
ok('2026-11-12T00:01:00-06:00' in t20 and 'class=DRUID' in t20 and 'side=H' in t20 and '\tMoon\t' in t20, "after midnight: the second day; (all <name>); class", t20)
t30 = open(T + '/manual-wowhead/quest-30.tsv').read()
ok('\t31\tMiddle\t' in t30 and 'side=' not in t30, '(2-3 <name>); both factions: no side', t30)
ok('~2026-11-12T02:27:00-06:00/2026-11-12T03:08:00-06:00' in open(T + '/manual-wowhead/quest-100.tsv').read(), 'batch 8: the range, not the line times')
ok('class=WARLOCK+DRUID' in open(T + '/manual-wowhead/quest-90.tsv').read(), 'Warlock/Druid')
pr = open(T + '/manual-wowhead/pages-read.tsv').read()
ok('\n12\tsame series\t' in pr and '\n50\tseries\t' in pr, 'pages read: same series; the retry')
# the build (no chain-data/pages at all) and the data in the loader
lua_out = T + '/QuestChains.lua'
B = [sys.executable, os.path.join(HERE, 'build_chains.py')]
r = subprocess.run(B + ['build', lua_out], env=env, capture_output=True, text=True); print(r.stdout.strip(), r.stderr.strip())
ok(' 9 chains' in r.stdout, 'build without saved pages: the typed series (500, 10, 20, 30, 50, 60, 80, 90, 100)', r.stdout)
lua = r'''
local ns = { L = setmetatable({}, { __index = function(_, k) return k end }), modules = {} }
function ns:NewModule(k, s) s = s or {} s.defaults = s.defaults or {} self.modules[k] = s return s end
CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
assert(loadfile("@OUT@"))("V", ns)
assert(loadfile("@QC@"))("V", ns)
local QC = ns.modules.chains.QC
local d, f = ns.QuestChainData, 0
local function ok(c, n) print((c and "PASS  " or "FAIL  ") .. n) if not c then f = f + 1 end end
QC.Build(d, "Alliance", "WARRIOR")
ok(QC.Of(11) and QC.Of(11).alt and QC.Of(12).step == 2, "Alliance: 10 / or 11, then 12")
ok(QC.Of(31) and QC.Of(31).step == 2, "both factions: an Alliance player has it")
ok(QC.Of(20) == nil and QC.Of(90) == nil, "the Horde druid chain and the warlock/druid chain: not an Alliance warrior's")
ok(QC.Of(60) and QC.Of(60).step == 1, "the conflict: the first reading (60 then 61)")
ok(QC.Of(70) == nil and QC.Of(71) == nil, "held back: no chain")
ok(QC.Of(101) and QC.Of(101).chain.src[1]:find("^100@~2026", 1) ~= nil, "src keeps the range")
local n = 0 for _ in pairs(d.noSeries) do n = n + 1 end
ok(d.noSeries[1] == 40 and n == 1, "noSeries: 40")
QC.Build(d, "Alliance", "WARLOCK")
ok(QC.Of(91) and QC.Of(91).step == 2, "a warlock: the warlock/druid chain")
QC.Build(d, "Horde", "DRUID")
ok(QC.Of(22) and QC.Of(22).step == 3 and QC.Of(31), "a Horde druid: the druid chain and the both-factions one")
os.exit(f == 0 and 0 or 1)
'''.replace('@OUT@', lua_out).replace('@QC@', os.path.join(REPO, 'Valhalla', 'Objectives', 'QuestChains.lua'))
open(T + '/t.lua', 'w').write(lua)
r = subprocess.run([LUA, T + '/t.lua'], capture_output=True, text=True); print(r.stdout + r.stderr, end='')
fails += r.stdout.count('FAIL') + (0 if r.returncode == 0 or 'FAIL' in r.stdout else 1)
print('%d failed' % fails)
sys.exit(1 if fails else 0)
