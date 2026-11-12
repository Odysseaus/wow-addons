#!/usr/bin/env python3
# Box test for build_chains.py: synthetic pages in Wowhead's shape (page source: the Quick Facts markup the page
# prints, its Series table; a saved DOM: the printed list), a tiny QuestieDB, then the data file loaded in Lua
# and indexed by Objectives/QuestChains.lua's QC.Build. Run: python3 tools/questchains/test_build.py
import html, json, os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
LUA = os.environ.get('LUA', '/workspace/valhalla/bin/lua')
T = tempfile.mkdtemp(prefix='qc-')
os.makedirs(T + '/pages'); os.makedirs(T + '/questiedb')

def series(rows, me):
    out = []
    for n, row in enumerate(rows, 1):
        divs = ''.join('<div><b>%s</b></div>' % html.escape(nm) if q == me else '<div><a href="/forever/quest=%d/x">%s</a></div>' % (q, html.escape(nm)) for q, nm in row)
        out.append('<tr><th>%d.</th><td>%s</td></tr>' % (n, divs))
    return '<table class="series">%s</table>' % ''.join(out)

def page(q, name, rows, side='Alliance', cls=None, extra='', dom=False):
    facts = '[li]Level: 10[\\/li][li]Side: [span class=icon-alliance]%s[\\/span][\\/li]' % side
    if cls: facts += '[li]Class: [class=%d][\\/li]' % cls
    facts += extra
    qf = ('<div id="infobox-contents-0"><ul><li>Side: %s</li></ul></div>' % side) if dom else \
        '<div id="infobox-contents-0"></div><script>WH.markup.printHtml("[ul]%s[\\/ul]", "infobox-contents-0", {});</script>' % facts
    return ('<html><head><title>%s - Quest - Forever</title></head><body><h1 class="heading-size-1">%s</h1>'
            '<table class="infobox"><tr><td>%s</td><td>%s</td></tr></table>'
            '<a href="/forever/quest=%d">x</a></body></html>') % (name, name, qf, series(rows, q) if rows else '', q)

S1 = [[(10, 'One')], [(11, 'Two')], [(12, 'Three'), (13, 'Three B')]]
S2 = [[(20, 'Four & Co')], [(21, 'Five')]]
D = [[(30, 'Moon')], [(31, 'Lake')]]
pages = {10: page(10, 'One', S1), 20: page(20, 'Four & Co', S2, extra='[li]Breadcrumb quest[\\/li]'),
         30: page(30, 'Moon', D, cls=11), 31: page(31, 'Lake', D, cls=11, dom=True),
         40: page(40, 'Alone', None), 50: '<html>Please verify you are human</html>'}
for q, h in pages.items(): open(T + '/pages/quest-%d.html' % q, 'w').write(h)
open(T + '/pages/index.tsv', 'w').write('10\thttps://www.wowhead.com/forever/quest=10\t2026-11-12T09:00:00-06:00\t200\n')
qdb = {10: {'name': 'One', 'nextQuestInChain': 11}, 11: {'nextQuestInChain': 12}, 12: {'nextQuestInChain': 20},
       20: {'nextQuestInChain': 21, 'breadcrumbForQuestId': 21}, 21: {}, 30: {'nextQuestInChain': 31}, 31: {}, 40: {'nextQuestInChain': 41}, 41: {}}
# typed in by hand (manual/quest-<id>.tsv): a header, an 'or' row (same pos), opt, side/class flags; Five links on
# to it in QuestieDB (joined to the One..Five chain); a file with an unread id ('?') is skipped and listed
os.makedirs(T + '/manual')
open(T + '/manual/quest-60.tsv', 'w').write(
    '# read from the Series box on screen\n'
    'pos\tid\tname\tflags\turl\tfetched\n'
    '1\t60\tSix\tside=A\thttps://www.wowhead.com/forever/quest=60\t2026-11-11T20:15:00-06:00\n'
    '2\t61\tSeven\topt\t\t\n'
    '2\t62\tSeven B\t\t\t\n'
    '3\t63\tEight "the Last"\tclass=DRUID\t\t\n')
open(T + '/manual/quest-70.tsv', 'w').write(
    '1\t70\tSeventy\t\thttps://www.wowhead.com/forever/quest=70\t2026-11-11T20:20:00-06:00\n2\t?\tSeventy-one\t\t\t\n')
