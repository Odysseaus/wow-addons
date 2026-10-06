local _, NS = ...

-- Layered UI: every visual piece is its own Frame so pieces can move later.
-- Transparent PAD outside chrome so ornate edges never clip (root > art).
-- Themes apply to Full AND Less AND Compass. Solid colors = P0/P1; TGA polish = P4.
-- P1: ApplyRoute / RefreshRouteUI paint live or mock; Route.lua rotates needles.
-- 0.2.1 (P0 UX fix): window controls live on layers.chromeControls, which is
-- NEVER hidden by mode switches (Full / Less / Compass / minimized), sits above
-- all content (frame level), and is anchored inside art TOPRIGHT.

local PAD = 24
NS.PAD = PAD

-- Sizes leave a ~32px top strip in every mode for the persistent controls.
local ART = {
  full = { w = 400, h = 460 },
  less = { w = 440, h = 128 },
  compass = { w = 240, h = 264 },
  minimized = { w = 240, h = 40 },
}

local CTRL_H = 22
local CTRL_GAP = 3
local CTRL_CLOSE_GAP = 8 -- extra space so Close is not hit by accident
local CTRL_INSET = 10
local CTRL_LEVEL = 20 -- above every content layer
local W_MODE, W_EDIT, W_MIN, W_EXPAND, W_CLOSE, W_GRIP = 60, 36, 36, 56, 22, 44

local MODE_LABEL = { full = "Full", less = "Less", compass = "Compass" }
NS.MODE_LABEL = MODE_LABEL

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
  -- White solid base; color via SetVertexColor so re-themes always stick (see Themes.lua).
  t:SetColorTexture(1, 1, 1, 1)
  t._qgThemeWhite = true
  t:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
  f.tex = t
  return f
end

-- Tooltip: getTip(self) returns title, line (line optional).
local function ShowTip(self)
  if not GameTooltip or not self.getTip then return end
  local title, line = self.getTip(self)
  if not title then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:SetText(title, 1, 0.85, 0.4)
  if line then GameTooltip:AddLine(line, 0.95, 0.93, 0.88, true) end
  GameTooltip:Show()
end

local function HideTip()
  if GameTooltip then GameTooltip:Hide() end
end

-- Labeled control chip: thin chromeHi border, dark panel fill, readable text.
local function ChipButton(parent, label, w, h, getTip)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 28, h or CTRL_H)
  b.border = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  b.border:SetAllPoints()
  b.border:SetColorTexture(1, 1, 1, 1)
  b.border._qgThemeWhite = true
  b.border:SetVertexColor(0.90, 0.78, 0.40, 1)
  b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
  b.bg:SetPoint("TOPLEFT", 1, -1)
  b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  b.bg:SetColorTexture(1, 1, 1, 1)
  b.bg._qgThemeWhite = true
  b.bg:SetVertexColor(0.18, 0.12, 0.07, 1)
  b.text = FS(b, nil, 11, "OUTLINE")
  b.text:SetJustifyH("CENTER")
  b.text:SetPoint("CENTER", 0, 0)
  b.text:SetText(label or "")
  b.getTip = getTip
  b:SetScript("OnEnter", function(self)
    NS.SetVertexColor(self.bg, NS.GetTheme().chrome)
    ShowTip(self)
  end)
  b:SetScript("OnLeave", function(self)
    local th = NS.GetTheme()
    NS.SetVertexColor(self.bg, th.panel, 1)
    HideTip()
  end)
  return b
end

local function CurrentMode()
  local m = NS.db and NS.db.mode
  if m and MODE_LABEL[m] then return m end
  return "full"
end

local function NextModeLabel(step)
  local modes = NS.MODES or { "full", "less", "compass" }
  local cur = CurrentMode()
  local i, n = 1, 1
  for n = 1, #modes do
    if modes[n] == cur then i = n end
  end
  i = i + (step or 1)
  if i > #modes then i = 1 end
  if i < 1 then i = #modes end
  return MODE_LABEL[modes[i]] or "Full"
end

-- Drag helpers shared by root, title, Move grip, and minimized bar.
local function StartHUDDrag()
  local root = NS.root
  if not root then return end
  if NS.db and NS.db.locked then return end
  root.isDragging = true
  root:StartMoving()
