-- 0.5.0 Map tab: the game's own map pictures (C_Map art tiles + explored overlays) in our own frames, with a
-- Google-Maps style wheel zoom toward the cursor from the world to a continent to its zones, drag to pan, a breadcrumb,
-- zone search, Find me + player arrow, coordinates, level badges (public data), quest markers, and full screen.
-- Taint-safe: plain frames and textures only; no WorldMapFrame access, no hooks, no protected calls, so it works in combat.
-- How the zoom works: everything is placed in WORLD coords (0..1 on the world map's art). One scale (px per world-art
-- px) and an offset make the view. Continents sit on the world at MD.Placement; zones sit on their continent at
-- GetMapRectOnMap. Each map is one layer frame of tiles moved/scaled as a unit; a continent fades in as it grows past
-- the screen width and a zone as it grows past ~half the screen, so the crossfade follows the wheel both ways.
local _, NS = ...
local UI, MD = NS.UI, NS.MapData
local CU = NS.MapCloseUp -- 0.5.1.4: the game's minimap tiles up close (MapCloseUp.lua)
local M = { layers = {}, fade = {}, pools = {}, view = { s = 1, ox = 0, oy = 0 }, layersOn = { levels = true, quests = true } }
NS.MapTab = M

local ICONS = "Interface\\AddOns\\DarkMatter\\Media\\dm-map-icons"
local I = { findme = 0, pin = 1, starpen = 2, town = 3, full = 4, back = 5, arrow = 6, quest = 7, closeup = 0 }
local function Icon(tex, key) tex:SetTexture(ICONS) tex:SetTexCoord(I[key] / 8, (I[key] + 1) / 8, 0, 1) end

local function Clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function Fmt(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end

local tab, page, root, bar, vpBox, vp, canvas, over, strip, full, empty, closeHost
local crumbs, crumbKey, search, results, coordCur, coordMe, caption
local ev, drag, lastClick, zoomT, fly
local V = M.view
local BW, BH = 1002, 668

---------------------------------------------------------------------------
-- the base picture: the world when the client has one with art, else one continent at a time
---------------------------------------------------------------------------
local function Setup()
  M.world = MD.World()
  local wa = M.world and MD.Art(M.world)
  M.conts = MD.Continents()
  if wa then
    M.hasWorld, BW, BH = true, wa.w, wa.h
  else
    M.hasWorld = false
    M.only = M.only or (MD.ContinentOf(MD.PlayerMap())) or (M.conts[1] and M.conts[1].id)
    local ca = M.only and MD.Art(M.only)
    if ca then BW, BH = ca.w, ca.h end
  end
  M.ready = M.hasWorld or (M.only ~= nil and MD.Art(M.only) ~= nil)
end
local function Place(cont)
  if M.hasWorld then return MD.Placement(cont) end
  return { 0, 1, 0, 1 }
end
local function ContList()
  if M.hasWorld then return M.conts end
  local out = {}
  for _, c in ipairs(M.conts) do if c.id == M.only then out[1] = c end end
  if #out == 0 and M.only then out[1] = { id = M.only, name = MD.Name(M.only) or "Continent" } end
  return out
end
-- map coords on a zone/continent -> world coords
local function ToW(id, x, y)
  if M.hasWorld and id == M.world then return x, y end
  local cont = id
  local z = not MD.Is(id, "continent") and MD.ZoneEntry(id)
  if z then x, y, cont = z.r[1] + x * (z.r[2] - z.r[1]), z.r[3] + y * (z.r[4] - z.r[3]), z.cont end
  local p = Place(cont)
  return p[1] + x * (p[2] - p[1]), p[3] + y * (p[4] - p[3]), cont
end
local function WorldRect(id)
  if M.hasWorld and id == M.world then return 0, 1, 0, 1 end
  local z = not MD.Is(id, "continent") and MD.ZoneEntry(id)
  if z then
    local x1, y1 = ToW(id, 0, 0)
    local x2, y2 = ToW(id, 1, 1)
    return x1, x2, y1, y2
  end
  local p = Place(id)
  return p[1], p[2], p[3], p[4]
end

---------------------------------------------------------------------------
-- view maths
---------------------------------------------------------------------------
local function VW() return math.max(1, vp and vp:GetWidth() or 1) end
local function VH() return math.max(1, vp and vp:GetHeight() or 1) end
-- 0.5.1.11: fully zoomed out the world picture COVERS the box (no empty band around it, like the stock map)
local function SFit() return math.max(VW() / BW, VH() / BH) end
local function ZMax()
  local m = 40
  for _, c in ipairs(ContList()) do local p = Place(c.id) m = math.max(m, 40 / math.max(0.05, p[2] - p[1])) end
  m = math.min(m, 250)
  -- 0.5.1.4: no deeper than twice the minimap's own sharpness (MapCloseUp MAX_PPY); past that every picture only blurs
  local cap
  for _, c in ipairs(ContList()) do
    local p = Place(c.id)
    local sMax = CU and CU.MaxScale(c.id, (p[2] - p[1]) * BW)
    if sMax then cap = math.max(cap or 0, sMax / SFit()) end
  end
  if cap then m = math.min(m, math.max(8, cap)) end
  return m
end
M.ZMax = function() return ZMax() end
-- 0.5.1.10: the scale at which map id's art just covers the view (the stock map's zone view: no edge in sight)
function M.CoverScale(id)
  local x1, x2, y1, y2 = WorldRect(id)
  if not x1 then return 0 end
  return math.max(VW() / math.max(1e-9, (x2 - x1) * BW), VH() / math.max(1e-9, (y2 - y1) * BH))
end
function M.ToScreen(wx, wy) return V.ox + wx * BW * V.s, V.oy + wy * BH * V.s end
function M.ToWorld(px, py) return (px - V.ox) / (BW * V.s), (py - V.oy) / (BH * V.s) end
function M.Center() return M.ToWorld(VW() / 2, VH() / 2) end
function M.Zoom() return V.s / SFit() end
local function SetView(cx, cy, s)
  local sf = SFit()
  V.s = Clamp(s, sf, sf * ZMax())
  -- keep the picture covering the view (centred where it is smaller than the view, e.g. fully zoomed out)
  local hw, hh = VW() / 2 / (BW * V.s), VH() / 2 / (BH * V.s)
  cx = hw >= 0.5 and 0.5 or Clamp(cx, hw, 1 - hw)
  cy = hh >= 0.5 and 0.5 or Clamp(cy, hh, 1 - hh)
  V.ox, V.oy = VW() / 2 - cx * BW * V.s, VH() / 2 - cy * BH * V.s
  M.dirty = true
end
local function ClampView() local cx, cy = M.Center() SetView(cx, cy, V.s) end

local function Cursor()
  if M.testCursor then return M.testCursor() end
  local x, y = GetCursorPosition()
  local sc = vp:GetEffectiveScale() or 1
  local l, t = vp:GetLeft(), vp:GetTop()
  if not (x and l and t) then return VW() / 2, VH() / 2 end
  return x / sc - l, t - y / sc
end
local function MouseOver() if M.testCursor then return true end return vp and vp:IsMouseOver() end

-- the continent the view is about: the one whose land holds the view centre (nearest land otherwise)
local function Focus()
  local list = ContList()
  if #list <= 1 then return list[1] and list[1].id end
  local cx, cy = M.Center()
  local best, bd
  for _, c in ipairs(list) do
    local land = MD.Land(c.id) or { 0, 1, 0, 1 }
    local p = Place(c.id)
    local x1, x2 = p[1] + land[1] * (p[2] - p[1]), p[1] + land[2] * (p[2] - p[1])
    local y1, y2 = p[3] + land[3] * (p[4] - p[3]), p[3] + land[4] * (p[4] - p[3])
    local dx = cx < x1 and x1 - cx or (cx > x2 and cx - x2 or 0)
    local dy = cy < y1 and y1 - cy or (cy > y2 and cy - y2 or 0)
    local d = dx * dx + dy * dy
    if not bd or d < bd then best, bd = c.id, d end
  end
  return best
end

