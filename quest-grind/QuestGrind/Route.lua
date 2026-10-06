local _, NS = ...

-- P1: distance/compass ticker. Throttled ~0.25s. Forever-safe.

local ticker
local updateFrame
local elapsedAcc = 0
local enumAcc = 0
local TICK = 0.25
local ENUM_EVERY = 1.0

function NS.NoteRouteEnum()
  enumAcc = 0
end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function SafeRegister(frame, event)
  if not frame or not event then return end
  local ok = pcall(function() frame:RegisterEvent(event) end)
  return ok
end

-- Bearing convention (0.2.5): bearingDeg is a compass bearing, degrees
-- CLOCKWISE from north (E = 90), for both coord kinds:
--   map   : normalized x grows east, y grows south  -> atan2(dx, -dy)
--   world : UnitPosition order is (y, x); worldX grows north, worldY grows
--           west, so east = -dy, north = dx         -> atan2(-dy, dx)
function NS.BearingFromDelta(dx, dy, kind)
  local deg
  if kind == "world" then
    deg = math.deg(math.atan2(-dy, dx))
  else
    deg = math.deg(math.atan2(dx, -dy))
  end
  if deg < 0 then deg = deg + 360 end
  return deg
end

-- Screen rotation for a compass arrow, radians COUNTER-CLOCKWISE from up
-- (Texture:SetRotation convention). GetPlayerFacing is radians CCW from north,
-- bearing is CW from north, so the target's CCW angle is -bearing and the
-- arrow turns by (-bearing - facing). Without a facing API the arrow sits on
-- a north-up rose: -bearing.
function NS.ArrowRadians(bearingDeg)
  if type(bearingDeg) ~= "number" then return nil end
  local facing = SafeCall(GetPlayerFacing)
  local facingDeg = 0
  if type(facing) == "number" then facingDeg = math.deg(facing) end
  return math.rad((-bearingDeg - facingDeg) % 360)
end

function NS.ComputeDistanceBearing(tx, ty, tmap)
  local px, py, pmap, kind = NS.GetPlayerMapPosition()
  if not (px and py and tx and ty) then
    return nil, nil, false
  end
  local dx = tx - px
  local dy = ty - py
  local dist
  if kind == "world" then
    dist = math.sqrt(dx * dx + dy * dy)
  else
    dist = math.sqrt(dx * dx + dy * dy) * 1000
  end
  return dist, NS.BearingFromDelta(dx, dy, kind), true
end

local function FormatDistance(yards)
  if not yards then return "?" end
  if yards >= 1000 then
    return string.format("%.1fk yd", yards / 1000)
  end
  return string.format("%d yd", math.floor(yards + 0.5))
end

local function Cardinal(deg)
  if not deg then return "unknown" end
  local d = deg % 360
  if d < 0 then d = d + 360 end
  local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
  local idx = math.floor((d + 22.5) / 45) % 8 + 1
  return dirs[idx]
end

local function RelativeBearing(targetDeg)
  if not targetDeg then return "unknown" end
  local facing = SafeCall(GetPlayerFacing)
  if not facing then
    return Cardinal(targetDeg)
  end
  local facingDeg = math.deg(facing)
  -- CCW delta (positive = left): target CCW angle is -bearing.
  local delta = (-targetDeg - facingDeg + 180) % 360 - 180
  local ad = math.abs(delta)
  if ad < 25 then return "ahead"
  elseif ad > 155 then return "behind"
  elseif delta > 0 then return "left"
  else return "right"
  end
end

-- Arrow convention (0.2.5):
-- MinimapArrow points up at 0 radians. Texture:SetRotation is
-- counter-clockwise positive and rotates around the texture center.
-- Callers pass NS.ArrowRadians(bearingDeg) (CCW from up, facing-relative),
-- so SetRotation(radians) aims the arrow at the quest as the player turns.
-- The arrow frame stays at face CENTER (never moved). Skip SetRotation
-- unless the angle changed by more than ~0.5 degree (anti-jitter).
-- bearingDeg == nil hides the arrow (no false north). A numeric bearing,
-- including mock bearingDeg, shows and aims it.
local ROT_EPS = math.rad(0.5)

local function ShowArrow(needleFrame, visible)
  if not needleFrame then return end
  if needleFrame._qgCanRotate and needleFrame.tex then
    if visible then
      if needleFrame.tex.Show then needleFrame.tex:Show() end
    else
      if needleFrame.tex.Hide then needleFrame.tex:Hide() end
    end
    if needleFrame.glyph and needleFrame.glyph.Hide then needleFrame.glyph:Hide() end
  else
    if needleFrame.tex and needleFrame.tex.Hide then needleFrame.tex:Hide() end
    if needleFrame.glyph then
      if visible then
        if needleFrame.glyph.Show then needleFrame.glyph:Show() end
      else
        if needleFrame.glyph.Hide then needleFrame.glyph:Hide() end
      end
    end
  end
end

local function AngleChanged(prev, radians)
  if type(prev) ~= "number" then return true end
  local d = math.abs(radians - prev)
  if d > math.pi then d = (math.pi * 2) - d end
  return d > ROT_EPS
end

