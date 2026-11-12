-- Box tests for Valhalla/Objectives/QuestChains.lua (1.1.0, the quest log's Chain quest view). Lua 5.1.
-- Run: lua valhalla/tests/questchains/chain_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
dofile(here .. "../objectives/stubs.lua")
local Frame = getmetatable(UIParent)

-- what the window paints, recorded (the stubs' frames do nothing with these)
function Frame.SetTextColor(self, r, g, b) self._tc = { r, g, b } end
function Frame.SetColorTexture(self, r, g, b, a) self._color = { r, g, b, a } end
function Frame.SetText(self, s) self._text = s end
function Frame.SetAlpha(self, a) self._alpha = a end
function Frame.SetClampedToScreen(self, v) self._clamped = v end
function Frame.SetFrameStrata(self, s) self._strata = s end
function Frame.GetTop(self) return rawget(self, "_top") or 700 end
function Frame.RegisterForClicks(self, ...) self._clicks = { ... } end
function Frame.HookScript(self, k, fn)
  self._hooked = (rawget(self, "_hooked") or 0) + 1
  local h = rawget(self, "_hk") or {} self._hk = h
  h[k] = h[k] or {} table.insert(h[k], fn)
end
local function RunHooks(f, k) for _, fn in ipairs((rawget(f, "_hk") or {})[k] or {}) do fn(f) end end
Frame.protectedCalls = 0

-- the game: quests completed, the player, the menu, Escape's list
W.done = {}
C_QuestLog.IsQuestFlaggedCompleted = function(id) return W.done[id] == true end
C_QuestLog.GetLogIndexForQuestID = function(id) for i, x in ipairs(W.order) do if x == id and W.quests[id] then return i end end return nil end
W.faction, W.class = "Alliance", "WARRIOR"
function UnitFactionGroup() return W.faction, W.faction end
function UnitClass() return "x", W.class, 1 end
W.menus = {}
Menu = { ModifyMenu = function(tag, fn) W.menus[#W.menus + 1] = { tag = tag, fn = fn } end }
UISpecialFrames = {}
tinsert = table.insert
_G.WorldMapFrame = W.NewFrame("Frame")
WorldMapFrame._top = 760

-- Valhalla's namespace: the Look (two themes), the Look's window
local ns = { modules = {}, Media = { path = "Interface\\AddOns\\Valhalla\\Media\\" } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.printed = {}
function ns:Print(fmt, ...) ns.printed[#ns.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} if m.defaults.enabled == nil then m.defaults.enabled = true end self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
local THEMES = {
  profession = { key = "profession", text = { 1, 0.82, 0 }, selected = { 1, 1, 1 }, dim = { 0.72, 0.63, 0.45 }, highlight = { 1, 0.85, 0.45, 0.16 } },
  norse = { key = "norse", text = { 1, 0.82, 0 }, selected = { 1, 0.95, 0.72 }, dim = { 0.7, 0.62, 0.45 }, highlight = { 0.85, 0.6, 0.3, 0.18 } },
}
local look, listeners = "profession", {}
ns.Style = { Theme = function() return THEMES[look] end, OnLook = function(fn) listeners[#listeners + 1] = fn end }
local function SetLook(v) look = v for _, fn in ipairs(listeners) do fn(v) end end
local windows = {}
ns.Look = { Window = function(_, f, title, onClose) windows[#windows + 1] = { frame = f, title = title, onClose = onClose } return 21 end }

assert(loadfile(root .. "Data/Forever/QuestChains.lua"))("Valhalla", ns)
local shipped = ns.QuestChainData
-- the test chains (the shipped file's shape)
ns.QuestChainData = { meta = { source = "test", built = "now" }, noSeries = { 87 }, chains = {
  { { 40, "A Fishy Peril" }, { 35, "Further Concerns" }, { 37, "Find the Lost Guards", opt = true }, { 45, "Discover Rolf's Fate" },
    { 71, "Report to Thomas", alt = { { 72, "Report to Thomas (other)" } } }, { 39, "Deliver Thomas' Report" }, side = "A", breaks = { 3 }, src = { "40@x" } },
  { { 26, "A Lesson to Learn" }, { 29, "Trial of the Lake" }, side = "A", class = "DRUID" },
  { { 27, "A Lesson to Learn" }, { 28, "Trial of the Lake" }, side = "H", class = "DRUID" },
  { { 500, "Horde only", side = "H", alt = { { 501, "Alliance version", side = "A" } } }, { 502, "Both" } },
  { { 600, "Lonely" } },                                      -- (one step: no chain)
  { { 700, "Short" }, { 701, "Short 2" } },
  { { 700, "Short" }, { 701, "Short 2" }, { 702, "Short 3" } }, -- (700 in two: the longer chain wins)
} }
assert(loadfile(root .. "Objectives/QuestChains.lua"))("Valhalla", ns)
local mod = ns:GetModule("chains")
local QC = mod.QC

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end
local function same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
local function Start(db) mod.db = db or { enabled = true, chainView = false } mod.char = {} mod.enabled = true mod:OnEnable() end
local function Fire(event, a1)
  for _, f in ipairs(W.frames) do
    if rawget(f, "_events") and f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, a1) end
  end
end
local function ButtonOf(row)
  for _, f in ipairs(W.frames) do if f._parent == row and f._kind == "Button" and f.icon then return f end end
end
local function RowOf(id) for _, r in ipairs(W.log.rows) do if r.questID == id then return r end end end
local function Shown(f) return f and f._shown end

---------------------------------------------------------------------------
print("== 1. the data: this character's chains (faction, class), alternatives, lines, a quest in two chains")
ok(type(shipped) == "table" and type(shipped.chains) == "table" and type(shipped.meta) == "table", "the shipped data file loads (ns.QuestChainData: meta, chains)")
local n = QC.Build(ns.QuestChainData, "Alliance", "WARRIOR")
ok(n == 4, "Alliance warrior: 4 chains (Fishy Peril, 500/501, the two Short)", tostring(n))
ok(QC.Of(45) and QC.Of(45).step == 4, "Discover Rolf's Fate: step 4")
ok(QC.Of(26) == nil and QC.Of(27) == nil, "druid chains: not for a warrior")
local a = QC.Of(501)
ok(a and a.chain.steps[1].id == 501 and QC.Of(500) == nil, "a Horde step's Alliance alternative takes its place for Alliance")
ok(QC.Of(600) == nil, "a one-step chain is no chain")
ok(QC.Of(700) and #QC.Of(700).chain.steps == 3, "a quest in two chains: the longer one")
ok(QC.Of(72) and QC.Of(72).alt and QC.Of(72).step == 5, "an 'or' quest indexed at its step")
ok(QC.Of(40).chain.breaks[3] == true, "a joined series: a line after step 3")
QC.Build(ns.QuestChainData, "Alliance", "DRUID")
ok(QC.Of(26) and QC.Of(27) == nil, "Alliance druid: the Alliance druid chain only")
QC.Build(ns.QuestChainData, "Horde", "DRUID")
ok(QC.Of(27) and QC.Of(26) == nil and QC.Of(45) == nil and QC.Of(500) and QC.Of(501) == nil, "Horde druid: Horde chains only")
ok(QC.Build(nil, "Alliance", "MAGE") == 0, "no data: no chains, no error")

---------------------------------------------------------------------------
-- the shipped data file (Data/Forever/QuestChains.lua): loads, every chain well formed, builds for an Alliance druid
do
	local shipped = {}
	local f = assert(loadfile(root .. "Data/Forever/QuestChains.lua"))
	local saved = ns.QuestChainData
	f("Valhalla", ns)
	shipped, ns.QuestChainData = ns.QuestChainData, saved
	local good = type(shipped.chains) == "table" and type(shipped.meta) == "table" and shipped.meta.chains == #shipped.chains
	local ids = {}
	for _, c in ipairs(shipped.chains) do
		good = good and #c >= 2 and type(c.src) == "table" and #c.src >= 1
		for _, st in ipairs(c) do
			good = good and type(st[1]) == "number" and type(st[2]) == "string" and st[2] ~= ""
			ids[st[1]] = (ids[st[1]] or 0) + 1
		end
	end
	ok(good, "shipped data: meta.chains matches, every chain 2+ steps with a source, every step an id and a name")
	-- every chain is some character's (a faction and a class whose steps leave it 2 or more), and none is in two
	local some, seen, twice = {}, {}, 0
	for _, fac in ipairs({ "Alliance", "Horde" }) do
		for _, cls in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
			QC.Build(shipped, fac, cls)
			for _, c in ipairs(QC.chains) do some[c.src and c.src[1] or c] = true end
		end
	end
	local n = 0 for _ in pairs(some) do n = n + 1 end
	ok(n == #shipped.chains, "shipped data: every chain is some faction and class's", n .. " of " .. #shipped.chains)
	for _, c in ipairs(shipped.chains) do
		for _, st in ipairs(c) do
			for _, x in ipairs({ st, unpack(st.alt or {}) }) do if seen[x[1]] then twice = twice + 1 end seen[x[1]] = true end
		end
	end
	ok(twice == 0, "shipped data: no quest in two chains", twice)
	QC.Build(shipped, "Alliance", "DRUID")
	ok(QC.Of(1265) and QC.Of(26) and QC.Of(27) == nil, "shipped data, an Alliance druid: The Missing Diplomat, the druid's Lesson to Learn; not the Horde one")
	local inchain = {}
	for _, q in ipairs(shipped.noSeries or {}) do if QC.Of(q) then inchain[#inchain + 1] = q end end
	ok(#inchain == 0, "shipped noSeries (" .. #(shipped.noSeries or {}) .. " pages): none in a chain", table.concat(inchain, " "))
	QC.Build(ns.QuestChainData, "Alliance", "PALADIN")
end

print("== 2. the setting: off at first; the gear menu; Valhalla's menu")
W.Reset()
W.AddQuest(45, "Elwynn Forest", "Discover Rolf's Fate", 10)
W.AddQuest(87, "Elwynn Forest", "Goldtooth", 9)
W.AddQuest(47, "Elwynn Forest", "Gold Dust Exchange", 10)
W.AddQuest(71, "Elwynn Forest", "Report to Thomas", 10)
local SF = W.NewQuestLog()
W.faction, W.class = "Alliance", "WARRIOR"
Start()
ok(mod.db.chainView == false and mod.defaults.chainView == false, "Chain quest view off by default")
ok(#W.menus == 1 and W.menus[1].tag == "MENU_QUEST_MAP_FRAME_SETTINGS", "the quest log's gear menu gets an entry (Menu.ModifyMenu, its tag)")
local made = {}
local fakeRoot = { CreateCheckbox = function(_, label, get, set) made = { label = label, get = get, set = set } end }
W.menus[1].fn(nil, fakeRoot)
ok(made.label == "Chain quest view" and made.get() == false, "the entry: a checkbox 'Chain quest view', unticked")
QuestLogQuests_Update()
local allShown = true
for _, r in ipairs(W.log.rows) do if not r.Checkbox._shown then allShown = false end end
ok(allShown, "off: every Track tick shown (as 1.0.1)")
ok(ButtonOf(RowOf(45)) == nil or not Shown(ButtonOf(RowOf(45))), "off: no chain buttons")

---------------------------------------------------------------------------
print("== 3. on: every Track tick hidden, a chain button on chain quests only, in the tick's place")
made.set()
ok(mod.db.chainView == true, "the menu's checkbox turns it on")
QuestLogQuests_Update()
local anyShown = false
for _, r in ipairs(W.log.rows) do if r.Checkbox._shown then anyShown = true end end
ok(not anyShown, "on: the Track tick hidden on EVERY quest (chain or not)")
local b45 = ButtonOf(RowOf(45))
ok(Shown(b45) and b45.questID == 45, "Discover Rolf's Fate: a chain button")
ok(Shown(ButtonOf(RowOf(71))), "Report to Thomas: a chain button")
ok(not Shown(ButtonOf(RowOf(87))) and not Shown(ButtonOf(RowOf(47))), "Goldtooth, Gold Dust Exchange (no chain data here): no button")
local p = b45._points[1]
ok(p and p[1] == "CENTER" and p[2] == RowOf(45).Checkbox, "the button sits on the hidden tick (CENTER)")
ok(b45._w == QC.BUTTON and b45.icon._tex:find("ValhallaChain"), "18 px, Media/Textures/ValhallaChain")
ok(b45._scripts.OnEnter == nil, "no hover tooltip (owner: none)")

---------------------------------------------------------------------------
print("== 4. pooled rows: the buttons follow their quests; off gives every tick back")
W.order = { 87, 47, 71, 45 }
QuestLogQuests_Update() QuestLogQuests_Update()
ok(Shown(ButtonOf(RowOf(45))) and ButtonOf(RowOf(45)).questID == 45 and not Shown(ButtonOf(RowOf(87))), "re-ordered twice: buttons on 45 and 71 only")
W.AddQuest(40, "Elwynn Forest", "A Fishy Peril", 8)
QuestLogQuests_Update()
ok(not RowOf(40).Checkbox._shown and Shown(ButtonOf(RowOf(40))), "a row taken while on: no tick, a button")
QC.SetView(false)
local back = true
for _, r in ipairs(W.log.rows) do if not r.Checkbox._shown then back = false end end
ok(back, "turned off: every row's tick back at once (no log update needed)")
ok(not Shown(ButtonOf(RowOf(45))), "turned off: buttons hidden")
QuestLogQuests_Update()
back = true for _, r in ipairs(W.log.rows) do if not r.Checkbox._shown then back = false end end
ok(back, "off, after another update: ticks still shown")
W.Drop(40)
QC.SetView(true)
QuestLogQuests_Update()

---------------------------------------------------------------------------
print("== 5. the window: in order, done grey, the quest clicked highlighted, In your log, 'or', optional, the line")
W.done = { [40] = true, [35] = true }
b45 = ButtonOf(RowOf(45))
b45._scripts.OnClick(b45)
local win = QC.Window()
ok(win and Shown(win) and QC.ShownFor() == 45, "click: the window opens for Discover Rolf's Fate")
ok(#windows == 1 and windows[1].title == "Quest chain", "in the Look's window (Look:Window: Profession / Norse frame, title, close)")
local wp = win._points[#win._points]
ok(wp[1] == "TOPLEFT" and wp[2] == WorldMapFrame and wp[3] == "TOPRIGHT" and wp[4] == 8, "to the right of the map window", tostring(wp[1]) .. " " .. tostring(wp[3]))
ok(win._clamped == true and win._strata == "DIALOG", "kept on the screen, above the map")
local hasEsc = false for _, nm in ipairs(UISpecialFrames) do if nm == "ValhallaQuestChain" then hasEsc = true end end
ok(hasEsc, "Escape closes it")
local L = QC.shownLines
local names = {} for i, ln in ipairs(L) do names[i] = ln.name end
ok(#L == 7 and L[1].id == 40 and L[4].id == 45 and L[5].id == 71 and L[6].id == 72 and L[7].id == 39, "steps in order, the 'or' quest after its step", table.concat(names, " | "))
ok(win.head._text == "A Fishy Peril", "heading: the chain's first quest")
ok(win.sub._text == "Step 4 of 6    2 done", "the line under it: Step 4 of 6, 2 done", tostring(win.sub._text))
local th = THEMES.profession
local function Row(i) return ({ QC.Window() })[1] and (function() local c = 0 for _, f in ipairs(W.frames) do if f._parent == win and f.text and f.num then c = c + 1 if c == i then return f end end end end)() end
ok(same(Row(1).text._tc, QC.GREY) and Shown(Row(1).mark), "done: grey with a tick")
ok(same(Row(4).text._tc, th.selected) and Shown(Row(4).hl), "the quest clicked: the Look's selected colour, highlighted")
ok(Row(4).tag._text == "In your log", "In your log on the current one")
ok(same(Row(5).text._tc, th.text) and Row(5).tag._text == "In your log", "Report to Thomas (in the log): the Look's text colour, not grey")
ok(same(Row(7).text._tc, th.text) and not same(Row(7).text._tc, QC.GREY), "to do: not greyed")
ok(Row(7).tag._text == "" and Row(1).tag._text == "", "no In your log tag on quests not in the log (or done)")
ok(not Shown(Row(5).hl) and not Shown(Row(7).hl), "only the quest clicked is highlighted")
ok(Row(3).text._text:find("(optional)", 1, true) and same(Row(3).text._tc, th.dim), "optional: dimmed, '(optional)'")
ok(Row(6).text._text:find("^or ") and Row(6).text._points[1][4] > Row(5).text._points[1][4], "'or' quest indented, 'or ...'")
ok(Shown(Row(3).line) and not Shown(Row(2).line), "a thin line after a joined series (step 3)")
ok(not Shown(Row(4).mark), "not done: no tick")

---------------------------------------------------------------------------
print("== 6. live: a turn-in, the other path, the Look, closing")
W.done[45] = true
Fire("QUEST_TURNED_IN", 45)
ok(same(Row(4).text._tc, QC.GREY), "turned in while open: greyed")
W.done[72] = true
Fire("QUEST_LOG_UPDATE")
ok(Row(5).text._text:find("(other path)", 1, true) and same(Row(5).text._tc, th.dim), "the other 'or' quest done: '(other path)', dimmed")
SetLook("norse")
ok(same(Row(7).text._tc, THEMES.norse.text) and same(Row(5).text._tc, THEMES.norse.dim), "Norse: repainted at once (the Look's colours)")
SetLook("profession")
local b71 = ButtonOf(RowOf(71))
b71._scripts.OnClick(b71)
ok(QC.ShownFor() == 71 and Shown(win), "another chain button: the window switches to it")
b71._scripts.OnClick(b71)
ok(not Shown(win) and QC.ShownFor() == nil, "the same button again: closes")
b45._scripts.OnClick(b45)
QC.SetView(false)
ok(not Shown(win), "turning the view off closes the window")
QC.SetView(true)
-- (1.2.0) the map window (Valhalla's main window) closing closes the chain too
b45._scripts.OnClick(b45)
ok(Shown(win) and QC.ShownFor() == 45, "open again (quest 45)")
local mapHooks = #((rawget(WorldMapFrame, "_hk") or {}).OnHide or {})
WorldMapFrame:Hide() RunHooks(WorldMapFrame, "OnHide")
ok(mapHooks == 1 and not Shown(win) and QC.ShownFor() == nil, "the map window hides: the chain window closes with it (one hook, made once)", mapHooks)
WorldMapFrame:Show()
b45._scripts.OnClick(b45) b45._scripts.OnClick(b45)
ok(#WorldMapFrame._hk.OnHide == 1, "opening it again adds no second hook")

---------------------------------------------------------------------------
print("== 7. /valhalla chain coverage, combat, off")
W.done = {}
ns.printed = {}
mod:Slash("coverage")
ok(ns.printed[2] and ns.printed[2]:find("2 with chain data, 2 without"), "coverage: the log's quests with and without chain data", tostring(ns.printed[2]))
ok(ns.printed[3] and ns.printed[3]:find("Goldtooth (87)", 1, true), "coverage: names the ones without")
ok(ns.printed[3]:find("Goldtooth (87): no series on Wowhead", 1, true) ~= nil, "coverage: a quest whose page has no Series box says so", ns.printed[3])
W.combat = true
QC.SetView(false) QC.SetView(true) QuestLogQuests_Update()
ok(W.blockedSetters == 0, "in combat: only show / hide / place (no blocked setters)")
W.combat = false
mod:OnDisable()
back = true for _, r in ipairs(W.log.rows) do if not r.Checkbox._shown then back = false end end
ok(back and not Shown(ButtonOf(RowOf(45))), "module off: the ticks back, no buttons")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
