local _, NS = ...

-- P1: world map pin(s) + minimap edge arrow / bottom focus badge (0.2.4).

local mapPin
local minimapArrow
local minimapBadge
local hookedMap = false

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

local function FindWorldMapParent()
  if not WorldMapFrame then return nil end
  if WorldMapFrame.ScrollContainer then return WorldMapFrame.ScrollContainer end
  if WorldMapDetailFrame then return WorldMapDetailFrame end
  if WorldMapButton then return WorldMapButton end
  return WorldMapFrame
end

local function EnsureMapPin()
  if mapPin then return mapPin end
  local parent = FindWorldMapParent()
  if not parent then return nil end
  local f = CreateFrame("Frame", "QuestGrindMapPin", parent)
  f:SetSize(18, 18)
  f:SetFrameStrata("TOOLTIP")
  f.bg = f:CreateTexture(nil, "ARTWORK")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0.90, 0.78, 0.20, 0.95)
  f.glyph = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.glyph:SetPoint("CENTER")
  f.glyph:SetText("!")
  f:Hide()
  mapPin = f
  return f
end

local function EnsureMinimapArrow()
  if minimapArrow then return minimapArrow end
  if not Minimap then return nil end
  local f = CreateFrame("Frame", "QuestGrindMinimapArrow", Minimap)
  f:SetSize(22, 22)
  f:SetFrameStrata("HIGH")
  local base = 0
  if Minimap.GetFrameLevel then base = Minimap:GetFrameLevel() or 0 end
  f:SetFrameLevel(base + 40)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.tex:SetColorTexture(0.95, 0.78, 0.20, 1)
  f.glyph = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.glyph:SetPoint("CENTER", 0, 0)
  if f.glyph.SetFont and GameFontNormal and GameFontNormal.GetFont then
    local path = GameFontNormal:GetFont()
    if path then f.glyph:SetFont(path, 16, "OUTLINE") end
  end
  f.glyph:SetText("!")
  f.glyph:SetTextColor(0.12, 0.06, 0.02, 1)
  f:Hide()
  minimapArrow = f
  return f
end

