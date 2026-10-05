local _, NS = ...

-- In-addon Edit Mode: theme picker for default + Forever class themes.
-- Themes apply to Full, Less, AND Compass. Labels may use class names;
-- textures never bake class name strings (colors/motifs only).

local PAD = 24
local editRoot, editArt, themeButtons

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

local function BuildEdit()
  if editRoot then return end

  local artW, artH = 320, 420
  editRoot = CreateFrame("Frame", "QuestGrindEditFrame", UIParent)
  editRoot:SetSize(artW + PAD * 2, artH + PAD * 2)
  editRoot:SetPoint("CENTER", UIParent, "CENTER", 220, 40)
  editRoot:SetFrameStrata("DIALOG")
  editRoot:SetMovable(true)
  editRoot:EnableMouse(true)
  editRoot:RegisterForDrag("LeftButton")
  editRoot:SetClipsChildren(false)
  editRoot:SetScript("OnDragStart", function(self) self:StartMoving() end)
  editRoot:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  editRoot:Hide()
  NS.editRoot = editRoot

  editArt = CreateFrame("Frame", nil, editRoot)
  editArt:SetSize(artW, artH)
  editArt:SetPoint("CENTER")
  NS.editArt = editArt

  local chrome = Solid(editArt, 0.72, 0.55, 0.22, 1)
  chrome:SetAllPoints()
  editArt.chrome = chrome

  local panel = Solid(editArt, 0.18, 0.12, 0.07, 0.96)
  panel:SetPoint("TOPLEFT", 8, -8)
  panel:SetPoint("BOTTOMRIGHT", -8, 8)
  editArt.panel = panel

  local title = FS(editArt, 16, "OUTLINE")
  title:SetPoint("TOP", 0, -20)
  title:SetText("Edit Mode")
  editArt.title = title

  local sub = FS(editArt, 12)
  sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
  sub:SetText("Theme")
  editArt.sub = sub

  local note = FS(editArt, 10)
  note:SetPoint("BOTTOM", 0, 40)
  note:SetWidth(280)
  note:SetJustifyH("CENTER")
  note:SetText("Themes apply to Full, Less, and Compass. Art polish (TGA) is P4 — colors/motifs for now.")
  editArt.note = note

  local close = CreateFrame("Button", nil, editArt)
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", -14, -14)
  close.bg = close:CreateTexture(nil, "BACKGROUND")
  close.bg:SetAllPoints()
  close.bg:SetColorTexture(0.7, 0.55, 0.25, 1)
  close.text = FS(close, 12, "OUTLINE")
  close.text:SetPoint("CENTER")
  close.text:SetText("X")
  close:SetScript("OnClick", function() NS.CloseEditMode() end)
  editArt.close = close

  themeButtons = {}
  local i, id
  for i, id in ipairs(NS.THEME_ORDER) do
    local th = NS.THEMES[id]
    local btn = CreateFrame("Button", nil, editArt)
    btn:SetSize(280, 28)
    local row = i - 1
    btn:SetPoint("TOPLEFT", 20, -60 - row * 30)

    btn.swatchChrome = btn:CreateTexture(nil, "BACKGROUND")
    btn.swatchChrome:SetSize(20, 20)
    btn.swatchChrome:SetPoint("LEFT", 4, 0)
    btn.swatchChrome:SetColorTexture(th.chrome.r, th.chrome.g, th.chrome.b, 1)

    btn.swatchAccent = btn:CreateTexture(nil, "ARTWORK")
    btn.swatchAccent:SetSize(10, 10)
    btn.swatchAccent:SetPoint("CENTER", btn.swatchChrome, "CENTER", 0, 0)
    btn.swatchAccent:SetColorTexture(th.accent.r, th.accent.g, th.accent.b, 1)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetPoint("TOPLEFT", 28, 0)
    btn.bg:SetPoint("BOTTOMRIGHT", 0, 0)
    btn.bg:SetColorTexture(0.12, 0.10, 0.08, 0.6)

    btn.label = FS(btn, 12, "OUTLINE")
    btn.label:SetPoint("LEFT", btn.swatchChrome, "RIGHT", 12, 0)
    btn.label:SetText(th.label) -- picker label OK; not painted into art textures

    btn.themeId = id
    btn:SetScript("OnClick", function(self)
      NS.SetTheme(self.themeId)
      NS.RefreshEditMode()
    end)
    themeButtons[#themeButtons + 1] = btn
  end
end

function NS.RefreshEditMode()
  if not themeButtons then return end
  local cur = NS.db and NS.db.theme or "default"
  local th = NS.GetTheme()
  local i, btn
  for i = 1, #themeButtons do
    btn = themeButtons[i]
    if btn.themeId == cur then
      btn.bg:SetColorTexture(th.accent.r, th.accent.g, th.accent.b, 0.35)
    else
      btn.bg:SetColorTexture(0.12, 0.10, 0.08, 0.6)
    end
  end
  if editArt then
    NS.SetVertexColor(editArt.chrome.tex, th.chrome)
    NS.SetVertexColor(editArt.panel.tex, th.panel)
    NS.SetVertexColor(editArt.title, th.title)
    NS.SetVertexColor(editArt.sub, th.muted)
    NS.SetVertexColor(editArt.note, th.muted)
    NS.SetVertexColor(editArt.close.bg, th.chromeHi)
  end
end

function NS.OpenEditMode()
  BuildEdit()
  NS.RefreshEditMode()
  editRoot:Show()
  NS.editOpen = true
  NS.Print("Edit Mode — pick a theme (applies to Full, Less, Compass).")
end

function NS.CloseEditMode()
  if editRoot then editRoot:Hide() end
  NS.editOpen = false
end

function NS.ApplyDialogThemes()
  if editRoot and editRoot:IsShown() then
    NS.RefreshEditMode()
  end
end