function NS.SetNeedleRotation(needleFrame, radians)
  if not needleFrame then return end
  if type(radians) ~= "number" then radians = 0 end
  local twopi = math.pi * 2
  radians = radians % twopi
  if radians < 0 then radians = radians + twopi end

  local changed = AngleChanged(needleFrame._qgRadians, radians)
  if changed then
    needleFrame._qgRadians = radians
  end

  if needleFrame._qgCanRotate and needleFrame.tex and type(needleFrame.tex.SetRotation) == "function" then
    if not changed then return end
    local ok = pcall(needleFrame.tex.SetRotation, needleFrame.tex, radians)
    if ok then return end
    -- SetRotation threw: drop to the single glyph for this face.
    needleFrame._qgCanRotate = false
    if needleFrame.tex.Hide then needleFrame.tex:Hide() end
    if needleFrame.glyph and needleFrame.glyph.Show then needleFrame.glyph:Show() end
  end

  if not changed then return end
  if needleFrame.glyph and needleFrame.glyph.ClearAllPoints and needleFrame.glyph.SetPoint then
    local radius = needleFrame._qgGlyphRadius or 24
    -- 0 rad = up, CCW positive (same as SetRotation): x = -sin, y = cos.
    local ox = -math.sin(radians) * radius
    local oy = math.cos(radians) * radius
    needleFrame.glyph:ClearAllPoints()
    needleFrame.glyph:SetPoint("CENTER", needleFrame, "CENTER", ox, oy)
  end
end

local function EachNeedle()
  local list = {}
  local layers = NS.layers
  if not layers then return list end
  -- Compass-only face is included even when Full/Less layers are hidden.
  if layers.compassOnlyFace and layers.compassOnlyFace.needle then
    list[#list + 1] = layers.compassOnlyFace.needle
  end
  if layers.compassLarge and layers.compassLarge.needle then
    list[#list + 1] = layers.compassLarge.needle
  end
  if layers.lessCompass and layers.lessCompass.needle then
    list[#list + 1] = layers.lessCompass.needle
  end
  return list
end

function NS.UpdateCompassNeedles(bearingDeg)
  local needles = EachNeedle()
  if bearingDeg == nil then
    local i
    for i = 1, #needles do
      ShowArrow(needles[i], false)
    end
    return
  end
  local rel = NS.ArrowRadians(bearingDeg) or 0
  local i
  for i = 1, #needles do
    ShowArrow(needles[i], true)
    NS.SetNeedleRotation(needles[i], rel)
  end
end

function NS.TickRoute()
  local nested = NS._refreshing
  if NS.PushRefresh then NS.PushRefresh() end
  local ok, err = pcall(function()
    local forceMock = NS.forceMock or (NS.db and NS.db.forceMock)
    enumAcc = enumAcc + TICK
    local wantFull = (not forceMock) and enumAcc >= (ENUM_EVERY - 0.001)

    local route = NS.liveRoute
    if forceMock then
      if (not route or route.source ~= "mock") and NS.GetLiveRoute then
        route = NS.GetLiveRoute()
      end
    elseif not nested and (wantFull or not route or route.source ~= "live") and NS.GetLiveRoute then
      enumAcc = 0
      route = NS.GetLiveRoute()
      if route and NS.ApplyRoute then
        NS.ApplyRoute(route)
      end
    elseif route and route.source == "live" and NS.RefreshFocusedNav then
      -- 0.25s: distance, bearing, arrow. POI reprobe lives in RefreshFocusedNav
      -- so a quest that starts without coords can still acquire them.
      NS.RefreshFocusedNav(route)
    end

    if route then
      if NS.RefreshRouteUI then
        NS.RefreshRouteUI(route)
      end
      if route.hasCoords and route.bearingDeg ~= nil then
        NS.UpdateCompassNeedles(route.bearingDeg)
      elseif route.source == "live" then
        -- No coords: hide the arrow. Do not aim it north.
        NS.UpdateCompassNeedles(nil)
      elseif route.bearingDeg ~= nil then
        -- Mock route with bearingDeg may still point.
        NS.UpdateCompassNeedles(route.bearingDeg)
      else
        NS.UpdateCompassNeedles(nil)
      end
      if NS.UpdateMapPins then
        NS.UpdateMapPins(route)
      end
    end
  end)
  if NS.PopRefresh then NS.PopRefresh() end
  if not ok then
    local shown = false
    if type(geterrorhandler) == "function" then
      local handler = geterrorhandler()
      if type(handler) == "function" then
        handler(err)
        shown = true
      end
    end
    if not shown and NS.Print then
      NS.Print("route error: " .. tostring(err))
    end
  end
end

function NS.StartRouteTicker()
  if ticker or updateFrame then return end
  if C_Timer and type(C_Timer.NewTicker) == "function" then
    ticker = C_Timer.NewTicker(TICK, function()
      NS.TickRoute()
    end)
    return
  end
  updateFrame = CreateFrame("Frame", "QuestGrindRouteTicker")
  elapsedAcc = 0
  updateFrame:SetScript("OnUpdate", function(_, elapsed)
    elapsedAcc = elapsedAcc + (elapsed or 0)
    if elapsedAcc >= TICK then
      elapsedAcc = 0
      NS.TickRoute()
    end
  end)
end

function NS.StopRouteTicker()
  if ticker then
    if type(ticker.Cancel) == "function" then
      pcall(ticker.Cancel, ticker)
    end
    ticker = nil
  end
  if updateFrame then
    updateFrame:SetScript("OnUpdate", nil)
    updateFrame = nil
  end
end

local routeEv = CreateFrame("Frame")
SafeRegister(routeEv, "ZONE_CHANGED_NEW_AREA")
SafeRegister(routeEv, "ZONE_CHANGED")
SafeRegister(routeEv, "ZONE_CHANGED_INDOORS")
SafeRegister(routeEv, "PLAYER_STARTED_MOVING")
SafeRegister(routeEv, "PLAYER_STOPPED_MOVING")
routeEv:SetScript("OnEvent", function(_, event)
  if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
    if NS.Refresh then
      NS.Refresh()
    else
      NS.TickRoute()
    end
  else
    NS.TickRoute()
  end
end)
