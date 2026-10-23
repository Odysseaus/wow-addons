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
M.ContList = function() return ContList() end
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
M.ToW, M.WorldRect = function(...) return ToW(...) end, function(...) return WorldRect(...) end -- 0.5.2b.7: for MapExtras.lua

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
M.Cursor, M.MouseOver = Cursor, MouseOver -- 0.5.2b.7: for MapExtras.lua

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
function M.ArtMag(id, worldW)
  local a = MD.Art(id)
  return a and a.w > 0 and worldW * BW * V.s / a.w or 0
end
function M.ContMag(cont) local p = Place(cont) return M.ArtMag(cont, p[2] - p[1]) end
-- 0.5.2b.3: how far the view is zoomed in past the continent's fitted view, capped by the continent art's magnification
-- (a big window shows the whole continent at art x1.3: still the clean continent picture)
M.BASE_FADE = { 1.6, 3.2, 0.35 } -- continent art from x1.6 to x3.2 fades to 35% over the backdrop colour
function M.FitScale(cont)
  local p = Place(cont)
  return math.min(VW() / math.max(1e-9, (p[2] - p[1]) * BW), VH() / math.max(1e-9, (p[4] - p[3]) * BH))
end
function M.ContZoomK(cont) return math.min(M.ContMag(cont), V.s / math.max(1e-9, M.FitScale(cont))) end
-- 0.5.2b.7.2: numbered zoom levels, one per wheel step: level 1 = fully zoomed out (the widest view the wheel reaches),
-- each level 1.35x (one wheel step) the one before, the last = the deepest zoom (that step may be shorter: the wheel
-- stops at the cap). The same numbers on every continent.
M.LEVEL_STEP = 1.35
local LOG_STEP = math.log(M.LEVEL_STEP)
function M.LevelOf(_, s) return 1 + math.log(math.max(1e-9, (s or V.s) / SFit())) / LOG_STEP end
-- a last step under a quarter of a step is folded into the one before (no wheel click that barely moves)
M.LEVEL_SLIVER = 0.25
function M.MaxLevel()
  local k = math.max(0, M.LevelOf(nil, SFit() * ZMax()) - 1)
  local full = math.floor(k + 1e-6)
  return 1 + ((k - full > M.LEVEL_SLIVER or full == 0) and full + 1 or full)
end
-- the view scale at level n (the last level is the deepest zoom)
function M.LevelScale(_, n)
  local top = SFit() * ZMax()
  if n >= M.MaxLevel() then return top end
  return Clamp(SFit() * M.LEVEL_STEP ^ (n - 1), SFit(), top)
end
-- the level a view scale is at (the nearest level; the deepest zoom is the last level)
function M.LevelIndex(s)
  s = s or V.s
  local top, mx = SFit() * ZMax(), M.MaxLevel()
  if s >= top * 0.9999 then return mx end
  return Clamp(math.floor(M.LevelOf(nil, s) + 0.5), 1, mx)
end
-- the level now (what the readout shows)
function M.ZoomLevel() return M.LevelIndex(), M.focus end
-- level table for /dm mapprobe: level -> zoom past the continent fit, continent art magnification
function M.LevelTable(cont)
  local out = {}
  if not cont then return out end
  local fit = M.FitScale(cont)
  for n = 1, M.MaxLevel(cont) do
    local s = M.LevelScale(cont, n)
    local k = s / math.max(1e-9, fit)
    out[n] = { n = n, s = s, zk = k, art = M.ContMag(cont) * s / math.max(1e-9, V.s) }
  end
  return out
end
-- 0.5.2b.7.3: the capitals fade in from one zoom level (DarkMatterDB.map.cityFade) and are fully drawn from another
-- (DarkMatterDB.map.cityLevel) and deeper, anywhere in view. Default: fade in from Zoom 8, full at Zoom 10.
-- /dm citylevel N sets the full level with the fade starting two levels earlier; /dm citylevel A B sets both.
-- (0.5.2b.7.2 saved only cityLevel, the level they showed from: a saved 10 now reads as fade 8 -> full 10.)
M.CITY_LEVEL_DEFAULT = 10
M.CITY_FADE_LEVELS = 2
function M.CityLevel()
  local db = NS.db and NS.db.map
  local n = db and tonumber(db.cityLevel)
  return n or M.CITY_LEVEL_DEFAULT
end
function M.CityFadeStart()
  local db = NS.db and NS.db.map
  local full = M.CityLevel()
  local a = db and tonumber(db.cityFade)
  if a and a <= full then return a end
  return math.max(1, full - M.CITY_FADE_LEVELS)
end
function M.CityFade(cont)
  local full, a = M.CityLevel(), M.CityFadeStart()
  local L = M.LevelOf(cont)
  if full - a < 0.5 then return Smooth((L - (full - 0.5)) / 0.5) end
  return Smooth((L - a) / (full - a))
end
-- 0.5.2b.4: when the (one) zone picture comes in: as you zoom toward the zone, once it fills ZONE_SHARE of the view
-- (the larger of its width and height share), or once the continent art is magnified past ZONE_MAG (a small zone,
-- so the continent picture never blurs under the middle of the view). At continent view both are 0: no zone art.
M.ZONE_SHARE = { 0.6, 0.9 }
M.ZONE_MAG = { 2.0, 2.8 }
function M.ZoneShare(z)
  local p = Place(z.cont)
  return math.max((z.r[2] - z.r[1]) * (p[2] - p[1]) * BW * V.s / VW(), (z.r[4] - z.r[3]) * (p[4] - p[3]) * BH * V.s / VH())
end
function M.ZoneIn(z)
  local s, m = M.ZONE_SHARE, M.ZONE_MAG
  return math.max(Smooth((M.ZoneShare(z) - s[1]) / (s[2] - s[1])), Smooth((M.ContZoomK(z.cont) - m[1]) / (m[2] - m[1])))
