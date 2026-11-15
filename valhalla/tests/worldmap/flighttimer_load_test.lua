-- Box tests for the flight timer (1.2.13) as the game loads it: the addon's real files in the TOC's order
-- (LibStub, Core, Style, FlightData, FlyPath, WorldMap, Flights, Init), then ADDON_LOADED, PLAYER_LOGIN and
-- PLAYER_ENTERING_WORLD through Core's and Init's own event frames. The timer must work with the map on,
-- off, or waiting for the Gamepad UI; a flight it didn't see start (before a /reload, or a click it didn't
-- hear) shows "In flight"; the real Style.lua paints it in each look. Lua 5.1.
-- Run: lua valhalla/tests/worldmap/flighttimer_load_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")) end
end

local W, ns, T
-- one game session: the stubs afresh, the saved tables given, the files loaded in order, the events fired
local function Session(o)
  o = o or {}
  local S = dofile(here .. "stubs.lua")   -- (and Stitch.lua's stand-in, the stitched map: as flyto_test's)
  W = _G.W
  W.wall0 = o.wall or 1700000000
  local clock0 = W.clock
  function time() return math.floor(W.wall0 + (W.clock - clock0)) end
  -- events: who registered what (the stubs' frames do nothing with them)
  local mt = getmetatable(CreateFrame("Frame"))
  local base = mt.__index
  W.reg = {}
  mt.__index = function(t, k)
    if k == "RegisterEvent" then return function(self, e) W.reg[e] = W.reg[e] or {} W.reg[e][self] = true return true end end
    if k == "UnregisterEvent" then return function(self, e) if W.reg[e] then W.reg[e][self] = nil end end end
    if k == "SetFont" then return function(self, file, size, flags) rawset(self, "_font", file) return true end end
    if k == "SetStatusBarColor" then return function(self, r, g, b) rawset(self, "_barColor", { r, g, b }) end end
    if k == "SetAtlas" then return function(self, a) rawset(self, "_atlas", a) end end
    -- (a real frame has no field it wasn't given: only methods, which start upper-case)
    if type(k) == "string" and k:find("^[%l_]") then return nil end
    return base(t, k)
  end
  function W.Fire(e, ...)
    for f in pairs(W.reg[e] or {}) do local fn = f._scripts.OnEvent if fn then fn(f, e, ...) end end
  end
  -- the game
  W.printed = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) W.printed[#W.printed + 1] = m end }
  GetAddOnMetadata = function(_, k) if k == "Version" then return "1.2.13" end end
  C_AddOns = { GetAddOnMetadata = GetAddOnMetadata, IsAddOnLoaded = function() return false end }
  C_Texture = { GetAtlasInfo = function(name) return { file = "art/" .. name, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end }
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  SlashCmdList = {}
  UIParent = UIParent or CreateFrame("Frame", "UIParent")
  bit = bit or { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
  InputUtil = { IsGamepadUIEnabled = function() return o.pad and true or false end }
  W.taxi = o.onTaxi and true or false
  function UnitOnTaxi(u) return u == "player" and W.taxi end
  function UnitFactionGroup() return "Alliance" end
  W.slots = { { id = 2, name = "Stormwind, Elwynn", kind = "CURRENT" }, { id = 4, name = "Sentinel Hill, Westfall" } }
  W.routes = { [2] = { { 1, 2 } } }
  function NumTaxiNodes() return #W.slots end
  function TaxiNodeName(i) return W.slots[i] and W.slots[i].name end
  function TaxiNodeGetType(i) return W.slots[i] and W.slots[i].kind or "REACHABLE" end
  function GetNumRoutes(i) return #(W.routes[i] or {}) end
  function TaxiGetNodeSlot(i, hop, src) local h = W.routes[i] and W.routes[i][hop] return h and (src and h[1] or h[2]) end
  function GetTaxiMapID() return 1415 end
  C_TaxiMap = { GetAllTaxiNodes = function() local t = {} for i, s in ipairs(W.slots) do t[#t + 1] = { slotIndex = i, nodeID = s.id } end return t end,
    GetTaxiNodesForMap = function() return {} end }
  W.took = 0
  function TakeTaxiNode() W.took = W.took + 1 end
  function TaxiRequestEarlyLanding() end
  W.callbacks = {}
  EventRegistry.RegisterCallback = function(_, event, fn, owner) W.callbacks[event] = function(...) fn(owner, ...) end end
  ValhallaDB, ValhallaCharDB = o.db, o.char
  -- the addon, in the TOC's order
  ns = { Client = "Forever", MapStitch = S }
  local files = { "Libs/LibStub/LibStub.lua", "Core.lua", "UI/Style.lua", "Data/Forever/FlightData.lua", "Map/FlyPath.lua",
    "Map/WorldMap.lua", "Map/Flights.lua", "Init.lua" }
  for _, f in ipairs(files) do assert(loadfile(root .. f))("Valhalla", ns) end
  T = ns.MapFlights.Timer
  W.Fire("ADDON_LOADED", "Valhalla")
  if o.beforeLogin then o.beforeLogin() end
  W.Fire("PLAYER_LOGIN")
  W.Fire("PLAYER_ENTERING_WORLD", not o.reload, o.reload and true or false)
  W.Tick(1.1)
  return ns:GetModule("worldmap")
end
local function Tick(secs) local n = math.floor(secs / 0.1 + 0.5) for _ = 1, n do W.Tick(0.1) end end
local function Popup() return T.popup end
local function Fly(secs)
  TakeTaxiNode(2) Tick(1) W.taxi = true Tick(0.3)
  local shown = Popup() and Popup():IsShown()
  local title = Popup() and Popup().title._text
  Tick(secs) W.taxi = false Tick(0.3)
  return shown, title
end

print("== 1. the map on: set up once at login (Init's PLAYER_LOGIN and the map's SetupFlights)")
local mod = Session({ db = nil, char = nil })
ok(mod.enabled and T.setup and T.hooked, "map on: the timer set up at login, TakeTaxiNode heard")
ok(ValhallaDB.worldmap.flightTimer == true, "the setting on at first (a fresh install)")
local shown, title = Fly(78)
ok(shown and title == "Sentinel Hill", "a flight: the popup at takeoff", tostring(title))
ok(ValhallaDB.worldmap.flightRoutes["2>4"] == 78, "and timed once (one hook, not two: the time saved once and right)", ValhallaDB.worldmap.flightRoutes["2>4"])
-- (a second hook would run OnTakeTaxi twice: count the timer's watchers by setting up again)
ok(ns.loadMs.parts.Flights ~= nil, "the map's setup ran its Flights part too (SetupFlights)")
ok(T.hooks == 1, "TakeTaxiNode hooked once (login and the map's setup both asked)", T.hooks)
T.Setup()
ok(T.hooks == 1, "SetupTimer again: nothing more (idempotent)", T.hooks)
local db1, char1 = ValhallaDB, ValhallaCharDB

print("== 2. the map off (Enable Valhalla unticked): the timer all the same")
db1.worldmap.enabled = false
mod = Session({ db = db1, char = char1 })
ok(not mod.enabled and T.setup and T.hooked, "map off: the timer set up at login anyway")
db1.worldmap.flightRoutes["2>4"] = nil
shown, title = Fly(80)
ok(shown and title == "Sentinel Hill" and db1.worldmap.flightRoutes["2>4"] == 80, "a flight shows and is timed", tostring(db1.worldmap.flightRoutes["2>4"]))
db1.worldmap.enabled = true

print("== 3. the Gamepad UI on (Valhalla leaves the map to Blizzard): the timer all the same")
mod = Session({ db = db1, char = char1, pad = true })
ok(mod.padWaits and not mod.enabled and T.setup, "map waiting for the Gamepad UI: the timer set up")
TakeTaxiNode(2) Tick(1) W.taxi = true Tick(0.3)
ok(Popup():IsShown() and Popup().time._text == "1:20", "a flight timed before: counts down (1:20)", Popup().time._text)
W.taxi = false Tick(3)

print("== 4. already in the air at load, nothing saved (begun before the update / a reload)")
char1.worldmap.flightNow = nil
mod = Session({ db = db1, char = char1, onTaxi = true, reload = true })
ok(Popup() and Popup():IsShown() and Popup().title._text == "In flight (reloaded)", "after the /reload: \"In flight (reloaded)\"", Popup() and Popup().title._text)
ok(Popup().status._text == "Learning" and Popup().time._text == "0:01", "the time since (0:01), Learning; no countdown", Popup().time._text)
Tick(30)
ok(Popup().time._text == "0:31", "it goes on (0:31)", Popup().time._text)
local before = 0 for _ in pairs(db1.worldmap.flightRoutes) do before = before + 1 end
W.taxi = false Tick(3)
local after = 0 for _ in pairs(db1.worldmap.flightRoutes) do after = after + 1 end
ok(after == before and not Popup():IsShown(), "landed: nothing saved (not the whole flight), faded")

print("== 5. a click not heard: control lost on a taxi; a stun isn't a flight")
mod = Session({ db = db1, char = char1 })
W.taxi = true
W.Fire("PLAYER_CONTROL_LOST")
Tick(0.5)
ok(Popup() and Popup():IsShown() and Popup().title._text == "In flight" and Popup().status._text == "Learning", "control lost, on a taxi: \"In flight\", Learning")
W.taxi = false Tick(3)
W.Fire("PLAYER_CONTROL_LOST")
Tick(4)
ok(not Popup():IsShown(), "control lost, not on a taxi (a stun): nothing")
shown, title = Fly(30)
ok(shown and title == "Sentinel Hill", "a click heard after: the destination, as ever (control lost doesn't take it over)")
W.Fire("PLAYER_CONTROL_LOST")
Tick(3)

print("== 6. a saved flight across a /reload goes on (1.2.12's, still)")
TakeTaxiNode(2) Tick(1) W.taxi = true Tick(20.3)
ok(char1.worldmap.flightNow and char1.worldmap.flightNow.key == "2>4", "the flight saved for the character")
mod = Session({ db = db1, char = char1, onTaxi = true, reload = true, wall = time() + 2 })
ok(Popup():IsShown() and Popup().title._text == "Sentinel Hill", "after the /reload: the same flight, its destination", Popup().title._text)
W.taxi = false Tick(3)
ok(char1.worldmap.flightNow == nil, "landed: forgotten")
char1.worldmap.flightNow = { key = "2>4", epoch = 1, seen = 1, dest = "Sentinel Hill, Westfall" }
mod = Session({ db = db1, char = char1, onTaxi = false })
ok(char1.worldmap.flightNow == nil and not (Popup() and Popup():IsShown()), "a saved flight, on the ground once in the world: forgotten")

print("== 7. the look (the real Style.lua)")
local function Parts(f) local t = {} for k, p in pairs(f.vh and f.vh.parts or {}) do if p._shown then t[k] = p end end return t end
db1.ui = db1.ui or {}
db1.ui.look = "norse"
mod = Session({ db = db1, char = char1 })
TakeTaxiNode(2) Tick(1) W.taxi = true Tick(0.3)
local f = Popup()
local p = Parts(f)
ok(f.vh and f.vh.kind == "popup", "the popup is the look's (Style.Popup)")
ok(p.n1 and p.n8 and p.ktl and p.kbr and p.bg and p.bg._atlas == "heavybronze-frame-background-c60", "Norse: heavy bronze border (8 pieces) and its corner brackets, its background", p.bg and p.bg._atlas)
ok(p.ktl and p.ktl._atlas == "heavybronze-horz-cornerbracket-tl-c60", "the brackets' own art", p.ktl and p.ktl._atlas)
ok(f.title._font == "Fonts\\MORPHEUS.TTF", "Norse: the title in Morpheus", f.title._font)
local c = f.bar._barColor
ok(c and c[1] == 0.8 and c[2] == 0.56, "Norse: a bronze bar")
ns.Style.SetLook("profession")
p = Parts(f)
ok(p.bg and p.bg._atlas == "profession-background-template2-c60" and p.mT and p.eT and not p.n1 and not p.ktl,
  "switched to Profession: the profession window's background, a metal and gold edge; the bronze gone", p.bg and p.bg._atlas)
c = f.bar._barColor
ok(c and c[1] == 1 and c[2] == 0.78, "Profession: a gold bar")
ok(f.title._font ~= "Fonts\\MORPHEUS.TTF", "and the game's font for the title")
ns.Style.SetLook("norse")
p = Parts(f)
ok(p.n1 and p.ktl and not p.mT and f.bar._barColor[1] == 0.8, "and back to Norse: repainted")
W.taxi = false Tick(3)

print("== 8. /valhalla flight")
W.printed = {}
SlashCmdList.VALHALLA("flight")
local all = table.concat(W.printed, "\n")
ok(all:find("Flight timer: set up true, TakeTaxiNode heard true, setting true, look norse", 1, true) and all:find("Popup:", 1, true),
  "prints the state: set up, heard, setting, look, popup", all)
TakeTaxiNode(2) Tick(1) W.taxi = true Tick(5.3)
W.printed = {}
SlashCmdList.VALHALLA("flight")
all = table.concat(W.printed, "\n")
ok(all:find("In the air: Sentinel Hill, Westfall, route 2>4", 1, true), "in the air: the flight's state", all)
W.taxi = false Tick(3)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
