-- Small widget kit built from plain stock frame types (Frame, Button, ScrollFrame, Slider, Texture, FontString).
-- No templates that touch Blizzard secure code, no hooks. Everything reads its look from NS.theme (see Theme.lua).
local _, NS = ...

local UI = {}
NS.UI = UI

function UI.Text(parent, layer, size, colorKey, justify)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  NS.SetFont(fs, size, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
  if justify then fs:SetJustifyH(justify) end
  if colorKey then
    NS.OnSkin(function() fs:SetTextColor(NS.Color(colorKey)) end)
  end
  return fs
end

-- Three-slice strip: two caps (scaled to the strip height) and a stretched middle.
-- Flat pieces (class themes): the middle carries the gradient, the caps shrink to 1px side borders and
-- two extra 1px lines (made on first use) draw the top and bottom border.
function UI.ThreeSlice(owner, prefix, h, layer, sub)
  local s = { prefix = prefix, h = h, shown = true }
  s.l = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  s.m = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  s.r = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  function s:Edges(bc)
    if not self.bt then
      self.bt = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
      self.bt:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
      self.bt:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
      self.bt:SetHeight(1)
      self.bb = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
      self.bb:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
      self.bb:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
      self.bb:SetHeight(1)
    end
    self.edgeOn = bc and true or false
    if bc then
      NS.PaintFlat(self.bt, bc) NS.PaintFlat(self.bb, bc)
      NS.PaintFlat(self.l, bc) NS.PaintFlat(self.r, bc)
    end
    if bc and self.shown then self.bt:Show() self.bb:Show() else self.bt:Hide() self.bb:Hide() end
  end
  function s:Apply(newPrefix)
    if newPrefix then self.prefix = newPrefix end
    local p = self.prefix
    NS.SetPiece(self.l, p .. "_l")
    NS.SetPiece(self.m, p .. "_m")
    NS.SetPiece(self.r, p .. "_r")
    local spec = NS.FlatSpec(p .. "_m")
    local lw, rw
    if spec then
      lw, rw = 1, 1
      self:Edges(spec.border)
    else
      local pw, ph = NS.PieceSize(p .. "_l")
      local qw, qh = NS.PieceSize(p .. "_r")
      lw, rw = pw * self.h / ph, qw * self.h / qh
      if self.bt then self:Edges(nil) end
    end
    self.l:ClearAllPoints()
    self.l:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    self.l:SetSize(lw, self.h)
    self.r:ClearAllPoints()
    self.r:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
    self.r:SetSize(rw, self.h)
    self.m:ClearAllPoints()
    self.m:SetPoint("TOPLEFT", self.l, "TOPRIGHT", 0, 0)
    self.m:SetPoint("BOTTOMRIGHT", self.r, "BOTTOMLEFT", 0, 0)
  end
  function s:SetBlend(mode)
    self.l:SetBlendMode(mode) self.m:SetBlendMode(mode) self.r:SetBlendMode(mode)
  end
  function s:SetAlpha(a) self.l:SetAlpha(a) self.m:SetAlpha(a) self.r:SetAlpha(a) end
  function s:Show()
    self.shown = true
    self.l:Show() self.m:Show() self.r:Show()
    if self.bt and self.edgeOn then self.bt:Show() self.bb:Show() end
  end
  function s:Hide()
    self.shown = false
    self.l:Hide() self.m:Hide() self.r:Hide()
    if self.bt then self.bt:Hide() self.bb:Hide() end
  end
  NS.OnSkin(function() s:Apply() end)
  return s
end

-- Nine-slice border (no centre): corner pieces t x t, edges stretched between them.
-- Flat pieces (class themes): a 1px line in the theme's border colour (or nothing when it has none).
local NINE = { "tl", "tr", "bl", "br", "t", "b", "l", "r" }
function UI.NineSlice(owner, prefix, t, layer, sub)
  local n = { prefix = prefix, size = t }
  for _, k in ipairs(NINE) do
    n[k] = owner:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
  end
  function n:Apply()
    local p, size = self.prefix, self.size
    local spec = NS.FlatSpec(p .. "_t")
    -- 0.5.1 WoW theme: a stock backdrop edge file (dialog / tooltip border), drawn the way the game's Backdrop does
    local ed = not spec and NS.Stock and NS.Stock.Spec(p)
    self.edgeOn = ed and ed.edge and true or false
    if ed and ed.edge then
      size = ed.size or size
      local w, h = NS.Num(owner:GetWidth()) or 0, NS.Num(owner:GetHeight()) or 0
      -- small boxes get a thinner edge (corners never overlap)
      if w > 0 and h > 0 then size = math.max(1, math.min(size, math.floor((math.min(w, h) - 2) / 2))) end
      local cs, ce = 0.0625, 0.9375
      local rx = w > 0 and math.max(0, w / size - 2 - cs) or 1
      local ry = h > 0 and math.max(0, h / size - 2 - cs) or 1
      local TC = {
        tl = { 0.5078125, cs, 0.5078125, ce, 0.6171875, cs, 0.6171875, ce },
        tr = { 0.6328125, cs, 0.6328125, ce, 0.7421875, cs, 0.7421875, ce },
        bl = { 0.7578125, cs, 0.7578125, ce, 0.8671875, cs, 0.8671875, ce },
        br = { 0.8828125, cs, 0.8828125, ce, 0.9921875, cs, 0.9921875, ce },
        t = { 0.2578125, rx, 0.3671875, rx, 0.2578125, cs, 0.3671875, cs },
        b = { 0.3828125, rx, 0.4921875, rx, 0.3828125, cs, 0.4921875, cs },
        l = { 0.0078125, cs, 0.0078125, ry, 0.1171875, cs, 0.1171875, ry },
        r = { 0.1328125, cs, 0.1328125, ry, 0.2421875, cs, 0.2421875, ry },
      }
      for _, k in ipairs(NINE) do
        local tex = self[k]
        NS.Unflat(tex)
        NS.Stock.Reset(tex)
        tex:SetTexture(ed.file, "REPEAT", "REPEAT")
        tex:SetTexCoord(unpack(TC[k]))
        local vc = ed.vc or { 1, 1, 1, 1 }
        tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
      end
    elseif spec then
      size = 1
      local bc = spec.border or { 0, 0, 0, 0 }
      for _, k in ipairs(NINE) do NS.PaintFlat(self[k], bc) end
    else
      for _, k in ipairs(NINE) do NS.SetPiece(self[k], p .. "_" .. k) end
    end
    self.tl:ClearAllPoints() self.tl:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0) self.tl:SetSize(size, size)
    self.tr:ClearAllPoints() self.tr:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0) self.tr:SetSize(size, size)
    self.bl:ClearAllPoints() self.bl:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0) self.bl:SetSize(size, size)
    self.br:ClearAllPoints() self.br:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0) self.br:SetSize(size, size)
    self.t:ClearAllPoints() self.t:SetPoint("TOPLEFT", self.tl, "TOPRIGHT", 0, 0) self.t:SetPoint("BOTTOMRIGHT", self.tr, "BOTTOMLEFT", 0, 0)
    self.b:ClearAllPoints() self.b:SetPoint("TOPLEFT", self.bl, "TOPRIGHT", 0, 0) self.b:SetPoint("BOTTOMRIGHT", self.br, "BOTTOMLEFT", 0, 0)
    self.l:ClearAllPoints() self.l:SetPoint("TOPLEFT", self.tl, "BOTTOMLEFT", 0, 0) self.l:SetPoint("BOTTOMRIGHT", self.bl, "TOPRIGHT", 0, 0)
    self.r:ClearAllPoints() self.r:SetPoint("TOPLEFT", self.tr, "BOTTOMLEFT", 0, 0) self.r:SetPoint("BOTTOMRIGHT", self.br, "TOPRIGHT", 0, 0)
  end
  function n:Show() for _, k in ipairs(NINE) do self[k]:Show() end end
  function n:Hide() for _, k in ipairs(NINE) do self[k]:Hide() end end
  NS.OnSkin(function() n:Apply() end)
  -- a stock edge tiles by the frame's size, so redraw it when the frame is resized
  if owner.HookScript then owner:HookScript("OnSizeChanged", function() if n.edgeOn then n:Apply() end end) end
  return n
