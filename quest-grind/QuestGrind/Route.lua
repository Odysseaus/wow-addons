local _, NS = ...

-- P1: distance/text ticker (~0.25s) + 0.2.6 per-frame compass animator.
-- The arrow re-reads facing and player position every frame (position at
-- ~20 Hz) and eases toward the target angle, so turning is smooth instead of
-- stepping every 0.25s. Forever-safe.

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

-- Convert map-norm (0..1) on uiMapID to continent world yards.
-- Returns continentID, worldX, worldY or nils. Kept local so Route.lua does not depend on Quests.lua helpers.
local function MapNormToWorld(mapID, mapX, mapY)
  if type(mapID) ~= "number" or type(mapX) ~= "number" or type(mapY) ~= "number" then
    return nil, nil, nil
  end
  if type(C_Map) ~= "table" or type(C_Map.GetWorldPosFromMapPos) ~= "function" then
    return nil, nil, nil
  end
  local vec = { x = mapX, y = mapY }
  if type(CreateVector2D) == "function" then
    local created = SafeCall(CreateVector2D, mapX, mapY)
    if type(created) == "table" then vec = created end
  end
  local ok, a, b = pcall(C_Map.GetWorldPosFromMapPos, mapID, vec)
  if not ok then return nil, nil, nil end
  local continentID, worldPos
  if type(a) == "number" and type(b) == "table" then
    continentID, worldPos = a, b
  elseif type(a) == "table" then
    worldPos = a
    continentID = b
  else
    return nil, nil, nil
  end
  local wx, wy
  if type(worldPos) == "table" then
    if type(worldPos.GetXY) == "function" then
      local okxy, x, y = pcall(worldPos.GetXY, worldPos)
      if okxy and type(x) == "number" and type(y) == "number" then
        wx, wy = x, y
      end
    end
    if type(wx) ~= "number" and type(worldPos.x) == "number" and type(worldPos.y) == "number" then
      wx, wy = worldPos.x, worldPos.y
    end
  end
  if type(wx) ~= "number" or type(wy) ~= "number" then return nil, nil, nil end
  return continentID, wx, wy
end

function NS.ComputeDistanceBearing(tx, ty, tmap)
  if type(tx) ~= "number" or type(ty) ~= "number" then
    return nil, nil, false
  end
  if type(NS.GetPlayerPositions) ~= "function" then
    return nil, nil, false
  end
  local pos = NS.GetPlayerPositions()
  if type(pos) ~= "table" then
    return nil, nil, false
  end

  -- 1) Same-continent world yards: map-norm on tmap → world, compared to UnitPosition.
  if pos.worldX and pos.worldY and type(tmap) == "number" then
    local tCont, twx, twy = MapNormToWorld(tmap, tx, ty)
    if twx and twy then
      local pCont = pos.worldMapID
      if tCont == nil or pCont == nil or tCont == pCont then
        local dx = twx - pos.worldX
        local dy = twy - pos.worldY
        local dist = math.sqrt(dx * dx + dy * dy)
        return dist, NS.BearingFromDelta(dx, dy, "world"), true
      end
    end
  end

  -- 2) Same uiMapID, or tmap unknown: map-norm ×1000. Never raw-compare a different map.
  local pMap = pos.mapID
  if pos.mapX and pos.mapY and (tmap == nil or tmap == pMap) then
    local dx = tx - pos.mapX
    local dy = ty - pos.mapY
    local dist = math.sqrt(dx * dx + dy * dy) * 1000
    return dist, NS.BearingFromDelta(dx, dy, "map"), true
  end

  -- 3) Different maps: project the player onto tmap, then map-norm ×1000.
  if type(tmap) == "number" and type(C_Map) == "table" and type(C_Map.GetPlayerMapPosition) == "function" then
    local p = SafeCall(C_Map.GetPlayerMapPosition, tmap, "player")
    local px, py
    if type(p) == "table" then
      if type(p.GetXY) == "function" then
        local okxy, x, y = pcall(p.GetXY, p)
        if okxy and type(x) == "number" and type(y) == "number" then
          px, py = x, y
        end
      end
      if type(px) ~= "number" and type(p.x) == "number" and type(p.y) == "number" then
        px, py = p.x, p.y
      end
    end
    if type(px) == "number" and type(py) == "number" and (px > 0 or py > 0) and px <= 1 and py <= 1 then
      local dx = tx - px
      local dy = ty - py
      local dist = math.sqrt(dx * dx + dy * dy) * 1000
      return dist, NS.BearingFromDelta(dx, dy, "map"), true
    end
  end

  -- 4) Incomparable — do not fake a cross-map map-norm ×1000.
  return nil, nil, false
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
-- unless the angle changed by more than ~0.1 degree (0.2.6: was 0.5 — the
-- easing animator below removes jitter, so the deadzone can be tiny).
-- bearingDeg == nil hides the arrow (no false north). A numeric bearing,
-- including mock bearingDeg, shows and aims it.
local ROT_EPS = math.rad(0.1)

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

