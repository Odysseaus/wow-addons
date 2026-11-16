-- Box tests for the flight timer popup (1.2.12, Map/Flights.lua): takeoff to landing, measured countdowns,
-- Learning for routes never flown, whole routes by node ID (stops too), early landings, /reload in the air,
-- Edit Mode moving, the setting. Lua 5.1. Run: lua valhalla/tests/worldmap/flighttimer_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")) end
end

-- the game, as much as the timer touches ----------------------------------------------------------
local W = { clock = 1000, wall = 1700000000, timers = {}, taxi = false, combat = false, calls = {}, frames = {}, errors = {} }
function GetTime() return W.clock end
function time() return W.wall end
function InCombatLockdown() return W.combat end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function geterrorhandler() return function(e) W.errors[#W.errors + 1] = tostring(e) end end
bit = bit or { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
C_Timer = { After = function(t, fn) W.timers[#W.timers + 1] = { at = W.clock + t, fn = fn } end }
local PROTECTED = { SetAttribute = true, RegisterForClicks = false }
local Frame = {}
local FrameMT = { __index = function(t, k)
  if Frame[k] then return Frame[k] end
  return function(self, ...) W.calls[#W.calls + 1] = k if PROTECTED[k] then W.protectedCalls = (W.protectedCalls or 0) + 1 end end
end }
local function NewFrame(kind, name, template)
  local f = setmetatable({ _kind = kind, _shown = true, _alpha = 1, _scripts = {}, _points = {}, _template = template }, FrameMT)
  W.frames[#W.frames + 1] = f
  if name then _G[name] = f end
  return f
end
function Frame.Show(self) self._shown = true end
function Frame.Hide(self) self._shown = false end
function Frame.IsShown(self) return self._shown end
function Frame.SetShown(self, v) self._shown = v and true or false end
function Frame.SetAlpha(self, a) self._alpha = a end
function Frame.GetAlpha(self) return self._alpha end
function Frame.SetScript(self, k, fn) self._scripts[k] = fn end
function Frame.GetScript(self, k) return self._scripts[k] end
function Frame.SetText(self, s) self._text = s end
function Frame.GetText(self) return self._text end
function Frame.SetTextColor(self, r, g, b) self._color = { r, g, b } end
function Frame.SetValue(self, v) self._value = v end
function Frame.GetFrameLevel() return 5 end
function Frame.EnableMouse(self, v) self._mouse = v and true or false end
function Frame.ClearAllPoints(self) self._points = {} end
function Frame.SetPoint(self, ...) self._points[#self._points + 1] = { ... } end
function Frame.GetPoint(self, i) return unpack(W.dragTo or self._points[i or 1] or {}) end
function Frame.StartMoving(self) self._moving = true end
function Frame.StopMovingOrSizing(self) self._moving = false end
function Frame.CreateTexture(self) return NewFrame("Texture") end
function Frame.CreateFontString(self) return NewFrame("FontString") end
function CreateFrame(kind, name, parent, template) return NewFrame(kind, name, template) end
UIParent = NewFrame("Frame", "UIParent")
function hooksecurefunc(a, b)
  local orig = _G[a]
  _G[a] = function(...) local r = { orig(...) } b(...) return unpack(r) end
end
function UnitOnTaxi(unit) return unit == "player" and W.taxi end
function UnitFactionGroup() return "Alliance" end
-- a flight master's list: slots -> node IDs and names; routes: slot -> its hops (slot pairs)
W.slots = {}
W.routes = {}
local function Nodes(list) W.slots = list end
function NumTaxiNodes() return #W.slots end
function TaxiNodeName(i) return W.slots[i] and W.slots[i].name end
function TaxiNodeGetType(i) return W.slots[i] and W.slots[i].kind or "REACHABLE" end
function GetNumRoutes(i) return #(W.routes[i] or {}) end
function TaxiGetNodeSlot(i, hop, src) local h = W.routes[i] and W.routes[i][hop] return h and (src and h[1] or h[2]) end
function GetTaxiMapID() return 1415 end
C_TaxiMap = { GetAllTaxiNodes = function() local t = {} for i, s in ipairs(W.slots) do t[#t + 1] = { slotIndex = i, nodeID = s.id, name = s.name } end return t end }
W.took = 0
function TakeTaxiNode(i) W.took = W.took + 1 end
function TaxiRequestEarlyLanding() W.early = true end
W.callbacks = {}
EventRegistry = { RegisterCallback = function(self, event, fn, owner) W.callbacks[event] = function(...) fn(owner, ...) end end }

-- Valhalla's side -------------------------------------------------------------------------------
local function NewNS()
  local ns = { modules = {}, MapStitch = {} }
  ns.L = setmetatable({}, { __index = function(_, k) return k end })
  ns.Safe = { Call = function(fn, ...) if type(fn) ~= "function" then return nil end local ok2, v = pcall(fn, ...) if ok2 then return v end end }
  ns.events = {}
  function ns.RegisterEvent(owner, event, fn) ns.events[event] = fn end
  ns.Look = { Panel = function(_, f) f._panel = true end, Font = function(_, fs) return fs end }
  ns.Style = { theme = { key = "profession", text = { 1, 0.82, 0 } }, listeners = {} }
  function ns.Style.Theme() return ns.Style.theme end
  function ns.Style.OnLook(fn) ns.Style.listeners[#ns.Style.listeners + 1] = fn end
  function ns.Style.Title(fs) fs._title = true return fs end
  local mod = { key = "worldmap", defaults = { enabled = true, flight = true } }
  ns.modules.worldmap = mod
  function ns:GetModule(k) return self.modules[k] end
  assert(loadfile(root .. "Data/Forever/FlightData.lua"))("Valhalla", ns)
  return ns, mod
end
local function Fill(t, d) for k, v in pairs(d) do if t[k] == nil then if type(v) == "table" then t[k] = Fill({}, v) else t[k] = v end end end return t end

local DB, CHAR = {}, {}
local ns, mod
local function Load()
  W.callbacks = {}
  -- (a /reload: the game's functions as they were, the addon loaded again over the same saved tables)
  TakeTaxiNode = function(i) W.took = W.took + 1 end
  TaxiRequestEarlyLanding = function() W.early = true end
  _G.ValhallaFlightTimer = nil
  ns, mod = NewNS()
  assert(loadfile(root .. "Map/Flights.lua"))("Valhalla", ns)
  mod.db, mod.char = Fill(DB, mod.defaults), CHAR
  mod:SetupFlights()
  return ns.MapFlights.Timer
end

local function Run(secs)
  local stop = W.clock + secs
  while true do
    table.sort(W.timers, function(a, b) return a.at < b.at end)
    local t = W.timers[1]
    if not t or t.at > stop then break end
    table.remove(W.timers, 1)
    W.wall = W.wall + (t.at - W.clock)
    W.clock = t.at
    t.fn()
  end
  W.wall = W.wall + (stop - W.clock)
  W.clock = stop
end

-- Stormwind (2), Sentinel Hill (4), Lakeshire (5), Darkshire (12): FlightData's IDs
local SW, WF, LS, DS = "Stormwind, Elwynn", "Sentinel Hill, Westfall", "Lakeshire, Redridge", "Darkshire, Duskwood"
local function AtStormwind()
  Nodes({ { id = 2, name = SW, kind = "CURRENT" }, { id = 4, name = WF }, { id = 5, name = LS }, { id = 12, name = DS } })
  W.routes = { [2] = { { 1, 2 } }, [3] = { { 1, 2 }, { 2, 3 } }, [4] = { { 1, 4 } } }
  ns.events.TAXIMAP_OPENED()
end
-- take off `delay` seconds after the click, fly `secs`, land
local function Fly(slot, secs, opts)
  opts = opts or {}
  TakeTaxiNode(slot)
  Run(opts.delay or 1)
  W.taxi = true
  Run(0.2)
  if opts.mid then Run(opts.mid) opts.atMid() Run(secs - opts.mid) else Run(secs) end
  W.taxi = false
  Run(0.2)
end

local T = Load()
local P = function() return T.popup end

print("== 1. the setting and its defaults")
ok(DB.flightTimer == true, "Flight timer popup: on at first")
ok(type(DB.flightRoutes) == "table" and next(DB.flightRoutes) == nil and DB.flightTimerPos == false, "no routes measured yet; the default place")
local panel = io.open(root .. "Map/Panel.lua"):read("*a")
local a1, a2 = panel:find('optRow(L["Flight masters"]', 1, true), panel:find('optRow(L["Flight timer popup"], "flightTimer"', 1, true)
local a3 = panel:find('optRow(L["Only places you\'ve found"]', 1, true)
ok(a1 and a2 and a3 and a1 < a2 and a2 < a3, "Valhalla's menu: right under Flight masters")
local wm = io.open(root .. "Map/WorldMap.lua"):read("*a")
ok(wm:find('flightTimer = { type = "toggle", name = ns.L["Flight timer popup"], order = 32.2', 1, true)
  and wm:find('flightTimerReset = { type = "execute"', 1, true), "Settings: the toggle under Flight masters (32 < 32.2 < 32.5) and Reset position")

print("== 2. a route never flown: the time so far, Learning; measured as it lands")
AtStormwind()
TakeTaxiNode(2)
Run(1)
ok(P() == nil or not P():IsShown(), "clicked, not in the air yet: no popup")
W.taxi = true
Run(0.2)
ok(P() and P():IsShown(), "takeoff: the popup")
ok(P().title._text == "Sentinel Hill" and P().status._text == "Learning" and P().time._text == "0:00", "Sentinel Hill, 0:00, Learning", tostring(P().title._text) .. " " .. tostring(P().time._text))
ok(not P().bar:IsShown(), "no bar while learning (nothing to count down from)")
Run(30)
ok(P().time._text == "0:30", "30 s later: 0:30 (the time so far)", P().time._text)
local p1 = P()._points[1]
ok(p1 and p1[1] == "TOP" and p1[2] == UIParent and p1[3] == "TOP" and p1[4] == 0 and p1[5] == -110, "at TOP 0, -110 (below the top centre)")
Run(48)
W.taxi = false
Run(0.2)
ok(DB.flightRoutes["2>4"] == 78, "landed after 78 s: the whole route saved by node IDs (2>4)", DB.flightRoutes["2>4"])
ok(DB.flightTimes[SW .. "|" .. WF] == 78, "and the direct leg by name, as before (the map's route times)")
ok(P():IsShown(), "just landed: still shown a moment")
Run(1.5 + 1.2)
ok(not P():IsShown() and P():GetAlpha() == 1, "then faded away")
ok(CHAR.flightNow == nil, "nothing left in the air")

print("== 3. flown before: a countdown and a bar; past it: Landing soon")
TakeTaxiNode(2) Run(1) W.taxi = true Run(0.2)
ok(P().time._text == "1:18" and P().status._text == "" and P().bar:IsShown(), "countdown from 1:18, the bar", P().time._text)
Run(30)
ok(P().time._text == "0:48" and math.abs(P().bar._value - 30.2 / 78) < 0.01, "30 s in: 0:48, the bar 30/78", P().time._text .. " " .. tostring(P().bar._value))
Run(60)
ok(P().time._text == "Landing soon (+0:12)" and P().bar._value == 1, "past the time: Landing soon (+0:12)", P().time._text)
W.taxi = false Run(0.2)
ok(DB.flightRoutes["2>4"] == 90, "landed: the route's time measured again (90)")
Run(3)

print("== 4. a route with stops: whole route, else every leg; else Learning")
DB.flightTimes[WF .. "|" .. LS] = nil
TakeTaxiNode(3) Run(1) W.taxi = true Run(0.2)
ok(P().title._text == "Lakeshire" and P().status._text == "Learning", "Stormwind > Lakeshire by Sentinel Hill, one leg not measured: Learning (no guess)", P().status._text)
ok(not P().time._text:find("stop"), "no stop count")
Run(200) W.taxi = false Run(0.2) Run(3)
ok(DB.flightRoutes["2>5"] == 200 and DB.flightTimes[SW .. "|" .. LS] == nil, "the whole route saved (2>5: 200); not as a direct leg")
TakeTaxiNode(3) Run(1) W.taxi = true Run(0.2)
ok(P().time._text == "3:20", "flown again: counts down from the whole route's 3:20", P().time._text)
W.taxi = false Run(0.2) Run(3)
DB.flightRoutes["2>5"] = nil
DB.flightTimes[WF .. "|" .. LS] = 130
TakeTaxiNode(3) Run(1) W.taxi = true Run(0.2)
ok(P().time._text == T.Clock(DB.flightRoutes["2>4"] + 130), "no whole route, every leg measured: their sum (" .. T.Clock(DB.flightRoutes["2>4"] + 130) .. ")", P().time._text)
W.taxi = false Run(0.2) Run(3)

print("== 5. landing early, never taking off")
local before = DB.flightRoutes["2>12"]
TakeTaxiNode(4) Run(1) W.taxi = true Run(10)
TaxiRequestEarlyLanding()
Run(5) W.taxi = false Run(0.2) Run(3)
ok(before == nil and DB.flightRoutes["2>12"] == nil and DB.flightTimes[SW .. "|" .. DS] == nil, "landed early: not saved")
TakeTaxiNode(4) Run(12)
ok(not P():IsShown() and CHAR.flightNow == nil, "clicked but never took off: no popup, forgotten after 10 s")
Fly(4, 116)
ok(DB.flightRoutes["2>12"] == 116, "the next flight there is measured (116)")
Run(3)

print("== 6. the setting off: no popup, still measured")
DB.flightTimer = false
mod.RefreshFlightTimer()
TakeTaxiNode(2) Run(1) W.taxi = true Run(0.2)
ok(not P():IsShown(), "off: no popup in the air")
Run(20)
DB.flightTimer = true mod.RefreshFlightTimer()
ok(P():IsShown(), "switched on mid-flight: it shows")
DB.flightTimer = false mod.RefreshFlightTimer()
ok(not P():IsShown(), "off mid-flight: it goes")
Run(60) W.taxi = false Run(0.2)
ok(DB.flightRoutes["2>4"] == 80, "and the flight still measured (80)", DB.flightRoutes["2>4"])
DB.flightTimer = true
Run(3)

print("== 7. /reload in the air: goes on; a log-in later: shown, not measured")
TakeTaxiNode(2) Run(1) W.taxi = true Run(30.2)
ok(CHAR.flightNow and CHAR.flightNow.key == "2>4" and CHAR.flightNow.epoch, "the flight in the air saved for the character")
W.timers = {}
W.wall = W.wall + 3 W.clock = W.clock + 3          -- (the reload)
T = Load()
ok(P() and P():IsShown() and P().title._text == "Sentinel Hill", "after the /reload: the popup again, the same flight")
ok(P().time._text == T.Clock(80 - 33), "and the countdown where it was (33 s in: " .. T.Clock(80 - 33) .. ")", P().time._text)
Run(47) W.taxi = false Run(0.2)
ok(DB.flightRoutes["2>4"] == 80, "landed: measured across the reload (80)", DB.flightRoutes["2>4"])
Run(3)
TakeTaxiNode(2) Run(1) W.taxi = true Run(20.2)
W.timers = {}
W.wall = W.wall + 120 W.clock = W.clock + 120      -- (logged out, back two minutes later)
T = Load()
ok(P() and P():IsShown(), "logged back in still flying: shown")
Run(10) W.taxi = false Run(0.2)
ok(DB.flightRoutes["2>4"] == 80, "but not measured (the time away isn't the flight's)")
Run(3)
W.taxi = false
CHAR.flightNow = { key = "2>4", epoch = W.wall - 10, seen = W.wall }
T = Load()
ok(CHAR.flightNow ~= nil and not (P() and P():IsShown()), "a saved flight, on the ground at login: kept till the world is entered (the taxi may not be known yet), no popup")
ns.events.PLAYER_ENTERING_WORLD()
Run(1.1)
ok(CHAR.flightNow == nil and not (P() and P():IsShown()), "in the world, still on the ground: forgotten, no popup")

print("== 8. Edit Mode: moved only while it's open; Reset position")
ok(W.callbacks["EditMode.Enter"] and W.callbacks["EditMode.Exit"], "listens to Edit Mode's own Enter / Exit")
W.callbacks["EditMode.Enter"]()
local f = P()
ok(f:IsShown() and f._mouse and f.edit:IsShown() and f.title._text == "Flight timer", "Edit Mode open: a sample popup, marked in blue, takes the mouse")
f._scripts.OnMouseDown(f, "LeftButton")
ok(f._moving, "drag: it moves")
W.dragTo = { "TOPLEFT", UIParent, "TOPLEFT", 812.4, -201.6 }
f._scripts.OnMouseUp(f, "LeftButton")
W.dragTo = nil
local pos = DB.flightTimerPos
ok(type(pos) == "table" and pos[1] == "TOPLEFT" and pos[3] == 812 and pos[4] == -202 and not f._moving, "dropped: the place saved")
W.callbacks["EditMode.Exit"]()
ok(not f:IsShown() and not f._mouse and not f.edit:IsShown(), "Edit Mode closed: hidden, no mouse")
f._scripts.OnMouseDown(f, "LeftButton")
ok(not f._moving, "not in Edit Mode: it doesn't move")
Fly(2, 30, { mid = 10, atMid = function()
  local q = P()._points[1]
  ok(q and q[1] == "TOPLEFT" and q[4] == 812 and q[5] == -202, "the next flight: where it was put")
end })
Run(3)
W.callbacks["EditMode.Enter"]()
f._scripts.OnMouseDown(f, "RightButton")
ok(DB.flightTimerPos == false and f._points[1][1] == "TOP" and f._points[1][5] == -110, "right-click in Edit Mode: back to TOP 0, -110")
DB.flightTimerPos = { "CENTER", "CENTER", 5, 5 }
T.ResetPosition()
ok(DB.flightTimerPos == false, "Settings' Reset position: the same")
W.callbacks["EditMode.Exit"]()

print("== 9. combat, the look")
W.combat = true
W.calls = {}
Fly(2, 30)
local bad = 0
for _, fr in ipairs(W.frames) do if rawget(fr, "_template") then bad = bad + 1 end end
ok(bad == 0 and (W.protectedCalls or 0) == 0 and #W.errors == 0, "in combat: plain frames only, no protected calls, no errors", bad .. " " .. tostring(W.protectedCalls) .. " " .. tostring(W.errors[1]))
W.combat = false
Run(3)
ok(#ns.Style.listeners >= 1, "follows the Look: repainted when it changes")
ns.Style.theme = { key = "norse", text = { 0.9, 0.7, 0.3 } }
for _, fn in ipairs(ns.Style.listeners) do fn("norse") end
TakeTaxiNode(2) Run(1) W.taxi = true Run(0.2)
ok(P().title._color[1] == 0.9 and P().title._title and P()._panel, "Norse: its colour, the look's title font and panel")
W.taxi = false Run(3.5)

print("== 10. (1.2.18) OpenMap v0.8.9's flight data: Powderfuse Port's nodes gone, Nighthaven's for druids only")
do
  local FD = ns.MapFlights
  ok(FD.nodes[3274] == nil and FD.nodes[3275] == nil, "FlightData: Powderfuse Port's two nodes gone (no flight master there in game)")
  local dangling, toPowder = 0, 0
  for _, path in ipairs(FD.paths) do
    if not FD.nodes[path[1]] or not FD.nodes[path[2]] then dangling = dangling + 1 end
    if path[1] == 3274 or path[1] == 3275 or path[2] == 3274 or path[2] == 3275 then toPowder = toPowder + 1 end
  end
  ok(dangling == 0 and toPowder == 0, "every flight path's ends are nodes; none to or from Powderfuse Port", dangling .. " " .. toPowder)
  ok(FD.nodes[62][6] == "DRUID" and FD.nodes[63][6] == "DRUID" and FD.nodes[62][1]:find("Nighthaven"), "Nighthaven's two nodes: druids only")
  local others = 0
  for id, n in pairs(FD.nodes) do if n[6] and id ~= 62 and id ~= 63 then others = others + 1 end end
  ok(others == 0, "no other node is a class's own", others)
  ok(FD.nodes[3276] and FD.nodes[3203], "Riverglades' other flight masters stay (Farholde Keep, Rog'mar)")
  -- the map's flight masters, built for a druid and for a warrior
  tinsert = tinsert or table.insert
  GameTooltip_Hide = GameTooltip_Hide or function() end
  local function BuildAs(class, faction)
    local built = {}
    local ns2, mod2 = NewNS()
    local S2 = ns2.MapStitch
    S2.IsBuilt = function() return true end
    S2.PinSet = function() return {} end
    S2.FromYards = function() return 0.5, 0.5 end
    S2.AddPin = function() local pin = NewFrame("Button") pin.Icon, pin.shadow = NewFrame("Texture"), false built[#built + 1] = pin return pin end
    S2.Look = function() end
    local oldClass, oldFaction = _G.UnitClass, _G.UnitFactionGroup
    _G.UnitClass = function() return class:lower(), class end
    _G.UnitFactionGroup = function() return faction end
    assert(loadfile(root .. "Map/Flights.lua"))("Valhalla", ns2)
    mod2.db, mod2.char = Fill({}, mod2.defaults), {}
    local okBuild, err = pcall(mod2.BuildFlights, mod2)
    _G.UnitClass, _G.UnitFactionGroup = oldClass, oldFaction
    local by = {}
    for _, pin in ipairs(built) do by[pin.node] = true end
    return by, okBuild, err
  end
  local druid, ok1, e1 = BuildAs("DRUID", "Alliance")
  local warrior, ok2, e2 = BuildAs("WARRIOR", "Alliance")
  local hdruid, ok3, e3 = BuildAs("DRUID", "Horde")
  local hwarrior = BuildAs("WARRIOR", "Horde")
  ok(ok1 and ok2 and ok3, "the map's flight masters built, no error", tostring(e1 or e2 or e3))
  ok(druid[62] and not druid[63] and hdruid[63] and not hdruid[62], "a druid: Nighthaven's flight master on the map (their faction's)")
  ok(not warrior[62] and not warrior[63] and not hwarrior[62] and not hwarrior[63], "a warrior: no Nighthaven flight master")
  ok(warrior[2] and druid[2] and hwarrior[3203] and not warrior[3274] and not hwarrior[3275], "the rest as before (Stormwind; Rog'mar for the Horde); no Powderfuse Port")
  -- the timer next to where Powderfuse Port's was: Farholde Keep to Lakeshire, measured as any other
  Nodes({ { id = 3276, name = "Farholde Keep, Riverglades", kind = "CURRENT" }, { id = 5, name = LS } })
  W.routes = { [2] = { { 1, 2 } } }
  ns.events.TAXIMAP_OPENED()
  Fly(2, 64)
  ok(DB.flightRoutes["3276>5"] == 64, "Farholde Keep to Lakeshire: timed and saved by node IDs (3276>5)", DB.flightRoutes["3276>5"])
  Run(3)
  -- a flight master the game still lists there (an old save, a client's own list): by name, no error
  local errs = #W.errors
  Nodes({ { id = 3275, name = "Powderfuse Port, Riverglades", kind = "CURRENT" }, { id = 3276, name = "Farholde Keep, Riverglades" } })
  W.routes = { [2] = { { 1, 2 } } }
  ns.events.TAXIMAP_OPENED()
  Fly(2, 40)
  ok(#W.errors == errs and P().title._text == "Farholde Keep", "from a node FlightData no longer has: the timer still runs, no error", tostring(P().title._text))
  Run(3)
  -- the boat stays: Places.lua's transports and sailings, Routes.lua's neutral port
  local real = { Media = { tex = "" } }
  assert(loadfile(root .. "Data/Forever/Places.lua"))("Valhalla", real)
  local boats, sails = 0, 0
  for _, t in ipairs(real.MapPlaces.transports or {}) do if t[1] == "boat" and t[2] == "Steamwheedle Port - Powderfuse Port" then boats = boats + 1 end end
  for _, t in ipairs(real.MapPlaces.sailings or {}) do if t[2] == "Steamwheedle Port - Powderfuse Port" then sails = sails + 1 end end
  ok(boats == 2 and sails == 1, "Powderfuse Port's boat stays (both ways, its sailing)", boats .. " " .. sails)
  local routes = io.open(root .. "Map/Routes.lua"):read("*a")
  ok(routes:find('["Steamwheedle Port - Powderfuse Port"] = true', 1, true), "Routes.lua: its boat still drawn as a neutral goblin port's")
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
