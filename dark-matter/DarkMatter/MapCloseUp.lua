-- 0.5.1.4 Map tab close-up detail: the game's own minimap tiles, loaded at runtime by file ID (Data_Minimap.lua, OpenMap's
-- MIT table), drawn over the zone maps when you zoom in past the zone picture's own sharpness. Nothing is bundled: every
-- tile is the client's file. Self-contained: it never needs (or looks at) any other addon's files.
-- Rules (ideas from OpenMap's Map/Close.lua, MIT; see LICENSES/THIRD_PARTY.md):
--   * tiles are 533.33 yards; tile x = 32 - worldY / 533.33 (runs east), tile y = 32 - worldX / 533.33 (runs south)
--   * fades are keyed to screen pixels per yard (ppy); 0.5.1.6 values below (C.MIX_FADE, C.MID_K, C.DEEP_FADE). 0.5.1.5 was: the tiles mix in from 0.12 to 0.24 ppy at the chosen
--     strength and take over (toward 1.9x the strength, 85% at the default 45%) from 0.24 to 0.48 ppy (0.48 = one tile
--     pixel per screen pixel), so a zone seen whole already carries them faintly and close up they carry the map
--   * 0.5.2b.5: the tiles come in by the LARGER of two rules: the art-blur rule (MAG_FADE below) and how many tiles fit
--     the view (full at FULL_TILES = 200, gone at OUT_TILES = 320: a smooth function of the zoom, so the crossfade
--     follows the wheel), with a cap on real tiles in view (faded FADE_TILES..MAX_TILES = 380..460). Each continent
--     is one scaled plane of tiles (built once, moved by SetPoint/SetScale on a pan), so 400+ tiles stay cheap
--   * softened toward the parchment: desaturated 0.35 and tinted (1, 0.93, 0.80)
--   * 0.5.1.5: blended across the whole view (no explored-only cut-outs, so no square seams). Where the tiles end (open
--     sea, the void: no tile in the table, or a file that will not load) the last half tile fades out: such a tile's
--     neighbours are cut into 4 x 4 cells (0.5.2b.5: 2 x 2 when a tile is under ~96 px) whose alpha ramps to 0 toward the gap (vertex gradients), so no block edge
-- Taint-safe: own frames and textures only; no hooks, no WorldMapFrame, nothing protected; works in combat.
local _, NS = ...
local MD = NS.MapData
local C = { pool = {}, cells = {}, frames = {}, failed = {}, loaded = 0, fails = 0 }
NS.MapCloseUp = C

C.TILE = 1600 / 3
C.NATIVE_PPY = 256 / C.TILE          -- 0.48: one minimap pixel per screen pixel
-- 0.5.1.8: two clean layers, like OpenMap. The game's own map art (zone pictures with their names painted in, city maps,
-- continent pictures) shows at 100% with NO tiles, tint or grain, until it is magnified past MAG_FADE[1] screen pixels
-- per art texel (the art starts to blur); then the minimap tiles take over quickly, fully in by MAG_FADE[2] (about one
-- wheel step later). No long middle range with both half visible. The magnification is the art layer under the middle
-- of the view (a city map wins over its zone); where no map art is there, about YD_PER_TEXEL yards per texel is assumed.
C.MAG_FADE = { 2.0, 2.6 }
C.YD_PER_TEXEL = 5
C.DEEP_K = 2.25                      -- full strength (1.0) at the default 45%
C.GRAIN_ALPHA = 0.16
C.MAX_PPY = 2 * C.NATIVE_PPY         -- the deepest zoom: twice the minimap's own sharpness
-- 0.5.2b.5: the tiles also reach out as far as the view holds no more than FULL_TILES tiles (a tile is sharp at any
-- size up to MAX_PPY; the limit is how many textures one view needs). From FULL_TILES to OUT_TILES (the tiles the view
-- would hold if it were all land: a smooth function of the zoom) they crossfade with the parchment maps; in a 1221 x
-- 729 view that is tiles of 67 px (full) down to 53 px (gone). Real tiles in view are capped as well (FADE..MAX_TILES).
C.FULL_TILES = 200
C.OUT_TILES = 320
C.MAX_TILES = 460
C.FADE_TILES = 380
C.FEATHER = 0.5                      -- tiles: how far the edge fade reaches into a tile next to a gap
C.CELLS = 4
-- 0.5.1.6: lighter and warmer, toward the zone pictures' parchment palette: desaturated half way, tinted warm, and a
-- second pass of the same tile added (ADD blend) in a warm parchment tone, which lifts the dark minimap tiles to the
-- zone art's brightness instead of darkening it
C.DESAT = 0.5
C.PAPER = { 1, 0.93, 0.78 }
C.GLOW = { 0.46, 0.38, 0.24 }
C.DEFAULT_MIX = 0.45
C.GRAIN = "Interface\\AddOns\\DarkMatter\\Media\\wow-parchment" -- Dark Matter's own generated parchment (no game art)
C.LABEL_ON = "Map: the game's map pictures + the game's minimap tiles up close"
C.LABEL_OFF = "Map: the game's own map pictures"

