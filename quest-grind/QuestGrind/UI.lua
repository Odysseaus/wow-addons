local _, NS = ...

-- Layered UI: every visual piece is its own Frame so pieces can move later.
-- Transparent PAD outside chrome so ornate edges never clip (root > art).
-- Themes apply to Full AND Less AND Compass. Solid colors = P0/P1; TGA polish = P4.
-- P1: ApplyRoute / RefreshRouteUI paint live or mock; Route.lua rotates needles.

local PAD = 24
NS.PAD = PAD

local ART = {
  full = { w = 360, h = 420 },
  less = { w = 420, h = 110 },
  compass = { w = 200, h = 220 },
  minimized = { w = 180, h = 36 },
}

local layers = {}
NS.layers = layers

local function FS(parent, name, size, flags)
  local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if f.SetFont then
    local path = GameFontNormal:GetFont()
    f:SetFont(path, size or 12, flags or "")
  end
  f:SetJustifyH("LEFT")
  return f
end

local function Tex(parent)
  local t = parent:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  return t
end

local function Solid(parent, r, g, b, a)
  local f = CreateFrame("Frame", nil, parent)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
  f.tex = t
  return f
end

local function ChipButton(parent, label, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 28, h or 28)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0.5, 0.4, 0.2, 0.95)
  b.text = FS(b, nil, 12, "OUTLINE")
  b.text:SetPoint("CENTER")
  b.text:SetText(label or "")
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(0.7, 0.55, 0.25, 1)
  end)
  b:SetScript("OnLeave", function(self)
    local th = NS.GetTheme()
    NS.SetVertexColor(self.bg, th.chromeHi)
  end)
  return b
end

local function MakeSegmentBar(parent, n)
  local bar = CreateFrame("Frame", nil, parent)
  bar.segs = {}
  local i
  for i = 1, n do
    local s = CreateFrame("Frame", nil, bar)
    s:SetSize(28, 8)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetAllPoints()
    s.bg:SetColorTexture(0.15, 0.12, 0.08, 0.9)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetAllPoints()
    s.fill:SetColorTexture(0.85, 0.65, 0.2, 1)
    s.fill:Hide()
    if i == 1 then
      s:SetPoint("LEFT", bar, "LEFT", 0, 0)
    else
      s:SetPoint("LEFT", bar.segs[i - 1], "RIGHT", 3, 0)
    end
    bar.segs[i] = s
  end
  bar:SetSize(n * 31, 8)
  function bar:SetFilled(count, accent)
    local j
    for j = 1, #self.segs do
      if j <= count then
        if accent then NS.SetVertexColor(self.segs[j].fill, accent) end
        self.segs[j].fill:Show()
      else
        self.segs[j].fill:Hide()
      end
    end
  end
  return bar
end

local function EmblemGlyph(motif)
  if motif == "swords" then return "X"
  elseif motif == "paw" or motif == "leaf" then return "*"
  elseif motif == "feather" then return ">"
  elseif motif == "dagger" then return "+"
  elseif motif == "holy" then return "*"
  elseif motif == "totem" then return "^"
  elseif motif == "arcane" then return "*"
  elseif motif == "fel" then return "+"
  else return "!"
  end
end

