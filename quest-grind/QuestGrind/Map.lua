local _, NS = ...

-- Main world-map route only (minimap overlays dropped).
-- Up to 7 stops in QuestGrind completion order. First objective is the
-- START of the route (no line from map center / player to #1). Chain
-- locations share one order number; distinct quests get distinct colors.
-- Lines stop short of Blizzard quest icons / QG circles.
--
-- 0.2.11 marker rule: if a stop already has a live Blizzard quest pin,
-- do NOT draw a QuestGrind numbered badge there — the Blizzard icon is
-- the marker. Still run route lines from that Blizzard pin XY to later
-- stops. QG numbered circles only for stops without a live Blizzard pin
-- (untriggered / upcoming chain steps, or accepted stops with no pin).
--
-- MapCanvas places pins from TOPLEFT with inverted Y (same math as Blizzard):
--   ox, oy = width * nx, -height * ny
--   SetPoint("CENTER", canvas, "TOPLEFT", ox, oy)
-- Do not use BOTTOMLEFT + positive Y.

local MAX_STOPS = 7
local ICON_CLEAR_PX = 16 -- pull line endpoints short of icon centers
local PIN_SIZE = 22
local LINE_THICK = 2.5
local OVERLAY_LEVEL_OFFSET = 8 -- canvas level + this; route lines stay below live pins

-- Live Blizzard pins whose parent is the real map canvas. Quest templates
-- are listed first so a quest bang wins when we snap coordinates.
local QUEST_PIN_TEMPLATES = {
  "QuestPinTemplate",
  "StorylineQuestPinTemplate",
  "BonusObjectivePinTemplate",
  "WorldQuestPinTemplate",
  "CampaignQuestPinTemplate",
  "QuestOfferPinTemplate",
}
local PARENT_PIN_TEMPLATES = {
  "QuestPinTemplate",
  "StorylineQuestPinTemplate",
  "BonusObjectivePinTemplate",
  "WorldQuestPinTemplate",
  "CampaignQuestPinTemplate",
  "QuestOfferPinTemplate",
  "AreaPOIPinTemplate",
  "WorldMapUnitPinTemplate",
  "DungeonEntrancePinTemplate",
  "GroupMembersPinTemplate",
}

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

-- WoW widgets are tables; some clients expose them as userdata.
local function IsWidget(obj)
  local t = type(obj)
  return t == "table" or t == "userdata"
end

local function FrameSize(f)
  if not IsWidget(f) or type(f.GetWidth) ~= "function" or type(f.GetHeight) ~= "function" then
    return 0, 0
  end
  local w = SafeCall(f.GetWidth, f)
  local h = SafeCall(f.GetHeight, f)
  if type(w) ~= "number" then w = 0 end
  if type(h) ~= "number" then h = 0 end
  return w, h
end

local function UsableCanvas(f)
  local w, h = FrameSize(f)
  return w >= 1 and h >= 1
end

-- The scroll viewport is window space. Pins parented there drift off the
-- quest icons whenever a real canvas child exists.
local function IsScrollViewport(f)
  if not f or not WorldMapFrame then return false end
  local sc = WorldMapFrame.ScrollContainer
  return sc and f == sc
end

-- EnumeratePinsByTemplate yields either `next, pool, nil` (pairs) or a
-- closure. Walk a bounded number of pins; ignore a missing API.
local function ForEachTemplatePin(templates, fn)
  if not WorldMapFrame or type(WorldMapFrame.EnumeratePinsByTemplate) ~= "function" then
    return
  end
  if type(templates) ~= "table" or type(fn) ~= "function" then return end
  local ti
  for ti = 1, #templates do
    local ok, iter, state, ctrl = pcall(WorldMapFrame.EnumeratePinsByTemplate, WorldMapFrame, templates[ti])
    if ok and type(iter) == "function" then
      local guard = 0
      while guard < 250 do
        guard = guard + 1
        local ok2, a, b = pcall(iter, state, ctrl)
        if not ok2 or a == nil then break end
        -- pairs() key is the control variable. Array pools key by index and
        -- yield the pin as the second value; hash pools key by the pin.
        ctrl = a
        local pin
        if IsWidget(a) and type(a.GetParent) == "function" then
          pin = a
        elseif IsWidget(b) and type(b.GetParent) == "function" then
          pin = b
        end
        if pin then
          local stop = fn(pin)
          if stop then return end
        end
      end
    end
  end
end

local function BlizzardPinCanvas()
  local found
  ForEachTemplatePin(PARENT_PIN_TEMPLATES, function(pin)
    if type(pin.GetParent) ~= "function" then return false end
    local parent = SafeCall(pin.GetParent, pin)
    if parent and UsableCanvas(parent) and not IsScrollViewport(parent) then
      found = parent
      return true
    end
    return false
  end)
  return found
end

local function FindWorldMapParent()
  if not WorldMapFrame then return nil end

  -- Same parent as a live Blizzard pin, when one exists.
  local fromPin = BlizzardPinCanvas()
  if fromPin then return fromPin end

  if type(WorldMapFrame.GetCanvas) == "function" then
    local canvas = SafeCall(WorldMapFrame.GetCanvas, WorldMapFrame)
    if UsableCanvas(canvas) and not IsScrollViewport(canvas) then
      return canvas
    end
  end

  local sc = WorldMapFrame.ScrollContainer
  if IsWidget(sc) then
    if sc.Child and UsableCanvas(sc.Child) and not IsScrollViewport(sc.Child) then
      return sc.Child
    end
    if type(sc.GetCanvas) == "function" then
      local canvas = SafeCall(sc.GetCanvas, sc)
      if UsableCanvas(canvas) and not IsScrollViewport(canvas) then
        return canvas
      end
    end
  end

  if WorldMapDetailFrame and UsableCanvas(WorldMapDetailFrame) and not IsScrollViewport(WorldMapDetailFrame) then
    return WorldMapDetailFrame
  end
  if WorldMapButton and UsableCanvas(WorldMapButton) and not IsScrollViewport(WorldMapButton) then
    return WorldMapButton
  end

  -- Canvas exists but is not sized yet: do not fall back to the viewport.
  local childExists = type(WorldMapFrame.GetCanvas) == "function"
  if IsWidget(sc) and (sc.Child or type(sc.GetCanvas) == "function") then
    childExists = true
  end
  if childExists then return nil end
  if UsableCanvas(WorldMapFrame) and not IsScrollViewport(WorldMapFrame) then
    return WorldMapFrame
  end
  return nil
end

-- Anchor space is the map canvas, not the overlay frame. Blizzard pins are
-- positioned against that canvas; measuring the overlay before it lays out
-- would put markers in the wrong pixel space.
local function AnchorFrame(overlayFrame)
  if overlayFrame and type(overlayFrame.GetParent) == "function" then
    local gp = overlayFrame:GetParent()
    if gp and UsableCanvas(gp) and not IsScrollViewport(gp) then
      return gp
    end
  end
  return overlayFrame
end

local function LowestQuestPinLevel()
  local lowest
  ForEachTemplatePin(QUEST_PIN_TEMPLATES, function(pin)
    if type(pin.GetFrameLevel) ~= "function" then return false end
    local lv = SafeCall(pin.GetFrameLevel, pin)
    if type(lv) == "number" and lv > 1 then
      if not lowest or lv < lowest then lowest = lv end
    end
    return false
  end)
  return lowest
end

local function ApplyOverlayDepth(f, parent)
  if not f or not parent then return end
  -- Same strata as the canvas. Never force TOOLTIP (that paints over quest
  -- bangs). If the canvas itself is HIGH, matching it keeps route lines from
  -- covering a live pin. Number badges are not drawn on those pins.
  local strata = "MEDIUM"
  if type(parent.GetFrameStrata) == "function" then
    local s = SafeCall(parent.GetFrameStrata, parent)
    if type(s) == "string" and s ~= "" and s ~= "TOOLTIP" then
      strata = s
    end
  end
  pcall(f.SetFrameStrata, f, strata)

  local base = 1
  if type(parent.GetFrameLevel) == "function" then
    local lv = SafeCall(parent.GetFrameLevel, parent)
    if type(lv) == "number" and lv > 0 then base = lv end
  end
  local level = base + OVERLAY_LEVEL_OFFSET
  local lowest = LowestQuestPinLevel()
  -- Lines (and any QuestGrind number on a stop Blizzard did not pin) are
  -- parented here. Keep that frame level under a live quest pin so a stroke
  -- cannot cover the Blizzard icon.
  if type(lowest) == "number" and lowest > base then
    local cap = lowest - 2
    if cap < base then cap = base end
    if level > cap then level = cap end
  end
  if level < base then level = base end
  if level > 10000 then level = 10000 end
  pcall(f.SetFrameLevel, f, level)
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
  local parent = FindWorldMapParent()
  if not parent then return nil end
  if not overlay then
    local f = CreateFrame("Frame", "QuestGrindMapRoute", parent)
    f:SetAllPoints(parent)
    f:EnableMouse(false)
    f:Hide()
    overlay = f
  elseif overlay:GetParent() ~= parent then
    local ok = pcall(overlay.SetParent, overlay, parent)
    if not ok then return nil end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(parent)
  end
  ApplyOverlayDepth(overlay, parent)
  overlay:EnableMouse(false)
  return overlay
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
      GameTooltip:AddLine("Upcoming chain step — same order # as its chain. QuestGrind number; this stop has no Blizzard pin.", 0.85, 0.82, 0.75, true)
    else
      GameTooltip:AddLine("Route stop — QuestGrind marker (no live Blizzard quest pin on this spot).", 0.85, 0.82, 0.75, true)
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
  if not parent or type(parent.GetWidth) ~= "function" then return nil, nil end
  local w = parent:GetWidth() or 0
  local h = parent:GetHeight() or 0
  if w <= 0 or h <= 0 then return nil, nil end
  -- Normalized 0..1, TOPLEFT origin. Y grows south, so the pixel offset is
  -- negative. This is MapCanvasMixin:ApplyPinPosition.
  return x * w, -(y * h)
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
      pcall(line.SetStartPoint, line, "TOPLEFT", parent, sx, sy)
      pcall(line.SetEndPoint, line, "TOPLEFT", parent, ex, ey)
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
  line:SetPoint("CENTER", parent, "TOPLEFT", (sx + ex) / 2, (sy + ey) / 2)
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

-- Pins stay mouse-enabled for their tooltip. The overlay itself does not
-- take clicks. Numbered markers are not placed on a live Blizzard quest pin.
local function MatchPinDepth(pin)
  local parent = pin:GetParent()
  if not parent then return end
  if type(parent.GetFrameStrata) == "function" then
    local strata = SafeCall(parent.GetFrameStrata, parent)
    if type(strata) == "string" and strata ~= "" and strata ~= "TOOLTIP" then
      pcall(pin.SetFrameStrata, pin, strata)
    end
  end
  if type(parent.GetFrameLevel) == "function" then
    local lv = SafeCall(parent.GetFrameLevel, parent)
    if type(lv) == "number" then
      local child = lv + 1
      if child < 1 then child = 1 end
      if child > 10000 then child = 10000 end
      pcall(pin.SetFrameLevel, pin, child)
    end
  end
end

local function PlacePin(pin, parent, x, y, n, stop, r, g, b)
  if not pin or not parent then return end
  local px, py = NormToPixel(parent, x, y)
  if not px then
    pin:Hide()
    return
  end
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", parent, "TOPLEFT", px, py)
  MatchPinDepth(pin)
  pin.questTitle = stop.title
  pin.routeN = n
  pin.untriggered = stop.untriggered and true or false
  if pin.num then pin.num:SetText(tostring(n)) end
  -- QG circle only (placed when the stop has no live Blizzard pin):
  -- colored ring, dark fill, colored number.
  if pin.ring and pin.ring.SetVertexColor then
    pin.ring:SetVertexColor(r, g, b, 1)
  end
  if pin.fill and pin.fill.SetVertexColor then
    pin.fill:SetVertexColor(0.12, 0.08, 0.04, 0.95)
  end
  if pin.num then pin.num:SetTextColor(r, g, b, 1) end
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
    parts[#parts + 1] = string.format("%d:%d:%s:%.4f:%.4f:%s:%s",
      s.n or i,
      s.colorIndex or s.n or i,
      tostring(s.questID or 0),
      s.mapX or 0,
      s.mapY or 0,
      s.untriggered and "u" or "a",
      s.hasBlizzardPin and "b" or "q")
  end
  return table.concat(parts, "|")
end

local function PinQuestID(pin)
  if type(pin.questID) == "number" then return pin.questID end
  if type(pin.GetQuestID) == "function" then
    local id = SafeCall(pin.GetQuestID, pin)
    if type(id) == "number" then return id end
  end
  if type(pin.questId) == "number" then return pin.questId end
  return nil
end

-- GetPosition is normalized 0..1. A raw x/y above 1 is percent, never yards.
local function PinMapNorm(pin)
  local x, y
  if type(pin.GetPosition) == "function" then
    x, y = SafeCall(pin.GetPosition, pin)
  end
  if type(x) ~= "number" or type(y) ~= "number" then
    x, y = pin.normalizedX, pin.normalizedY
  end
  if type(x) ~= "number" or type(y) ~= "number" then
    x, y = pin.x, pin.y
  end
  if type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
  if x == 0 and y == 0 then return nil, nil end
  if x >= 0 and y >= 0 and x <= 1 and y <= 1 then return x, y end
  if x > 1 and y > 1 and x <= 100 and y <= 100 then
    return x / 100, y / 100
  end
  return nil, nil
end

local function SnapStopsToBlizzardPins(stops)
  if type(stops) ~= "table" or #stops < 1 then return end
  if not WorldMapFrame or type(WorldMapFrame.EnumeratePinsByTemplate) ~= "function" then
    return
  end
  local want = {}
  local i
  for i = 1, #stops do
    local id = stops[i].questID
    if type(id) == "number" then want[id] = stops[i] end
  end
  ForEachTemplatePin(QUEST_PIN_TEMPLATES, function(pin)
    local id = PinQuestID(pin)
    local stop = id and want[id] or nil
    if stop then
      local x, y = PinMapNorm(pin)
      if x then
        stop.mapX, stop.mapY = x, y
        stop.hasBlizzardPin = true
        want[id] = nil
      end
    end
    return false
  end)
end

local function NormalizeMapXY(x, y)
  if type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
  if x == 0 and y == 0 then return nil, nil end
  if x >= 0 and y >= 0 and x <= 1 and y <= 1 then return x, y end
  if x > 1 and y > 1 and x <= 100 and y <= 100 then
    return x / 100, y / 100
  end
  return nil, nil
end

local function MarkStopsWithQuestsOnMap(stops, viewMap)
  if type(stops) ~= "table" or #stops < 1 then return end
  if type(viewMap) ~= "number" then return end
  if type(C_QuestLog) ~= "table" or type(C_QuestLog.GetQuestsOnMap) ~= "function" then
    return
  end
  local list = SafeCall(C_QuestLog.GetQuestsOnMap, viewMap)
  if type(list) ~= "table" then return end
  local byID = {}
  local i
  for i = 1, #list do
    local e = list[i]
    if type(e) == "table" then
      local id = e.questID or e.questId or e.id
      if type(id) == "number" then
        local x = e.x or e.mapX or e.normalizedX
        local y = e.y or e.mapY or e.normalizedY
        local nx, ny = NormalizeMapXY(x, y)
        if nx then byID[id] = { x = nx, y = ny } end
      end
    end
  end
  for i = 1, #stops do
    local s = stops[i]
    local id = s and s.questID
    local hit = type(id) == "number" and byID[id] or nil
    if hit then
      s.hasBlizzardPin = true
      -- Prefer live-pin snap XY when already set; otherwise take GetQuestsOnMap.
      if type(s.mapX) ~= "number" or type(s.mapY) ~= "number" then
        s.mapX, s.mapY = hit.x, hit.y
      end
    end
  end
end

local function StopHasBlizzardPin(stop)
  return type(stop) == "table" and stop.hasBlizzardPin and true or false
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

  -- Fallback: builder yielded nothing but the focused route has a coordinate.
  -- After snap/mark, a lone Blizzard-backed stop draws nothing; a stop with
  -- no Blizzard pin still gets one QuestGrind marker.
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

  -- Per draw: live canvas pins, then GetQuestsOnMap. Both set hasBlizzardPin
  -- and XY so route lines leave the Blizzard icon. Numbers are skipped later.
  for i = 1, #visible do
    visible[i].hasBlizzardPin = nil
  end
  SnapStopsToBlizzardPins(visible)
  MarkStopsWithQuestsOnMap(visible, viewMap)

  -- Only stop on the map is already a live Blizzard pin: no badge, no segment.
  if #visible == 1 and StopHasBlizzardPin(visible[1]) then
    HideAllPinsAndLines()
    return
  end

  local anchor = AnchorFrame(parent)
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
    local ax, ay = NormToPixel(anchor, a.x, a.y)
    local bx, by = NormToPixel(anchor, bpt.x, bpt.y)
    if ax and bx then
      local line = EnsureLine(li)
      local cr, cg, cb = RouteColor(bpt.colorIndex or bpt.n)
      -- Same-chain segment (shared order #): paint with that quest's color.
      if a.n and bpt.n and a.n == bpt.n then
        cr, cg, cb = RouteColor(a.colorIndex or a.n)
      end
      DrawLinePixels(line, anchor, ax, ay, bx, by, ICON_CLEAR_PX, ICON_CLEAR_PX, cr, cg, cb, 0.85)
      li = li + 1
    end
  end

  local pi = 1
  for i = 1, #visible do
    local s = visible[i]
    if not StopHasBlizzardPin(s) then
      local pin = EnsurePin(pi)
      local cr, cg, cb = RouteColor(s.colorIndex or s.n or i)
      PlacePin(pin, anchor, s.mapX, s.mapY, s.n or i, s, cr, cg, cb)
      pi = pi + 1
    end
  end
  -- hide unused pin slots (already hidden at start; EnsurePin may create more — hide from pi to MAX_STOPS)
  for i = pi, MAX_STOPS do
    if pins[i] then pins[i]:Hide() end
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