end
function M.ZoneDrawAlpha(z) return M.ZoneIn(z) * M.ContAlpha(z.cont) end
function M.BaseFade(cont)
  local f = M.BASE_FADE
  return 1 - (1 - f[3]) * Smooth((M.ContMag(cont) - f[1]) / (f[2] - f[1]))
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
  -- 0.5.2b.6.2: a masked picture is drawn exactly as /dm masktest zone panel 2: ARTWORK (tiles at sublevel 0, the
  -- explored overlays above at 1), no texture filter, its place and size in screen pixels (Fit), the mask added last
  local sub
  if L.mask then sub = layer == "BACKGROUND" and 0 or 1 layer = "ARTWORK" end
  local function New(px, py, pw, ph, u1, uu2, v1, vv2)
    local t = f:CreateTexture(nil, layer, nil, sub)
    local k = L.mask and L.fitSc or 1
    t:SetSize(pw * k, ph * k)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", px * k, -py * k)
    if L.mask then t:SetTexture(fid) else t:SetTexture(fid, nil, nil, "TRILINEAR") end
    t:SetTexCoord(u1, uu2, v1, vv2)
    t.dmG = { px, py, pw, ph }
    -- 0.5.2b.6.1: the mask goes on last, once the texture has its file, size and place (as /dm masktest does)
    if L.mask then M.AttachMask(t, L.mask) end
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
-- 0.5.2b.4: the game's zone highlight (C_Map.GetMapHighlightInfoAtPosition at a point the game says is that zone),
-- read for the sweep and mapprobe only. 0.5.2b.3 used it as a mask texture to cut each zone to its shape; on 1.60.1
-- that left every zone a full hard-edged rectangle, so nothing is drawn with it any more. Cached per session.
M.hl = {}
local SAMPLE = { { 0.5, 0.5 } }
for j = 0, 4 do for i = 0, 4 do SAMPLE[#SAMPLE + 1] = { (i + 0.5) / 5, (j + 0.5) / 5 } end end
local function Num(v) return type(v) == "number" and v == v end
function M.HighlightInfo(z)
  local c = M.hl[z.id]
  if c ~= nil then return c end
  c = false
  local hi = C_Map and C_Map.GetMapHighlightInfoAtPosition
  local at = C_Map and C_Map.GetMapInfoAtPosition
  if type(hi) == "function" and type(at) == "function" then
    local r = z.r
    for _, s in ipairs(SAMPLE) do
      local x, y = r[1] + s[1] * (r[2] - r[1]), r[3] + s[2] * (r[4] - r[3])
      local ok, info = pcall(at, z.cont, x, y)
      local id = ok and type(info) == "table" and tonumber(info.mapID)
      if id and (id == z.id or MD.ZoneOf(id) == z.id) then
        local ok2, fid = pcall(hi, z.cont, x, y)
        c = ok2 and Num(fid) and fid > 0 or false
        break
      end
    end
  end
  M.hl[z.id] = c
  return c
end
-- 0.5.2b.6.2: a layer frame may be built on another host (the /dm masktest zone panels build the map's own layer
-- there); force = the zone's mask even where the continent is not drawn masked
local function NewLayer(id, level, host, force)
  local art = MD.Art(id)
  if not art then return nil end
  local f = CreateFrame("Frame", nil, host)
  f:SetSize(art.w, art.h)
  -- 0.5.2b.6.2: anchored before its mask is made (panel 2's frame has its place first; 0.5.2b.6.1 made the mask on a
  -- frame with no anchor and anchored it only when shown)
  f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
  f:SetFrameLevel(host:GetFrameLevel() + level)
  f:Hide()
  local L = { id = id, key = id, art = art, frame = f, tiles = {}, ov = {}, built = false, level = level, fitSc = 1 }
  -- 0.5.1.6: zone pictures are feathered at their rim; 0.5.1.7: continent pictures too when the world picture lies under
  -- them (the world picture is the base and is never feathered). 0.5.2b.4: always (no masked zones)
  L.feather = CU and CU.CornerGrad and id ~= M.world and (M.hasWorld or not MD.Is(id, "continent")) or false
  -- 0.5.2b.5: a zone with a shape mask (Data_ZoneMasks.lua) on a continent whose zones all have one is cut to its real
  -- outline by that mask (its own soft edge) instead of being feathered at its rectangle
  local mf = id ~= M.world and not MD.Is(id, "continent") and M.MaskFile(id)
  local ze = mf and MD.ZoneEntry(id)
  if ze and (force or M.ContMasked(ze.cont)) then
    if f.CreateMaskTexture then
      local ok, m = pcall(f.CreateMaskTexture, f)
      if ok and m then
        local ok2, r = pcall(m.SetTexture, m, mf, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        if ok2 and r ~= false then
          -- 0.5.2b.6: a mask made for a zone the game gave no shape for (Redridge, Moonglade, ...) carries its own
          -- rect on the continent; it is placed there inside the zone's picture (beyond it: nothing is drawn)
          local mr = M.MaskRect(id)
          local zr = ze.r
          if mr and zr[2] > zr[1] and zr[4] > zr[3] then
            local sx, sy = art.w / (zr[2] - zr[1]), art.h / (zr[4] - zr[3])
            L.maskBox = { (mr[1] - zr[1]) * sx, (mr[3] - zr[3]) * sy, (mr[2] - mr[1]) * sx, (mr[4] - mr[3]) * sy }
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", f, "TOPLEFT", L.maskBox[1], -L.maskBox[2])
            m:SetSize(L.maskBox[3], L.maskBox[4])
          else
            m:SetAllPoints(f)
          end
          L.mask, L.feather = m, false
        else
          M.maskFail = (M.maskFail or 0) + 1
        end
      end
    else
      M.canMask, M.masked = false, nil
    end
  end
  return L
end
local function Layer(id, level)
  local L = M.layers[id]
  if L then return L end
  L = NewLayer(id, level, canvas)
  if L then M.layers[id] = L end
  return L
end
-- 0.5.2b.6.2: put a built layer on its host at screen px (l, t), sc screen px per art texel. A masked layer is drawn
-- exactly as /dm masktest zone panel 2: never scaled (SetScale 1); its frame, every piece and the mask are sized and
-- placed in screen pixels (re-placed only when sc changes). Others keep 0.5.1's one SetScale.
local function Fit(L, host, l, t, sc)
  local f = L.frame
  sc = math.max(sc, 0.0001)
  if L.mask then
    if L.fitSc ~= sc or not L.fitDone then
      L.fitSc, L.fitDone = sc, true
      if f:GetScale() ~= 1 then f:SetScale(1) end
      f:SetSize(L.art.w * sc, L.art.h * sc)
      for _, list in ipairs({ L.tiles, L.ov }) do
        for _, p in ipairs(list) do
          local g = p.dmG
          if g then
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", f, "TOPLEFT", g[1] * sc, -g[2] * sc)
            p:SetSize(g[3] * sc, g[4] * sc)
          end
        end
      end
      local b = L.maskBox
      if b then
        L.mask:ClearAllPoints()
        L.mask:SetPoint("TOPLEFT", f, "TOPLEFT", b[1] * sc, -b[2] * sc)
        L.mask:SetSize(b[3] * sc, b[4] * sc)
      end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", host, "TOPLEFT", l, -t)
    return
  end
  f:SetScale(sc)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", host, "TOPLEFT", l / sc, -t / sc)
end
M.NewLayer, M.Fit = NewLayer, Fit
-- 0.5.2b.6.2: the map's own layer code drawing a zone on another host at sc (/dm masktest zone panels 3 and 4)
function M.TestLayer(host, id, sc)
  local L = NewLayer(id, 1, host, true)
  if not L then return nil end
  BuildTiles(L)
  L.built = true
  Fit(L, host, 0, 0, sc)
  L.frame:Show()
  L.shown = true
  return L
end
-- place a layer whose art covers world rect (x1..x2, y1..y2) at alpha a (hidden when off screen or invisible)
-- 0.5.2b.3: M.dry (the sweep) places it without building or drawing anything
local function Show(L, x1, x2, y1, y2, a)
  local l, t = M.ToScreen(x1, y1)
  local r, b = M.ToScreen(x2, y2)
  local dry = M.dry
  if a < 0.01 or r < 0 or b < 0 or l > VW() or t > VH() then if not dry then L.frame:Hide() end L.shown = false return false end
  local sc = (r - l) / L.art.w
  if dry then
    L.shown, L.alpha, L.sc, L.box = true, a, sc, { l, t, r, b }
    return true
  end
  -- 0.5.1.11: while dragging, at most one picture is built per frame (the base under it shows meanwhile), so a drag
  -- never stalls on building a zone's tiles and overlays
  if M.buildBudget and (not L.built or (not L.ovBuilt and L.wantOv)) then
    if M.buildBudget <= 0 then L.frame:Hide() L.shown = false M.dirty = true return false end
    M.buildBudget = M.buildBudget - 1
  end
  if not L.built then BuildTiles(L) L.built = true end
  if not L.ovBuilt and L.wantOv then BuildOverlays(L) end
  Fit(L, canvas, l, t, sc)
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
M.Pool, M.PoolReset, M.PoolHideRest = Pool, PoolReset, PoolHideRest -- 0.5.2b.7: for MapExtras.lua
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
-- the objectives of a quest as tooltip lines (markers and the shaded objective areas share it)
function M.AddObjectiveLines(qid)
  if not (GameTooltip and NS.QL and NS.QL.Objectives) then return 0 end
  local ok, objs = pcall(NS.QL.Objectives, { questID = qid })
  local n = 0
  if ok and type(objs) == "table" then
    for _, o in ipairs(objs) do
      if type(o.text) == "string" then
        n = n + 1
        GameTooltip:AddLine((o.done and "\226\156\147 " or "- ") .. o.text, o.done and 0.5 or 1, o.done and 0.9 or 1, o.done and 0.5 or 1, true)
      end
    end
  end
  return n
end
-- 0.5.2b.7: paint a marker as the objective tracker's quest POI button (Blizzard_POIButton): the round button, the
-- "..." (in progress) or "?" (ready) on it, the gold ring and brown dots when the quest is the selected one. All game
-- atlases (QuestState.lua roles poi*); false when this client lacks the button or the symbol (the caller falls back)
function M.PaintPOI(mk, status, hot)
  local QS = NS.QS
  if not (QS and mk.ring) then return false end
  local sym = status == "ready" and "poiComplete" or (hot and "poiProgressSel" or "poiProgress")
  if status == "ready" and not QS.Icon(sym) then return false end
  if not QS.Icon(sym) then sym = "poiProgress" end
  local ring = hot and QS.Icon("poiRingSel") and "poiRingSel" or "poiRing"
  if not (QS.Icon(ring) and QS.Icon(sym)) then return false end
  QS.PaintIcon(mk.ring, ring)
  mk.ring:Show()
  QS.PaintIcon(mk.icon, sym)
  mk.icon:ClearAllPoints()
  mk.icon:SetPoint("CENTER", mk, "CENTER", 0, 0)
  local s = status == "ready" and 0.85 or 0.62
  mk.icon:SetSize(math.floor((hot and 26 or 22) * s + 0.5), math.floor((hot and 26 or 22) * s + 0.5))
  if not QS.PaintIcon(mk.glow, "poiGlow") then QS.PaintIcon(mk.glow, ring) end
  return true
end
local function MakeQuest()
  local q = CreateFrame("Button", nil, over)
  q:SetSize(18, 18)
  q.glow = q:CreateTexture(nil, "BACKGROUND")
  q.glow:SetPoint("CENTER", q, "CENTER", 0, 0)
  q.glow:SetSize(32, 32)
  q.glow:SetBlendMode("ADD")
  q.glow:SetAlpha(0.55)
  q.glow:Hide()
  -- 0.5.2b.7: the POI button's round face (the game draws a 32 px ring on a 20 px button)
  q.ring = q:CreateTexture(nil, "BORDER")
  q.ring:SetPoint("TOPLEFT", q, "TOPLEFT", -4, 4)
  q.ring:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 4, -4)
  q.ring:Hide()
  q.icon = q:CreateTexture(nil, "ARTWORK")
  q.icon:SetAllPoints(q)
  q:SetScript("OnEnter", function(self)
    if NS.QS then NS.QS.Hover(self.qid, "map") end
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(MD.QuestTitle(self.qid), 1, 0.82, 0)
    local st = self.status
    GameTooltip:AddLine(st == "ready" and "Ready to turn in" or (st == "failed" and "Failed" or "In progress"), 0.85, 0.85, 0.85, true)
    M.AddObjectiveLines(self.qid)
    GameTooltip:AddLine("Click: open it in the quest log", 0.5, 0.8, 1)
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
              local hot = QS and QS.IsHot(q.id)
              -- 0.5.2b.7: the objective tracker's own quest POI button (the round button with "..." in progress, "?" when
              -- ready; gold ring and brown dots when selected), as OpenMap draws it; a client without those atlases gets
              -- the 0.5.2a game icons; one with neither draws no marker (/dm questmap)
              local poi = QS and M.PaintPOI(mk, status, hot)
              if poi or (QS and QS.PaintIcon(mk.icon, role)) then
                if not poi then
                  mk.ring:Hide()
                  QS.PaintIcon(mk.glow, role)
                  mk.icon:ClearAllPoints()
                  mk.icon:SetAllPoints(mk)
                end
                mk.poi = poi
                mk.qid, mk.status, mk.map, mk.mx, mk.my = q.id, status, z.id, q.x, q.y
                mk.wx, mk.wy = ToW(z.id, q.x, q.y)
                mk.icon:SetVertexColor(1, 1, 1) -- 0.5.2a.1: the game icon as it is (no tint), like the game map
                local sz = poi and (hot and 26 or 22) or (hot and 24 or 18)
                mk:SetSize(sz, sz)
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
  -- 0.5.2b.7: quest objective areas, party / raid members and your corpse (MapExtras.lua)
  if M.DrawExtras then local ok, e = pcall(M.DrawExtras) if not ok then M.extrasErr = e end end
  if M.DrawUserPins then M.DrawUserPins() end
  if caption then if anyBadge then caption:Show() else caption:Hide() end end
end
-- 0.5.1.7: map pictures on screen: total, feathered at their rim, the world base, and hard-edged ones (mapprobe 21)
function M.SeamReport()
  local shown, fe, base, hard = 0, 0, 0, 0
  for id, L in pairs(M.layers) do
    if L.shown then
      shown = shown + 1
      if L.feather or L.mask then fe = fe + 1 -- 0.5.2b.5: a masked picture's edge is its mask's soft edge
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
M.HOP_SLOW = 1.32 -- 0.5.2b.1: the zoom-out, pan, zoom-in glide takes 32% longer (was 0.8-1.4 s, now about 1.06-1.85 s)
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
-- 0.5.2b.4: the map's layer stack, the same everywhere in Azeroth (no masks: nothing depends on the client cutting a
-- texture to a zone's shape)
--   backdrop  a flat parchment colour under everything (a colour, no art), so no view is ever black
--   1 world   the world picture, wherever the continents do not cover the view
--   2 base    the continent picture: full strength up to art x1.6, then faded toward the backdrop as it is magnified
--             (BASE_FADE), so a magnified, pixelated continent picture never becomes the visible surface
--   4 zone    ONE zone picture: the zone under the middle of the view, feathered at its rim (no hard edge). It comes
--             in only when you zoom toward it (M.ZoneIn: the zone fills ZONE_SHARE of the view, or the continent art
--             is magnified past ZONE_MAG), so the continent seen whole is the clean continent picture
--   3 old     the zone you just left, fading out over a fifth of a second as the middle crosses into the next one
--   6 city    a city's own picture: when it is the focus, and (0.5.2b.7.1) whenever any of it is in view while its
--             parent zone's picture is drawn, at the parent's strength, feathered at its rim
-- A zone's picture includes the parchment, sea and torn edges around the zone; with one zone at a time no other zone
-- ever lies under them, and at zone view that picture fills the view like the game's own map.
local CITY = { 0.45, 0.60 }
M.CITY = CITY
-- 0.5.2b.6: the six capitals by ID; another small zone (Redridge, Moonglade: under 0.004 of the continent) counts as a
-- city only while it has no mask of its own
local function IsCity(z) return MD.IsCityID(z.id) or (z.area < 0.004 and not M.MaskFile(z.id)) end
M.IsCity = IsCity
-- 0.5.2b.5: zone shape masks. Data_ZoneMasks.lua (NS.ZoneMasks[mapID] = { file = ... }) is generated on the box by
-- tools/mapshapes from /dm mapshapes; an addon cannot list its own files, so that table says which masks ship. A
-- continent is drawn masked only when ALL its zones (not the cities) have a mask: then every zone in view is drawn at
-- full strength, each cut to its real outline, so neighbours meet at their real borders and a pan is seamless; the
-- continent picture shows only beyond the outermost zones. Without masks (0.5.2b.5 ships none): 0.5.2b.4's one
-- feathered zone picture at a time.
M.MASK_IN = { 1.3, 1.9 } -- masked zones come in together from x1.3 to x1.9 past the continent's fitted view
-- 0.5.2b.6.1: attach a zone's mask to one of its textures and count what the game says happened. A texture the game
-- reports with no mask after AddMaskTexture (or an error) means masks do not cut here: the map falls back to one
-- feathered zone at a time (M.maskBroken) instead of drawing every zone as a hard rectangle.
M.maskStat = { add = 0, ok = 0, none = 0, err = 0, noCount = 0 }
function M.AttachMask(t, m)
  local st = M.maskStat
  st.add = st.add + 1
  if not t.AddMaskTexture then st.err = st.err + 1 st.lastErr = "no AddMaskTexture" M.MaskBroken("no AddMaskTexture") return false end
  local ok, err = pcall(t.AddMaskTexture, t, m)
  if not ok then st.err = st.err + 1 st.lastErr = tostring(err) M.MaskBroken("AddMaskTexture: " .. tostring(err)) return false end
  if not t.GetNumMaskTextures then st.noCount = st.noCount + 1 return true end
  local ok2, n = pcall(t.GetNumMaskTextures, t)
  if ok2 and type(n) == "number" then
    if n >= 1 then st.ok = st.ok + 1 return true end
    st.none = st.none + 1
    M.MaskBroken("the game kept no mask on a zone texture")
    return false
  end
  st.noCount = st.noCount + 1
  return true
end
function M.MaskBroken(why)
  if M.maskBroken then return end
  M.maskBroken = why
  M.masked = nil
  M.rebuildLayers = true
  M.dirty = true
end
-- what the masked layers hold right now (mapsweep / mapprobe): pieces, how many carry the mask, the mask's file and size
function M.MaskCheck()
  local st = M.maskStat
  local layers, pieces, carry, first = 0, 0, 0, nil
  for _, L in pairs(M.layers) do
    if L.mask then
      layers = layers + 1
      first = first or L
      for _, list in ipairs({ L.tiles, L.ov }) do
        for _, t in ipairs(list or {}) do
          pieces = pieces + 1
          local ok, n = false, nil
          if t.GetNumMaskTextures then ok, n = pcall(t.GetNumMaskTextures, t) end
          if ok and type(n) == "number" and n >= 1 then carry = carry + 1 end
        end
      end
    end
  end
  local mf = "none"
  if first then
    local m = first.mask
    local okT, tex = pcall(m.GetTexture, m)
    local okW, w = pcall(m.GetWidth, m)
    local okH, h = pcall(m.GetHeight, m)
    local okS, sh = pcall(m.IsShown, m)
    mf = string.format("map %d mask %s, %sx%s, shown %s (picture %dx%d)", first.id, okT and tostring(tex) or "?", okW and string.format("%.0f", w) or "?",
      okH and string.format("%.0f", h) or "?", okS and tostring(sh) or "?", first.art.w, first.art.h)
  end
  return string.format("maskcheck: %d masked layers, %d pieces, %d carry the mask; adds %d (ok %d, kept none %d, errors %d, uncounted %d)%s; %s",
    layers, pieces, carry, st.add, st.ok, st.none, st.err, st.noCount, M.maskBroken and ("; MASKS OFF: " .. M.maskBroken) or "", mf)
end
-- 0.5.2b.6.1: throw the built pictures away (they are built again, masked or feathered, on the next layout)
function M.RebuildLayers()
  M.rebuildLayers = nil
  for _, L in pairs(M.layers) do L.frame:Hide() end
  M.layers, M.masked = {}, nil
  M.dirty = true
end
-- /dm mapmask on|off: the zone masks on or off for this session (off = one feathered zone at a time, as 0.5.2b.5)
function M.MapMaskSlash(arg)
  arg = (arg or ""):lower():match("^%s*(%S*)")
  if arg == "off" then M.maskOff = true
  elseif arg == "on" then M.maskOff = nil M.maskBroken = nil M.maskStat = { add = 0, ok = 0, none = 0, err = 0, noCount = 0 }
  elseif arg ~= "" then return "mapmask: /dm mapmask on|off (now: " .. (M.maskOff and "off" or "on") .. ")" end
  if arg ~= "" then M.RebuildLayers() end
  return "mapmask: " .. (M.maskOff and "off" or "on") .. " - " .. M.MaskLine()
end
-- the same in under 70 characters (mapprobe)
function M.MaskShort()
  local st = M.maskStat
  return string.format("adds %d: kept %d, none %d, errors %d, uncounted %d%s", st.add, st.ok, st.none, st.err, st.noCount,
    M.maskBroken and "; OFF" or M.maskOff and "; off" or "")
end
-- 0.5.2b.6.2: an honest check of what the map has drawn right now (not of the dry sweep): every zone picture on
-- screen on a masked continent must be built the panel-2 way: it has its mask, every piece carries it, the mask is
-- the picture's (or its own rect's) size in screen pixels, the frame is unscaled, pieces in ARTWORK, the mask on the
-- pieces' own frame, and no ScrollFrame above it. The game reports no pixels: this proves the build, and /dm
-- masktest zone (panels 2 to 4) shows the picture.
local function Near(a, b) return type(a) == "number" and math.abs(a - b) <= 1 + 0.01 * math.abs(b) end
function M.MaskAudit(r)
  r = r or { shown = 0, cut = 0, pieces = 0, unmasked = 0, rect = 0, way = 0, bad = {} }
  local function Bad(L, kind, why)
    r[kind] = r[kind] + 1
    if #r.bad < 6 then r.bad[#r.bad + 1] = (MD.Name(L.id) or tostring(L.id)) .. " " .. why end
  end
  for _, L in pairs(M.layers) do
    local ze = L.shown and L.frame:IsShown() and L.id ~= M.world and not MD.Is(L.id, "continent") and MD.ZoneEntry(L.id)
    if ze and not IsCity(ze) and M.ContMasked(ze.cont) then
      r.shown = r.shown + 1
      local ok = true
      local m = L.mask
      if not m then Bad(L, "unmasked", "unmasked-rect: no mask") ok = false end
      local f = L.frame
      local okS, s = pcall(f.GetScale, f)
      if m and okS and type(s) == "number" and math.abs(s - 1) > 0.001 then Bad(L, "way", "not-panel2: scaled x" .. string.format("%.2f", s)) ok = false end
      for _, list in ipairs({ L.tiles, L.ov }) do
        for _, t in ipairs(list) do
          do
            r.pieces = r.pieces + 1
            local n = 0
            if t.GetNumMaskTextures then local o, v = pcall(t.GetNumMaskTextures, t) if o and type(v) == "number" then n = v end end
            if n < 1 then Bad(L, "unmasked", "unmasked-rect: a piece without its mask") ok = false break end
            if t.GetDrawLayer then
              local o, lay = pcall(t.GetDrawLayer, t)
              if o and lay ~= "ARTWORK" then Bad(L, "way", "not-panel2: piece in " .. tostring(lay)) ok = false break end
            end
          end
        end
      end
      if m then
        local wantW = L.maskBox and L.maskBox[3] * L.fitSc or L.art.w * L.fitSc
        local wantH = L.maskBox and L.maskBox[4] * L.fitSc or L.art.h * L.fitSc
        local o1, w = pcall(m.GetWidth, m)
        local o2, h = pcall(m.GetHeight, m)
        if not (o1 and o2 and Near(w, wantW) and Near(h, wantH)) then
          Bad(L, "rect", string.format("mask-rect: %sx%s, want %.0fx%.0f", tostring(o1 and w and math.floor(w + 0.5)), tostring(o2 and h and math.floor(h + 0.5)), wantW, wantH))
          ok = false
        end
        if m.GetParent then
          local o, p = pcall(m.GetParent, m)
          if o and p and p ~= f then Bad(L, "way", "not-panel2: mask on another frame") ok = false end
        end
      end
      local x = f.GetParent and f:GetParent() or nil
      while x do
        if x.GetObjectType and x:GetObjectType() == "ScrollFrame" then Bad(L, "way", "not-panel2: inside a ScrollFrame") ok = false break end
        x = x.GetParent and x:GetParent() or nil
      end
      if ok then r.cut = r.cut + 1 end
    end
  end
  return r