function NS.BuildUI()
  if NS.root then return end

  local root = CreateFrame("Frame", "QuestGrindFrame", UIParent)
  root:SetSize(ART.full.w + PAD * 2, ART.full.h + PAD * 2)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  root:SetMovable(true)
  root:EnableMouse(true)
  root:RegisterForDrag("LeftButton")
  root:SetClipsChildren(false)
  root:SetFrameStrata("MEDIUM")
  -- Root has NO opaque background — transparent padding outside art.
  NS.root = root

  root:SetScript("OnDragStart", function(self)
    if NS.db and not NS.db.locked then
      self:StartMoving()
    end
  end)
  root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if NS.db then
      local p, _, rp, x, y = self:GetPoint(1)
      NS.db.point = p
      NS.db.relativePoint = rp
      NS.db.xOfs = x
      NS.db.yOfs = y
    end
  end)

  local art = CreateFrame("Frame", nil, root)
  art:SetSize(ART.full.w, ART.full.h)
  art:SetPoint("CENTER", root, "CENTER", 0, 0)
  layers.art = art

  -- Outer chrome (border)
  local chromeOuter = Solid(art, 0.72, 0.55, 0.22, 1)
  chromeOuter:SetAllPoints(art)
  layers.chromeOuter = chromeOuter

  -- Inner panel (wood/stone) inset from chrome
  local chromeInner = Solid(art, 0.18, 0.12, 0.07, 0.96)
  chromeInner:SetPoint("TOPLEFT", art, "TOPLEFT", 8, -8)
  chromeInner:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -8, 8)
  layers.chromeInner = chromeInner

  -- Corner filigree accents (separate layers)
  local function Corner(name, point, ox, oy)
    local c = Solid(art, 0.90, 0.78, 0.40, 1)
    c:SetSize(18, 18)
    c:SetPoint(point, art, point, ox, oy)
    layers[name] = c
  end
  Corner("cornerTL", "TOPLEFT", 2, -2)
  Corner("cornerTR", "TOPRIGHT", -2, -2)
  Corner("cornerBL", "BOTTOMLEFT", 2, 2)
  Corner("cornerBR", "BOTTOMRIGHT", -2, 2)

  -- Quest bang / motif emblem (own layer)
  local emblem = CreateFrame("Frame", nil, art)
  emblem:SetSize(40, 40)
  emblem:SetPoint("TOP", art, "TOP", 0, 6)
  emblem.bg = emblem:CreateTexture(nil, "BACKGROUND")
  emblem.bg:SetAllPoints()
  emblem.bg:SetColorTexture(0.72, 0.55, 0.22, 1)
  emblem.ring = emblem:CreateTexture(nil, "BORDER")
  emblem.ring:SetPoint("TOPLEFT", 3, -3)
  emblem.ring:SetPoint("BOTTOMRIGHT", -3, 3)
  emblem.ring:SetColorTexture(0.10, 0.08, 0.05, 1)
  emblem.glyph = FS(emblem, nil, 18, "OUTLINE")
  emblem.glyph:SetPoint("CENTER")
  emblem.glyph:SetText("!")
  layers.emblem = emblem

  -- Title
  local title = CreateFrame("Frame", nil, art)
  title:SetSize(200, 24)
  title:SetPoint("TOP", art, "TOP", 0, -28)
  title.text = FS(title, nil, 18, "OUTLINE")
  title.text:SetPoint("CENTER")
  title.text:SetText("QuestGrind")
  layers.title = title

  -- Window controls (own layers)
  local btnClose = ChipButton(art, "X", 24, 24)
  btnClose:SetPoint("TOPRIGHT", art, "TOPRIGHT", -14, -14)
  btnClose:SetScript("OnClick", function() root:Hide() end)
  layers.btnClose = btnClose

  local btnMinimize = ChipButton(art, "-", 24, 24)
  btnMinimize:SetPoint("RIGHT", btnClose, "LEFT", -4, 0)
  btnMinimize:SetScript("OnClick", function() NS.ToggleMinimize() end)
  layers.btnMinimize = btnMinimize

  local btnEdit = ChipButton(art, "E", 24, 24)
  btnEdit:SetPoint("RIGHT", btnMinimize, "LEFT", -4, 0)
  btnEdit:SetScript("OnClick", function() NS.ToggleEditMode() end)
  layers.btnEdit = btnEdit

  local btnMode = ChipButton(art, "M", 24, 24)
  btnMode:SetPoint("RIGHT", btnEdit, "LEFT", -4, 0)
  btnMode:SetScript("OnClick", function() NS.CycleMode() end)
  layers.btnModeCycle = btnMode

  -- ===== FULL mode content layers =====
  local routeRow = CreateFrame("Frame", nil, art)
  routeRow:SetSize(200, 48)
  routeRow:SetPoint("TOPLEFT", art, "TOPLEFT", 20, -60)
  routeRow.icon = Solid(routeRow, 0.72, 0.55, 0.22, 1)
  routeRow.icon:SetSize(22, 22)
  routeRow.icon:SetPoint("TOPLEFT", 0, 0)
  routeRow.iconGlyph = FS(routeRow.icon, nil, 12, "OUTLINE")
  routeRow.iconGlyph:SetPoint("CENTER")
  routeRow.iconGlyph:SetText("o")
  routeRow.name = FS(routeRow, nil, 14, "OUTLINE")
  routeRow.name:SetPoint("LEFT", routeRow.icon, "RIGHT", 8, 4)
  routeRow.progress = FS(routeRow, nil, 11)
  routeRow.progress:SetPoint("LEFT", routeRow.name, "RIGHT", 6, 0)
  routeRow.bar = MakeSegmentBar(routeRow, 5)
  routeRow.bar:SetPoint("TOPLEFT", routeRow.icon, "BOTTOMLEFT", 0, -8)
  layers.routeRow = routeRow

  local stepRow = CreateFrame("Frame", nil, art)
  stepRow:SetSize(200, 70)
  stepRow:SetPoint("TOPLEFT", routeRow, "BOTTOMLEFT", 0, -10)
  stepRow.icon = Solid(stepRow, 0.72, 0.55, 0.22, 1)
  stepRow.icon:SetSize(22, 22)
  stepRow.icon:SetPoint("TOPLEFT", 0, 0)
  stepRow.iconGlyph = FS(stepRow.icon, nil, 12, "OUTLINE")
  stepRow.iconGlyph:SetPoint("CENTER")
  stepRow.iconGlyph:SetText("o")
  stepRow.label = FS(stepRow, nil, 10)
  stepRow.label:SetPoint("LEFT", stepRow.icon, "RIGHT", 8, 6)
  stepRow.label:SetText("Current Step")
  stepRow.title = FS(stepRow, nil, 15, "OUTLINE")
  stepRow.title:SetPoint("TOPLEFT", stepRow.label, "BOTTOMLEFT", 0, -2)
  stepRow.dist = FS(stepRow, nil, 11)
  stepRow.dist:SetPoint("TOPLEFT", stepRow.title, "BOTTOMLEFT", 0, -2)
  stepRow.bearing = FS(stepRow, nil, 11)
  stepRow.bearing:SetPoint("LEFT", stepRow.dist, "RIGHT", 4, 0)
  stepRow.approx = FS(stepRow, nil, 11)
  stepRow.approx:SetPoint("LEFT", stepRow.bearing, "RIGHT", 4, 0)
  stepRow.zone = FS(stepRow, nil, 11)
  stepRow.zone:SetPoint("TOPLEFT", stepRow.dist, "BOTTOMLEFT", 0, -2)
  layers.stepRow = stepRow

  local trackerRow = CreateFrame("Frame", nil, art)
  trackerRow:SetSize(200, 50)
  trackerRow:SetPoint("TOPLEFT", stepRow, "BOTTOMLEFT", 0, -8)
  trackerRow.label = FS(trackerRow, nil, 10)
  trackerRow.label:SetPoint("TOPLEFT", 0, 0)
  trackerRow.label:SetText("Tracker")
  trackerRow.icon = Solid(trackerRow, 0.6, 0.2, 0.2, 1)
  trackerRow.icon:SetSize(20, 20)
  trackerRow.icon:SetPoint("TOPLEFT", trackerRow.label, "BOTTOMLEFT", 0, -4)
  trackerRow.text = FS(trackerRow, nil, 12)
  trackerRow.text:SetPoint("LEFT", trackerRow.icon, "RIGHT", 8, 4)
  trackerRow.count = FS(trackerRow, nil, 14, "OUTLINE")
  trackerRow.count:SetPoint("TOPLEFT", trackerRow.text, "BOTTOMLEFT", 0, -2)
  layers.trackerRow = trackerRow

  -- Right column: large compass
  local compassLarge = CreateFrame("Frame", nil, art)
  compassLarge:SetSize(130, 130)
  compassLarge:SetPoint("TOPRIGHT", art, "TOPRIGHT", -24, -70)
  compassLarge.face = Solid(compassLarge, 0.25, 0.20, 0.12, 1)
  compassLarge.face:SetAllPoints()
  compassLarge.ring = Solid(compassLarge, 0.72, 0.55, 0.22, 1)
  compassLarge.ring:SetPoint("TOPLEFT", -4, 4)
  compassLarge.ring:SetPoint("BOTTOMRIGHT", 4, -4)
  compassLarge.ring:SetFrameLevel(compassLarge:GetFrameLevel() - 1)
  compassLarge.N = FS(compassLarge, nil, 12, "OUTLINE")
  compassLarge.N:SetPoint("TOP", 0, -8)
  compassLarge.N:SetText("N")
  compassLarge.E = FS(compassLarge, nil, 12, "OUTLINE")
  compassLarge.E:SetPoint("RIGHT", -8, 0)
  compassLarge.E:SetText("E")
  compassLarge.S = FS(compassLarge, nil, 12, "OUTLINE")
  compassLarge.S:SetPoint("BOTTOM", 0, 8)
  compassLarge.S:SetText("S")
  compassLarge.W = FS(compassLarge, nil, 12, "OUTLINE")
  compassLarge.W:SetPoint("LEFT", 8, 0)
  compassLarge.W:SetText("W")
  compassLarge.needle = Solid(compassLarge, 0.90, 0.78, 0.40, 1)
  compassLarge.needle:SetSize(6, 50)
  compassLarge.needle:SetPoint("CENTER", 8, 12)
  layers.compassLarge = compassLarge

  local statusBlock = CreateFrame("Frame", nil, art)
  statusBlock:SetSize(130, 80)
  statusBlock:SetPoint("TOP", compassLarge, "BOTTOM", 0, -12)
  statusBlock.label = FS(statusBlock, nil, 10)
  statusBlock.label:SetPoint("TOPLEFT", 0, 0)
  statusBlock.label:SetText("Status")
  statusBlock.state = FS(statusBlock, nil, 13, "OUTLINE")
  statusBlock.state:SetPoint("TOPLEFT", statusBlock.label, "BOTTOMLEFT", 0, -2)
  statusBlock.lastLabel = FS(statusBlock, nil, 10)
  statusBlock.lastLabel:SetPoint("TOPLEFT", statusBlock.state, "BOTTOMLEFT", 0, -6)
  statusBlock.lastLabel:SetText("Last")
  statusBlock.last = FS(statusBlock, nil, 12)
  statusBlock.last:SetPoint("LEFT", statusBlock.lastLabel, "RIGHT", 6, 0)
  statusBlock.xp = FS(statusBlock, nil, 13, "OUTLINE")
  statusBlock.xp:SetPoint("TOPLEFT", statusBlock.lastLabel, "BOTTOMLEFT", 0, -4)
  layers.statusBlock = statusBlock

  -- Divider between columns
  local divider = Solid(art, 0.72, 0.55, 0.22, 0.6)
  divider:SetSize(2, 240)
  divider:SetPoint("TOP", art, "TOP", 20, -60)
  layers.divider = divider

  -- Ask SI button (own layer)
  local askButton = CreateFrame("Button", nil, art)
  askButton:SetSize(200, 36)
  askButton:SetPoint("BOTTOM", art, "BOTTOM", 0, 24)
  askButton.bg = askButton:CreateTexture(nil, "BACKGROUND")
  askButton.bg:SetAllPoints()
  askButton.bg:SetColorTexture(0.85, 0.65, 0.20, 1)
  askButton.border = askButton:CreateTexture(nil, "BORDER")
  askButton.border:SetPoint("TOPLEFT", -2, 2)
  askButton.border:SetPoint("BOTTOMRIGHT", 2, -2)
  askButton.border:SetColorTexture(0.72, 0.55, 0.22, 1)
  askButton:SetFrameLevel(askButton:GetFrameLevel() + 1)
  askButton.text = FS(askButton, nil, 14, "OUTLINE")
  askButton.text:SetPoint("CENTER")
  askButton.text:SetText("Ask SI")
  askButton:SetScript("OnClick", function()
    if NS.OpenAskSI then NS.OpenAskSI() end
  end)
  layers.askButton = askButton

  -- Bottom diamond filigree
  local bottomJewel = Solid(art, 0.90, 0.78, 0.40, 1)
  bottomJewel:SetSize(14, 14)
  bottomJewel:SetPoint("BOTTOM", art, "BOTTOM", 0, 6)
  layers.bottomJewel = bottomJewel

  -- ===== LESS mode layers =====
  local lessCompass = CreateFrame("Frame", nil, art)
  lessCompass:SetSize(70, 70)
  lessCompass:SetPoint("LEFT", art, "LEFT", 16, 0)
  lessCompass.face = Solid(lessCompass, 0.25, 0.20, 0.12, 1)
  lessCompass.face:SetAllPoints()
  lessCompass.ring = Solid(lessCompass, 0.72, 0.55, 0.22, 1)
  lessCompass.ring:SetPoint("TOPLEFT", -3, 3)
  lessCompass.ring:SetPoint("BOTTOMRIGHT", 3, -3)
  lessCompass.ring:SetFrameLevel(lessCompass:GetFrameLevel() - 1)
  lessCompass.needle = Solid(lessCompass, 0.90, 0.78, 0.40, 1)
  lessCompass.needle:SetSize(4, 28)
  lessCompass.needle:SetPoint("CENTER", 4, 6)
  layers.lessCompass = lessCompass

  local lessTitle = CreateFrame("Frame", nil, art)
  lessTitle:SetSize(220, 20)
  lessTitle:SetPoint("TOPLEFT", lessCompass, "TOPRIGHT", 12, -4)
  lessTitle.text = FS(lessTitle, nil, 15, "OUTLINE")
  lessTitle.text:SetPoint("LEFT")
  layers.lessTitle = lessTitle

  local lessDistance = CreateFrame("Frame", nil, art)
  lessDistance:SetSize(220, 18)
  lessDistance:SetPoint("TOPLEFT", lessTitle, "BOTTOMLEFT", 0, -2)
  lessDistance.diamondL = Solid(lessDistance, 0.90, 0.78, 0.40, 1)
  lessDistance.diamondL:SetSize(8, 8)
  lessDistance.diamondL:SetPoint("LEFT", 40, 0)
  lessDistance.text = FS(lessDistance, nil, 13, "OUTLINE")
  lessDistance.text:SetPoint("LEFT", lessDistance.diamondL, "RIGHT", 8, 0)
  lessDistance.diamondR = Solid(lessDistance, 0.90, 0.78, 0.40, 1)
  lessDistance.diamondR:SetSize(8, 8)
  lessDistance.diamondR:SetPoint("LEFT", lessDistance.text, "RIGHT", 8, 0)
  layers.lessDistance = lessDistance

  local lessProgress = CreateFrame("Frame", nil, art)
  lessProgress:SetSize(220, 12)
  lessProgress:SetPoint("TOPLEFT", lessDistance, "BOTTOMLEFT", 0, -6)
  lessProgress.bar = MakeSegmentBar(lessProgress, 5)
  lessProgress.bar:SetPoint("LEFT", 0, 0)
  layers.lessProgress = lessProgress

  local modeChrome = CreateFrame("Frame", nil, art)
  modeChrome:SetSize(56, 70)
  modeChrome:SetPoint("RIGHT", art, "RIGHT", -12, 0)
  modeChrome.bg = Solid(modeChrome, 0.72, 0.55, 0.22, 1)
  modeChrome.bg:SetAllPoints()
  modeChrome.inner = Solid(modeChrome, 0.18, 0.12, 0.07, 0.96)
  modeChrome.inner:SetPoint("TOPLEFT", 3, -3)
  modeChrome.inner:SetPoint("BOTTOMRIGHT", -3, 3)
  modeChrome.label = FS(modeChrome, nil, 12, "OUTLINE")
  modeChrome.label:SetPoint("CENTER", 0, 8)
  modeChrome.chevron = FS(modeChrome, nil, 14, "OUTLINE")
  modeChrome.chevron:SetPoint("CENTER", 0, -12)
  modeChrome.chevron:SetText("v")
  modeChrome:EnableMouse(true)
  modeChrome:SetScript("OnMouseUp", function() NS.CycleMode() end)
  layers.modeChrome = modeChrome

  -- ===== COMPASS mode layers =====
  local compassOnly = CreateFrame("Frame", nil, art)
  compassOnly:SetSize(160, 160)
  compassOnly:SetPoint("CENTER", art, "CENTER", 0, 8)
  compassOnly.face = Solid(compassOnly, 0.30, 0.25, 0.18, 1)
  compassOnly.face:SetAllPoints()
  compassOnly.ring = Solid(compassOnly, 0.72, 0.55, 0.22, 1)
  compassOnly.ring:SetPoint("TOPLEFT", -5, 5)
  compassOnly.ring:SetPoint("BOTTOMRIGHT", 5, -5)
  compassOnly.ring:SetFrameLevel(compassOnly:GetFrameLevel() - 1)
  compassOnly.N = FS(compassOnly, nil, 14, "OUTLINE")
  compassOnly.N:SetPoint("TOP", 0, -10)
  compassOnly.N:SetText("N")
  compassOnly.E = FS(compassOnly, nil, 14, "OUTLINE")
  compassOnly.E:SetPoint("RIGHT", -10, 0)
  compassOnly.E:SetText("E")
  compassOnly.S = FS(compassOnly, nil, 14, "OUTLINE")
  compassOnly.S:SetPoint("BOTTOM", 0, 28)
  compassOnly.S:SetText("S")
  compassOnly.W = FS(compassOnly, nil, 14, "OUTLINE")
  compassOnly.W:SetPoint("LEFT", 10, 0)
  compassOnly.W:SetText("W")
  compassOnly.needle = Solid(compassOnly, 0.90, 0.78, 0.40, 1)
  compassOnly.needle:SetSize(8, 60)
  compassOnly.needle:SetPoint("CENTER", 10, 16)
  compassOnly.dist = FS(compassOnly, nil, 13, "OUTLINE")
  compassOnly.dist:SetPoint("BOTTOM", 0, 12)
  layers.compassOnlyFace = compassOnly

  local compassPlate = CreateFrame("Frame", nil, art)
  compassPlate:SetSize(100, 24)
  compassPlate:SetPoint("BOTTOM", art, "BOTTOM", 0, 14)
  compassPlate.bg = Solid(compassPlate, 0.72, 0.55, 0.22, 1)
  compassPlate.bg:SetAllPoints()
  compassPlate.label = FS(compassPlate, nil, 12, "OUTLINE")
  compassPlate.label:SetPoint("CENTER")
  compassPlate.label:SetText("Compass")
  layers.compassPlate = compassPlate

  -- Crest for compass mode top
  local compassCrest = Solid(art, 0.90, 0.78, 0.40, 1)
  compassCrest:SetSize(36, 16)
  compassCrest:SetPoint("TOP", art, "TOP", 0, -10)
  layers.compassCrest = compassCrest

  -- Minimized restore chip
  local miniBar = CreateFrame("Button", nil, art)
  miniBar:SetSize(160, 28)
  miniBar:SetPoint("CENTER", art, "CENTER", 0, 0)
  miniBar.bg = miniBar:CreateTexture(nil, "BACKGROUND")
  miniBar.bg:SetAllPoints()
  miniBar.bg:SetColorTexture(0.72, 0.55, 0.22, 1)
  miniBar.text = FS(miniBar, nil, 12, "OUTLINE")
  miniBar.text:SetPoint("CENTER")
  miniBar.text:SetText("QuestGrind")
  miniBar:SetScript("OnClick", function() NS.ToggleMinimize() end)
  miniBar:Hide()
  layers.miniBar = miniBar

  if NS.db then
    root:ClearAllPoints()
    root:SetPoint(NS.db.point or "CENTER", UIParent, NS.db.relativePoint or "CENTER", NS.db.xOfs or 0, NS.db.yOfs or 80)
    root:SetScale(NS.db.scale or 1)
  end
