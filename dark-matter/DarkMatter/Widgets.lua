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
function UI.ThreeSlice(owner, prefix, h, layer, sub)
  local s = { prefix = prefix, h = h }
  s.l = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  s.m = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  s.r = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  function s:Apply(newPrefix)
    if newPrefix then self.prefix = newPrefix end
    local p = self.prefix
    NS.SetPiece(self.l, p .. "_l")
    NS.SetPiece(self.m, p .. "_m")
    NS.SetPiece(self.r, p .. "_r")
    local lw, lh = NS.PieceSize(p .. "_l")
    local rw, rh = NS.PieceSize(p .. "_r")
    self.l:ClearAllPoints()
    self.l:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    self.l:SetSize(lw * self.h / lh, self.h)
    self.r:ClearAllPoints()
    self.r:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
    self.r:SetSize(rw * self.h / rh, self.h)
    self.m:ClearAllPoints()
    self.m:SetPoint("TOPLEFT", self.l, "TOPRIGHT", 0, 0)
    self.m:SetPoint("BOTTOMRIGHT", self.r, "BOTTOMLEFT", 0, 0)
  end
  function s:SetBlend(mode) self.l:SetBlendMode(mode) self.m:SetBlendMode(mode) self.r:SetBlendMode(mode) end
  function s:SetAlpha(a) self.l:SetAlpha(a) self.m:SetAlpha(a) self.r:SetAlpha(a) end
  function s:Show() self.l:Show() self.m:Show() self.r:Show() end
  function s:Hide() self.l:Hide() self.m:Hide() self.r:Hide() end
  NS.OnSkin(function() s:Apply() end)
  return s
end

-- Nine-slice border (no centre): corner pieces t x t, edges stretched between them.
function UI.NineSlice(owner, prefix, t, layer, sub)
  local n = { prefix = prefix, size = t }
  for _, k in ipairs({ "tl", "tr", "bl", "br", "t", "b", "l", "r" }) do
    n[k] = owner:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
  end
  function n:Apply()
    local p, size = self.prefix, self.size
    for _, k in ipairs({ "tl", "tr", "bl", "br", "t", "b", "l", "r" }) do NS.SetPiece(self[k], p .. "_" .. k) end
    self.tl:ClearAllPoints() self.tl:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0) self.tl:SetSize(size, size)
    self.tr:ClearAllPoints() self.tr:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0) self.tr:SetSize(size, size)
    self.bl:ClearAllPoints() self.bl:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0) self.bl:SetSize(size, size)
    self.br:ClearAllPoints() self.br:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0) self.br:SetSize(size, size)
    self.t:ClearAllPoints() self.t:SetPoint("TOPLEFT", self.tl, "TOPRIGHT", 0, 0) self.t:SetPoint("BOTTOMRIGHT", self.tr, "BOTTOMLEFT", 0, 0)
    self.b:ClearAllPoints() self.b:SetPoint("TOPLEFT", self.bl, "TOPRIGHT", 0, 0) self.b:SetPoint("BOTTOMRIGHT", self.br, "BOTTOMLEFT", 0, 0)
    self.l:ClearAllPoints() self.l:SetPoint("TOPLEFT", self.tl, "BOTTOMLEFT", 0, 0) self.l:SetPoint("BOTTOMRIGHT", self.bl, "TOPRIGHT", 0, 0)
    self.r:ClearAllPoints() self.r:SetPoint("TOPLEFT", self.tr, "BOTTOMLEFT", 0, 0) self.r:SetPoint("BOTTOMRIGHT", self.br, "TOPRIGHT", 0, 0)
  end
  NS.OnSkin(function() n:Apply() end)
  return n
end

-- Dark slate fill (stretched), optionally shaded darker.
function UI.Slate(owner, shadeKey, layer, sub)
  local tex = owner:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  tex:SetAllPoints(owner)
  NS.OnSkin(function()
    tex:SetTexture(NS.theme.media.slate)
    local s = NS.Metric(shadeKey or "slateShade")
    tex:SetVertexColor(s, s, s, 1)
  end)
  return tex
end