end
function M.CutShort()
  local r = M.MaskAudit()
  return string.format("shown %d, cut %d; unmasked %d, mask-rect %d, not-panel2 %d; view %s", r.shown, r.cut, r.unmasked,
    r.rect, r.way, M.vpKind or "?")
end
function M.MaskFile(id)
  local t = NS.ZoneMasks
  local m = type(t) == "table" and t[id]
  if type(m) == "table" then return m.file end
  if type(m) == "string" then return m end
end
function M.MaskRect(id)
  local t = NS.ZoneMasks
  local m = type(t) == "table" and t[id]
  local r = type(m) == "table" and m.rect
  if type(r) == "table" and type(r[1]) == "number" and type(r[4]) == "number" and r[2] > r[1] and r[4] > r[3] then return r end
end
function M.ContMasked(cont)
  M.masked = M.masked or {}
  local c = M.masked[cont]
  if c ~= nil then return c end
  local n, have = 0, 0
  for _, z in ipairs(MD.Zones(cont)) do
    if not IsCity(z) then n = n + 1 if M.MaskFile(z.id) then have = have + 1 end end
  end
  c = n > 0 and have == n and M.canMask ~= false and not M.maskBroken and not M.maskOff
  M.masked[cont] = c
  return c
end
function M.MaskCount()
  local n, have = 0, 0
  for _, ct in ipairs(MD.Continents()) do
    for _, z in ipairs(MD.Zones(ct.id)) do
      if not IsCity(z) then n = n + 1 if M.MaskFile(z.id) then have = have + 1 end end
    end
  end
  return have, n
