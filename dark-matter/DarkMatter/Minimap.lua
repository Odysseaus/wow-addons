-- Circular minimap-edge button. Drag it around the edge; the angle is saved.
-- Plain Button parented to the Minimap (not a secure frame).
local _, NS = ...

local button
local ICON = "Interface\\AddOns\\DarkMatter\\Media\\dm-icon"
local STOCK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local atan2 = math.atan2 or math.atan

-- GetMinimapShape is optional (this client has none): assume a round minimap.
local function MinimapShape()
  local fn = _G.GetMinimapShape
  if type(fn) == "function" then
    local ok, shape = pcall(fn)
    if ok and type(shape) == "string" then return shape end
  end
  return "ROUND"
end

local function UpdatePosition()
  if not button or not NS.db then return end
  local angle = math.rad(NS.db.minimap.angle or 215)
  local x, y = math.cos(angle), math.sin(angle)
  local w = (Minimap:GetWidth() / 2) + 5
  local h = (Minimap:GetHeight() / 2) + 5
  local shape = MinimapShape()
  if shape == "SQUARE" then
    -- push out to the square edge instead of the circle
    local m = math.max(math.abs(x), math.abs(y))
    if m > 0 then x, y = x / m, y / m end
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  local deg = math.deg(atan2(py - my, px - mx))
  if deg < 0 then deg = deg + 360 end
  NS.db.minimap.angle = deg
  UpdatePosition()
end

function NS.SetMinimapIcon()
  if button then
    button.icon:SetTexture(NS.db.stockIcon and STOCK_ICON or ICON)
  end
end

function NS.SetMinimapButtonShown(show)
  if not button then return end
  NS.db.minimap.hide = not show
  if show then button:Show() else button:Hide() end
end

function NS.CreateMinimapButton()
  if button or not Minimap then return end
  button = CreateFrame("Button", "DarkMatterMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(24, 24)
  bg:SetPoint("TOPLEFT", 4, -4)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(22, 22)
  icon:SetPoint("TOPLEFT", 4, -4)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:RegisterForClicks("AnyUp")
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then NS.ResetWindowPosition() else NS.ToggleWindow() end
  end)
  button:SetScript("OnDragStart", function(self)
    self.dragging = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", OnDragUpdate)
  end)
  button:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    if self.dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Dark Matter")
    GameTooltip:AddLine("Click: toggle window", 1, 1, 1)
    GameTooltip:AddLine("Right-click: reset window position", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  NS.SetMinimapIcon()
  UpdatePosition()
  if NS.db.minimap.hide then button:Hide() else button:Show() end
end

function NS.ResetMinimapButton()
  if not NS.db then return end
  NS.db.minimap.angle = 215
  NS.db.minimap.hide = false
  UpdatePosition()
  if button then button:Show() end
end