-- Focus badge: sits under the minimap disk (NOT on the player). Used when the
-- live focus has no coords — still useful (quest title on hover), never a fake bearing.
local function EnsureMinimapBadge()
  if minimapBadge then return minimapBadge end
  if not Minimap then return nil end
  local f = CreateFrame("Button", "QuestGrindMinimapBadge", Minimap)
  f:SetSize(22, 22)
  f:SetFrameStrata("HIGH")
  local base = 0
  if Minimap.GetFrameLevel then base = Minimap:GetFrameLevel() or 0 end
  f:SetFrameLevel(base + 42)
  f.border = f:CreateTexture(nil, "BACKGROUND")
  f.border:SetAllPoints()
  f.border:SetColorTexture(1, 1, 1, 1)
  f.border._qgThemeWhite = true
  f.border:SetVertexColor(0.90, 0.78, 0.40, 1)
  f.bg = f:CreateTexture(nil, "ARTWORK")
  f.bg:SetPoint("TOPLEFT", 1, -1)
  f.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  f.bg:SetColorTexture(1, 1, 1, 1)
  f.bg._qgThemeWhite = true
  f.bg:SetVertexColor(0.18, 0.12, 0.07, 1)
  f.glyph = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.glyph:SetPoint("CENTER", 0, 0)
  if f.glyph.SetFont and GameFontNormal and GameFontNormal.GetFont then
    local path = GameFontNormal:GetFont()
    if path then f.glyph:SetFont(path, 14, "OUTLINE") end
  end
  f.glyph:SetText("!")
  f.glyph:SetTextColor(0.95, 0.85, 0.35, 1)
  f:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, -2)
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp")
  f:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local title = self.questTitle or "Focused quest"
    GameTooltip:SetText(title, 1, 0.85, 0.4)
    GameTooltip:AddLine("No map coords yet — edge arrow appears when Forever exposes a POI.", 0.85, 0.82, 0.75, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  f:Hide()
  minimapBadge = f
  return f
end

local function PositionOnMap(pin, x, y)
  -- x,y normalized 0..1 (top-left origin varies). Classic often bottom-left.
  local parent = pin:GetParent()
  if not parent then return end
  local w = parent:GetWidth() or 0
  local h = parent:GetHeight() or 0
  if w <= 0 or h <= 0 then return end
  -- Assume 0,0 = bottom-left (common for detail frame); y up.
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", parent, "BOTTOMLEFT", x * w, y * h)
end

function NS.ClearMapPins()
  if mapPin then mapPin:Hide() end
  if minimapArrow then minimapArrow:Hide() end
  if minimapBadge then minimapBadge:Hide() end
end

function NS.UpdateMapPins(route)
  route = route or NS.liveRoute
  if not route or route.source ~= "live" then
    NS.ClearMapPins()
    return
  end

  -- World map pin when we have normalized coords (raw or converted from yards).
  local pin = EnsureMapPin()
  local tx, ty
  if NS.NormalizeQuestPin then
    tx, ty = NS.NormalizeQuestPin(route)
  end
  if not tx and route.mapX and route.mapY then
    tx, ty = route.mapX, route.mapY
  end
  local looksNormalized = type(tx) == "number" and type(ty) == "number"
    and tx >= 0 and tx <= 1 and ty >= 0 and ty <= 1
    and not (tx == 0 and ty == 0)
  if pin and looksNormalized and WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() then
    PositionOnMap(pin, tx, ty)
    pin:Show()
  elseif pin then
    pin:Hide()
  end

  -- Minimap: edge arrow when bearing known; bottom focus badge when not (never center-on-player).
  NS.UpdateMinimapArrow(route)
  NS.HookWorldMap()
end

function NS.UpdateMinimapArrow(route)
  route = route or NS.liveRoute
  local arrow = EnsureMinimapArrow()
  local badge = EnsureMinimapBadge()
  if not arrow and not badge then return end

  if not route or route.source ~= "live" then
    if arrow then arrow:Hide() end
    if badge then badge:Hide() end
    return
  end

  local haveBearing = route.hasCoords and route.bearingDeg ~= nil
  local title = nil
  if route.step and type(route.step.title) == "string" and route.step.title ~= "" then
    title = route.step.title
  elseif type(route.name) == "string" then
    title = route.name
  end

  if haveBearing and arrow then
    if badge then badge:Hide() end
    if arrow.glyph then arrow.glyph:SetText("!") end
    local facing = SafeCall(GetPlayerFacing)
    local rel
    if type(facing) == "number" then
      local facingDeg = math.deg(facing)
      rel = math.rad((route.bearingDeg - facingDeg + 360) % 360)
    else
      rel = math.rad(route.bearingDeg % 360)
    end
    local radius = 62
    if Minimap and Minimap.GetWidth then
      radius = math.max(48, (Minimap:GetWidth() or 140) * 0.42)
    end
    local ox = math.sin(rel) * radius
    local oy = math.cos(rel) * radius
    -- Edge pointer: tall gold tip + bang, rotated toward focus.
    arrow:SetSize(18, 26)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
    if arrow.tex and type(arrow.tex.SetRotation) == "function" then
      pcall(arrow.tex.SetRotation, arrow.tex, rel)
    elseif type(arrow.SetRotation) == "function" then
      pcall(arrow.SetRotation, arrow, rel)
    end
    arrow:Show()
  else
    -- No coords: hide edge arrow; show bottom badge (not center-on-player).
    if arrow then arrow:Hide() end
    if badge then
      badge.questTitle = title or "Focused quest"
      badge:ClearAllPoints()
      badge:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, -2)
      badge:Show()
    end
  end
end

function NS.HookWorldMap()
  if hookedMap or not WorldMapFrame then return end
  hookedMap = true
  WorldMapFrame:HookScript("OnShow", function()
    if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
  end)
  WorldMapFrame:HookScript("OnHide", function()
    if mapPin then mapPin:Hide() end
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