end
function M.MaskIn(cont) local m = M.MASK_IN return Smooth((M.ContZoomK(cont) - m[1]) / (m[2] - m[1])) end
function M.MaskLine()
  local have, n = M.MaskCount()
  if have == 0 then return string.format("0/%d zones masked (fallback: one zone at a time)", n) end
  local on = 0
  for _, ct in ipairs(MD.Continents()) do if M.ContMasked(ct.id) then on = on + 1 end end
  local why = M.canMask == false and " (no mask API)" or M.maskBroken and " (masks did not attach: one zone at a time)" or M.maskOff and " (off: /dm mapmask on)" or ""
  return string.format("%d/%d zones masked; %d continent(s) drawn masked%s", have, n, on, why)
end
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

-- 0.5.2b.7.1: a city's parent zone: the smallest zone (not a city) holding the city's middle (Elwynn for Stormwind,
-- Dun Morogh for Ironforge, Teldrassil, Durotar, Mulgore, Tirisfal); worked out once per city
M.cityParent = {}
function M.CityParent(cont, z)
  local v = M.cityParent[z.id]
  if v == nil then
    local mx, my, best = (z.r[1] + z.r[2]) / 2, (z.r[3] + z.r[4]) / 2, nil
    for _, e in ipairs(MD.Zones(cont) or {}) do
      if not IsCity(e) and Inside(e.r, mx, my) and (not best or e.area < best.area) then best = e end
    end
    v = best or false
    M.cityParent[z.id] = v
  end
  return v or nil
end