end

local FULL_LAYERS = {
  "routeRow", "stepRow", "trackerRow", "compassLarge", "statusBlock",
  "askButton", "divider", "bottomJewel", "emblem", "title",
  "btnClose", "btnMinimize", "btnEdit", "btnModeCycle",
}
local LESS_LAYERS = {
  "lessCompass", "lessTitle", "lessDistance", "lessProgress", "modeChrome",
  "btnClose", "btnMinimize", "btnEdit",
}
local COMPASS_LAYERS = {
  "compassOnlyFace", "compassPlate", "compassCrest",
  "btnClose", "btnMinimize", "btnEdit", "btnModeCycle",
}
local ALWAYS = {
  "chromeOuter", "chromeInner", "cornerTL", "cornerTR", "cornerBL", "cornerBR",
}

local function HideAllContent()
  local name, frame
  for name, frame in pairs(layers) do
    if name ~= "art" and name ~= "chromeOuter" and name ~= "chromeInner"
      and name ~= "cornerTL" and name ~= "cornerTR"
      and name ~= "cornerBL" and name ~= "cornerBR"
      and name ~= "miniBar" then
      frame:Hide()
    end
  end
end

local function ShowList(list)
  local i, name
  for i = 1, #list do
    name = list[i]
    if layers[name] then layers[name]:Show() end
  end