end

local function StopHUDDrag()
  local root = NS.root
  if not root or not root.isDragging then return end
  root.isDragging = nil
  root:StopMovingOrSizing()
  if NS.db then
    local p, _, rp, x, y = root:GetPoint(1)
    NS.db.point = p
    NS.db.relativePoint = rp
    NS.db.xOfs = x
    NS.db.yOfs = y
  end
end
NS.StartHUDDrag = StartHUDDrag
NS.StopHUDDrag = StopHUDDrag

local function MoveTip()
  if NS.db and NS.db.locked then
    return "Locked", "Position locked. Type /qg lock to unlock, then drag to move."
  end
  return "Move", "Drag to move (lock/unlock with /qg lock)."
end

local function MakeDraggable(f)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() StartHUDDrag() end)
  f:SetScript("OnDragStop", function() StopHUDDrag() end)
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
    s.bg:SetColorTexture(1, 1, 1, 1)
    s.bg._qgThemeWhite = true
    s.bg:SetVertexColor(0.15, 0.12, 0.08, 0.9)
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetAllPoints()
    s.fill:SetColorTexture(1, 1, 1, 1)
    s.fill._qgThemeWhite = true
    s.fill:SetVertexColor(0.85, 0.65, 0.2, 1)
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
  root:SetClampedToScreen(true) -- resizes / drags never push controls off-screen
  root:SetFrameStrata("MEDIUM")
  -- Root has NO opaque background — transparent padding outside art.
  NS.root = root

  root:SetScript("OnDragStart", function() StartHUDDrag() end)
  root:SetScript("OnDragStop", function() StopHUDDrag() end)

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
  emblem.bg:SetColorTexture(1, 1, 1, 1)
  emblem.bg._qgThemeWhite = true
  emblem.bg:SetVertexColor(0.72, 0.55, 0.22, 1)
  emblem.ring = emblem:CreateTexture(nil, "BORDER")
  emblem.ring:SetPoint("TOPLEFT", 3, -3)
  emblem.ring:SetPoint("BOTTOMRIGHT", -3, 3)
  emblem.ring:SetColorTexture(1, 1, 1, 1)
  emblem.ring._qgThemeWhite = true
  emblem.ring:SetVertexColor(0.10, 0.08, 0.05, 1)
  emblem.glyph = FS(emblem, nil, 18, "OUTLINE")
  emblem.glyph:SetPoint("CENTER")
  emblem.glyph:SetText("!")
  layers.emblem = emblem

  -- Title (header drag zone when unlocked; sits below the control strip)
  local title = CreateFrame("Frame", nil, art)
  title:SetSize(200, 24)
  title:SetPoint("TOP", art, "TOP", 0, -36)
  title.text = FS(title, nil, 18, "OUTLINE")
  title.text:SetJustifyH("CENTER")
  title.text:SetPoint("CENTER")
  title.text:SetText("QuestGrind")
  MakeDraggable(title)
  title.getTip = MoveTip
  title:SetScript("OnEnter", ShowTip)
  title:SetScript("OnLeave", HideTip)
  layers.title = title

  -- ===== Persistent control chrome (never hidden by mode switches) =====
  local chromeControls = CreateFrame("Frame", nil, art)
  chromeControls:SetFrameLevel(art:GetFrameLevel() + CTRL_LEVEL)
  chromeControls:SetSize(W_MODE + W_EDIT + W_MIN + W_CLOSE + CTRL_GAP * 2 + CTRL_CLOSE_GAP, CTRL_H)
  chromeControls:SetPoint("TOPRIGHT", art, "TOPRIGHT", -CTRL_INSET, -CTRL_INSET)
  layers.chromeControls = chromeControls

  local ctrlLevel = chromeControls:GetFrameLevel() + 1

  local btnClose = ChipButton(chromeControls, "X", W_CLOSE, CTRL_H, function()
    return "Close", "Hide the HUD. Bring it back with /qg show."
  end)
  btnClose:SetFrameLevel(ctrlLevel)
  btnClose:SetPoint("RIGHT", chromeControls, "RIGHT", 0, 0)
  btnClose:SetScript("OnClick", function() NS.HideHUD() end)
  layers.btnClose = btnClose
  chromeControls.btnClose = btnClose

  local btnMinimize = ChipButton(chromeControls, "Min", W_MIN, CTRL_H, function()
    if NS.db and NS.db.minimized then
      return "Expand", "Restore the full QuestGrind HUD."
    end
    return "Minimize", "Collapse to a small bar. Click Expand (or the bar) to restore."
  end)
  btnMinimize:SetFrameLevel(ctrlLevel)
  btnMinimize:SetPoint("RIGHT", btnClose, "LEFT", -CTRL_CLOSE_GAP, 0)
  btnMinimize:SetScript("OnClick", function() NS.ToggleMinimize() end)
  layers.btnMinimize = btnMinimize
  chromeControls.btnMinimize = btnMinimize

  local btnEdit = ChipButton(chromeControls, "Edit", W_EDIT, CTRL_H, function()
    return "Edit Mode", "Open the theme picker (themes apply to Full, Less, and Compass)."
  end)
  btnEdit:SetFrameLevel(ctrlLevel)
  btnEdit:SetPoint("RIGHT", btnMinimize, "LEFT", -CTRL_GAP, 0)
  btnEdit:SetScript("OnClick", function() NS.ToggleEditMode() end)
  layers.btnEdit = btnEdit
  chromeControls.btnEdit = btnEdit

  local btnMode = ChipButton(chromeControls, "Full", W_MODE, CTRL_H, function()
    return "Cycle view mode", "Now: " .. (MODE_LABEL[CurrentMode()] or "Full")
      .. "   Next: " .. NextModeLabel(1) .. "\nLeft-click: next  |  Right-click: previous"
  end)
  btnMode:SetFrameLevel(ctrlLevel)
  btnMode:SetPoint("RIGHT", btnEdit, "LEFT", -CTRL_GAP, 0)
  btnMode:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btnMode:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
      NS.CycleMode(-1)
    else
      NS.CycleMode(1)
    end
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then ShowTip(self) end
  end)
  layers.btnModeCycle = btnMode
  chromeControls.btnMode = btnMode

  -- Move grip: child of chromeControls (shown/hidden with it) but anchored to art TOPLEFT.
  local moveGrip = ChipButton(chromeControls, "Move", W_GRIP, CTRL_H, MoveTip)
  moveGrip:SetFrameLevel(ctrlLevel)
  moveGrip:SetPoint("TOPLEFT", art, "TOPLEFT", CTRL_INSET, -CTRL_INSET)
  -- Press-and-hold drags immediately (no drag threshold); release saves position.
  moveGrip:SetScript("OnMouseDown", function() StartHUDDrag() end)
  moveGrip:SetScript("OnMouseUp", function() StopHUDDrag() end)
  moveGrip:SetScript("OnClick", function()
    if NS.db and NS.db.locked then
      NS.Print("HUD is locked — /qg lock to unlock, then drag Move.")
    end
  end)
  layers.moveGrip = moveGrip
  chromeControls.moveGrip = moveGrip

  -- ===== FULL mode content layers =====
  local routeRow = CreateFrame("Frame", nil, art)
  routeRow:SetSize(200, 48)
  routeRow:SetPoint("TOPLEFT", art, "TOPLEFT", 20, -72)
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
  stepRow:SetSize(200, 116)
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
  stepRow.typeBadge = FS(stepRow, nil, 11, "OUTLINE")
  stepRow.typeBadge:SetPoint("LEFT", stepRow.label, "RIGHT", 8, 0)
  stepRow.typeBadge:SetText("")
  stepRow.title = FS(stepRow, nil, 15, "OUTLINE")
  stepRow.title:SetPoint("TOPLEFT", stepRow.label, "BOTTOMLEFT", 0, -2)
  stepRow.title:SetWidth(180)
  stepRow.dist = FS(stepRow, nil, 11)
  stepRow.dist:SetPoint("TOPLEFT", stepRow.title, "BOTTOMLEFT", 0, -2)
  stepRow.bearing = FS(stepRow, nil, 11)
  stepRow.bearing:SetPoint("LEFT", stepRow.dist, "RIGHT", 4, 0)
  stepRow.approx = FS(stepRow, nil, 11)
  stepRow.approx:SetPoint("LEFT", stepRow.bearing, "RIGHT", 4, 0)
  stepRow.zone = FS(stepRow, nil, 11)
  stepRow.zone:SetPoint("TOPLEFT", stepRow.dist, "BOTTOMLEFT", 0, -2)
  stepRow.rewards = FS(stepRow, nil, 11)
  stepRow.rewards:SetPoint("TOPLEFT", stepRow.zone, "BOTTOMLEFT", 0, -2)
  stepRow.rewards:SetWidth(190)
  stepRow.rewards:SetWordWrap(true)
  stepRow.rewards:SetText("")
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
  compassLarge:SetPoint("TOPRIGHT", art, "TOPRIGHT", -28, -82)
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
  statusBlock:SetSize(130, 100)
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
  statusBlock.xp = FS(statusBlock, nil, 12, "OUTLINE")
  statusBlock.xp:SetPoint("TOPLEFT", statusBlock.lastLabel, "BOTTOMLEFT", 0, -4)
  statusBlock.xp:SetWidth(124)
  statusBlock.xp:SetWordWrap(true)
  layers.statusBlock = statusBlock

  -- Divider between columns
  local divider = Solid(art, 0.72, 0.55, 0.22, 0.6)
  divider:SetSize(2, 240)
  divider:SetPoint("TOP", art, "TOP", 20, -72)
  layers.divider = divider

  -- Ask SI button (own layer). Border sits BELOW the fill (it previously
  -- drew on BORDER over the fill and swallowed the button into the chrome).
  local askButton = CreateFrame("Button", nil, art)
  askButton:SetSize(220, 40)
  askButton:SetPoint("BOTTOM", art, "BOTTOM", 0, 28)
  askButton:SetFrameLevel(art:GetFrameLevel() + 6)
  askButton.border = askButton:CreateTexture(nil, "BACKGROUND", nil, -8)
  askButton.border:SetPoint("TOPLEFT", -2, 2)
  askButton.border:SetPoint("BOTTOMRIGHT", 2, -2)
  askButton.border:SetColorTexture(1, 1, 1, 1)
  askButton.border._qgThemeWhite = true
  askButton.border:SetVertexColor(0.72, 0.55, 0.22, 1)
  askButton.bg = askButton:CreateTexture(nil, "BACKGROUND", nil, 1)
  askButton.bg:SetAllPoints()
  askButton.bg:SetColorTexture(1, 1, 1, 1)
  askButton.bg._qgThemeWhite = true
  askButton.bg:SetVertexColor(0.85, 0.65, 0.20, 1)
  askButton.text = FS(askButton, nil, 16, "OUTLINE")
  askButton.text:SetJustifyH("CENTER")
  askButton.text:SetPoint("CENTER")
  askButton.text:SetText("Ask SI")
  askButton.getTip = function()
    return "Ask SI", "Ask a question about your current quest (stub until P2). Also /qg ask."
  end
  askButton:SetScript("OnEnter", ShowTip)
  askButton:SetScript("OnLeave", HideTip)
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
  lessCompass:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 16, 14)
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
  lessTitle:SetSize(250, 36)
  lessTitle:SetPoint("TOPLEFT", lessCompass, "TOPRIGHT", 12, -4)
  lessTitle.text = FS(lessTitle, nil, 15, "OUTLINE")
  lessTitle.text:SetPoint("TOPLEFT")
  lessTitle.text:SetWidth(240)
  lessTitle.sub = FS(lessTitle, nil, 11)
  lessTitle.sub:SetPoint("TOPLEFT", lessTitle.text, "BOTTOMLEFT", 0, -1)
  lessTitle.sub:SetWidth(240)
  lessTitle.sub:SetText("")
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
  modeChrome:SetSize(56, 56)
  modeChrome:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -12, 12)
  modeChrome.bg = Solid(modeChrome, 0.72, 0.55, 0.22, 1)
  modeChrome.bg:SetAllPoints()
  modeChrome.inner = Solid(modeChrome, 0.18, 0.12, 0.07, 0.96)
  modeChrome.inner:SetPoint("TOPLEFT", 3, -3)
  modeChrome.inner:SetPoint("BOTTOMRIGHT", -3, 3)
  modeChrome.label = FS(modeChrome, nil, 12, "OUTLINE")
  modeChrome.label:SetJustifyH("CENTER")
  modeChrome.label:SetPoint("CENTER", 0, 8)
  modeChrome.chevron = FS(modeChrome, nil, 14, "OUTLINE")
  modeChrome.chevron:SetPoint("CENTER", 0, -10)
  modeChrome.chevron:SetText("v")
  -- Secondary mode control (Less only). Primary is chromeControls.btnMode.
  modeChrome:EnableMouse(true)
  modeChrome:SetScript("OnMouseUp", function() NS.CycleMode(1) end)
  modeChrome.getTip = function()
    return "Cycle view mode", "Next: " .. NextModeLabel(1)
  end
  modeChrome:SetScript("OnEnter", ShowTip)
  modeChrome:SetScript("OnLeave", HideTip)
  layers.modeChrome = modeChrome

  -- ===== COMPASS mode layers =====
  local compassOnly = CreateFrame("Frame", nil, art)
  compassOnly:SetSize(160, 160)
  compassOnly:SetPoint("CENTER", art, "CENTER", 0, -6)
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
  compassCrest:SetPoint("TOP", art, "TOP", 0, 6)
  layers.compassCrest = compassCrest

  -- Minimized restore chip (click = Expand; drag = move when unlocked).
  -- The Expand + Close buttons on chromeControls stay visible next to it.
  local miniBar = CreateFrame("Button", nil, art)
  miniBar:SetSize(130, 26)
  miniBar:SetPoint("LEFT", art, "LEFT", 8, 0)
  miniBar:SetFrameLevel(art:GetFrameLevel() + 15)
  miniBar.bg = miniBar:CreateTexture(nil, "BACKGROUND")
  miniBar.bg:SetAllPoints()
  miniBar.bg:SetColorTexture(1, 1, 1, 1)
  miniBar.bg._qgThemeWhite = true
  miniBar.bg:SetVertexColor(0.72, 0.55, 0.22, 1)
  miniBar.text = FS(miniBar, nil, 12, "OUTLINE")
  miniBar.text:SetJustifyH("CENTER")
  miniBar.text:SetPoint("CENTER")
  miniBar.text:SetText("QuestGrind")
  miniBar:RegisterForDrag("LeftButton")
  miniBar:SetScript("OnDragStart", function() StartHUDDrag() end)
  miniBar:SetScript("OnDragStop", function() StopHUDDrag() end)
  miniBar:SetScript("OnClick", function() NS.ToggleMinimize() end)
  miniBar.getTip = function()
    return "QuestGrind (minimized)", "Click to expand. Drag to move when unlocked."
  end
  miniBar:SetScript("OnEnter", ShowTip)
  miniBar:SetScript("OnLeave", HideTip)
  miniBar:Hide()
  layers.miniBar = miniBar

  if NS.db then
    root:ClearAllPoints()
    root:SetPoint(NS.db.point or "CENTER", UIParent, NS.db.relativePoint or "CENTER", NS.db.xOfs or 0, NS.db.yOfs or 80)
    root:SetScale(NS.db.scale or 1)
  end
