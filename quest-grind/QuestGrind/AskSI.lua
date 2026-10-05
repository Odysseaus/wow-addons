local _, NS = ...

-- Ask SI stub dialog (P0). Label is "Ask SI".
-- First AI providers: xAI + Claude.
-- Companion: recommend extend WoWGrok (P2 bridge). Keys never in Lua.

local PAD = 24
local askRoot, askArt

local function FS(parent, size, flags)
  local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if f.SetFont then
    local path = GameFontNormal:GetFont()
    f:SetFont(path, size or 12, flags or "")
  end
  f:SetJustifyH("LEFT")
  return f
end

local function Solid(parent, r, g, b, a)
  local f = CreateFrame("Frame", nil, parent)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
  f.tex = t
  return f
end

local function BuildAsk()
  if askRoot then return end

  local artW, artH = 340, 260
  askRoot = CreateFrame("Frame", "QuestGrindAskFrame", UIParent)
  askRoot:SetSize(artW + PAD * 2, artH + PAD * 2)
  askRoot:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  askRoot:SetFrameStrata("DIALOG")
  askRoot:SetMovable(true)
  askRoot:EnableMouse(true)
  askRoot:RegisterForDrag("LeftButton")
  askRoot:SetClipsChildren(false)
  askRoot:SetScript("OnDragStart", function(self) self:StartMoving() end)
  askRoot:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  askRoot:Hide()
  NS.askRoot = askRoot

  askArt = CreateFrame("Frame", nil, askRoot)
  askArt:SetSize(artW, artH)
  askArt:SetPoint("CENTER")

  local chrome = Solid(askArt, 0.72, 0.55, 0.22, 1)
  chrome:SetAllPoints()
  askArt.chrome = chrome

  local panel = Solid(askArt, 0.18, 0.12, 0.07, 0.96)
  panel:SetPoint("TOPLEFT", 8, -8)
  panel:SetPoint("BOTTOMRIGHT", -8, 8)
  askArt.panel = panel

  local title = FS(askArt, 18, "OUTLINE")
  title:SetPoint("TOP", 0, -22)
  title:SetJustifyH("CENTER")
  title:SetText("Ask SI")
  askArt.title = title

  local diamondL = Solid(askArt, 0.90, 0.78, 0.40, 1)
  diamondL:SetSize(10, 10)
  diamondL:SetPoint("RIGHT", title, "LEFT", -10, 0)
  askArt.diamondL = diamondL

  local diamondR = Solid(askArt, 0.90, 0.78, 0.40, 1)
  diamondR:SetSize(10, 10)
  diamondR:SetPoint("LEFT", title, "RIGHT", 10, 0)
  askArt.diamondR = diamondR

  local query = FS(askArt, 12)
  query:SetPoint("TOPLEFT", 24, -60)
  query:SetWidth(290)
  query:SetText("Where do I turn in Smart Drinks?")
  askArt.query = query

  local box = CreateFrame("Frame", nil, askArt)
  box:SetSize(290, 32)
  box:SetPoint("TOPLEFT", query, "BOTTOMLEFT", 0, -10)
  box.bg = box:CreateTexture(nil, "BACKGROUND")
  box.bg:SetAllPoints()
  box.bg:SetColorTexture(0.08, 0.06, 0.04, 0.95)
  box.border = Solid(box, 0.72, 0.55, 0.22, 1)
  box.border:SetPoint("TOPLEFT", -1, 1)
  box.border:SetPoint("BOTTOMRIGHT", 1, -1)
  box.border:SetFrameLevel(box:GetFrameLevel() - 1)

  local edit = CreateFrame("EditBox", "QuestGrindAskEditBox", box)
  edit:SetPoint("TOPLEFT", 8, -6)
  edit:SetPoint("BOTTOMRIGHT", -8, 6)
  edit:SetAutoFocus(false)
  edit:SetFontObject(GameFontHighlight)
  edit:SetTextInsets(0, 0, 0, 0)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  askArt.edit = edit

  local askBtn = CreateFrame("Button", nil, askArt)
  askBtn:SetSize(160, 32)
  askBtn:SetPoint("TOP", box, "BOTTOM", 0, -14)
  askBtn.bg = askBtn:CreateTexture(nil, "BACKGROUND")
  askBtn.bg:SetAllPoints()
  askBtn.bg:SetColorTexture(0.85, 0.65, 0.20, 1)
  askBtn.text = FS(askBtn, 13, "OUTLINE")
  askBtn.text:SetPoint("CENTER")
  askBtn.text:SetText("Ask SI")
  askBtn:SetScript("OnClick", function()
    local q = askArt.edit:GetText()
    if not q or q == "" then
      q = (NS.MockRoute and NS.MockRoute.askPlaceholder) or "…"
    end
    NS.Print("Ask SI (stub): \"" .. q .. "\"")
    NS.Print("P2 will bridge via extending WoWGrok. Providers: xAI + Claude. API keys stay on the companion — never in Lua.")
  end)
  askArt.askBtn = askBtn

  local tipIcon = Solid(askArt, 0.90, 0.78, 0.40, 1)
  tipIcon:SetSize(16, 16)
  tipIcon:SetPoint("BOTTOMLEFT", 24, 28)
  tipIcon.glyph = FS(tipIcon, 11, "OUTLINE")
  tipIcon.glyph:SetPoint("CENTER")
  tipIcon.glyph:SetText("!")
  askArt.tipIcon = tipIcon

  local tip = FS(askArt, 10)
  tip:SetPoint("LEFT", tipIcon, "RIGHT", 8, 0)
  tip:SetWidth(270)
  tip:SetText("Tip: Install the QuestGrind desktop companion for the best experience and choose your xAI or Claude API key in settings. Recommend extend WoWGrok. P0 stubs Ask; P2 bridges.")
  askArt.tip = tip

  local close = CreateFrame("Button", nil, askArt)
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -14, -14)
  close.bg = close:CreateTexture(nil, "BACKGROUND")
  close.bg:SetAllPoints()
  close.bg:SetColorTexture(0.7, 0.55, 0.25, 1)
  close.text = FS(close, 12, "OUTLINE")
  close.text:SetPoint("CENTER")
  close.text:SetText("X")
  close:SetScript("OnClick", function() NS.CloseAskSI() end)
  askArt.close = close
