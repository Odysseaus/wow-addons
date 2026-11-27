-- Box tests for 1.2.60 (Map/Flights.lua, Data/Forever/FlightData.lua): built-in flight times by exact path of node IDs,
-- learned once (never overwritten), lookup learned > built in > legs less 15 s a stop > old two-end keys > Learning,
-- the old tables migrated / kept as a fallback, /valhalla flighttimes export. Lua 5.1. The harness is flighttimer_test.lua's.
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
  assert(loadfile(root .. "Util.lua"))("Valhalla", ns)   -- (1.2.26: the shared helpers, after Core.lua)
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

local printed = {}
local _NewLoad = Load
Load = function()
  local t = _NewLoad()
  function ns:Print(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end
  return t
end
function GetBuildInfo() return "1.60.1", "70790" end
function date() return "2026-11-27 14:40" end
ValhallaDB = { worldmap = DB }

local T = Load()
local P = function() return T.popup end
local F = ns.MapFlights
local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

print("== 1. the built-in table: 25 single legs, every one a real path between real flight masters")
local direct = {}
for _, p in ipairs(F.paths) do direct[p[1] .. ">" .. p[2]] = true end
local allDirect, multi = true, 0
for k in pairs(F.baseline) do
  if not direct[k] then allDirect = false end
  if select(2, k:gsub(">", "")) > 1 then multi = multi + 1 end
end
ok(Count(F.baseline) == 25 and allDirect and multi == 0, "25 single legs by node IDs, each one of FlightData's paths; no stops shipped", Count(F.baseline))
ok(F.baseline["2>4"] == 78 and F.baseline["6>2"] == 211 and F.baseline["62>27"] == 152 and F.baseline["71>3276"] == 132, "the measured times (2>4 78, 6>2 211, 62>27 152, 71>3276 132)")
ok(F.baseline["2>14"] == nil and F.baseline["2>7"] == nil, "the old two-end times of routes with stops are not shipped")

print("== 2. a new character: a built-in route counts down at once; landing keeps it")
ok(next(DB.flightLearned) == nil, "nothing learned on this account yet")
AtStormwind()
TakeTaxiNode(2) Run(1) W.taxi = true Run(0.2)
ok(P().time._text == "1:18" and P().status._text == "" and P().bar:IsShown(), "Sentinel Hill: 1:18 counting down at takeoff, not Learning", P().time._text .. " " .. tostring(P().status._text))
Run(90) W.taxi = false Run(0.2) Run(3)
ok(DB.flightLearned["2>4"] == nil and T.lastLearn.result == "kept" and T.lastLearn.secs == 90, "landed at 90: nothing learned (the built-in 78 stays)")

print("== 3. learned on this account beats built in")
DB.flightLearned["2>4"] = 70
ok(T.Expected({ legs = { { 2, 4 } } }) == 70, "learned 70 over the built-in 78")
DB.flightLearned["2>4"] = nil

print("== 4. a path with stops: learned once by its whole path")
TakeTaxiNode(3) Run(1) W.taxi = true Run(0.2)
ok(P().status._text == "Learning", "2>4>5, the leg 4>5 unknown: Learning", P().status._text)
Run(200) W.taxi = false Run(0.2) Run(3)
ok(DB.flightLearned["2>4>5"] == 200 and DB.flightLearned["2>5"] == nil, "learned as 2>4>5 (200), not by its two ends")
Fly(3, 240) Run(3)
ok(DB.flightLearned["2>4>5"] == 200 and T.lastLearn.result == "kept", "flown again at 240: 200 kept (never overwritten)")

print("== 5. same ends, another path: kept apart")
ok(T.PathKey({ { 2, 6 }, { 6, 7 }, { 7, 14 } }) == "2>6>7>14" and T.PathKey({ { 2, 6 }, { 6, 14 } }) == "2>6>14", "two paths from 2 to 14, two keys")
DB.flightLearned["2>6>7>14"] = 447
ok(T.Expected({ legs = { { 2, 6 }, { 6, 14 } } }) ~= 447, "2>6>14 doesn't take 2>6>7>14's time")
ok(T.PathKey({ { 2, 6 }, { 7, 14 } }) == nil and T.PathKey({ { 2, nil } }) == nil, "legs that don't join, or a missing ID: no path key")

print("== 6. no whole path: the legs less 15 s a stop; then the old two-end time; then Learning")
ok(T.Expected({ legs = { { 6, 2 }, { 2, 5 } } }) == 211 + 113 - 15, "6>2>5: 211 + 113 - 15 = 309", T.Expected({ legs = { { 6, 2 }, { 2, 5 } } }))
DB.flightRoutes["6>7"] = 330
ok(T.Expected({ key = "6>7", legs = { { 6, 2 }, { 2, 7 } } }) == 330, "a leg unknown: the old two-end time (6>7, 330) as a fallback")
ok(T.Expected({ key = "6>66", legs = { { 6, 2 }, { 2, 66 } } }) == nil, "nothing at all: nil (Learning)")
DB.flightRoutes["6>7"] = nil

print("== 7. no node IDs: the old name keys, read and learned only when missing")
DB.flightTimes["Alpha|Beta"] = 50
ok(T.Expected({ legs = { { nil, nil, "Alpha", "Beta" } } }) == 50, "a leg by names: the old flightTimes")
local f = { key = "Alpha>Gamma", legs = { { nil, nil, "Alpha", "Gamma" } }, direct = true, fromName = "Alpha", dest = "Gamma" }
T.Learn(f, 60)
T.Learn(f, 99)
ok(DB.flightRoutes["Alpha>Gamma"] == 60 and DB.flightTimes["Alpha|Gamma"] == 60, "learned by names once (60), the second (99) not written")

print("== 8. the old single legs by node IDs migrated; two-end routes with stops left as they are")
local spare
for k in pairs(direct) do if not F.baseline[k] then spare = k break end end
DB.flightRoutes[spare] = 123
DB.flightRoutes["2>14"] = 445          -- (a route with stops, by its ends)
DB.flightRoutes["26>28"] = 999         -- (built in: not copied)
local n = T.Migrate()
ok(n == 1 and DB.flightLearned[spare] == 123, "a single leg (" .. spare .. ") copied to the learned table", n)
ok(DB.flightLearned["2>14"] == nil and DB.flightLearned["26>28"] == nil and DB.flightRoutes["2>14"] == 445, "the two-end route not copied (kept as a fallback); a built-in leg not copied")
ok(T.Migrate() == 0, "again: nothing more (idempotent)")

print("== 9. factions: their own node IDs")
ok(F.nodes[19][5] == 1 and F.nodes[18][5] == 2 and F.baseline["2>19"] and not F.baseline["2>18"], "Booty Bay: Alliance 19 has a built-in time, Horde 18 its own ID (none yet)")

print("== 10. /valhalla flighttimes export")
DB.flightLearned["Alpha>Beta"] = 5      -- (not a node-ID path: not exported)
T.TimesReport("export")
local ex = ValhallaDB.flightExport
ok(ex and ex.times["2>4>5"] == 200 and ex.times[spare] == 123 and ex.times["2>6>7>14"] == 447 and ex.times["Alpha>Beta"] == nil,
  "learned times exported by node-ID path; name keys left out")
ok(ex.count == 3 and ex.factions["2>4>5"] == 1 and ex.build == "1.60.1.70790" and ex.date == "2026-11-27 14:40" and ex.faction == "Alliance" and ex.baseline == 25,
  "with the count, the faction of each, the build, the date, the player's faction and the built-in count", table.concat({ tostring(ex.factions["2>4>5"]), tostring(ex.build), tostring(ex.date), tostring(ex.faction), tostring(ex.baseline) }, " "))
ok(printed[#printed] and printed[#printed]:find("3 learned", 1, true), "said in chat", printed[#printed])
T.TimesReport("")
ok(printed[#printed]:find("25 built in", 1, true), "/valhalla flighttimes: the counts", printed[#printed])
local init = io.open(root .. "Init.lua"):read("*a")
ok(init:find('objWord == "flighttimes"', 1, true) and init:find("T.TimesReport(objArg)", 1, true), "the slash command is wired (Init.lua)")

print("== 11. the map's route times read the same tables; the tool keeps the built-in table")
local src = io.open(root .. "Map/Flights.lua"):read("*a")
ok(src:find("local t = T.LegSecs(path[1], path[2], a[1], b[1])", 1, true), "LegTime: learned, built in, then the old tables")
local tool = root .. "../tools/flight-times/build_baseline.py"
local fh = io.open(tool)
ok(fh ~= nil, "tools/flight-times/build_baseline.py is there")
if fh then fh:close() end
local tmp = os.tmpname()
local w = io.open(tmp, "w") w:write('["times"] = {\n["2>4"] = 78,\n["2>14"] = 445,\n["999>2"] = 5,\n}\n') w:close()
local pipe = io.popen('python3 "' .. tool .. '" "' .. tmp .. '" --data "' .. root .. 'Data/Forever/FlightData.lua" --dry-run 2>&1')
local said = pipe and pipe:read("*a") or ""
if pipe then pipe:close() end
os.remove(tmp)
if said:find("baseline:", 1, true) then
  ok(said:find("25 before, 0 added", 1, true) and said:find("rejected 2>14", 1, true) and said:find("rejected 999>2", 1, true),
    "the tool (dry run): the built-in 2>4 kept, a two-end route and an unknown node rejected", said)
else
  print("SKIP  no python3 here: the tool not run")
end

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