end

-- Dark slate fill (stretched), optionally shaded darker. Class themes: the class texture, tinted per area.
-- 0.5.1: "detailShade" is the quest-detail panel. The WoW theme draws it on the stock QuestBG parchment (stockMedia.detail);
-- every other theme, and the WoW theme without that texture, draws it like a list panel. owner.parch tells the caller
-- which one was drawn, so it can pick dark ink for parchment.
local SURFACE_OF = { slateShade = "shell", railShade = "rail", listShade = "list", detailShade = "detail" }
local function SlateArea(shadeKey)
  local area = SURFACE_OF[shadeKey or "slateShade"] or "shell"
  if area == "detail" and not (NS.theme.stockMedia and NS.theme.stockMedia.detail) then area = "list" end
  return area
end
local function SlateShade(shadeKey)
  if shadeKey == "detailShade" then shadeKey = "listShade" end
  return NS.Metric(shadeKey or "slateShade")
end
function UI.Slate(owner, shadeKey, layer, sub)
  local tex = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  tex:SetAllPoints(owner)
  NS.OnSkin(function()
    local area = SlateArea(shadeKey)
    owner.parch = false
    if NS.ApplySurface(tex, area == "detail" and "list" or area) then return end
    local stock = NS.Stock.Media(tex, area, "slate", SlateShade(shadeKey))
    owner.parch = (area == "detail") and stock or false
  end)
  if owner.HookScript then
    owner:HookScript("OnSizeChanged", function()
      local area = SlateArea(shadeKey)
      if NS.theme.stockMedia and not NS.theme.surface then NS.Stock.Media(tex, area, "slate", SlateShade(shadeKey)) end
    end)
  end
  return tex
end

-- Dark list/detail panel with the pane border. shadeKey "detailShade" (0.5.1) = the quest-detail panel.
function UI.Panel(parent, w, h, shadeKey)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  UI.Slate(f, shadeKey or "listShade", "BACKGROUND", 0)
  f.border = UI.NineSlice(f, "pane", NS.theme.m.listBorder, "BORDER", 1)
  return f
end

-- Light warm panel on parchment (previewer .dm-panel): translucent wash + pane border.
-- Use for Fishing skill strip so ink colours stay readable (not slate-grey on slate).
function UI.PaperPanel(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  bg:SetAllPoints(f)
  NS.OnSkin(function()
    -- approximates --dm-panel-bg (WoW: warm wash over parchment; class themes give their own)
    local c = NS.theme.panelWash or { 0.95, 0.90, 0.65, 0.28 }
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
  end)
  f.border = UI.NineSlice(f, "pane", NS.theme.m.listBorder, "BORDER", 1)
  return f
end

-- Parchment page with the pane border (class themes: the tinted class texture).
-- 0.5.1.1: the WoW theme (pageDark) draws the page on the stock rock and falls back to the dark slate, never to a
-- light parchment under its light page ink. The texture is anchored to both corners and re-tiled on resize, so it
-- always fills the page.
local function PageFallback()
  return NS.theme.pageDark and "slate" or "parchment"
end
function UI.Page(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local parch = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  parch:SetAllPoints(f)
  NS.OnSkin(function()
    if NS.ApplySurface(parch, "page") then return end
    NS.Stock.Media(parch, "page", PageFallback(), NS.theme.pageDark and NS.Metric("slateShade") or 1)
  end)
  if f.HookScript then
    f:HookScript("OnSizeChanged", function()
      if NS.theme.stockMedia and not NS.theme.surface then NS.Stock.Media(parch, "page", PageFallback(), NS.theme.pageDark and NS.Metric("slateShade") or 1) end
    end)
  end
  f.border = UI.NineSlice(f, "pane", NS.theme.m.pageBorder, "BORDER", 1)
  return f
end


-- Hover look (0.4.4) for every labelled button and list row. It is drawn UNDER the label (ARTWORK sublevel 7, above
-- the button art), never on the HIGHLIGHT layer (that one draws over the text and washed labels out on light themes):
-- a soft theme tint plus a 1px theme-coloured edge. Shown on enter, hidden on leave and when the button is disabled.
-- 0.5.1.2: b.hoverSoft (true or a function) = a faint dark tint only, no edge (item rows on the parchment); a button with
-- the stock WoW behaviour (b.stockOn) draws no tint at all: its stock Highlight texture does the hover.
function UI.Hover(b, onEnter, onLeave)
  local h = {}
  for i = 1, 5 do h[i] = b:CreateTexture(nil, "ARTWORK", nil, 7) end
  h[1]:SetAllPoints(b)
  h[2]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) h[2]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0) h[2]:SetHeight(1)
  h[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0) h[3]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0) h[3]:SetHeight(1)
  h[4]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) h[4]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0) h[4]:SetWidth(1)
  h[5]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0) h[5]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0) h[5]:SetWidth(1)
  local function show(on)
    b._over = on and true or nil
    if b.stockOn then
      for i = 1, 5 do h[i]:Hide() end
      if b.StockPaint then b:StockPaint() end
      return
    end
    local soft = b.hoverSoft
    if type(soft) == "function" then soft = soft(b) end
    if on then
      if soft then
        h[1]:SetColorTexture(0.25, 0.12, 0, 0.12)
      else
        -- tint AWAY from the label ink (darker behind light labels, lighter behind dark ones), so hover only adds contrast
        local k = b.hoverInk or "listInk"
        if type(k) == "function" then k = k(b) end
        local ink = NS.theme.colors[k]
        if ink and NS.Lum(ink) > 0.3 then h[1]:SetColorTexture(0, 0, 0, 0.16) else h[1]:SetColorTexture(1, 1, 1, 0.18) end
      end
    end
    for i = 1, 5 do if on and (i == 1 or not soft) then h[i]:Show() else h[i]:Hide() end end
  end
  NS.OnSkin(function()
    local e = NS.theme.colors.hoverEdge or { 1, 0.82, 0.30, 0.75 }
    for i = 2, 5 do h[i]:SetColorTexture(e[1], e[2], e[3], e[4] or 0.75) end
  end)
  show(false)
  b:SetScript("OnEnter", function(self)
    if not (self.IsEnabled and self:IsEnabled() == false) then show(true) end
    if onEnter then onEnter(self) end
  end)
  b:SetScript("OnLeave", function(self)
    show(false)
    if onLeave then onLeave(self) end
  end)
  b:SetScript("OnDisable", function() show(false) end)
  b.hoverTex = h
  return h
