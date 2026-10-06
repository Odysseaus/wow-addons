local _, NS = ...

-- P1: world map pin(s) + minimap arrow. Simple SetColorTexture art (P4 = polish).

local mapPin
local minimapArrow
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

  -- Minimap pointer is required for every live focus, even with no pin coords.
  NS.UpdateMinimapArrow(route)
  NS.HookWorldMap()
end

function NS.UpdateMinimapArrow(route)
  route = route or NS.liveRoute
  local arrow = EnsureMinimapArrow()
  if not arrow then return end
  if not route or route.source ~= "live" then
    arrow:Hide()
    return
  end

  if arrow.glyph then arrow.glyph:SetText("!") end

  local haveBearing = route.hasCoords and route.bearingDeg ~= nil
  if haveBearing then
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
    arrow:SetSize(20, 28)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
    if arrow.tex and type(arrow.tex.SetRotation) == "function" then
      pcall(arrow.tex.SetRotation, arrow.tex, rel)
    elseif type(arrow.SetRotation) == "function" then
      pcall(arrow.SetRotation, arrow, rel)
    end
  else
    -- No coords: still show a quest-bang so a live focus is never invisible.
    arrow:SetSize(22, 22)
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", Minimap, "CENTER", 0, 10)
    if arrow.tex and type(arrow.tex.SetRotation) == "function" then
      pcall(arrow.tex.SetRotation, arrow.tex, 0)
    end
  end
  arrow:Show()
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

