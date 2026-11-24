-- Box tests for the quest fly-to (v0.4.2.4): Map/FlyPath.lua (the path, its timing), Map/WorldMap.lua's `fly`
-- (the flight on the map, its interrupts) and Map/QuestFly.lua (Blizzard's quest clicks, the settings, the edge
-- cases). Lua 5.1. Run: lua valhalla/tests/worldmap/flyto_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
local S = dofile(here .. "stubs.lua")
W.trace = os.getenv("TRACE")

local ns = { modules = {}, loadMs = { parts = {} }, MapStitch = S, name = "Valhalla" }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
local Safe = {}
function Safe.IsSecret() return false end
function Safe.Value(v) return v end
function Safe.XY(vec) if type(vec) ~= "table" then return end return vec.x, vec.y end
function Safe.Call(fn, ...) if type(fn) ~= "function" then return nil end local ok, v = pcall(fn, ...) if ok then return v end end
function Safe.Finite(...)
  for i = 1, select("#", ...) do
    local n = select(i, ...)
    if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then return false end
  end
  return true
end
ns.Safe = Safe
function ns:Print(fmt, ...) W.printed[#W.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
function ns.RegisterEvent() end
function ns.Bind(getdb) return function(info) return getdb()[info[#info]] end, function(info, v) getdb()[info[#info]] = v end end
function ns.Desc() return {} end
function ns.Header() return {} end

assert(loadfile(root .. "Util.lua"))("Valhalla", ns)   -- (1.2.26: the shared helpers, after Core.lua)
assert(loadfile(root .. "Map/FlyPath.lua"))("Valhalla", ns)
local P = ns.FlyPath

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 1e-9) end

print("== 1. the path (van Wijk and Nuij, rho 1.4)")
do
  local p = P.New(0.3, 0.4, 0.1, 0.7, 0.2, 0.05)
  local x, y, w = p:At(0)
  ok(x == 0.3 and y == 0.4 and w == 0.1, "starts exactly at the start view")
  x, y, w = p:At(1)
  ok(x == 0.7 and y == 0.2 and w == 0.05, "ends exactly at the target view")
  local x1, y1, w1 = p:At(1 - 1e-9)
  ok(near(x1, 0.7, 1e-6) and near(y1, 0.2, 1e-6) and near(w1, 0.05, 1e-6), "the curve itself reaches the target (no jump at the end)")
  local x0, y0, w0 = p:At(1e-9)
  ok(near(x0, 0.3, 1e-6) and near(w0, 0.1, 1e-6), "and leaves the start smoothly")
  -- the zoom-out grows with distance
  local last = 0
  local grows = true
  for _, d in ipairs({ 0.02, 0.1, 0.3, 0.6, 1.0 }) do
    local peak = P.New(0, 0, 0.08, d, 0, 0.08):Peak()
    if peak <= last then grows = false end
    last = peak
  end
  ok(grows, "the further the trip, the further out it rises")
  -- same spot: a pure zoom
  local z = P.New(0.5, 0.5, 0.2, 0.5, 0.5, 0.05)
  ok(z.pure and near(z.S, math.log(0.25) / 1.4, 1e-12), "the same spot: a pure zoom (S = log(w1/w0)/rho)")
  local _, _, wm = z:At(0.5)
  ok(near(wm, 0.1, 1e-9), "a pure zoom is even in log zoom (halfway: the geometric mean)")
  ok(z:Peak() == 0.2, "a pure zoom never rises past its wider end")
  -- a near hop at one zoom: barely rises, close to a straight pan
  local n = P.New(0.5, 0.5, 0.1, 0.52, 0.5, 0.1)
  ok(n:Peak() < 0.1 * 1.05, "a short hop at the same zoom barely zooms out (<5%)", n:Peak())
  local straight = true
  for i = 1, 9 do local _, yy = n:At(i / 10) if not near(yy, 0.5, 1e-12) then straight = false end end
  ok(straight, "and keeps to the straight line between the two")
  -- the previews' numbers (map 947 normalized; a view the world's shape: w = 1 / zoom)
  -- (in world px, as WorldMap.lua flies: y in the world's own height, 668/1002 of its width)
  local k = 668 / 1002
  local ew = P.New(0.72699, 0.64909 * k, 1 / 12.9, 0.70587, 0.69157 * k, 1 / 13.4)
  ok(near(ew.S, 0.63, 0.02) and near(P.Duration(ew.S, "normal"), 3), "Elwynn -> Westfall: S 0.63, 3 s at Normal", ew.S)
  local sd = P.New(0.71040, 0.61990 * k, 1 / 25.7, 0.18284, 0.27120 * k, 1 / 7.2)
  ok(near(sd.S, 4.0, 0.1) and near(P.Duration(sd.S, "normal"), 3), "Stormwind -> Darkshore: S about 4, 3 s at Normal too", sd.S)
  ok(near(1 / sd:Peak(), 1.74, 0.05), "and it rises to about zoom 1.7 (most of the world in view) on the way", 1 / sd:Peak())
end

print("== 2. durations, speeds and easing")
do
  ok(near(P.Duration(0, "normal"), 3) and near(P.Duration(100, "normal"), 3), "Normal: 3 s, near or far")
  ok(near(P.Duration(0, "slow"), 5) and near(P.Duration(100, "slow"), 5), "Slow: 5 s, near or far")
  ok(near(P.Duration(0, "fast"), 1.2) and near(P.Duration(100, "fast"), 1.2), "Fast: 1.2 s, near or far")
  ok(near(P.Duration(3, "normal"), 3), "in between: 3 s")
  ok(near(P.Duration(-3, "normal"), 3), "a zoom out is as long as the zoom in")
  ok(near(P.Duration(3, "bogus"), 3), "an unknown speed is Normal")
  local mono, prev = true, -1
  for i = 0, 100 do local e = P.Ease(i / 100) if e < prev then mono = false end prev = e end
  ok(mono and P.Ease(0) == 0 and P.Ease(1) == 1 and near(P.Ease(0.5), 0.5), "ease in-out cubic: 0 to 1, never back")
  ok(near(P.Ease(0.25) + P.Ease(0.75), 1, 1e-12), "symmetric: as soft landing as take-off")
end

print("== 3. Always zoom out (short trips)")
do
  local p = P.ZoomOut(0.5, 0.5, 0.1, 0.52, 0.5, 0.1, 2)
  ok(p:Peak() >= 0.2 - 1e-6 and p:Peak() < 0.2 * 1.05, "a short hop rises at least 2x out (and not much more)", p:Peak())
  local x, y, w = p:At(1)
  ok(x == 0.52 and y == 0.5 and w == 0.1, "and still lands exactly")
  local far = P.ZoomOut(0, 0, 0.05, 1, 0, 0.05, 2)
  ok(near(far.rho, P.RHO) and far:Peak() > 0.1, "a far trip that rises past 2x anyway: the plain path")
  local same = P.ZoomOut(0.5, 0.5, 0.1, 0.5, 0.5, 0.05, 2)
  ok(same.pure, "the same spot stays a pure zoom (nowhere to travel)")
end

print("== 4. a flight in time, the slow-frame guard")
do
  local f = P.Flight(P.New(0, 0, 0.1, 0.3, 0, 0.1), 1.0)
  local t, steps, done = 0, 0, false
  repeat local _, _, _, d = f:Step(1 / 60) t = t + 1 / 60 steps = steps + 1 done = d until done or steps > 200
  ok(done and near(t, 1.0, 0.03), "lasts its duration (60 fps)", t)
  local g = P.Flight(P.New(0, 0, 0.1, 0.3, 0, 0.1), 2.0)
  g:Step(1.5)
  ok(near(g.t, (1 / 30) / 2.0, 1e-9), "its first frame counts as 1/30 s at most (the map's opening frame)")
  g:Step(1 / 60) g:Step(0.06)
  ok(not g.cut, "one slow frame: carries on")
  g:Step(0.06)
  ok(g.cut and g.rate >= (1 - g.t) / 0.3 - 1e-9, "a second slow frame: the rest cut to 0.3 s")
  local rest = 0
  repeat local _, _, _, d = g:Step(0.06) rest = rest + 0.06 done = d until done or rest > 5
  ok(done and rest <= 0.3 + 0.06 + 1e-9, "and it lands within that", rest)
end

-- the map module
assert(loadfile(root .. "Map/WorldMap.lua"))("Valhalla", ns)
local mod = ns:GetModule("worldmap")
assert(loadfile(root .. "Map/QuestFly.lua"))("Valhalla", ns)
mod.db = {}
for k, v in pairs(mod.defaults) do mod.db[k] = v end
mod.enabled = true
mod.DungeonEntrance = function(id) if id == 9999 then return 0.672, 0.712 end end   -- (Dungeons.lua's: the Deadmines' door in Westfall)
local map, sc = WorldMapFrame, WorldMapFrame.ScrollContainer
mod:OnEnable()
local Q = mod.QuestFly
ok(Q ~= nil and W.dp ~= nil, "the map set up (its data provider, the fly-to)")

local function View() return mod.ViewNow() end
local function Land(max)
  for _ = 1, max or 400 do if not mod.Flying() then return true end W.Tick(1 / 60) end
  return not mod.Flying()
end
local function Pings(q, after) local n = 0 for _, p in ipairs(W.pings) do if p.q == q and p.at >= after then n = n + 1 end end return n end
local function Fit(id) return mod.FitZoom(id) end
local function ToWorld(id, x, y) return mod.ToWorld(id, x, y) end
local function Defaults() for _, k in ipairs({ "questFly", "questFlySpeed", "questFlyLanding", "questFlyShort" }) do mod.db[k] = mod.defaults[k] end end

print("== 5. settings")
do
  ok(mod.defaults.questFly == "fly" and mod.defaults.questFlySpeed == "normal" and mod.defaults.questFlyLanding == "zone"
    and mod.defaults.questFlyShort == "auto", "defaults: Fly to it, Normal, Whole zone, zoom out by distance")
  mod.db.questFly = "bogus" mod.db.questFlySpeed = 7
  ok(Q.Mode() == "fly" and Q.Speed() == "normal", "a bad saved value reads as the default")
  Defaults()
  local opts = mod:Options()
  ok(opts.questFly and opts.questFly.values.fly and opts.questFly.values.jump and opts.questFly.values.blizzard, "Options: Quest click Fly | Jump | As Blizzard")
  ok(opts.questFlySpeed and #opts.questFlySpeed.sorting == 3 and opts.questFlyLanding and opts.questFlyLanding.sorting[1] == "zone"
    and opts.questFlyShort and opts.questFlyShort.sorting[1] == "auto", "Options: speed, landing (Whole zone first), short trips")
  ok(opts.questFly.order > 11 and opts.questFly.order < 12, "beside 'When reopening the map'")
end

-- the map open on Elwynn, settled
W.OpenMap()
W.Ticks(3)
ok(mod.IsStitched() and map:GetMapID() == 1429, "the map open, stitched, on Elwynn")
local eu, ev = ToWorld(1429, 0.42, 0.65)
mod.ShowNow(eu, ev, Fit(1429))
W.Ticks(2)

print("== 6. a quest in the tracker / the quest log: the map open")
local q1 = 101          -- Westfall, in progress
W.quests[q1] = { map = 1436, x = 0.56, y = 0.47 }
do
  local u0, v0, z0 = View()
  local before = W.clock
  QuestMapFrame_OpenToQuestDetails(q1)
  ok(mod.Flying() == q1, "a flight starts (Blizzard's details shown, its map put up)")
  local u, v, z = View()
  ok(near(u, u0, 1e-6) and near(v, v0, 1e-6) and near(z, z0, 1e-6), "from the view on screen: no frame of the zone whole")
  ok(map:GetMapID() == 1436, "the map underneath is Blizzard's for the quest (Westfall)")
  local zmin = z0
  local frames = 0
  for _ = 1, 400 do
    if not mod.Flying() then break end
    ok(mod.Zooming(), "Zooming() while flying (Valhalla's extra icons rest)")
    W.Tick(1 / 60) frames = frames + 1
    local _, _, zz = View()
    zmin = math.min(zmin, zz)
  end
  local tu, tv = ToWorld(1436, 0.56, 0.47)
  local lu, lv, lz = View()
  ok(near(lu, tu, 1e-6) and near(lv, tv, 1e-6), "lands on the game's marker for the quest")
  ok(near(lz, math.max(6, 1.05 * Fit(1436)), 1e-6), "Whole zone: the zone's fit x1.05, centred on the quest", lz)
  ok(near(frames / 60, 3, 0.05), "3 s at Normal (Elwynn -> Westfall)", frames / 60)
  ok(Pings(q1, before) == 2, "pinged by Blizzard on the click and once more on landing", Pings(q1, before))
end

print("== 7. re-entry, another quest mid-flight, Back")
local q2 = 102          -- Darkshore: the other continent
W.quests[q2] = { map = 1439, x = 0.37, y = 0.44 }
do
  QuestMapFrame_ShowQuestDetails(q2)
  local _, n = mod.Flying()
  QuestMapFrame_ShowQuestDetails(q2)   -- (Blizzard's SetMapID re-enters it, the same moment)
  local _, n2 = mod.Flying()
  ok(mod.Flying() == q2 and n == n2, "one flight per quest per moment (the re-entry doesn't start another)")
  W.Ticks(20)
  local mu, mv, mz = View()
  QuestMapFrame_ShowQuestDetails(q1)
  local u, v, z = View()
  ok(mod.Flying() == q1 and near(u, mu, 1e-6) and near(z, mz, 1e-6), "another quest mid-flight: a new flight from where the camera is")
  W.Ticks(3)
  QuestMapFrame_ReturnFromQuestDetails()
  ok(not mod.Flying(), "Back: the flight stops")
  Land()
end

print("== 8. interrupts: a drag, the wheel, the gamepad, closing, a map put up")
do
  local function Start() QuestMapFrame_ShowQuestDetails(q2) W.Ticks(5) return mod.Flying() == q2 end
  ok(Start(), "flying")
  W.Run(sc, "OnMouseDown", "LeftButton")
  local u, v, z = View()
  W.Ticks(5)
  local u2, v2, z2 = View()
  ok(not mod.Flying() and near(u, u2, 1e-9) and near(z, z2, 1e-9), "a drag: stops where it is")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  ok(Start(), "flying again")
  W.Run(sc, "OnMouseWheel", 1)
  ok(not mod.Flying() and mod.Animating(), "the wheel: the flight gives way to the wheel's zoom")
  W.Ticks(60)
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  ok(Start(), "flying again")
  sc.gamepadZoom, sc.gamepadZoomSpeed = 1, 1
  W.Tick()
  sc.gamepadZoom = 0
  ok(not mod.Flying(), "the gamepad's zoom stick: stops")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  ok(Start(), "flying again")
  sc.HasGamepadScrollSpeed = function() return true end
  W.Tick()
  sc.HasGamepadScrollSpeed = nil
  ok(not mod.Flying(), "the gamepad's edge pan: stops")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  ok(Start(), "flying again")
  map:SetMapID(1415)                   -- (the dropdown: another map put up)
  ok(not mod.Flying(), "another map put up: stops")
  W.Ticks(4)
  ok(not mod.Flying(), "and isn't started again (the quest's details were left as they were, but the view reset came later)")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  ok(Start(), "flying again")
  W.CloseMap()
  ok(not mod.Flying(), "the map closed: stops")
  W.OpenMap() W.Ticks(3)
  ok(not mod.Flying() and not mod.Animating(), "and doesn't go on when it's opened again")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
end

print("== 9. the map closed when the quest is clicked: from your character")
do
  W.CloseMap()
  W.Tick()
  local pu, pv = ToWorld(1429, 0.42, 0.65)
  QuestMapFrame_OpenToQuestDetails(q2)
  local u, v, z = View()
  ok(mod.Flying() == q2 and near(u, pu, 1e-6) and near(v, pv, 1e-6) and near(z, Fit(1429), 1e-6),
    "starts on your character at its zone's view (Elwynn)", ("%.3f %.3f %.1f"):format(u, v, z))
  ok(Land(), "and lands")
  local tu, tv = ToWorld(1439, 0.37, 0.44)
  local lu, lv = View()
  ok(near(lu, tu, 1e-6) and near(lv, tv, 1e-6), "on Darkshore's marker (the other continent)")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
end

print("== 10. a view reset in the frames right after (the map's first layout): flown once more")
do
  W.CloseMap() W.Tick()
  QuestMapFrame_OpenToQuestDetails(q1)
  ok(mod.Flying() == q1, "flying")
  sc:ResetZoom()                       -- (Blizzard lays the newly opened map out again)
  ok(not mod.Flying(), "the reset cut it")
  W.Tick()
  ok(mod.Flying() == q1, "started again the next frame (the details still open)")
  local u, v, z = View()
  local pu, pv = ToWorld(1429, 0.42, 0.65)
  ok(near(z, Fit(1429), 0.6), "from the same start", z)
  Land()
  sc:ResetZoom() W.Ticks(3)
  ok(not mod.Flying(), "a reset after it has landed: nothing")
  QuestMapFrame_ShowQuestDetails(q2) W.Tick()
  QuestMapFrame_ReturnFromQuestDetails()
  W.Ticks(3)
  ok(not mod.Flying(), "Back right after a click: not started again")
end

print("== 11. where to: route stops, turn-ins, the zone, nothing, a dungeon")
do
  Defaults()
  local q3 = 103                       -- a route through Westfall first (the boat), its quest in Darkshore
  W.quests[q3] = { map = 1439, x = 0.5, y = 0.5, waypoint = { 1436, 0.3, 0.6 } }
  QuestMapFrame_ShowQuestDetails(q3) Land()
  local wu, wv = ToWorld(1436, 0.3, 0.6)
  local u, v = View()
  ok(near(u, wu, 1e-6) and near(v, wv, 1e-6), "a route: its next stop (Blizzard's waypoint)")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  W.ignoreWaypoints[q3] = true
  QuestMapFrame_ShowQuestDetails(q3) Land()
  local du, dv = ToWorld(1439, 0.5, 0.5)
  u, v = View()
  ok(near(u, du, 1e-6) and near(v, dv, 1e-6), "its waypoints turned off in the details: the quest's own marker")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  -- complete: the game's marker is the turn-in now
  W.quests[q1].x, W.quests[q1].y = 0.60, 0.30
  QuestMapFrame_ShowQuestDetails(q1) Land()
  local tu, tv = ToWorld(1436, 0.60, 0.30)
  u, v = View()
  ok(near(u, tu, 1e-6) and near(v, tv, 1e-6), "complete: the game's marker (its turn-in)")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  -- a map but no marker: the zone whole
  local q4 = 104
  W.quests[q4] = { map = 1434 }
  QuestMapFrame_ShowQuestDetails(q4) Land()
  local l, r, t, b = S.Rect(1434)
  local z
  u, v, z = View()
  ok(near(u, (l + r) / 2, 1e-6) and near(v, (t + b) / 2, 1e-6) and near(z, Fit(1434), 1e-6), "a map but no marker: its zone whole")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  -- no place at all
  local q5 = 105
  W.quests[q5] = { map = 0 }
  local u0, v0, z0 = View()
  QuestMapFrame_ShowQuestDetails(q5)
  u, v, z = View()
  ok(not mod.Flying() and near(u, u0, 1e-9) and near(z, z0, 1e-9), "no place for it: no flight, the map stays")
  ok(Q.NoteShown(), "'No map location for this quest' shows")
  W.Ticks(200, 1 / 60) W.Tick(0.5)
  ok(not Q.NoteShown(), "for 3 seconds")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  -- a map Valhalla doesn't stitch, no entrance known: Blizzard's
  local q6 = 106
  W.quests[q6] = { map = 8888 }
  QuestMapFrame_ShowQuestDetails(q6)
  W.Ticks(3)
  ok(not mod.Flying() and not mod.IsStitched() and not Q.NoteShown(), "an unstitched map with no entrance: left to Blizzard, no note")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  -- a dungeon's quest: its entrance
  local q7 = 107
  W.quests[q7] = { map = 9999 }
  QuestMapFrame_ShowQuestDetails(q7)
  ok(not mod.IsStitched() and map:GetMapID() == 9999, "a dungeon's quest: Blizzard puts the dungeon's map up first")
  W.Ticks(60)
  -- (1.2.16) its description open: the dungeon's map stays (Westfall put up under it would close it)
  ok(map:GetMapID() == 9999 and QuestMapFrame_GetDetailQuestID() == q7, "1.2.16: its description open, the dungeon's map stays and the description too")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  -- the stitched map up (a Ready row, a quest icon): glides to the entrance, no map change
  mod.ShowNow(eu, ev, Fit(1429)) W.Ticks(2)
  local before = map:GetMapID()
  ok(mod.FlyToQuest(q7) and mod.Flying() == q7 and map:GetMapID() == before, "from the stitched map: a flight to its entrance, the map not changed")
  Land()
  u, v, z = View()
  ok(near(u, 0.672, 1e-6) and near(v, 0.712, 1e-6), "to the dungeon's entrance")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
end

print("== 12. the settings at work")
do
  -- As Blizzard
  mod.db.questFly = "blizzard"
  QuestMapFrame_ShowQuestDetails(q2)
  local u, v, z = View()
  ok(not mod.Flying() and near(z, Fit(1439), 0.01), "As Blizzard: no flight, the quest's zone whole (Blizzard's reset)", z)
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  -- Jump
  mod.db.questFly = "jump"
  QuestMapFrame_ShowQuestDetails(q2)
  u, v, z = View()
  local tu, tv = ToWorld(1439, 0.37, 0.44)
  ok(not mod.Flying() and near(u, tu, 1e-6) and near(z, math.max(6, 1.05 * Fit(1439)), 1e-6), "Jump to it: there at once, at the landing zoom")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  Defaults()
  -- Slow / Fast
  local function Time(speed)
    mod.db.questFlySpeed = speed
    mod.ShowNow(0.71, 0.62, 25)
    W.Ticks(2)
    QuestMapFrame_ShowQuestDetails(q2)
    local n = 0
    while mod.Flying() and n < 400 do W.Tick(1 / 60) n = n + 1 end
    QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
    return n / 60
  end
  local tn, ts, tf = Time("normal"), Time("slow"), Time("fast")
  ok(near(ts, 5, 0.05) and near(tn, 3, 0.05) and near(tf, 1.2, 0.05), ("Slow 5 s, Normal 3 s, Fast 1.2 s, frame for frame (%.2f / %.2f / %.2f s)"):format(ts, tn, tf))
  Defaults()
  -- Close-up
  mod.db.questFlyLanding = "close"
  QuestMapFrame_ShowQuestDetails(q2) Land()
  u, v, z = View()
  ok(near(z, math.max(6, 2 * Fit(1439)), 1e-6), "Close-up: about twice the zone's fit", z)
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  Defaults()
  -- Always zoom out: a short hop rises at least 2x
  local function Lowest(short)
    mod.db.questFlyShort = short
    local pu, pv = ToWorld(1436, 0.5, 0.5)
    mod.ShowNow(pu, pv, 1.05 * Fit(1436))
    W.Ticks(2)
    W.quests[q1].x, W.quests[q1].y = 0.56, 0.47
    QuestMapFrame_ShowQuestDetails(q1)
    local zmin = 1e9
    while mod.Flying() do W.Tick(1 / 60) local _, _, zz = View() zmin = math.min(zmin, zz) end
    QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
    return zmin
  end
  local za, zo = Lowest("auto"), Lowest("out")
  local zt = 1.05 * Fit(1436)
  ok(za > zt * 0.9, "zoom out by distance: a short hop barely zooms out", za)
  ok(zo <= zt / 2 + 1e-6, "Always zoom out: at least 2x out on the way", zo)
  Defaults()
end

print("== 13. combat, Valhalla's quest icons, Ready to Turn In")
do
  W.combat = true
  local mapBefore
  QuestMapFrame_ShowQuestDetails(q2)
  mapBefore = map:GetMapID()
  ok(mod.Flying() == q2, "in combat: the flight runs")
  Land()
  W.Ticks(90)
  ok(map:GetMapID() == mapBefore, "no map switch underneath till combat ends")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  W.combat = false
  -- (1.2.46) a quest icon on the map is the game's own click (Quests.lua), not a flight
  ok(mod.QuestIconClick == nil, "no fly-to for map quest icons")
  Defaults()
  -- Ready to Turn In in combat (Objectives.lua calls this; Blizzard's details wait)
  W.combat = true
  ok(mod.FlyToQuest(q2) and mod.Flying() == q2, "a Ready row in combat, the map open: the flight alone")
  Land()
  W.combat = false
  W.CloseMap()
  ok(mod.FlyToQuest(q2) == false, "the map closed: nothing (Valhalla doesn't open it in combat)")
end

print("== 15. (1.2.16) a quest's description stays open: the map underneath never changed while it's open")
do
  Defaults()
  W.OpenMap() W.Ticks(3)
  -- an Ironforge-style city edge: an Elwynn quest whose marker is inside Stormwind City's map; Close-up
  -- lands at Stormwind's own zoom, so the zone-in-view switch would put Stormwind up after 0.6 s still
  local q8 = 108
  local su, sv = 0.715, 0.62
  W.quests[q8] = { map = 1429, x = (su - 0.69516) / (0.77283 - 0.69516), y = (sv - 0.59857) / (0.67626 - 0.59857) }
  local function Start() local wu, wv = ToWorld(1436, 0.5, 0.5) mod.ShowNow(wu, wv, Fit(1436)) W.Ticks(2) end
  local function Click(how)
    if how == "closed" then W.CloseMap() W.Tick() QuestMapFrame_OpenToQuestDetails(q8)
    elseif how == "tracker" then QuestMapFrame_OpenToQuestDetails(q8)
    else QuestMapFrame_ShowQuestDetails(q8) end
    Land()
    W.Ticks(120)   -- (2 s still after landing: well past the switch's 0.6 s)
  end
  mod.db.questFlyLanding = "close"
  -- the bug as it was (the guard off): the switch puts Stormwind up and Blizzard closes the description
  local guard = mod.DetailsOpen
  mod.DetailsOpen = function() return false end
  Start()
  local closes = W.detailCloses or 0
  Click("log")
  ok(map:GetMapID() == 1453 and QuestMapFrame_GetDetailQuestID() == nil and (W.detailCloses or 0) == closes + 1,
    "control (guard off): the switch puts Stormwind up and the description closes (the bug)", map:GetMapID())
  local e = mod.db.detailsLog and mod.db.detailsLog[1]
  ok(e and e.quest == q8 and e.questMap == 1429 and e.newMap == 1453, "detailsLog: the close logged (quest, its map, the new map)")
  ok(e and e.flags:find("valhalla switch", 1, true) and e.flags:find("auto-switch on", 1, true), "its flags: Valhalla's switch, auto-switch on", e and e.flags)
  ok(e and e.stack:find("WorldMap:", 1, true) ~= nil, "a short stack naming WorldMap.lua", e and e.stack)
  mod.DetailsOpen = guard
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  for _, how in ipairs({ "log", "tracker", "closed" }) do
    Start()
    Click(how)
    ok(map:GetMapID() == 1429 and QuestMapFrame_GetDetailQuestID() == q8, "1.2.16 " .. how .. ": landed, 2 s still: the map stays the quest's, its description open", map:GetMapID())
    local u, v = View()
    ok(near(u, su, 1e-6) and near(v, sv, 1e-6), "  and the view glided to the quest")
    QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  end
  -- a complete quest (Ready to Turn In: the same Blizzard call, its turn-in marker)
  W.quests[q8].done = true
  Start() Click("tracker")
  ok(map:GetMapID() == 1429 and QuestMapFrame_GetDetailQuestID() == q8, "a Ready to Turn In row: the same, description kept")
  -- Back: the switch goes on again
  QuestMapFrame_ReturnFromQuestDetails()
  ok(QuestMapFrame_GetDetailQuestID() == nil and map:GetMapID() == 1429, "Back: the description closed, Blizzard's map back")
  e = mod.db.detailsLog[1]
  ok(e.quest == q8 and e.flags:find("back", 1, true), "detailsLog: Back logged with its flag", e.flags)
  W.Ticks(60)
  ok(map:GetMapID() == 1453, "after Back the zone-in-view switch goes on (Stormwind put up)", map:GetMapID())
  -- Jump mode
  mod.db.questFly = "jump"
  Start() Click("log")
  ok(map:GetMapID() == 1429 and QuestMapFrame_GetDetailQuestID() == q8, "Jump to it: there at once, map and description kept")
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)
  Defaults()
  -- the log: 10 at most, newest first; a close with nothing open isn't logged
  for _ = 1, 12 do Start() QuestMapFrame_ShowQuestDetails(q8) W.Tick() QuestMapFrame_ReturnFromQuestDetails() end
  local n = #mod.db.detailsLog
  _G.QuestMapFrame_CloseQuestDetails()
  ok(n == 10 and #mod.db.detailsLog == 10, "detailsLog keeps the last 10", n)
  ok(type(mod.db.detailsLog[1].at) == "string" and mod.db.detailsLog[1].quest == q8, "each with its time and quest")

  -- C: the map opened inside a dungeon (Dungeons.lua's handler: the dungeon's own map)
  local entrance = mod.DungeonEntrance
  assert(loadfile(root .. "Map/Dungeons.lua"))("Valhalla", ns)
  mod.DungeonEntrance = entrance
  S.InstanceMap = function(name) if name == "The Deadmines" then return 9999 end end
  ns.MapPlaces = { instances = { { "Westfall", 1436, {}, { { 36, "The Deadmines" } } } } }
  _G.IsInInstance = function() return true end
  _G.GetInstanceInfo = function() return "The Deadmines", "party", 1, "", 5, 0, false, 36 end
  _G.GetRealZoneText = function() return "The Deadmines" end
  if type(rawget(map, "QuestLog")) ~= "table" then map.QuestLog = CreateFrame("Frame") end
  local okSetup, err = pcall(mod.SetupDungeons, mod, map)
  ok(okSetup, "Dungeons.lua set up on the box map", err)
  local function OpenIn(click)
    W.CloseMap() W.Tick()
    if click then QuestMapFrame_OpenToQuestDetails(q1) else W.OpenMap() end
    W.Run(map, "OnShow")
    W.Ticks(30)
  end
  OpenIn(false)
  ok(map:GetMapID() == 9999, "opened in the Deadmines (M): its own map, as before", map:GetMapID())
  OpenIn(true)
  ok(map:GetMapID() == 1436 and QuestMapFrame_GetDetailQuestID() == q1, "opened by a tracker click in the Deadmines: the quest's map and description stay", map:GetMapID())
  QuestMapFrame_ReturnFromQuestDetails() W.Ticks(2)

  -- D (1.2.18): WoW Forever's own dungeons, Places.lua and DungeonDrawn.lua as shipped (OpenMap v0.8.9's):
  -- the dungeon the map opened inside finds, its floors and the floor it opens on
  local real = { Media = { tex = "" } }
  assert(loadfile(root .. "Data/Forever/Places.lua"))("Valhalla", real)
  assert(loadfile(root .. "Data/Forever/DungeonDrawn.lua"))("Valhalla", real)
  ns.MapPlaces, ns.MapDungeonDrawn = real.MapPlaces, real.MapDungeonDrawn
  local sub = ""
  _G.GetSubZoneText = function() return sub end
  _G.IsInInstance = function() return true end
  local function Inside(name, id)
    _G.GetInstanceInfo = function() return name, "party", 1, "", 5, 0, false, id end
    local inst, floors, first = mod.DungeonHere()
    return inst, floors, first, floors and first and floors[first].name
  end
  for _, c in ipairs({ { "The Drowned City", 2970, 1 }, { "Krol'dok Stronghold", 3039, 1 }, { "Blackmaw Hold", 2974, 6 }, { "Shaper's Terrace", 3001, 2 }, { "Alcaz Prison", 2994, 0 } }) do
    local inst, floors, first = Inside(c[1], c[2])
    ok(inst and inst[1] == c[2] and inst[2] == c[1], ("inside %s (%d): found by its instance ID"):format(c[1], c[2]), inst and tostring(inst[1]))
    if c[3] > 0 then
      ok(floors and #floors == c[3] and first == 1 and floors[1].tiles and #floors[1].tiles == 12, ("  its drawn map: %d floor(s), opens on the first"):format(c[3]), floors and #floors)
    else
      ok(floors == nil and first == nil, "  no drawn map yet: the blank page, as before")
    end
  end
  local bm = ns.MapDungeonDrawn[2974]
  ok(bm[1].name == "Blackmaw Grove" and bm[6].name == "Depths of Forbidden Magic", "Blackmaw Hold's six floors, by name")
  local inst, floors, first, fname = Inside("City of Dalaran", 2959)
  ok(inst and inst[1] == 2959 and #floors == 2 and first == 1 and fname == "City of Dalaran", "inside City of Dalaran, in the city: its first floor", tostring(fname))
  sub = "The Underbelly"
  inst, floors, first, fname = Inside("City of Dalaran", 2959)
  ok(first == 2 and fname == "The Underbelly" and floors[2].tiles[1]:find("dalaran%-the%-underbelly_1"), "inside City of Dalaran, in the Underbelly: opens on the Underbelly floor", tostring(fname))
  sub = "Клоака"
  inst, floors, first = Inside("City of Dalaran", 2959)
  ok(first == 2, "  the sub-zone's name in another client language (ruRU) too", tostring(first))
  _G.IsInInstance = function() return false end
  sub = "The Underbelly"
  ok(mod.DungeonHere() == nil, "outdoors: no dungeon here")
  _G.IsInInstance = function() return true end
  _G.GetInstanceInfo = function() return "", "none", 0, "", 0, 0, false, 0 end
  ok(mod.DungeonHere() == nil, "instance ID 0: never one of the dungeons")
  sub = ""
  _G.GetSubZoneText = nil
  _G.IsInInstance = function() return false end
end

print("== 16. (1.2.23) the quest log shown: no seamless switch (the game's quest log refresh never run from Valhalla's code)")
do
  Defaults()
  W.OpenMap() W.Ticks(3)
  local q9 = 109
  local su, sv = 0.715, 0.62
  W.quests[q9] = { map = 1429, x = (su - 0.69516) / (0.77283 - 0.69516), y = (sv - 0.59857) / (0.67626 - 0.59857) }
  local function Start() local wu, wv = ToWorld(1436, 0.5, 0.5) mod.ShowNow(wu, wv, Fit(1436)) W.Ticks(2) end
  ok(mod.QuestLogShown() == false, "the quest log hidden: QuestLogShown false")
  -- the view left at the Stormwind edge (as section 15's Back), the quest log open beside the map
  mod.db.questFlyLanding = "close"     -- (lands at Stormwind's own zoom: the switch would put Stormwind up)
  Start() QuestMapFrame_OpenToQuestDetails(q9) Land() W.Ticks(120)
  QuestMapFrame_ReturnFromQuestDetails()
  local was = map:GetMapID()
  QuestMapFrame.IsShown = function() return true end
  ok(mod.QuestLogShown() == true, "the quest log shown: QuestLogShown true")
  W.Ticks(120)
  ok(map:GetMapID() == was and was == 1429, "quest log shown, 2 s still at Stormwind's edge: no switch (the map stays)", map:GetMapID())
  QuestMapFrame.IsShown = nil
  W.Ticks(60)
  ok(map:GetMapID() == 1453, "the quest log closed: the zone-in-view switch goes on (Stormwind put up)", map:GetMapID())
  -- the side panel's own answer, with the log frame's not there
  local wm = _G.WorldMapFrame
  local had = wm and wm.IsSidePanelShown
  if wm then
    wm.IsSidePanelShown = function() return true end
    ok(mod.QuestLogShown() == true, "WorldMapFrame:IsSidePanelShown(): the quest log shown")
    wm.IsSidePanelShown = had
  end
  Defaults()
end

print("== 14. nothing broken")
ok(#W.errors == 0, "no handler errors", table.concat(W.errors, " | "))
ok(QuestMapFrame_ShowQuestDetails ~= nil and type(QuestMapFrame_OpenToQuestDetails) == "function", "Blizzard's functions are still there (hooked after, not replaced)")

print("== (1.2.25) the waypoint out of combat with HasSecretRestrictions always true: set at once (Map/Nav.lua)")
do
  local okLoad, err = pcall(function()
    assert(loadfile(root .. "CombatQueue.lua"))("Valhalla", ns)
    assert(loadfile(root .. "Map/Nav.lua"))("Valhalla", ns)
  end)
  ok(okLoad, "CombatQueue.lua and Map/Nav.lua load", tostring(err))
  local wm = ns:GetModule("worldmap")
  local set, super, cleared = {}, 0, 0
  local saveCM, saveST, saveSec, saveUP = C_Map, C_SuperTrack, rawget(_G, "C_Secrets"), rawget(_G, "UiMapPoint")
  local has = false
  C_Map = setmetatable({
    SetUserWaypoint = function(p) set[#set + 1] = p has = true end,
    ClearUserWaypoint = function() cleared = cleared + 1 has = false end,
    HasUserWaypoint = function() return has end,
    GetUserWaypoint = function() local p = set[#set] return p and { uiMapID = p.m, position = { x = p.x, y = p.y } } end,
    CanSetUserWaypointOnMap = function() return true end,
    GetMapInfo = function(m) return { name = "Map " .. tostring(m) } end,
  }, { __index = saveCM })
  UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
  C_SuperTrack = setmetatable({ SetSuperTrackedUserWaypoint = function() super = super + 1 end }, { __index = saveST or {} })
  C_Secrets = { HasSecretRestrictions = function() return true end, ShouldAurasBeSecret = function() return false end }
  local combat0 = W.combat
  W.combat = false
  wm.char = wm.char or {}
  local before = #W.printed
  local okT, errT = pcall(wm.TrackPoint, 1429, 0.5, 0.5, "test")
  ok(okT, "TrackPoint ran", tostring(errT))
  ok(#set == 1 and super == 1 and not ns.Combat.Pending(), "set and super-tracked at once, nothing queued", #set .. " " .. super)
  local said = false for i = before + 1, #W.printed do if W.printed[i]:find("waypoint is set when combat ends", 1, true) then said = true end end
  ok(not said, "no 'when combat ends' line out of combat")
  W.combat = true
  pcall(wm.TrackPoint, 1429, 0.6, 0.6, "test2")
  ok(#set == 1 and ns.Combat.Pending("waypoint"), "in combat: queued (as 1.2.24)")
  ns.Combat.Cancel("waypoint")
  W.combat = combat0
  C_Map, C_SuperTrack, C_Secrets, UiMapPoint = saveCM, saveST, saveSec, saveUP
end

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