local function Hide(L) if not M.dry then L.frame:Hide() end L.shown = false end
function M.Layout()
  M.dirty = false
  local dry = M.dry
  M.buildBudget = (drag and not dry) and 1 or nil
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
    if L then if covered then Hide(L) else Show(L, 0, 1, 0, 1, 1) end end
  end
  local fz, city = M.FocusZones(M.focus)
  M.focusZone, M.focusCity = fz and fz.id, city and city.id
  local cityA = city and Smooth((Frac(city) - CITY[1]) / (CITY[2] - CITY[1])) or 0
  M.cityA = cityA
  local base = canvas:GetFrameLevel()
  local zf = M.zfade or {}
  M.zfade = zf
  for _, c in ipairs(ContList()) do
    local cl = Layer(c.id, 2)
    local a = M.ContAlpha(c.id)
    -- 0.5.1.11: the continent picture is always drawn (the base); 0.5.2b.3: faded toward the backdrop when magnified
    if cl then local p = Place(c.id) Show(cl, p[1], p[2], p[3], p[4], a * M.BaseFade(c.id)) end
    local masked = M.ContMasked(c.id)
    local maskIn = masked and M.MaskIn(c.id) or 0
    local cityFade = M.CityFade(c.id)
    -- 0.5.2b.7.1: cities after the zones, so each one can follow its parent zone (see M.CityParent)
    local order, cities, dz = {}, {}, {}
    for _, z in ipairs(MD.Zones(c.id)) do if IsCity(z) then cities[#cities + 1] = z else order[#order + 1] = z end end
    for _, z in ipairs(cities) do order[#order + 1] = z end
    for _, z in ipairs(order) do
      local isCity, isFocus = IsCity(z), fz and z.id == fz.id
      -- 0.5.2b.4: one zone picture (the focus zone; the one just left while it fades out), never the neighbours.
      -- The sweep (dry) checks the settled view: the focus zone at its full fade, no zone fading out.
      local d = 0
      if a > 0 then
        if isCity then
          -- 0.5.2b.7.2: a capital is drawn from the city zoom level on (/dm citylevel), whenever any of it is in view,
          -- above its parent zone and feathered at its rim (0.5.2b.7.1 followed the parent zone's picture)
          d = Frac(z) > 0 and a * cityFade or 0
        elseif masked then d = a * maskIn -- 0.5.2b.5: every zone, cut to its shape
        else d = a * M.ZoneIn(z) * (dry and (isFocus and 1 or 0) or (zf[z.id] or 0)) end
      end
      dz[z.id] = d
      local zl = M.layers[z.id]
      if d >= 0.01 then zl = zl or Layer(z.id, 3) end
      if zl then
        zl.wantOv = true
        local lv = isCity and 6 or ((isFocus or masked) and 4 or 3)
        if zl.level ~= lv then zl.level = lv zl.frame:SetFrameLevel(base + lv) end
        local x1, x2, y1, y2 = WorldRect(z.id)
        Show(zl, x1, x2, y1, y2, d)
      end
    end
  end
  -- 0.5.1.4: the game's minimap tiles over the zones when zoomed in (0.5.1.5: blended across the whole view, feathered where the tiles end), then the paper grain
  -- 0.5.2b.5: the sweep (dry) asks the tiles what they WOULD draw (nothing is built); a real layout is timed
  if CU and closeHost then
    local cl = {}
    for _, c in ipairs(ContList()) do cl[#cl + 1] = { id = c.id, alpha = M.ContAlpha(c.id) } end
    local ctx = { host = closeHost, conts = cl, place = Place, toScreen = M.ToScreen, vw = VW(), vh = VH(), mag = M.RefMag(), dry = dry }
    if dry then M.closeDry = CU.Layout(ctx) return end
    local clock = debugprofilestop
    local t0 = type(clock) == "function" and clock()
    M.close = CU.Layout(ctx)
    if t0 then
      local ms = clock() - t0
      local st = M.closeMs or { n = 0, sum = 0, max = 0 }
      M.closeMs = st
      st.n, st.sum, st.max, st.last = st.n + 1, st.sum + ms, math.max(st.max, ms), ms
    end
  elseif dry then
    return
  end
  LayoutOverlay()
  UpdatePlayer()
  if Crumbs then Crumbs() end
  M.UpdateZoomReadout()
  local cx, cy = M.Center()
  M.lastView = { cx = cx, cy = cy, z = M.Zoom(), w = VW(), h = VH() }
  if NS.db and NS.db.map then NS.db.map.view = { cx = cx, cy = cy, z = M.lastView.z } end
end

-- 0.5.2b.4: what the current view shows, checked point by point (mapprobe 23 and the sweep). A 12 x 8 grid of screen
-- points: each is land of a zone (the game's own GetMapInfoAtPosition) or open (sea, outside the continent), and is
-- drawn by a zone picture at full strength or else by the base (the continent picture). Flags:
--   magnified-base   the focus zone's own land left to the continent picture once that is magnified past ZONE_MAG[2]
--   open-base        sea / open ground shown by the continent picture at more than half strength past x3.2 (stripes)
--   hard-seam        a zone picture on screen with an edge in view that is not feathered
--   zone-rect        zone art drawn at continent view (no zone fills ZONE_SHARE[1], art under ZONE_MAG[1])
--   overlap          more than one zone picture drawn at once (a neighbour's parchment, sea or torn edge over a zone)
-- 0.5.2b.5 (stricter):
--   base-land        ANY land point left to the stretched continent picture once zoomed in (past MASK_IN[2]: x1.9 past
--                    the fitted continent): it must be drawn by a zone picture at full strength or by the minimap tiles
-- A point counts as drawn by the tiles where the tiles are at 0.9+ and a tile is there; by a masked zone picture only
-- for its own land (its box holds its neighbours' too, but its mask does not). Masked pictures have soft edges by
-- their mask (no hard-seam) and may be drawn side by side (no overlap).
function M.LayerCheck()
  local r = { mag = 0, land = 0, zone = 0, base = 0, open = 0, seams = 0, rects = 0, overlap = 0, zones = 0, focusBase = 0, tiles = 0, flags = {} }
  local cont = M.focus
  if not (M.ready and cont) then r.text = "no map on screen" return r end
  local vw, vh = VW(), VH()
  r.mag = M.ContMag(cont)
  local fz = M.focusZone and MD.ZoneEntry(M.focusZone)
  r.zoneIn = fz and M.ZoneIn(fz) or 0
  local cl = M.layers[cont]
  r.baseA = cl and cl.shown and cl.alpha or 0
  -- continent view judged by the view itself (not by ZoneIn, so a wrong ZoneIn is caught): the zone under the middle
  -- fills less than ZONE_SHARE[1] and the continent art is not magnified past ZONE_MAG[1]
  local masked = M.ContMasked(cont)
  local zk = M.ContZoomK(cont)
  r.zoomK, r.masked = zk, masked
  local contView = not fz or (M.ZoneShare(fz) < M.ZONE_SHARE[1] and zk < M.ZONE_MAG[1])
  if masked then contView = zk < M.MASK_IN[1] end
  local cs = M.dry and M.closeDry or M.close
  r.tileA = cs and cs.byCont and cs.byCont[cont] or 0
  local tilesOn = CU and CU.Covers and r.tileA >= 0.9
  local list, strong = {}, 0
  for _, L in pairs(M.layers) do
    if L.shown and (L.alpha or 0) > 0.01 and L.id ~= M.world and not MD.Is(L.id, "continent") then
      list[#list + 1] = L
      local z = MD.ZoneEntry(L.id)
      if not (z and IsCity(z)) then
        r.zones = r.zones + 1
        if contView then r.rects = r.rects + 1 end
        if L.alpha > 0.05 and not L.mask then strong = strong + 1 end
      end
      local b = L.box
      if L.alpha > 0.05 and not L.feather and not L.mask and b then
        local function In(v, n) return v > 1 and v < n - 1 end
        if In(b[1], vw) or In(b[3], vw) or In(b[2], vh) or In(b[4], vh) then r.seams = r.seams + 1 end
      end
    end
  end
  if strong > 1 then r.overlap = strong - 1 end
  local p = Place(cont)
  local at = C_Map and C_Map.GetMapInfoAtPosition
  local zones = {}
  for _, z in ipairs(MD.Zones(cont)) do zones[z.id] = z end
  for j = 0, 7 do
    for i = 0, 11 do
      local px, py = (i + 0.5) / 12 * vw, (j + 0.5) / 8 * vh
      local wx, wy = M.ToWorld(px, py)
      local x, y = (wx - p[1]) / (p[2] - p[1]), (wy - p[3]) / (p[4] - p[3])
      local zid
      if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        if type(at) == "function" then
          local ok, info = pcall(at, cont, x, y)
          local id = ok and type(info) == "table" and tonumber(info.mapID)
          if id and not zones[id] then id = MD.ZoneOf(id) end
          zid = id and zones[id] and id or nil
        else
          local z = MD.ZoneAt(cont, x, y)
          zid = z and z.id
        end
      end
      local covered, own = false, false
      for _, L in ipairs(list) do
        local b = L.box
        if b and L.alpha >= 0.9 and px >= b[1] and px <= b[3] and py >= b[2] and py <= b[4]
          and (not L.mask or (zid and (L.id == zid or IsCity(zones[zid])))) then
          covered = true
          if fz and L.id == fz.id then own = true end
        end
      end
      if zid then
        r.land = r.land + 1
        if not covered and tilesOn and CU.Covers(cont, x, y) then covered = true r.tiles = r.tiles + 1 end
        if covered then r.zone = r.zone + 1 else r.base = r.base + 1 end
        if fz and zid == fz.id and not own then r.focusBase = r.focusBase + 1 end
      elseif not covered then r.open = r.open + 1 end
    end
  end
  local F = r.flags
  if r.mag > M.ZONE_MAG[2] and r.focusBase > 0 and r.baseA > 0.01 then F[#F + 1] = "magnified-base" end
  if r.mag > M.BASE_FADE[2] and r.open > 0 and r.baseA > 0.5 then F[#F + 1] = "open-base" end
  if r.seams > 0 then F[#F + 1] = "hard-seam" end
  if r.rects > 0 then F[#F + 1] = "zone-rect" end
  if r.overlap > 0 then F[#F + 1] = "overlap" end
  if not contView and zk >= M.MASK_IN[2] and r.base > 0 and r.baseA > 0.01 then F[#F + 1] = "base-land" end
  r.text = string.format("art x%.2f, zoom x%.2f, zone in %.2f, base %.2f, tiles %.2f; zone pictures %d; points: land %d (zone art or tiles %d, of them tiles %d; base %d; focus zone on base %d), open %d; hard seams %d; zone art at continent view %d; overlapping zone pictures %d -> %s",
    r.mag, zk, r.zoneIn, r.baseA, r.tileA, r.zones, r.land, r.zone, r.tiles, r.base, r.focusBase, r.open, r.seams, r.rects, r.overlap, #F == 0 and "OK" or table.concat(F, ", "))
  return r
end
-- 0.5.2b.4: diagnostic only (nothing is drawn with it): for how many of a continent's zones the game answers
-- C_Map.GetMapHighlightInfoAtPosition with a file, and the names it did not
function M.HighlightCount(cont)
  local n, ok, miss = 0, 0, {}
  for _, z in ipairs(MD.Zones(cont)) do
    if not IsCity(z) then
      n = n + 1
      if M.HighlightInfo(z) then ok = ok + 1 else miss[#miss + 1] = z.name end
    end
  end
  return ok, n, miss
end
-- 0.5.2b.5: how far the minimap tiles reach on a continent in this view size: the zoom past its fitted view (x1 =
-- the whole continent fits) where they start (OUT_TILES in view), where they are full (FULL_TILES) and the deepest zoom
-- (MAX_PPY). The tile count in view goes with 1 / zoom^2, so one dry layout at the fitted view gives all three.
function M.TileReach(cont)
  if not (CU and CU.Layout and closeHost and M.ready) then return nil end
  local s0, ox0, oy0 = V.s, V.ox, V.oy
  local p = Place(cont)
  local fs = M.FitScale(cont)
  local wasDry = M.dry
  -- 0.5.2b.6: the continent at full strength for this dry layout (0.5.2b.5 read the faded-out continent the player is
  -- not on as "no tiles": Kalimdor from Eastern Kingdoms)
  local fade0 = M.fade[cont]
  M.fade[cont] = 1
  M.dry = true
  SetView((p[1] + p[2]) / 2, (p[3] + p[4]) / 2, fs)
  local ok = pcall(M.Layout)
  M.dry = wasDry
  M.fade[cont] = fade0
  V.s, V.ox, V.oy = s0, ox0, oy0
  if not wasDry then M.Layout() end
  local cd = M.closeDry
  local est = ok and cd and cd.estBy and cd.estBy[cont]
  if not est or est <= 0 or est == math.huge then return nil end
  local r = { est = est, tpx = cd.tpxBy[cont] }
  r.start = math.sqrt(est / CU.OUT_TILES)
  r.full = math.sqrt(est / CU.FULL_TILES)
  local ms = CU.MaxScale and CU.MaxScale(cont, (p[2] - p[1]) * BW)
  r.deep = ms and ms / fs
  return r
end
function M.ReachLine(cont)
  local r = M.TileReach(cont)
  if not r then return "no tiles" end
  local mode = CU.Layer and CU.Layer() or "terrain"
  if mode ~= "terrain" then
    -- 0.5.2b.6: painted / auto draw no tiles by count; where terrain would bring them, for comparison
    return string.format("%s, %s (terrain: x%.1f-x%.1f, deepest x%.0f)", mode, mode == "auto" and "tiles at art blur x2.8+" or "no tiles",
      r.start, r.full, r.deep or 0)
  end
  return string.format("tiles from x%.1f, full x%.1f, deepest x%.0f (tile %.0f px at fit)", r.start, r.full, r.deep or 0, r.tpx or 0)
end
-- 0.5.2b.6: /dm maplayer auto|painted|terrain (no argument: say which one is on)
M.LAYER_SAY = {
  painted = "the game's painted zone maps everywhere, no minimap tiles",
  auto = "the painted zone maps; the minimap tiles only at the deepest zoom",
  terrain = "the minimap tiles as soon as they fit the view (0.5.2b.5)",
}
function M.MapLayerSlash(arg)
  if not (CU and CU.Layer) then return "maplayer: no close-up module" end
  arg = arg and arg:lower():match("^%s*(%S*)") or ""
  if arg ~= "" then
    if not CU.SetLayer(arg) then return "maplayer: /dm maplayer auto|painted|terrain (now: " .. CU.Layer() .. ")" end
    if M.started then M.UpdateStatus() end
    M.SyncClosePanel()
  end
  local v = CU.Layer()
  return "maplayer: " .. v .. " - " .. M.LAYER_SAY[v] .. (v == CU.DEFAULT_LAYER and " (default)" or "")
end
-- 0.5.2b.7.3: /dm citylevel [N | A B | default]: the capitals are fully drawn from zoom level N, fading in from N-2
-- (or from A to B); saved in DarkMatterDB.map.cityLevel / cityFade; live
function M.CityLevelSlash(arg)
  arg = arg and arg:lower() or ""
  local a1, a2 = arg:match("^%s*(%S*)%s*(%S*)")
  a1, a2 = a1 or "", a2 or ""
  local say = "/dm citylevel N (full from N, fading in from N-2) or A B (fade A to full B); 1 = fully zoomed out"
  if a1 ~= "" then
    if not NS.db then return "citylevel: saved settings not loaded yet" end
    NS.db.map = NS.db.map or {}
    if a1 == "default" or a1 == "reset" then
      NS.db.map.cityLevel, NS.db.map.cityFade = nil, nil
    else
      local x, y = tonumber(a1), a2 ~= "" and tonumber(a2) or nil
      local function okn(v) return v and v == math.floor(v) and v >= 1 and v <= 40 end
      if not okn(x) or (a2 ~= "" and not okn(y)) then return "citylevel: " .. say .. ", or default" end
      if y then
        if y < x then x, y = y, x end
        NS.db.map.cityLevel, NS.db.map.cityFade = y, x
      else
        NS.db.map.cityLevel, NS.db.map.cityFade = x, nil
      end
    end
    M.dirty = true
  end
  local n, a = M.CityLevel(), M.CityFadeStart()
  local def = n == M.CITY_LEVEL_DEFAULT and a == M.CITY_LEVEL_DEFAULT - M.CITY_FADE_LEVELS
  local top = M.ready and M.MaxLevel(M.focus or Focus()) or nil
  return "citylevel: cities fade in from zoom level " .. a .. ", full from " .. n .. (def and " (default)" or "")
    .. (top and (" - this map goes to " .. top) or "") .. " - " .. say
end
-- 0.5.2b.5: /dm tileprobe: what the minimap tiles have on this client, how far they reach, what they cost
function M.TileProbe()
  local out = { "tileprobe " .. NS.version .. " (read-only): the minimap tiles behind the map close-up" }
  if not CU then out[#out + 1] = "tileprobe: no close-up module" return out end
  out[#out + 1] = "tileprobe: " .. (CU.Label and CU.Label() or "?")
  out[#out + 1] = "tileprobe: map layer " .. (CU.Layer and CU.Layer() or "terrain") .. " (/dm maplayer auto|painted|terrain)"
  for inst = 0, 1 do
    local r = CU.Coverage(inst, 48)
    out[#out + 1] = string.format("tileprobe %s: %d tiles listed (x %s-%s, y %s-%s)", CU.NAMES[inst] or inst, r.n,
      tostring(r.x1 or "-"), tostring(r.x2 or "-"), tostring(r.y1 or "-"), tostring(r.y2 or "-"))
    out[#out + 1] = string.format("tileprobe %s sample of %d: %d load, %d missing, %d unknown", CU.NAMES[inst] or inst, r.tried, r.ok, r.no, r.unknown)
  end
  out[#out + 1] = string.format("tileprobe rule: full at %d tiles in view, gone at %d; or art x%.1f-x%.1f; cap %d-%d real tiles",
    CU.FULL_TILES, CU.OUT_TILES, CU.MAG_FADE[1], CU.MAG_FADE[2], CU.FADE_TILES, CU.MAX_TILES)
  if not M.ready then
    out[#out + 1] = "tileprobe: open the Map tab once for the reach and the timing"
    return out
  end
  for _, c in ipairs(ContList()) do out[#out + 1] = "tileprobe reach " .. (MD.Name(c.id) or c.id) .. ": " .. M.ReachLine(c.id) end
  local last = CU.last
  if last then
    out[#out + 1] = string.format("tileprobe now: %d tiles in view, %d fit, tile %d px, %d pieces, shown %.2f",
      last.tiles or 0, math.floor((last.est or 0) + 0.5), math.floor((last.tpx or 0) + 0.5), last.pieces or 0, last.alpha or 0)
  end
  local st = M.closeMs
  if st and st.n > 0 then
    out[#out + 1] = string.format("tileprobe timing: layout %.2f ms average, %.2f ms worst, over %d frames", st.sum / st.n, st.max, st.n)
  else
    out[#out + 1] = "tileprobe timing: no frames timed yet (pan the map, then run it again)"
  end
  return out
end
-- 0.5.2b.3: /dm mapsweep: the layer check over every continent and zone of Azeroth at several zooms (a dry run: the
-- layers are placed, nothing is built or drawn), then the view as it was. Returns the report lines.
function M.Sweep()
  if not (M.ready and canvas) then return { "mapsweep: open the Map tab once first" } end
  local s0, ox0, oy0 = V.s, V.ox, V.oy
  local res = { views = 0, flagged = 0, count = {}, bad = {}, per = {} }
  local cur
  local function Try(name, cx, cy, s)
    SetView(cx, cy, s)
    M.Layout()
    local r = M.LayerCheck()
    res.views = res.views + 1
    cur.views = cur.views + 1
    if #r.flags > 0 then
      res.flagged = res.flagged + 1
      cur.flagged = cur.flagged + 1
      for _, f in ipairs(r.flags) do res.count[f] = (res.count[f] or 0) + 1 end
      if #res.bad < 25 then res.bad[#res.bad + 1] = name .. ": " .. r.text end
    end
  end
  local hlOk, zonesN = 0, 0
  M.dry = true
  local ok, err = pcall(function()
    for _, c in ipairs(ContList()) do
      local p = Place(c.id)
      local cn = MD.Name(c.id) or tostring(c.id)
      cur = { name = cn, id = c.id, views = 0, flagged = 0 }
      res.per[#res.per + 1] = cur
      local fs = M.FitScale(c.id)
      local mx, my = (p[1] + p[2]) / 2, (p[3] + p[4]) / 2
      Try(cn .. " fitted", mx, my, fs)
      Try(cn .. " x1.4", mx, my, fs * 1.4)
      Try(cn .. " x2", mx, my, fs * 2)
      local h1, n1 = M.HighlightCount(c.id)
      hlOk, zonesN = hlOk + h1, zonesN + n1
      for _, z in ipairs(MD.Zones(c.id)) do
        if not IsCity(z) then
          local x1, x2, y1, y2 = WorldRect(z.id)
          local zc = M.CoverScale(z.id)
          local zx, zy = (x1 + x2) / 2, (y1 + y2) / 2
          Try(z.name .. " fitted", zx, zy, zc * 0.6)
          Try(z.name .. " zone view", zx, zy, zc)
          Try(z.name .. " x2", zx, zy, zc * 2)
          Try(z.name .. " west edge", x1, zy, zc)
          Try(z.name .. " east edge", x2, zy, zc)
          Try(z.name .. " north edge", zx, y1, zc)
          Try(z.name .. " south edge", zx, y2, zc)
        end
      end
    end
  end)
  M.dry = nil
  -- 0.5.2b.6.2: then views drawn for real (zoomed out: each continent fitted, x1.4, x2; and each zone fitted), every
  -- zone picture on screen audited (MaskAudit)
  local cut = { views = 0, shown = 0, cut = 0, pieces = 0, unmasked = 0, rect = 0, way = 0, bad = {} }
  local okC, errC = pcall(function()
    for _, c in ipairs(ContList()) do
      if M.ContMasked(c.id) then
        local p = Place(c.id)
        local fs = M.FitScale(c.id)
        local mx, my = (p[1] + p[2]) / 2, (p[3] + p[4]) / 2
        local views = { { mx, my, fs }, { mx, my, fs * 1.4 }, { mx, my, fs * 2 } }
        for _, z in ipairs(MD.Zones(c.id)) do
          if not IsCity(z) then
            local x1, x2, y1, y2 = WorldRect(z.id)
            views[#views + 1] = { (x1 + x2) / 2, (y1 + y2) / 2, M.CoverScale(z.id) * 0.6 }
          end
        end
        for _, v in ipairs(views) do
          SetView(v[1], v[2], v[3])
          M.Layout()
          cut.views = cut.views + 1
          M.MaskAudit(cut)
        end
      end
    end
  end)
  if not okC then cut.err = tostring(errC) end
  M.cut = cut
  V.s, V.ox, V.oy = s0, ox0, oy0
  M.Layout()
  local out = { "Dark Matter " .. NS.version .. " mapsweep" }
  if not ok then out[#out + 1] = "mapsweep error: " .. tostring(err) end
  local function C(f) return res.count[f] or 0 end
  out[#out + 1] = string.format("mapsweep: %d views, %d flagged; base-land %d, magnified-base %d, open-base %d, hard-seam %d, zone-rect %d, overlap %d",
    res.views, res.flagged, C("base-land"), C("magnified-base"), C("open-base"), C("hard-seam"), C("zone-rect"), C("overlap"))
  out[#out + 1] = "mapsweep masks: " .. M.MaskLine()
  out[#out + 1] = "mapsweep " .. M.MaskCheck()
  local cut = M.cut
  local cutBad = cut.unmasked + cut.rect + cut.way
  out[#out + 1] = string.format("mapsweep cut: %d views drawn for real (zoomed out and zone views), %d zone pictures on screen, %d cut the panel-2 way (%d pieces carry the mask); unmasked-rect %d, mask-rect %d, not-panel2 %d; viewport %s -> %s",
    cut.views, cut.shown, cut.cut, cut.pieces, cut.unmasked, cut.rect, cut.way, M.vpKind or "?",
    cut.err and ("ERROR " .. cut.err) or (cut.views == 0 and "no masked continent") or (cutBad == 0 and cut.shown > 0 and "OK") or "FLAGGED")
  for _, b in ipairs(cut.bad) do out[#out + 1] = "mapsweep cut flag " .. b end
  out[#out + 1] = "mapsweep cut: the game reports no pixels; this checks how each picture is built. /dm masktest zone shows it"
  for _, c in ipairs(res.per) do
    out[#out + 1] = string.format("mapsweep %s: %d views, %d flagged -> %s; %s", c.name, c.views, c.flagged, c.flagged == 0 and "OK" or "FLAGGED", M.ReachLine(c.id))
  end
  out[#out + 1] = string.format("mapsweep highlight info (diagnostic, not drawn): the game answered for %d/%d zones", hlOk, zonesN)
  for _, b in ipairs(res.bad) do out[#out + 1] = "mapsweep flag " .. b end
  M.sweep = res
  return out
end

---------------------------------------------------------------------------
-- motion: wheel zoom to the cursor, drag, fly-to
---------------------------------------------------------------------------
-- 0.5.2b.7.2: where one wheel step from scale `base` lands: the next numbered zoom level (M.LevelOf)
function M.WheelNext(base, delta)
  local sf = SFit()
  if delta == 0 then return Clamp(base, sf, sf * ZMax()) end
  local n = M.LevelIndex(base) + (delta > 0 and math.ceil(delta) or math.floor(delta))
  return M.LevelScale(nil, n)
end
-- the wheel steps from fully out to fully in (counted by stepping the wheel rule itself)
function M.WheelSteps()
  local s, top, n = SFit(), SFit() * ZMax(), 0
  while s < top * 0.9999 and n < 200 do s = M.WheelNext(s, 1) n = n + 1 end
  return n
end
function M.Wheel(delta)
  if not M.ready then return end
  M.pendingFit = nil
  local px, py = Cursor()
  local u, v = M.ToWorld(px, py)
  local base = zoomT and zoomT.s or V.s
  zoomT = { s = M.WheelNext(base, delta), u = u, v = v, px = px, py = py }
  fly = nil
end
-- 0.5.2b.7.2: a zoom or fly is under way (the quest areas count their frames then; /dm mapprobe 10e)
function M.Gliding() return zoomT ~= nil or fly ~= nil or (drag ~= nil and drag.moved and true or false) end
-- 0.5.2b.7.2: the "Zoom N" readout follows the view (Layout)
function M.UpdateZoomReadout()
  local zr = M.zoomReadout
  if not zr or not zr.text then return end
  local n = M.ZoomLevel()
  local txt = "Zoom " .. math.max(1, n)
  if M.zoomText ~= txt then
    M.zoomText = txt
    zr.text:SetText(txt)
    local w = zr.text.GetStringWidth and zr.text:GetStringWidth()
    zr:SetWidth(math.max(52, (type(w) == "number" and w or 50) + 12))
  end
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
    fly.dur = (0.8 + math.min(0.6, fly.dip * 0.2)) * M.HOP_SLOW -- 0.5.2b.1: about a third slower, same easing
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
  -- 0.5.2b.1: its waypoint and arrow go too (only when the game's waypoint is this pin's)
  local cleared = p and NS.QS and NS.QS.ClearWaypoint and NS.QS.ClearWaypoint(p.map, p.x, p.y)
  NS.SetStatus(cleared and "Pin removed, with its waypoint and arrow." or "Pin removed.")
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
  -- 0.5.2b.7.2: the frame counter (0.5.2b.7.3: quest areas are drawn in the frame they move, after LayoutBlobs; MapExtras.lua)
  if M.ExtrasPreTick then local ok, e = pcall(M.ExtrasPreTick) if not ok then M.extrasErr = e end end
  M.ExploreTick(dt)
  if M.rebuildLayers then M.RebuildLayers() end
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
  -- 0.5.2b.4: zone fade (a fifth of a second): only the zone under the middle of the view is drawn; when the middle
  -- crosses into a neighbour, the old zone picture fades out as the new one fades in (never a stack of zones)
  local fz = M.FocusZones(f)
  local zf = M.zfade or {}
  M.zfade = zf
  for id, v in pairs(zf) do
    if not (fz and id == fz.id) then
      v = math.max(0, v - dt * 5)
      zf[id] = v > 0 and v or nil
      M.dirty = true
    end
  end
  if fz and (zf[fz.id] or 0) < 1 then zf[fz.id] = math.min(1, (zf[fz.id] or 0) + dt * 5) M.dirty = true end
  if M.dirty then M.Layout() end
  M.acc = (M.acc or 0) + dt
  if M.acc >= 0.05 then M.acc = 0 UpdatePlayer() UpdateCoords() end
  if M.ExtrasTick then local ok, e = pcall(M.ExtrasTick, dt) if not ok then M.extrasErr = e end end
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
  -- 0.5.2b.6.2: the viewport is a plain frame that clips its children (SetClipsChildren), as /dm masktest zone panel 2
  -- is a plain frame. 0.5.0 to 0.5.2b.6.1 drew the map inside a ScrollFrame's scroll child, and there every
  -- zone mask failed to cut on 1.60.1 (0.5.2b.3, 0.5.2b.6, 0.5.2b.6.1) while the same masks cut in masktest; the
  -- game kept them on every texture. masktest zone panels 3 and 4 show both. A ScrollFrame only where a frame cannot clip.
  vp = CreateFrame("Frame", nil, vpBox)
  M.vpKind = "frame"
  if not (vp.SetClipsChildren and pcall(vp.SetClipsChildren, vp, true)) then
    vp:Hide()
    vp = CreateFrame("ScrollFrame", nil, vpBox)
    M.vpKind = "scrollframe"
  end
  vp:SetPoint("TOPLEFT", vpBox, "TOPLEFT", b, -b)
  vp:SetPoint("BOTTOMRIGHT", vpBox, "BOTTOMRIGHT", -b, b)
  if M.vpKind == "scrollframe" and vp.SetClipsChildren then pcall(vp.SetClipsChildren, vp, true) end
  canvas = CreateFrame("Frame", nil, vp)
  canvas:SetSize(VW(), VH())
  if M.vpKind == "scrollframe" then vp:SetScrollChild(canvas) else canvas:SetPoint("TOPLEFT", vp, "TOPLEFT", 0, 0) end
  over = CreateFrame("Frame", nil, canvas)
  over:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
  over:SetSize(VW(), VH())
  over:SetFrameLevel(canvas:GetFrameLevel() + 8)
  -- 0.5.1.4: the close-up minimap tiles sit above the zone layers (levels 1-6) and under the markers
  closeHost = CreateFrame("Frame", nil, canvas)
  closeHost:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
  closeHost:SetSize(VW(), VH())
  closeHost:SetFrameLevel(canvas:GetFrameLevel() + 7)
  if closeHost.EnableMouse then closeHost:EnableMouse(false) end
  -- 0.5.2b.3: the backdrop under every map picture: a flat parchment colour (no art), so no view is ever black and
  -- the magnified continent picture fades toward it
  local backdrop = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
  backdrop:SetAllPoints(canvas)
  backdrop:SetColorTexture(0.62, 0.55, 0.42, 1)
  M.backdrop = backdrop
  M.vp, M.canvas, M.over, M.closeHost = vp, canvas, over, closeHost
  local arrow = over:CreateTexture(nil, "OVERLAY")
  arrow:SetSize(26, 26)
  -- 0.5.2b.7 (G): the stock map's own player arrow (white with the blue dot); Dark Matter's arrow only on a client without it
  M.arrowGame = NS.QS and NS.QS.PaintIcon(arrow, "playerArrow") or false
  if M.arrowGame then arrow:SetSize(24, 24) else Icon(arrow, "arrow") end
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
  -- 0.5.2b.7.2: "Zoom N" readout, top left of the map, in the game's small font (no art: a plain dark plate)
  local zr = CreateFrame("Frame", nil, vpBox)
  zr:SetFrameLevel(canvas:GetFrameLevel() + 20)
  zr:SetSize(60, 16)
  zr:SetPoint("TOPLEFT", vp, "TOPLEFT", 6, -6)
  local zpl = zr:CreateTexture(nil, "BACKGROUND")
  zpl:SetAllPoints(zr)
  zpl:SetColorTexture(0.06, 0.05, 0.035, 0.75)
  zr.text = zr:CreateFontString(nil, "OVERLAY")
  if GameFontNormalSmall and zr.text.SetFontObject then zr.text:SetFontObject(GameFontNormalSmall) else NS.SetFont(zr.text, 10, "") end
  zr.text:SetPoint("CENTER", zr, "CENTER", 0, 0)
  zr.text:SetText("Zoom 1")
  M.zoomReadout = zr

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
        M.ForgetExplored()
      end
      M.dirty = true
    end)
  end
  for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "QUEST_LOG_UPDATE", "MAP_EXPLORATION_UPDATED",
    "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "SUPER_TRACKING_CHANGED" }) do
    if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
  end
end

-- 0.5.2b.6: the fog. 0.5.2b.5 listened for MAP_EXPLORATION_UPDATED only while the tab was open, so an area found with
-- the map closed stayed fogged until /reload. Now: a small frame listens all the time (discovery, zone and info
-- events; each registered only if the client has it) and marks the explored areas to be read again; the tab checks
-- every built zone when it opens, after such an event, and the player's zone every EXPLORE_POLL s while open, and
-- redraws at once when the game's list differs from the one drawn.
M.EXPLORE_POLL = 2
M.EXPLORE_EVENTS = { "MAP_EXPLORATION_UPDATED", "UI_INFO_MESSAGE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
  "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE" }
function M.ForgetExplored()
  MD.Forget("explored")
  if CU then CU.Forget() end
  for _, L in pairs(M.layers) do L.ovBuilt = false end
  M.exploreRefreshes = (M.exploreRefreshes or 0) + 1
  M.dirty = true
end
-- ids: the maps to look at (nil: every zone already drawn); true when the fog was out of date and is redrawn
function M.CheckExplored(ids)
  local stale = false
  if ids then
    for _, id in ipairs(ids) do if MD.ExploredChanged(id) then stale = true break end end
  else
    for id, L in pairs(M.layers) do if L.ovBuilt and MD.ExploredChanged(id) then stale = true break end end
  end
  if stale then M.ForgetExplored() end
  return stale
end
-- an event said the explored areas may have grown: check now (if the tab is open) and once more a little later (the
-- server's update can trail the event)
function M.ExploreEvent(e)
  M.exploreEvents = (M.exploreEvents or 0) + 1
  M.exploreLast = e
  M.exploreDue, M.exploreLeft = 0.25, 2
end
local watch = CreateFrame("Frame")
watch:SetScript("OnEvent", function(_, e) M.ExploreEvent(e) end)
M.exploreWatched = {}
for _, e in ipairs(M.EXPLORE_EVENTS) do
  local ok = pcall(watch.RegisterEvent, watch, e)
  if ok then M.exploreWatched[#M.exploreWatched + 1] = e end
end
M.exploreWatch = watch
function M.ExploreTick(dt)
  if M.exploreLeft then
    M.exploreDue = (M.exploreDue or 0) - dt
    if M.exploreDue <= 0 then
      M.CheckExplored()
      M.exploreLeft = M.exploreLeft - 1
      M.exploreDue = 1.5
      if M.exploreLeft <= 0 then M.exploreLeft, M.exploreDue = nil, nil end
    end
  end
  M.explorePoll = (M.explorePoll or M.EXPLORE_POLL) - dt
  if M.explorePoll <= 0 then
    M.explorePoll = M.EXPLORE_POLL
    local id = M.player and M.player.map
    local z = id and (MD.ZoneOf(id) or id)
    if z then M.CheckExplored({ z }) end
  end
end

local function Start()
  NS.db.map = NS.db.map or {}
  M.CheckExplored() -- 0.5.2b.6: anything found while the tab was closed
  M.exploreLeft, M.exploreDue = nil, nil
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
  -- 0.5.2b.7: every opening starts centred on you at your zone's zoom (Show on map and a tracker title click call
  -- ShowQuest right after this, and that flight to the quest wins)
  M.CentreOnPlayer()
  UpdateCoords()
  M.UpdateStatus()
end
-- centre the view on the player at the zone's zoom (no animation); false when the game gives no position
function M.CentreOnPlayer()
  if not M.ready then return false end
  UpdatePlayer()
  local p = M.player
  if not p then return false end
  if not M.hasWorld and p.cont and p.cont ~= M.only and MD.Art(p.cont) then
    M.only = p.cont
    Setup()
    for _, L in pairs(M.layers) do L.frame:Hide() end
    UpdatePlayer()
    p = M.player
    if not p then return false end
  end
  if p.cont then M.fade[p.cont] = 1 end
  local z = MD.ZoneOf(p.map) or p.map
  fly, zoomT, drag = nil, nil, nil
  M.pendingFit = { id = MD.ZoneEntry(z) and z or p.cont, wx = p[1], wy = p[2], centre = true }
  ApplyFit()
  M.dirty = true
  return true
end

-- re-read everything from the game (drops the built layers; the next show starts fresh)
function M.Reset()
  for _, L in pairs(M.layers) do L.frame:Hide() end
  M.layers, M.fade, M.zfade = {}, {}, {}
  M.hl = {}
  M.masked, M.canMask, M.maskFail = nil, nil, nil -- 0.5.2b.5: the masks are looked at again
  M.maskBroken, M.rebuildLayers = nil, nil
  M.maskStat = { add = 0, ok = 0, none = 0, err = 0, noCount = 0 }
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
  local p = UI.Panel(host, 262, 122)
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
  -- 0.5.2b.6: the map layer (/dm maplayer): painted, auto (default since 0.5.2b.6.1), terrain
  local ll = UI.Text(p, "OVERLAY", 12, "listInk", "LEFT")
  ll:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -92)
  ll:SetText("Layer")
  p.layerBtn = {}
  for i, v in ipairs({ "painted", "auto", "terrain" }) do
    local b = UI.Button(p, v:sub(1, 1):upper() .. v:sub(2), 58, 20, "grey", 11)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 58 + (i - 1) * 64, -88)
    b:SetScript("OnClick", function() NS.Print(M.MapLayerSlash(v)) end)
    b.layer = v
    p.layerBtn[i] = b
  end
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
  local cur = CU.Layer and CU.Layer()
  for _, b in ipairs(p.layerBtn or {}) do b.active = b.layer == cur if b.stockOn and b.StockPaint then b:StockPaint() end if b.SetAlpha then b:SetAlpha(b.active and 1 or 0.6) end end
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
    M.layers, M.fade, M.zfade, M.pools, M.started, M.full = {}, {}, {}, {}, nil, nil
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
