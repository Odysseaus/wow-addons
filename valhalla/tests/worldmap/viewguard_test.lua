-- Box tests for 1.2.34's blank-map guards (OpenMap v0.8.10 #260 #261 #306): Safe.Finite, ScrubSaved on
-- logout, and FitZoom when the map is still 0 px across. Lua 5.1.
-- Run: lua valhalla/tests/worldmap/viewguard_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")) end
end

local scripts = {}
local function NewFrame()
  local f = {}
  function f:SetScript(name, fn) scripts[name] = fn end
  function f:RegisterEvent() return true end
  function f:UnregisterEvent() end
  return f
end
function CreateFrame() return NewFrame() end
function GetAddOnMetadata(_, key) if key == "Version" then return "1.2.34" end end
C_AddOns = { GetAddOnMetadata = GetAddOnMetadata }

local ns = { Client = "Forever" }
assert(loadfile(root .. "Core.lua"))("Valhalla", ns)
local Safe = ns.Safe

print("== 1. Safe.Finite")
local nan = 0 / 0
ok(Safe.Finite(0) and Safe.Finite(1.5) and Safe.Finite(-3) and Safe.Finite(), "0, ordinary numbers, and no arguments")
ok(not Safe.Finite(nan) and not Safe.Finite(math.huge) and not Safe.Finite(-math.huge), "NaN and both infinities")
ok(not Safe.Finite("1") and not Safe.Finite(nil) and not Safe.Finite(true) and not Safe.Finite({}), "a non-number")
ok(not Safe.Finite(1, nan) and not Safe.Finite(math.huge, 2), "any one bad argument fails the whole call")
issecretvalue = function(v) return v == 7 end
ok(not Safe.Finite(7) and Safe.Finite(8), "a secret number is not finite; a plain one is")
issecretvalue = nil

print("== 2. ScrubSaved")
local t = { a = 1, b = nan, c = "kept", d = { e = math.huge, f = { g = -math.huge, h = 2 } }, ok = 0 }
t.self = t
ns.ScrubSaved(t)
ok(t.a == 1 and t.b == nil and t.c == "kept" and t.ok == 0, "a finite number and a string stay; NaN goes", tostring(t.b))
ok(t.d and t.d.e == nil and t.d.f and t.d.f.g == nil and t.d.f.h == 2, "nested infinities go; the tables and a finite child stay")
ok(t.self == t, "a cycle is walked once")
ns.ScrubSaved("no")
ns.ScrubSaved(nil)

print("== 3. logout scrubs every saved table")
ValhallaDB = { worldmap = { windowScale = nan, name = "kept", nested = { zoom = math.huge, n = 4 } } }
ValhallaCharDB = { worldmap = { x = -math.huge } }
ValhallaInvestDB = { prices = { bad = nan, good = 12 } }
ns.modules = {}
ns:InitDB()
ok(type(scripts.OnEvent) == "function", "Core's event frame is listening")
scripts.OnEvent(nil, "PLAYER_LOGOUT")
ok(ValhallaDB.worldmap.windowScale == nil and ValhallaDB.worldmap.name == "kept" and ValhallaDB.worldmap.nested.zoom == nil and ValhallaDB.worldmap.nested.n == 4, "ValhallaDB: only the bad numbers", tostring(ValhallaDB.worldmap.windowScale))
ok(ValhallaCharDB.worldmap.x == nil, "ValhallaCharDB")
ok(ValhallaInvestDB.prices.bad == nil and ValhallaInvestDB.prices.good == 12, "ValhallaInvestDB")
local n = 0
for _ in pairs(ns.modules) do n = n + 1 end
ok(n == 0, "scrub does not invent a module")

print("== 4. FitZoom: a map 0 px across is zoom 1, not NaN")
local function Source(file) local f = assert(io.open(root .. file)) local s = f:read("*a") f:close() return s end
local function Chunk(src, head)
  local L = {}
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do L[#L + 1] = line end
  for i, l in ipairs(L) do
    if l:sub(1, #head) == head then
      local out = { l }
      for j = i + 1, #L do
        out[#out + 1] = L[j]
        if L[j] == "end" then return table.concat(out, "\n") end
      end
    end
  end
  error("no chunk " .. head)
end
local function Run(code, env)
  setmetatable(env, { __index = _G })
  local fn = assert(loadstring(code))
  setfenv(fn, env)
  fn()
  return env
end
local env = {
  ns = ns,
  sc = { w = 0, h = 0, GetWidth = function(self) return self.w end, GetHeight = function(self) return self.h end },
  S = {
    Size = function() return 1000, 600 end,
    Rect = function() return 0, 0.5, 0, 0.5 end,
  },
}
function env.FitPx()
  local W, H = env.S.Size()
  return math.min(env.sc:GetWidth() / W, env.sc:GetHeight() / H)
end
Run(Chunk(Source("Map/WorldMap.lua"), "local function FitZoom(mapID)"):gsub("^local ", ""), env)
ok(env.FitZoom(1) == 1, "width 0: 1, not NaN", tostring(env.FitZoom(1)))
env.sc.w, env.sc.h = 500, 500
local z = env.FitZoom(1)
ok(z == 2, "a real size: the zone's fit, unchanged", tostring(z))
env.S.Rect = function() return 0, 1, 0, 1 end
ok(env.FitZoom(1) == 1, "the whole world in a 500 px view: zoom 1", tostring(env.FitZoom(1)))

print("== 5. the guards are in the source, ahead of the write")
local wm = Source("Map/WorldMap.lua")
local fitAt = wm:find("return ns.Safe.Finite(z) and z > 0 and z or 1", 1, true)
local setAt = wm:find("if not ns.Safe.Finite(scale, x, y) or scale <= 0 then return end", 1, true)
local writeAt = wm:find("sc.currentScale, sc.targetScale, sc.zoomTarget = scale, scale, scale", 1, true)
local viewAt = wm:find("if not ns.Safe.Finite(zoom) or zoom <= 0 then zoom = 1 end", 1, true)
ok(fitAt and setAt and writeAt and setAt < writeAt and viewAt, "FitZoom, View and SetView check before the canvas is written", tostring(setAt) .. " " .. tostring(writeAt))
local win = Source("Map/Window.lua")
ok(win:find("if w0 and not ns.Safe.Finite(w0[3], w0[4]) then mod.db.window = false end", 1, true) ~= nil, "a saved window place that isn't a number is forgotten")
ok(win:find("if s0 and not (ns.Safe.Finite(s0[1], s0[2]) and s0[1] >= 1 and s0[2] >= 1) then mod.db.windowSize = false end", 1, true) ~= nil, "a saved window size that isn't a number is forgotten")
ok(win:find("if not ns.Safe.Finite(mod.db.windowScale) or mod.db.windowScale <= 0 then mod.db.windowScale = 1 end", 1, true) ~= nil, "a saved window scale that isn't a number is 1")
ok(win:find("if point and ns.Safe.Finite(x, y) then mod.db.window", 1, true) ~= nil, "Save refuses a NaN place")
ok(win:find("if not ns.Safe.Finite(s) or s <= 0 then return end", 1, true) ~= nil, "a resize with no scale does not divide")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