-- fade-in bands (fraction of the view width the map's art covers on screen)
local function ContBand(cont)
  local p = Place(cont)
  local lo = math.max(0.55, (p[2] - p[1]) * 1.15)
  return lo, lo + 0.35
end
local ZONE_LO, ZONE_HI = 0.40, 0.70
local ZONE_DRAW = { 0.40, 0.55 } -- 0.5.1.11: zone pictures fade in over the continent picture (largest zone's share of the view)
M.ZONE_DRAW = ZONE_DRAW
function M.ContAlpha(cont)
  if not M.hasWorld then return 1 end
  local p = Place(cont)
  -- how much of the view the continent fills: the larger of its width and height share
  local frac = math.max((p[2] - p[1]) * BW * V.s / VW(), (p[4] - p[3]) * BH * V.s / VH())
  local lo, hi = ContBand(cont)
  return Smooth((frac - lo) / (hi - lo)) * (M.fade[cont] or 0)
end
-- 0.5.1.7: every zone picture of a continent is drawn fading in TOGETHER (by the continent's largest zone), so a continent seen whole
-- does not turn into a patchwork of zone pictures at different strengths
function M.ZoneAlpha(z)
  local p = Place(z.cont)
  -- width or height share, whichever is larger (a tall zone in a wide view still fades in when fitted)
  local frac = math.max((z.r[2] - z.r[1]) * (p[2] - p[1]) * BW * V.s / VW(), (z.r[4] - z.r[3]) * (p[4] - p[3]) * BH * V.s / VH())
  return Smooth((frac - ZONE_LO) / (ZONE_HI - ZONE_LO)) * M.ContAlpha(z.cont)
end
-- how strongly a zone's picture is DRAWN (the breadcrumb and focus keep ZoneAlpha)
-- 0.5.1.11: all of a continent's zone pictures fade in TOGETHER over the continent picture, keyed to the share of the view
-- the continent's largest zone fills (ZONE_DRAW); the continent picture always stays underneath as the base
function M.ArtMag(id, worldW)
  local a = MD.Art(id)
  return a and a.w > 0 and worldW * BW * V.s / a.w or 0
end
function M.ContMag(cont) local p = Place(cont) return M.ArtMag(cont, p[2] - p[1]) end
M.zoneSpan = {}
local function ZoneSpan(cont)
  local s = M.zoneSpan[cont]
  if s then return s[1], s[2] end
  local w, h = 0, 0
  for _, z in ipairs(MD.Zones(cont)) do w, h = math.max(w, z.r[2] - z.r[1]), math.max(h, z.r[4] - z.r[3]) end
  M.zoneSpan[cont] = { w, h }
  return w, h
end
function M.ZoneDrawAlpha(z)
  local p = Place(z.cont)
  local zw, zh = ZoneSpan(z.cont)
  local frac = math.max(zw * (p[2] - p[1]) * BW * V.s / VW(), zh * (p[4] - p[3]) * BH * V.s / VH())
  return Smooth((frac - ZONE_DRAW[1]) / (ZONE_DRAW[2] - ZONE_DRAW[1])) * M.ContAlpha(z.cont)
end

---------------------------------------------------------------------------
-- layers: one frame per map, holding its tiles + explored overlays (built the first time it is on screen)
---------------------------------------------------------------------------
-- 0.5.1.6: a zone's picture (and its explored overlays) fades out over its outer FEATHER px, so zones drawn side by side
-- on the continent and over the continent picture leave no rectangular edge. A piece inside that rim is one texture; a
-- piece reaching into it is cut into 4 x 4 cells whose alpha ramps to 0 at the picture's edge (vertex gradients).
local FEATHER = 64
local function S01(t) if t <= 0 then return 0 elseif t >= 1 then return 1 end return t * t * (3 - 2 * t) end
local function EdgeW(a, x, y) return S01(math.min(x, y, a.w - x, a.h - y) / FEATHER) end
M.EdgeW = EdgeW
local function Piece(L, fid, layer, x, y, w, h, u2, v2, list)
  local a, f = L.art, L.frame
  local function New(px, py, pw, ph, u1, uu2, v1, vv2)
    local t = f:CreateTexture(nil, layer)
    t:SetSize(pw, ph)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", px, -py)
    t:SetTexture(fid, nil, nil, "TRILINEAR")
    t:SetTexCoord(u1, uu2, v1, vv2)
    list[#list + 1] = t
    return t
  end
  if not L.feather or (x >= FEATHER and y >= FEATHER and x + w <= a.w - FEATHER and y + h <= a.h - FEATHER) then
    New(x, y, w, h, 0, u2, 0, v2)
    return
  end
  local n = 4
  for r = 0, n - 1 do
    for c = 0, n - 1 do
      local cx, cy, cw, ch = x + c * w / n, y + r * h / n, w / n, h / n
      local w00, w10, w01, w11 = EdgeW(a, cx, cy), EdgeW(a, cx + cw, cy), EdgeW(a, cx, cy + ch), EdgeW(a, cx + cw, cy + ch)
      if w00 + w10 + w01 + w11 > 0.001 then
        local t = New(cx, cy, cw, ch, c / n * u2, (c + 1) / n * u2, r / n * v2, (r + 1) / n * v2)
        local o, a1, a2 = CU.CornerGrad(w00, w10, w01, w11)
        CU.Grad(t, o, a1, a2, 1, 1, 1)
        t.dmEdge = true
      end
    end
  end
end
local function BuildTiles(L)
  local a = L.art
  for i, fid in ipairs(a.tex) do
    local col, row = (i - 1) % a.cols, math.floor((i - 1) / a.cols)
    local x, y = col * a.tw, row * a.th
    local w, h = math.min(a.tw, a.w - x), math.min(a.th, a.h - y)
    if w > 0 and h > 0 then Piece(L, fid, "BACKGROUND", x, y, w, h, w / a.tw, h / a.th, L.tiles) end
  end
end
-- explored overlays, laid out exactly like the game's own map (MapExplorationPinMixin): tiles of 256; the number of
-- tiles from the overlay's size (ceil(size / 256), not the entry's numTextures fields); the last row/column cut to
-- the overlay size inside a power-of-two file (16, 32, ... 256), so one texel is one map pixel everywhere.
-- 0.5.1.10: a pure function (tested) returning { fid, x, y, w, h, fileW, fileH } per tile
function M.OverlayTiles(e, TW, TH)
  TW, TH = TW or 256, TH or 256
  local out = {}
  local ow, oh = tonumber(e.textureWidth) or 0, tonumber(e.textureHeight) or 0
  local ox, oy = tonumber(e.offsetX) or 0, tonumber(e.offsetY) or 0
  if ow <= 0 or oh <= 0 or type(e.fileDataIDs) ~= "table" then return out end
  local nw, nt = math.ceil(ow / TW), math.ceil(oh / TH)
  for j = 1, nt do
    local ph, fh = TH, TH
    if j == nt then
      ph = oh % TH if ph == 0 then ph = TH end
      fh = 16 while fh < ph do fh = fh * 2 end
    end
    for k = 1, nw do
      local pw, fw = TW, TW
      if k == nw then
        pw = ow % TW if pw == 0 then pw = TW end
        fw = 16 while fw < pw do fw = fw * 2 end
      end
      local fid = e.fileDataIDs[(j - 1) * nw + k]
      if fid then out[#out + 1] = { fid, ox + TW * (k - 1), oy + TH * (j - 1), pw, ph, fw, fh } end
    end
  end
  return out
end
local function BuildOverlays(L)
  for _, t in ipairs(L.ov) do t:Hide() end
  L.ov = {}
  local list = MD.Explored(L.id)
  if not list then return end
  for _, e in ipairs(list) do
    for _, q in ipairs(M.OverlayTiles(e, L.art.tw, L.art.th)) do
      Piece(L, q[1], "ARTWORK", q[2], q[3], q[4], q[5], q[4] / q[6], q[5] / q[7], L.ov)
    end
  end
  L.ovBuilt = true
end
local function Layer(id, level)
  local L = M.layers[id]
  if L then return L end
  local art = MD.Art(id)
  if not art then return nil end
  local f = CreateFrame("Frame", nil, canvas)
  f:SetSize(art.w, art.h)
  f:SetFrameLevel(canvas:GetFrameLevel() + level)
  f:Hide()
  L = { id = id, art = art, frame = f, tiles = {}, ov = {}, built = false, level = level }
  -- 0.5.1.6: zone pictures are feathered at their rim; 0.5.1.7: continent pictures too when the world picture lies under
  -- them (the world picture is the base and is never feathered)
  L.feather = CU and CU.CornerGrad and id ~= M.world and (M.hasWorld or not MD.Is(id, "continent")) or false
  M.layers[id] = L
  return L
end
-- place a layer whose art covers world rect (x1..x2, y1..y2) at alpha a (hidden when off screen or invisible)
local function Show(L, x1, x2, y1, y2, a)
  local l, t = M.ToScreen(x1, y1)
  local r, b = M.ToScreen(x2, y2)
  if a < 0.01 or r < 0 or b < 0 or l > VW() or t > VH() then L.frame:Hide() L.shown = false return false end
  -- 0.5.1.11: while dragging, at most one picture is built per frame (the base under it shows meanwhile), so a drag
  -- never stalls on building a zone's tiles and overlays
  if M.buildBudget and (not L.built or (not L.ovBuilt and L.wantOv)) then
    if M.buildBudget <= 0 then L.frame:Hide() L.shown = false M.dirty = true return false end
    M.buildBudget = M.buildBudget - 1
  end
  if not L.built then BuildTiles(L) L.built = true end
  if not L.ovBuilt and L.wantOv then BuildOverlays(L) end
  local sc = (r - l) / L.art.w
  L.frame:SetScale(math.max(sc, 0.0001))
  L.frame:ClearAllPoints()
  L.frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", l / sc, -t / sc)
  L.frame:SetAlpha(a)
  L.frame:Show()
  L.shown, L.alpha = true, a
  L.sc, L.box = sc, { l, t, r, b } -- 0.5.1.8: screen px per art texel, and where it is on screen
  return true
end

---------------------------------------------------------------------------
-- overlay: player arrow, level badges, quest markers (unscaled, labels on solid plates)
---------------------------------------------------------------------------
local function Pool(name, make)
  local p = M.pools[name] or { n = 0 }
  M.pools[name] = p
  p.n = p.n + 1
  if not p[p.n] then p[p.n] = make() end
  return p[p.n]
end
local function PoolReset(name) local p = M.pools[name] if p then p.n = 0 end end
local function PoolHideRest(name)
  local p = M.pools[name]
  if not p then return end
  for i = p.n + 1, #p do p[i]:Hide() end
end
local function MakeBadge()
  local b = CreateFrame("Frame", nil, over)
  b:SetSize(44, 18)
  b.plate = b:CreateTexture(nil, "BACKGROUND")
  b.plate:SetAllPoints(b)
  b.plate:SetColorTexture(0.06, 0.05, 0.035, 0.9)
  b.edge = b:CreateTexture(nil, "BORDER")
  b.edge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.edge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.edge:SetHeight(1)
  b.edge:SetColorTexture(1, 0.82, 0.25, 0.8)
  b.text = b:CreateFontString(nil, "OVERLAY")
  NS.SetFont(b.text, 11, "")
  b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.text:SetTextColor(1, 0.84, 0.3, 1)
  return b
end
-- 0.5.2a quest markers: the game's own quest icons (QuestState.lua: grey ? in progress, yellow ? ready to turn in),
-- clickable. Hover highlights the quest's row in the Quests tab (and a row's hover highlights its markers here); click
-- selects the quest there and flies to it; shift-click sets the game's waypoint + arrow. A press that turns into a drag
-- still pans the map (the press is handed to the map).
local QuestClick -- forward (assigned below)
local function MakeQuest()
  local q = CreateFrame("Button", nil, over)
  q:SetSize(18, 18)
  q.glow = q:CreateTexture(nil, "BACKGROUND")
  q.glow:SetPoint("CENTER", q, "CENTER", 0, 0)
  q.glow:SetSize(32, 32)
  q.glow:SetBlendMode("ADD")
  q.glow:SetAlpha(0.55)
  q.glow:Hide()
  q.icon = q:CreateTexture(nil, "ARTWORK")
  q.icon:SetAllPoints(q)
  q:SetScript("OnEnter", function(self)
    if NS.QS then NS.QS.Hover(self.qid, "map") end
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(MD.QuestTitle(self.qid), 1, 0.82, 0)
    local st = self.status
    GameTooltip:AddLine(st == "ready" and "Ready to turn in" or (st == "failed" and "Failed" or "In progress"), 0.85, 0.85, 0.85, true)
    if NS.QL and NS.QL.Objectives then
      local ok, objs = pcall(NS.QL.Objectives, { questID = self.qid })
      if ok and type(objs) == "table" then
        for _, o in ipairs(objs) do if type(o.text) == "string" then GameTooltip:AddLine((o.done and "\226\156\147 " or "- ") .. o.text, o.done and 0.5 or 1, o.done and 0.9 or 1, o.done and 0.5 or 1, true) end end
      end
    end
    GameTooltip:AddLine("Click: select it in the Quests tab", 0.5, 0.8, 1)
    GameTooltip:AddLine("Shift-click: the game's waypoint and arrow", 0.5, 0.8, 1)
    GameTooltip:Show()
  end)
  q:SetScript("OnLeave", function()
    if NS.QS then NS.QS.Hover(nil, "map") end
    if GameTooltip then GameTooltip:Hide() end
  end)
  q:SetScript("OnMouseDown", function(_, btn) if M.VpDown then M.VpDown(btn) end end)
  q:SetScript("OnMouseUp", function(self, btn)
    if btn == "LeftButton" and drag and not drag.moved then
      drag = nil
      QuestClick(self)
      return
    end
    if M.VpUp then M.VpUp(btn) end
  end)
  return q
end

local function UpdatePlayer()
  local wx, wy = nil, nil
  local m = MD.PlayerMap()
  local cont = m and MD.ContinentOf(m)
  if cont and (M.hasWorld or cont == M.only) then
    local x, y = MD.PlayerPos(cont)
    if not x then
      local z = MD.ZoneOf(m) or m
      local zx, zy = MD.PlayerPos(z)
      if zx then wx, wy = ToW(z, zx, zy) end
    else
      local p = Place(cont)
      wx, wy = p[1] + x * (p[2] - p[1]), p[3] + y * (p[4] - p[3])
    end
  end
  M.player = wx and { wx, wy, cont = cont, map = m } or nil
  local a = M.arrow
  if not a then return end
  if not wx then a:Hide() return end
  local px, py = M.ToScreen(wx, wy)
  if px < -12 or py < -12 or px > VW() + 12 or py > VH() + 12 then a:Hide() return end
  a:ClearAllPoints()
  a:SetPoint("CENTER", over, "TOPLEFT", px, -py)
  local face = type(GetPlayerFacing) == "function" and select(2, pcall(GetPlayerFacing))
  if type(face) == "number" and a.SetRotation then pcall(a.SetRotation, a, face) end
  a:Show()
end

local function LayoutOverlay()
  PoolReset("badge") PoolReset("quest")
  local vw, vh = VW(), VH()
  local anyBadge = false
  for _, c in ipairs(ContList()) do
    local ca = M.ContAlpha(c.id)
    if ca > 0.5 then
      for _, z in ipairs(MD.Zones(c.id)) do
        local x1, x2, y1, y2 = WorldRect(z.id)
        local l, t = M.ToScreen(x1, y1)
        local r, b = M.ToScreen(x2, y2)
        local w = r - l
        local cx, cy = (l + r) / 2, (t + b) / 2
        local lv = NS.ZoneLevelText(z.name)
        -- a badge (about 40 px) shows when its zone is wide enough to hold it and not yet filling the view
        if lv and M.layersOn.levels and w >= 46 and w <= vw * 0.85 and cx > 20 and cx < vw - 60 and cy > 14 and cy < vh - 40 then
          local bd = Pool("badge", MakeBadge)
          bd.zone = z.name
          bd.text:SetText(lv)
          bd:SetWidth(math.max(34, (bd.text:GetStringWidth() or 30) + 14))
          bd:ClearAllPoints()
          bd:SetPoint("CENTER", over, "TOPLEFT", cx, -cy)
          bd:Show()
          anyBadge = true
        end
        if M.layersOn.quests and M.ZoneAlpha(z) > 0.6 then
          for _, q in ipairs(MD.Quests(z.id) or {}) do
            local qx, qy = M.ToScreen(ToW(z.id, q.x, q.y))
            if qx > 0 and qy > 0 and qx < vw and qy < vh then
              local QS = NS.QS
              local role, status = "progress", "progress"
              if QS then role, status = QS.MarkerRole(q.id) end
              local mk = Pool("quest", MakeQuest)
              -- 0.5.2a: the game's own icon for the quest's status; a client without it draws no marker (/dm questmap)
              if QS and QS.PaintIcon(mk.icon, role) then
                QS.PaintIcon(mk.glow, role)
                mk.qid, mk.status, mk.map, mk.mx, mk.my = q.id, status, z.id, q.x, q.y
                mk.wx, mk.wy = ToW(z.id, q.x, q.y)
                mk.icon:SetVertexColor(1, 1, 1) -- 0.5.2a.1: the game icon as it is (no tint), like the game map
                local hot = QS.IsHot(q.id)
                mk:SetSize(hot and 24 or 18, hot and 24 or 18)
                if hot then mk.glow:Show() else mk.glow:Hide() end
                mk:SetFrameLevel(over:GetFrameLevel() + (hot and 3 or 1))
                mk:ClearAllPoints()
                mk:SetPoint("CENTER", over, "TOPLEFT", qx, -qy)
                mk:Show()
              else
                mk.qid = nil
                mk:Hide()
              end
            end
          end
        end
      end
    end
  end
  PoolHideRest("badge") PoolHideRest("quest")
  if M.DrawUserPins then M.DrawUserPins() end
  if caption then if anyBadge then caption:Show() else caption:Hide() end end
end
-- 0.5.1.7: map pictures on screen: total, feathered at their rim, the world base, and hard-edged ones (mapprobe 21)
function M.SeamReport()
  local shown, fe, base, hard = 0, 0, 0, 0
  for id, L in pairs(M.layers) do
    if L.shown then
      shown = shown + 1
      if L.feather then fe = fe + 1
      elseif id == M.world or (not M.hasWorld and MD.Is(id, "continent")) then base = base + 1
      else hard = hard + 1 end
    end
  end
  return shown, fe, base, hard
end

-- 0.5.1.8: how magnified the map art under the middle of the view is (screen px per art texel): the top-most map
-- picture there that is shown at full strength (a city map over its zone, a zone over its continent). The close-up
-- tiles come in only when THAT art starts to blur. nil when no picture covers the middle.
function M.RefMag()
  local cx, cy = VW() / 2, VH() / 2
  local best
  for _, L in pairs(M.layers) do
    local b = L.box
    if L.shown and (L.alpha or 0) > 0.5 and b and cx >= b[1] and cx <= b[3] and cy >= b[2] and cy <= b[4] then
      local lv = L.level or 0
      if not best or lv > best.level or (lv == best.level and (b[3] - b[1]) < (best.box[3] - best.box[1])) then
        best = { level = lv, box = b, sc = L.sc, id = L.id }
      end
    end
  end
  M.ref = best
  return best and best.sc or nil
end

---------------------------------------------------------------------------
-- breadcrumb + coordinates
---------------------------------------------------------------------------
local FlyTo -- forward (assigned below)
local Crumbs
local function Trail()
  local out = {}
  if M.hasWorld then out[#out + 1] = { id = M.world, name = MD.Name(M.world) or "World", world = true } end
  local f = M.focus
  if f and (M.ContAlpha(f) > 0.5 or not M.hasWorld) then
    out[#out + 1] = { id = f, name = MD.Name(f) or "Continent" }
    local cx, cy = M.Center()
    local p = Place(f)
    local x, y = (cx - p[1]) / (p[2] - p[1]), (cy - p[3]) / (p[4] - p[3])
    local z = MD.ZoneAt(f, x, y)
    -- a city's rect sits inside its zone: while the city is still faded out, the trail names the zone you see
    if not (z and M.ZoneAlpha(z) > 0.5) then
      z = nil
      for _, e in ipairs(MD.Zones(f)) do
        local r = e.r
        if x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4] and M.ZoneAlpha(e) > 0.5 and (not z or e.area < z.area) then z = e end
      end
    end
    if z then out[#out + 1] = { id = z.id, name = z.name } end
  end
  return out
end
function M.Trail() local t = Trail() local n = {} for i, s in ipairs(t) do n[i] = s.name end return n end

local function UpdateCoords()
  local cur = "--"
  if MouseOver() then
    local px, py = Cursor()
    local wx, wy = M.ToWorld(px, py)
    local f = M.focus
    if f and (M.ContAlpha(f) > 0.5 or not M.hasWorld) then
      local p = Place(f)
      local cx, cy = (wx - p[1]) / (p[2] - p[1]), (wy - p[3]) / (p[4] - p[3])
      local z, zx, zy = MD.ZoneAt(f, cx, cy)
      if z then cur = z.name .. "  " .. Fmt(zx, zy)
      elseif cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then cur = (MD.Name(f) or "") .. "  " .. Fmt(cx, cy) end
    elseif wx >= 0 and wx <= 1 and wy >= 0 and wy <= 1 then
      cur = (MD.Name(M.world) or "World") .. "  " .. Fmt(wx, wy)
    end
  end
  M.coordText = cur
  local me = "Player  --"
  local pm = MD.PlayerMap()
  local x, y = MD.PlayerPos(pm)
  if x then me = "Player  " .. Fmt(x, y) end
  M.playerText = me
  if coordCur then
    coordCur.text:SetText(cur)
    coordMe.text:SetText(me)
    coordCur:SetWidth(math.max(70, (coordCur.text:GetStringWidth() or 60) + 22))
    coordMe:SetWidth(math.max(70, (coordMe.text:GetStringWidth() or 60) + 22))
  end
end

---------------------------------------------------------------------------
-- the frame: lay out every visible layer for the current view
---------------------------------------------------------------------------
-- 0.5.1.9: at zone view ONE zone picture is drawn, like the game's map: the zone under the middle of the view (with its
-- explored overlays), over the continent picture. Its neighbours fade out as it fills the view (SOLO: its share of the
-- view) and only come back at continent zoom, all together. A city's own picture (Ironforge, Stormwind City...) is never
-- drawn over its zone; only when the city itself is the focus (the middle of the view on it and the city filling CITY
-- of the view) it fades in, cleanly, on top.
local SOLO = { 0.55, 0.70 }
local CITY = { 0.45, 0.60 }
M.SOLO, M.CITY = SOLO, CITY
local function IsCity(z) return z.area < 0.004 end
M.IsCity = IsCity
-- 0.5.1.11: the share of the view the zone actually covers (so dragging off it brings its neighbours back in)
local function Frac(z)
  local p = Place(z.cont)
  local l, t = M.ToScreen(p[1] + z.r[1] * (p[2] - p[1]), p[3] + z.r[3] * (p[4] - p[3]))
  local r, b = M.ToScreen(p[1] + z.r[2] * (p[2] - p[1]), p[3] + z.r[4] * (p[4] - p[3]))
  local w = math.max(0, math.min(r, VW()) - math.max(l, 0))
  local h = math.max(0, math.min(b, VH()) - math.max(t, 0))
  return w * h / (VW() * VH())
end
M.Frac = Frac
local function Inside(r, x, y) return x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4] end
-- the zone (never a city) and the city under the middle of the view, on continent cont
function M.FocusZones(cont)
  if not cont then return nil, nil end
  local cx, cy = M.Center()
  local p = Place(cont)
  local x, y = (cx - p[1]) / (p[2] - p[1]), (cy - p[3]) / (p[4] - p[3])
  local z = MD.ZoneAt(cont, x, y)
  local city
  if z and IsCity(z) then
    city = z
    local mx, my, best = (z.r[1] + z.r[2]) / 2, (z.r[3] + z.r[4]) / 2, nil
    for _, e in ipairs(MD.Zones(cont)) do
      if not IsCity(e) and Inside(e.r, mx, my) and (not best or e.area < best.area) then best = e end
    end
    z = best
  end
  if z and IsCity(z) then z = nil end
  return z, city
end

function M.Layout()
  M.dirty = false
  M.buildBudget = drag and 1 or nil
  if not M.ready then return end
  M.focus = Focus()
  -- world picture underneath
  local covered = false
  if M.hasWorld then
    local L = Layer(M.world, 1)
    for _, c in ipairs(ContList()) do
      local p = Place(c.id)
      local l, t = M.ToScreen(p[1], p[3])
      local r, b = M.ToScreen(p[2], p[4])
      -- 0.5.1.11: covered only where the continent is at full strength: inside its feathered rim
      local art = MD.Art(c.id)
      local fe = art and art.w > 0 and FEATHER * (r - l) / art.w or 0
      if M.ContAlpha(c.id) >= 0.999 and l + fe <= 0 and t + fe <= 0 and r - fe >= VW() and b - fe >= VH() then covered = true end
    end
    -- 0.5.1.11: the world picture is the base wherever the continents do not cover the view (any magnification)
    if L then if covered then L.frame:Hide() L.shown = false else Show(L, 0, 1, 0, 1, 1) end end
  end
  local fz, city = M.FocusZones(M.focus)
  M.focusZone, M.focusCity = fz and fz.id, city and city.id
  local solo = fz and Smooth((Frac(fz) - SOLO[1]) / (SOLO[2] - SOLO[1])) or 0
  local cityA = city and Smooth((Frac(city) - CITY[1]) / (CITY[2] - CITY[1])) or 0
  M.solo, M.cityA = solo, cityA
  local base = canvas:GetFrameLevel()
  for _, c in ipairs(ContList()) do
    local cl = Layer(c.id, 2)
    local a = M.ContAlpha(c.id)
    -- 0.5.1.11: the continent picture is always drawn (the base under its zones, at any magnification)
    if cl then local p = Place(c.id) Show(cl, p[1], p[2], p[3], p[4], a) end
    for _, z in ipairs(MD.Zones(c.id)) do
      local isCity, isFocus = IsCity(z), fz and z.id == fz.id
      local lv = isCity and 5 or (isFocus and 4 or 3)
      local zl = Layer(z.id, lv)
      if zl then
        zl.wantOv = true
        if zl.level ~= lv then zl.level = lv zl.frame:SetFrameLevel(base + lv) end
        local d = a > 0 and M.ZoneDrawAlpha(z) or 0
        if isCity then d = (city and z.id == city.id) and d * cityA or 0
        elseif not isFocus then d = d * (1 - solo) end
        local x1, x2, y1, y2 = WorldRect(z.id)
        Show(zl, x1, x2, y1, y2, d)
      end
    end
  end
  -- 0.5.1.4: the game's minimap tiles over the zones when zoomed in (0.5.1.5: blended across the whole view, feathered where the tiles end), then the paper grain
  if CU and closeHost then
    local cl = {}
    for _, c in ipairs(ContList()) do cl[#cl + 1] = { id = c.id, alpha = M.ContAlpha(c.id) } end
    M.close = CU.Layout({ host = closeHost, conts = cl, place = Place, toScreen = M.ToScreen, vw = VW(), vh = VH(), mag = M.RefMag() })
  end
  LayoutOverlay()
  UpdatePlayer()
  if Crumbs then Crumbs() end
  local cx, cy = M.Center()
  M.lastView = { cx = cx, cy = cy, z = M.Zoom(), w = VW(), h = VH() }
  if NS.db and NS.db.map then NS.db.map.view = { cx = cx, cy = cy, z = M.lastView.z } end
end

---------------------------------------------------------------------------
-- motion: wheel zoom to the cursor, drag, fly-to
---------------------------------------------------------------------------
function M.Wheel(delta)
  if not M.ready then return end
  M.pendingFit = nil
  local px, py = Cursor()
  local u, v = M.ToWorld(px, py)
  local base = zoomT and zoomT.s or V.s
  local sf = SFit()
  zoomT = { s = Clamp(base * (1.35 ^ delta), sf, sf * ZMax()), u = u, v = v, px = px, py = py }
  fly = nil
end
function M.ZoomAt(px, py, factor)
  M.pendingFit = nil
  local u, v = M.ToWorld(px, py)
  local sf = SFit()
  zoomT = { s = Clamp(V.s * factor, sf, sf * ZMax()), u = u, v = v, px = px, py = py }
  fly = nil
end
-- fly to a map (fits it) or, with wx/wy, centre on that world point at the map's fit
-- 0.5.2a: hop = a smooth "zoom out, pan, zoom in" (Show on map, a quest marker click); sMin = never end wider than this
FlyTo = function(id, wx, wy, hop, sMin)
  if not M.ready or not id then return end
  M.pendingFit = nil
  if not M.hasWorld then
    local cont = MD.Is(id, "continent") and id or MD.ContinentOf(id)
    if cont and cont ~= M.only and MD.Art(cont) then
      M.only = cont
      Setup()
      for _, L in pairs(M.layers) do L.frame:Hide() end
    end
  end
  local x1, x2, y1, y2 = WorldRect(id)
  if not x1 then return end
  local s
  if M.hasWorld and id == M.world then s = SFit()
  else
    s = 0.94 * math.min(VW() / ((x2 - x1) * BW), VH() / ((y2 - y1) * BH))
    -- 0.5.1.10: a zone or city fills the view (cover); 0.5.1.11: the framing only, the view stays free to drag
    if not MD.Is(id, "continent") then s = M.CoverScale(id) end
    if MD.Is(id, "continent") then
      local _, hi = ContBand(id)
      s = math.max(s, (hi + 0.02) * VW() / ((x2 - x1) * BW))
    end
  end
  if sMin and s < sMin then s = sMin end
  local cx, cy = M.Center()
  fly = { t = 0, dur = 0.45, c0 = { cx, cy }, s0 = V.s, c1 = { wx or (x1 + x2) / 2, wy or (y1 + y2) / 2 }, s1 = s }
  if hop then
    -- out far enough to see where you are and where you go (never past the whole world), across, then in
    local dxp = math.abs(fly.c1[1] - cx) * BW
    local dyp = math.abs(fly.c1[2] - cy) * BH
    local sm = math.min(V.s, s, 0.8 * math.min(VW() / math.max(dxp, 1e-6), VH() / math.max(dyp, 1e-6)))
    sm = math.max(sm, SFit())
    fly.dip = math.max(0, (math.log(V.s) + math.log(s)) / 2 - math.log(sm))
    fly.hop = true
    fly.dur = 0.8 + math.min(0.6, fly.dip * 0.2)
  end
  zoomT = nil
  M.flyTarget = id
end
M.FlyTo = function(...) return FlyTo(...) end

function M.FindMe()
  UpdatePlayer()
  local p = M.player
  if not p then NS.SetStatus("Find me: the game gives no position here (instance or loading).") return false end
  local z = MD.ZoneOf(p.map) or p.map
  if not MD.ZoneEntry(z) then z = p.cont end
  if M.hasWorld then M.fade[p.cont] = M.fade[p.cont] or 0 end
  FlyTo(z, p[1], p[2])
  return true
end

---------------------------------------------------------------------------
-- 0.5.2a quests on the map: Show on map (Quests tab), a marker click, the "no map location" note
---------------------------------------------------------------------------
-- world coords of a point on any map the game gives (a zone, a continent, or a city/cave inside a zone)
local function WorldOf(map, x, y)
  if (M.hasWorld and map == M.world) or MD.Is(map, "continent") or MD.ZoneEntry(map) then return ToW(map, x, y) end
  local z = MD.ZoneOf(map)
  local x1, x2, y1, y2 = MD.Rect(map, z)
  if z and x1 then return ToW(z, x1 + x * (x2 - x1), y1 + y * (y2 - y1)) end
  local c = MD.ContinentOf(map)
  x1, x2, y1, y2 = MD.Rect(map, c)
  if c and x1 then return ToW(c, x1 + x * (x2 - x1), y1 + y * (y2 - y1)) end
end
-- the map our view frames for a map id: its zone when it has one we draw, else its continent
local function FrameId(map)
  local z = MD.ZoneOf(map) or map
  if MD.ZoneEntry(z) then return z end
  return MD.ContinentOf(map) or map
end
M.WorldOf, M.FrameId = WorldOf, FrameId

---------------------------------------------------------------------------
-- 0.5.2b your own pins: the Drop a pin tool, then a click on the map drops one there (saved in DarkMatterDB.userPins)
-- and points the game's waypoint and minimap arrow at it. Drawn with the game's own map pin icon only (nothing drawn
-- on a client without it). A pin click points the arrow there again; right-click removes it.
---------------------------------------------------------------------------
M.USER_PIN_MAX = 50
local function UserPins()
  if not NS.db then return {} end
  if type(NS.db.userPins) ~= "table" then NS.db.userPins = {} end
  return NS.db.userPins
end
M.UserPins = UserPins
function M.SetPinMode(on)
  M.pinMode = on and true or nil
  local b = M.pinBtn
  if b then
    if on then b.icon:SetVertexColor(1, 0.82, 0.25) else b.icon:SetVertexColor(0.93, 0.89, 0.8) end
  end
  if on then NS.SetStatus("Drop a pin: click the map where you want it (click the tool again to cancel).") end
end
local function PointPin(p)
  local QS = NS.QS
  if not (QS and p) then return false end
  local ok, why = QS.SetWaypoint(p.map, p.x, p.y)
  NS.SetStatus("Your pin in " .. tostring(MD.Name(p.map) or "?") .. ": " .. (ok and why or ("no waypoint: " .. tostring(why))))
  return ok
end
M.PointPin = PointPin
-- drop a pin at view point (px, py): the zone under it (the game's own answer first), zone coords. Returns the pin or nil.
function M.DropPin(px, py)
  local wx, wy = M.ToWorld(px, py)
  local pin
  for _, c in ipairs(ContList()) do
    local p = Place(c.id)
    local cx, cy = (wx - p[1]) / (p[2] - p[1]), (wy - p[3]) / (p[4] - p[3])
    if cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
      local z, zx, zy = MD.ZoneAt(c.id, cx, cy)
      if z then pin = { map = z.id, x = zx, y = zy } break end
    end
  end
  M.SetPinMode(false)
  if not pin then
    M.Note("No zone under that point: pins go on a zone of the map.")
    return nil
  end
  local list = UserPins()
  list[#list + 1] = pin
  while #list > M.USER_PIN_MAX do table.remove(list, 1) end
  PointPin(pin)
  M.dirty = true
  return pin
end
function M.RemovePin(p)
  local list = UserPins()
  for i = #list, 1, -1 do if list[i] == p then table.remove(list, i) end end
  NS.SetStatus("Pin removed.")
  M.dirty = true
end
local function MakeUserPin()
  local b = CreateFrame("Button", nil, over)
  b:SetSize(20, 20)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.pin) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Your pin", 1, 0.82, 0)
    GameTooltip:AddLine(string.format("%s (%.1f, %.1f)", tostring(MD.Name(self.pin.map) or "?"), self.pin.x * 100, self.pin.y * 100), 1, 1, 1)
    GameTooltip:AddLine("Click: the game's waypoint and arrow", 0.5, 0.8, 1)
    GameTooltip:AddLine("Right-click: remove", 0.5, 0.8, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" and M.VpDown then M.VpDown(btn) end end)
  b:SetScript("OnMouseUp", function(self, btn)
    if btn == "RightButton" then if self.pin then M.RemovePin(self.pin) end return end
    if btn == "LeftButton" and drag and not drag.moved then
      drag = nil
      PointPin(self.pin)
      return
    end
    if M.VpUp then M.VpUp(btn) end
  end)
  return b
end
function M.DrawUserPins()
  PoolReset("upin")
  local QS = NS.QS
  local vw, vh = VW(), VH()
  for _, p in ipairs(UserPins()) do
    local wx, wy = WorldOf(p.map, p.x, p.y)
    if wx then
      local sx, sy = M.ToScreen(wx, wy)
      if sx > 0 and sy > 0 and sx < vw and sy < vh then
        local b = Pool("upin", MakeUserPin)
        if QS and QS.PaintIcon(b.icon, "userPin") then
          b.pin = p
          b:SetFrameLevel(over:GetFrameLevel() + 4)
          b:ClearAllPoints()
          b:SetPoint("BOTTOM", over, "TOPLEFT", sx, -sy) -- the pin's point sits on the spot
          b:Show()
        else
          b.pin = nil
          b:Hide()
        end
      end
    end
  end
  PoolHideRest("upin")
end

-- a themed note across the top of the map (our own plate: the theme's pane border on a dark plate); click or 8 s hides it
local note
function M.Note(text)
  if not vpBox then return end
  if not note then
    note = CreateFrame("Button", nil, vpBox)
    note:SetFrameLevel(canvas:GetFrameLevel() + 30)
    note:SetSize(420, 46)
    note:SetPoint("TOP", vp, "TOP", 0, -10)
    local bg = note:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(note)
    bg:SetColorTexture(0.03, 0.03, 0.03, 0.88)
    UI.NineSlice(note, "pane", 4, "BORDER", 1)
    note.text = UI.Text(note, "OVERLAY", 12, "gold", "CENTER")
    note.text:SetPoint("CENTER", note, "CENTER", 0, 0)
    note.text:SetWidth(396)
    note:SetScript("OnClick", function(self) self:Hide() end)
  end
  note.text:SetText(text or "")
  note:SetHeight(math.max(46, (NS.Num(note.text:GetStringHeight()) or 14) + 22))
  note.left = 8
  note:Show()
  M.note = note
end
function M.HideNote() if note then note:Hide() end end

-- fly smoothly to a quest (zoom out, pan, zoom in): its location when the game gives one, else its zone with the note.
-- wp: also set the game's waypoint + arrow there. Returns what it did ("point", "zone" or "none").
function M.ShowQuest(q, wp)
  local QS = NS.QS
  if not (QS and q) then return "none" end
  if not M.ready or VW() < 50 or VH() < 50 then M.pendingQuest = { q = q, wp = wp } return "pending" end
  MD.Forget("quests")
  local title = QS.Title(q)
  QS.Select(q, "map")
  local loc = QS.Locate(q)
  if loc and not loc.zoneOnly then
    local wx, wy = WorldOf(loc.map, loc.x, loc.y)
    if wx then
      local fid = FrameId(loc.map)
      FlyTo(fid, wx, wy, true)
      M.HideNote()
      local msg = "Showing \"" .. title .. "\" on the map."
      if wp then
        local ok, why = QS.SetWaypoint(loc.map, loc.x, loc.y, q)
        msg = msg .. (ok and " The game's arrow points there." or (" No waypoint: " .. tostring(why) .. "."))
      end
      NS.SetStatus(msg)
      M.dirty = true
      return "point"
    end
  end
  if loc and loc.zoneOnly then
    local fid = FrameId(loc.map)
    FlyTo(fid, nil, nil, true)
    if wp then QS.TrackQuest(q) end
    M.Note("No map location from the game for \"" .. title .. "\". Showing its zone, " .. tostring(MD.Name(loc.map) or "?") .. ".")
    NS.SetStatus("\"" .. title .. "\": no map location from the game; showing its zone.")
    M.dirty = true
    return "zone"
  end
  M.Note("No map location from the game for \"" .. title .. "\", and no zone to show.")
  NS.SetStatus("\"" .. title .. "\": the game gives no map location or zone for it.")
  return "none"
end

-- a marker click: select the quest and open its detail in the docked Quest Log panel (0.5.2a.2; the map stays still,
-- Show on map glides); shift-click: the game's waypoint + arrow
QuestClick = function(mk)
  local QS = NS.QS
  if not (QS and mk and mk.qid) then return end
  if type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() then
    local ok, why = QS.SetWaypoint(mk.map, mk.mx, mk.my, mk.qid)
    NS.SetStatus("\"" .. QS.Title(mk.qid) .. "\": " .. (ok and why or ("no waypoint: " .. tostring(why))))
    return
  end
  QS.Select(mk.qid, "map")
  if NS.QuestPanel and NS.QuestPanel.OpenQuest then NS.QuestPanel.OpenQuest(mk.qid) end
  NS.SetStatus("Selected \"" .. QS.Title(mk.qid) .. "\" (Quest Log panel). Shift-click a marker for the game's waypoint and arrow.")
  M.dirty = true
end
M.QuestClick = function(mk) return QuestClick(mk) end

function M.Tick(dt)
  dt = math.min(dt or 0, 0.1)
  if M.pendingQuest and M.ready and VW() >= 50 and VH() >= 50 then local p = M.pendingQuest M.pendingQuest = nil M.ShowQuest(p.q, p.wp) end
  if note and note:IsShown() then note.left = (note.left or 0) - dt if note.left <= 0 then note:Hide() end end
  -- the main window was closed (/dm, a keybind) while the map was full screen: come back with it
  if M.full and _G.DarkMatterFrame and not _G.DarkMatterFrame:IsShown() then M.SetFull(false) return end
  if drag then
    local px, py = Cursor()
    if math.abs(px - drag.x) + math.abs(py - drag.y) > 3 then drag.moved = true end
    V.ox, V.oy = drag.ox + (px - drag.x), drag.oy + (py - drag.y)
    ClampView()
  end
  if zoomT then
    local k = 1 - math.exp(-dt * 14)
    local ls = math.log(V.s) + (math.log(zoomT.s) - math.log(V.s)) * k
    if math.abs(math.log(zoomT.s) - ls) < 0.003 then ls = math.log(zoomT.s) end
    V.s = math.exp(ls)
    V.ox, V.oy = zoomT.px - zoomT.u * BW * V.s, zoomT.py - zoomT.v * BH * V.s
    ClampView()
    if V.s == zoomT.s or math.abs(V.s - zoomT.s) < 1e-9 then zoomT = nil end
  elseif fly then
    fly.t = fly.t + dt
    local e = Smooth(fly.t / fly.dur)
    local ls = math.log(fly.s0) + (math.log(fly.s1) - math.log(fly.s0)) * e
    local ce = e
    if fly.hop then
      -- 0.5.2a: the scale dips in the middle (zoom out), the pan happens mostly while zoomed out
      ls = ls - fly.dip * 4 * e * (1 - e)
      ce = Smooth((fly.t / fly.dur - 0.15) / 0.7)
    end
    SetView(fly.c0[1] + (fly.c1[1] - fly.c0[1]) * ce, fly.c0[2] + (fly.c1[2] - fly.c0[2]) * ce, math.exp(ls))
    if fly.t >= fly.dur then fly = nil end
  end
  -- focus fade (a quarter second when the view moves from one continent to the other)
  local f = Focus()
  for _, c in ipairs(ContList()) do
    local want = (c.id == f) and 1 or 0
    local cur = M.fade[c.id] or want
    if cur ~= want then
      cur = want > cur and math.min(want, cur + dt * 4) or math.max(want, cur - dt * 4)
      M.dirty = true
    end
    M.fade[c.id] = cur
  end
  if M.dirty then M.Layout() end
  M.acc = (M.acc or 0) + dt
  if M.acc >= 0.05 then M.acc = 0 UpdatePlayer() UpdateCoords() end
end

---------------------------------------------------------------------------
-- chrome
---------------------------------------------------------------------------
local function ToolTip(b)
  if not GameTooltip then return end
  GameTooltip:SetOwner(b, "ANCHOR_LEFT")
  GameTooltip:SetText(b.tipTitle or "", 1, 1, 1)
  if b.tipText then GameTooltip:AddLine(b.tipText, 1, 0.82, 0, true) end
  GameTooltip:Show()
end
local function ToolButton(key, title, text, soon, onClick)
  local b = CreateFrame("Button", nil, strip)
  b:SetSize(30, 30)
  -- square button: a themed card plate + the thin pane border (three-slice art needs a wider button)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetColorTexture(0.03, 0.03, 0.03, 0.82) -- a dark plate: the icon must read over any map picture, in every theme
  b.border = UI.NineSlice(b, "pane", 4, "BORDER", 1)
  b.icon = b:CreateTexture(nil, "OVERLAY")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  Icon(b.icon, key)
  b.key, b.tipTitle, b.tipText, b.soon = key, title, text, soon
  UI.Hover(b, ToolTip, function() if GameTooltip then GameTooltip:Hide() end end)
  if key ~= "arrow" and key ~= "quest" then b.icon:SetVertexColor(0.93, 0.89, 0.8) end
  b.icon:SetAlpha(soon and 0.45 or 1)
  b:SetScript("OnClick", function(self)
    if self.soon then NS.SetStatus(self.tipTitle .. ": " .. self.tipText) ToolTip(self) return end
    if onClick then onClick(self) end
  end)
  return b
end

local function PlaceRoot(host, inset, top)
  root:SetParent(host)
  root:ClearAllPoints()
  root:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -(top or inset))
  root:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
end
-- the first view (your zone) is fitted to the box's real size: until you move the map, it is fitted again on resize
local function ApplyFit()
  local f = M.pendingFit
  if not f or VW() < 50 or VH() < 50 then return false end
  local x1, x2, y1, y2 = WorldRect(f.id)
  if not x1 then M.pendingFit = nil return false end
  -- 0.5.1.10: a zone (or city) is opened like the game's map: its art fills the box (0.5.1.11: a framing only, no lock)
  if MD.Is(f.id, "continent") or (M.hasWorld and f.id == M.world) then
    SetView(f.wx or (x1 + x2) / 2, f.wy or (y1 + y2) / 2, 0.94 * math.min(VW() / ((x2 - x1) * BW), VH() / ((y2 - y1) * BH)))
  else
    -- the first view is framed so the zone's art fills the box (the player as near the middle as that allows)
    local s = M.CoverScale(f.id)
    local hw, hh = VW() / 2 / (BW * s), VH() / 2 / (BH * s)
    local cx = Clamp(f.wx or (x1 + x2) / 2, x1 + hw, math.max(x1 + hw, x2 - hw))
    local cy = Clamp(f.wy or (y1 + y2) / 2, y1 + hh, math.max(y1 + hh, y2 - hh))
    SetView(cx, cy, s)
  end
  return true
end
local function Refit()
  if not vp then return end
  canvas:SetSize(VW(), VH())
  over:SetSize(VW(), VH())
  if closeHost then closeHost:SetSize(VW(), VH()) end
  if not ApplyFit() then
    -- the view as last laid out (centre + zoom relative to the fit), so a new box size keeps the place
    local lv = M.lastView
    if lv then SetView(lv.cx, lv.cy, lv.z * SFit())
    else local cx, cy = M.Center() SetView(cx, cy, M.Zoom() * SFit()) end
  end
  M.Layout()
end
M.Refit = Refit
-- tests and probes: put the view at world point cx, cy and zoom (1 = fully zoomed out)
function M.SetViewAt(cx, cy, zoom) SetView(cx, cy, zoom * SFit()) M.Layout() end
-- move the view by dx, dy screen px (free, like a drag)
function M.Pan(dx, dy) V.ox, V.oy = V.ox + dx, V.oy + dy ClampView() M.Layout() end

-- 0.5.2a.1: the quest-log button is lit while the docked panel is open
function M.SetPanelIcon()
  local b = M.panelBtn
  if not b then return end
  local on = NS.QuestPanel and NS.QuestPanel.Wanted()
  b.icon:SetAlpha(on and 1 or 0.55)
  b.tipTitle = on and "Hide quest log" or "Show quest log"
end
local function SetFullIcon()
  if not M.fullBtn then return end
  Icon(M.fullBtn.icon, M.full and "back" or "full")
  M.fullBtn.tipTitle = M.full and "Back to window" or "Full screen"
  M.fullBtn.tipText = M.full and "Return to the Dark Matter window (or press Esc)." or "Fill the screen with the map. Click again or press Esc to go back."
end
local function BuildFull()
  local m = NS.theme.m
  full = CreateFrame("Frame", "DarkMatterMapFull", UIParent)
  full:SetFrameStrata("DIALOG")
  full:SetAllPoints(UIParent)
  full:EnableMouse(true)
  full:Hide()
  UI.Slate(full, "slateShade", "BACKGROUND", 0)
  UI.NineSlice(full, "frame", m.frameCorner, "BORDER", 2)
  -- the title sits on its own plate (the slate under it is dark in some themes and light in others)
  local tp = CreateFrame("Frame", nil, full)
  tp:SetSize(220, 24)
  tp:SetPoint("TOP", full, "TOP", 0, -9)
  local tpl = tp:CreateTexture(nil, "BACKGROUND")
  tpl:SetAllPoints(tp)
  tpl:SetColorTexture(0.06, 0.05, 0.035, 0.92)
  local title = tp:CreateFontString(nil, "OVERLAY")
  NS.SetFont(title, 15, "")
  title:SetPoint("CENTER", tp, "CENTER", 0, 0)
  title:SetTextColor(1, 0.84, 0.3, 1)
  title:SetText("Dark Matter  \194\183  Map")
  full.title = title
  full:SetScript("OnHide", function() if M.full then M.SetFull(false) end end)
end
function M.SetFull(on)
  if not root then return end
  on = on and true or false
  if on == (M.full or false) then return end
  if on then
    if not full then BuildFull() end
    M.full = true
    PlaceRoot(full, 14, 40)
    full:Show()
    if NS.SpecialFrame then NS.SpecialFrame("DarkMatterFrame", false) NS.SpecialFrame("DarkMatterMapFull", true) end
  else
    M.full = false
    PlaceRoot(page, 10)
    if full and full:IsShown() then full:Hide() end
    if NS.SpecialFrame then NS.SpecialFrame("DarkMatterMapFull", false) end
    -- next frame: Esc is still walking UISpecialFrames, and re-adding the main window now would close it too
    if NS.RestoreEscMain then
      if C_Timer and C_Timer.After then C_Timer.After(0, NS.RestoreEscMain) else NS.RestoreEscMain() end
    end
  end
  SetFullIcon()
  Refit()
end

local function ShowResults(list)
  results.list = list
  for i, row in ipairs(results.rows) do
    local r = list[i]
    if r then
      row.name:SetText(r.name)
      row.sub:SetText(r.sub or "")
      row.entry = r
      row:Show()
    else row:Hide() end
  end
  if #list > 0 then
    results:SetHeight(#list * 24 + 10)
    results:Show()
  elseif search and search:GetText() ~= "" then
    results.rows[1].name:SetText("No matching zones")
    results.rows[1].sub:SetText("")
    results.rows[1].entry = nil
    results.rows[1]:Show()
    results:SetHeight(34)
    results:Show()
  else results:Hide() end
end
function M.Search(q) if search then search:SetText(q or "") end ShowResults(MD.Search(q or "", 8)) return results.list end
local function Pick(r)
  if not r then return end
  if search then search:SetText("") search.edit:ClearFocus() end
  results:Hide()
  FlyTo(r.id)
end
M.Pick = Pick

-- 0.5.1.4 WoW theme (theme.crumbFaces): each crumb is drawn like the stock map's top-bar buttons: the first (the
-- world) on the red panel-button face, the rest on the dark field face with a small down arrow, and no ">" between
-- them. Class themes keep the plain text crumbs with ">".
local ARROW = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
Crumbs = function()
  local t = Trail()
  local faces = NS.theme.crumbFaces and true or false
  local key = faces and "f:" or ""
  for _, s in ipairs(t) do key = key .. s.id .. ">" end
  if key == crumbKey then return end
  crumbKey = key
  for _, c in ipairs(crumbs) do
    c:Hide() if c.sep then c.sep:Hide() end
  end
  local x = faces and 4 or 8
  for i, s in ipairs(t) do
    local c = crumbs[i]
    if not c then
      c = CreateFrame("Button", nil, bar)
      c:SetHeight(22)
      c.face = UI.ThreeSlice(c, i == 1 and "btn_red" or "btn_field", 22, "BACKGROUND", 1)
      c.arrow = c:CreateTexture(nil, "ARTWORK")
      c.arrow:SetSize(16, 16)
      c.arrow:SetPoint("RIGHT", c, "RIGHT", -3, 0)
      c.text = UI.Text(c, "OVERLAY", 13, nil, "LEFT")
      c.text:SetPoint("LEFT", c, "LEFT", 4, 0)
      UI.Hover(c)
      c.sep = UI.Text(bar, "OVERLAY", 13, "listSoft", "CENTER")
      c.sep:SetText(">")
      c:SetScript("OnClick", function(self) FlyTo(self.mapID) end)
      crumbs[i] = c
    end
    local last = (i == #t)
    c.mapID = s.id
    c.text:SetText(s.name)
    local tw = c.text:GetStringWidth() or 60
    c.text:ClearAllPoints()
    if faces then
      c.face:Show()
      local arrow = i > 1 and NS.Stock.TextureOK(ARROW)
      if arrow then c.arrow:SetTexture(ARROW) c.arrow:Show() else c.arrow:Hide() end
      c.text:SetPoint("LEFT", c, "LEFT", 10, 0)
      c.text:SetTextColor(1, 0.82, 0)
      c.hoverInk = "gold"
      c.faceW = tw + 20 + (arrow and 14 or 0)
      c:SetWidth(c.faceW)
    else
      c.face:Hide() c.arrow:Hide()
      c.text:SetPoint("LEFT", c, "LEFT", 4, 0)
      c.text:SetTextColor(NS.Color(last and "gold" or "listInk"))
      c.hoverInk = last and "gold" or "listInk"
      c:SetWidth(tw + 8)
    end
    c:ClearAllPoints()
    c:SetPoint("LEFT", bar, "LEFT", x, 0)
    c:Show()
    if faces then
      x = x + c.faceW - 2
    else
      x = x + tw + 8
      if not last then
        c.sep:ClearAllPoints()
        c.sep:SetPoint("LEFT", bar, "LEFT", x + 2, 0)
        c.sep:Show()
        x = x + 16
      end
    end
  end
  M.crumbFaces = faces
  M.crumbText = table.concat(M.Trail(), " > ")
end

local function Build(body)
  local m = NS.theme.m
  tab = CreateFrame("Frame", nil, body)
  tab:SetAllPoints(body)
  page = UI.Page(tab, m.pageW, m.pageH)
  page:SetPoint("TOPLEFT", tab, "TOPLEFT", m.pageX, 0)
  root = CreateFrame("Frame", nil, page)
  PlaceRoot(page, 10)
  M.root = root

  -- top bar: breadcrumb (left) + zone search (right)
  bar = UI.Panel(root, 100, 32)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  bar:SetHeight(32)
  crumbs = {}
  M.crumbs = crumbs
  -- 0.5.1.4: a theme change redraws the crumbs (stock-button faces in the WoW theme, plain text in class themes)
  NS.OnSkin(function() crumbKey = nil if bar and bar:IsShown() ~= nil then Crumbs() end end)
  search = UI.SearchBox(bar, 190, 22)
  search:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
  search.placeholder:SetText("Search zones…")
  search.onChange = function(t) ShowResults(MD.Search(t, 8)) end
  search.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() Pick(results.list and results.list[1]) end)
  search.edit:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() results:Hide() end)
  M.searchBox = search

  -- the map: a ScrollFrame clips the canvas (the game's tiles never draw outside the box)
  vpBox = UI.Panel(root, 100, 100)
  vpBox:ClearAllPoints()
  vpBox:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
  vpBox:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  local b = m.listBorder
  vp = CreateFrame("ScrollFrame", nil, vpBox)
  vp:SetPoint("TOPLEFT", vpBox, "TOPLEFT", b, -b)
  vp:SetPoint("BOTTOMRIGHT", vpBox, "BOTTOMRIGHT", -b, b)
  if vp.SetClipsChildren then pcall(vp.SetClipsChildren, vp, true) end
  canvas = CreateFrame("Frame", nil, vp)
  canvas:SetSize(VW(), VH())
  vp:SetScrollChild(canvas)
  over = CreateFrame("Frame", nil, canvas)
  over:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
  over:SetSize(VW(), VH())
  over:SetFrameLevel(canvas:GetFrameLevel() + 8)
  -- 0.5.1.4: the close-up minimap tiles sit above the zone layers (levels 1-4) and under the markers
  closeHost = CreateFrame("Frame", nil, canvas)
  closeHost:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
  closeHost:SetSize(VW(), VH())
  closeHost:SetFrameLevel(canvas:GetFrameLevel() + 6)
  if closeHost.EnableMouse then closeHost:EnableMouse(false) end
  M.vp, M.canvas, M.over, M.closeHost = vp, canvas, over, closeHost
  local arrow = over:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(26, 26)
  Icon(arrow, "arrow")
  arrow:Hide()
  M.arrow = arrow
  empty = UI.Text(vpBox, "OVERLAY", 13, "listSoft", "CENTER")
  empty:SetPoint("CENTER", vpBox, "CENTER", 0, 0)
  empty:SetWidth(360)
  empty:SetText("This client returned no map pictures (C_Map art), so the map cannot be drawn here.")
  empty:Hide()
  M.empty = empty

  vp:EnableMouse(true)
  if vp.EnableMouseWheel then vp:EnableMouseWheel(true) end
  vp:SetScript("OnMouseWheel", function(_, delta) M.Wheel(delta) end)
  -- 0.5.2a: the same press and release handlers serve the quest markers (a press on a marker can still drag the map)
  M.VpDown = function(btn)
    if btn == "LeftButton" then M.pendingFit = nil local x, y = Cursor() drag = { x = x, y = y, ox = V.ox, oy = V.oy } fly, zoomT = nil, nil end
  end
  M.VpUp = function(btn)
    if btn == "RightButton" then M.ZoomOutLevel() return end
    if btn ~= "LeftButton" then return end
    local was = drag
    drag = nil
    if was and not was.moved and M.pinMode then M.DropPin(was.x, was.y) return end
    if was and not was.moved then
      local now = (type(GetTime) == "function" and GetTime()) or 0
      if lastClick and now - lastClick < 0.35 then lastClick = nil M.ZoomAt(was.x, was.y, 2) else lastClick = now end
    end
  end
  vp:SetScript("OnMouseDown", function(_, btn) M.VpDown(btn) end)
  vp:SetScript("OnMouseUp", function(_, btn) M.VpUp(btn) end)
  vp:SetScript("OnSizeChanged", function() Refit() end)
  root:SetScript("OnUpdate", function(_, dt) M.Tick(dt) end)

  -- right tool strip
  strip = CreateFrame("Frame", nil, vpBox)
  strip:SetFrameLevel(canvas:GetFrameLevel() + 20)
  strip:SetSize(40, 7 * 34 + 8)
  strip:SetPoint("TOPRIGHT", vp, "TOPRIGHT", -6, -6)
  local sbg = strip:CreateTexture(nil, "BACKGROUND")
  sbg:SetAllPoints(strip)
  sbg:SetColorTexture(0, 0, 0, 0.55)
  UI.NineSlice(strip, "pane", 4, "BORDER", 1)
  local tools = {
    ToolButton("starpen", "Starpen", "Draw on the map. Coming in 0.5.3.", true),
    ToolButton("pin", "Drop a pin", "Click this, then click the map: a pin there, and the game's waypoint and minimap arrow point at it. Click a pin to point at it again; right-click removes it.", false,
      function() M.SetPinMode(not M.pinMode) end),
    ToolButton("town", "Town Pins", "Flight masters, innkeepers, vendors, trainers and more. Coming in 0.5.4.", true),
    ToolButton("findme", "Find me", "Jump to where you are.", false, function() M.FindMe() end),
    ToolButton("full", "Full screen", "", false, function() M.SetFull(not M.full) end),
    ToolButton("closeup", "Close-up detail", "The game's minimap tiles when you zoom in close (blended across the whole zone). On/off and strength.", false,
      function() M.ToggleClosePanel() end),
    -- 0.5.2a.1: the docked quest panel beside the window (open or closed, remembered)
    ToolButton("quest", "Quest log", "Show or hide the quest list docked beside the window.", false, function() if NS.QuestPanel then NS.QuestPanel.Toggle() end end),
  }
  -- the close-up button shows the game's spyglass icon (stock art by path); the strip's own find-me icon if missing
  do
    local cb = tools[6]
    local ok, r = pcall(cb.icon.SetTexture, cb.icon, "Interface\\Icons\\INV_Misc_Spyglass_02")
    if ok and r ~= false then cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) cb.icon:SetVertexColor(1, 1, 1) else Icon(cb.icon, "closeup") end
    M.closeBtn = cb
  end
  for i, tb in ipairs(tools) do tb:SetPoint("TOP", strip, "TOP", 0, -5 - (i - 1) * 34) end
  M.tools = tools
  M.fullBtn = tools[5]
  M.panelBtn = tools[7]
  M.pinBtn = tools[2]
  M.SetPanelIcon()
  SetFullIcon()
  M.BuildClosePanel(vpBox, strip, canvas:GetFrameLevel() + 30)

  -- coordinates (bottom right) and the public-data caption (bottom left), each on a solid plate
  local function Box(anchor, rel, x)
    local f = CreateFrame("Frame", nil, vpBox)
    f:SetFrameLevel(canvas:GetFrameLevel() + 20)
    f:SetSize(120, 24)
    f:SetPoint("BOTTOMRIGHT", anchor, rel, x, rel == "BOTTOMRIGHT" and 6 or 0)
    local pl = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    pl:SetAllPoints(f)
    pl:SetColorTexture(0, 0, 0, 0.8)
    f.slice = UI.ThreeSlice(f, "btn_field", 24, "BACKGROUND", 0)
    f.text = UI.Text(f, "OVERLAY", 12, "status", "CENTER")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text:SetShadowOffset(0, 0)
    return f
  end
  coordMe = Box(vp, "BOTTOMRIGHT", -6)
  coordCur = Box(coordMe, "BOTTOMLEFT", -6)
  M.coordCur, M.coordMe = coordCur, coordMe
  caption = CreateFrame("Frame", nil, vpBox)
  caption:SetFrameLevel(canvas:GetFrameLevel() + 20)
  caption:SetSize(150, 18)
  caption:SetPoint("BOTTOMLEFT", vp, "BOTTOMLEFT", 6, 6)
  local cpl = caption:CreateTexture(nil, "BACKGROUND")
  cpl:SetAllPoints(caption)
  cpl:SetColorTexture(0.06, 0.05, 0.035, 0.85)
  caption.text = caption:CreateFontString(nil, "OVERLAY")
  NS.SetFont(caption.text, 10, "")
  caption.text:SetPoint("CENTER", caption, "CENTER", 0, 0)
  caption.text:SetTextColor(0.92, 0.88, 0.76, 1)
  caption.text:SetText(NS.ZoneLevels and NS.ZoneLevels.short or "Levels: public data")
  caption:SetWidth(math.max(120, (caption.text:GetStringWidth() or 110) + 14))
  caption:EnableMouse(true)
  caption:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("Zone level badges", 1, 1, 1)
    GameTooltip:AddLine("Not from the game (it gives no level ranges). " .. (NS.ZoneLevels and NS.ZoneLevels.source or ""), 1, 0.82, 0, true)
    GameTooltip:Show()
  end)
  caption:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  caption:Hide()
  M.caption = caption

  -- search results drop-down (above the map)
  results = UI.Panel(root, 260, 34)
  results:ClearAllPoints()
  results:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -6, -2)
  results:SetFrameLevel(canvas:GetFrameLevel() + 40)
  results.rows = {}
  for i = 1, 8 do
    local row = CreateFrame("Button", nil, results)
    row:SetSize(250, 24)
    row:SetPoint("TOPLEFT", results, "TOPLEFT", 5, -5 - (i - 1) * 24)
    UI.Hover(row)
    row.hoverInk = "listInk"
    row.name = UI.Text(row, "OVERLAY", 12, "listInk", "LEFT")
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.sub = UI.Text(row, "OVERLAY", 11, "listSoft", "RIGHT")
    row.sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:SetScript("OnClick", function(self) Pick(self.entry) end)
    row:Hide()
    results.rows[i] = row
  end
  results:Hide()
  M.results = results
  return tab
end

function M.ZoomOutLevel()
  local t = Trail()
  if #t >= 2 then FlyTo(t[#t - 1].id) elseif t[1] then FlyTo(t[1].id) end
end

local function Events(on)
  if not ev then
    ev = CreateFrame("Frame")
    ev:SetScript("OnEvent", function(_, e)
      if e == "QUEST_LOG_UPDATE" or e == "QUEST_WATCH_LIST_CHANGED" or e == "QUEST_ACCEPTED" or e == "QUEST_REMOVED" or e == "QUEST_TURNED_IN" then MD.Forget("quests")
      elseif e == "MAP_EXPLORATION_UPDATED" then
        MD.Forget("explored")
        if CU then CU.Forget() end
        for _, L in pairs(M.layers) do L.ovBuilt = false end
      end
      M.dirty = true
    end)
  end
  for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "QUEST_LOG_UPDATE", "MAP_EXPLORATION_UPDATED",
    "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "SUPER_TRACKING_CHANGED" }) do
    if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
  end
end

local function Start()
  NS.db.map = NS.db.map or {}
  if not M.started then
    Setup()
    if not M.ready then empty:Show() M.started = true return end
    for _, c in ipairs(ContList()) do M.fade[c.id] = 0 end
    M.started = true
    local sv = NS.db.map.view
    if type(sv) == "table" and type(sv.cx) == "number" and type(sv.z) == "number" then
      SetView(sv.cx, sv.cy, sv.z * SFit())
      local f = Focus()
      if f then M.fade[f] = 1 end
    else
      SetView(0.5, 0.5, SFit())
      UpdatePlayer()
      if M.player then
        M.fade[M.player.cont] = 1
        local z = MD.ZoneOf(M.player.map) or M.player.map
        M.pendingFit = { id = MD.ZoneEntry(z) and z or M.player.cont, wx = M.player[1], wy = M.player[2] }
        ApplyFit()
      end
    end
  end
  if M.ready then empty:Hide() end
  Refit()
  UpdateCoords()
  M.UpdateStatus()
end

-- re-read everything from the game (drops the built layers; the next show starts fresh)
function M.Reset()
  for _, L in pairs(M.layers) do L.frame:Hide() end
  M.layers, M.fade = {}, {}
  M.started, M.ready, M.only, M.hasWorld, M.player = false, false, nil, nil, nil
  M.pendingFit, M.lastView = nil, nil
  drag, zoomT, fly, crumbKey = nil, nil, nil, nil
  MD.Forget()
  if CU then CU.Reset() end
end

-- the status line names the map's sources honestly (0.5.1.4: + the game's minimap tiles up close, when on and loading)
function M.UpdateStatus()
  NS.SetStatus("Dark Matter " .. NS.version .. "  \194\183  " .. (CU and CU.Label() or "Map: the game's own map pictures"))
end

---------------------------------------------------------------------------
-- 0.5.1.4 close-up options: a small themed panel by the tool strip (check box + strength slider), saved in
-- DarkMatterDB.map.closeUp / closeMix
---------------------------------------------------------------------------
function M.BuildClosePanel(host, anchor, level)
  local p = UI.Panel(host, 262, 92)
  p:ClearAllPoints()
  p:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
  p:SetFrameLevel(level)
  p:EnableMouse(true)
  local head = UI.Text(p, "OVERLAY", 13, "listHead", "LEFT")
  head:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -10)
  head:SetText("Close-up detail")
  local box = UI.Checkbox(p, "The game's minimap tiles up close", 18, "listInk")
  box:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -30)
  box.onToggle = function(_, on) CU.SetEnabled(on) M.SyncClosePanel() M.UpdateStatus() end
  local label = UI.Text(p, "OVERLAY", 12, "listInk", "LEFT")
  label:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -60)
  label:SetText("Strength")
  local val = UI.Text(p, "OVERLAY", 12, "gold", "RIGHT")
  val:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -60)
  -- the slider: a stock-looking field groove with the stock scroll knob as its thumb (themed pieces)
  local sl = CreateFrame("Slider", nil, p)
  sl:SetPoint("TOPLEFT", p, "TOPLEFT", 78, -56)
  sl:SetSize(130, 18)
  if sl.SetOrientation then sl:SetOrientation("HORIZONTAL") end
  sl:SetMinMaxValues(0, 1)
  if sl.SetValueStep then sl:SetValueStep(0.05) end
  if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
  sl:EnableMouse(true)
  UI.ThreeSlice(sl, "btn_field", 14, "BACKGROUND") -- the groove (re-skinned with the theme by ThreeSlice itself)
  local thumb = sl:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(14, 18)
  NS.OnSkin(function() NS.SetPiece(thumb, "sb_thumb") NS.Stock.Recolor(thumb, NS.Stock.Tint("sb")) end) -- class themes: recoloured like their scroll knobs
  sl:SetThumbTexture(thumb)
  sl:SetScript("OnValueChanged", function(_, v)
    if p.syncing then return end
    v = math.floor((tonumber(v) or 0) * 20 + 0.5) / 20
    CU.SetStrength(v)
    val:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
  end)
  if sl.EnableMouseWheel then sl:EnableMouseWheel(true) end
  sl:SetScript("OnMouseWheel", function(_, d) M.SetCloseStrength(CU.Strength() + (d > 0 and 0.05 or -0.05)) end)
  p.box, p.slider, p.value = box, sl, val
  p:Hide()
  M.closePanel = p
  M.SyncClosePanel()
  return p