end

function NS.RefreshAskTheme()
  if not askArt then return end
  local th = NS.GetTheme()
  NS.SetVertexColor(askArt.chrome.tex, th.chrome)
  NS.SetVertexColor(askArt.panel.tex, th.panel)
  NS.SetVertexColor(askArt.title, th.title)
  NS.SetVertexColor(askArt.diamondL.tex, th.chromeHi)
  NS.SetVertexColor(askArt.diamondR.tex, th.chromeHi)
  NS.SetVertexColor(askArt.query, th.text)
  NS.SetVertexColor(askArt.askBtn.bg, th.accent)
  NS.SetVertexColor(askArt.askBtn.text, th.text)
  NS.SetVertexColor(askArt.tip, th.muted)
  NS.SetVertexColor(askArt.tipIcon.tex, th.chromeHi)
  NS.SetVertexColor(askArt.close.bg, th.chromeHi)
end

function NS.OpenAskSI()
  BuildAsk()
  local placeholder = (NS.MockRoute and NS.MockRoute.askPlaceholder) or "Where do I turn in Smart Drinks?"
  askArt.query:SetText(placeholder)
  askArt.edit:SetText(placeholder)
  NS.RefreshAskTheme()
  askRoot:Show()
  NS.Print("Ask SI opened (stub). Providers: xAI + Claude. Companion: extend WoWGrok.")
end

function NS.CloseAskSI()
  if askRoot then askRoot:Hide() end
end

-- Hook into theme apply
local prev = NS.ApplyDialogThemes
function NS.ApplyDialogThemes()
  if prev then prev() end
  if askRoot and askRoot:IsShown() then
    NS.RefreshAskTheme()
  end
end
