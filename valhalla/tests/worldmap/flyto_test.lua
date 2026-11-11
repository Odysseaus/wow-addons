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
ns.Safe = Safe
function ns:Print(fmt, ...) W.printed[#W.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
function ns.RegisterEvent() end
function ns.Bind(getdb) return function(info) return getdb()[info[#info]] end, function(info, v) getdb()[info[#info]] = v end end
function ns.Desc() return {} end
function ns.Header() return {} end

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
  ok(near(ew.S, 0.63, 0.02) and near(P.Duration(ew.S, "normal"), 0.64, 0.01), "Elwynn -> Westfall: S 0.63, 0.64 s at Normal (a gentle glide)", ew.S)
  local sd = P.New(0.71040, 0.61990 * k, 1 / 25.7, 0.18284, 0.27120 * k, 1 / 7.2)
  ok(near(sd.S, 4.0, 0.1) and near(P.Duration(sd.S, "normal"), 1.65, 0.04), "Stormwind -> Darkshore: S about 4, about 1.65 s at Normal", sd.S)
  ok(near(1 / sd:Peak(), 1.74, 0.05), "and it rises to about zoom 1.7 (most of the world in view) on the way", 1 / sd:Peak())
end

print("== 2. durations, speeds and easing")
do
  ok(near(P.Duration(0, "normal"), 0.6) and near(P.Duration(100, "normal"), 2.0), "Normal: 0.6 s at least, 2.0 s at most")
  ok(near(P.Duration(0, "slow"), 0.9) and near(P.Duration(100, "slow"), 3.0), "Slow x1.5: 0.9 .. 3.0 s")
  ok(near(P.Duration(0, "fast"), 0.36) and near(P.Duration(100, "fast"), 1.2), "Fast x0.6: 0.36 .. 1.2 s")
  ok(near(P.Duration(3, "normal"), 1.35), "in between: 0.45 + 0.30 S")
  ok(near(P.Duration(-3, "normal"), 1.35), "a zoom out is as long as the zoom in")
  ok(near(P.Duration(3, "bogus"), 1.35), "an unknown speed is Normal")
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
  ok(near(frames / 60, 0.64, 0.08), "about 0.64 s at Normal (Elwynn -> Westfall)", frames / 60)
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
  W.Tick()
  ok(mod.IsStitched() and map:GetMapID() == 1436 and mod.Flying() == q7, "a frame later: the stitched map (Westfall) back, flying")
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
  ok(near(ts / tn, 1.5, 0.06) and near(tf / tn, 0.6, 0.06), ("Slow x1.5, Fast x0.6 (%.2f / %.2f / %.2f s)"):format(ts, tn, tf))
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
  -- an icon on the map
  local pu, pv = ToWorld(1434, 0.35, 0.10)
  ok(mod.QuestIconClick(201, pu, pv, 1434) and mod.Flying() == 201, "a quest icon: flies (not the 0.4 s glide)")
  Land()
  local u, v, z = View()
  ok(near(u, pu, 1e-6) and near(z, math.max(6, 1.05 * Fit(1434)), 1e-6), "to the icon, at the landing zoom")
  mod.db.questFly = "blizzard"
  ok(mod.QuestIconClick(201, pu, pv, 1434) == false, "As Blizzard: the icon keeps its old glide (Quests.lua)")
  mod.db.questFly = "jump"
  local before = #W.pings
  ok(mod.QuestIconClick(201, 0.7, 0.66, nil) and not mod.Flying(), "Jump: straight there")
  ok(#W.pings == before + 1 and W.pings[#W.pings].q == 201, "and pinged")
  Defaults()
  -- Ready to Turn In in combat (Objectives.lua calls this; Blizzard's details wait)
  W.combat = true
  ok(mod.FlyToQuest(q2) and mod.Flying() == q2, "a Ready row in combat, the map open: the flight alone")
  Land()
  W.combat = false
  W.CloseMap()
  ok(mod.FlyToQuest(q2) == false, "the map closed: nothing (Valhalla doesn't open it in combat)")
end

print("== 14. nothing broken")
ok(#W.errors == 0, "no handler errors", table.concat(W.errors, " | "))
ok(QuestMapFrame_ShowQuestDetails ~= nil and type(QuestMapFrame_OpenToQuestDetails) == "function", "Blizzard's functions are still there (hooked after, not replaced)")

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