end
function M.SyncClosePanel()
  local p = M.closePanel
  if not p then return end
  p.syncing = true
  p.box:SetChecked(CU.Enabled())
  p.slider:SetValue(CU.Strength())
  p.syncing = false
  p.value:SetText(string.format("%d%%", math.floor(CU.Strength() * 100 + 0.5)))
  if p.slider.SetEnabled then p.slider:SetEnabled(CU.Enabled()) end
  p.slider:SetAlpha(CU.Enabled() and 1 or 0.45)
end
function M.SetCloseStrength(v)
  CU.SetStrength(v)
  M.SyncClosePanel()
end
function M.ToggleClosePanel(show)
  local p = M.closePanel
  if not p then return end
  if show == nil then show = not p:IsShown() end
  if show then M.SyncClosePanel() p:Show() else p:Hide() end
end

NS.RegisterTab({
  id = "map", name = "Map", glyph = "map",
  Build = Build,
  OnShow = function() Events(true) Start() if NS.QuestPanel then NS.QuestPanel.Sync(true) end end,
  OnHide = function()
    Events(false)
    if NS.QuestPanel then NS.QuestPanel.Sync(false) end
    drag, zoomT, fly = nil, nil, nil
    if M.full then M.SetFull(false) end
  end,
  Refresh = function() if M.started then M.dirty = true end end,
  -- 0.5.1.6: the window is being built again; drop everything that hangs off the old one
  Reset = function()
    M.layers, M.fade, M.pools, M.started, M.full = {}, {}, {}, nil, nil
    if full then full:Hide() end
    full = nil
    if CU and CU.Drop then CU.Drop() end
    if NS.QuestPanel then NS.QuestPanel.Drop() end
  end,
})

-- 0.5.2a: the shared quest state (QuestState.lua): a hover or selection from the Quests tab redraws the markers
if NS.QS then
  NS.QS.On(function(what)
    if (what == "hover" or what == "select") and M.started then M.dirty = true end
  end)
end
