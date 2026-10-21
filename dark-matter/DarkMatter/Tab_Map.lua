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
local M = { layers = {}, fade = {}, pools = {}, view = { s = 1, ox = 0, oy = 0 }, layersOn = { levels = true, quests = true } }
NS.MapTab = M

local ICONS = "Interface\\AddOns\\DarkMatter\\Media\\dm-map-icons"
local I = { findme = 0, pin = 1, starpen = 2, town = 3, full = 4, back = 5, arrow = 6, quest = 7 }
local function Icon(tex, key) tex:SetTexture(ICONS) tex:SetTexCoord(I[key] / 8, (I[key] + 1) / 8, 0, 1) end

local function Clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function Smooth(t) t = Clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function Fmt(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end

local tab, page, root, bar, vpBox, vp, canvas, over, strip, full, empty
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
local function SFit() return math.min(VW() / BW, VH() / BH) end
local function ZMax()
  local m = 40
  for _, c in ipairs(ContList()) do local p = Place(c.id) m = math.max(m, 40 / math.max(0.05, p[2] - p[1])) end
  return math.min(m, 250)
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
function M.ContAlpha(cont)
  if not M.hasWorld then return 1 end
  local p = Place(cont)
  -- how much of the view the continent fills: the larger of its width and height share
  local frac = math.max((p[2] - p[1]) * BW * V.s / VW(), (p[4] - p[3]) * BH * V.s / VH())
  local lo, hi = ContBand(cont)
  return Smooth((frac - lo) / (hi - lo)) * (M.fade[cont] or 0)
end
function M.ZoneAlpha(z)
  local p = Place(z.cont)
  -- width or height share, whichever is larger (a tall zone in a wide view still fades in when fitted)
  local frac = math.max((z.r[2] - z.r[1]) * (p[2] - p[1]) * BW * V.s / VW(), (z.r[4] - z.r[3]) * (p[4] - p[3]) * BH * V.s / VH())
  return Smooth((frac - ZONE_LO) / (ZONE_HI - ZONE_LO)) * M.ContAlpha(z.cont)
end

---------------------------------------------------------------------------
-- layers: one frame per map, holding its tiles + explored overlays (built the first time it is on screen)
---------------------------------------------------------------------------
local function BuildTiles(L)
  local a, f = L.art, L.frame
  for i, fid in ipairs(a.tex) do
    local col, row = (i - 1) % a.cols, math.floor((i - 1) / a.cols)
    local x, y = col * a.tw, row * a.th
    local w, h = math.min(a.tw, a.w - x), math.min(a.th, a.h - y)
    if w > 0 and h > 0 then
      local t = f:CreateTexture(nil, "BACKGROUND")
      t:SetSize(w, h)
      t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
      t:SetTexture(fid, nil, nil, "TRILINEAR")
      t:SetTexCoord(0, w / a.tw, 0, h / a.th)
      L.tiles[#L.tiles + 1] = t
    end
  end
end
-- explored overlays, laid out like the game's own map (tiles of 256; the last row/column cut to the overlay size)
local function BuildOverlays(L)
  for _, t in ipairs(L.ov) do t:Hide() end
  L.ov = {}
  local list = MD.Explored(L.id)
  if not list then return end
  local f = L.frame
  for _, e in ipairs(list) do
    local nw, nt = tonumber(e.numTexturesWide) or 1, tonumber(e.numTexturesTall) or 1
    local ow, oh = tonumber(e.textureWidth) or 0, tonumber(e.textureHeight) or 0
    local ox, oy = tonumber(e.offsetX) or 0, tonumber(e.offsetY) or 0
    for j = 1, nt do
      local ph = (j < nt) and 256 or (ow > 0 and (oh % 256 == 0 and 256 or oh % 256) or 256)
      local th = 256
      if j == nt then th = 16 while th < ph do th = th * 2 end end
      for k = 1, nw do
        local pw = (k < nw) and 256 or (ow % 256 == 0 and 256 or ow % 256)
        local tw = 256
        if k == nw then tw = 16 while tw < pw do tw = tw * 2 end end
        local fid = e.fileDataIDs[(j - 1) * nw + k]
        if fid and pw > 0 and ph > 0 then
          local t = f:CreateTexture(nil, "ARTWORK")
          t:SetSize(pw, ph)
          t:SetPoint("TOPLEFT", f, "TOPLEFT", ox + 256 * (k - 1), -(oy + 256 * (j - 1)))
          t:SetTexture(fid, nil, nil, "TRILINEAR")
          t:SetTexCoord(0, pw / tw, 0, ph / th)
          L.ov[#L.ov + 1] = t
        end
      end
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
  L = { id = id, art = art, frame = f, tiles = {}, ov = {}, built = false }
  M.layers[id] = L
  return L
end
-- place a layer whose art covers world rect (x1..x2, y1..y2) at alpha a (hidden when off screen or invisible)
local function Show(L, x1, x2, y1, y2, a)
  local l, t = M.ToScreen(x1, y1)
  local r, b = M.ToScreen(x2, y2)
  if a < 0.01 or r < 0 or b < 0 or l > VW() or t > VH() then L.frame:Hide() L.shown = false return false end
  if not L.built then BuildTiles(L) L.built = true end
  if not L.ovBuilt and L.wantOv then BuildOverlays(L) end
  local sc = (r - l) / L.art.w
  L.frame:SetScale(math.max(sc, 0.0001))
  L.frame:ClearAllPoints()
  L.frame:SetPoint("TOPLEFT", canvas, "TOPLEFT", l / sc, -t / sc)
  L.frame:SetAlpha(a)
  L.frame:Show()
  L.shown, L.alpha = true, a
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
local function MakeQuest()
  local q = CreateFrame("Button", nil, over)
  q:SetSize(18, 18)
  q.icon = q:CreateTexture(nil, "ARTWORK")
  q.icon:SetAllPoints(q)
  Icon(q.icon, "quest")
  if q.SetMouseClickEnabled then pcall(q.SetMouseClickEnabled, q, false) end -- clicks pass through to the map (drag)
  q:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(MD.QuestTitle(self.qid), 1, 0.82, 0)
    GameTooltip:AddLine("Quest objective (from the game's quest log)", 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  q:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
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
              local mk = Pool("quest", MakeQuest)
              mk.qid = q.id
              mk:ClearAllPoints()
              mk:SetPoint("CENTER", over, "TOPLEFT", qx, -qy)
              mk:Show()
            end
          end
        end
      end
    end
  end
  PoolHideRest("badge") PoolHideRest("quest")
  if caption then if anyBadge then caption:Show() else caption:Hide() end end
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
function M.Layout()
  M.dirty = false
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
      if M.ContAlpha(c.id) >= 0.999 and l <= 0 and t <= 0 and r >= VW() and b >= VH() then covered = true end
    end
    if L then if covered then L.frame:Hide() L.shown = false else Show(L, 0, 1, 0, 1, 1) end end
  end
  for _, c in ipairs(ContList()) do
    local cl = Layer(c.id, 2)
    local a = M.ContAlpha(c.id)
    if cl then local p = Place(c.id) Show(cl, p[1], p[2], p[3], p[4], a) end
    for _, z in ipairs(MD.Zones(c.id)) do
      local zl = Layer(z.id, z.area < 0.004 and 4 or 3)
      if zl then
        zl.wantOv = true
        local x1, x2, y1, y2 = WorldRect(z.id)
        Show(zl, x1, x2, y1, y2, a > 0 and M.ZoneAlpha(z) or 0)
      end
    end
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
FlyTo = function(id, wx, wy)
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
    if MD.Is(id, "continent") then
      local _, hi = ContBand(id)
      s = math.max(s, (hi + 0.02) * VW() / ((x2 - x1) * BW))
    end
  end
  local cx, cy = M.Center()
  fly = { t = 0, dur = 0.45, c0 = { cx, cy }, s0 = V.s, c1 = { wx or (x1 + x2) / 2, wy or (y1 + y2) / 2 }, s1 = s }
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

function M.Tick(dt)
  dt = math.min(dt or 0, 0.1)
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
    local s = math.exp(math.log(fly.s0) + (math.log(fly.s1) - math.log(fly.s0)) * e)
    SetView(fly.c0[1] + (fly.c1[1] - fly.c0[1]) * e, fly.c0[2] + (fly.c1[2] - fly.c0[2]) * e, s)
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
  SetView(f.wx or (x1 + x2) / 2, f.wy or (y1 + y2) / 2, 0.94 * math.min(VW() / ((x2 - x1) * BW), VH() / ((y2 - y1) * BH)))
  return true
end
local function Refit()
  if not vp then return end
  canvas:SetSize(VW(), VH())
  over:SetSize(VW(), VH())
  if not ApplyFit() then
    -- the view as last laid out (centre + zoom relative to the fit), so a new box size keeps the place
    local lv = M.lastView
    if lv then SetView(lv.cx, lv.cy, lv.z * SFit())
    else local cx, cy = M.Center() SetView(cx, cy, M.Zoom() * SFit()) end
  end
  M.Layout()
end
M.Refit = Refit

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

Crumbs = function()
  local t = Trail()
  local key = ""
  for _, s in ipairs(t) do key = key .. s.id .. ">" end
  if key == crumbKey then return end
  crumbKey = key
  for _, c in ipairs(crumbs) do c:Hide() if c.sep then c.sep:Hide() end end
  local x = 8
  for i, s in ipairs(t) do
    local c = crumbs[i]
    if not c then
      c = CreateFrame("Button", nil, bar)
      c:SetHeight(22)
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
    c.text:SetTextColor(NS.Color(last and "gold" or "listInk"))
    c.hoverInk = last and "gold" or "listInk"
    c:SetWidth((c.text:GetStringWidth() or 60) + 8)
    c:ClearAllPoints()
    c:SetPoint("LEFT", bar, "LEFT", x, 0)
    c:Show()
    x = x + (c.text:GetStringWidth() or 60) + 8
    if not last then
      c.sep:ClearAllPoints()
      c.sep:SetPoint("LEFT", bar, "LEFT", x + 2, 0)
      c.sep:Show()
      x = x + 16
    end
  end
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
  M.vp, M.canvas, M.over = vp, canvas, over
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
  vp:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" then M.pendingFit = nil local x, y = Cursor() drag = { x = x, y = y, ox = V.ox, oy = V.oy } fly, zoomT = nil, nil end
  end)
  vp:SetScript("OnMouseUp", function(_, btn)
    if btn == "RightButton" then M.ZoomOutLevel() return end
    if btn ~= "LeftButton" then return end
    local was = drag
    drag = nil
    if was and not was.moved then
      local now = (type(GetTime) == "function" and GetTime()) or 0
      if lastClick and now - lastClick < 0.35 then lastClick = nil M.ZoomAt(was.x, was.y, 2) else lastClick = now end
    end
  end)
  vp:SetScript("OnSizeChanged", function() Refit() end)
  root:SetScript("OnUpdate", function(_, dt) M.Tick(dt) end)

  -- right tool strip
  strip = CreateFrame("Frame", nil, vpBox)
  strip:SetFrameLevel(canvas:GetFrameLevel() + 20)
  strip:SetSize(40, 5 * 34 + 8)
  strip:SetPoint("TOPRIGHT", vp, "TOPRIGHT", -6, -6)
  local sbg = strip:CreateTexture(nil, "BACKGROUND")
  sbg:SetAllPoints(strip)
  sbg:SetColorTexture(0, 0, 0, 0.55)
  UI.NineSlice(strip, "pane", 4, "BORDER", 1)
  local tools = {
    ToolButton("starpen", "Starpen", "Draw on the map. Coming in 0.5.3.", true),
    ToolButton("pin", "Drop a pin", "Pins with notes, colours and minimap follow. Coming in 0.5.2.", true),
    ToolButton("town", "Town Pins", "Flight masters, innkeepers, vendors, trainers and more. Coming in 0.5.4.", true),
    ToolButton("findme", "Find me", "Jump to where you are.", false, function() M.FindMe() end),
    ToolButton("full", "Full screen", "", false, function() M.SetFull(not M.full) end),
  }
  for i, tb in ipairs(tools) do tb:SetPoint("TOP", strip, "TOP", 0, -5 - (i - 1) * 34) end
  M.tools = tools
  M.fullBtn = tools[5]
  SetFullIcon()

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
      if e == "QUEST_LOG_UPDATE" or e == "QUEST_WATCH_LIST_CHANGED" then MD.Forget("quests")
      elseif e == "MAP_EXPLORATION_UPDATED" then
        MD.Forget("explored")
        for _, L in pairs(M.layers) do L.ovBuilt = false end
      end
      M.dirty = true
    end)
  end
  for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "QUEST_LOG_UPDATE", "MAP_EXPLORATION_UPDATED" }) do
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
  NS.SetStatus("Dark Matter " .. NS.version .. "  \194\183  Map: the game's own map pictures")
end

-- re-read everything from the game (drops the built layers; the next show starts fresh)
function M.Reset()
  for _, L in pairs(M.layers) do L.frame:Hide() end
  M.layers, M.fade = {}, {}
  M.started, M.ready, M.only, M.hasWorld, M.player = false, false, nil, nil, nil
  M.pendingFit, M.lastView = nil, nil
  drag, zoomT, fly, crumbKey = nil, nil, nil, nil
  MD.Forget()
end

NS.RegisterTab({
  id = "map", name = "Map", glyph = "map",
  Build = Build,
  OnShow = function() Events(true) Start() end,
  OnHide = function()
    Events(false)
    drag, zoomT, fly = nil, nil, nil
    if M.full then M.SetFull(false) end
  end,
  Refresh = function() if M.started then M.dirty = true end end,
})
