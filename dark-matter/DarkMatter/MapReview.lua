-- MapReview.lua (0.5.2b.8, sweep 0.5.2b.8.1): checks of the two-pass zone masks in the game. Nothing here changes
-- saved settings except DarkMatterDB.map.shot (the last /dm shottest result).
--   /dm shottest         takes ONE screenshot (the game's Screenshot(), into the game's Screenshots folder) and
--                        records whether the game reported SCREENSHOT_SUCCEEDED; /dm seamsweep needs it to have passed
--   /dm seamsweep [N]    the map open: for the N worst zone borders (Data_ZoneSeams.lua, from the box border review)
--                        at zoom levels 4, 8 and 12: centres the map on the first view and shows a Shot button; each
--                        click shoots the view shown and centres the next (N defaults to 8; /dm seamsweep next = one
--                        click; /dm seamsweep stop). Refused until /dm shottest has passed. Screenshot() runs only in a
--                        click or a typed command, never from a timer.
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

-- 0.5.2b.8.1: the sweep is driven by clicks. The game counts a click as the player's own action, and Screenshot() is
-- only ever called inside one: the Shot button's OnClick, /dm seamsweep next, or /dm shottest (both typed). No timer,
-- OnUpdate or event handler ever calls Screenshot(). /dm seamsweep centres the map on the first border; each click on
-- the Shot button (bottom left of the map) shoots the view shown, then centres the next one. The button's text names
-- the view, so it shows in the picture as its caption. Every step is saved to DarkMatterDB.probeLog.seamsweep as it
-- happens (a refusal too), so a sweep left half done still leaves its log.
local sweep, shotBtn
local function Nm(id) local MD = NS.MapData return MD and MD.Name and MD.Name(id) or tostring(id) end
local function SweepLog(line)
  if line then
    if sweep then sweep.lines[#sweep.lines + 1] = line end
    Out(line)
  end
  if NS.LogProbe then NS.LogProbe("seamsweep", sweep and sweep.lines or { line }) end
end
local function Refuse(line) if NS.LogProbe then NS.LogProbe("seamsweep", { line }) end return { line } end -- the slash prints it
local function ViewLabel(v) return string.format("#%d %s | %s (score %.0f) level %d", v.k, Nm(v.s.a), Nm(v.s.b), v.s.score, v.L) end
local function ButtonText()
  if not (shotBtn and sweep) then return end
  local v = sweep.views[sweep.i]
  shotBtn:SetText(v and string.format("Shot %d/%d: %s", sweep.i, #sweep.views, ViewLabel(v)) or "Shot")
end
local function Centre()
  local mt = M()
  local v = sweep.views[sweep.i]
  local wx, wy = mt.ToW(v.s.cont, v.s.x, v.s.y)
  mt.ViewLevelAt(wx, wy, v.L)
  local lv = mt.lastView
  sweep.at = lv and { cx = lv.cx, cy = lv.cy, z = lv.z }
  ButtonText()
end
local function Finish(line)
  local s = sweep
  if not s then return end
  if line then s.lines[#s.lines + 1] = line Out(line) end
  if MapOpen() then Restore(s.back) end
  local done = string.format("seamsweep: %d of %d shots taken; the screenshots are in the game's Screenshots folder, in this order",
    s.taken, #s.views)
  s.lines[#s.lines + 1] = done
  Out(done)
  if NS.LogProbe then NS.LogProbe("seamsweep", s.lines) end
  sweep, R.busy = nil, nil
  if shotBtn then shotBtn:Hide() end
end
local function Moved()
  local lv, at = M().lastView, sweep.at
  if not (lv and at) then return true end
  return math.abs(lv.cx - at.cx) > 1e-4 or math.abs(lv.cy - at.cy) > 1e-4 or math.abs(lv.z - at.z) > 1e-3 * math.max(1, at.z)
end
-- one step, from a click (the Shot button) or from /dm seamsweep next (typed); never from a timer
function R.SweepClick()
  if not sweep then return { "seamsweep: nothing running (/dm seamsweep [N] starts one)" } end
  if sweep.waiting then return { "seamsweep: waiting for the game's screenshot" } end
  if not MapOpen() then Finish("seamsweep: the map was closed") return { "seamsweep: stopped" } end
  if InCombatLockdown and InCombatLockdown() then return { "seamsweep: not in combat (click again after it)" } end
  if Moved() then
    Centre()
    SweepLog("seamsweep: the map had moved; centred on " .. ViewLabel(sweep.views[sweep.i]) .. " again - click Shot")
    return {}
  end
  local v, s = sweep.views[sweep.i], sweep
  s.waiting = true
  Shot(function(r)
    if sweep ~= s then return end
    s.waiting = nil
    if r == "ok" then s.taken = s.taken + 1 end
    SweepLog(string.format("%s at %.1f,%.1f: %s", ViewLabel(v), v.s.x * 100, v.s.y * 100, r))
    s.i = s.i + 1
    if s.i > #s.views then Finish() elseif MapOpen() then Centre() else Finish("seamsweep: the map was closed") end
  end)
  return {}
end
local function ShotButton()
  local mt = M()
  if not shotBtn then
    shotBtn = CreateFrame("Button", nil, mt.root, "UIPanelButtonTemplate")
    shotBtn:SetSize(360, 22)
    shotBtn:SetScript("OnClick", function() R.SweepClick() end)
    R.shotButton = shotBtn
  end
  shotBtn:SetParent(mt.root)
  shotBtn:ClearAllPoints()
  shotBtn:SetPoint("BOTTOMLEFT", mt.root, "BOTTOMLEFT", 8, 8)
  shotBtn:SetFrameLevel((mt.root:GetFrameLevel() or 1) + 50)
  shotBtn:Enable()
  shotBtn:Show()
  return shotBtn
end

function R.SeamSweep(arg)
  arg = (arg or ""):lower()
  if arg:match("^%s*stop") then
    if sweep then Finish("seamsweep: stopped") return { "seamsweep: stopped" } end
    return { "seamsweep: nothing running" }
  end
  if arg:match("^%s*next") then return R.SweepClick() end
  if sweep then return { "seamsweep: already running - click Shot on the map (or /dm seamsweep next); /dm seamsweep stop" } end
  if R.busy then return Refuse("seamsweep: busy (" .. R.busy .. ")") end
  if not R.ShotOK() then return Refuse("seamsweep: run /dm shottest first (it must pass: " .. R.ShotLine() .. ")") end
  if InCombatLockdown and InCombatLockdown() then return Refuse("seamsweep: not in combat") end
  if not MapOpen() then return Refuse("seamsweep: open the Dark Matter map first (/dm, the Map tab)") end
  local n = math.max(1, math.min(40, tonumber(arg:match("(%d+)")) or 8))
  local seams = R.Seams(n)
  if #seams == 0 then return Refuse("seamsweep: no borders in Data_ZoneSeams.lua") end
  local mt = M()
  local lv = Levels(R.SEAM_LEVELS)
  local views = {}
  for k, s in ipairs(seams) do for _, L in ipairs(lv) do views[#views + 1] = { k = k, s = s, L = L } end end
  sweep = { views = views, i = 1, taken = 0, back = { cx = mt.lastView.cx, cy = mt.lastView.cy, z = mt.lastView.z },
    lines = { string.format("seamsweep: %d borders x levels %s = %d shots, one click each (%s)", #seams, table.concat(lv, ","), #views, NS.version or "?") } }
  R.busy = "seamsweep"
  ShotButton()
  Centre()
  SweepLog()
  Out(sweep.lines[1])
  return { "seamsweep: click Shot (bottom left of the map) once per view; wait for its text to change between clicks; /dm seamsweep stop" }
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