local function N(v) if type(v) == "number" and v == v then return v end end
local function Clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function Smooth(x, r)
  local t = Clamp((x - r[1]) / (r[2] - r[1]), 0, 1)
  return t * t * (3 - 2 * t)
end
C.Smooth = Smooth

---------------------------------------------------------------------------
-- settings (DarkMatterDB.map.closeUp / closeMix)
---------------------------------------------------------------------------
local function DB()
  if not NS.db then return {} end
  NS.db.map = NS.db.map or {}
  return NS.db.map
end
function C.Enabled() return DB().closeUp ~= false end
function C.Strength() local v = N(DB().closeMix) return v and Clamp(v, 0, 1) or C.DEFAULT_MIX end
function C.SetEnabled(on) DB().closeUp = on and true or false if NS.MapTab then NS.MapTab.dirty = true end end
function C.SetStrength(v) DB().closeMix = Clamp(N(v) or C.DEFAULT_MIX, 0, 1) if NS.MapTab then NS.MapTab.dirty = true end end
-- true when the data table is there and the tiles have not proven unloadable
function C.Available()
  return type(NS.MinimapTiles) == "table" and not C.unavailable
end
function C.Label()
  if C.Enabled() and C.Available() then return C.LABEL_ON end
  return C.LABEL_OFF
end

---------------------------------------------------------------------------
-- yards <-> continent map coords (the game's own corners of the continent's map)
---------------------------------------------------------------------------
local function WorldPos(mapID, x, y)
  local cm = _G.C_Map
  local f = type(cm) == "table" and cm.GetWorldPosFromMapPos
  if type(f) ~= "function" then return end
  local v
  local V = _G.CreateVector2D
  if type(V) == "function" then local ok, r = pcall(V, x, y) if ok and type(r) == "table" then v = r end end
  v = v or { x = x, y = y }
  local ok, inst, wp = pcall(f, mapID, v)
  if not ok or type(wp) ~= "table" then return end
  local wx, wy = wp.x, wp.y
  if type(wp.GetXY) == "function" then local ok2, a, b = pcall(wp.GetXY, wp) if ok2 then wx, wy = a, b end end
  if N(wx) and N(wy) then return N(inst), wx, wy end
end
C.WorldPos = WorldPos

-- { inst, X0, Y0, X1, Y1 } for a map: world X runs north-south (X0 at the top), Y east-west (Y0 at the left)
function C.Frame(mapID)
  local c = C.frames[mapID]
  if c == nil then
    c = false
    local inst, x0, y0 = WorldPos(mapID, 0, 0)
    local _, x1, y1 = WorldPos(mapID, 1, 1)
    if x0 and x1 and x0 ~= x1 and y0 ~= y1 then c = { inst = inst, X0 = x0, Y0 = y0, X1 = x1, Y1 = y1 } end
    C.frames[mapID] = c
  end
  return c or nil
