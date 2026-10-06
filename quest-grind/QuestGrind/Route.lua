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

-- Needle rotation: radians from up (0 = north / ahead on face). Geometric tip+tail
-- pivot always works; SetRotation is best-effort on Forever ColorTextures.
function NS.SetNeedleRotation(needleFrame, radians)
  if not needleFrame then return end
  radians = radians or 0
  needleFrame._qgRadians = radians

  local parent = needleFrame.GetParent and needleFrame:GetParent()
  if parent and needleFrame.ClearAllPoints and needleFrame.SetPoint then
    -- Pivot stays glued to face center (no off-center rectangle nudge).
    needleFrame:ClearAllPoints()
    needleFrame:SetPoint("CENTER", parent, "CENTER", 0, 0)
  end

  local ox = math.sin(radians)
  local oy = math.cos(radians)

  if needleFrame._qgNeedle then
    local tipLen = needleFrame.tipLen or 40
    local tipW = needleFrame.tipW or 7
    local tailLen = needleFrame.tailLen or 16
    local tailW = needleFrame.tailW or 5

    if needleFrame.tip then
      local mid = tipLen * 0.48
      needleFrame.tip:ClearAllPoints()
      needleFrame.tip:SetSize(tipW, tipLen)
      needleFrame.tip:SetPoint("CENTER", needleFrame, "CENTER", ox * mid, oy * mid)
      if type(needleFrame.tip.SetRotation) == "function" then
        pcall(needleFrame.tip.SetRotation, needleFrame.tip, radians)
      end
      if needleFrame.tip.tex and type(needleFrame.tip.tex.SetRotation) == "function" then
        pcall(needleFrame.tip.tex.SetRotation, needleFrame.tip.tex, radians)
      end
    end
    if needleFrame.tail then
      local mid = tailLen * 0.48
      needleFrame.tail:ClearAllPoints()
      needleFrame.tail:SetSize(tailW, tailLen)
      needleFrame.tail:SetPoint("CENTER", needleFrame, "CENTER", -ox * mid, -oy * mid)
      if type(needleFrame.tail.SetRotation) == "function" then
        pcall(needleFrame.tail.SetRotation, needleFrame.tail, radians)
      end
      if needleFrame.tail.tex and type(needleFrame.tail.tex.SetRotation) == "function" then
        pcall(needleFrame.tail.tex.SetRotation, needleFrame.tail.tex, radians)
      end
    end
    if needleFrame.hub then
      needleFrame.hub:ClearAllPoints()
      needleFrame.hub:SetPoint("CENTER", needleFrame, "CENTER", 0, 0)
    end
    -- Direction tip glyph always tracks bearing even when texture rotation fails.
    if needleFrame.glyph then
      local reach = tipLen * 0.92
      needleFrame.glyph:ClearAllPoints()
      needleFrame.glyph:SetPoint("CENTER", needleFrame, "CENTER", ox * reach, oy * reach)
    end
    return
  end

  -- Legacy Solid rectangle: rotate in place only (no center nudge).
  local tex = needleFrame.tex
  if tex and type(tex.SetRotation) == "function" then
    pcall(tex.SetRotation, tex, radians)
  end
  if type(needleFrame.SetRotation) == "function" then
    pcall(needleFrame.SetRotation, needleFrame, radians)
  end
end

function NS.UpdateCompassNeedles(bearingDeg)
  if bearingDeg == nil then return end
  local facing = SafeCall(GetPlayerFacing)
  local rel
  if type(facing) == "number" then
    local facingDeg = math.deg(facing)
    rel = math.rad((bearingDeg - facingDeg + 360) % 360)
  else
    -- No facing API: point by absolute bearing, 0 = north.
    rel = math.rad(bearingDeg % 360)
  end
  local layers = NS.layers
  if not layers then return end
  -- Compass-only face is updated even when Full/Less layers are hidden.
  if layers.compassOnlyFace and layers.compassOnlyFace.needle then
    NS.SetNeedleRotation(layers.compassOnlyFace.needle, rel)
  end
  if layers.compassLarge and layers.compassLarge.needle then
    NS.SetNeedleRotation(layers.compassLarge.needle, rel)
  end
  if layers.lessCompass and layers.lessCompass.needle then
    NS.SetNeedleRotation(layers.lessCompass.needle, rel)
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
      -- 0.25s: distance, bearing, needle. POI reprobe lives in RefreshFocusedNav
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
        -- Drop a stale mock angle when the live quest has no bearing yet.
        NS.UpdateCompassNeedles(0)
      elseif route.bearingDeg ~= nil then
        NS.UpdateCompassNeedles(route.bearingDeg)
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