open(T + '/manual/quest-80.tsv', 'w').write('pos\tid\tname\tflags\turl\tfetched\nnone\t\t\t\thttps://www.wowhead.com/forever/quest=80\t2026-11-11T20:21:00-06:00\n')
qdb[21] = {'nextQuestInChain': 60}; qdb[60] = {'nextQuestInChain': 61}; qdb[61] = {'nextQuestInChain': 63}; qdb[63] = {}
qdb[70] = {'nextQuestInChain': 71}; qdb[71] = {}
open(T + '/current-log.tsv', 'w').write('# test\nid\ttitle\n11\tTwo\n61\tSeven\n31\tLake\n40\tAlone\n99\tNot a chain\n')
json.dump(qdb, open(T + '/questiedb/quests.json', 'w'))
env = dict(os.environ, CHAIN_DATA=T)
B = [sys.executable, os.path.join(HERE, 'build_chains.py')]
print(subprocess.run(B + ['urls'], env=env, capture_output=True, text=True).stdout.strip())
print(subprocess.run(B + ['check'], env=env, capture_output=True, text=True).stdout.strip())
print(subprocess.run(B + ['next'], env=env, capture_output=True, text=True).stdout.strip())
r = subprocess.run(B + ['current'], env=env, capture_output=True, text=True); print(r.stdout.strip())
cur = open(T + '/urls-current.txt').read().split()
good_cur = cur == ['https://www.wowhead.com/forever/quest=11', 'https://www.wowhead.com/forever/quest=31', 'https://www.wowhead.com/forever/quest=40']
print(('PASS' if good_cur else 'FAIL') + '  current: one URL per chain of a log quest (11 and 61 share one; 99 none)', cur)
r = subprocess.run(B + ['check'], env=env, capture_output=True, text=True); print(r.stdout.strip())
good_chk = 'quest-70.tsv' in r.stdout and 'no quest id' in r.stdout
print(('PASS' if good_chk else 'FAIL') + '  check: the manual file with an unread id listed')
out = T + '/QuestChains.lua'
# joins off (the default until approved): each Wowhead series its own chain; the page with none recorded
out0 = T + '/QuestChains-nojoin.lua'
r = subprocess.run(B + ['build', out0], env=env, capture_output=True, text=True); print(r.stdout.strip(), r.stderr.strip())
t0 = open(out0).read()
n0 = sum(1 for l in t0.splitlines() if l.startswith('\t\t{ '))
good_nojoin = n0 == 4 and not any('breaks' in l for l in t0.splitlines() if l.startswith('\t\t{ ')) and 'noSeries = { 40, 80 }' in t0 and 'Joins: off' in t0
print(('PASS' if good_nojoin else 'FAIL') + '  joins off by default: 4 chains, no lines; noSeries lists 40 and 80', n0)
r = subprocess.run(B + ['build', out, '--join'], env=env, capture_output=True, text=True); print(r.stdout.strip(), r.stderr.strip())
lua = r'''
local ns = { L = setmetatable({}, { __index = function(_, k) return k end }), modules = {} }
function ns:NewModule(k, s) s = s or {} s.defaults = s.defaults or {} self.modules[k] = s return s end
CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
assert(loadfile("@OUT@"))("V", ns)
assert(loadfile("@QC@"))("V", ns)
local QC = ns.modules.chains.QC
local fails = 0
local function ok(c, n) print((c and "PASS  " or "FAIL  ") .. n) if not c then fails = fails + 1 end end
local d = ns.QuestChainData
ok(d.meta.chains == 2, "2 chains (One..Five + the typed Six..Eight joined; Moon..Lake); the '?' file skipped")
local n = QC.Build(d, "Alliance", "WARRIOR")
ok(n == 1, "a warrior: 1 chain (the druid one filtered)")
local e = QC.Of(21)
ok(e and e.step == 5 and #e.chain.steps == 7, "series joined end to end: Five is step 5; Eight (a druid's) dropped for a warrior", e and #e.chain.steps)
ok(e.chain.breaks[3] == true and e.chain.breaks[5] == true, "the lines after step 3 and 5 (where the series meet)")
local s6 = QC.Of(61)
ok(s6 and s6.step == 7 and e.chain.steps[7].opt and e.chain.steps[7].alt[1].id == 62, "typed: Seven optional, Seven B its 'or'")
ok(QC.Of(63) == nil, "typed class=DRUID: not a warrior's")
ok(QC.Of(70) == nil and QC.Of(71) == nil, "the file with an unread id: no chain")
ok(QC.Of(13) and QC.Of(13).alt and e.chain.steps[3].alt[1].name == "Three B", "a Series row with two quests: 'or'")
ok(e.chain.steps[4].opt == true and e.chain.steps[4].name == "Four & Co", "Wowhead says breadcrumb: optional; names unescaped")
ok(QC.Of(40) == nil, "a page with no Series box: no chain")
QC.Build(d, "Alliance", "DRUID")
ok(QC.Of(31) and QC.Of(31).step == 2, "a druid: the druid chain (class from the page, a saved DOM page too)")
ok(QC.Of(63) and QC.Of(63).step == 8 and QC.Of(63).chain.steps[8].name == 'Eight "the Last"', "a druid: Eight is step 8; quotes kept")
local srcs = table.concat(QC.Of(63).chain.src, " ")
ok(srcs:find("60@2026%-11%-11T20:15:00%-06:00", 1) ~= nil, "src: the typed page and its fetch time", srcs)
ok(d.chains[1].src[1]:find("^10@2026%-11%-12T09:00:00") ~= nil, "src: the page and its fetch time (index.tsv)")
os.exit(fails == 0 and 0 or 1)
'''.replace('@OUT@', out).replace('@QC@', os.path.join(REPO, 'Valhalla', 'Objectives', 'QuestChains.lua'))
open(T + '/t.lua', 'w').write(lua)
r = subprocess.run([LUA, T + '/t.lua'], capture_output=True, text=True)
print(r.stdout + r.stderr)
rep = open(T + '/report/coverage.txt').read()
ok = 'not a quest page: 50' in rep
print(('PASS' if ok else 'FAIL') + '  report: the captcha page listed as not a quest page')
sys.exit(0 if r.returncode == 0 and ok and good_cur and good_chk and good_nojoin else 1)
