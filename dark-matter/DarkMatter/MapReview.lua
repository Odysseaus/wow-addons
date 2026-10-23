-- MapReview.lua (0.5.2b.8): checks of the two-pass zone masks in the game. Nothing here changes saved settings
-- except DarkMatterDB.map.shot (the last /dm shottest result).
--   /dm shottest         takes ONE screenshot (the game's Screenshot(), into the game's Screenshots folder) and
--                        records whether the game reported SCREENSHOT_SUCCEEDED; /dm seamsweep needs it to have passed
--   /dm seamsweep [N]    the map open: for the N worst zone borders (Data_ZoneSeams.lua, from the box border review)
--                        centres the map on the border at zoom levels 4, 8 and 12 and takes a screenshot of each
--                        (N defaults to 8; /dm seamsweep stop). Refused until /dm shottest has passed.
--   /dm mapcost [both]   the map open: steps through zoom levels 1, 2, 3, 4, 6, 8, 10 at the current centre, waits for
--                        the pictures to load, and records the frame rate and the textures built and on screen; both =
--                        once with the core pass and once without (/dm mapcore), then puts it back
--   probe line           R.ShotLine(): whether the game has Screenshot() and its events, without taking a shot
local _, NS = ...
local R = {}
NS.MapReview = R

R.SEAM_LEVELS = { 4, 8, 12 }
R.COST_LEVELS = { 1, 2, 3, 4, 6, 8, 10 }
R.SETTLE = 1.5     -- seconds for a view's pictures to load before it is measured / shot
R.SHOT_WAIT = 4.0  -- seconds to wait for the game's screenshot event

local function Out(msg) if NS.Print then NS.Print(msg) else print(msg) end end
local function M() return NS.MapTab end
local function Map() local db = NS.db if not db then return nil end db.map = db.map or {} return db.map end

