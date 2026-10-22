-- Dark Matter main window (P1): the approved mockup layout built from stock frame types and the theme layer.
-- Opens at screen centre, auto-saves its position, Reset window position lives in the Settings popover.
-- Left vertical tabs; each tab is a module registered with NS.RegisterTab (Tab_*.lua).
local _, NS = ...
local UI = NS.UI

NS.tabs = NS.tabs or {}
NS.tabOrder = NS.tabOrder or {}

function NS.RegisterTab(def)
  NS.tabs[def.id] = def
  NS.tabOrder[#NS.tabOrder + 1] = def.id
end

local frame
local W = {} -- window parts
NS.windowParts = W

---------------------------------------------------------------------------
-- position
---------------------------------------------------------------------------
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

-- Class-theme art space: the previewer's 880x680 css window (rim 38, header 46, footer 48). Its shell box
-- (38..842 x 84..594) is mapped onto ours (pad..w-pad x shellTop..footerTop), so the art frames our layout.
-- 0.5.1.4: the art keeps the scale it has on the 880x680 window; a window sized to the game's map window only makes the
-- art space wider / taller (aw x ah css), so the frame's edges run longer and every piece keeps its density.
local function ArtMap()
  local m = NS.theme.m
  local b = NS.MapWindow and NS.MapWindow.bases and NS.MapWindow.bases[m] or m
  local sx = (b.w - 2 * m.pad) / 804
  local sy = (b.footerTop - m.shellTop) / 510
  local aw = 880 + (m.w - b.w) / sx
  local ah = 680 + (m.h - b.h) / sy
  return sx, sy, m.pad - 38 * sx, m.shellTop - 84 * sy, aw, ah
end
NS.ClassArtMap = ArtMap

-- Shrink (never enlarge) so the 880x680 window (or a class theme's larger frame art) fits small screens.
local function FitScale(f)
  local m = NS.theme.m
  local w, h = m.w, m.h
  if NS.theme.classArt then
    local sx, sy, _, _, aw, ah = ArtMap()
    w, h = aw * sx, ah * sy
  end
  local s = 1
  local uh, uw = NS.Num(UIParent:GetHeight()), NS.Num(UIParent:GetWidth())
  if uh and uh > 0 then s = math.min(s, uh * m.maxScreenFraction / h) end
  if uw and uw > 0 then s = math.min(s, uw * m.maxScreenFraction / w) end
  f:SetScale(math.max(0.5, s))
end

-- Class frame art (theme.classArt), all data-driven (0.4.3). No backdrop: the game world shows around the frame.
-- Frame layer (under the content, on the window's own BORDER layer): 4 corners at the source art's density plus 4 edge
-- strips that REPEAT along their length at the same density (sharp, not stretched); each corner fades into its strips.
-- Overlay layer (no-mouse child above the content): its 4 corners plus its edge sprites (glows, vines, crystals) at
-- their own spots, then the corner ornaments, crest and base plate. Overhanging art stays and is part of the drag area.
local function BuildClassArt(f)
  local A = { fe = {}, fc = {}, oc = {}, os = {}, orn = {} }
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f)
  top:SetFrameLevel(f:GetFrameLevel() + 25)
  top:EnableMouse(false)
  A.top = top
  for i = 1, 4 do
    A.fe[i] = f:CreateTexture(nil, "BORDER", nil, 0)
    A.fc[i] = f:CreateTexture(nil, "BORDER", nil, 1)
    A.oc[i] = top:CreateTexture(nil, "ARTWORK", nil, 1)
  end
  for _, k in ipairs({ "tl", "tr", "bl", "br" }) do A.orn[k] = top:CreateTexture(nil, "OVERLAY", nil, 0) end
  A.crest = top:CreateTexture(nil, "OVERLAY", nil, 1)
  A.base = top:CreateTexture(nil, "OVERLAY", nil, 1)
  local all = { A.crest, A.base }
  for i = 1, 4 do all[#all + 1] = A.fe[i] all[#all + 1] = A.fc[i] all[#all + 1] = A.oc[i] end
  for _, k in ipairs({ "tl", "tr", "bl", "br" }) do all[#all + 1] = A.orn[k] end
  A.all = all
  -- r = { left, top, width, height } in texels of a tw x th texture (half a texel inset)
  local function TC(r, tw, th)
    return (r[1] + 0.5) / tw, (r[1] + r[3] - 0.5) / tw, (r[2] + 0.5) / th, (r[2] + r[4] - 0.5) / th
  end
  local function Put(tex, file, l, r, t, b, x, y, w, h, wrapH, wrapV)
    if wrapH or wrapV then tex:SetTexture(file, wrapH or "CLAMP", wrapV or "CLAMP") else tex:SetTexture(file) end
    tex:SetTexCoord(l, r, t, b)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    tex:SetSize(w, h)
    tex:Show()
  end
  local CORNER = { { 0, 0 }, { 256, 0 }, { 0, 256 }, { 256, 256 } } -- tl, tr, bl, br cells (240x240 used)
  function A.Apply()
    local ca = NS.theme.classArt
    for _, t in ipairs(A.os) do t:Hide() end
    if not ca then
      for _, t in ipairs(all) do t:Hide() end
      top:Hide()
      return
    end
    top:Show()
    local sx, sy, ax, ay, AW, AH = ArtMap()
    local k = (sx + sy) / 2
    local E = ca.edges
    local c, fd = E.corner, E.fade
    local fr, ov = E.frame, E.over
    -- art css rect -> window units
    local function X(v) return ax + v * sx end
    local function Y(v) return ay + v * sy end
    local pos = { { 0, 0 }, { AW - c, 0 }, { 0, AH - c }, { AW - c, AH - c } }
    for i = 1, 4 do
      local cell = { CORNER[i][1], CORNER[i][2], 240, 240 }
      local l, r, t, b = TC(cell, 512, 512)
      Put(A.fc[i], fr.corners, l, r, t, b, X(pos[i][1]), Y(pos[i][2]), c * sx, c * sy)
      Put(A.oc[i], ov.corners, l, r, t, b, X(pos[i][1]), Y(pos[i][2]), c * sx, c * sy)
    end
    -- edge strips start under the corner fade (c - fd) and repeat len[i] css per tile
    local s0 = c - fd
    local hw, vh = AW - 2 * s0, AH - 2 * s0
    local L = fr.len
    Put(A.fe[1], fr.tb, 0, hw / L[1], 0.5 / 512, 239.5 / 512, X(s0), Y(0), hw * sx, c * sy, "REPEAT", "CLAMP")
    Put(A.fe[2], fr.tb, 0, hw / L[2], 256.5 / 512, 495.5 / 512, X(s0), Y(AH - c), hw * sx, c * sy, "REPEAT", "CLAMP")
    Put(A.fe[3], fr.lr, 0.5 / 512, 239.5 / 512, 0, vh / L[3], X(0), Y(s0), c * sx, vh * sy, "CLAMP", "REPEAT")
    Put(A.fe[4], fr.lr, 256.5 / 512, 495.5 / 512, 0, vh / L[4], X(AW - c), Y(s0), c * sx, vh * sy, "CLAMP", "REPEAT")
    for i, sp in ipairs(ov.list) do
      local tex = A.os[i]
      if not tex then
        tex = top:CreateTexture(nil, "ARTWORK", nil, 0)
        A.os[i] = tex
      end
      local a, t2 = sp[1], sp[2]
      local l, r, t, b = TC(t2, 512, ov.sh)
      -- sprites on the right / bottom half stay at their edge when the art space is wider / taller
      local px = a[1] + ((a[1] + a[3] / 2 > 440) and (AW - 880) or 0)
      local py = a[2] + ((a[2] + a[4] / 2 > 340) and (AH - 680) or 0)
      Put(tex, ov.sprites, l, r, t, b, X(px), Y(py), a[3] * sx, a[4] * sy)
    end
    local R, file, pw, ph = ca.rects, ca.parts, ca.pw, ca.ph
    local aw, ah = AW * sx, AH * sy
    local o = ca.orn * k
    local function P(tex, key, x, y, w, h)
      local l, r, t, b = TC(R[key], pw, ph)
      Put(tex, file, l, r, t, b, x, y, w, h)
    end
    P(A.orn.tl, "orn_tl", ax, ay, o, o)
    P(A.orn.tr, "orn_tr", ax + aw - o, ay, o, o)
    P(A.orn.bl, "orn_bl", ax, ay + ah - o, o, o)
    P(A.orn.br, "orn_br", ax + aw - o, ay + ah - o, o, o)
    local cs = ca.crest[1] * k
    local cx, cy = ax + (AW / 2 + ca.crest[2]) * sx - cs / 2, ay + ca.crest[3] * sy
    P(A.crest, "crest", cx, cy, cs, cs)
    local bw, bh = ca.base[1] * k, ca.base[2] * k
    local bs = math.min(bw, bh)
    local bx, by = ax + AW / 2 * sx - bs / 2, ay + (642 + AH - 680) * sy + (bh - bs) / 2
    P(A.base, "base", bx, by, bs, bs)
    -- everything drawn (art rect + overhanging crest and base), window-relative, y down
    A.box = { math.min(ax, cx, bx), math.min(ay, cy), math.max(ax + aw, cx + cs, bx + bs), math.max(ay + ah, by + bs) }
  end
  return A
end

---------------------------------------------------------------------------
-- tabs
---------------------------------------------------------------------------
function NS.ShowTab(id)
  if not frame then return end
  local def = NS.tabs[id] or NS.tabs[NS.tabOrder[1]]
  if not def then return end
  id = def.id
  local prevId = W.current
  if prevId and prevId ~= id then
    local prev = NS.tabs[prevId]
    if prev and prev.OnHide then pcall(prev.OnHide) end
  end
  for _, tid in ipairs(NS.tabOrder) do
    local t = NS.tabs[tid]
    if t.frame then t.frame:Hide() end
    if W.railTabs[tid] then W.railTabs[tid]:SetActive(tid == id) end
  end
  if not def.frame then def.frame = def.Build(W.body) end
  def.frame:Show()
  W.current = id
  if NS.db then NS.db.tab = id end
  if W.pop then W.pop:Hide() end
  if def.OnShow and frame:IsShown() then pcall(def.OnShow) end
end

function NS.SetStatus(text)
  if W.statusText then W.statusText:SetText(text or "") end
end

function NS.SetAllIcon(expanded)
  if W.allIcon then NS.SetPiece(W.allIcon, expanded and "coin_minus" or "coin_plus") end
end

---------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------
local function EdgeLine(parent, point1, rel1, point2, rel2, w, h, r, g, b)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetPoint(point1, parent, rel1, 0, 0)
  t:SetPoint(point2, parent, rel2, 0, 0)
  if w then t:SetWidth(w) end
  if h then t:SetHeight(h) end
  t:SetColorTexture(r, g, b, 1)
  return t
end

local function SpecialFrame(name, add)
  -- Esc closes named frames through Blizzard's UISpecialFrames list (stock, taint-safe).
  if type(UISpecialFrames) ~= "table" then return end
  if add then
    for i = 1, #UISpecialFrames do if UISpecialFrames[i] == name then return end end
    tinsert(UISpecialFrames, name)
  else
    for i = #UISpecialFrames, 1, -1 do
      if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
  end
end

NS.SpecialFrame = SpecialFrame
-- Esc target back to the main window (after a popup or the AG dropdown closes), unless another popup is open.
function NS.RestoreEscMain()
  local f, pop, catch = _G.DarkMatterFrame, _G.DarkMatterSettingsPop, _G.DarkMatterAGMenuCatcher
  if f and f:IsShown() and not (pop and pop:IsShown()) and not (catch and catch:IsShown()) then SpecialFrame("DarkMatterFrame", true) end
end

local function BuildSettings(f)
  local m = NS.theme.m
  -- Named so Esc can close it via UISpecialFrames while it is open (instead of the main window).
  local pop = CreateFrame("Frame", "DarkMatterSettingsPop", f)
  pop:SetSize(m.popW, m.popH)
  pop:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", m.popX, m.pad + m.popBottom)
  pop:SetFrameLevel(f:GetFrameLevel() + 30)
  pop:EnableMouse(true)
  local bg = pop:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(pop)
  local lines = {
    EdgeLine(pop, "TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1, 1, 1, 1),
    EdgeLine(pop, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1, 1, 1, 1),
    EdgeLine(pop, "TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil, 1, 1, 1),
    EdgeLine(pop, "TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil, 1, 1, 1),
  }
  NS.OnSkin(function()
    bg:SetColorTexture(NS.Color("popBg"))
    for _, l in ipairs(lines) do l:SetColorTexture(NS.Color("popBorder")) end
  end)
  local head = UI.Text(pop, "OVERLAY", 15, "listHead", "LEFT")
  head:SetPoint("TOPLEFT", pop, "TOPLEFT", 14, -12)
  head:SetText("Settings")
  local label = UI.Text(pop, "OVERLAY", 14, "popInk", "LEFT")
  label:SetPoint("TOPLEFT", pop, "TOPLEFT", 14, -44)
  label:SetText("Theme")
  local value = UI.Text(pop, "OVERLAY", 14, "gold", "RIGHT")
  value:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -14, -44)
  -- Theme picker: one plain button per registered theme (WoW + the nine class themes), 2 columns.
  -- A click applies the theme live (NS.SetTheme re-skins every widget) and saves it in DarkMatterDB.theme.
  local pick = {}
  local bw, bh = math.floor((m.popW - 28 - 8) / 2), 24
  for i, id in ipairs(NS.themeOrder) do
    local def = NS.themes[id]
    local b = UI.Button(pop, def.name, bw, bh, "grey", 12)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    b:SetPoint("TOPLEFT", pop, "TOPLEFT", 14 + col * (bw + 8), -70 - row * (bh + 6))
    b:SetScript("OnClick", function() NS.SetTheme(id) end)
    b.themeId = id
    pick[#pick + 1] = b
  end
  W.themeButtons = pick
  NS.OnSkin(function()
    value:SetText(NS.theme.name)
    for _, b in ipairs(pick) do
      local on = b.themeId == NS.theme.id
      b.active = on -- 0.5.1.2 WoW theme: the current theme's button shows held down (stock button feel)
      b:SetLook(on and "red" or "grey")
      if not on and not b.stockOn then b.text:SetTextColor(NS.Color("popInk")) end -- readable, not the disabled grey
    end
  end)
  local reset = UI.Button(pop, "Reset window position", m.popW - 28, m.fbtnH, "red", m.fbtnSize)
  reset:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 14, 14)
  reset:SetScript("OnClick", function() NS.ResetWindowPosition() end)

  -- Click-outside: a catcher over the main window (above content, below the pop) and a
  -- full-screen catcher under the window so a click on the world also dismisses. Both are
  -- plain Frames with private OnMouseDown handlers; neither hooks Blizzard code.
  local catcher = CreateFrame("Frame", nil, f)
  catcher:SetAllPoints(f)
  catcher:SetFrameLevel(f:GetFrameLevel() + 20)
  catcher:EnableMouse(true)
  catcher:Hide()
  catcher:SetScript("OnMouseDown", function() pop:Hide() end)

  local world = CreateFrame("Frame", nil, UIParent)
  world:SetAllPoints(UIParent)
  world:SetFrameStrata("HIGH")
  world:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
  world:EnableMouse(true)
  world:Hide()
  world:SetScript("OnMouseDown", function() pop:Hide() end)

  pop:SetScript("OnShow", function()
    catcher:Show()
    world:Show()
    -- Esc closes the pop first; restore the main window entry when the pop hides.
    SpecialFrame("DarkMatterFrame", false)
    SpecialFrame("DarkMatterSettingsPop", true)
  end)
  pop:SetScript("OnHide", function()
    catcher:Hide()
    world:Hide()
    SpecialFrame("DarkMatterSettingsPop", false)
    NS.RestoreEscMain()
  end)

  pop:Hide()
  W.popCatcher = catcher
  W.popWorldCatcher = world
  return pop
end


-- 0.5.1.4 WoW theme: the frame of the game's own map window (WorldMapFrame), drawn on ours. When the map window's
-- border pieces can be read (NS.MapWindow.Art), the same 8 game textures are placed around our window the way its
-- NineSlice places them; otherwise Dark Matter draws its own thin bronze frame. A slim dark title strip with the gold
-- title sits under either. Class themes never show any of it.
local MAP_TITLE_H = 24
local BRONZE = { 0.72, 0.57, 0.30, 1 }
local function BuildMapChrome(f)
  local MW = NS.MapWindow
  local C = { nine = {}, own = {}, all = {} }
  local function T(layer, sub) local t = f:CreateTexture(nil, layer, nil, sub) C.all[#C.all + 1] = t return t end
  C.strip = T("BACKGROUND", 6)
  C.strip:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
  C.strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  C.strip:SetHeight(MAP_TITLE_H)
  C.stripLine = T("BACKGROUND", 7)
  C.stripLine:SetPoint("TOPLEFT", C.strip, "BOTTOMLEFT", 0, 0)
  C.stripLine:SetPoint("TOPRIGHT", C.strip, "BOTTOMRIGHT", 0, 0)
  C.stripLine:SetHeight(1)
  -- own thin frame: a dark outer line and a bronze inner line on each side
  local sides = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }
  for i, sd in ipairs(sides) do
    for j = 0, 1 do
      local t = T("BORDER", 4)
      local ix = (sd[1]:find("RIGHT") and -j or j)
      local iy = (sd[1]:find("BOTTOM") and j or -j)
      local ix2 = (sd[2]:find("RIGHT") and -j or j)
      local iy2 = (sd[2]:find("BOTTOM") and j or -j)
      t:SetPoint(sd[1], f, sd[1], ix, iy)
      t:SetPoint(sd[2], f, sd[2], ix2, iy2)
      if sd[3] then t:SetHeight(1) else t:SetWidth(1) end
      t.inner = j == 1
      C.own[#C.own + 1] = t
    end
    C.own[i * 2 - 1].side = i
  end
  for _, k in ipairs(MW.NINE) do C.nine[k] = T("BORDER", 5) end
  local CORNER_PT = { TopLeftCorner = "TOPLEFT", TopRightCorner = "TOPRIGHT", BottomLeftCorner = "BOTTOMLEFT", BottomRightCorner = "BOTTOMRIGHT" }
  -- edge: its two corners, the points it joins them at, and whether it runs across (its height is the art's)
  local EDGE = { TopEdge = { "TopLeftCorner", "TOPLEFT", "TOPRIGHT", "TopRightCorner", "TOPRIGHT", "TOPLEFT", true },
    BottomEdge = { "BottomLeftCorner", "BOTTOMLEFT", "BOTTOMRIGHT", "BottomRightCorner", "BOTTOMRIGHT", "BOTTOMLEFT", true },
    LeftEdge = { "TopLeftCorner", "TOPLEFT", "BOTTOMLEFT", "BottomLeftCorner", "BOTTOMLEFT", "TOPLEFT", false },
    RightEdge = { "TopRightCorner", "TOPRIGHT", "BOTTOMRIGHT", "BottomRightCorner", "BOTTOMRIGHT", "TOPRIGHT", false } }
  function C.Mirror()
    local A = MW.Art()
    if not (A and A.full) then return false end
    for _, k in ipairs(MW.NINE) do
      if not MW.Paint(C.nine[k], A.nine[k]) then return false end
    end
    for k, pt in pairs(CORNER_PT) do
      local p, t = A.nine[k], C.nine[k]
      t:ClearAllPoints()
      local own = p.point == pt
      t:SetPoint(pt, f, pt, own and p.x or 0, own and p.y or 0)
      t:SetSize(p.w or 32, p.h or 32)
    end
    for k, e in pairs(EDGE) do
      local p, t = A.nine[k], C.nine[k]
      t:ClearAllPoints()
      t:SetPoint(e[2], C.nine[e[1]], e[3], 0, 0)
      t:SetPoint(e[5], C.nine[e[4]], e[6], 0, 0)
      if e[7] then t:SetHeight(p.h or 16) else t:SetWidth(p.w or 16) end
    end
    return true
  end
  function C.Apply(on)
    C.mirrored = false
    if not on then for _, t in ipairs(C.all) do t:Hide() end return end
    C.strip:SetColorTexture(0.055, 0.05, 0.045, 0.97) C.strip:Show()
    C.stripLine:SetColorTexture(BRONZE[1] * 0.6, BRONZE[2] * 0.6, BRONZE[3] * 0.6, 1) C.stripLine:Show()
    C.mirrored = C.Mirror()
    for _, k in ipairs(MW.NINE) do if C.mirrored then C.nine[k]:Show() else C.nine[k]:Hide() end end
    for _, t in ipairs(C.own) do
      if C.mirrored then t:Hide()
      else
        if t.inner then t:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], BRONZE[4]) else t:SetColorTexture(0, 0, 0, 0.9) end
        t:Show()
      end
    end
  end
  return C
end
NS.MAP_TITLE_H = MAP_TITLE_H

local function Build()
  local m = NS.theme.m
  -- 0.5.1.4: as large as the game's own map window (read only; Dark Matter's own size when it cannot be read)
  if NS.MapWindow then NS.MapWindow.Apply(m) end
  local f = CreateFrame("Frame", "DarkMatterFrame", UIParent)
  f:SetSize(m.w, m.h)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
  f:Hide()
  frame = f
  FitScale(f)

  -- dark slate behind everything, footer tint, thin line above the footer
  local slate = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  slate:SetPoint("TOPLEFT", f, "TOPLEFT", m.pad, -m.pad)
  slate:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -m.pad, m.pad)
  NS.OnSkin(function()
    if NS.ApplySurface(slate, "shell") then return end
    NS.Stock.Media(slate, "shell", "slate", NS.Metric("slateShade"))
  end)
  local tint = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  tint:SetPoint("TOPLEFT", f, "TOPLEFT", m.pad, -m.footerTop)
  tint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -m.pad, m.pad)
  local line = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  line:SetPoint("TOPLEFT", f, "TOPLEFT", m.pad, -m.footerTop)
  line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -m.pad, -m.footerTop)
  line:SetHeight(1)
  NS.OnSkin(function()
    tint:SetColorTexture(0.016, 0.016, 0.016, NS.Metric("footerTint"))
    line:SetColorTexture(0, 0, 0, 1)
  end)

  -- fine border frame
  local frameNine = UI.NineSlice(f, "frame", m.frameCorner, "BORDER", 2)

  -- title plate + title text (also a drag handle)
  local tb = CreateFrame("Frame", nil, f)
  tb:SetPoint("TOPLEFT", f, "TOPLEFT", m.titleX, -m.titleY)
  tb:SetSize(m.titleW, m.titleH)
  tb:EnableMouse(true)
  tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() f:StartMoving() end)
  tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() SavePosition() end)
  local tbSlice = UI.ThreeSlice(tb, "title", m.titleH, "ARTWORK")
  local title = UI.Text(tb, "OVERLAY", m.titleSize, "title", "CENTER")
  title:SetPoint("CENTER", tb, "CENTER", 0, 0)
  NS.OnSkin(function() title:SetText(NS.theme.title or "Dark Matter") end)
  W.title = title

  -- rail with the vertical tabs
  local rail = CreateFrame("Frame", nil, f)
  rail:SetPoint("TOPLEFT", f, "TOPLEFT", m.railX, -m.railY)
  rail:SetSize(m.railW, m.railH)
  UI.Slate(rail, "railShade", "BACKGROUND", 3)
  UI.NineSlice(rail, "pane", m.railBorder, "BORDER", 3, "rail") -- 0.5.1.3: an inset divider in the class themes
  W.rail = rail
  W.railTabs = {}
  for i, tid in ipairs(NS.tabOrder) do
    local def = NS.tabs[tid]
    local t = UI.RailTab(rail, def.name, NS.theme.glyphs[def.glyph])
    t:SetPoint("TOPLEFT", rail, "TOPLEFT", m.tabX - m.railX, -(m.tabY - m.railY) - (i - 1) * (m.tabH + m.tabGap))
    t:SetScript("OnClick", function() NS.ShowTab(tid) end)
    W.railTabs[tid] = t
  end

  -- body host: tabs build into this
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", f, "TOPLEFT", m.bodyX, -m.bodyY)
  body:SetSize(m.bodyW, m.bodyH)
  W.body = body

  -- 0.4.5: All + Track Quest moved into the Quests tab (toolbar row above the quest list)

  -- footer: Settings, status field, Share stats (later phase), Exit
  local settings = UI.Button(f, "Settings", m.fbtnW, m.fbtnH, "red", m.fbtnSize)
  settings:SetPoint("TOPLEFT", f, "TOPLEFT", m.fbtnLeft, -m.fbtnY)
  local status = CreateFrame("Frame", nil, f)
  status:SetPoint("TOPLEFT", f, "TOPLEFT", m.statusX, -m.statusY)
  status:SetSize(m.statusW, m.statusH)
  W.statusSlice = UI.ThreeSlice(status, "btn_field", m.statusH, "ARTWORK")
  W.statusText = UI.Text(status, "OVERLAY", m.statusSize, "status", "CENTER")
  W.statusText:SetPoint("CENTER", status, "CENTER", 0, 0)
  W.statusText:SetShadowOffset(0, 0)
  local share = UI.Button(f, "Share stats", m.fbtnW, m.fbtnH, "grey", m.fbtnSize)
  W.shareBtn = share
  share:SetPoint("TOPLEFT", f, "TOPLEFT", m.shareX, -m.fbtnY)
  share:Disable()
  local exit = UI.Button(f, "Exit", m.fbtnW, m.fbtnH, "red", m.fbtnSize)
  exit:SetPoint("TOPLEFT", f, "TOPLEFT", m.exitX, -m.fbtnY)
  exit:SetScript("OnClick", function() f:Hide() end)

  -- settings popover (Theme, Reset window position)
  W.pop = BuildSettings(f)
  W.settingsBtn = settings
  -- Toggle: open shows the pop (and its catchers); close hides it. While the pop is open the
  -- window catcher sits above this button, so a second click hits the catcher and dismisses
  -- without re-opening — same end state as a plain toggle close.
  settings:SetScript("OnClick", function()
    if W.pop:IsShown() then W.pop:Hide() else W.pop:Show() end
  end)

  -- medal (above the border, like the mockup) and close button
  local medal = CreateFrame("Frame", nil, f)
  medal:SetSize(m.medalSize, m.medalSize)
  medal:SetPoint("TOPLEFT", f, "TOPLEFT", m.medalX, -m.medalY)
  medal:SetFrameLevel(f:GetFrameLevel() + 40)
  local medalTex = medal:CreateTexture(nil, "ARTWORK")
  medalTex:SetAllPoints(medal)
  NS.OnSkin(function() NS.SetPiece(medalTex, "medal") end)

  local close = CreateFrame("Button", nil, f)
  close:SetSize(m.closeSize, m.closeSize)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(m.pad + m.closeRight), -(m.pad + m.closeTop))
  close:SetFrameLevel(f:GetFrameLevel() + 20)
  local closeTex = close:CreateTexture(nil, "ARTWORK")
  closeTex:SetAllPoints(close)
  local closeGlow = close:CreateTexture(nil, "HIGHLIGHT")
  closeGlow:SetAllPoints(close)
  closeGlow:SetBlendMode("ADD")
  closeGlow:SetAlpha(0.25)
  NS.OnSkin(function() NS.SetPiece(closeTex, "xbtn") NS.SetPiece(closeGlow, "xbtn") end)
  close:SetScript("OnClick", function() f:Hide() end)
  -- 0.5.1 WoW theme: the game's own close button (UIPanelCloseButton template) when the client has it
  local stockClose = NS.Stock.FromTemplate("Button", f, "UIPanelCloseButton")
  if stockClose then
    stockClose:SetScript("OnClick", function() f:Hide() end)
    stockClose:SetFrameLevel(f:GetFrameLevel() + 21)
    stockClose:Hide()
  end
  W.stockClose = stockClose

  f:SetScript("OnShow", function()
    local def = NS.tabs[W.current]
    if def and def.OnShow then pcall(def.OnShow) end
  end)
  f:SetScript("OnHide", function()
    if W.pop then W.pop:Hide() end
    local def = NS.tabs[W.current]
    if def and def.OnHide then pcall(def.OnHide) end
  end)

  -- class themes: frame art on, WoW-only chrome (frame border, title plate, medal, footer tint) off
  local art = BuildClassArt(f)
  W.classArt = art
  local wowOnly = { frameNine, tbSlice, tint, line, medal }
  local mapChrome = BuildMapChrome(f)
  W.mapChrome = mapChrome
  NS.OnSkin(function()
    art.Apply()
    local ca = NS.theme.classArt
    -- 0.5.1.4: the WoW theme wears the game's map-window frame (theme.mapWindow) instead of the dialog border + plate
    local mapLook = (not ca) and NS.theme.mapWindow and true or false
    W.mapLook = mapLook
    for _, o in ipairs(wowOnly) do if ca then o:Hide() else o:Show() end end
    if mapLook then frameNine:Hide() tbSlice:Hide() end
    mapChrome.Apply(mapLook)
    tb:ClearAllPoints()
    if mapLook then
      tb:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -2)
      tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -2)
      tb:SetHeight(MAP_TITLE_H)
    else
      tb:SetPoint("TOPLEFT", f, "TOPLEFT", m.titleX, -m.titleY)
      tb:SetSize(m.titleW, m.titleH)
    end
    -- the portrait: the map window's own when it can be read, else the quest-log book, small, at the corner
    medal:ClearAllPoints()
    local A = mapLook and NS.MapWindow.Art()
    local pp = A and A.portrait
    if mapLook and pp and pp.shown and NS.MapWindow.Paint(medalTex, pp) then
      medal:SetSize(pp.w or 58, pp.h or 58)
      medal:SetPoint("TOPLEFT", f, "TOPLEFT", pp.point == "TOPLEFT" and pp.x or -6, pp.point == "TOPLEFT" and pp.y or 6)
      W.medalFrom = "map window"
    elseif mapLook then
      NS.SetPiece(medalTex, "medal")
      medal:SetSize(40, 40)
      medal:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 10)
      W.medalFrom = "book"
    else
      NS.SetPiece(medalTex, "medal")
      medal:SetSize(m.medalSize, m.medalSize)
      medal:SetPoint("TOPLEFT", f, "TOPLEFT", m.medalX, -m.medalY)
      W.medalFrom = nil
    end
    title:ClearAllPoints()
    if ca then
      local sx, sy, ax, ay, AW = ArtMap()
      NS.SetFont(title, math.floor(ca.titleSize * 0.8 + 0.5), "")
      title:SetPoint("CENTER", f, "TOPLEFT", ax + AW / 2 * sx, -(ay + (61 + ca.titleDy) * sy))
      local box = art.box -- everything drawn, incl. overhanging crest/base/ornaments: left, top, right, bottom (y down)
      if f.SetClampRectInsets then f:SetClampRectInsets(box[1], box[3] - m.w, -box[2], m.h - box[4]) end
      -- the whole frame art is a drag handle: the window's mouse area grows to it (content frames above stay clickable)
      if f.SetHitRectInsets then f:SetHitRectInsets(box[1], m.w - box[3], box[2], m.h - box[4]) end
    elseif mapLook then
      local tp = A and A.title
      NS.SetFont(title, math.floor(math.max(11, math.min(15, tp and tp.size or 13)) + 0.5), "")
      title:SetPoint("CENTER", mapChrome.strip, "CENTER", 0, 0)
      if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 0, 0) end
      if f.SetHitRectInsets then f:SetHitRectInsets(0, 0, 0, 0) end
    else
      NS.SetFont(title, m.titleSize, "")
      title:SetPoint("CENTER", tb, "CENTER", 0, 0)
      if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 0, 0) end
      if f.SetHitRectInsets then f:SetHitRectInsets(0, 0, 0, 0) end
    end
    FitScale(f)
    -- footer row + close button: the previewer's class layout (inset from the frame rim) or the WoW positions
    settings:ClearAllPoints() status:ClearAllPoints() share:ClearAllPoints() exit:ClearAllPoints() close:ClearAllPoints()
    local sRight, shLeft, midY
    if ca then
      local sx, sy, ax, ay, AW, AH = ArtMap()
      local ft = ca.footer
      local x, cy = ax + ft.pad * sx, ay + (618 + AH - 680) * sy
      local widths = { 90, ft.cols[2] + (AW - 880), 90, 90 }
      local cols = { ft.cols[1], ft.cols[2] + (AW - 880), ft.cols[3], ft.cols[4] }
      for i, b in ipairs({ settings, status, share, exit }) do
        b:SetWidth(widths[i] * sx)
        b:SetPoint("LEFT", f, "TOPLEFT", x, -cy)
        if i == 1 then sRight = x + widths[1] * sx elseif i == 3 then shLeft = x end
        x = x + (cols[i] + ft.gap) * sx
      end
      midY = cy
      close:SetSize(m.closeSize, m.closeSize)
      close:SetPoint("TOPRIGHT", f, "TOPLEFT", ax + (AW - ca.close[1]) * sx, -(ay + ca.close[2] * sy))
      close:SetFrameLevel(f:GetFrameLevel() + 27)
    else
      settings:SetWidth(m.fbtnW) settings:SetPoint("TOPLEFT", f, "TOPLEFT", m.fbtnLeft, -m.fbtnY)
      share:SetWidth(m.fbtnW) share:SetPoint("TOPLEFT", f, "TOPLEFT", m.shareX, -m.fbtnY)
      exit:SetWidth(m.fbtnW) exit:SetPoint("TOPLEFT", f, "TOPLEFT", m.exitX, -m.fbtnY)
      sRight, shLeft, midY = m.fbtnLeft + m.fbtnW, m.shareX, m.fbtnY + m.fbtnH / 2
      close:SetFrameLevel(f:GetFrameLevel() + 20)
      if mapLook then
        close:SetSize(22, 22)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
      else
        close:SetSize(m.closeSize, m.closeSize)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(m.pad + m.closeRight), -(m.pad + m.closeTop))
      end
    end
    -- the close button: the map window's own close-button art (map look), else the stock UIPanelCloseButton template
    local cA = mapLook and A and A.close
    W.closeFrom = nil
    if cA and NS.MapWindow.Paint(closeTex, cA.normal) then
      if not NS.MapWindow.Paint(closeGlow, cA.highlight) then NS.MapWindow.Paint(closeGlow, cA.normal) end
      if cA.w and cA.h and cA.w >= 12 and cA.h >= 12 and cA.w <= 40 then close:SetSize(cA.w, cA.h) end
      W.closeFrom = "map window"
    else
      NS.SetPiece(closeTex, "xbtn") NS.SetPiece(closeGlow, "xbtn")
    end
    local useStock = (not W.closeFrom) and stockClose and NS.theme.stockTemplates and not ca and NS.Stock.TemplateOK("UIPanelCloseButton", "Button")
    if useStock then
      stockClose:ClearAllPoints()
      stockClose:SetPoint("CENTER", close, "CENTER", 0, 0)
      if mapLook then stockClose:SetSize(28, 28) else stockClose:SetSize(m.closeSize + 4, m.closeSize + 4) end
      stockClose:Show() close:Hide()
      W.closeFrom = W.closeFrom or "UIPanelCloseButton"
    else
      if stockClose then stockClose:Hide() end
      close:Show()
    end
    -- 0.4.4 status box, every theme: fills the gap between Settings and Share stats (same margin on both sides, so it
    -- is centred between them), tall enough for its text plus padding; the text truncates with an ellipsis only when
    -- it still does not fit.
    local gapM = 10
    local sw = math.max(40, shLeft - sRight - 2 * gapM)
    local sh = math.max(m.statusH, math.floor(m.statusSize * 1.3 + 10 + 0.5))
    status:ClearAllPoints()
    status:SetSize(sw, sh)
    status:SetPoint("LEFT", f, "TOPLEFT", sRight + gapM, -midY)
    W.statusSlice.h = sh
    W.statusSlice:Apply()
    W.statusText:SetWidth(sw - 16)
    if W.statusText.SetWordWrap then W.statusText:SetWordWrap(false) end
    W.status = status
  end)

  -- ESC closes it, the stock way (plain table insert; Blizzard reads it through securecall).
  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "DarkMatterFrame") end
  return f
end

function NS.GetWindow()
  if not frame then
    -- Build under pcall: if anything in the build errors, never leave a half-built window behind.
    local ok, err = pcall(function()
      Build()
      ApplyPosition()
      NS.SetStatus("Dark Matter " .. NS.version)
      NS.ShowTab(NS.db and NS.db.tab or "quests")
    end)
    if not ok then
      if frame then frame:Hide() end
      frame = nil
      NS.buildError = tostring(err)
      if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Dark Matter: the window could not be built:|r " .. NS.buildError)
      end
      return nil
    end
  end
  return frame
end

function NS.RefreshWindow()
  if not frame then return end
  local def = NS.tabs[W.current]
  if def and def.Refresh then pcall(def.Refresh) end
end

function NS.ToggleWindow(show)
  local f = NS.GetWindow()
  if not f then return end
  if show == nil then show = not f:IsShown() end
  if show then f:Show() else f:Hide() end
end
