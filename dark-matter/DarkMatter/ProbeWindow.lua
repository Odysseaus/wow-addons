-- Probe report window: a small stock-template window for /dm probe output (summary + optional raw list).
-- Kept separate from the main window; read-only text, mouse wheel scrolls.
local _, NS = ...

local pf

local function Build()
  local ok, f = pcall(CreateFrame, "Frame", "DarkMatterProbeFrame", UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", "DarkMatterProbeFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
  end
  f:SetSize(560, 480)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:SetScript("OnShow", function() NS.RefreshProbeWindow() end)
  f:Hide()

  local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
  if title then
    title:SetText("Dark Matter probe")
  else
    title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Dark Matter probe")
  end

  local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  head:SetPoint("TOPLEFT", 16, -34)
  head:SetText("Dark Matter " .. NS.version .. " probe")

  local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
  note:SetWidth(520)
  note:SetJustifyH("LEFT")
  note:SetText("Summary of /dm probe (mouse wheel scrolls). /dm raw shows the raw call list; everything is saved in SavedVariables.")

  local scroll = CreateFrame("ScrollFrame", "DarkMatterProbeScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -78)
  scroll:SetPoint("BOTTOMRIGHT", -34, 46)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(504, 10)
  scroll:SetScrollChild(content)
  local probeText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  probeText:SetPoint("TOPLEFT", 0, 0)
  probeText:SetWidth(504)
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

  -- ESC closes it, the stock way (plain table insert; no secure code involved).
  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "DarkMatterProbeFrame") end
  return f
end

function NS.GetProbeWindow()
  if not pf then
    pf = Build()
    NS.RefreshProbeWindow()
  end
  return pf
end

function NS.RefreshProbeWindow()
  if not pf or not pf.probeText then return end
  local p = NS.lastProbe
  if p and p.summary then
    local text = table.concat(p.summary, "\n")
    if NS.showRaw and NS.RawLines then
      text = text .. "\n\n-- Raw call returns (type:value) --\n" .. table.concat(NS.RawLines(p), "\n")
    end
    pf.probeText:SetText(text)
    pf.probeContent:SetHeight((pf.probeText:GetStringHeight() or 0) + 8)
    pf.probeScroll:SetVerticalScroll(0)
  end
end

function NS.ShowProbeWindow()
  local f = NS.GetProbeWindow()
  f:Show()
end