end

-- 0.5.1.2 stock button feel (WoW theme). Every WoW-theme button behaves like the game's own UIPanelButtonTemplate:
-- Normal / Pushed / Disabled faces from Interface\Buttons\UI-Panel-Button-Up / -Down / -Disabled (texcoords
-- 0..0.625 x 0..0.6875, drawn as the template's left / middle / right slices), the -Highlight texture over the whole
-- button (same texcoords, ADD blend) on hover, the label 1px down-right while the mouse is held, the stock click
-- sound, gold normal / white highlight / grey disabled font colours (GameFontNormal / GameFontHighlight /
-- GameFontDisable). Section tabs behave like CharacterFrameTabButtonTemplate: the selected tab raised (ActiveTab) with
-- a white label and no hover, the others darker (InActiveTab) with a gold label and UI-Character-Tab-Highlight on
-- hover; no press offset. The buttons are built by hand rather than created from the templates because the window
-- switches theme live: a template button cannot drop its art again for the class themes. /dm artprobe still reports
-- the templates. Any of the files missing (or a class theme): the button keeps Dark Matter's own art and feel.
local STOCK_FONT = { normal = { 1, 0.82, 0 }, highlight = { 1, 1, 1 }, disabled = { 0.8, 0.8, 0.8 } }
-- (disabled: GameFontDisable's grey, lifted from 0.5 to 0.8 so the label still reads 4.5:1 on the stock Disabled face)
UI.STOCK_FONT = STOCK_FONT
-- The stock click sound (SOUNDKIT where the client has it, the old sound names otherwise). kind "tab": the tab sound.
function NS.ClickSound(kind)
  if type(PlaySound) ~= "function" then return end
  local sk = type(SOUNDKIT) == "table" and SOUNDKIT or nil
  local id
  if sk then
    if kind == "tab" then id = sk.IG_CHARACTER_INFO_TAB end
    id = id or sk.IG_MAINMENU_OPTION_CHECKBOX_ON or sk.IGMAINMENUOPTIONCHECKBOXON or sk.U_CHAT_SCROLL_BUTTON
  end
  if id then pcall(PlaySound, id) return end
  pcall(PlaySound, kind == "tab" and "igCharacterInfoTab" or "igMainMenuOptionCheckBoxOn")
end

-- opts: slice (the button's ThreeSlice), style "button" | "tab", toggle (active = held down), place(self, dx, dy)
-- (moves the label), classic(self) (repaints Dark Matter's own look), classicDown(self, on) (its own press feel).
function UI.StockFeel(b, opts)
  local style = opts.style or "button"
  b.stockStyle = style
  b.stockOn = false
  b.active = (rawget(b, "active") == true)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.stockHL = hl
  local function enabled(self) return not (self.IsEnabled and self:IsEnabled() == false) end
  function b:StockPaint()
    if not self.stockOn then return end
    local en = enabled(self)
    local col
    if style == "tab" then
      opts.slice:Apply(self.active and "ptab_a" or "ptab_i")
      col = (self.active or self._over) and STOCK_FONT.highlight or STOCK_FONT.normal
      if not en then col = STOCK_FONT.disabled end
      hl:SetAlpha((self.active or not en) and 0 or 1)
      opts.place(self, 0, 0)
    else
      local held = en and (self._pressed or (opts.toggle and self.active))
      opts.slice:Apply((not en) and "btn_grey" or (held and "btn_down" or "btn_red"))
      if not en then col = STOCK_FONT.disabled
      elseif self._over or (opts.toggle and self.active) then col = STOCK_FONT.highlight
      else col = STOCK_FONT.normal end
      hl:SetAlpha(en and 1 or 0)
      if held then opts.place(self, 1, -1) else opts.place(self, 0, 0) end
    end
    self.text:SetTextColor(col[1], col[2], col[3])
    self.text:SetShadowColor(0, 0, 0, 1)
    if opts.icon then opts.icon:SetVertexColor(col[1], col[2], col[3]) end
  end
  -- repaint on enable / disable (the client's OnEnable/OnDisable scripts are not relied on)
  for _, k in ipairs({ "Enable", "Disable" }) do
    local orig = b[k]
    if type(orig) == "function" then
      b[k] = function(self, ...)
        local r = orig(self, ...)
        if not enabled(self) then self._pressed = nil end
        if self.stockOn then self:StockPaint() end
        return r
      end
    end
  end
  b:SetScript("OnMouseDown", function(self, button)
    if self.stockOn then
      if style ~= "tab" and enabled(self) and (button == nil or button == "LeftButton") then self._pressed = true self:StockPaint() end
    elseif opts.classicDown then opts.classicDown(self, true) end
  end)
  b:SetScript("OnMouseUp", function(self)
    if self.stockOn then
      self._pressed = nil
      self:StockPaint()
    elseif opts.classicDown then opts.classicDown(self, false) end
  end)
  b:SetScript("PostClick", function(self)
    if self.stockOn then NS.ClickSound(style) end
  end)
  NS.OnSkin(function()
    local st = NS.Stock.PanelButton()
    local on = st and true or false
    if on and style == "tab" then on = NS.Stock.TabButton() and true or false end
    b.stockOn = on
    b._pressed = nil
    if on then
      NS.Unflat(hl)
      if style == "tab" then
        local tb = NS.Stock.TabButton()
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -2)
        hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -10, 2)
        hl:SetTexture(tb.highlight)
        hl:SetTexCoord(unpack(tb.highlightTC))
      else
        hl:ClearAllPoints()
        hl:SetAllPoints(b)
        hl:SetTexture(st.highlight)
        hl:SetTexCoord(unpack(st.tc))
      end
      hl:SetBlendMode("ADD")
      hl:SetVertexColor(1, 1, 1, 1)
      if b.hoverTex then for i = 1, 5 do b.hoverTex[i]:Hide() end end
      b:StockPaint()
    else
      hl:SetTexture(nil)
      hl:SetAlpha(0)
      if b.text then b.text:SetShadowColor(0, 0, 0, 0.9) end
      if opts.icon then opts.icon:SetVertexColor(1, 1, 1, 1) end
      opts.place(b, 0, 0)
      if opts.classic then opts.classic(b) end
    end
  end)
end

-- Plain button with the three-slice art. kind: "red", "grey" or "field".
-- 0.5.1.2: the WoW theme gives "red" and "grey" buttons the stock UIPanelButtonTemplate feel (UI.StockFeel; "grey" is the
-- same stock button, it only differs in the class themes). Like every stock-feel button it shows held down while
-- b.active (the Settings theme picker).
local KIND_INK = { red = "btnInk", grey = "greyBtn", field = "gold" }  -- 0.4.4: button faces get their own ink
function UI.Button(parent, label, w, h, kind, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.kind = kind or "red"
  b.slice = UI.ThreeSlice(b, "btn_" .. b.kind, h, "ARTWORK")
  UI.Hover(b)
  b.hoverInk = KIND_INK[b.kind] or "btnInk"
  b.text = b:CreateFontString(nil, "OVERLAY")
  NS.SetFont(b.text, size or NS.theme.m.fbtnSize, "")
  b.text:SetShadowOffset(1, -1)
  b.text:SetShadowColor(0, 0, 0, 0.9)
  b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.text:SetText(label or "")
  function b:SetLook(kindName)
    self.kind = kindName
    if self.stockOn then self:StockPaint() return end
    self.slice:Apply("btn_" .. kindName)
    self.text:SetTextColor(NS.Color(KIND_INK[kindName] or "gold"))
  end
  local function place(self, dx, dy)
    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", self, "CENTER", dx, 1 + dy)
  end
  if b.kind == "field" then
    NS.OnSkin(function() b:SetLook(b.kind) end)
    b:SetScript("OnMouseDown", function(self) place(self, 1, -1) end)
    b:SetScript("OnMouseUp", function(self) place(self, 0, 0) end)
    return b
  end
  UI.StockFeel(b, {
    slice = b.slice, place = place,
    toggle = true,
    classic = function(self) self:SetLook(self.kind) end,
    classicDown = function(self, on) if on then place(self, 1, -1) else place(self, 0, 0) end end,
  })
  return b
end

-- Left-rail tab: icon + label, three-slice art, wider when active.
-- 0.5.1.2 WoW theme: the stock panel button feel (UI.StockFeel); the active tab stays held down with a white label.
function UI.RailTab(parent, label, glyphKey)
  local m = NS.theme.m
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(m.tabW, m.tabH)
  t.slice = UI.ThreeSlice(t, "rtab_i", m.tabH, "ARTWORK")
  UI.Hover(t)
  t.hoverInk = function(s) return s.active and "goldOn" or "gold" end
  t.icon = t:CreateTexture(nil, "OVERLAY")
  t.icon:SetSize(m.tabIcon, m.tabIcon)
  t.icon:SetPoint("LEFT", t, "LEFT", 12, 0)
  t.text = t:CreateFontString(nil, "OVERLAY")
  NS.SetFont(t.text, m.tabSize, "")
  t.text:SetShadowOffset(1, -1)
  t.text:SetShadowColor(0, 0, 0, 0.9)
  t.text:SetPoint("LEFT", t.icon, "RIGHT", 8, 0)
  t.text:SetText(label)
  t.glyphKey = glyphKey
  t.active = false
  local function classic(self)
    local p = self.active and "rtab_a" or "rtab_i"
    self.slice:Apply(p)
    self.text:SetTextColor(NS.Color(self.active and "goldOn" or "gold"))
    self.icon:SetVertexColor(NS.Color(self.active and "goldOn" or "gold"))
  end
  function t:SetActive(on)
    self.active = on and true or false
    local mm = NS.theme.m
    self:SetWidth(self.active and mm.tabWOn or mm.tabW)
    if self.stockOn then self:StockPaint() else classic(self) end
  end
  UI.StockFeel(t, {
    slice = t.slice, toggle = true, icon = t.icon,
    place = function(self, dx, dy)
      self.icon:ClearAllPoints()
      self.icon:SetPoint("LEFT", self, "LEFT", 12 + dx, dy)
    end,
    classic = classic,
  })
  NS.OnSkin(function()
    NS.SetPiece(t.icon, t.glyphKey)
    t:SetActive(t.active)
  end)
  return t
end

-- Section pill (like the mockup's Fishing / Adventure Guide / Achievements buttons).
-- 0.5.1.2: kind "toggle" = a filter toggle (All levels / Near my level, by zone / by fish, Catches / Statistics): in the
-- WoW theme a stock panel button, held down while active. Otherwise a section tab: in the WoW theme a stock
-- character-frame tab. The WoW theme shows no marker dot on either (class themes keep theirs).
function UI.Pill(parent, label, kind)
  local m = NS.theme.m
  local p = CreateFrame("Button", nil, parent)
  p.kind = kind or "tab"
  p.text = p:CreateFontString(nil, "OVERLAY")
  NS.SetFont(p.text, m.pillSize, "")
  p.text:SetShadowOffset(1, -1)
  p.text:SetShadowColor(0, 0, 0, 0.9)
  p.text:SetText(label)
  local tw = NS.Num(p.text:GetStringWidth()) or 60
  p:SetSize(math.floor(tw + m.pillPad * 2 + 0.5), m.pillsH)
  p.slice = UI.ThreeSlice(p, "ptab_i", m.pillsH, "ARTWORK")
  UI.Hover(p)
  p.hoverInk = function(s) return s.active and "goldOn" or "gold" end
  p.mark = p:CreateTexture(nil, "OVERLAY")
  p.mark:SetSize(11, 11)
  p.mark:SetPoint("LEFT", p, "LEFT", 9, 0)
  p.text:SetPoint("CENTER", p, "CENTER", 0, 1)
  p.active = false
  local function classic(self)
    local prefix = self.active and "ptab_a" or "ptab_i"
    self.slice:Apply(prefix)
    self.text:SetTextColor(NS.Color(self.active and "goldOn" or "gold"))
    if self.active then self.mark:Show() else self.mark:Hide() end
    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", self, "CENTER", self.active and 6 or 0, 1)
  end
  function p:SetActive(on)
    self.active = on and true or false
    if self.stockOn then self.mark:Hide() self:StockPaint() else classic(self) end
  end
  UI.StockFeel(p, {
    slice = p.slice, style = (p.kind == "toggle") and "button" or "tab", toggle = true,
    place = function(self, dx, dy)
      self.mark:Hide()
      self.text:ClearAllPoints()
      self.text:SetPoint("CENTER", self, "CENTER", dx, 1 + dy)
    end,
    classic = classic,
  })
  NS.OnSkin(function()
    NS.SetPiece(p.mark, "coin_target")
    p:SetActive(p.active)
  end)
  return p
end

-- Scroll area with the generated scrollbar art: up/down buttons, track, three-slice thumb.
-- 0.5.1.2: plus the stock groove (UI-Character-ScrollBar) instead of the solid dark track, and the stock scroll sound.
-- 0.5.1.1 WoW theme: the game's own scroll buttons at their stock 16x16 size (Up / Down when pressed / Disabled at the
-- ends / Highlight on hover) and the stock 18x24 knob, like UIPanelScrollBarTemplate; any missing file: the old art.
function UI.Scroll(parent, w, h)
  local m = NS.theme.m
  local sbw = m.sbWidth
  local S = { w = w, h = h, step = 40, contentH = 1 }
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  S.frame = f

  local sf = CreateFrame("ScrollFrame", nil, f)
  sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  sf:SetSize(w - sbw, h)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(w - sbw, 1)
  sf:SetScrollChild(content)
  S.scroll, S.content = sf, content

  local up = CreateFrame("Button", nil, f)
  up:SetSize(sbw, sbw)
  up:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  local upTex = up:CreateTexture(nil, "ARTWORK")
  upTex:SetAllPoints(up)
  local upGlow = up:CreateTexture(nil, "HIGHLIGHT")
  upGlow:SetAllPoints(up)
  upGlow:SetBlendMode("ADD")
  upGlow:SetAlpha(0.2)
  local down = CreateFrame("Button", nil, f)
  down:SetSize(sbw, sbw)
  down:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  local downTex = down:CreateTexture(nil, "ARTWORK")
  downTex:SetAllPoints(down)
  local downGlow = down:CreateTexture(nil, "HIGHLIGHT")
  downGlow:SetAllPoints(down)
  downGlow:SetBlendMode("ADD")
  downGlow:SetAlpha(0.2)

  local trackBg = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  trackBg:SetPoint("TOPLEFT", up, "BOTTOMLEFT", 0, 0)
  trackBg:SetPoint("BOTTOMRIGHT", down, "TOPRIGHT", 0, 0)
  trackBg:SetColorTexture(0.02, 0.02, 0.035, 0.85)

  -- 0.5.1.2 WoW theme: the stock groove (UI-Character-ScrollBar, like the quest log's scroll bar) behind the buttons and
  -- the knob, instead of the solid dark track. Laid out from the bar's height (top piece, stretched middle, bottom piece).
  local grooveT = f:CreateTexture(nil, "BACKGROUND", nil, 3)
  local grooveM = f:CreateTexture(nil, "BACKGROUND", nil, 3)
  local grooveB = f:CreateTexture(nil, "BACKGROUND", nil, 3)
  local grooveOn = false
  local function LayoutGroove()
    if not grooveOn then grooveT:Hide() grooveM:Hide() grooveB:Hide() return end
    local gw = sbw + 8
    local total = math.max(8, S.h + 3) -- 2px above the up button, 1px below the down button
    local bh = math.min(106, math.floor(total / 2))
    local th = math.min(256, total - bh)
    local mh = total - bh - th
    grooveT:ClearAllPoints() grooveT:SetPoint("TOP", up, "TOP", 0, 2) grooveT:SetSize(gw, th)
    grooveT:SetTexCoord(0, 0.484375, 0, th / 256)
    grooveB:ClearAllPoints() grooveB:SetPoint("BOTTOM", down, "BOTTOM", 0, -1) grooveB:SetSize(gw, bh)
    grooveB:SetTexCoord(0.515625, 1, 0.4140625 - bh / 256, 0.4140625)
    if mh > 0 then
      grooveM:ClearAllPoints()
      grooveM:SetPoint("TOP", grooveT, "BOTTOM", 0, 0) grooveM:SetSize(gw, mh)
      grooveM:SetTexCoord(0, 0.484375, 0.25, 0.75)
      grooveM:Show()
    else
      grooveM:Hide()
    end
    grooveT:Show() grooveB:Show()
  end
  S.LayoutGroove = LayoutGroove
  S.groove = { grooveT, grooveM, grooveB }


  local sb = CreateFrame("Slider", nil, f)
  sb:SetOrientation("VERTICAL")
  sb:SetPoint("TOPLEFT", up, "BOTTOMLEFT", 0, 0)
  sb:SetPoint("BOTTOMRIGHT", down, "TOPRIGHT", 0, 0)
  sb:SetMinMaxValues(0, 0)
  sb:SetValueStep(1)
  sb:SetValue(0)
  local thumb = sb:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(sbw, 40)
  sb:SetThumbTexture(thumb)
  local capT = sb:CreateTexture(nil, "OVERLAY", nil, 1)
  local capB = sb:CreateTexture(nil, "OVERLAY", nil, 1)
  S.slider, S.thumb = sb, thumb
  local capH = 8
  capT:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, 0)
  capT:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", 0, 0)
  capT:SetHeight(capH)
  capB:SetPoint("BOTTOMLEFT", thumb, "BOTTOMLEFT", 0, 0)
  capB:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)
  capB:SetHeight(capH)

  local stockUp, stockDn, stockKnob -- stock specs while the WoW theme's scroll art is in use (nil otherwise)
  local function ButtonArt(btn, tex, sp)
    if not sp then return end
    local f2 = sp.file
    if btn:IsEnabled() == false then f2 = sp.disabled elseif btn._down then f2 = sp.down end
    tex:SetTexture(f2)
    tex:SetTexCoord(unpack(sp.tc))
  end
  local function RefreshButtons()
    if not (stockUp and stockDn) then return end
    local maxScroll = math.max(0, S.contentH - S.h)
    local v = sb:GetValue() or 0
    if v > 0 then up:Enable() else up:Disable() up._down = nil end
    if v < maxScroll then down:Enable() else down:Disable() down._down = nil end
    ButtonArt(up, upTex, stockUp) ButtonArt(down, downTex, stockDn)
  end
  S.RefreshButtons = RefreshButtons
  local function Press(btn, on)
    btn._down = on or nil
    if stockUp and stockDn then ButtonArt(up, upTex, stockUp) ButtonArt(down, downTex, stockDn) end
  end
  up:SetScript("OnMouseDown", function(self) Press(self, true) end)
  up:SetScript("OnMouseUp", function(self) Press(self, false) end)
  down:SetScript("OnMouseDown", function(self) Press(self, true) end)
  down:SetScript("OnMouseUp", function(self) Press(self, false) end)

  NS.OnSkin(function()
    stockUp, stockDn = NS.Stock.ButtonStates("sb_up"), NS.Stock.ButtonStates("sb_dn")
    if not (stockUp and stockDn) then stockUp, stockDn = nil, nil end
    stockKnob = stockUp and NS.Stock.Spec("sb_thumb") or nil
    local gt, gm, gb = NS.Stock.Spec("sb_track_t"), NS.Stock.Spec("sb_track_m"), NS.Stock.Spec("sb_track_b")
    grooveOn = (stockUp and gt and gm and gb) and true or false
    if grooveOn then
      NS.Stock.Apply(grooveT, gt) NS.Stock.Apply(grooveM, gm) NS.Stock.Apply(grooveB, gb)
      trackBg:Hide()
    else
      trackBg:Show()
    end
    LayoutGroove()
    if stockUp then
      for _, pr in ipairs({ { up, upTex, upGlow, stockUp }, { down, downTex, downGlow, stockDn } }) do
        local btn, tex, glow, sp = pr[1], pr[2], pr[3], pr[4]
        NS.Unflat(tex) NS.Stock.Reset(tex)
        tex:ClearAllPoints() tex:SetPoint("CENTER", btn, "CENTER", 0, 0) tex:SetSize(sp.w, sp.h)
        tex:SetVertexColor(1, 1, 1, 1)
        NS.Unflat(glow)
        glow:ClearAllPoints() glow:SetPoint("CENTER", btn, "CENTER", 0, 0) glow:SetSize(sp.w, sp.h)
        glow:SetTexture(sp.highlight) glow:SetTexCoord(unpack(sp.tc))
        glow:SetVertexColor(1, 1, 1, 1) glow:SetBlendMode("ADD") glow:SetAlpha(1)
      end
      RefreshButtons()
    else
      for _, pr in ipairs({ { up, upTex, upGlow }, { down, downTex, downGlow } }) do
        local btn, tex, glow = pr[1], pr[2], pr[3]
        tex:ClearAllPoints() tex:SetAllPoints(btn)
        glow:ClearAllPoints() glow:SetAllPoints(btn)
        glow:SetBlendMode("ADD") glow:SetAlpha(0.2)
        btn:Enable() btn._down = nil
      end
      NS.SetPiece(upTex, "sb_up") NS.SetPiece(upGlow, "sb_up")
      NS.SetPiece(downTex, "sb_dn") NS.SetPiece(downGlow, "sb_dn")
    end
    if stockKnob then
      NS.Stock.Apply(thumb, stockKnob)
      thumb:SetSize(stockKnob.w, stockKnob.h)
      capT:SetAlpha(0) capB:SetAlpha(0)
    else
      thumb:SetWidth(sbw)
      capT:SetAlpha(1) capB:SetAlpha(1)
      NS.SetPiece(thumb, "sb_thumb_m") NS.SetPiece(capT, "sb_thumb_t") NS.SetPiece(capB, "sb_thumb_b")
    end
    if S.Update then S:Update() end
  end)

  local updating = false
  sb:SetScript("OnValueChanged", function(_, value)
    if updating then return end
    sf:SetVerticalScroll(value or 0)
    RefreshButtons()
  end)
  function S:Update()
    local maxScroll = math.max(0, self.contentH - self.h)
    updating = true
    sb:SetMinMaxValues(0, maxScroll)
    local v = sb:GetValue() or 0
    if v > maxScroll then v = maxScroll end
    sb:SetValue(v)
    updating = false
    sf:SetVerticalScroll(v)
    if maxScroll > 0 then
      local track = math.max(1, self.h - 2 * sbw)
      if stockKnob then thumb:SetHeight(stockKnob.h)
      else thumb:SetHeight(math.max(26, track * self.h / self.contentH)) end
      sb:Show()
      capT:Show() capB:Show() thumb:Show()
    else
      capT:Hide() capB:Hide() thumb:Hide()
    end
    RefreshButtons()
    LayoutGroove()
  end
  function S:SetContentHeight(ch)
    self.contentH = math.max(1, ch)
    content:SetSize(w - sbw, self.contentH)
    self:Update()
  end
  function S:ScrollBy(delta)
    local maxScroll = math.max(0, self.contentH - self.h)
    local v = (sb:GetValue() or 0) + delta
    if v < 0 then v = 0 elseif v > maxScroll then v = maxScroll end
    updating = true
    sb:SetValue(v)
    updating = false
    sf:SetVerticalScroll(v)
    RefreshButtons()
  end
  function S:ScrollTo(v) self:ScrollBy(v - (sb:GetValue() or 0)) end
  function S.GetScroll() return sb:GetValue() or 0 end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta) S:ScrollBy(-delta * S.step) end)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) S:ScrollBy(-delta * S.step) end)
  -- the stock scroll buttons click with the chat-scroll sound (UIPanelScrollUpButtonTemplate)
  local function ScrollSound()
    if stockUp and type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.U_CHAT_SCROLL_BUTTON then
      pcall(PlaySound, SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end
  end
  up:SetScript("OnClick", function() ScrollSound() S:ScrollBy(-S.step) end)
  down:SetScript("OnClick", function() ScrollSound() S:ScrollBy(S.step) end)
  S:Update()
  return S
end


-- Horizontal progress bar matching previewer .dm-bar (dark track, gold/green fill, gloss, cream label).
-- Stock ColorTexture only; Friz via NS.SetFont. Optional thin=true for share rows.
function UI.Bar(parent, w, h, thin)
  local f = CreateFrame("Frame", nil, parent)
  h = h or (thin and 12 or 20)
  f:SetSize(w, h)
  -- border rim (~ --dm-bar-border #4b4a44)
  local rim = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  rim:SetAllPoints(f)
  local track = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  track:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  local fill = f:CreateTexture(nil, "ARTWORK", nil, 0)
  fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
  fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
  fill:SetWidth(1)
  -- darker lower band to suggest the mockup gradient
  local fillDeep = f:CreateTexture(nil, "ARTWORK", nil, 1)
  fillDeep:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
  fillDeep:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
  fillDeep:SetHeight(math.max(2, math.floor(h * 0.45)))
  local gloss = f:CreateTexture(nil, "OVERLAY", nil, 0)
  gloss:SetPoint("TOPLEFT", track, "TOPLEFT", 1, 0)
  gloss:SetPoint("TOPRIGHT", track, "TOPRIGHT", -1, 0)
  gloss:SetHeight(math.max(2, math.floor(h * 0.45)))
  local label = f:CreateFontString(nil, "OVERLAY")
  NS.SetFont(label, thin and 9 or 11, "OUTLINE") -- 0.4.4: light ink + black outline, legible over fill and track
  label:SetPoint("CENTER", f, "CENTER", 0, 0)
  label:SetShadowOffset(1, -1)
  label:SetShadowColor(0.16, 0.08, 0.02, 0.9)
  f.fill, f.fillDeep, f.label, f._thin = fill, fillDeep, label, thin and true or false
  function f:SetProgress(cur, maxv, text, colorKey)
    maxv = maxv or 1
    if maxv < 1 then maxv = 1 end
    cur = cur or 0
    if cur < 0 then cur = 0 elseif cur > maxv then cur = maxv end
    local inner = math.max(1, track:GetWidth())
    if inner < 2 then inner = math.max(1, self:GetWidth() - 2) end
    local fw = math.max(1, math.floor(inner * cur / maxv + 0.5))
    fill:SetWidth(fw)
    label:SetText(text or (tostring(cur) .. " / " .. tostring(maxv)))
    local done = cur >= maxv and maxv > 0
    local key = colorKey or (done and "good" or "barFill")
    local r, g, b = NS.Color(key)
    fill:SetColorTexture(r, g, b, 1)
    fillDeep:SetColorTexture(r * 0.55, g * 0.55, b * 0.45, 0.85)
  end
  NS.OnSkin(function()
    rim:SetColorTexture(NS.Color("barBorder"))          -- WoW #4b4a44
    local tr, tg, tb = NS.Color("barTrack")            -- WoW #050504
    track:SetColorTexture(tr, tg, tb, 0.98)
    gloss:SetColorTexture(1, 1, 1, 0.35)
    -- cream label (~ --dm-bar-ink #fff6d8)
    label:SetTextColor(NS.Color("barText"))
  end)
  return f
end


-- Item icon with rarity rim. Forever 1.60.1: SetPortraitToTexture blanks the
-- texture (white square); use plain SetTexture(Interface\Icons\...) instead.
function UI.RoundIcon(parent, size)
  size = size or 28
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  -- Outer rarity rim (visible even when quality is common/white)
  local border = f:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints(f)
  border:SetColorTexture(0.78, 0.78, 0.78, 1)
  -- Dark pad so a white common rim still reads as a border
  local pad = f:CreateTexture(nil, "BORDER")
  pad:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  pad:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  pad:SetColorTexture(0.08, 0.07, 0.05, 1)
  local tex = f:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
  tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.tex, f.border, f.pad = tex, border, pad
  f._iconPath = nil
  f._quality = 1
  f._itemId = nil

  local function SetBorderQuality(q)
    q = tonumber(q) or 1
    f._quality = q
    local r, g, b = 0.78, 0.78, 0.78
    if GetItemQualityColor then
      local ok, rr, gg, bb = pcall(GetItemQualityColor, q)
      if ok and type(rr) == "number" then r, g, b = rr, gg, bb end
    elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
      local c = ITEM_QUALITY_COLORS[q]
      r, g, b = c.r or r, c.g or g, c.b or b
    else
      local map = {
        [0] = { 0.62, 0.62, 0.62 },
        [1] = { 0.90, 0.90, 0.90 },
        [2] = { 0.12, 1.00, 0.00 },
        [3] = { 0.00, 0.44, 0.87 },
        [4] = { 0.64, 0.21, 0.93 },
        [5] = { 1.00, 0.50, 0.00 },
      }
      local c = map[q] or map[1]
      r, g, b = c[1], c[2], c[3]
    end
    border:SetColorTexture(r, g, b, 1)
  end

  local function ApplyPath(path)
    f._iconPath = path
    if not path then
      tex:SetColorTexture(0.18, 0.15, 0.10, 1)
      return false
    end
    -- Forever: never use SetPortraitToTexture — it clears the layer to white.
    tex:SetTexture(path)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    tex:Show()
    return true
  end

  function f.SetItem(_, itemId, quality, fallbackPath)
    if type(quality) == "string" and fallbackPath == nil then
      fallbackPath = quality
      quality = nil
    end
    f._itemId = itemId
    SetBorderQuality(quality)
    local path = fallbackPath
    if (not path) and itemId and NS.FishingItemIcon then
      path = NS.FishingItemIcon(itemId)
    end
    if not path and itemId and NS.FishingCatalogIcon then
      path = NS.FishingCatalogIcon(itemId)
    end
    ApplyPath(path)
    -- Ask client to load; GET_ITEM_INFO_RECEIVED / next refresh fills missing icons.
    if itemId and NS.FishingRequestItemIcon then
      NS.FishingRequestItemIcon(itemId)
    end
  end
  function f.GetIconPath(_) return f._iconPath end
  function f.RefreshIcon(_)
    if not f._itemId then return end
    local path = NS.FishingItemIcon and NS.FishingItemIcon(f._itemId)
    if path then ApplyPath(path) end
  end
  return f
end

-- Small checkbox with label (stock CheckButton).
function UI.Checkbox(parent, label, size, ink)
  size = size or 20
  local b = CreateFrame("CheckButton", nil, parent)
  b:SetSize(size, size)
  if b.EnableMouse then b:EnableMouse(true) end
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetColorTexture(0.05, 0.05, 0.04, 0.95)
  local border = b:CreateTexture(nil, "BORDER")
  border:SetAllPoints(b)
  border:SetColorTexture(0.45, 0.42, 0.32, 1)
  local check = b:CreateTexture(nil, "ARTWORK")
  check:SetPoint("CENTER", b, "CENTER", 0, 0)
  check:SetSize(size - 6, size - 6)
  check:SetColorTexture(0.85, 0.72, 0.2, 1)
  check:Hide()
  b._check = check
  function b:SetChecked(on)
    self._on = on and true or false
    if self._on then check:Show() else check:Hide() end
  end
  function b:GetChecked() return self._on and true or false end
  b:SetScript("OnClick", function(self)
    self:SetChecked(not self:GetChecked())
    if self.onToggle then self:onToggle(self:GetChecked()) end
  end)
  local text = UI.Text(parent, "OVERLAY", 12, ink or "listInk", "LEFT")
  text:SetPoint("LEFT", b, "RIGHT", 6, 0)
  text:SetText(label or "")
  b.label = text
  NS.OnSkin(function()
    -- 0.5.1 WoW theme: the stock check box (UICheckButtonTemplate's own textures) when the client has them
    local box, mark = NS.Stock.Spec("check_box"), NS.Stock.Spec("check_mark")
    if box and mark then
      NS.Stock.Apply(bg, box)
      border:Hide()
      NS.Stock.Apply(check, mark)
      check:SetSize(size + 4, size + 4)
      return
    end
    NS.Stock.Reset(bg) NS.Stock.Reset(check)
    border:Show()
    check:SetSize(size - 6, size - 6)
    bg:SetColorTexture(0.05, 0.05, 0.04, 0.95)
    border:SetColorTexture(0.45, 0.42, 0.32, 1)
    check:SetColorTexture(0.85, 0.72, 0.2, 1)
  end)
  return b
end

-- Single-line search field (stock EditBox).
function UI.SearchBox(parent, w, h)
  h = h or 24
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0.02, 0.02, 0.02, 0.92)
  f.border = UI.NineSlice(f, "pane", 4, "BORDER", 1)
  local eb = CreateFrame("EditBox", nil, f)
  eb:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -3)
  eb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 3)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(60)
  NS.SetFont(eb, 12, "")
  eb:SetTextColor(0.9, 0.88, 0.8, 1)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local ph = UI.Text(f, "OVERLAY", 12, "listSoft", "LEFT")
  ph:SetPoint("LEFT", eb, "LEFT", 0, 0)
  ph:SetText("Search…")
  eb:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    if t == "" then ph:Show() else ph:Hide() end
    if f.onChange then f.onChange(t) end
  end)
  f.edit, f.placeholder = eb, ph
  function f.SetText(_, t) eb:SetText(t or "") end
  function f.GetText(_) return eb:GetText() or "" end
  NS.OnSkin(function()
    local c = NS.theme.colors.fieldBg or { 0.02, 0.02, 0.02, 0.92 }  -- 0.4.4: themed field (search box, dropdown)
    bg:SetColorTexture(c[1], c[2], c[3], c[4] or 0.92)
    eb:SetTextColor(NS.Color("listInk"))
  end)
  return f
