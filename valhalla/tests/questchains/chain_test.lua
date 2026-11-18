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
local made, boxes = {}, {}
local fakeRoot = { CreateCheckbox = function(_, label, get, set) boxes[#boxes + 1] = { label = label, get = get, set = set } end }
W.menus[1].fn(nil, fakeRoot)
made = boxes[1] or {}
ok(made.label == "Chain quest view" and made.get() == false, "the entry: a checkbox 'Chain quest view', unticked")
ok(#boxes == 2 and boxes[2].label == "Show Ready to Turn In section" and boxes[2].get() == false, "(1.2.11) then 'Show Ready to Turn In section', unticked (off by default)")
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

---------------------------------------------------------------------------
print("== 8. (1.2.11) the zones in alphabetical order; the Ready to Turn In section")
-- the game's log as QuestMapFrame.lua builds it: headers (questLogIndex, layoutIndex, topPadding), rows,
-- objective lines (anchored to their row, no layoutIndex), quest icons; Contents:Layout() counted
mod.enabled = true mod:OnEnable()
W.Reset()
W.collapsed = {}
local baseInfo = C_QuestLog.GetInfo
C_QuestLog.GetInfo = function(i)
  local e = baseInfo(i)
  if e then e = setmetatable({ questLogIndex = i, isCollapsed = e.isHeader and W.collapsed[e.title] or false }, { __index = e }) end
  return e
end
W.AddQuest(101, "Westfall", "The Defias Brotherhood", 14)
W.AddQuest(102, "Westfall", "Patrolling Westfall", 12, true)
W.AddQuest(201, "Elwynn Forest", "A Fishy Peril", 8, true)
W.AddQuest(45, "Elwynn Forest", "Discover Rolf's Fate", 10, true)
W.AddQuest(301, "Darkshore", "Buzzbox 827", 12)
W.AddQuest(401, "Redridge Mountains", "Murloc Poachers", 18, true)
local SF8 = W.NewQuestLog()
local contents = SF8.Contents
contents.layouts = 0
function contents:Layout() self.layouts = self.layouts + 1 end
local objPool = { active = {} }
function objPool:EnumerateActive() return next, self.active end
SF8.objectiveFramePool = objPool
W.blizzardCalls = {}
local gameUpdate = QuestLogQuests_Update
_G.QuestLogQuests_Update = function()
  objPool.active = {}
  local li = 3   -- (a separator / story header before it, as the game's)
  local idx = 0
  local last
  local seen, collapsedNow = {}, false
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local e = C_QuestLog.GetInfo(i)
    if e.isHeader then last, collapsedNow = e, e.isCollapsed end
  end
  gameUpdate()
  -- the game's indices: in log order, headers and the shown rows; a collapsed zone shows its header only
  local headersByTitle = {}
  for _, h in ipairs(W.log.headers) do headersByTitle[h._title] = h end
  local prevKind
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local e = C_QuestLog.GetInfo(i)
    if e.isHeader then
      local h = headersByTitle[e.title]
      h.questLogIndex, h.layoutIndex = i, li li = li + 1
      h.ButtonText = rawget(h, "ButtonText") or W.NewFrame("FontString") h.ButtonText._text = e.title
      h.topPadding = prevKind == nil and 8 or prevKind == "Q" and 4 or 6
      prevKind = "H"
      collapsedNow = e.isCollapsed
    else
      local row = RowOf(e.questID)
      if collapsedNow then row:Hide() rawset(row, "layoutIndex", nil)
      else
        row.questLogIndex, row.layoutIndex = i, li li = li + 1
        row.topPadding = prevKind == "H" and 2 or -3
        prevKind = "Q"
        local o = W.NewFrame("Frame") o.questID = e.questID objPool.active[o] = true
      end
    end
  end
  for _, r in ipairs(W.log.rows) do if not rawget(r, "layoutIndex") then r:Hide() end end
end
hooksecurefunc("QuestLogQuests_Update", QC.OnUpdate)   -- (the module's hook, as on the game's function: this log was made after it hooked)
local log8 = _G.QuestLogQuests_Update   -- (1.2.22's tests lay the same log out again)
local function Order()
  local t = {}
  for _, f in pairs(W.frames) do end
  local all = {}
  for h in SF8.headerFramePool:EnumerateActive() do if h:IsShown() then all[#all + 1] = { li = h.layoutIndex, s = "H:" .. h._title } end end
  for r in SF8.titleFramePool:EnumerateActive() do if r:IsShown() and rawget(r, "layoutIndex") then all[#all + 1] = { li = r.layoutIndex, s = "Q:" .. r.questID } end end
  local O = QC.ours
  if O.header and O.header:IsShown() then all[#all + 1] = { li = O.header.layoutIndex, s = "READY" } end
  for _, r in ipairs(O.rows) do if r:IsShown() then all[#all + 1] = { li = r.layoutIndex, s = "R:" .. r.questID } end end
  for _, n in pairs(O.notes) do if n:IsShown() then all[#all + 1] = { li = n.layoutIndex, s = "NOTE" } end end
  table.sort(all, function(a, b) return a.li < b.li end)
  for _, x in ipairs(all) do t[#t + 1] = x.s end
  return table.concat(t, " ")
end
local function Dups()
  local seen = {}
  for _, s in ipairs(QC.lastSeq or {}) do if seen[s.f.layoutIndex] then return true end seen[s.f.layoutIndex] = true end
  return false
end
QC.SetView(false)
QuestLogQuests_Update()
ok(Order() == "H:Darkshore Q:301 H:Elwynn Forest Q:201 Q:45 H:Redridge Mountains Q:401 H:Westfall Q:101 Q:102", "zones in alphabetical order (the game gave Westfall first)", Order())
ok(not Dups() and QC.lastSeq[1].f.layoutIndex == 3 and contents.layouts >= 1, "indices from where the game's section starts (3), none twice; the layout run again")
local function Pad(title) for h in SF8.headerFramePool:EnumerateActive() do if h._title == title then return h.topPadding end end end
ok(Pad("Darkshore") == 8 and Pad("Elwynn Forest") == 4 and RowOf(201).topPadding == 2 and RowOf(45).topPadding == -3, "the game's spacing: first header 8, header after a quest 4, first quest 2, next -3")
-- a map change: the game sorts the zone of the map first, a quest's click the same
W.order = { 401, 301, 101, 102, 201, 45 }
QuestLogQuests_Update()
ok(Order() == "H:Darkshore Q:301 H:Elwynn Forest Q:201 Q:45 H:Redridge Mountains Q:401 H:Westfall Q:101 Q:102", "the game re-sorted (Redridge first, as on a map change / quest click): still alphabetical", Order())
W.order = { 45, 201, 101, 102, 401, 301 }
QuestLogQuests_Update()
ok(Order() == "H:Darkshore Q:301 H:Elwynn Forest Q:45 Q:201 H:Redridge Mountains Q:401 H:Westfall Q:101 Q:102", "and again (Elwynn first): zones the same; a zone's quests as the game lists them", Order())
W.order = { 101, 102, 201, 45, 301, 401 }
W.collapsed["Elwynn Forest"] = true
QuestLogQuests_Update()
ok(Order() == "H:Darkshore Q:301 H:Elwynn Forest H:Redridge Mountains Q:401 H:Westfall Q:101 Q:102" and Pad("Redridge Mountains") == 6, "a collapsed zone: its header only, in place; header after header 6", Order())
ok(QC.ours.header == nil or not QC.ours.header:IsShown(), "Ready section off by default: not shown")
-- the game's Separator (after the campaigns / zone story): the zones start right after it
contents.Separator = { layoutIndex = 2 }
QuestLogQuests_Update()
ok(QC.lastSeq[1].f.layoutIndex == 3 and not Dups(), "after the game's Separator (2): from 3")
contents.Separator = nil

print("-- Ready to Turn In: on")
local db = mod.db
ok(not db.readyInLog and mod.defaults.readyInLog == false and mod.defaults.readyLogCollapsed == false, "the setting: readyInLog off at first; the section expanded at first")
QC.SetReady(true)
QuestLogQuests_Update()
ok(Order() == "H:Darkshore Q:301 H:Elwynn Forest H:Redridge Mountains NOTE H:Westfall Q:101 READY R:201 R:45 R:401 R:102", "ready quests leave their zones for the section at the very bottom (a collapsed zone's too)", Order())
ok(QC.ours.header.ButtonText._text == "Ready to Turn In (4)", "its header: Ready to Turn In (4)", QC.ours.header.ButtonText._text)
local nRR
for h, n in pairs(QC.ours.notes) do if n:IsShown() then nRR = n end end
ok(nRR and nRR.Text._text == "Quests are in the Ready to Turn In section" and QC.ours.notes[(function() for h in SF8.headerFramePool:EnumerateActive() do if h._title == "Redridge Mountains" then return h end end end)()] == nRR,
  "a zone whose quests all moved: header kept, 'Quests are in the Ready to Turn In section' under it")
ok(not RowOf(102):IsShown() and RowOf(101):IsShown(), "a zone with some left: only the rest shown (Westfall: The Defias Brotherhood)")
local hiddenObj = true
for o in objPool:EnumerateActive() do if o.questID == 102 and o:IsShown() then hiddenObj = false end end
local poi = contents:FindButtonByQuestID(102)
ok(hiddenObj and poi and not poi:IsShown(), "its objective lines and quest icon hidden with it")
ok(not Dups() and QC.ours.header.topPadding == 4 and QC.ours.rows[1].topPadding == 2 and QC.ours.rows[2].topPadding == -3, "the section's spacing as the game's (4, 2, -3); no index twice")
ok(QC.ours.rows[1].Text._text == "A Fishy Peril" and QC.ours.rows[4].Text._text == "Patrolling Westfall", "its rows: by zone name, then log order")
-- the collapsed zone: Elwynn's ready quests listed though its rows aren't there
ok(Order():find("R:201 R:45", 1, true) ~= nil, "a collapsed zone's ready quests listed all the same")
print("-- clicks")
local opened, tracked
_G.QuestMapFrame_ShowQuestDetails = function(q) opened = q end
_G.QuestMapQuestOptions_TrackQuest = function(q) tracked = q end
local r1 = QC.ours.rows[1]
r1._scripts.OnClick(r1, "LeftButton")
ok(opened == 201 and tracked == nil, "left-click: the quest opens (as the game's row)")
_G.IsShiftKeyDown = function() return true end
r1._scripts.OnClick(r1, "LeftButton")
ok(tracked == 201, "Shift-click: tracked (as the game's row)")
_G.IsShiftKeyDown = function() return false end
print("-- chain buttons on Ready rows (Chain quest view on)")
QC.SetView(true)
QuestLogQuests_Update()
local rb = ButtonOf(QC.ours.rows[2])
ok(rb and Shown(rb) and rb.questID == 45, "Chain quest view on: Discover Rolf's Fate's chain button on its Ready row")
ok(not (ButtonOf(QC.ours.rows[1]) and Shown(ButtonOf(QC.ours.rows[1]))), "a quest without chain data: none")
QC.SetView(false)
ok(not Shown(ButtonOf(QC.ours.rows[2])), "view off: gone")
print("-- collapse, remembered")
local hdr = QC.ours.header
hdr._scripts.OnClick(hdr, "LeftButton")
ok(db.readyLogCollapsed == true and Order():find("READY$") ~= nil and not QC.ours.rows[1]:IsShown(), "its header: collapsed (rows hidden), saved", Order())
QuestLogQuests_Update()
ok(Order():find("READY$") ~= nil and hdr.ButtonText._text == "Ready to Turn In (4)", "after the game's next update: still collapsed, the count kept")
hdr._scripts.OnClick(hdr, "LeftButton")
ok(db.readyLogCollapsed == false and QC.ours.rows[1]:IsShown(), "again: expanded")
print("-- a quest turned in / completed; off again")
W.quests[101].ready = true
QuestLogQuests_Update()
ok(Order():find("H:Westfall NOTE READY", 1, true) and hdr.ButtonText._text == "Ready to Turn In (5)", "Westfall's last quest ready: Westfall's note, Ready (5)", Order())
W.Drop(201) W.Drop(45)
QuestLogQuests_Update()
ok(hdr.ButtonText._text == "Ready to Turn In (3)" and not Order():find("Elwynn", 1, true), "turned in: gone from the section (and its zone with them)", Order())
QC.SetReady(false)
ok(Order() == "H:Darkshore Q:301 H:Redridge Mountains Q:401 H:Westfall Q:101 Q:102" and not hdr:IsShown(), "off: every quest back in its zone, the section and notes gone (at once, no game update)", Order())
local back8 = true
for o in objPool:EnumerateActive() do if not o:IsShown() then back8 = false end end
ok(back8 and contents:FindButtonByQuestID(102):IsShown(), "their objective lines and quest icons shown again")
print("-- combat, module off")
QC.SetReady(true)
W.combat = true
QuestLogQuests_Update() QC.SetReady(false) QC.SetReady(true)
ok(W.blockedSetters == 0 and Frame.protectedCalls == 0, "in combat: only show / hide / place (no blocked setters, nothing protected)")
W.combat = false
mod:OnDisable()
ok(not hdr:IsShown() and RowOf(102):IsShown(), "module off: our section gone, the rows back")
mod.enabled = true
C_QuestLog.GetInfo = baseInfo
_G.QuestLogQuests_Update = gameUpdate

---------------------------------------------------------------------------
print("== 9. (1.2.22) the log's zones stay as you leave them (by name, per character), whatever the game resets")
W.Reset()
W.collapsed = {}
W.mapZone = nil
W.zc = {}
W.search = ""
mod.db = { enabled = true, chainView = false, readyInLog = false, readyLogCollapsed = false }
mod.char = {}
mod.enabled = true
mod:OnEnable()   -- (section 8 ended with the module off: its events again)
W.AddQuest(101, "Westfall", "The Defias Brotherhood", 14)
W.AddQuest(102, "Westfall", "Patrolling Westfall", 12)
W.AddQuest(201, "Elwynn Forest", "A Fishy Peril", 8, true)
W.AddQuest(45, "Elwynn Forest", "Discover Rolf's Fate", 10)
W.AddQuest(301, "Darkshore", "Buzzbox 827", 12)
W.AddQuest(401, "Redridge Mountains", "Murloc Poachers", 18, true)
-- the game: isCollapsed / isOnMap by zone; its header calls; its ResetFilters (QuestMapFrame.lua 927-940)
C_QuestLog.GetInfo = function(i)
  local e = baseInfo(i)
  if e then e = setmetatable({ questLogIndex = i, isCollapsed = e.isHeader and W.collapsed[e.title] or false,
    isOnMap = e.isHeader and e.title == W.mapZone or false }, { __index = e }) end
  return e
end
local function TitleAt(i) local e = baseInfo(i) return e and e.title end
function ExpandQuestHeader(i, auto) W.zc[#W.zc + 1] = { "E", TitleAt(i), auto } W.collapsed[TitleAt(i)] = false end
function CollapseQuestHeader(i, auto) W.zc[#W.zc + 1] = { "C", TitleAt(i), auto } W.collapsed[TitleAt(i)] = true end
function QuestMapFrame_ResetFilters()
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(i)
    if info and info.isHeader then
      if info.isOnMap then ExpandQuestHeader(i, true) else CollapseQuestHeader(i, true) end
    end
  end
end
_G.QuestLogQuests_Update = log8
SF8.SearchBox = W.NewFrame("EditBox")
SF8.SearchBox.GetText = function() return W.search end
ok(QC.Zones and QC.Zones.Hook() and QC.Zones.hooked, "hooked after the game's QuestMapFrame_ResetFilters")
QC.Zones.Hook()
-- the game's Refresh: a map change, the map opening, a loading screen (the zone on the map shown)
local function Refresh(zone) W.mapZone = zone QuestMapFrame_ResetFilters() QuestLogQuests_Update() end
local function Head(title) for h in SF8.headerFramePool:EnumerateActive() do if h._title == title and h:IsShown() then return h end end end
local function Hooks(h, k, ...) for _, fn in ipairs((rawget(h, "_hk") or {})[k] or {}) do fn(h, ...) end end
-- a click on a zone header, as the game's (QuestLogHeaderCodeMixin's click handler, then our hooks)
local function Click(title, button)
  button = button or "LeftButton"
  local h = Head(title)
  Hooks(h, "PreClick", button)
  if button == "LeftButton" then
    local info = C_QuestLog.GetInfo(h.questLogIndex)
    if info.isCollapsed then ExpandQuestHeader(h.questLogIndex) else CollapseQuestHeader(h.questLogIndex) end
  end
  Hooks(h, "OnClick", button)
  QuestLogQuests_Update()
end
local function Folded(t) return W.collapsed[t] and true or false end
local Z = QC.Zones

Refresh("Elwynn Forest")
ok(Folded("Darkshore") and not Folded("Elwynn Forest") and Folded("Westfall"), "nothing saved: the game's way (the map's zone open, the rest folded)")
ok(Order() == "H:Darkshore H:Elwynn Forest Q:201 Q:45 H:Redridge Mountains H:Westfall", "alphabetical as ever", Order())
local hk = Head("Westfall")
ok(rawget(hk, "_hk") and #hk._hk.OnClick == 1 and #hk._hk.PreClick == 1, "each header hooked once (PreClick, OnClick)")
QuestLogQuests_Update() QuestLogQuests_Update()
ok(#hk._hk.OnClick == 1, "laid out again: not hooked twice")
print("-- his clicks saved; the game's resets undone")
Click("Elwynn Forest")      -- (folded: the map's own zone)
Click("Westfall")           -- (opened: another zone)
local store = mod.char.logZones
ok(store and store["Elwynn Forest"] == true and store["Westfall"] == false, "saved by zone name: Elwynn folded, Westfall open")
ok(store["Darkshore"] == nil and store["Redridge Mountains"] == nil, "zones not clicked: nothing saved")
W.zc = {}
Refresh("Elwynn Forest")    -- (a map change back to Elwynn)
ok(Folded("Elwynn Forest") and not Folded("Westfall"), "after the game's reset (a map change): Elwynn still folded, Westfall still open")
ok(Folded("Darkshore") and Folded("Redridge Mountains"), "the zones never clicked: the game's way (folded, not on the map)")
local auto = true for _, c in ipairs(W.zc) do if c[3] ~= true then auto = false end end
ok(#W.zc == 4 + 2 and auto, "the game's 4 calls, then ours 2 (as the game's: auto)", #W.zc)
ok(Order() == "H:Darkshore H:Elwynn Forest H:Redridge Mountains H:Westfall Q:101 Q:102", "laid out: still alphabetical; Elwynn's rows hidden, Westfall's shown", Order())
Refresh("Redridge Mountains")  -- (the map opening on another zone)
ok(Folded("Elwynn Forest") and not Folded("Westfall") and not Folded("Redridge Mountains") and Folded("Darkshore"), "the map opening elsewhere: his two kept; Redridge (the map's, never clicked) the game's")
W.zc = {}
ok(Z.Apply() == 0 and #W.zc == 0, "nothing to put back: no calls at all (no loop)")
Z.applying = true
W.collapsed["Westfall"] = true
ok(Z.Apply() == 0, "while putting back: not again (guard)")
Z.applying = false
ok(Z.Apply() == 1 and not Folded("Westfall"), "then once: Westfall open again")
print("-- what isn't a click: not saved")
local snap = {} for k, v in pairs(store) do snap[k] = v end
local function Same() for k, v in pairs(snap) do if store[k] ~= v then return false end end for k in pairs(store) do if snap[k] == nil then return false end end return true end
-- a map pin's hover (ExpandHeaderForQuest: ExpandQuestHeader, no click)
for i = 1, C_QuestLog.GetNumQuestLogEntries() do local e = C_QuestLog.GetInfo(i) if e.isHeader and e.title == "Darkshore" then ExpandQuestHeader(i) end end
QuestLogQuests_Update()
ok(not Folded("Darkshore") and Same(), "a map pin's hover opened Darkshore: not saved")
-- the search: the game saves, expands, restores (QuestSearcher); clicks while searching aren't saved
W.search = "murloc"
local before = {} for k, v in pairs(W.collapsed) do before[k] = v end
for i = 1, C_QuestLog.GetNumQuestLogEntries() do local e = C_QuestLog.GetInfo(i) if e.isHeader and e.isCollapsed then ExpandQuestHeader(i) end end
QuestLogQuests_Update()
Click("Westfall")
ok(Same(), "searching: the search's expanding and a click on a header: not saved")
W.zc = {}
QuestMapFrame_ResetFilters()
local ours = 0 for _, c in ipairs(W.zc) do if c[3] == true then ours = ours + 1 end end
ok(Folded("Elwynn Forest") and ours == 4, "searching: the game's reset, nothing put back by us (the search keeps the headers)", ours)
for k, v in pairs(before) do W.collapsed[k] = v end   -- (the search cleared: the game restores)
W.search = ""
QuestLogQuests_Update()
ok(Same(), "search cleared: still nothing saved from it")
Click("Darkshore", "RightButton")
ok(Same(), "a right-click (the header's menu): not saved")
print("-- a /reload, a log-in: the game forgets, Valhalla puts them back")
W.collapsed = {}                            -- (the client's own state gone: every zone open)
W.zc = {}
Fire("PLAYER_ENTERING_WORLD")
ok(Folded("Elwynn Forest") and not Folded("Westfall") and not Folded("Darkshore") and #W.zc == 1, "PLAYER_ENTERING_WORLD alone: Elwynn folded again (one call)", #W.zc)
W.collapsed = {}
Refresh("Westfall")                          -- (the game's own Refresh at the loading screen)
ok(Folded("Elwynn Forest") and not Folded("Westfall") and Folded("Darkshore"), "the game's Refresh at login: his zones as he left them")
print("-- a quest accepted elsewhere: the log's indices shift, the names don't")
W.AddQuest(501, "Ashenvale", "Bathran's Hair", 21)
table.remove(W.order) table.insert(W.order, 1, 501)
Refresh("Westfall")
ok(C_QuestLog.GetInfo(1).title == "Ashenvale" and Folded("Elwynn Forest") and not Folded("Westfall"), "a new zone first in the log (every index moved): Elwynn folded, Westfall open")
ok(Order():find("^H:Ashenvale H:Darkshore H:Elwynn Forest H:Redridge Mountains H:Westfall Q:101 Q:102$") ~= nil, "alphabetical, the new zone the game's way (folded)", Order())
Click("Ashenvale")
ok(store["Ashenvale"] == false and not Folded("Ashenvale"), "clicked open: saved by its name")
Click("Elwynn Forest")
ok(store["Elwynn Forest"] == false, "Elwynn clicked open again: saved open")
Refresh("Darkshore")
ok(not Folded("Elwynn Forest") and not Folded("Ashenvale") and not Folded("Westfall") and Folded("Redridge Mountains"), "the next reset: all three open; Redridge the game's")
print("-- the Ready to Turn In section: its own state, as before")
QC.SetReady(true)
QuestLogQuests_Update()
local rh = QC.ours.header
local was = mod.db.readyLogCollapsed
rh._scripts.OnClick(rh, "LeftButton")
ok(mod.db.readyLogCollapsed == not was and store["Ready to Turn In (2)"] == nil, "its header: readyLogCollapsed toggled, nothing in the zones' store")
rh._scripts.OnClick(rh, "LeftButton")
ok(mod.db.readyLogCollapsed == was, "and back")
Refresh("Darkshore")
ok(Order():find("READY", 1, true) and Order():find("^H:Ashenvale") ~= nil, "after a reset: the section still at the bottom, the zones alphabetical", Order())
QC.SetReady(false)
print("-- the game's state a moment late (after the click's hooks): saved as it will be")
do
  local h = Head("Redridge Mountains")
  local was = Folded("Redridge Mountains")
  Hooks(h, "PreClick", "LeftButton")
  Hooks(h, "OnClick", "LeftButton")              -- (the game hasn't changed it yet)
  if was then ExpandQuestHeader(h.questLogIndex) else CollapseQuestHeader(h.questLogIndex) end
  QuestLogQuests_Update()
  ok(store["Redridge Mountains"] == not was, "Redridge clicked, the game's state late: saved as " .. tostring(not was))
  local h2 = Head("Redridge Mountains")
  local was2 = Folded("Redridge Mountains")
  Hooks(h2, "OnClick", "LeftButton")             -- (no PreClick seen: the state at the last layout)
  if was2 then ExpandQuestHeader(h2.questLogIndex) else CollapseQuestHeader(h2.questLogIndex) end
  QuestLogQuests_Update()
  ok(store["Redridge Mountains"] == not was2, "no PreClick, the state late: from the last layout, saved as " .. tostring(not was2))
end
print("-- the module off: the game's way")
mod.enabled = false
W.zc = {}
Refresh("Darkshore")
local mine = 0 for _, c in ipairs(W.zc) do if c[1] == "E" and c[2] == "Westfall" then mine = mine + 1 end end
ok(Folded("Westfall") and mine == 0, "off: nothing put back (Westfall folded, as the game set it)")
Click("Westfall")
ok(store["Westfall"] == false, "off: clicks not saved either")
mod.enabled = true
ok(Frame.protectedCalls == 0 and W.blockedSetters == 0, "nothing protected, no blocked setters")
local fields = 0
for h in SF8.headerFramePool:EnumerateActive() do for _, k in ipairs({ "valhallaFolded", "valhallaHooked", "folded", "preFolded" }) do if rawget(h, k) ~= nil then fields = fields + 1 end end end
ok(fields == 0, "no fields of ours on the game's header buttons")
print("== 10. (1.2.23) in combat: the zones put back once combat ends; a Shift-click's tracking waits too")
assert(loadfile(root .. "CombatQueue.lua"))("Valhalla", ns)
local CQ = ns.Combat
store["Westfall"] = false
W.collapsed["Westfall"] = true
W.combat = true
W.zc = {}
ok(Z.Apply() == 0 and #W.zc == 0 and Folded("Westfall") and CQ.Pending("questlog:zones"), "in combat: no header calls of ours; one apply queued")
local heads = 0 for i = 1, C_QuestLog.GetNumQuestLogEntries() do if C_QuestLog.GetInfo(i).isHeader then heads = heads + 1 end end
QuestMapFrame_ResetFilters()
ok(#W.zc == heads, "the game's reset in combat: only the game's own calls (its hook queues, doesn't call)", #W.zc .. " vs " .. heads)
W.zc = {}
Fire("PLAYER_ENTERING_WORLD")
ok(#W.zc == 0, "a loading screen in combat: nothing put back yet", #W.zc)
local queued = 0 for _, k in ipairs(CQ.order) do if k == "questlog:zones" then queued = queued + 1 end end
ok(queued == 1, "queued once, however many asked", queued)
local wantW = store["Westfall"]
W.collapsed["Westfall"] = true
W.combat = false
CQ.Flush()
ok(Folded("Westfall") == wantW and not CQ.Pending("questlog:zones"), "combat over: put back (Westfall open, as he left it)")
local okAll = true
for t, want in pairs(store) do
  local found = false
  for i = 1, C_QuestLog.GetNumQuestLogEntries() do local e = C_QuestLog.GetInfo(i) if e.isHeader and e.title == t then found = true end end
  if found and Folded(t) ~= want then okAll = false end
end
ok(okAll, "every saved zone as he left it after the flush")
W.zc = {}
ok(Z.Apply() == 0 and #W.zc == 0, "out of combat, nothing different: no calls (as 1.2.22)")
-- Shift-click on a chain row: the game's track toggle, in combat queued
local tracked = {}
local gameTrack, shift, cfu = rawget(_G, "QuestMapQuestOptions_TrackQuest"), rawget(_G, "IsShiftKeyDown"), rawget(_G, "ChatFrameUtil")
_G.QuestMapQuestOptions_TrackQuest = function(q) tracked[#tracked + 1] = q end
_G.IsShiftKeyDown = function() return true end
_G.ChatFrameUtil = nil
ns.printed = {}
W.combat = true
QC.RowClick({ questID = 101 }, "LeftButton")
QC.RowClick({ questID = 101 }, "LeftButton")
local said = 0 for _, p in ipairs(ns.printed) do if p:find("applies when combat ends", 1, true) then said = said + 1 end end
ok(#tracked == 0 and CQ.Pending("watch:101") and said == 1, "Shift-click in combat: not tracked yet, queued, told once", #tracked .. " " .. said)
W.combat = false
CQ.Flush()
ok(#tracked == 1 and tracked[1] == 101, "combat over: the game's track toggle once (the last click kept)", #tracked)
QC.RowClick({ questID = 101 }, "LeftButton")
ok(#tracked == 2 and not CQ.Pending(), "out of combat: straight away")
_G.QuestMapQuestOptions_TrackQuest, _G.IsShiftKeyDown, _G.ChatFrameUtil = gameTrack, shift, cfu
ok(Frame.protectedCalls == 0 and W.blockedSetters == 0, "nothing protected, no blocked setters")

C_QuestLog.GetInfo = baseInfo
_G.QuestLogQuests_Update = gameUpdate

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