end

-- Window controls are NOT in these lists: they live on chromeControls,
-- which is shown in every mode by LayoutControls().
local FULL_LAYERS = {
  "routeRow", "stepRow", "trackerRow", "compassLarge", "statusBlock",
  "askButton", "divider", "bottomJewel", "emblem", "title",
}
local LESS_LAYERS = {
  "lessCompass", "lessTitle", "lessDistance", "lessProgress", "modeChrome",
}
local COMPASS_LAYERS = {
  "compassOnlyFace", "compassPlate", "compassCrest",
}
local ALWAYS = {
  "chromeOuter", "chromeInner", "cornerTL", "cornerTR", "cornerBL", "cornerBR",
}
NS.FULL_LAYERS = FULL_LAYERS
NS.LESS_LAYERS = LESS_LAYERS
NS.COMPASS_LAYERS = COMPASS_LAYERS

-- Never hidden by HideAllContent (chrome + persistent controls).
local PERSIST = {
  art = true,
  chromeOuter = true, chromeInner = true,
  cornerTL = true, cornerTR = true, cornerBL = true, cornerBR = true,
  chromeControls = true,
  btnModeCycle = true, btnEdit = true, btnMinimize = true, btnClose = true,
  moveGrip = true,
}

local function HideAllContent()
  local name, frame
  for name, frame in pairs(layers) do
    if not PERSIST[name] then
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
  layers.art:SetSize(a.w, a.h)
  NS.root:SetSize(a.w + PAD * 2, a.h + PAD * 2)
  -- Re-anchor chrome inner inset
  layers.chromeInner:ClearAllPoints()
  layers.chromeInner:SetPoint("TOPLEFT", layers.art, "TOPLEFT", 8, -8)
  layers.chromeInner:SetPoint("BOTTOMRIGHT", layers.art, "BOTTOMRIGHT", -8, 8)