end

-- Centred "coming in a later phase" state on a page (glyph, big title, text).
function UI.Stub(page, glyphKey, title, text)
  local s = CreateFrame("Frame", nil, page)
  s:SetAllPoints(page)
  local g = s:CreateTexture(nil, "ARTWORK")
  g:SetSize(64, 64)
  g:SetPoint("CENTER", s, "CENTER", 0, 48)
  local big = UI.Text(s, "OVERLAY", 30, "inkHead", "CENTER")
  big:SetShadowOffset(0, 0)
  big:SetPoint("TOP", g, "BOTTOM", 0, -14)
  local p = UI.Text(s, "OVERLAY", 14, "inkSoft", "CENTER")
  p:SetShadowOffset(0, 0)
  p:SetWidth(420)
  p:SetPoint("TOP", big, "BOTTOM", 0, -10)
  s.big, s.sub = big, p
  function s.SetContent(_, newGlyph, newTitle, newText)
    if newGlyph then s.glyphKey = newGlyph NS.SetPiece(g, newGlyph) end
    big:SetText(newTitle or "")
    p:SetText(newText or "")
  end
  NS.OnSkin(function()
    if s.glyphKey then NS.SetPiece(g, s.glyphKey) end
    g:SetVertexColor(NS.Color("inkFaint"))
  end)
  s:SetContent(glyphKey, title, text)
  return s
end
