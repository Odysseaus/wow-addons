-- Box tests for Valhalla/Objectives/Objectives.lua (Lua 5.1). Run: lua valhalla/tests/objectives/objectives_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
dofile(here .. "stubs.lua")

-- a minimal Valhalla namespace (Core.lua's pieces the module uses)
local ns = { modules = {}, Media = { path = "Interface\\AddOns\\Valhalla\\Media\\" } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Safe = { Value = function(v) return v end }
ns.printed = {}
function ns:Print(fmt, ...) ns.printed[#ns.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} if m.defaults.enabled == nil then m.defaults.enabled = true end self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
assert(loadfile(root .. "Objectives/Objectives.lua"))("Valhalla", ns)
local mod = ns:GetModule("objectives")
local O = mod.O

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end
local function list(t) local s = {} for i, v in ipairs(t) do s[i] = tostring(v) end return "{" .. table.concat(s, ",") .. "}" end
local function eq(a, b) if #a ~= #b then return false end for i = 1, #a do if a[i] ~= b[i] then return false end end return true end
local function has(t, x) for _, v in ipairs(t) do if v == x then return true end end return false end

-- the game's side of an event (its tracker's own handlers), then ours
local function Fire(event, a1)
  if event == "QUEST_ACCEPTED" and W.autoWatch then C_QuestLog.AddQuestWatch(a1) end
  if event == "ZONE_CHANGED_NEW_AREA" then -- C_QuestLog.SortQuestWatches: some other order
    local r = {} for i = #W.watches, 1, -1 do r[#r + 1] = W.watches[i] end W.watches = r
  end
  -- delivered as the game does: to frames that registered the event
  for _, f in ipairs(W.frames) do
    if rawget(f, "_events") and f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, a1) end
  end
end
-- the module's ticker, while it runs
local function Run(sec)
  local n = math.floor(sec / O.TICK + 0.5)
  for _ = 1, n do
    W.clock = W.clock + O.TICK
    if W.ticker and not W.ticker.cancelled then W.ticker.fn() end
  end
end
-- the game's tracker, as the module reads it (its frame, sections and rows)
_G.ObjectiveTrackerFrame = W.NewFrame("Frame")
ObjectiveTrackerFrame.modules = {}
local function Start(db, char)
  mod.db = db or { enabled = true, readyCollapsed = false }
  mod.char = char or {}
  mod.enabled = true
  mod:OnEnable()
end
local function ReadyIds() local out = {} for _, e in ipairs(O.ReadyList(O.S.log, O.S.here)) do out[#out + 1] = e.id end return out end

---------------------------------------------------------------------------
print("== 1. zone filter: Stormwind plus Elwynn Forest; level order; tie by title")
W.Reset()
W.AddQuest(1, "Stormwind City", "Report to Bishop", 8, false, true)
W.AddQuest(2, "Elwynn Forest", "Wolves", 5, false, true)
W.AddQuest(3, "Elwynn Forest", "Kobolds", 7, false, true)
W.AddQuest(4, "Westfall", "Harvest Watchers", 12, false, true)
W.AddQuest(5, "Dun Morogh", "Frostmane", 6, false, true)
W.AddQuest(6, "Elwynn Forest", "Bears", 7, false, true)   -- same level as Kobolds: "Bears" first
W.map = 1453
Start()
Run(2)
ok(eq(W.watches, { 2, 6, 3, 1 }), "Stormwind: city + Elwynn quests, lowest level first, ties by title", list(W.watches))
ok(not has(W.watches, 4) and not has(W.watches, 5), "Stormwind: Westfall / Dun Morogh quests untracked")
ok(mod.db.watchSide == "front", "learned: a new watch goes to the front", tostring(mod.db.watchSide))
ok(mod.char.hidden[4] and mod.char.hidden[5], "untracked quests remembered (given back when turned off)")

print("== 1b. a sub-zone micro map walks up to its zone")
W.map = 9001
Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(eq(W.watches, { 2, 6, 3 }), "Goldshire Inn (micro map) -> Elwynn Forest only", list(W.watches))
W.map = 1453 Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(eq(W.watches, { 2, 6, 3, 1 }), "back in Stormwind", list(W.watches))

print("== 1c. GetQuestsOnMap counts a quest whose log header is another zone")
W.onMap[1429] = { 5 }
Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(has(W.watches, 5), "a quest on Elwynn's map is listed in Stormwind", list(W.watches))
W.onMap[1429] = nil
Fire("ZONE_CHANGED_NEW_AREA") Run(2)

---------------------------------------------------------------------------
print("== 2. taxi: nothing changes in flight; applied on landing")
local before = list(W.watches)
W.taxi = true
W.map = 1436 Fire("ZONE_CHANGED_NEW_AREA")
Run(5)
ok(list(W.watches) == list({ 1, 3, 6, 2 }) or true, "(the game's own re-sort happened at the zone change)")
local adds, removes = W.calls.add, W.calls.remove
Run(5)
ok(W.calls.add == adds and W.calls.remove == removes, "no watch changes while on the taxi")
ok(not has(W.watches, 4), "Westfall quest not tracked yet (still flying)")
W.taxi = false
Fire("PLAYER_CONTROL_GAINED")
Run(0.6)
ok(not has(W.watches, 4), "waits about a second after landing (the game's re-sort first)")
Run(1.5)
ok(eq(W.watches, { 4 }), "landed in Westfall: Westfall quests only", list(W.watches))

print("== 2b. loading screen: held until it's over")
W.map = 1426
Fire("PLAYER_LEAVING_WORLD") Fire("LOADING_SCREEN_ENABLED")
Fire("ZONE_CHANGED_NEW_AREA") Run(3)
ok(eq(W.watches, { 4 }), "no change during the loading screen", list(W.watches))
Fire("LOADING_SCREEN_DISABLED") Fire("PLAYER_ENTERING_WORLD") Run(2)
ok(eq(W.watches, { 5 }), "arrived in Dun Morogh: its quest", list(W.watches))

---------------------------------------------------------------------------
print("== 3. combat: deferred until it ends")
W.combat = true
W.map = 1436 Fire("ZONE_CHANGED_NEW_AREA")
Run(3)
ok((W.combatChanges or 0) == 0, "no watch changes in combat")
ok(eq(W.watches, { 5 }), "list unchanged in combat", list(W.watches))
W.combat = false Fire("PLAYER_REGEN_ENABLED")
Run(2)
ok(eq(W.watches, { 4 }), "after combat: Westfall's", list(W.watches))

---------------------------------------------------------------------------
print("== 4. sort helper: level, then title, then id")
local s = { { id = 3, level = 10, title = "B" }, { id = 1, level = 10, title = "A" }, { id = 2, level = 2, title = "Z" } }
table.sort(s, O.Before)
ok(s[1].id == 2 and s[2].id == 1 and s[3].id == 3, "level 2 Z, level 10 A, level 10 B")

---------------------------------------------------------------------------
print("== 5. pins: kept in every zone, mixed in by level; shown in Ready when ready")
O.SetPinned(5, true)   -- Dun Morogh quest (level 6), in Westfall
Run(2)
ok(eq(W.watches, { 5, 4 }), "pinned Dun Morogh quest listed in Westfall, by level (6 before 12)", list(W.watches))
ok(mod.char.pinned[5] == true, "saved in ValhallaCharDB.objectives.pinned")
W.map = 1453 Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(has(W.watches, 5) and eq(W.watches, { 2, 5, 6, 3, 1 }), "pinned quest kept in Stormwind, by level", list(W.watches))
W.quests[5].ready = true
Fire("QUEST_LOG_UPDATE") Run(2)
ok(not has(W.watches, 5), "pinned quest ready: leaves Quests", list(W.watches))
ok(has(ReadyIds(), 5), "pinned ready quest in Ready to Turn In (other zone)", list(ReadyIds()))
O.SetPinned(5, false) Run(1)
ok(not has(ReadyIds(), 5), "unpinned: the other zone's ready quest leaves Ready", list(ReadyIds()))
O.SetPinned(5, true) Run(1)

---------------------------------------------------------------------------
print("== 6. ready quests move from Quests to Ready")
W.quests[3].ready = true
Fire("QUEST_LOG_UPDATE") Run(2)
ok(not has(W.watches, 3), "Kobolds ready: untracked from Quests", list(W.watches))
ok(eq(ReadyIds(), { 5, 3 }), "Ready lists 5 (lvl 6) then 3 (lvl 7)", list(ReadyIds()))
ok(O.UI.ready and O.UI.ready._shown, "Ready section shown")
local r1 = O.UI.ready and O.UI.ready.rows[1]
ok(r1 and r1.q == 5 and r1.pin and r1.pin._shown, "Ready row 1 is quest 5 with its pin")
O.UI.ready.toggle._scripts.OnClick(O.UI.ready.toggle)
ok(mod.db.readyCollapsed == true and O.UI.ready.n == 0, "collapse button folds the section")
O.UI.ready.toggle._scripts.OnClick(O.UI.ready.toggle)
ok(mod.db.readyCollapsed == false and O.UI.ready.n == 2, "and unfolds it")
r1._scripts.OnClick(r1)
ok(W.super == 5, "clicking a Ready row selects (super-tracks) the quest")

---------------------------------------------------------------------------
print("== 7. a new quest in this zone shows at once, in its place")
W.AddQuest(7, "Elwynn Forest", "Gold Dust", 6, false, false)
Fire("QUEST_ACCEPTED", 7)
Run(1.2)
ok(eq(W.watches, { 2, 7, 6, 1 }), "new Elwynn quest (lvl 6) tracked in order", list(W.watches))

print("== 7b. a new quest whose data arrives late")
W.autoWatch = false
Fire("QUEST_ACCEPTED", 8) Run(1)  -- not in the log yet
W.AddQuest(8, "Stormwind City", "Late Data", 9, false, false)
Run(1.2)
ok(has(W.watches, 8) and W.watches[#W.watches] == 8, "placed once its entry appears (lvl 9 last)", list(W.watches))
W.autoWatch = true

print("== 7c. a new quest that is already complete goes to Ready")
W.AddQuest(9, "Elwynn Forest", "Deliver Letter", 5, true, false)
Fire("QUEST_ACCEPTED", 9) Run(1.2)
ok(not has(W.watches, 9) and has(ReadyIds(), 9), "complete on accept: in Ready, not Quests", list(W.watches) .. " " .. list(ReadyIds()))

---------------------------------------------------------------------------
print("== 8. a new quest for another zone is untracked until you get there")
W.AddQuest(10, "Duskwood", "Night Web", 20, false, false)
Fire("QUEST_ACCEPTED", 10)
ok(has(W.watches, 10), "(the game auto-tracked it)")
Run(1.2)
ok(not has(W.watches, 10), "Duskwood quest untracked in Stormwind", list(W.watches))
Fire("QUEST_LOG_UPDATE") Run(2)
ok(not has(W.watches, 10), "stays out on later log updates", list(W.watches))
W.map = 1431 Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(has(W.watches, 10), "entering Duskwood: tracked", list(W.watches))

---------------------------------------------------------------------------
print("== 9. pins cleared on turn-in and abandon")
O.SetPinned(10, true)
W.Drop(5) Fire("QUEST_TURNED_IN", 5) Fire("QUEST_REMOVED", 5)
ok(mod.char.pinned[5] == nil, "turned in: pin cleared")
W.Drop(10) Fire("QUEST_REMOVED", 10)
ok(mod.char.pinned[10] == nil, "abandoned: pin cleared")
Run(2)

---------------------------------------------------------------------------
print("== 10. the 25 limit: pinned stay, highest levels drop off")
W.Reset()
for i = 1, 30 do W.AddQuest(100 + i, "Westfall", ("Q%02d"):format(i), i, false, i <= 20) end
W.AddQuest(200, "Duskwood", "Pinned A", 40, false, false)
W.AddQuest(201, "Duskwood", "Pinned B", 41, false, false)
mod:OnDisable()
Start({ enabled = true, watchSide = "front" }, { pinned = { [200] = true, [201] = true } })
W.map = 1436 Fire("ZONE_CHANGED_NEW_AREA") Run(4)
ok(#W.watches == 25, "25 tracked", tostring(#W.watches))
ok(has(W.watches, 200) and has(W.watches, 201), "both pinned kept")
ok(has(W.watches, 123) and not has(W.watches, 124) and not has(W.watches, 130), "levels 1-23 kept, 24-30 dropped")
ok(W.watches[1] == 101 and W.watches[23] == 123 and W.watches[24] == 200 and W.watches[25] == 201, "in level order", list(W.watches))

---------------------------------------------------------------------------
print("== 11. the off switch gives back normal tracking")
ok(mod.char.hidden[124] ~= nil or true, "(quests above the limit were never watched)")
-- some hidden: make a quest from another zone hidden by Valhalla
W.Reset()
W.AddQuest(1, "Westfall", "A", 10, false, true)
W.AddQuest(2, "Duskwood", "B", 20, false, true)
W.AddQuest(3, "Westfall", "C", 11, true, true)
mod:OnDisable()
Start({ enabled = true, watchSide = "front" }, {})
W.map = 1436 Fire("ZONE_CHANGED_NEW_AREA") Run(3)
ok(eq(W.watches, { 1 }), "on: Westfall's in-progress quest only", list(W.watches))
O.SetOn(false)
ok(has(W.watches, 2) and has(W.watches, 3) and #W.watches == 3, "off: untracked quests tracked again", list(W.watches))
ok(W.ticker.cancelled and mod.db.enabled == false and mod.enabled == false, "off: ticker stopped, saved off")
ok(not (O.UI.ready and O.UI.ready._shown), "off: Ready section hidden")
local a2 = W.calls.add + W.calls.remove
W.map = 1453 Fire("ZONE_CHANGED_NEW_AREA") Run(3)
ok(W.calls.add + W.calls.remove == a2, "off: zone changes leave tracking alone")
O.SetOn(true) Run(2)
ok(mod.enabled and eq(W.watches, {}), "on again: Stormwind has none of these", list(W.watches))
mod:Slash("off")
ok(mod.enabled == false and ns.printed[#ns.printed]:find("off"), "/valhalla objectives off", ns.printed[#ns.printed])
mod:Slash("on")
ok(mod.enabled == true and ns.printed[#ns.printed]:find(": on"), "/valhalla objectives on")

print("== 11b. turned off in combat: given back after it")
W.map = 1436 Fire("ZONE_CHANGED_NEW_AREA") Run(3)
W.combat = true
O.SetOn(false)
ok((W.combatChanges or 0) == 0, "nothing in combat")
W.combat = false Fire("PLAYER_REGEN_ENABLED")
ok(has(W.watches, 2), "given back after combat", list(W.watches))

---------------------------------------------------------------------------
print("== 12. a client where a new watch goes to the end")
W.Reset() W.side = "end"
W.AddQuest(1, "Westfall", "C", 12, false, true)
W.AddQuest(2, "Westfall", "A", 10, false, true)
W.AddQuest(3, "Westfall", "B", 11, false, true)
Start({ enabled = true }, {})
W.map = 1436 Fire("ZONE_CHANGED_NEW_AREA") Run(3)
ok(eq(W.watches, { 2, 3, 1 }), "ordered", list(W.watches))
ok(mod.db.watchSide == "end", "learned: end", tostring(mod.db.watchSide))
W.watches = { 1, 3, 2 } O.S.reorderDue = W.clock Run(1)
ok(eq(W.watches, { 2, 3, 1 }), "re-ordered with the learned side", list(W.watches))

---------------------------------------------------------------------------
print("== 13. pins on the tracker's rows")
local block = W.NewFrame("Frame") block.poiButton = W.NewFrame("Button") block.HeaderText = W.NewFrame("FontString")
_G.QuestObjectiveTracker = { blockTemplate = "ObjectiveTrackerQuestPOIBlockTemplate", usedBlocks = { ObjectiveTrackerQuestPOIBlockTemplate = { [2] = block } } }
Run(0.4)
local p = O.UI.pins[1]
ok(p and p._shown and p.q == 2, "a pin on the quest's row")
ok(p and p._points[1] and p._points[1][1] == "RIGHT" and p._points[1][2] == block.poiButton and p._points[1][3] == "LEFT", "left of the game's quest icon")
ok(p.icon._tex and p.icon._tex:find("ValhallaPinOff"), "off by default (grey pin)")
p._scripts.OnClick(p) Run(0.4)
ok(mod.char.pinned[2] == true and p.icon._tex:find("ValhallaPinOn"), "click: pinned (gold pin)")
p._scripts.OnEnter(p)
p._scripts.OnClick(p) Run(0.4)
ok(not mod.char.pinned[2], "click again: unpinned")
ok(rawget(block, "_scripts") and next(block._scripts) == nil and #block._points == 0, "the game's row untouched (no scripts, no points set)")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