end

local function PaintGrip()
  local grip = layers.moveGrip
  if not grip then return end
  local th = NS.GetTheme()
  if NS.db and NS.db.locked then
    grip.text:SetText("Locked")
    NS.SetVertexColor(grip.text, th.muted)
  else
    grip.text:SetText("Move")
    NS.SetVertexColor(grip.text, th.text)
  end
end

--- Position + label the persistent controls. Always leaves the strip visible.
local function LayoutControls(minimized)
  local cc = layers.chromeControls
  if not cc then return end
  local art = layers.art
  local close, minb, edit, modeb, grip = cc.btnClose, cc.btnMinimize, cc.btnEdit, cc.btnMode, cc.moveGrip

  cc:ClearAllPoints()
  close:ClearAllPoints()
  close:SetPoint("RIGHT", cc, "RIGHT", 0, 0)
  minb:ClearAllPoints()
  minb:SetPoint("RIGHT", close, "LEFT", -CTRL_CLOSE_GAP, 0)

  if minimized then
    minb.text:SetText("Expand")
    minb:SetWidth(W_EXPAND)
    edit:Hide()
    modeb:Hide()
    grip:Hide()
    cc:SetSize(W_EXPAND + CTRL_CLOSE_GAP + W_CLOSE, CTRL_H)
    cc:SetPoint("RIGHT", art, "RIGHT", -8, 0)
  else
    minb.text:SetText("Min")
    minb:SetWidth(W_MIN)
    edit:ClearAllPoints()
    edit:SetPoint("RIGHT", minb, "LEFT", -CTRL_GAP, 0)
    modeb:ClearAllPoints()
    modeb:SetPoint("RIGHT", edit, "LEFT", -CTRL_GAP, 0)
    modeb.text:SetText(MODE_LABEL[CurrentMode()] or "Full")
    grip:ClearAllPoints()
    grip:SetPoint("TOPLEFT", art, "TOPLEFT", CTRL_INSET, -CTRL_INSET)
    edit:Show()
    modeb:Show()
    grip:Show()
    cc:SetSize(W_MODE + W_EDIT + W_MIN + W_CLOSE + CTRL_GAP * 2 + CTRL_CLOSE_GAP, CTRL_H)
    cc:SetPoint("TOPRIGHT", art, "TOPRIGHT", -CTRL_INSET, -CTRL_INSET)
  end
  close:Show()
  minb:Show()
  cc:Show()
  PaintGrip()