-- Dark list/detail panel with the pane border.
function UI.Panel(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  UI.Slate(f, "listShade", "BACKGROUND", 0)
  f.border = UI.NineSlice(f, "pane", NS.theme.m.listBorder, "BORDER", 1)
  return f
end

-- Parchment page with the pane border.
function UI.Page(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, h)
  local parch = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  parch:SetAllPoints(f)
  NS.OnSkin(function() parch:SetTexture(NS.theme.media.parchment) end)
  f.border = UI.NineSlice(f, "pane", NS.theme.m.pageBorder, "BORDER", 1)
  return f
end

-- Plain button with the three-slice art. kind: "red", "grey" or "field".
local KIND_INK = { red = "gold", grey = "greyBtn", field = "gold" }
function UI.Button(parent, label, w, h, kind, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.kind = kind or "red"
  b.slice = UI.ThreeSlice(b, "btn_" .. b.kind, h, "ARTWORK")
  b.glow = UI.ThreeSlice(b, "btn_" .. b.kind, h, "HIGHLIGHT")
  b.glow:SetBlend("ADD")
  b.glow:SetAlpha(0.22)
  b.text = b:CreateFontString(nil, "OVERLAY")
  NS.SetFont(b.text, size or NS.theme.m.fbtnSize, "")
  b.text:SetShadowOffset(1, -1)
  b.text:SetShadowColor(0, 0, 0, 0.9)
  b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
  b.text:SetText(label or "")
  function b:SetLook(kindName)
    self.kind = kindName
    self.slice:Apply("btn_" .. kindName)
    self.glow:Apply("btn_" .. kindName)
    self.text:SetTextColor(NS.Color(KIND_INK[kindName] or "gold"))
  end
  NS.OnSkin(function() b:SetLook(b.kind) end)
  b:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", self, "CENTER", 1, 0) end)
  b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", self, "CENTER", 0, 1) end)
  return b
end

-- Left-rail tab: icon + label, three-slice art, wider when active.
function UI.RailTab(parent, label, glyphKey)
  local m = NS.theme.m
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(m.tabW, m.tabH)
  t.slice = UI.ThreeSlice(t, "rtab_i", m.tabH, "ARTWORK")
  t.glow = UI.ThreeSlice(t, "rtab_i", m.tabH, "HIGHLIGHT")
  t.glow:SetBlend("ADD")
  t.glow:SetAlpha(0.14)
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
  function t:SetActive(on)
    self.active = on and true or false
    local mm = NS.theme.m
    self:SetWidth(self.active and mm.tabWOn or mm.tabW)
    local p = self.active and "rtab_a" or "rtab_i"
    self.slice:Apply(p)
    self.glow:Apply(p)
    self.text:SetTextColor(NS.Color(self.active and "goldOn" or "gold"))
    self.icon:SetVertexColor(NS.Color(self.active and "goldOn" or "gold"))
  end
  NS.OnSkin(function()
    NS.SetPiece(t.icon, t.glyphKey)
    t:SetActive(t.active)
  end)
  return t
end

-- Section pill (like the mockup's Fishing / Adventure Guide / Achievements buttons).
function UI.Pill(parent, label)
  local m = NS.theme.m
  local p = CreateFrame("Button", nil, parent)
  p.text = p:CreateFontString(nil, "OVERLAY")
  NS.SetFont(p.text, m.pillSize, "")
  p.text:SetShadowOffset(1, -1)
  p.text:SetShadowColor(0, 0, 0, 0.9)
  p.text:SetText(label)
  local tw = NS.Num(p.text:GetStringWidth()) or 60
  p:SetSize(math.floor(tw + m.pillPad * 2 + 0.5), m.pillsH)
  p.slice = UI.ThreeSlice(p, "ptab_i", m.pillsH, "ARTWORK")
  p.glow = UI.ThreeSlice(p, "ptab_i", m.pillsH, "HIGHLIGHT")
  p.glow:SetBlend("ADD")
  p.glow:SetAlpha(0.16)
  p.mark = p:CreateTexture(nil, "OVERLAY")
  p.mark:SetSize(11, 11)
  p.mark:SetPoint("LEFT", p, "LEFT", 9, 0)
  p.text:SetPoint("CENTER", p, "CENTER", 0, 1)
  p.active = false
  function p:SetActive(on)
    self.active = on and true or false
    local prefix = self.active and "ptab_a" or "ptab_i"
    self.slice:Apply(prefix)
    self.glow:Apply(prefix)
    self.text:SetTextColor(NS.Color(self.active and "goldOn" or "gold"))
    if self.active then self.mark:Show() else self.mark:Hide() end
    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", self, "CENTER", self.active and 6 or 0, 1)
  end
  NS.OnSkin(function()
    NS.SetPiece(p.mark, "coin_target")
    p:SetActive(p.active)
  end)
  return p
end

-- Scroll area with the generated scrollbar art: up/down buttons, track, three-slice thumb.
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

  NS.OnSkin(function()
    NS.SetPiece(upTex, "sb_up") NS.SetPiece(upGlow, "sb_up")
    NS.SetPiece(downTex, "sb_dn") NS.SetPiece(downGlow, "sb_dn")
    NS.SetPiece(thumb, "sb_thumb_m") NS.SetPiece(capT, "sb_thumb_t") NS.SetPiece(capB, "sb_thumb_b")
  end)

  local updating = false
  sb:SetScript("OnValueChanged", function(_, value)
    if updating then return end
    sf:SetVerticalScroll(value or 0)
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
      thumb:SetHeight(math.max(26, track * self.h / self.contentH))
      sb:Show()
      capT:Show() capB:Show() thumb:Show()
    else
      capT:Hide() capB:Hide() thumb:Hide()
    end
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
  end
  function S:ScrollTo(v) self:ScrollBy(v - (sb:GetValue() or 0)) end
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta) S:ScrollBy(-delta * S.step) end)
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) S:ScrollBy(-delta * S.step) end)
  up:SetScript("OnClick", function() S:ScrollBy(-S.step) end)
  down:SetScript("OnClick", function() S:ScrollBy(S.step) end)
  S:Update()
  return S
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