end
function C.ToYards(F, x, y) return F.X0 + y * (F.X1 - F.X0), F.Y0 + x * (F.Y1 - F.Y0) end -- map x,y -> world X, Y
function C.FromYards(F, X, Y) return (Y - F.Y0) / (F.Y1 - F.Y0), (X - F.X0) / (F.X1 - F.X0) end
-- the minimap tile under world X, Y
function C.TileAt(X, Y) return math.floor(32 - Y / C.TILE), math.floor(32 - X / C.TILE) end
-- a tile's rectangle on the map: x1, x2, y1, y2 (map coords)
function C.TileRect(F, tx, ty)
  local xa, ya = C.FromYards(F, (32 - ty) * C.TILE, (32 - tx) * C.TILE)
  local xb, yb = C.FromYards(F, (31 - ty) * C.TILE, (31 - tx) * C.TILE)
  return math.min(xa, xb), math.max(xa, xb), math.min(ya, yb), math.max(ya, yb)
end
function C.FileFor(inst, tx, ty)
  local list = NS.MinimapTiles and inst and NS.MinimapTiles[inst]
  return list and list[tx * 64 + ty]
end
-- screen pixels per yard for a continent drawn `px` screen pixels wide
function C.PixelsPerYard(F, px) return px / math.abs(F.Y1 - F.Y0) end
-- the tiles' strength at a ppy (0 off)
-- 0.5.2b.5: n = the tiles the view holds (optional): the larger of the art-blur rule and the tile-count rule
function C.Density(n) return 1 - Smooth(n, { C.FULL_TILES, C.OUT_TILES }) end
function C.Mix(mag, strength, n)
  strength = strength or C.Strength()
  if strength <= 0 then return 0 end
  local m = Smooth(mag or 0, C.MAG_FADE)
  if n then m = math.max(m, C.Density(n)) end
  return math.min(1, strength * C.DEEP_K) * m
end
-- which layer shows at this mix: "zone art", "crossfading" or "tiles"
function C.LayerName(mix, strength)
  local deep = math.min(1, (strength or C.Strength()) * C.DEEP_K)
  if not mix or mix < 0.005 then return "zone art" end
  if mix >= deep - 0.005 then return "tiles" end
  return "crossfading"
end

---------------------------------------------------------------------------
-- 0.5.1.5: feathered edges. A tile is "there" when the table has it and it has not failed to load. A tile with a gap
-- among its 8 neighbours is drawn as 4 x 4 cells whose alpha falls to 0 over FEATHER tiles toward the gap; any other
-- tile is one texture. Cached per tile until a load fails.
---------------------------------------------------------------------------
local function There(inst, tx, ty)
  if tx < 0 or ty < 0 or tx > 63 or ty > 63 then return false end
  local fid = C.FileFor(inst, tx, ty)
  return fid ~= nil and not C.failed[fid]
end
C.There = There
-- weight (0..1) of a point u, v (0..1 inside tile tx, ty): 0 at a gap, 1 from FEATHER tiles away
local function Weight(inst, tx, ty, u, v)
  local w = 1
  for dx = -1, 1 do
    for dy = -1, 1 do
      if (dx ~= 0 or dy ~= 0) and not There(inst, tx + dx, ty + dy) then
        local ex = dx < 0 and u or (dx > 0 and 1 - u) or 0
        local ey = dy < 0 and v or (dy > 0 and 1 - v) or 0
        local d
        if dx ~= 0 and dy ~= 0 then d = math.sqrt(ex * ex + ey * ey) elseif dx ~= 0 then d = ex else d = ey end
        w = math.min(w, Smooth(d, { 0, C.FEATHER }))
      end
    end
  end
  return w