end

--- Single layout pass for every state. Compass / Less / minimized never hide
--- chromeControls and never Hide() the root.
local function ApplyLayout()
  if not NS.root or not layers.art then return end
  local minimized = NS.db and NS.db.minimized
  local mode = CurrentMode()
  if NS.db and NS.db.mode ~= mode then NS.db.mode = mode end

  HideAllContent()
  ShowList(ALWAYS)
  if minimized then
    layers.miniBar:Show()
    ResizeForMode("minimized")
  else
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
  end
  LayoutControls(minimized)

  if not minimized then
    if NS.Refresh then
      NS.Refresh()
    elseif NS.RefreshMock then
      NS.RefreshMock()
    end
  end
  NS.ApplyTheme()
end
NS.ApplyLayout = ApplyLayout

function NS.ApplyMode()
  ApplyLayout()
end

function NS.ApplyMinimize()
  ApplyLayout()
end

function NS.ApplyLock()
  -- Drag gated in StartHUDDrag via NS.db.locked; grip label reflects state.
  if NS.root then PaintGrip() end
end

function NS.ApplyTheme()
  if not NS.root then return end
  local th = NS.GetTheme(NS.db and NS.db.theme)
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
    if b.border then set(b.border, th.chromeHi) end
    set(b.bg, th.panel, 1)
    set(b.text, th.text)
  end
  paintBtn(layers.btnClose)
  paintBtn(layers.btnMinimize)
  paintBtn(layers.btnEdit)
  paintBtn(layers.btnModeCycle)
  paintBtn(layers.moveGrip)
  PaintGrip()

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
    if layers.stepRow.typeBadge then
      local qtype = NS.liveRoute and NS.liveRoute.questType
      if qtype == "Dungeon" then
        set(layers.stepRow.typeBadge, th.accent)
      else
        set(layers.stepRow.typeBadge, th.statusOk)
      end
    end
    if layers.stepRow.rewards then
      set(layers.stepRow.rewards, th.statusXp)
    end
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
  if layers.lessTitle then
    set(layers.lessTitle.text, th.text)
    if layers.lessTitle.sub then
      local qtype = NS.liveRoute and NS.liveRoute.questType
      if qtype == "Dungeon" then
        set(layers.lessTitle.sub, th.accent)
      else
        set(layers.lessTitle.sub, th.muted)
      end
    end
  end
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

