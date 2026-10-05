local _, NS = ...

-- P1: distance/compass ticker. Throttled ~0.25s. Forever-safe.

local ticker
local updateFrame
local elapsedAcc = 0
local TICK = 0.25

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
  local bearingDeg = math.deg(math.atan2(dx, -dy))
  if bearingDeg < 0 then bearingDeg = bearingDeg + 360 end
  return dist, bearingDeg, true
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
  local delta = (targetDeg - facingDeg + 180) % 360 - 180
  local ad = math.abs(delta)
  if ad < 25 then return "ahead"
  elseif ad > 155 then return "behind"
  elseif delta > 0 then return "left"
  else return "right"
  end
end

-- Needle rotation: WoW SetRotation is radians clockwise from up for textures.
function NS.SetNeedleRotation(needleFrame, radians)
  if not needleFrame then return end
  local tex = needleFrame.tex
  if tex and type(tex.SetRotation) == "function" then
    pcall(tex.SetRotation, tex, radians)
    return
  end
  if type(needleFrame.SetRotation) == "function" then
    pcall(needleFrame.SetRotation, needleFrame, radians)
    return
  end
  -- Approximate: nudge needle offset by bearing (no SetRotation available).
  if needleFrame.SetPoint and needleFrame:GetParent() then
    local ox = math.sin(radians) * 12
    local oy = math.cos(radians) * 12
    needleFrame:ClearAllPoints()
    needleFrame:SetPoint("CENTER", needleFrame:GetParent(), "CENTER", ox, oy)
  end
end

function NS.UpdateCompassNeedles(bearingDeg)
  if bearingDeg == nil then return end
  local facing = SafeCall(GetPlayerFacing)
  local facingDeg = facing and math.deg(facing) or 0
  -- Relative angle for needle pointing toward objective on a north-up rose.
  local rel = math.rad(bearingDeg)
  -- If we have facing, show direction relative to player (needle = where to turn).
  if facing then
    rel = math.rad((bearingDeg - facingDeg + 360) % 360)
  end
  local layers = NS.layers
  if not layers then return end
  if layers.compassLarge and layers.compassLarge.needle then
    NS.SetNeedleRotation(layers.compassLarge.needle, rel)
  end
  if layers.lessCompass and layers.lessCompass.needle then
    NS.SetNeedleRotation(layers.lessCompass.needle, rel)
  end
  if layers.compassOnlyFace and layers.compassOnlyFace.needle then
    NS.SetNeedleRotation(layers.compassOnlyFace.needle, rel)
  end
end

function NS.TickRoute()
  local route = NS.liveRoute
  if not route then
    if NS.GetLiveRoute then route = NS.GetLiveRoute() end
  end
  if not route then return end

  -- Recompute nav when we have target coords (live) or skip for mock.
  if route.source == "live" and route.hasCoords and route.targetX and route.targetY then
    local dist, bearing, ok = NS.ComputeDistanceBearing(route.targetX, route.targetY, route.targetMapID)
    if ok then
      route.distanceYards = dist
      route.bearingDeg = bearing
      route.step.distance = FormatDistance(dist)
      route.step.bearing = RelativeBearing(bearing)
      route.step.approx = "approx."
      route.step.zone = (SafeCall(GetRealZoneText) or SafeCall(GetZoneText) or route.step.zone or "?")
    end
  elseif route.source == "live" and not route.hasCoords then
    route.step.distance = "?"
    route.step.bearing = "unknown"
    route.step.approx = "no coords"
    route.step.zone = SafeCall(GetRealZoneText) or SafeCall(GetZoneText) or route.step.zone or "?"
  end

  if NS.RefreshRouteUI then
    NS.RefreshRouteUI(route)
  end
  if route.bearingDeg then
    NS.UpdateCompassNeedles(route.bearingDeg)
  end
  if NS.UpdateMinimapArrow then
    NS.UpdateMinimapArrow(route)
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
