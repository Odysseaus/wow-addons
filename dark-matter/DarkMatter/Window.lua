-- Placeholder main window: a plain stock frame shell (P1 replaces this).
-- Opens at screen centre, remembers where you drag it, has a reset.
local _, NS = ...

local frame

local function SavePosition()
  if not frame or not NS.db then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  NS.db.window.point = point or "CENTER"
  NS.db.window.relPoint = relPoint or "CENTER"
  NS.db.window.x = x or 0
  NS.db.window.y = y or 0
end

local function ApplyPosition()
  local w = NS.db and NS.db.window or {}
  frame:ClearAllPoints()
  frame:SetPoint(w.point or "CENTER", UIParent, w.relPoint or "CENTER", w.x or 0, w.y or 0)
end

function NS.ResetWindowPosition()
  if NS.db then
    NS.db.window.point, NS.db.window.relPoint, NS.db.window.x, NS.db.window.y = "CENTER", "CENTER", 0, 0
  end
  if frame then ApplyPosition() end
  NS.Print("window position reset to screen centre.")
end

local function Build()
  local ok, f = pcall(CreateFrame, "Frame", "DarkMatterFrame", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "DarkMatterFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
  end
  f:SetSize(540, 460)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
  f:SetScript("OnShow", function() NS.RefreshWindow() end)
  f:Hide()

  local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
  if title then
    title:SetText("Dark Matter")
  elseif f.SetTitle then
    pcall(f.SetTitle, f, "Dark Matter")
  else
    title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Dark Matter")
  end

  local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  head:SetPoint("TOPLEFT", 16, -34)
  head:SetText("Dark Matter " .. NS.version .. " (P0.3 probe)")

  local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
  note:SetWidth(500)
  note:SetJustifyH("LEFT")
  note:SetText("Summary of /dm probe (mouse wheel scrolls). /dm raw shows the raw call list; everything is saved in SavedVariables.")

  local scroll = CreateFrame("ScrollFrame", "DarkMatterProbeScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -78)
  scroll:SetPoint("BOTTOMRIGHT", -34, 46)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(484, 10)
  scroll:SetScrollChild(content)
  local probeText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  probeText:SetPoint("TOPLEFT", 0, 0)
  probeText:SetWidth(484)
  probeText:SetJustifyH("LEFT")
  probeText:SetJustifyV("TOP")
  probeText:SetText("No probe yet. Press Run probe (or type /dm probe).")
  f.probeText = probeText
  f.probeContent = content
  f.probeScroll = scroll

  local probeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  probeBtn:SetSize(130, 24)
  probeBtn:SetPoint("BOTTOMLEFT", 16, 14)
  probeBtn:SetText("Run probe")
  probeBtn:SetScript("OnClick", function() NS.RunProbe(false) end)

  local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  resetBtn:SetSize(170, 24)
  resetBtn:SetPoint("LEFT", probeBtn, "RIGHT", 8, 0)
  resetBtn:SetText("Reset window position")
  resetBtn:SetScript("OnClick", function() NS.ResetWindowPosition() end)

  -- ESC closes it, the stock way (plain table insert; no secure code involved).
  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "DarkMatterFrame") end
  return f
end

function NS.GetWindow()
  if not frame then
    frame = Build()
    ApplyPosition()
    NS.RefreshWindow()
  end
  return frame
end

function NS.RefreshWindow()
  if not frame or not frame.probeText then return end
  local p = NS.lastProbe
  if p and p.summary then
    local text = table.concat(p.summary, "\n")
    if NS.showRaw and NS.RawLines then
      text = text .. "\n\n-- Raw call returns (type:value) --\n" .. table.concat(NS.RawLines(p), "\n")
    end
    frame.probeText:SetText(text)
    frame.probeContent:SetHeight((frame.probeText:GetStringHeight() or 0) + 8)
    frame.probeScroll:SetVerticalScroll(0)
  end
end

function NS.ToggleWindow(show)
  local f = NS.GetWindow()
  if show == nil then show = not f:IsShown() end
  if show then f:Show() else f:Hide() end
end