-- Live with no objective coords must not stay blank or stuck on mock distance.
local function CompassDistLine(m)
  if not m then return "?" end
  local step = m.step or {}
  if m.source == "live" and not m.hasCoords then
    local zone = step.zone
    if type(zone) ~= "string" or zone == "" then zone = "?" end
    return zone .. " · ?"
  end
  return step.distance or "?"
end

local function LiveSubtitle(m)
  if not m or m.source ~= "live" then return "" end
  local qtype = m.questTypeLabel or m.questType or ""
  local rewards = m.rewardsText or ""
  if qtype ~= "" and rewards ~= "" then return qtype .. " · " .. rewards end
  if qtype ~= "" then return qtype end
  return rewards
end

local function PaintQuestMeta(m)
  local th = NS.GetTheme()
  local set = NS.SetVertexColor
  local live = m and m.source == "live"
  local qtype = live and (m.questTypeLabel or m.questType or "") or ""
  local rewards = live and (m.rewardsText or "") or ""
  if layers.stepRow and layers.stepRow.typeBadge then
    layers.stepRow.typeBadge:SetText(qtype)
    if qtype == "Dungeon" then
      set(layers.stepRow.typeBadge, th.accent)
    else
      set(layers.stepRow.typeBadge, th.statusOk)
    end
  end
  if layers.stepRow and layers.stepRow.rewards then
    layers.stepRow.rewards:SetText(rewards)
    set(layers.stepRow.rewards, th.statusXp)
  end
  if layers.lessTitle and layers.lessTitle.sub then
    layers.lessTitle.sub:SetText(LiveSubtitle(m))
    if qtype == "Dungeon" then
      set(layers.lessTitle.sub, th.accent)
    else
      set(layers.lessTitle.sub, th.muted)
    end
  end
end

local function PaintNeedles(m)
  if not m or not NS.UpdateCompassNeedles then return end
  if m.hasCoords and m.bearingDeg ~= nil then
    NS.UpdateCompassNeedles(m.bearingDeg)
  elseif m.source == "live" then
    NS.UpdateCompassNeedles(0)
  elseif m.bearingDeg ~= nil then
    NS.UpdateCompassNeedles(m.bearingDeg)
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
  PaintQuestMeta(m)

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
    layers.compassOnlyFace.dist:SetText(CompassDistLine(m))
  end

  PaintNeedles(m)
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
    layers.compassOnlyFace.dist:SetText(CompassDistLine(m))
  end
  PaintNeedles(m)
end