end

local function ResizeForMode(mode)
  local a = ART[mode] or ART.full
  if NS.db and NS.db.minimized then
    a = ART.minimized
  end
  layers.art:SetSize(a.w, a.h)
  NS.root:SetSize(a.w + PAD * 2, a.h + PAD * 2)
  -- Re-anchor chrome inner inset
  layers.chromeInner:ClearAllPoints()
  layers.chromeInner:SetPoint("TOPLEFT", layers.art, "TOPLEFT", 8, -8)
  layers.chromeInner:SetPoint("BOTTOMRIGHT", layers.art, "BOTTOMRIGHT", -8, 8)
end

function NS.ApplyMode()
  if not NS.root then return end
  if NS.db and NS.db.minimized then
    NS.ApplyMinimize()
    return
  end
  local mode = (NS.db and NS.db.mode) or "full"
  HideAllContent()
  layers.miniBar:Hide()
  ShowList(ALWAYS)
  if mode == "less" then
    ShowList(LESS_LAYERS)
    if layers.modeChrome and layers.modeChrome.label then
      layers.modeChrome.label:SetText("Less")
    end
  elseif mode == "compass" then
    ShowList(COMPASS_LAYERS)
  else
    ShowList(FULL_LAYERS)
  end
  ResizeForMode(mode)
  if NS.Refresh then
    NS.Refresh()
  else
    NS.RefreshMock()
  end
  NS.ApplyTheme()
