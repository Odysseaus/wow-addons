local _, NS = ...

-- 0.2.9: MAIN world-map route only (minimap overlays dropped).
-- Up to 7 numbered stops in QuestGrind completion order. First objective is
-- the START of the route (no line from map center / player to #1). Chain
-- locations share one order number; distinct quests get distinct colors.
-- Lines stop short of Blizzard quest icons; untriggered chain steps get
-- QuestGrind number circles (no Blizzard pin yet).

local MAX_STOPS = 7
local ICON_CLEAR_PX = 16 -- pull line endpoints short of icon centers
local PIN_SIZE = 22
local LINE_THICK = 2.5

local overlay
local pins = {}
local lines = {}
local hookedMap = false
local lastDrawKey = nil

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function FindWorldMapParent()
  if not WorldMapFrame then return nil end
  if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child then
    return WorldMapFrame.ScrollContainer.Child
  end
  if WorldMapFrame.ScrollContainer then return WorldMapFrame.ScrollContainer end
  if WorldMapDetailFrame then return WorldMapDetailFrame end
  if WorldMapButton then return WorldMapButton end
  return WorldMapFrame
end

local function CurrentMapID()
  if WorldMapFrame and type(WorldMapFrame.GetMapID) == "function" then
    local id = SafeCall(WorldMapFrame.GetMapID, WorldMapFrame)
    if type(id) == "number" then return id end
  end
  if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
    local id = SafeCall(C_Map.GetBestMapForUnit, "player")
    if type(id) == "number" then return id end
  end
  return nil
end

local function EnsureOverlay()
  if overlay and overlay:GetParent() then return overlay end
  local parent = FindWorldMapParent()
  if not parent then return nil end
  local f = CreateFrame("Frame", "QuestGrindMapRoute", parent)
  f:SetAllPoints(parent)
  f:SetFrameStrata("TOOLTIP")
  local base = 0
  if parent.GetFrameLevel then base = parent:GetFrameLevel() or 0 end
  f:SetFrameLevel(base + 50)
  f:EnableMouse(false)
  f:Hide()
  overlay = f
  return f
end

local function ThemeGold()
  local th = NS.GetTheme and NS.GetTheme() or nil
  if type(th) == "table" and type(th.accent) == "table" then
    return th.accent[1] or 0.90, th.accent[2] or 0.78, th.accent[3] or 0.20
  end
  return 0.90, 0.78, 0.20
end

-- Distinct-quest palette (index = stop.n / colorIndex). Chain nodes of the
-- same quest reuse the same color. Falls back to theme gold past the table.
local ROUTE_COLORS = {
  { 0.95, 0.75, 0.20 }, -- 1 gold
  { 0.35, 0.75, 0.95 }, -- 2 sky
  { 0.95, 0.42, 0.35 }, -- 3 coral
  { 0.45, 0.90, 0.45 }, -- 4 green
  { 0.80, 0.50, 0.95 }, -- 5 violet
  { 0.95, 0.60, 0.20 }, -- 6 orange
  { 0.35, 0.85, 0.80 }, -- 7 teal
}

local function RouteColor(idx)
  local i = tonumber(idx) or 1
  if i < 1 then i = 1 end
  local c = ROUTE_COLORS[((i - 1) % #ROUTE_COLORS) + 1]
  if c then return c[1], c[2], c[3] end
  return ThemeGold()
end

local function EnsurePin(i)
  if pins[i] then return pins[i] end
  local parent = EnsureOverlay()
  if not parent then return nil end
  local f = CreateFrame("Frame", "QuestGrindMapPin" .. i, parent)
  f:SetSize(PIN_SIZE, PIN_SIZE)
  f:EnableMouse(true)
  f.ring = f:CreateTexture(nil, "ARTWORK")
  f.ring:SetAllPoints()
  f.ring:SetColorTexture(1, 1, 1, 1)
  f.ring._qgThemeWhite = true
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetPoint("TOPLEFT", 2, -2)
  f.fill:SetPoint("BOTTOMRIGHT", -2, 2)
  f.fill:SetColorTexture(1, 1, 1, 1)
  f.fill._qgThemeWhite = true
  f.num = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.num:SetPoint("CENTER", 0, 0)
  if f.num.SetFont and GameFontNormal and GameFontNormal.GetFont then
    local path = GameFontNormal:GetFont()
    if path then f.num:SetFont(path, 12, "OUTLINE") end
  end
  f:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local title = self.questTitle or "Quest"
    local n = self.routeN or "?"
    GameTooltip:SetText(tostring(n) .. ". " .. title, 1, 0.85, 0.4)
    if self.untriggered then
      GameTooltip:AddLine("Untriggered chain step — same order # as its chain; QuestGrind marker (no Blizzard pin yet).", 0.85, 0.82, 0.75, true)
    else
      GameTooltip:AddLine("Route stop — first stop is the route start; lines stop short of quest icons.", 0.85, 0.82, 0.75, true)
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  f:Hide()
  pins[i] = f
  return f
end

local function EnsureLine(i)
  if lines[i] then return lines[i] end
  local parent = EnsureOverlay()
  if not parent then return nil end
  local tex
  if type(parent.CreateLine) == "function" then
    local ok, line = pcall(parent.CreateLine, parent, nil, "ARTWORK", nil, 0)
    if ok and line then
      line._qgIsLine = true
      if line.SetThickness then pcall(line.SetThickness, line, LINE_THICK) end
      lines[i] = line
      return line
    end
  end
  tex = parent:CreateTexture(nil, "ARTWORK")
  tex:SetColorTexture(1, 1, 1, 1)
  tex._qgThemeWhite = true
  tex._qgIsLine = false
  tex:Hide()
  lines[i] = tex
  return tex
end

local function NormToPixel(parent, x, y)
  local w = parent:GetWidth() or 0
  local h = parent:GetHeight() or 0
  if w <= 0 or h <= 0 then return nil, nil end
  -- Normalized 0..1, bottom-left origin (Forever / classic detail frame).
  return x * w, y * h
end

-- Draw a line between pixel points. clearStart/clearEnd pull endpoints short
-- of quest icons so the stroke touches but does not cover them.
local function DrawLinePixels(line, parent, x1, y1, x2, y2, clearStart, clearEnd, r, g, b, a)
  if not line or not parent then return end
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  clearStart = clearStart or 0
  clearEnd = clearEnd or 0
  if len < (clearStart + clearEnd + 2) then
    if line.Hide then line:Hide() end
    return
  end
  local ux, uy = dx / len, dy / len
  local sx = x1 + ux * clearStart
  local sy = y1 + uy * clearStart
  local ex = x2 - ux * clearEnd
  local ey = y2 - uy * clearEnd
  if line._qgIsLine then
    if line.SetColorTexture then pcall(line.SetColorTexture, line, r, g, b, a) end
    if line.SetStartPoint then
      pcall(line.SetStartPoint, line, "BOTTOMLEFT", parent, sx, sy)
      pcall(line.SetEndPoint, line, "BOTTOMLEFT", parent, ex, ey)
    end
    if line.Show then line:Show() end
    return
  end
  local ldx, ldy = ex - sx, ey - sy
  local llen = math.sqrt(ldx * ldx + ldy * ldy)
  if llen < 1 then
    line:Hide()
    return
  end
  line:ClearAllPoints()
  line:SetSize(llen, LINE_THICK)
  line:SetPoint("CENTER", parent, "BOTTOMLEFT", (sx + ex) / 2, (sy + ey) / 2)
  if line.SetVertexColor then
    line:SetVertexColor(r, g, b, a)
  elseif line.SetColorTexture then
    line:SetColorTexture(r, g, b, a)
  end
  if type(line.SetRotation) == "function" then
    pcall(line.SetRotation, line, math.atan2(ldy, ldx))
  end
  line:Show()
end

local function PlacePin(pin, parent, x, y, n, stop, r, g, b)
  if not pin or not parent then return end
  local px, py = NormToPixel(parent, x, y)
  if not px then
    pin:Hide()
    return
  end
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", parent, "BOTTOMLEFT", px, py)
  pin.questTitle = stop.title
  pin.routeN = n
  pin.untriggered = stop.untriggered and true or false
  if pin.num then pin.num:SetText(tostring(n)) end
  if stop.untriggered then
    -- Own circle for chain steps that have no Blizzard icon yet.
    if pin.ring and pin.ring.SetVertexColor then
      pin.ring:SetVertexColor(r, g, b, 1)
    end
    if pin.fill and pin.fill.SetVertexColor then
      pin.fill:SetVertexColor(0.12, 0.08, 0.04, 0.95)
    end
    if pin.num then pin.num:SetTextColor(r, g, b, 1) end
  else
    -- Accepted: still number the stop; ring sits on / near the real icon.
    if pin.ring and pin.ring.SetVertexColor then
      pin.ring:SetVertexColor(r, g, b, 1)
    end
    if pin.fill and pin.fill.SetVertexColor then
      pin.fill:SetVertexColor(0.18, 0.12, 0.05, 0.85)
    end
    if pin.num then pin.num:SetTextColor(1, 0.95, 0.75, 1) end
  end
  pin:Show()
end

local function HideAllPinsAndLines()
  local i
  for i = 1, MAX_STOPS do
    if pins[i] then pins[i]:Hide() end
  end
  for i = 1, MAX_STOPS + 1 do
    if lines[i] and lines[i].Hide then lines[i]:Hide() end
  end
  if overlay then overlay:Hide() end
  lastDrawKey = nil
end

-- Minimap overlays intentionally disabled (0.2.8+). Keep stubs so old callers
-- (ClearMapPins / UpdateMinimapArrow) stay safe no-ops.
function NS.UpdateMinimapArrow(_route)
  -- dropped: no minimap route / pointer for now
end

function NS.ClearMapPins()
  HideAllPinsAndLines()
end

local function PlayerNormOnMap(mapID)
  local pos = NS.GetPlayerPositions and NS.GetPlayerPositions() or nil
  if not pos then return nil, nil end
  if type(mapID) == "number" and type(C_Map) == "table" and type(C_Map.GetPlayerMapPosition) == "function" then
    local p = SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
    if type(p) == "table" then
      local x, y
      if type(p.GetXY) == "function" then
        local ok, a, b = pcall(p.GetXY, p)
        if ok then x, y = a, b end
      end
      if type(x) ~= "number" then x, y = p.x, p.y end
      if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) and x <= 1 and y <= 1 then
        return x, y
      end
    end
  end
  if type(pos.mapX) == "number" and type(pos.mapY) == "number" then
    if (not mapID) or (pos.mapID == mapID) then
      return pos.mapX, pos.mapY
    end
  end
  return nil, nil
end

local function StopsKey(stops, mapID)
  local parts = { tostring(mapID or 0) }
  local i
  for i = 1, #stops do
    local s = stops[i]
    parts[#parts + 1] = string.format("%d:%d:%s:%.4f:%.4f:%s",
      s.n or i,
      s.colorIndex or s.n or i,
      tostring(s.questID or 0),
      s.mapX or 0,
      s.mapY or 0,
      s.untriggered and "u" or "a")
  end
  return table.concat(parts, "|")
end

function NS.UpdateMapPins(route)
  route = route or NS.liveRoute

  -- Always keep minimap quiet.
  NS.UpdateMinimapArrow(nil)
  NS.HookWorldMap()

  if not route or route.source ~= "live" then
    HideAllPinsAndLines()
    return
  end
  if not (WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()) then
    HideAllPinsAndLines()
    return
  end

  local parent = EnsureOverlay()
  if not parent then
    HideAllPinsAndLines()
    return
  end

  local viewMap = CurrentMapID()
  local stops
  if NS.GetMapRouteStops then
    stops = NS.GetMapRouteStops(MAX_STOPS)
  else
    stops = NS.mapRouteStops
  end
  stops = stops or {}

  -- Filter to the map currently shown (coords are map-local).
  local visible = {}
  local i
  for i = 1, #stops do
    local s = stops[i]
    if type(s.mapX) == "number" and type(s.mapY) == "number" then
      if (not viewMap) or (not s.mapID) or (s.mapID == viewMap) then
        visible[#visible + 1] = s
      end
    end
  end

  -- Fallback: if the multi-stop builder yielded nothing but the focused route
  -- has a pin, show a single numbered stop so the map is not blank.
  if #visible == 0 and NS.NormalizeQuestPin then
    local tx, ty = NS.NormalizeQuestPin(route)
    if type(tx) == "number" and type(ty) == "number" and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1
      and not (tx == 0 and ty == 0) then
      if (not viewMap) or (not route.targetMapID) or (route.targetMapID == viewMap) then
        visible[1] = {
          n = 1,
          questID = route.questID,
          title = (route.step and route.step.title) or route.name or "Focus",
          mapX = tx,
          mapY = ty,
          mapID = route.targetMapID or viewMap,
          inLog = true,
          untriggered = false,
        }
      end
    end
  end

  if #visible == 0 then
    HideAllPinsAndLines()
    return
  end

  local key = StopsKey(visible, viewMap)
  -- Still redraw when the map is shown even if key matches — parent size may
  -- have changed; cheap enough for ≤7 pins.
  lastDrawKey = key

  overlay:Show()

  -- Hide unused pin/line slots first.
  for i = 1, MAX_STOPS do
    if pins[i] then pins[i]:Hide() end
  end
  for i = 1, MAX_STOPS + 1 do
    if lines[i] and lines[i].Hide then lines[i]:Hide() end
  end

  -- 0.2.9: first objective is the START of the route — do NOT draw a line
  -- from map center / player to #1. Points are stop locations only.
  local points = {}
  for i = 1, #visible do
    local s = visible[i]
    local ci = s.colorIndex or s.n or i
    points[#points + 1] = {
      x = s.mapX,
      y = s.mapY,
      stop = s,
      n = s.n or i,
      colorIndex = ci,
    }
  end

  -- Route lines: #1 → #2 → … (within a chain, same n continues across steps).
  -- Color = destination stop's distinct-quest color. Stop short of icons.
  local li = 1
  for i = 1, #points - 1 do
    local a, bpt = points[i], points[i + 1]
    local ax, ay = NormToPixel(parent, a.x, a.y)
    local bx, by = NormToPixel(parent, bpt.x, bpt.y)
    if ax and bx then
      local line = EnsureLine(li)
      local cr, cg, cb = RouteColor(bpt.colorIndex or bpt.n)
      -- Same-chain segment (shared order #): paint with that quest's color.
      if a.n and bpt.n and a.n == bpt.n then
        cr, cg, cb = RouteColor(a.colorIndex or a.n)
      end
      DrawLinePixels(line, parent, ax, ay, bx, by, ICON_CLEAR_PX, ICON_CLEAR_PX, cr, cg, cb, 0.85)
      li = li + 1
    end
  end

  -- Number circles (accepted + untriggered). Shared n within a chain;
  -- distinct quests get distinct colors.
  for i = 1, #visible do
    local s = visible[i]
    local pin = EnsurePin(i)
    local cr, cg, cb = RouteColor(s.colorIndex or s.n or i)
    PlacePin(pin, parent, s.mapX, s.mapY, s.n or i, s, cr, cg, cb)
  end
end

function NS.HookWorldMap()
  if hookedMap or not WorldMapFrame then return end
  hookedMap = true
  WorldMapFrame:HookScript("OnShow", function()
    if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
  end)
  WorldMapFrame:HookScript("OnHide", function()
    HideAllPinsAndLines()
  end)
  -- Redraw when the player pans / changes map (API varies by client).
  if type(WorldMapFrame.OnMapChanged) == "function" or WorldMapFrame.ScrollContainer then
    pcall(function()
      if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.HookScript then
        WorldMapFrame.ScrollContainer:HookScript("OnSizeChanged", function()
          if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
        end)
      end
    end)
  end
  local ev = CreateFrame("Frame")
  pcall(function() ev:RegisterEvent("WORLD_MAP_OPEN") end)
  pcall(function() ev:RegisterEvent("PLAYER_ENTERING_WORLD") end)
  -- Some Forever builds fire this when the canvas map id changes.
  pcall(function() ev:RegisterEvent("ZONE_CHANGED_NEW_AREA") end)
  ev:SetScript("OnEvent", function()
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
      if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
    end
  end)
  -- Poll map id while open (cheap; OnUpdate only while shown).
  local poll = CreateFrame("Frame", "QuestGrindMapPoll")
  local acc, lastID = 0, nil
  poll:SetScript("OnUpdate", function(_, elapsed)
    if not (WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()) then
      return
    end
    acc = acc + (elapsed or 0)
    if acc < 0.35 then return end
    acc = 0
    local id = CurrentMapID()
    if id ~= lastID then
      lastID = id
      if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
    end
  end)
end

local mapEv = CreateFrame("Frame")
pcall(function() mapEv:RegisterEvent("PLAYER_LOGOUT") end)
pcall(function() mapEv:RegisterEvent("PLAYER_ENTERING_WORLD") end)
mapEv:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" then
    NS.ClearMapPins()
    if NS.StopRouteTicker then NS.StopRouteTicker() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
  end
end)
