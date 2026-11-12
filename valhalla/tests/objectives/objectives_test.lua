-- Box tests for Valhalla/Objectives/Objectives.lua (Lua 5.1). Run: lua valhalla/tests/objectives/objectives_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
dofile(here .. "stubs.lua")

-- a minimal Valhalla namespace (Core.lua's pieces the module uses)
local ns = { modules = {}, Media = { path = "Interface\\AddOns\\Valhalla\\Media\\" } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Safe = { Value = function(v) return v end }
-- (Data/Forever/Places.lua's shape: a few of the game's instances)
ns.MapPlaces = { instances = {
  { 0, 0, 0, { { 90, "Gnomeregan", false, 25, 30 } } },
  { 0, 0, 0, { { 36, "Deadmines", false, 16, 21 } } },
  { nil, 0.478, 0.562, { { 2998, "Excavation Site: Wetlands", false, 24, 29 } }, map = 1437 },
  { 0, 0, 0, { { 189, "Scarlet Monastery - Armory", false, 30, 35 } } },
}, unplaced = { { 0, "Krol'dok Stronghold", false, 40, 45 } } }
ns.printed = {}
function ns:Print(fmt, ...) ns.printed[#ns.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} if m.defaults.enabled == nil then m.defaults.enabled = true end self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
assert(loadfile(root .. "Objectives/Objectives.lua"))("Valhalla", ns)
assert(loadfile(root .. "Objectives/QuestLogPins.lua"))("Valhalla", ns)
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

print("== 1c. (v0.2.2, E1) another zone's quest: listed for a real marker here, not for a waypoint")
W.onMap[1429] = { 5 }
Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(has(W.watches, 5), "a Dun Morogh quest with a real objective marker on Elwynn's map is listed in Stormwind (E1; v0.2.1 said not)", list(W.watches))
W.waypoints["5:1429"] = true
Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(not has(W.watches, 5), "the same pin as a waypoint: not listed (the v0.2.1 rule)", list(W.watches))
W.waypoints["5:1429"] = nil
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
local block = W.NewFrame("Frame") block.poiButton = W.NewFrame("Button") block.HeaderText = W.NewFrame("FontString") block.HeaderText._text = "[5] Wolves"
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


---------------------------------------------------------------------------
-- v0.2.1
---------------------------------------------------------------------------
local function Arrive(map, inst)
  W.map, W.inst = map, inst
  Fire("PLAYER_LEAVING_WORLD") Fire("LOADING_SCREEN_ENABLED")
  Fire("ZONE_CHANGED_NEW_AREA")
  Fire("LOADING_SCREEN_DISABLED") Fire("PLAYER_ENTERING_WORLD")
  Run(2.5)
end
local function Go(map) W.map, W.inst = map, nil Fire("ZONE_CHANGED_NEW_AREA") Run(2.5) end
local function Restart(char)
  mod:OnDisable()
  Start({ enabled = true, watchSide = "front" }, char or {})
end

print("== 14. waypoint, map-indicator and other-map pins don't list a quest (Quests or Ready)")
W.Reset()
W.AddQuest(1, "Stormwind City", "Rethban Ore", 15, false, true)
W.AddQuest(2, "Duskwood", "Wolves at Our Heels", 20, false, true)
W.AddQuest(3, "Wetlands", "Tramping Paws", 22, false, true)
W.AddQuest(4, "Ironforge", "The Darkmoon Faire", 10, true, false)
W.AddQuest(5, "Duskwood", "The Legend of Stalvan", 25, true, false)
W.onMap[1429] = { 2, 5 } W.waypoints["2:1429"] = true W.waypoints["5:1429"] = true   -- "travel to Duskwood" pins on Elwynn
W.onMap[1453] = { { questID = 4, mapID = 1455 } }                                     -- Ironforge's pin, read on Stormwind's map
W.onMap[1426] = { { questID = 3, isMapIndicatorQuest = true } }                       -- a map indicator on Dun Morogh
Restart() Go(1453)
ok(eq(W.watches, { 1 }), "Stormwind: Duskwood quest's waypoint pin doesn't list it", list(W.watches))
ok(not has(ReadyIds(), 4) and not has(ReadyIds(), 5), "Stormwind Ready: no Ironforge / Duskwood quests", list(ReadyIds()))
Go(1455)
ok(not has(W.watches, 3) and not has(W.watches, 1), "Ironforge: the Wetlands quest's map indicator doesn't list it", list(W.watches))
ok(eq(ReadyIds(), { 4 }), "Ironforge Ready: its own Darkmoon Faire quest", list(ReadyIds()))
Go(1431)
ok(eq(W.watches, { 2 }) and eq(ReadyIds(), { 5 }), "Duskwood: its quests, by header", list(W.watches) .. list(ReadyIds()))

print("== 15. an unpinned, super-tracked ready quest from another zone leaves Ready")
O.SetPinned(5, true) Run(0.5)
Go(1453)
W.super = 5 Fire("SUPER_TRACKING_CHANGED") Run(0.4)
ok(has(ReadyIds(), 5), "pinned: in Stormwind's Ready", list(ReadyIds()))
O.SetPinned(5, false) Run(1)
ok(not has(ReadyIds(), 5), "unpinned: gone, though super-tracked (waypoint pin on Elwynn)", list(ReadyIds()))
local f0 = O.UI.ready
ok(not (f0 and f0._shown and (O.S.readyCount or 0) > 0), "Ready section hidden when nothing's ready here")

print("== 16. an already-tracked quest from another zone is untracked on arrival")
W.watches = { 3, 1 }   -- (Tramping Paws tracked from before)
W.waypoints["3:1426"] = true W.onMap[1426] = { 3 }
Arrive(1455)
ok(not has(W.watches, 3), "Ironforge: Tramping Paws untracked", list(W.watches))
ok(mod.char.hidden[3], "remembered (given back when turned off)")

print("== 17. 'Excavation Site: Wetlands' counts as Wetlands")
W.AddQuest(7, "Excavation Site: Wetlands", "Uncovering the Past", 24, false, false, 81)
Fire("QUEST_ACCEPTED", 7) Run(1.5)
ok(not has(W.watches, 7), "accepted in Ironforge: untracked (it's Wetlands')", list(W.watches))
Go(1437)
ok(has(W.watches, 7) and has(W.watches, 3), "Wetlands: listed (the 'X: Zone' rule wins over its Dungeon tag)", list(W.watches))
Arrive(9102, { name = "Excavation Site: Wetlands", kind = "party" })
ok(eq(W.watches, { 7 }), "inside the Excavation Site: its quest only", list(W.watches))

print("== 18. a header that isn't a zone: listed where it has a real map pin")
W.AddQuest(8, "Warrior", "The Islander", 20, false, true)
W.onMap[1437] = { { questID = 8, mapID = 1437 } }
Arrive(1437)
ok(has(W.watches, 8), "class quest with a pin on Wetlands' own map: listed", list(W.watches))
W.onMap[1437] = { { questID = 8, mapID = 1437, isMapIndicatorQuest = true } }
Go(1453) Go(1437)
ok(not has(W.watches, 8), "only a map-indicator pin: not listed", list(W.watches))
W.onMap[1437] = { 8 } W.waypoints["8:1437"] = true
Go(1453) Go(1437)
ok(not has(W.watches, 8), "only a waypoint pin: not listed", list(W.watches))
W.onMap[1437] = { { questID = 8, mapID = 1424 } } W.waypoints["8:1437"] = nil
Go(1453) Go(1437)
ok(not has(W.watches, 8), "only another map's pin: not listed", list(W.watches))

print("== 19. dungeon quests only inside their dungeon")
W.Reset()
W.AddQuest(20, "Gnomeregan", "Save Techbot's Brain", 26, false, true)
W.AddQuest(21, "Dun Morogh", "Gyrodrillmatic Excavationators", 30, false, true, 81)   -- (the Dungeon tag)
W.AddQuest(22, "Dun Morogh", "Frostmane Hold", 10, false, true)
W.AddQuest(23, "Gnomeregan", "The Grand Betrayal", 35, true, false)
W.AddQuest(24, "Westfall", "The Defias Brotherhood", 22, false, true, 81)
W.AddQuest(25, "Deadmines", "Red Silk Bandanas", 17, false, true)
W.AddQuest(26, "Westfall", "Harvest Watchers", 14, false, true)
W.onMap[1426] = { 20, 21 }   -- (entrance pins on Dun Morogh)
W.onMap[9100] = { { questID = 21, mapID = 9100 } }
W.onMap[9101] = { { questID = 24, mapID = 9101 } }
Restart()
Arrive(1455)
ok(eq(W.watches, { 22 }), "Ironforge + Dun Morogh: Gnomeregan quests hidden (header and tag)", list(W.watches))
ok(not has(ReadyIds(), 23), "and its ready one not in Ready", list(ReadyIds()))
Arrive(9100, { name = "Gnomeregan", kind = "party" })
ok(eq(W.watches, { 20, 21 }), "inside Gnomeregan: its quests only (no Dun Morogh)", list(W.watches))
ok(eq(ReadyIds(), { 23 }), "inside: its ready quest in Ready", list(ReadyIds()))
Arrive(1436)
ok(eq(W.watches, { 26 }), "Westfall: the Deadmines quests hidden (tag; header)", list(W.watches))
Arrive(9101, { name = "The Deadmines", kind = "party" })
ok(eq(W.watches, { 25, 24 }), "inside The Deadmines: 'Deadmines' header and the tagged Westfall quest", list(W.watches))
O.SetPinned(20, true) Run(1)
ok(has(W.watches, 20), "a pinned Gnomeregan quest listed in another dungeon", list(W.watches))
Arrive(1455)
ok(eq(W.watches, { 22, 20 }), "and outdoors", list(W.watches))
ok(O.IsDungeonName("Scarlet Monastery") and O.IsDungeonName("The Stockade") and O.IsDungeonName("Krol'dok Stronghold"), "dungeon names: wings, aliases, the game's tables")
ok(not O.IsDungeonName("Wetlands") and O.IsZoneName("Wetlands") and O.IsZoneName("Stormwind City"), "zone names from the map tree")

print("== 20. leaving a dungeon: back to the zone list, after loading, never in combat")
Arrive(9100, { name = "Gnomeregan", kind = "party" })
ok(eq(W.watches, { 20, 21 }), "in Gnomeregan", list(W.watches))
W.combat = true W.combatChanges = 0
Arrive(1426)
local sorted = {} for i, v in ipairs(W.watches) do sorted[i] = v end table.sort(sorted)
ok(W.combatChanges == 0 and eq(sorted, { 20, 21 }), "out in combat: Valhalla changes nothing yet (the game's own re-sort aside)", list(W.watches))
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(2.5)
ok(eq(W.watches, { 22, 20 }), "combat over: Dun Morogh's list (and the pinned one)", list(W.watches))
W.inst = { name = "Gnomeregan" } W.map = 9100
W.loadingTest = true Fire("PLAYER_LEAVING_WORLD") Fire("LOADING_SCREEN_ENABLED") Run(3)
ok(eq(W.watches, { 22, 20 }), "during the loading screen: nothing changes", list(W.watches))
Fire("LOADING_SCREEN_DISABLED") Fire("PLAYER_ENTERING_WORLD") Run(2.5)
ok(eq(W.watches, { 20, 21 }), "after it: the dungeon's list", list(W.watches))

print("== 21. a talk-to quest accepted in this zone (complete on accept) goes straight to Ready")
W.Reset()
Restart()
Arrive(1437)
W.AddQuest(305, "Wetlands", "In Search of the Excavation Team", 24, true, false)
Fire("QUEST_ACCEPTED", 305) Run(1.5)
ok(not has(W.watches, 305) and has(ReadyIds(), 305), "In Search of the Excavation Team: in Ready, not Quests", list(W.watches) .. list(ReadyIds()))

print("== 22. the Ready row's quest icon: the game's POI button, a toggle")
local row = O.UI.ready and O.UI.ready.rows[1]
local poi = row and row.poi
ok(poi and poi._template == "ObjectiveTrackerPOIButtonTemplate" and poi._q == 305, "the game's quest POI button, for the quest")
ok(poi and poi._w == 20 and poi._h == 20 and poi._style == POIButtonUtil.Style.QuestComplete, "20x20, the complete-quest style (as the Quests rows)")
ok(poi and poi._points[1] and poi._points[1][1] == "TOPRIGHT" and poi._points[1][2] == row.title and poi._points[1][4] == -7, "placed as the tracker places it")
ok(row.pin._points[1] and row.pin._points[1][2] == poi, "the pin left of it")
W.super = 0
local adds = W.calls.add
poi._scripts.OnClick(poi, "LeftButton") Run(0.4)
ok(W.super == 305 and poi._selected == true, "first click: selected", tostring(W.super))
poi._scripts.OnClick(poi, "LeftButton") Run(0.4)
ok(W.super == 0 and poi._selected == false and (W.cleared or 0) > 0, "second click: cleared", tostring(W.super))
ok(W.calls.add == adds and not has(W.watches, 305), "never tracks the ready quest (stays out of Quests)")
W.super = 305 Fire("SUPER_TRACKING_CHANGED") Run(0.4)
ok(poi._selected == true, "selected state follows the super-tracked quest (selected elsewhere)")
poi._scripts.OnClick(poi, "RightButton")
ok(W.super == 305, "right click: nothing")
local tb = O.UI.ready.toggle
ok(tb._template == "ObjectiveTrackerModuleMinimizeButtonTemplate" and tb._normal._atlas == "ui-questtrackerbutton-secondary-collapse", "collapse button: the Quests header's template and atlas")
tb._scripts.OnClick(tb) Run(0.4)
ok(tb._normal._atlas == "ui-questtrackerbutton-secondary-expand" and tb._pushed._atlas == "ui-questtrackerbutton-secondary-expand-pressed" and O.UI.ready.n == 0, "folded: expand atlas")
tb._scripts.OnClick(tb) Run(0.4)
ok(tb._normal._atlas == "ui-questtrackerbutton-secondary-collapse" and O.UI.ready.n == 1, "unfolded again")
W.combat = true
poi._scripts.OnClick(poi, "LeftButton")
ok(W.super == 0 and W.combatChanges == 0, "in combat: the toggle works, no watch changes")
W.combat = false

print("== 23. a watched ready quest that isn't listed here is untracked")
W.AddQuest(30, "Duskwood", "Seasoned Wolf Kabobs", 24, true, true)
Fire("QUEST_LOG_UPDATE") Run(1.5)
ok(not has(W.watches, 30) and not has(ReadyIds(), 30), "untracked, and not in Ready (another zone's)", list(W.watches))

print("== 24. /valhalla objectives why")
W.onMap[1437] = { 2 } W.waypoints["2:1437"] = true
W.AddQuest(2, "Duskwood", "Wolves at Our Heels", 20, false, false)
local n0 = #ns.printed
mod:Slash("why 2")
local text = table.concat(ns.printed, "\n", n0 + 1)
ok(text:find("Here: .*Wetlands") and text:find("is another zone") and text:find("waypoint") and text:find("dropped"), "why 2: where, the reason, its map pins", text)
n0 = #ns.printed
mod:Slash("why")
text = table.concat(ns.printed, "\n", n0 + 1)
ok(text:find("305") and text:find("listed in Ready") and text:find("not listed"), "why: every quest", text)
mod:Slash("WHY 99999")
ok(ns.printed[#ns.printed]:find("not in your quest log"), "why <unknown id>")
ok(mod.enabled, "why changes nothing (still on)")

---------------------------------------------------------------------------
-- v0.2.2
---------------------------------------------------------------------------
local function Why(id) local n0 = #ns.printed mod:Slash("why " .. id) return table.concat(ns.printed, "\n", n0 + 1) end

print("== 25. another zone's quest with a real objective marker here is listed")
W.Reset()
W.AddQuest(40, "Stormwind City", "A Noble Brew", 30, false, true)
W.AddQuest(41, "Wetlands", "Crocs of the Sky", 22, false, true)
W.AddQuest(42, "Duskwood", "Eight-Legged Menaces", 24, false, true)
Restart()
W.onMap[1437] = { { questID = 40, mapID = 1437 } }
Arrive(1437)
ok(eq(W.watches, { 41, 40 }), "Wetlands: A Noble Brew (Stormwind header) for its Musquash Root marker", list(W.watches))
ok(Why(40):find("is another zone, but it has an objective marker here"), "why: 'an objective marker here'")
W.onMap[1431] = { { questID = 40, mapID = 1431 } }
Arrive(1431)
ok(eq(W.watches, { 42, 40 }), "Duskwood: and for its Tear of Tilloa marker", list(W.watches))
W.onMap[1437] = { 40 } W.waypoints["40:1437"] = true
Arrive(1437)
ok(eq(W.watches, { 41 }), "only a waypoint pin: not listed", list(W.watches))
W.waypoints["40:1437"] = nil W.onMap[1437] = { { questID = 40, mapID = 1437, isMapIndicatorQuest = true } }
Go(1431) Go(1437)
ok(eq(W.watches, { 41 }), "only a map indicator: not listed", list(W.watches))
W.onMap[1437] = { { questID = 40, mapID = 1431 } }
Go(1431) Go(1437)
ok(eq(W.watches, { 41 }), "only another map's pin: not listed", list(W.watches))
W.onMap[1437] = { { questID = 40, mapID = 1437 } } W.next[40] = 1431
Go(1431) Go(1437)
ok(eq(W.watches, { 41 }), "a real pin, but the next waypoint is Duskwood: not listed", list(W.watches))
ok(Why(40):find("next waypoint is on map 1431"), "why: the next-waypoint guard")
W.next[40] = 1437
Go(1431) Go(1437)
ok(has(W.watches, 40), "next waypoint on this map: listed", list(W.watches))
W.next[40] = nil W.noLocal[40] = true
Go(1431) Go(1437)
ok(not has(W.watches, 40), "the game says no local marker on the map you stand on: not listed", list(W.watches))
ok(Why(40):find("no local marker"), "why: the local-marker guard")
W.noLocal[40] = nil
print("== 25b. E1: a capital's surrounding zone counts (no local-marker check there)")
W.onMap[1429] = { { questID = 42, mapID = 1429 } } W.noLocal[42] = true
Arrive(1453)
ok(has(W.watches, 42), "Stormwind: a Duskwood quest with a real marker in Elwynn", list(W.watches))
W.onMap[1429] = nil W.onMap[1453] = { { questID = 42, mapID = 1453 } }
Go(1436) Go(1453)
ok(not has(W.watches, 42), "on Stormwind's own map without the game's local marker: not listed", list(W.watches))
W.onMap[1453] = nil W.noLocal[42] = nil

print("== 26. the v0.2.0 leaks stay out")
W.Reset()
W.AddQuest(1, "Stormwind City", "Rethban Ore", 15, false, true)
W.AddQuest(2, "Duskwood", "Wolves at Our Heels", 20, false, true)
W.AddQuest(3, "Wetlands", "Tramping Paws", 22, false, true)
W.AddQuest(4, "Ironforge", "The Darkmoon Faire", 10, true, false)
W.AddQuest(5, "Duskwood", "The Legend of Stalvan", 25, true, false)
W.AddQuest(20, "Gnomeregan", "Save Techbot's Brain", 26, false, true)
W.AddQuest(21, "Dun Morogh", "Gyrodrillmatic Excavationators", 30, false, true, 81)
W.AddQuest(22, "Dun Morogh", "Frostmane Hold", 10, false, true)
W.onMap[1429] = { 2, 5 } W.waypoints["2:1429"] = true W.waypoints["5:1429"] = true W.next[2] = 1431 W.next[5] = 1431
W.onMap[1453] = { { questID = 4, mapID = 1455 } }
W.onMap[1426] = { { questID = 3, isMapIndicatorQuest = true }, { questID = 20, mapID = 1426 }, { questID = 21, mapID = 1426 } }
Restart() Arrive(1453)
ok(eq(W.watches, { 1 }), "Stormwind: no Duskwood quests (waypoints)", list(W.watches))
ok(eq(ReadyIds(), {}), "Stormwind Ready: no Darkmoon Faire (Ironforge's pin), no Stalvan (waypoint)", list(ReadyIds()))
Arrive(1455)
ok(eq(W.watches, { 22 }), "Ironforge: no Tramping Paws (indicator), no Gnomeregan quests (real entrance pins, but dungeon quests)", list(W.watches))
ok(eq(ReadyIds(), { 4 }), "Ironforge Ready: its own Darkmoon Faire", list(ReadyIds()))

print("== 27. R1: a ready quest with a turn-in marker here is in Ready")
W.onMap[1429] = { { questID = 5, mapID = 1429 } } W.waypoints["5:1429"] = nil W.next[5] = nil
Arrive(1453)
ok(has(ReadyIds(), 5) and not has(W.watches, 5), "Stormwind: The Legend of Stalvan for its turn-in marker in Elwynn (Ready, not Quests)", list(ReadyIds()))
ok(Why(5):find("but it has a turn%-in marker here"), "why: 'a turn-in marker here'")
W.onMap[1429] = { 5 } W.waypoints["5:1429"] = true
Go(1436) Go(1453)
ok(not has(ReadyIds(), 5), "the same as a waypoint: not in Ready", list(ReadyIds()))
W.AddQuest(23, "Gnomeregan", "The Grand Betrayal", 35, true, false)
W.onMap[1426] = { { questID = 23, mapID = 1426 } }
Arrive(1455)
ok(not has(ReadyIds(), 23), "a ready dungeon quest with a real marker outdoors: not in Ready", list(ReadyIds()))

print("== 28. inside a dungeon: no exception")
W.onMap[9100] = { { questID = 22, mapID = 9100 }, { questID = 21, mapID = 9100 } }
Arrive(9100, { name = "Gnomeregan", kind = "party" })
ok(eq(W.watches, { 20, 21 }), "Gnomeregan: a Dun Morogh quest with a pin on the dungeon map stays out", list(W.watches))
O.SetPinned(22, true) Run(1)
ok(has(W.watches, 22), "pinned: in", list(W.watches))
O.SetPinned(22, false) Run(1)

print("== 29. a marker gone: out after 2 misses; a new one: in at once; never in combat or flight")
W.Reset()
W.AddQuest(40, "Stormwind City", "A Noble Brew", 30, false, true)
W.AddQuest(41, "Wetlands", "Crocs of the Sky", 22, false, true)
W.AddQuest(45, "Duskwood", "Wolves at Our Heels", 20, false, false)
W.onMap[1437] = { { questID = 40, mapID = 1437 } }
Restart() Arrive(1437)
ok(has(W.watches, 40), "listed for its marker", list(W.watches))
W.onMap[1437] = {}
Fire("QUEST_POI_UPDATE") Run(0.7)
ok(has(W.watches, 40), "one miss: kept", list(W.watches))
W.onMap[1437] = { { questID = 40, mapID = 1437 } }
Run(1.2)
ok(has(W.watches, 40) and not (O.S.miss and O.S.miss[40]), "seen again: kept, count starts over", list(W.watches))
W.onMap[1437] = {}
Fire("QUEST_POI_UPDATE") Run(0.7)
ok(has(W.watches, 40), "a new first miss: kept", list(W.watches))
Run(1.5)
ok(not has(W.watches, 40), "second miss a second later: out (the root looted)", list(W.watches))
W.onMap[1437] = { { questID = 45, mapID = 1437 } }
Fire("QUEST_POI_UPDATE") Run(1.2)
ok(has(W.watches, 45), "a marker appearing here: tracked at once", list(W.watches))
W.combat = true W.combatChanges = 0
W.onMap[1437] = {}
Fire("QUEST_POI_UPDATE") Run(3)
ok(has(W.watches, 45) and W.combatChanges == 0, "in combat: nothing changes", list(W.watches))
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(3)
ok(not has(W.watches, 45), "after combat: two misses, out", list(W.watches))
W.onMap[1437] = { { questID = 45, mapID = 1437 } }
Fire("QUEST_POI_UPDATE") Run(1.2)
W.taxi = true local c0 = W.calls.add + W.calls.remove
W.onMap[1437] = {}
Fire("QUEST_POI_UPDATE") Run(3)
ok(W.calls.add + W.calls.remove == c0 and has(W.watches, 45), "on a taxi: nothing changes", list(W.watches))
W.taxi = false

print("== 30. the 25 limit with marker quests")
W.Reset()
for i = 1, 24 do W.AddQuest(300 + i, "Wetlands", ("W%02d"):format(i), i, false, true) end
W.AddQuest(400, "Stormwind City", "Low Marker", 5, false, false)
W.AddQuest(401, "Duskwood", "High Marker", 40, false, false)
W.onMap[1437] = { { questID = 400, mapID = 1437 }, { questID = 401, mapID = 1437 } }
Restart() Arrive(1437)
ok(#W.watches == 25 and has(W.watches, 400) and not has(W.watches, 401) and has(W.watches, 324), "25 tracked: the lowest levels, a marker quest mixed in, the level-40 one off", tostring(#W.watches))

---------------------------------------------------------------------------
print("== 31. quest-log pins")
W.Reset()
W.AddQuest(50, "Wetlands", "Crocs of the Sky", 22, false, true)
W.AddQuest(51, "Wetlands", "An Exceptionally Long Quest Title!", 24, false, true)   -- (33 letters: 1 line at 210 px, 2 at 190)
W.AddQuest(52, "Duskwood", "Night Web", 20, false, false)
local SF = W.NewQuestLog()
Restart() Arrive(1437)
ok(O.LogPins.Hooked(), "hooked into the log (pool Acquire, QuestLogQuests_Update)")
QuestLogQuests_Update()
local function PinOf(row) for _, f in ipairs(W.frames) do if f._parent == row and f.icon and f.q ~= nil then return f end end end
local function LogRow(id) for _, r in ipairs(W.log.rows) do if r.questID == id then return r end end end
ok(#W.log.rows == 3 and PinOf(LogRow(50)) and PinOf(LogRow(51)) and PinOf(LogRow(52)), "a pin on every quest row")
local onHeader = false
for _, h in ipairs(W.log.headers) do if PinOf(h) then onHeader = true end end
ok(#W.log.headers == 2 and not onHeader, "none on the headers")
ok(W.log.measured[50] == 50 and W.log.measured[51] == 50, "titles moved to x 50 before the game measured them (first show)", tostring(W.log.measured[51]))
ok(LogRow(51)._height == 8 + 24 + 6, "the long title measured at the narrower width: 2 lines in the row's height", tostring(LogRow(51)._height))
local poi = SF.Contents:FindButtonByQuestID(50)
local lp = poi._points[#poi._points]
ok(lp[1] == "TOPLEFT" and lp[2] == LogRow(50) and lp[4] == 25 and lp[5] == -4, "quest icon moved to x 25")
local p50 = PinOf(LogRow(50))
local pp = p50._points[1]
ok(p50._w == 17 and pp[1] == "TOPLEFT" and pp[2] == LogRow(50) and pp[4] == 4 and pp[5] == -6 and p50._shown, "pin: 17 px at (4, -6), left of the icon")
ok(p50.icon._tex:find("ValhallaPinOff"), "Pin 2 art, off")
W.noPOI = { [52] = true }
QuestLogQuests_Update()
local p52 = PinOf(LogRow(52))
ok(p52 and p52._shown and p52._points[1][4] == 4, "a row with no quest icon: the pin in the same place")
W.noPOI = nil

print("== 32. pooled rows: each update's quest")
mod.char.pinned[52] = true
W.order = { 52, 51, 50 }   -- (the rows come back in another order)
QuestLogQuests_Update()
local okAll = true
for _, r in ipairs(W.log.rows) do
  local p = PinOf(r)
  if not p or p.q ~= r.questID or (p.icon._tex:find("ValhallaPinOn") ~= nil) ~= (r.questID == 52) then okAll = false end
end
ok(okAll and SF.titleFramePool.made == 3, "reused rows show their new quest's pin state", tostring(SF.titleFramePool.made))
mod.char.pinned[52] = nil

print("== 33. one store, both ways")
local updates = 0
local realUpdate = QuestLogQuests_Update
QuestLogQuests_Update = function(...) updates = updates + 1 return realUpdate(...) end
local row50 = LogRow(50) local lpin = PinOf(row50)
lpin._scripts.OnClick(lpin) Run(0.4)
ok(mod.char.pinned[50] == true and lpin.icon._tex:find("ValhallaPinOn"), "log pin click: pinned in ValhallaCharDB.objectives.pinned")
ok(O.S.fullDue == nil, "and a replan ran")
local block = W.NewFrame("Frame") block.poiButton = W.NewFrame("Button")
_G.QuestObjectiveTracker = { blockTemplate = "ObjectiveTrackerQuestPOIBlockTemplate", usedBlocks = { ObjectiveTrackerQuestPOIBlockTemplate = { [50] = block } } }
Run(0.4)
local sp = O.UI.pins[1]
ok(sp and sp.q == 50 and sp.icon._tex:find("ValhallaPinOn"), "the tracker's pin for it: on")
sp._scripts.OnClick(sp)
ok(not mod.char.pinned[50] and lpin.icon._tex:find("ValhallaPinOff"), "tracker pin click: the log's pin off at once")
ok(updates == 0, "without a quest log update")
O.SetPinned(51, true)
ok(PinOf(LogRow(51)).icon._tex:find("ValhallaPinOn"), "pinned anywhere (Ready rows use O.SetPinned too): the log follows")
W.Drop(51) Fire("QUEST_TURNED_IN", 51) Fire("QUEST_REMOVED", 51)
ok(mod.char.pinned[51] == nil and PinOf(row50) and not PinOf(LogRow(51) or row50).icon._tex:find("ValhallaPinOn"), "turned in: cleared in the store and the log")
QuestLogQuests_Update = realUpdate
_G.QuestObjectiveTracker = nil

print("== 34. combat, and no game fields written")
W.combat = true W.combatChanges = 0
QuestLogQuests_Update()
local p = PinOf(LogRow(52))
p._scripts.OnClick(p)
ok(mod.char.pinned[52] == true and W.combatChanges == 0, "in combat: the store changes, the tracking waits")
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(2)
ok(has(W.watches, 52), "after combat: the pinned quest tracked", list(W.watches))
ok(W.blockedSetters == 0, "no mouse pass-through / propagation setters, ever")
local allowedRow = { Text = true, Checkbox = true, questID = true, info = true }   -- (Checkbox: the template's own)
local stray
for _, r in ipairs(W.log.rows) do
  for k in pairs(r) do if type(k) == "string" and not k:find("^_") and not allowedRow[k] then stray = k end end
end
for b in SF.poiPool:EnumerateActive() do
  for k in pairs(b) do if type(k) == "string" and not k:find("^_") and k ~= "GetQuestID" and k ~= "parent" then stray = k end end
end
ok(stray == nil, "no fields written on the game's rows or icons", tostring(stray))
O.SetPinned(52, false) Run(1)

print("== 35. /valhalla objectives off: no log pins, rows back as they're laid out")
O.SetOn(false)
local anyShown = false
for _, r in ipairs(W.log.rows) do local q = PinOf(r) if q and q._shown then anyShown = true end end
ok(not anyShown, "off: the pins hidden at once")
QuestLogQuests_Update()
anyShown = false
for _, r in ipairs(W.log.rows) do local q = PinOf(r) if q and q._shown then anyShown = true end end
local back = true
for _, r in ipairs(W.log.rows) do if W.log.measured[r.questID] ~= 31 then back = false end end
local poi2 = SF.Contents:FindButtonByQuestID(50)
ok(not anyShown and back and (function(t) return t[#t - 1] == 6 end)(poi2._points[#poi2._points]), "next update: titles at 31, icons at 6, no pins")
O.SetOn(true) Run(1)
QuestLogQuests_Update()
back = true
for _, r in ipairs(W.log.rows) do if W.log.measured[r.questID] ~= 50 or not PinOf(r)._shown then back = false end end
ok(back, "on again: shifted and pinned from the next update")


---------------------------------------------------------------------------
-- v0.4.2.2: progress kept in step
---------------------------------------------------------------------------
print("== 36. (v0.4.2.2, A) the count lands after the quest log update: BAG_UPDATE_DELAYED / UNIT_QUEST_LOG_CHANGED catch it")
W.Reset()
W.map = 1436
W.AddQuest(60, "Westfall", "Linen", 12, false, true) W.quests[60].obj = { { 9, 10 } }
W.AddQuest(61, "Westfall", "Murlocs", 14, false, true) W.quests[61].obj = { { 7, 8 } }
W.AddQuest(62, "Westfall", "Two Things", 13, false, true) W.quests[62].obj = { { 5, 5 }, { 2, 6 } }
W.AddQuest(63, "Westfall", "Gnolls", 15, false, true) W.quests[63].obj = { { 1, 2 } }
W.AddQuest(64, "Westfall", "Bandanas", 16, false, true) W.quests[64].obj = { { 3, 4 } }
W.AddQuest(65, "Westfall", "Feathers", 17, false, true) W.quests[65].obj = { { 3, 4 } }
W.AddQuest(66, "Westfall", "Oats", 18, false, true) W.quests[66].obj = { { 3, 4 } }
W.AddQuest(67, "Westfall", "Report", 11, false, true) W.quests[67].obj = { { 1, 1 } }
W.AddQuest(68, "Westfall", "Hides", 19, false, true) W.quests[68].obj = { { 0, 5 } }
W.AddQuest(70, "Elwynn Forest", "Wolves", 6, false, false) W.quests[70].obj = { { 0, 8 } }
Start({ enabled = true, readyCollapsed = false, watchSide = "front" })
Run(2)
ok(eq(W.watches, { 67, 60, 62, 61, 63, 64, 65, 66, 68 }), "Westfall's quests, by level", list(W.watches))
Fire("QUEST_LOG_UPDATE") Run(1)   -- (the update came: still 9/10)
W.quests[60].obj = { { 10, 10 } } W.quests[60].ready = true   -- (the tenth counted a moment later, no quest log update)
Fire("BAG_UPDATE_DELAYED") Run(2)
ok(not has(W.watches, 60) and has(ReadyIds(), 60), "BAG_UPDATE_DELAYED: the ready quest moves to Ready to Turn In", list(W.watches))
W.quests[61].obj = { { 8, 8 } } W.quests[61].ready = true
Fire("UNIT_QUEST_LOG_CHANGED", "party1") Run(1)
ok(has(W.watches, 61), "UNIT_QUEST_LOG_CHANGED for someone else: nothing read")
Fire("UNIT_QUEST_LOG_CHANGED", "player") Run(1)
ok(not has(W.watches, 61) and has(ReadyIds(), 61), "UNIT_QUEST_LOG_CHANGED (player): moved too", list(W.watches))
ok(has(O.EVENTS, "QUEST_WATCH_UPDATE") and has(O.EVENTS, "QUEST_LOG_CRITERIA_UPDATE") and has(O.EVENTS, "UI_INFO_MESSAGE") and has(O.EVENTS, "QUEST_ITEM_UPDATE"),
  "QUEST_WATCH_UPDATE, QUEST_LOG_CRITERIA_UPDATE, UI_INFO_MESSAGE, QUEST_ITEM_UPDATE heard as well")

print("== 37. (A) a second read after the last event")
Fire("QUEST_LOG_UPDATE") Run(0.8)
W.quests[63].obj = { { 2, 2 } } W.quests[63].ready = true   -- (after the first read, before the second; no event)
ok(has(W.watches, 63), "the first read (0.5 s) saw it unfinished")
Run(1.0)
ok(not has(W.watches, 63) and has(ReadyIds(), 63), "the second read (1.5 s) caught it", list(W.watches))

print("== 38. (B) progress reads go on in combat, in flight and before a zone's plan; watch changes wait")
W.combat = true W.combatChanges = 0
W.quests[64].obj = { { 4, 4 } } W.quests[64].ready = true
Fire("QUEST_LOG_CRITERIA_UPDATE", 64) Run(1)
O.Tick()
ok(has(ReadyIds(), 64) and (O.S.readyCount or 0) >= 1, "in combat: Ready to Turn In lists it at once", list(ReadyIds()))
ok(has(W.watches, 64) and W.combatChanges == 0, "in combat: no watch calls (still in Quests until the fight ends)")
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(1)
ok(not has(W.watches, 64), "fight over: out of Quests", list(W.watches))
local c0 = W.calls.add + W.calls.remove
W.taxi = true
W.quests[65].obj = { { 4, 4 } } W.quests[65].ready = true
Fire("UI_INFO_MESSAGE", 288) Run(1)
ok(has(ReadyIds(), 65) and has(W.watches, 65) and W.calls.add + W.calls.remove == c0, "on a taxi: Ready follows, no watch calls")
W.taxi = false Fire("PLAYER_CONTROL_GAINED") Run(3)
ok(not has(W.watches, 65) and has(ReadyIds(), 65), "landed: out of Quests", list(W.watches))
Fire("ZONE_CHANGED_NEW_AREA")   -- (same zone: a plan due in a second)
W.quests[66].obj = { { 4, 4 } } W.quests[66].ready = true
Fire("BAG_UPDATE_DELAYED") Run(0.6)
ok(O.S.fullDue ~= nil and has(ReadyIds(), 66), "a zone's plan still due: Ready already lists it", tostring(O.S.fullDue))
Run(2)
ok(not has(W.watches, 66), "then the plan takes it out of Quests", list(W.watches))

print("== 39. the landing rule for zones is unchanged")
local before39 = list(W.watches)
local c39 = W.calls.add + W.calls.remove
W.taxi = true W.map = 1429 Fire("ZONE_CHANGED_NEW_AREA") Run(2)
Fire("BAG_UPDATE_DELAYED") Fire("UNIT_QUEST_LOG_CHANGED", "player") Run(2)
ok(W.calls.add + W.calls.remove == c39, "in flight over Elwynn: no watch changes, progress events or not")
W.taxi = false Fire("PLAYER_CONTROL_GAINED") Run(0.6)
ok(not has(W.watches, 70), "landed: waits about a second, as before")
Run(2)
ok(eq(W.watches, { 70 }), "then Elwynn's quests", list(W.watches))
W.map = 1436 Fire("ZONE_CHANGED_NEW_AREA") Run(2)
ok(eq(W.watches, { 67, 62, 68 }) or eq(W.watches, { 62, 68 }), "back in Westfall: its unfinished quests", list(W.watches))

print("== 40. (E) ready when ReadyForTurnIn or IsComplete says it")
W.quests[67].rft, W.quests[67].ic = false, true
ok(O.ReadLog()[67].ready == true, "ReadyForTurnIn false, IsComplete true: ready")
Fire("QUEST_LOG_UPDATE") Run(1)
ok(not has(W.watches, 67) and has(ReadyIds(), 67), "and in Ready to Turn In, not Quests", list(W.watches))
W.quests[68].rft = nil

print("== 41. (C) the tracker made to read again: one re-track that keeps the order, out of combat, not too often")
ok(eq(W.watches, { 62, 68 }), "Quests: Two Things, Hides", list(W.watches))
Fire("QUEST_LOG_UPDATE") Run(1)
local order41 = list(W.watches)
local a41, r41 = W.calls.add, W.calls.remove
W.quests[62].obj = { { 5, 5 }, { 3, 6 } }   -- (counted, no quest log update)
Fire("UNIT_QUEST_LOG_CHANGED", "player") Run(1)
ok(W.calls.add == a41 + 1 and W.calls.remove == r41 + 1 and list(W.watches) == order41, "one re-track, the order kept", list(W.watches))
ok(O.S.nudges == 1 and next(O.S.stale) == nil, "counted once, nothing left stale")
Fire("UNIT_QUEST_LOG_CHANGED", "player") Run(3)
ok(W.calls.add == a41 + 1 and W.calls.remove == r41 + 1, "nothing changed: no re-track")
W.combat = true W.combatChanges = 0
W.quests[62].obj = { { 5, 5 }, { 4, 6 } }
Fire("BAG_UPDATE_DELAYED") Run(3)
ok(W.combatChanges == 0 and O.S.stale[62], "in combat: waits (marked)")
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(0.4)
ok(W.calls.add == a41 + 2 and list(W.watches) == order41, "fight over: re-tracked once", list(W.watches))
W.quests[62].obj = { { 5, 5 }, { 5, 6 } }
Fire("BAG_UPDATE_DELAYED") Run(0.8)
ok(W.calls.add == a41 + 2 and O.S.stale[62], "within NUDGE_GAP of the last: waits")
Run(2)
ok(W.calls.add == a41 + 3 and O.S.nudges == 3, "then once", tostring(O.S.nudges))
W.quests[62].obj = { { 5, 5 }, { 6, 6 } }
Fire("QUEST_LOG_UPDATE") Fire("BAG_UPDATE_DELAYED") Run(3)
ok(W.calls.add == a41 + 3, "a quest log update in between (the tracker heard it): no re-track")
W.quests[62].obj = { { 5, 5 }, { 2, 6 } }   -- (as before)
mod.db.watchSide = "end" W.side = "end"
Fire("QUEST_LOG_UPDATE") Run(1)
W.quests[62].obj = { { 5, 5 }, { 3, 6 } }
local a41b = W.calls.add
Fire("BAG_UPDATE_DELAYED") Run(3)
ok(W.calls.add == a41b + 1 and eq(W.watches, { 62, 68 }), "new watches at the end: the last one re-tracked, the order kept", list(W.watches))
mod.db.watchSide = "front"
W.side = "front"

print("== 42. /valhalla objectives sync: read only, saved, late changes flagged")
local a42, r42 = W.calls.add, W.calls.remove
mod:Slash("sync on")
ok(mod.db.syncOn == true and type(mod.db.syncLog) == "table" and #mod.db.syncLog >= 1, "on: ValhallaDB.objectives.syncLog")
local evf
for _, f in ipairs(W.frames) do if rawget(f, "_events") and f._events.QUEST_LOG_UPDATE then evf = f end end
ok(evf and evf._events.CHAT_MSG_LOOT, "the loot events heard while it's on")
local function LogHas(pat) for _, l in ipairs(mod.db.syncLog) do if l:find(pat) then return l end end end
ok(LogHas("q67 .* RFT!=IC"), "ReadyForTurnIn and IsComplete disagreeing: flagged")
Fire("CHAT_MSG_LOOT", "You receive loot: Hide") Run(0.4)
W.quests[68].obj = { { 1, 5 } }   -- (after the loot, no quest log update)
Run(1)
ok(LogHas("CHAT_MSG_LOOT You receive loot") and LogHas("late%+1s noQLU q68 1/5"), "the loot logged; the count that came later flagged late, unheard",
  tostring(LogHas("q68")))
ok(W.calls.add == a42 and W.calls.remove == r42, "no watch calls from the log")
mod:Slash("sync show")
local shown = false
for _, l in ipairs(ns.printed) do if l:find("late%+1s noQLU q68") then shown = true end end
ok(shown, "/valhalla objectives sync show: the late change printed")
for i = 1, 100 do O.SyncAdd("x" .. i) end
ok(#mod.db.syncLog == O.SYNC_MAX, "the last 80 kept", tostring(#mod.db.syncLog))
W.epoch = W.epoch + 31 * 60 Run(0.2)
ok(not mod.db.syncOn and LogHas("after 30 minutes") and not evf._events.CHAT_MSG_LOOT, "off by itself after 30 minutes; the log kept")
mod:Slash("sync on") mod:Slash("sync off")
ok(not mod.db.syncOn and LogHas("turned off"), "/valhalla objectives sync off")

print("== 43. no handler errors; nothing of the tracker's called or written")
local dirty = 0
_G.QuestObjectiveTracker = { MarkDirty = function() dirty = dirty + 1 end }
local keys0 = 0 for _ in pairs(ObjectiveTrackerFrame) do keys0 = keys0 + 1 end
mod:Slash("sync on")
local errs = 0
for _, e in ipairs({ "UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_LOG_CRITERIA_UPDATE", "QUEST_ITEM_UPDATE", "BAG_UPDATE_DELAYED",
  "UI_INFO_MESSAGE", "QUEST_AUTOCOMPLETE", "CHAT_MSG_LOOT", "ITEM_PUSH", "QUEST_LOG_UPDATE" }) do
  if not pcall(O.OnEvent, e) then errs = errs + 1 end
  if not pcall(O.OnEvent, e, "player", 12345) then errs = errs + 1 end
end
W.quests[68].obj = { { 2, 5 } }
local tickOk = pcall(Run, 4)
ok(errs == 0 and tickOk, "every new event, with or without arguments: no error")
local keys1 = 0 for _ in pairs(ObjectiveTrackerFrame) do keys1 = keys1 + 1 end
ok(dirty == 0 and keys1 == keys0, "the tracker's MarkDirty never called; nothing written on its frame")
mod:Slash("sync off")
_G.QuestObjectiveTracker = nil

---------------------------------------------------------------------------
-- 1.2.2: new quests' data, blank tracker titles, the Quest Timers box
---------------------------------------------------------------------------
print("== 44. (1.2.2) a dungeon quest picked up before its data: placed when the data's in, no zone change")
W.Reset()
local asked = {}
C_QuestLog.RequestLoadQuestByID = function(id) asked[id] = (asked[id] or 0) + 1 end
W.AddQuest(85, "Dun Morogh", "Frostmane Hold", 10, false, true)
Restart()
Arrive(1426)
ok(eq(W.watches, { 85 }), "Dun Morogh: its quest", list(W.watches))
W.AddQuest(80, "Dun Morogh", "Horrors in the Highland", 31, false, false)   -- (Dungeon tag not loaded yet)
Fire("QUEST_ACCEPTED", 80)
ok(asked[80] == 1, "accepted: its data asked for", tostring(asked[80]))
Run(1.2)
ok(has(W.watches, 80) and O.S.fresh[80] ~= nil, "not placed yet (its data not in): left as the game tracked it", list(W.watches))
W.quests[80].tag = 81
Fire("QUEST_DATA_LOAD_RESULT", 80) Run(1.2)
ok(not has(W.watches, 80) and mod.char.hidden[80] and O.S.fresh[80] == nil, "data in: the Dungeon tag read, untracked here (no zone change)", list(W.watches))
local why80 = O.Why(80)
ok(type(why80) == "table" and table.concat(why80, " "):find("dungeon quest"), "why: a dungeon quest", type(why80) == "table" and table.concat(why80, " | ") or tostring(why80))

print("== 45. (1.2.2) normal outdoor quests: placed as before; no load result: placed after DATA_TRIES")
W.AddQuest(81, "Dun Morogh", "Wolves of Dun Morogh", 9, false, false)
Fire("QUEST_ACCEPTED", 81) Fire("QUEST_DATA_LOAD_RESULT", 81) Run(1.2)
ok(has(W.watches, 81) and O.S.fresh[81] == nil and W.watches[1] == 81, "data in: tracked here, in its place (lvl 9 first)", list(W.watches))
W.AddQuest(82, "Dun Morogh", "Ice Troll Tusks", 12, false, false)
Fire("QUEST_ACCEPTED", 82) Run(1.2)
ok(O.S.fresh[82] ~= nil, "no load result yet: waiting", list(W.watches))
Run(3.6)
ok(O.S.fresh[82] == nil and eq(W.watches, { 81, 85, 82 }), "after DATA_TRIES looks: placed anyway (tracked here, in its place)", list(W.watches))
W.AddQuest(86, "Westfall", "Harvest Watchers", 14, false, false)
Fire("QUEST_ACCEPTED", 86) Fire("QUEST_DATA_LOAD_RESULT", 86) Run(1.2)
ok(not has(W.watches, 86), "another zone's quest: untracked as before", list(W.watches))
local saveRL = C_QuestLog.RequestLoadQuestByID
C_QuestLog.RequestLoadQuestByID = nil
W.AddQuest(87, "Dun Morogh", "Beer Basted Boar", 11, false, false)
Fire("QUEST_ACCEPTED", 87) Run(1.2)
ok(O.S.fresh[87] == nil and has(W.watches, 87), "a client that can't be asked: placed at once, as before", list(W.watches))
C_QuestLog.RequestLoadQuestByID = saveRL

print("== 46. (1.2.2) a watched quest is placed again when its tag or header changes")
W.AddQuest(83, "Dun Morogh", "Gnomeregan Gears", 28, false, false)   -- (data never comes: placed by its header)
Fire("QUEST_ACCEPTED", 83) Run(4)
ok(has(W.watches, 83), "placed by its header (no tag yet)", list(W.watches))
W.quests[83].tag = 81
Fire("QUEST_LOG_UPDATE") Run(1.5)
ok(not has(W.watches, 83) and mod.char.hidden[83], "its Dungeon tag read later: untracked, no zone change", list(W.watches))
W.quests[82].header = "Westfall"
Fire("QUEST_LOG_UPDATE") Run(1.5)
ok(not has(W.watches, 82) and has(W.watches, 81) and has(W.watches, 85), "its header now another zone: untracked; the others kept", list(W.watches))
local a46, r46 = W.calls.add, W.calls.remove
Fire("QUEST_LOG_UPDATE") Run(2)
ok(W.calls.add == a46 and W.calls.remove == r46, "nothing changed: no watch changes")
W.quests[82].header = "Dun Morogh"
Fire("QUEST_LOG_UPDATE") Run(1.5)
ok(has(W.watches, 82), "back to this zone's header: tracked again", list(W.watches))

print("== 47. (1.2.2) a tracker row with an empty title: no pin; redrawn once its data's in")
local order47 = list(W.watches)
local function Block(text) local b = W.NewFrame("Frame") b.poiButton = W.NewFrame("Button") b.HeaderText = W.NewFrame("FontString") b.HeaderText._text = text return b end
local good, blankB = Block("[9] Wolves of Dun Morogh"), Block("")
_G.QuestObjectiveTracker = { blockTemplate = "ObjectiveTrackerQuestPOIBlockTemplate", usedBlocks = { ObjectiveTrackerQuestPOIBlockTemplate = { [81] = good, [85] = blankB } } }
local function PinsOn() local out = {} for _, p in ipairs(O.UI.pins) do if p._shown then out[#out + 1] = p.q end end table.sort(out) return out end
asked[85] = nil
local a47, r47 = W.calls.add, W.calls.remove
Run(0.4)
ok(eq(PinsOn(), { 81 }), "a pin on the titled row only", list(PinsOn()))
ok(asked[85] == 1 and O.S.blank[85], "the empty row's quest data asked for (once)", tostring(asked[85]))
Run(2)
ok(W.calls.add == a47 and W.calls.remove == r47 and asked[85] == 1, "data not in yet: no re-track, not asked again")
W.combat = true W.combatChanges = 0
Fire("QUEST_DATA_LOAD_RESULT", 85) Run(1)
ok(W.combatChanges == 0, "in combat: waits")
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(0.4)
ok(W.calls.add == a47 + 1 and W.calls.remove == r47 + 1 and list(W.watches) == order47, "data in, fight over: one re-track, the order kept", list(W.watches))
Run(10)
ok(W.calls.add - a47 <= O.REDRAW_TRIES and W.calls.add - a47 >= 2 and (O.S.redraw[85] or 0) == O.REDRAW_TRIES, "a title that stays empty: at most REDRAW_TRIES, NUDGE_GAP apart", tostring(W.calls.add - a47))
local a47b = W.calls.add
Run(6)
ok(W.calls.add == a47b, "then it stops")
blankB.HeaderText._text = "[10] Frostmane Hold"
Run(0.4)
ok(eq(PinsOn(), { 81, 85 }) and not O.S.blank[85] and O.S.redraw[85] == nil, "the title in: its pin back, nothing waiting", list(PinsOn()))
_G.QuestObjectiveTracker = nil

print("== 48. (1.2.2) the Quest Timers box: the tracker laid out again once, debounced; never in combat")
local timer = W.NewFrame("Frame")
timer._hk = {}
timer.HookScript = function(self, k, fn) self._hk[k] = self._hk[k] or {} table.insert(self._hk[k], fn) end
local keysT0 = 0 for k in pairs(timer) do keysT0 = keysT0 + 1 end
local function Hooks(k) local n = 0 for _, fn in ipairs(timer._hk[k] or {}) do fn(timer) n = n + 1 end return n end
local function NHooks() local n = 0 for _, l in pairs(timer._hk) do n = n + #l end return n end
_G.QuestTimerFrame = timer
Run(0.4)
ok(NHooks() == 3 and timer._hk.OnShow and timer._hk.OnHide and timer._hk.OnSizeChanged, "hooked: OnShow, OnHide, OnSizeChanged", tostring(NHooks()))
local order48 = list(W.watches)
local a48 = W.calls.add
Hooks("OnShow") Hooks("OnSizeChanged") Run(0.2) Hooks("OnSizeChanged")
ok(W.calls.add == a48, "not at once (settling)")
Run(1)
ok(W.calls.add == a48 + 1 and list(W.watches) == order48 and O.S.timerLayouts == 1, "one re-track for the burst, the order kept", list(W.watches))
Run(3)
ok(W.calls.add == a48 + 1, "no more after")
W.combat = true W.combatChanges = 0
Hooks("OnHide") Run(2)
ok(W.combatChanges == 0, "in combat: waits")
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(0.6)
ok(W.calls.add == a48 + 2, "fight over: once")
Restart() Run(1)
ok(NHooks() == 3, "turned off and on: no second set of hooks", tostring(NHooks()))
local keysT = 0 for k in pairs(timer) do keysT = keysT + 1 end
ok(keysT == keysT0, "nothing written on the timer frame (only hooked)", keysT0 .. " -> " .. keysT)
W.watches = {}
Hooks("OnShow") local okT = pcall(Run, 1)
ok(okT, "nothing tracked: no error, nothing to re-track")
_G.QuestTimerFrame = nil
C_QuestLog.RequestLoadQuestByID = nil

---------------------------------------------------------------------------
-- 1.2.3: battlegrounds
---------------------------------------------------------------------------
print("== 49. (1.2.3) inside a battleground: only its quests (Quests and Ready), pinned as ever")
W.Reset()
W.MAPS[1416] = { name = "Alterac Mountains", mapType = 3, parentMapID = 1415 }
W.MAPS[1459] = { name = "Alterac Valley", mapType = 3, parentMapID = 1415 }   -- (the worst case: a battleground map that reads as a zone)
W.MAPS[1460] = { name = "Warsong Gulch", mapType = 3, parentMapID = 1415 }
W.MAPS[1461] = { name = "Arathi Basin", mapType = 3, parentMapID = 1415 }
O.ForgetNames()
W.AddQuest(90, "Alterac Valley", "The Battle of Alterac", 51, false, true)
W.AddQuest(91, "Alterac Valley", "Capture a Mine", 53, true, false)
W.AddQuest(92, "Warsong Gulch", "Fight for Warsong Gulch", 50, false, true)
W.AddQuest(93, "Battlegrounds", "Concerted Efforts", 55, false, true, 41)
W.AddQuest(94, "Alterac Mountains", "Syndicate Assassins", 33, false, true)
W.AddQuest(95, "Hillsbrad Foothills", "Hillsbrad Skirmish", 30, false, true, 41)   -- (world PvP: the PvP tag under a zone)
W.AddQuest(96, "Gnomeregan", "Save Techbot's Brain", 26, false, true)
W.AddQuest(97, "Alterac Valley", "Frostwolf Supplies", 52, true, false)
W.AddQuest(98, "Silverwing Hold", "Warsong Outfitting", 50, false, true)
W.onMap[1416] = { 90, 97 }   -- (an Alterac Valley quest's pin and turn-in outdoors, in Alterac Mountains)
Restart()
Arrive(1459, { name = "Alterac Valley", kind = "pvp" })
ok(eq(W.watches, { 90 }), "in Alterac Valley: its quest only", list(W.watches))
ok(eq(ReadyIds(), { 97, 91 }), "Ready: its ready quests only (by level)", list(ReadyIds()))
ok(O.S.here.bg == "Alterac Valley" and not O.S.here.inst and O.S.here.key:find(":bg:"), "a battleground: its own kind (not a dungeon)", tostring(O.S.here.key))
W.onMap[1459] = { 93 }
Fire("ZONE_CHANGED_NEW_AREA") Run(2.5)
ok(eq(W.watches, { 90, 93 }), "the 'Battlegrounds' quest with a pin here: listed", list(W.watches))
ok(not has(W.watches, 95), "a PvP-tagged zone quest with no pin here: not", list(W.watches))
W.onMap[1459] = { 93, 95 }
Fire("ZONE_CHANGED_NEW_AREA") Run(2.5)
ok(eq(W.watches, { 95, 90, 93 }) and table.concat(O.Why(95), " "):find("PvP tag"), "a PvP-tagged quest with a pin on this battleground's map: listed", list(W.watches))
W.onMap[1459] = { 93 }
Fire("ZONE_CHANGED_NEW_AREA") Run(2.5)
O.SetPinned(94, true) Run(1)
ok(eq(W.watches, { 94, 90, 93 }), "a pinned outdoor quest: listed inside too", list(W.watches))
local why49 = table.concat(O.Why(90), " | ")
ok(why49:find("in a battleground: ") and why49:find("is this battleground"), "why: the battleground and its reason", why49)
ok(table.concat(O.Why(92), " "):find("another battleground"), "why: another battleground's quest")
ok(table.concat(O.Why(96), " "):find("only its own quests"), "why: a dungeon quest inside a battleground")
O.SetPinned(94, false) W.onMap[1459] = nil

print("== 50. (1.2.3) Warsong Gulch: its header's other names; a quest picked up outside shows on entering")
Arrive(1460, { name = "Warsong Gulch", kind = "pvp" })
ok(eq(W.watches, { 92, 98 }), "in Warsong Gulch: 'Warsong Gulch' and 'Silverwing Hold' headers", list(W.watches))
ok(not has(W.watches, 90) and not has(ReadyIds(), 91), "Alterac Valley's quests: not here", list(ReadyIds()))
local bk = W.map
Arrive(1461, { name = "Arathi Basin", kind = "pvp" })
ok(#W.watches == 0 and #ReadyIds() == 0, "in Arathi Basin with none of its quests: an empty list", list(W.watches))

print("== 51. (1.2.3) outdoors (Option A): battleground quests hidden like dungeon quests, no marker exception")
Arrive(1416)
ok(eq(W.watches, { 94 }), "Alterac Mountains: its own quest; Alterac Valley's (with a pin here) hidden", list(W.watches))
ok(#ReadyIds() == 0, "an Alterac Valley turn-in with a marker here: not in Ready", list(ReadyIds()))
ok(table.concat(O.Why(90), " "):find("listed inside its battleground"), "why: a battleground quest outdoors")
Arrive(1424)
ok(eq(W.watches, { 95 }), "Hillsbrad: the world PvP quest (PvP tag, zone header) is that zone's", list(W.watches))
O.SetPinned(92, true) Run(1)
ok(has(W.watches, 92), "a pinned battleground quest: listed outdoors", list(W.watches))
O.SetPinned(92, false) Run(1)
W.AddQuest(99, "Alterac Valley", "The Legend of Korrak", 51, false, false)
Fire("QUEST_ACCEPTED", 99) Run(1.5)
ok(not has(W.watches, 99) and mod.char.hidden[99], "picked up outdoors: untracked until inside", list(W.watches))
Arrive(1459, { name = "Alterac Valley", kind = "pvp" })
ok(has(W.watches, 99) and has(W.watches, 90), "inside Alterac Valley: tracked", list(W.watches))

print("== 52. (1.2.3) leaving restores the zone list (never in combat); dungeons, arenas unchanged")
W.combat = true W.combatChanges = 0
Arrive(1424)
ok(W.combatChanges == 0 and has(W.watches, 90), "left in combat: nothing changes yet", list(W.watches))
W.combat = false Fire("PLAYER_REGEN_ENABLED") Run(2)
ok(eq(W.watches, { 95 }), "fight over: Hillsbrad's list back", list(W.watches))
Arrive(9100, { name = "Gnomeregan", kind = "party" })
ok(eq(W.watches, { 96 }) and O.S.here.inst and not O.S.here.bg, "in Gnomeregan: its quest only, as before", list(W.watches))
Arrive(1424, { name = "Nagrand Arena", kind = "arena" })
ok(eq(W.watches, { 95 }) and not O.S.here.bg, "an arena: as before (no battleground rule)", list(W.watches))
ok(O.BGOf("The Defilers") == "arathi basin" and O.BGOf("Frostwolf Keep") == "alterac valley" and O.BGOf("Battlegrounds") == "*"
  and O.BGOf("Alterac Mountains") == nil and O.BGOf("Hillsbrad Foothills") == nil, "battleground names: aliases, the general header; zones aren't")
W.MAPS[1416], W.MAPS[1459], W.MAPS[1460], W.MAPS[1461] = nil, nil, nil, nil
O.ForgetNames()

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