end

function NS.ApplyMinimize()
  if not NS.root then return end
  if NS.db and NS.db.minimized then
    HideAllContent()
    ShowList(ALWAYS)
    layers.miniBar:Show()
    ResizeForMode("minimized")
    NS.ApplyTheme()
  else
    NS.ApplyMode()
  end
end

function NS.ApplyLock()
  -- Drag gated in OnDragStart via NS.db.locked
end

function NS.ApplyTheme()
  if not NS.root then return end
  local th = NS.GetTheme()
  local set = NS.SetVertexColor

  set(layers.chromeOuter.tex, th.chrome)
  set(layers.chromeInner.tex, th.panel)
  set(layers.cornerTL.tex, th.chromeHi)
  set(layers.cornerTR.tex, th.chromeHi)
  set(layers.cornerBL.tex, th.chromeHi)
  set(layers.cornerBR.tex, th.chromeHi)
  set(layers.bottomJewel.tex, th.chromeHi)
  set(layers.divider.tex, th.chrome, 0.6)

  if layers.emblem then
    set(layers.emblem.bg, th.chrome)
    set(layers.emblem.glyph, th.title)
    layers.emblem.glyph:SetText(EmblemGlyph(th.motif))
  end
  if layers.title then set(layers.title.text, th.title) end

  local function paintBtn(b)
    if not b then return end
    set(b.bg, th.chromeHi)
    set(b.text, th.text)
  end
  paintBtn(layers.btnClose)
  paintBtn(layers.btnMinimize)
  paintBtn(layers.btnEdit)
  paintBtn(layers.btnModeCycle)

  if layers.routeRow then
    set(layers.routeRow.icon.tex, th.chrome)
    set(layers.routeRow.name, th.title)
    set(layers.routeRow.progress, th.text)
    layers.routeRow.bar:SetFilled(((NS.liveRoute or NS.MockRoute) and (NS.liveRoute or NS.MockRoute).filled) or 1, th.accent)
  end
  if layers.stepRow then
    set(layers.stepRow.icon.tex, th.chrome)
    set(layers.stepRow.label, th.title)
    set(layers.stepRow.title, th.text)
    set(layers.stepRow.dist, th.muted)
    set(layers.stepRow.bearing, th.statusOk)
    set(layers.stepRow.approx, th.muted)
    set(layers.stepRow.zone, th.title)
  end
  if layers.trackerRow then
    set(layers.trackerRow.label, th.title)
    set(layers.trackerRow.text, th.text)
    set(layers.trackerRow.count, th.text)
  end
  if layers.compassLarge then
    set(layers.compassLarge.face.tex, th.panel)
    set(layers.compassLarge.ring.tex, th.chrome)
    set(layers.compassLarge.needle.tex, th.chromeHi)
    set(layers.compassLarge.N, th.title)
    set(layers.compassLarge.E, th.title)
    set(layers.compassLarge.S, th.title)
    set(layers.compassLarge.W, th.title)
  end
  if layers.statusBlock then
    set(layers.statusBlock.label, th.title)
    set(layers.statusBlock.state, th.statusOk)
    set(layers.statusBlock.lastLabel, th.muted)
    set(layers.statusBlock.last, th.text)
    set(layers.statusBlock.xp, th.statusXp)
  end
  if layers.askButton then
    set(layers.askButton.bg, th.accent)
    set(layers.askButton.border, th.chrome)
    set(layers.askButton.text, th.text)
  end

  -- Less mode
  if layers.lessCompass then
    set(layers.lessCompass.face.tex, th.panel)
    set(layers.lessCompass.ring.tex, th.chrome)
    set(layers.lessCompass.needle.tex, th.chromeHi)
  end
  if layers.lessTitle then set(layers.lessTitle.text, th.text) end
  if layers.lessDistance then
    set(layers.lessDistance.text, th.text)
    set(layers.lessDistance.diamondL.tex, th.chromeHi)
    set(layers.lessDistance.diamondR.tex, th.chromeHi)
  end
  if layers.lessProgress then
    layers.lessProgress.bar:SetFilled(((NS.liveRoute or NS.MockRoute) and (NS.liveRoute or NS.MockRoute).filled) or 1, th.accent)
  end
  if layers.modeChrome then
    set(layers.modeChrome.bg.tex, th.chrome)
    set(layers.modeChrome.inner.tex, th.panel)
    set(layers.modeChrome.label, th.text)
    set(layers.modeChrome.chevron, th.chromeHi)
  end

  -- Compass mode
  if layers.compassOnlyFace then
    set(layers.compassOnlyFace.face.tex, th.panel)
    set(layers.compassOnlyFace.ring.tex, th.chrome)
    set(layers.compassOnlyFace.needle.tex, th.chromeHi)
    set(layers.compassOnlyFace.N, th.title)
    set(layers.compassOnlyFace.E, th.title)
    set(layers.compassOnlyFace.S, th.title)
    set(layers.compassOnlyFace.W, th.title)
    set(layers.compassOnlyFace.dist, th.text)
  end
  if layers.compassPlate then
    set(layers.compassPlate.bg.tex, th.chrome)
    set(layers.compassPlate.label, th.title)
  end
  if layers.compassCrest then
    set(layers.compassCrest.tex, th.chromeHi)
  end
  if layers.miniBar then
    set(layers.miniBar.bg, th.chrome)
    set(layers.miniBar.text, th.title)
  end

  if NS.ApplyDialogThemes then NS.ApplyDialogThemes() end