-- Target bearing (deg CW from north) the animator aims at. nil = hidden.
NS._needleBearing = nil
local needlesVisible = false

local function ApplyNeedleRadians(rel)
  local needles = EachNeedle()
  local i
  for i = 1, #needles do
    NS.SetNeedleRotation(needles[i], rel)
  end
end

function NS.UpdateCompassNeedles(bearingDeg)
  local needles = EachNeedle()
  local i
  if bearingDeg == nil then
    NS._needleBearing = nil
    needlesVisible = false
    for i = 1, #needles do
      ShowArrow(needles[i], false)
    end
    return
  end
  NS._needleBearing = bearingDeg
  local firstShow = not needlesVisible
  needlesVisible = true
  for i = 1, #needles do
    ShowArrow(needles[i], true)
  end
  -- Without the animator (or on first show) aim immediately; otherwise the
  -- animator eases toward the new target next frame.
  if firstShow or not NS._compassAnimating then
    local rel = NS.ArrowRadians(bearingDeg) or 0
    NS._needleShown = rel
    ApplyNeedleRadians(rel)
  end
end

-- ===== 0.2.6 compass animator =====
-- Exponential ease toward the facing-relative target. SMOOTH_K = 1/time-constant:
-- 16 -> ~90% of a turn caught up in ~0.14s. Big jumps (new quest) snap.
local SMOOTH_K = 16
local SNAP_RAD = math.rad(150)
local POS_EVERY = 0.05
local posAcc = 0
local TWO_PI = math.pi * 2

local function ShortestDelta(from, to)
  local d = (to - from) % TWO_PI
  if d > math.pi then d = d - TWO_PI end
  return d
end

-- Live bearing from the focused route's cached target and the player's
-- current position (same math as Quests.ComputeNav).
local function LiveBearing(route)
  if type(route) ~= "table" or route.source ~= "live" or not route.hasCoords then return nil end
  if not NS.GetPlayerPositions then return nil end
  local pos = NS.GetPlayerPositions()
  local tx, ty, kind
  if route.targetCoordKind == "world" and type(route.targetX) == "number" and pos.worldX then
    tx, ty, kind = route.targetX, route.targetY, "world"
    return NS.BearingFromDelta(tx - pos.worldX, ty - pos.worldY, kind)
  end
  local mx, my = route.mapX, route.mapY
  if type(mx) ~= "number" and route.targetCoordKind == "map" then mx, my = route.targetX, route.targetY end
  if type(mx) == "number" and type(my) == "number" and pos.mapX then
    return NS.BearingFromDelta(mx - pos.mapX, my - pos.mapY, "map")
  end
  return nil
end

local function AnyNeedleVisible()
  local needles = EachNeedle()
  local i
  for i = 1, #needles do
    local n = needles[i]
    if n and type(n.IsVisible) == "function" then
      local ok, v = pcall(n.IsVisible, n)
      if ok and v then return true end
    end
  end
  return false
end

local function AnimateCompass(elapsed)
  if not needlesVisible or NS._needleBearing == nil then return end
  if not AnyNeedleVisible() then return end
  elapsed = elapsed or 0
  if elapsed > 0.25 then elapsed = 0.25 end
  posAcc = posAcc + elapsed
  if posAcc >= POS_EVERY then
    posAcc = 0
    local b = LiveBearing(NS.liveRoute)
    if b then NS._needleBearing = b end
  end
  local target = NS.ArrowRadians(NS._needleBearing)
  if type(target) ~= "number" then return end
  local shown = NS._needleShown
  if type(shown) ~= "number" then
    shown = target
  else
    local d = ShortestDelta(shown, target)
    if math.abs(d) >= SNAP_RAD then
      shown = target
    else
      local a = 1 - math.exp(-SMOOTH_K * elapsed)
      shown = shown + d * a
      if math.abs(ShortestDelta(shown, target)) < ROT_EPS then shown = target end
    end
  end
  shown = shown % TWO_PI
  NS._needleShown = shown
  ApplyNeedleRadians(shown)
end

local animFrame
function NS.StartCompassAnimator()
  if animFrame or type(CreateFrame) ~= "function" then return end
  animFrame = CreateFrame("Frame", "QuestGrindCompassAnim")
  animFrame:SetScript("OnUpdate", function(_, elapsed)
    local ok, err = pcall(AnimateCompass, elapsed)
    if not ok then
      -- Never spam: stop animating and fall back to the 0.25s ticker aim.
      NS._compassAnimating = false
      animFrame:SetScript("OnUpdate", nil)
      if NS.Print then NS.Print("compass animator off: " .. tostring(err)) end
    end
  end)
  NS._compassAnimating = true
end

function NS.StopCompassAnimator()
  if animFrame then
    animFrame:SetScript("OnUpdate", nil)
    animFrame = nil
  end
  NS._compassAnimating = false
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
  if NS.StartCompassAnimator then NS.StartCompassAnimator() end
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
  if NS.StopCompassAnimator then NS.StopCompassAnimator() end
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