end
C.Weight = Weight
-- nil for a tile with no gap around it, else its cells { c, r, a1, a2, orient } (alpha a1 -> a2 left->right or top->bottom)
function C.Cells(inst, tx, ty, cells)
  local n = cells or C.CELLS
  local key = (inst * 65536 + tx * 64 + ty) * 8 + n
  local c = C.cells[key]
  if c ~= nil then return c or nil end
  local gap = false
  for dx = -1, 1 do for dy = -1, 1 do if not There(inst, tx + dx, ty + dy) then gap = true end end end
  if not gap then C.cells[key] = false return nil end
  local g = {}
  for i = 0, n do g[i] = {} for j = 0, n do g[i][j] = Weight(inst, tx, ty, i / n, j / n) end end
  c = {}
  for r = 0, n - 1 do
    for col = 0, n - 1 do
      local w00, w10, w01, w11 = g[col][r], g[col + 1][r], g[col][r + 1], g[col + 1][r + 1]
      if w00 + w10 + w01 + w11 > 0.001 then
        local o, a1, a2 = C.CornerGrad(w00, w10, w01, w11)
        c[#c + 1] = { col, r, a1, a2, o }
      end
    end
  end
  C.cells[key] = c
  return c
end
-- kept for the probe and tests (0.5.1.4 name): the explored test, informational now
local function Explored(z, zx, zy)
  local art = MD.Art(z.id)
  local list = MD.Explored(z.id)
  if not art or type(list) ~= "table" then return false end
  local px, py = zx * art.w, zy * art.h
  for _, e in ipairs(list) do
    local ox, oy = N(e.offsetX) or 0, N(e.offsetY) or 0
    local w, h = N(e.textureWidth) or 0, N(e.textureHeight) or 0
    if px >= ox and px <= ox + w and py >= oy and py <= oy + h then return true end
  end
  return false
end
C.ExploredAt = Explored
function C.Forget() C.cells = {} end
function C.Reset() C.cells, C.frames = {}, {} end

---------------------------------------------------------------------------
-- loading: a tile that the client refuses (SetTexture returns false) is remembered; if the first tiles all fail, the
-- close-up is switched off for the session (plain zone art; the status line says so)
---------------------------------------------------------------------------
local probeFrame, probeTex
-- one hidden test texture (the probe's "does this file load?" question); never shown
function C.TestLoad(file)
  if not probeFrame then
    probeFrame = CreateFrame("Frame", nil, UIParent)
    probeFrame:SetSize(1, 1)
    probeFrame:Hide()
    probeTex = probeFrame:CreateTexture(nil, "BACKGROUND")
  end
  local ok, r = pcall(probeTex.SetTexture, probeTex, file)
  if not ok or r == false then return false end
  local id = probeTex.GetTextureFileID and select(2, pcall(probeTex.GetTextureFileID, probeTex))
  if r == nil and id == nil then return nil end -- the client gives no answer either way
  return true, N(id)
end
local function SetFile(t, fid)
  if t.dmFile == fid then return not C.failed[fid] end
  t.dmFile = fid
  local ok, r = pcall(t.SetTexture, t, fid, nil, nil, "TRILINEAR")
  if not ok or r == false then
    C.failed[fid] = true
    C.cells = {} -- its neighbours now feather toward it
    C.dirtyAll = true
    C.fails = C.fails + 1
    if C.loaded == 0 and C.fails >= 4 then C.unavailable = true end
    return false
  end
  C.loaded = C.loaded + 1
  return true
end

---------------------------------------------------------------------------
-- drawing. 0.5.2b.5: one "plane" frame per continent holds that continent's tile pieces, laid out once in tile units
-- (256 per tile across); a pan or zoom only moves and scales the plane, and the fade is the plane's alpha. So a view
-- can hold a few hundred tiles without re-placing every texture each frame. A tile is built when it comes into view
-- and released (its textures pooled) when it leaves.
---------------------------------------------------------------------------
C.planes = {}
local function Plane(host, cont)
  local P = C.planes[cont]
  if P and P.host == host then return P end
  local f = CreateFrame("Frame", nil, host)
  f:SetSize(1, 1)
  if f.EnableMouse then f:EnableMouse(false) end
  f:Hide()
  P = { host = host, f = f, tiles = {}, free = {}, cont = cont, a = 0 }
  C.planes[cont] = P
  return P
end
local function NewPiece(P)
  local t = table.remove(P.free)
  if t then return t end
  local host = P.f
  t = host:CreateTexture(nil, "ARTWORK")
  if t.SetDesaturation then pcall(t.SetDesaturation, t, C.DESAT) end
  t:SetVertexColor(C.PAPER[1], C.PAPER[2], C.PAPER[3], 1)
  local g = host:CreateTexture(nil, "ARTWORK", nil, 1)
  if g.SetDesaturation then pcall(g.SetDesaturation, g, 1) end
  if g.SetBlendMode then pcall(g.SetBlendMode, g, "ADD") end
  g:SetVertexColor(C.GLOW[1], C.GLOW[2], C.GLOW[3], 1)
  g:Hide()
  t.glow, t.dmPlane = g, P
  C.pool[#C.pool + 1] = t
  return t
end
local function Release(P, key)
  local list = P.tiles[key]
  if not list then return end
  for _, t in ipairs(list) do
    t:Hide()
    if t.glow then t.glow:Hide() end
    t.dmTile = nil
    P.free[#P.free + 1] = t
  end
  P.tiles[key] = nil
end
local function ReleaseAll(P) for k in pairs(P.tiles) do Release(P, k) end end
C.ReleaseAll = ReleaseAll

local PR, PG, PB = C.PAPER[1], C.PAPER[2], C.PAPER[3]
local CreateColor = _G.CreateColor
-- alpha a1 -> a2 across the texture (orient "HORIZONTAL": left -> right; "VERTICAL": top -> bottom). The game's
-- SetGradient runs min -> max as left -> right and bottom -> top.
local function Grad(t, orient, a1, a2, cr, cg, cb)
  local R, G, B = cr or PR, cg or PG, cb or PB
  if math.abs(a1 - a2) < 0.01 then t:SetVertexColor(R, G, B, (a1 + a2) / 2) return end
  local lo, hi = a1, a2
  if orient == "VERTICAL" then lo, hi = a2, a1 end
  if t.SetGradient and type(CreateColor) == "function" then
    local ok = pcall(t.SetGradient, t, orient, CreateColor(R, G, B, lo), CreateColor(R, G, B, hi))
    if ok then return end
  end
  if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, orient, R, G, B, lo, R, G, B, hi) then return end
  t:SetVertexColor(R, G, B, (a1 + a2) / 2)
end
C.Grad = Grad
-- a cell's four corner weights -> one gradient (the axis along which they change most): orient, a1, a2
function C.CornerGrad(w00, w10, w01, w11)
  local dh = math.abs((w10 + w11) - (w00 + w01))
  local dv = math.abs((w01 + w11) - (w00 + w10))
  if dh >= dv then return "HORIZONTAL", (w00 + w01) / 2, (w10 + w11) / 2 end
  return "VERTICAL", (w00 + w10) / 2, (w01 + w11) / 2
end
-- 0.5.1.6: the window is built again: the pooled textures hang off the old map
function C.Drop()
  for _, t in ipairs(C.pool) do t:Hide() if t.glow then t.glow:Hide() end end
  for _, P in pairs(C.planes) do P.f:Hide() end
  if C.grain then C.grain:Hide() end
  C.pool, C.grain, C.cells, C.planes = {}, nil, {}, {}
end

-- one tile's pieces on its plane (one texture, or C.Cells cells where the tiles end)
local function BuildTile(P, inst, tx, ty, fid, n)
  local list = {}
  local K = P.K
  local function Put(u1, u2, v1, v2, orient, a1, a2)
    local t = NewPiece(P)
    if not SetFile(t, fid) then
      t:Hide() if t.glow then t.glow:Hide() end
      P.free[#P.free + 1] = t
      return
    end
    local x, y, w, h = (tx + u1) * 256, (ty + v1) * K, (u2 - u1) * 256, (v2 - v1) * K
    t:SetTexCoord(u1, u2, v1, v2)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", P.f, "TOPLEFT", x, -y)
    t:SetSize(math.max(0.01, w), math.max(0.01, h))
    t.dmX, t.dmY, t.dmW, t.dmH = x, y, w, h
    Grad(t, orient or "HORIZONTAL", a1 or 1, a2 or 1)
    t.dmA1, t.dmA2 = a1 or 1, a2 or 1
    t.dmTile = tx * 64 + ty
    t:Show()
    local g = t.glow
    if g then
      if g.dmFile ~= fid then g.dmFile = fid pcall(g.SetTexture, g, fid, nil, nil, "TRILINEAR") end
      g:SetTexCoord(u1, u2, v1, v2)
      g:ClearAllPoints()
      g:SetAllPoints(t)
      Grad(g, orient or "HORIZONTAL", a1 or 1, a2 or 1, C.GLOW[1], C.GLOW[2], C.GLOW[3])
      g:Show()
    end
    list[#list + 1] = t
  end
  local cells = C.Cells(inst, tx, ty, n)
  if not cells then
    Put(0, 1, 0, 1)
  else
    for _, cl in ipairs(cells) do Put(cl[1] / n, (cl[1] + 1) / n, cl[2] / n, (cl[2] + 1) / n, cl[5], cl[3], cl[4]) end
  end
  P.tiles[tx * 64 + ty] = list
end
-- a piece's rectangle on the host (screen px: left, top, right, bottom) and its drawn alpha (tests and the probe)
function C.ScreenRect(t)
  local P = t.dmPlane
  if not (P and P.sc and t.dmX) then return end
  return P.Ox + t.dmX * P.sc, P.Oy + t.dmY * P.sc, P.Ox + (t.dmX + t.dmW) * P.sc, P.Oy + (t.dmY + t.dmH) * P.sc
end
function C.PieceAlpha(t) local P = t.dmPlane return (P and P.f:IsShown() and P.a or 0) * (t._alpha or 1) end
-- the cells per tile side where the tiles end: 4 up close, 2 when a tile is small on screen (fewer textures); with a
-- little hysteresis so a zoom step does not flip it back and forth
function C.CellsFor(tpx, prev)
  if prev == 4 then return tpx >= 88 and 4 or 2 end
  if prev == 2 then return tpx >= 104 and 4 or 2 end
  return tpx >= 96 and 4 or 2
end
-- is there a tile (in the table, not refused) at continent map coords x, y?
function C.Covers(cont, x, y)
  local F = C.Frame(cont)
  if not F then return false end
  local X, Y = C.ToYards(F, x, y)
  local tx, ty = C.TileAt(X, Y)
  return There(F.inst, tx, ty)
end

-- ctx = { host, conts = { { id = cont, alpha } }, place(cont) -> {x1,x2,y1,y2} on the world, toScreen(wx, wy), vw, vh,
-- mag, dry }. Returns a summary { pieces shown, tiles (real tiles in view), est (tiles the view holds), tpx (tile size
-- on screen), mix, alpha, ppy, cells, byCont[cont] = alpha } for tests and the probes. ctx.dry (the sweep) works the
-- strengths out without drawing anything.
function C.Layout(ctx)
  local host, dry = ctx.host, ctx.dry
  local sum = { pieces = 0, tiles = 0, mix = 0, ppy = 0, est = 0, tpx = 0, byCont = {}, estBy = {}, tpxBy = {} }
  local on = C.Enabled() and C.Available()
  if C.dirtyAll and not dry then
    C.dirtyAll = nil
    for _, P in pairs(C.planes) do ReleaseAll(P) end
  end
  local seen = {}
  for _, ce in ipairs(on and ctx.conts or {}) do
    local cont, calpha = ce.id, ce.alpha or 1
    local F = calpha > 0.01 and C.Frame(cont)
    local inst = F and F.inst
    if F and NS.MinimapTiles and NS.MinimapTiles[inst] then
      local p = ctx.place(cont)
      local l, t = ctx.toScreen(p[1], p[3])
      local r, b = ctx.toScreen(p[2], p[4])
      local cw, ch = r - l, b - t
      local ppy = C.PixelsPerYard(F, cw)
      local mag = ctx.mag or ppy * C.YD_PER_TEXEL
      -- the plane: where tile 0,0 sits on screen and one tile's step across and down
      local ax1, _, ay1 = C.TileRect(F, 0, 0)
      local bx1, _, by1 = C.TileRect(F, 1, 1)
      local sx, sy = (bx1 - ax1) * cw, (by1 - ay1) * ch
      local est = (sx > 0 and sy > 0) and (ctx.vw * ctx.vh) / (sx * sy) or math.huge
      local mix = C.Mix(mag, nil, est) * calpha
      sum.ppy, sum.mix, sum.mag = math.max(sum.ppy, ppy), math.max(sum.mix, mix), math.max(sum.mag or 0, mag)
      if est < math.huge then sum.est, sum.tpx = math.max(sum.est, est), math.max(sum.tpx, sx) end
      sum.estBy[cont], sum.tpxBy[cont] = est, sx
      local a = 0
      if mix > 0.005 and cw > 0 and ch > 0 and sx > 0 and sy > 0 then
        -- the view on this continent's map (map coords), then in tiles
        local vx1, vx2 = (0 - l) / cw, (ctx.vw - l) / cw
        local vy1, vy2 = (0 - t) / ch, (ctx.vh - t) / ch
        local Xa, Ya = C.ToYards(F, vx1, vy1)
        local Xb, Yb = C.ToYards(F, vx2, vy2)
        local tx1, ty1 = C.TileAt(math.max(Xa, Xb), math.max(Ya, Yb))
        local tx2, ty2 = C.TileAt(math.min(Xa, Xb), math.min(Ya, Yb))
        tx1, ty1, tx2, ty2 = Clamp(tx1, 0, 63), Clamp(ty1, 0, 63), Clamp(tx2, 0, 63), Clamp(ty2, 0, 63)
        local count = 0
        for tx = tx1, tx2 do for ty = ty1, ty2 do if There(inst, tx, ty) then count = count + 1 end end end
        sum.tiles = sum.tiles + count
        -- a hard cap on real tiles in view, faded (no pop)
        a = mix * (1 - Smooth(count, { C.FADE_TILES, C.MAX_TILES }))
        if a > 0.005 and not dry then
          local P = Plane(host, cont)
          local sc = sx / 256
          local K = sy / sc
          local n = C.CellsFor(sx, P.n)
          if P.inst ~= inst or P.n ~= n or not P.K or math.abs(P.K - K) > 1e-3 * K then
            ReleaseAll(P)
            P.inst, P.n, P.K = inst, n, K
          end
          sum.cells = n
          local Ox, Oy = l + ax1 * cw, t + ay1 * ch
          if P.sc ~= sc or P.Ox ~= Ox or P.Oy ~= Oy then
            P.f:SetScale(math.max(sc, 0.0001))
            P.f:ClearAllPoints()
            P.f:SetPoint("TOPLEFT", host, "TOPLEFT", Ox / sc, -Oy / sc)
            P.sc, P.Ox, P.Oy = sc, Ox, Oy
          end
          if P.a ~= a then P.f:SetAlpha(a) P.a = a end
          P.f:Show()
          seen[cont] = true
          -- release the tiles that left the view, build the ones that came in
          for key in pairs(P.tiles) do
            local kx, ky = math.floor(key / 64), key % 64
            if kx < tx1 or kx > tx2 or ky < ty1 or ky > ty2 then Release(P, key) end
          end
          for tx = tx1, tx2 do
            for ty = ty1, ty2 do
              local key = tx * 64 + ty
              if not P.tiles[key] and There(inst, tx, ty) then BuildTile(P, inst, tx, ty, C.FileFor(inst, tx, ty), n) end
              for _, pc in ipairs(P.tiles[key] or {}) do if pc:IsShown() then sum.pieces = sum.pieces + 1 end end
            end
          end
        end
        sum.alpha = math.max(sum.alpha or 0, a)
      end
      sum.byCont[cont] = a
    end
  end
  sum.layer = C.LayerName(sum.mix)
  if dry then return sum end
  for cont, P in pairs(C.planes) do
    if not seen[cont] and (P.f:IsShown() or next(P.tiles)) then P.f:Hide() ReleaseAll(P) P.a = 0 end
  end
  C.last = sum
  -- the paper grain: Dark Matter's own parchment, faint, anchored to the map so it pans with it
  local g = C.grain
  if not g and host then
    g = host:CreateTexture(nil, "OVERLAY")
    g:SetTexture(C.GRAIN, "REPEAT", "REPEAT")
    if g.SetDesaturation then pcall(g.SetDesaturation, g, 1) end
    g:SetVertexColor(0.42, 0.33, 0.2, 1)
    g:SetAllPoints(host)
    C.grain = g
  end
  if g then
    local ga = on and C.GRAIN_ALPHA * sum.mix or 0 -- 0.5.1.8: no grain on the clean map art
    if ga > 0.005 then
      local ox, oy = ctx.toScreen(0, 0)
      local u0, v0 = -ox / 512, -oy / 512
      g:SetTexCoord(u0, u0 + ctx.vw / 512, v0, v0 + ctx.vh / 512)
      g:SetAlpha(ga)
      g:Show()
    else
      g:Hide()
    end
    sum.grain = ga
  end
  return sum
end

-- the deepest zoom for a continent drawn `px` wide at scale s: the scale at which it reaches MAX_PPY
function C.MaxScale(cont, widthAtScale1)
  local F = C.Frame(cont)
  if not F or not widthAtScale1 or widthAtScale1 <= 0 then return nil end
  return C.MAX_PPY * math.abs(F.Y1 - F.Y0) / widthAtScale1
end

-- 0.5.2b.5: /dm tileprobe: how many tiles the table has per continent and whether a spread sample of them loads
C.NAMES = { [0] = "Eastern Kingdoms", [1] = "Kalimdor" }
function C.Coverage(inst, sample)
  local list = NS.MinimapTiles and NS.MinimapTiles[inst]
  local r = { n = 0, ok = 0, no = 0, unknown = 0, tried = 0 }
  if type(list) ~= "table" then return r end
  local keys = {}
  for k in pairs(list) do keys[#keys + 1] = k end
  table.sort(keys)
  r.n = #keys
  for _, k in ipairs(keys) do
    local x, y = math.floor(k / 64), k % 64
    r.x1, r.x2 = math.min(r.x1 or x, x), math.max(r.x2 or x, x)
    r.y1, r.y2 = math.min(r.y1 or y, y), math.max(r.y2 or y, y)
  end
  local step = math.max(1, math.floor(#keys / math.max(1, sample or 48)))
  for i = 1, #keys, step do
    local a = C.TestLoad(list[keys[i]])
    r.tried = r.tried + 1
    if a == true then r.ok = r.ok + 1 elseif a == false then r.no = r.no + 1 else r.unknown = r.unknown + 1 end
  end
  return r
end