end

function NS.SetNeedleRotation(needleFrame, radians)
  if not needleFrame then return end
  local tex = needleFrame.tex
  if tex and type(tex.SetRotation) == "function" then
    pcall(tex.SetRotation, tex, radians)
    return
  end
  if type(needleFrame.SetRotation) == "function" then
    pcall(needleFrame.SetRotation, needleFrame, radians)
    return
  end
  if needleFrame.SetPoint and needleFrame:GetParent() then
    local ox = math.sin(radians or 0) * 12
    local oy = math.cos(radians or 0) * 12
    needleFrame:ClearAllPoints()
    needleFrame:SetPoint("CENTER", needleFrame:GetParent(), "CENTER", ox, oy)
  end
end

--- Paint HUD from any MockRoute-compatible table (live or mock).
function NS.ApplyRoute(m)
  if not m or not layers.routeRow then return end

  layers.routeRow.name:SetText(m.name or "")
  layers.routeRow.progress:SetText(string.format("%d/%d", m.index or 0, m.total or 0))
  layers.routeRow.bar:SetFilled(m.filled or 1, NS.GetTheme().accent)

  local step = m.step or {}
  layers.stepRow.title:SetText(step.title or "")
  layers.stepRow.dist:SetText((step.distance or "?") .. " ·")
  layers.stepRow.bearing:SetText(step.bearing or "")
  layers.stepRow.approx:SetText("· " .. (step.approx or ""))
  layers.stepRow.zone:SetText(step.zone or "")

  local tracker = m.tracker or {}
  layers.trackerRow.text:SetText(tracker.label or "")
  layers.trackerRow.count:SetText(string.format("%d/%d", tracker.count or 0, tracker.total or 0))

  local status = m.status or {}
  layers.statusBlock.state:SetText(status.state or "")
  layers.statusBlock.last:SetText(status.last or "")
  layers.statusBlock.xp:SetText(status.xp or "")

  if layers.lessTitle then layers.lessTitle.text:SetText(step.title or "") end
  if layers.lessDistance then layers.lessDistance.text:SetText(step.distance or "?") end
  if layers.lessProgress then
    layers.lessProgress.bar:SetFilled(m.filled or 1, NS.GetTheme().accent)
  end
  if layers.compassOnlyFace then
    layers.compassOnlyFace.dist:SetText(step.distance or "?")
  end

  if m.bearingDeg and NS.UpdateCompassNeedles then
    NS.UpdateCompassNeedles(m.bearingDeg)
  end
end

function NS.RefreshMock()
  NS.ApplyRoute(NS.MockRoute)
end

--- Soft update: distance / bearing / zone / compass only (ticker path).
function NS.RefreshRouteUI(m)
  m = m or NS.liveRoute
  if not m or not layers.stepRow then return end
  local step = m.step or {}
  layers.stepRow.dist:SetText((step.distance or "?") .. " ·")
  layers.stepRow.bearing:SetText(step.bearing or "")
  layers.stepRow.approx:SetText("· " .. (step.approx or ""))
  layers.stepRow.zone:SetText(step.zone or "")
  if layers.lessDistance then layers.lessDistance.text:SetText(step.distance or "?") end
  if layers.compassOnlyFace then
    layers.compassOnlyFace.dist:SetText(step.distance or "?")
  end
  if m.bearingDeg and NS.UpdateCompassNeedles then
    NS.UpdateCompassNeedles(m.bearingDeg)
  end
end