-- a timer that works with or without C_Timer
local ticker
local queue = {}
function R.After(sec, fn)
  if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(sec, fn) return end
  if not ticker then
    ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, el)
      for i = #queue, 1, -1 do
        local q = queue[i]
        q.t = q.t - (el or 0)
        if q.t <= 0 then table.remove(queue, i) q.fn() end
      end
    end)
  end
  queue[#queue + 1] = { t = sec, fn = fn }
end

---------------------------------------------------------------------------
-- screenshots
---------------------------------------------------------------------------
local events, waiting
-- the screenshot events (also called directly by the stub tests)
function R.ShotEvent(e)
  local w = waiting
  waiting = nil
  if w then w(e == "SCREENSHOT_SUCCEEDED" and "ok" or "failed") end
end
local function EventFrame()
  if events then return events end
  events = CreateFrame("Frame")
  R.eventsOK = {}
  for _, e in ipairs({ "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED" }) do
    local ok = pcall(events.RegisterEvent, events, e)
    R.eventsOK[e] = ok
  end
  events:SetScript("OnEvent", function(_, e) R.ShotEvent(e) end)
  return events
end
-- take one screenshot; done(result) with "ok", "failed" (the game said so), "no event" (nothing heard) or an error
local function Shot(done)
  if type(Screenshot) ~= "function" then done("no Screenshot()") return end
  EventFrame()
  local id = {}
  R.shotId = id
  waiting = function(r) if R.shotId == id then R.shotId = nil done(r) end end
  local ok, err = pcall(Screenshot)
  if not ok then waiting = nil R.shotId = nil done("error: " .. tostring(err)) return end
  R.After(R.SHOT_WAIT, function()
    if R.shotId == id then R.shotId, waiting = nil, nil done("no event") end
  end)
end
R.Shot = Shot

-- the probe's two short parts: what the client offers, and the last /dm shottest
function R.ShotParts()
  local m = Map()
  local last = m and type(m.shot) == "table" and m.shot
  local evs = R.eventsOK and string.format("events %s/%s", R.eventsOK.SCREENSHOT_SUCCEEDED and "ok" or "no", R.eventsOK.SCREENSHOT_FAILED and "ok" or "no")
    or "events not yet registered"
  return string.format("Screenshot() %s, %s", type(Screenshot) == "function" and "present" or "MISSING", evs),
    last and (tostring(last.result):sub(1, 20) .. " at " .. tostring(last.time) .. " (" .. tostring(last.version) .. ")") or "never"
end
function R.ShotLine()
  local a, b = R.ShotParts()
  return "screenshot: " .. a .. "; last /dm shottest: " .. b
end

function R.ShotTest()
  if R.busy then return { "shottest: busy (" .. R.busy .. ")" } end
  if type(Screenshot) ~= "function" then
    local m = Map()
    if m then m.shot = { result = "no Screenshot()", time = date("%Y-%m-%d %H:%M:%S"), version = NS.version } end
    return { "shottest: this client has no Screenshot() function; /dm seamsweep cannot run" }
  end
  R.busy = "shottest"
  Shot(function(r)
    R.busy = nil
    local m = Map()
    if m then m.shot = { result = r, time = date("%Y-%m-%d %H:%M:%S"), version = NS.version } end
    local lines = { "shottest: " .. (r == "ok" and "PASSED - the game saved a screenshot (in its Screenshots folder)" or ("FAILED - " .. r)),
      R.ShotLine() }
    for _, l in ipairs(lines) do Out(l) end
    if NS.LogProbe then NS.LogProbe("shottest", lines) end
  end)
  return { "shottest: taking one screenshot ..." }
end
function R.ShotOK()
  local m = Map()
  return m and type(m.shot) == "table" and m.shot.result == "ok"
end

---------------------------------------------------------------------------
-- runs that step the map's view
---------------------------------------------------------------------------
local function MapOpen()
  local mt = M()
  return mt and mt.root and mt.root.IsVisible and mt.root:IsVisible() and mt.ViewLevelAt and mt.lastView
end
local function Levels(list)
  local mt = M()
  local mx = mt.MaxLevel and mt.MaxLevel() or 1
  local out, seen = {}, {}
  for _, n in ipairs(list) do
    local v = math.max(1, math.min(mx, n))
    if not seen[v] then seen[v] = true out[#out + 1] = v end
  end
  return out
end
-- run steps one after another (each: fn(next)); finish(lines) at the end or on stop
local function Run(name, steps, lines, finish)
  R.busy, R.stop = name, nil
  local i = 0
  local function Next()
    i = i + 1
    if R.stop or i > #steps or not MapOpen() then
      if R.stop then lines[#lines + 1] = name .. ": stopped" elseif i <= #steps then lines[#lines + 1] = name .. ": the map was closed" end
      R.busy, R.stop = nil, nil
      finish(lines)
      return
    end
    steps[i](Next)
  end
  Next()
end
local function Restore(v)
  local mt = M()
  if v and mt.SetViewAt then mt.SetViewAt(v.cx, v.cy, v.z) end
end

-- the worst N borders of both continents, worst first
function R.Seams(n)
  local all = {}
  for cont, list in pairs(NS.ZoneSeams or {}) do
    for _, s in ipairs(list) do all[#all + 1] = { cont = cont, a = s[1], b = s[2], x = s[3], y = s[4], score = s[5] or 0 } end
  end
  table.sort(all, function(p, q) return p.score > q.score end)
  local out = {}
  for i = 1, math.min(n, #all) do out[i] = all[i] end
  return out
end

function R.SeamSweep(arg)
  arg = (arg or ""):lower()
  if arg:match("^%s*stop") then
    if R.busy then R.stop = true return { "seamsweep: stopping after this step" } end
    return { "seamsweep: nothing running" }
  end
  if R.busy then return { "seamsweep: busy (" .. R.busy .. "); /dm seamsweep stop" } end
  if not R.ShotOK() then return { "seamsweep: run /dm shottest first (it must pass: " .. R.ShotLine() .. ")" } end
  if InCombatLockdown and InCombatLockdown() then return { "seamsweep: not in combat" } end
  if not MapOpen() then return { "seamsweep: open the Dark Matter map first" } end
  local n = math.max(1, math.min(40, tonumber(arg:match("(%d+)")) or 8))
  local seams = R.Seams(n)
  if #seams == 0 then return { "seamsweep: no borders in Data_ZoneSeams.lua" } end
  local mt, MD = M(), NS.MapData
  local back = mt.lastView and { cx = mt.lastView.cx, cy = mt.lastView.cy, z = mt.lastView.z }
  local lv = Levels(R.SEAM_LEVELS)
  local lines = { string.format("seamsweep: %d borders x levels %s (%s)", #seams, table.concat(lv, ","), NS.version or "?") }
  local steps = {}
  for k, s in ipairs(seams) do
    for _, L in ipairs(lv) do
      steps[#steps + 1] = function(Next)
        local wx, wy = mt.ToW(s.cont, s.x, s.y)
        mt.ViewLevelAt(wx, wy, L)
        R.After(R.SETTLE, function()
          Shot(function(r)
            local nm = function(id) return MD and MD.Name and MD.Name(id) or tostring(id) end
            local l = string.format("#%d %s | %s (score %.0f) level %d at %.1f,%.1f: %s", k, nm(s.a), nm(s.b), s.score, L, s.x * 100, s.y * 100, r)
            lines[#lines + 1] = l
            Out(l)
            R.After(0.3, Next)
          end)
        end)
      end
    end
  end
  Run("seamsweep", steps, lines, function(ls)
    Restore(back)
    ls[#ls + 1] = "seamsweep: done; the screenshots are in the game's Screenshots folder, in this order"
    Out(ls[#ls])
    if NS.LogProbe then NS.LogProbe("seamsweep", ls) end
  end)
  return { lines[1] .. string.format(" - about %d s; /dm seamsweep stop", math.floor(#steps * (R.SETTLE + 1) + 0.5)) }
end

-- frame rate: the mean of a few samples over half a second
local function Fps(done)
  local acc, n = 0, 0
  local function Take(left)
    local f = type(GetFramerate) == "function" and GetFramerate() or nil
    if f then acc, n = acc + f, n + 1 end
    if left > 0 then R.After(0.1, function() Take(left - 1) end) else done(n > 0 and acc / n or nil) end
  end
  Take(4)
end

function R.MapCost(arg)
  arg = (arg or ""):lower()
  if arg:match("^%s*stop") then
    if R.busy then R.stop = true return { "mapcost: stopping" } end
    return { "mapcost: nothing running" }
  end
  if R.busy then return { "mapcost: busy (" .. R.busy .. ")" } end
  if not MapOpen() then return { "mapcost: open the Dark Matter map first" } end
  local mt = M()
  local back = { cx = mt.lastView.cx, cy = mt.lastView.cy, z = mt.lastView.z }
  local coreWas = mt.coreOff
  local passes = arg:match("both") and { false, true } or { coreWas and true or false }
  local lv = Levels(R.COST_LEVELS)
  local lines = { string.format("mapcost: levels %s at %.3f,%.3f, core pass %s (%s)", table.concat(lv, ","), back.cx, back.cy,
    #passes == 2 and "on, then off" or (coreWas and "off" or "on"), NS.version or "?") }
  local steps = {}
  for _, off in ipairs(passes) do
    for j, L in ipairs(lv) do
      steps[#steps + 1] = function(Next)
        if j == 1 and (mt.coreOff and true or false) ~= off then
          mt.coreOff = off or nil
          mt.RebuildLayers()
        end
        mt.ViewLevelAt(back.cx, back.cy, L)
        R.After(R.SETTLE, function()
          Fps(function(f)
            local t = mt.TexCount()
            local l = string.format("core %s level %d: %s fps; %d textures on screen in %d layers (%d built: %d tiles, %d overlays, %d core)",
              off and "off" or "on", L, f and string.format("%.0f", f) or "?", t.shownTex, t.shown, t.total, t.tiles, t.ov, t.core)
            lines[#lines + 1] = l
            Out(l)
            Next()
          end)
        end)
      end
    end
  end
  Run("mapcost", steps, lines, function(ls)
    if (mt.coreOff and true or false) ~= (coreWas and true or false) then mt.coreOff = coreWas mt.RebuildLayers() end
    Restore(back)
    ls[#ls + 1] = "mapcost: done (view and core setting put back)"
    Out(ls[#ls])
    if NS.LogProbe then NS.LogProbe("mapcost", ls) end
  end)
  return { lines[1] .. string.format(" - about %d s", math.floor(#steps * (R.SETTLE + 0.5) + 0.5)) }
end
