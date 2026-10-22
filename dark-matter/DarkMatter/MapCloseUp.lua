-- 0.5.1.4 Map tab close-up detail: the game's own minimap tiles, loaded at runtime by file ID (Data_Minimap.lua, OpenMap's
-- MIT table), drawn over the zone maps when you zoom in past the zone picture's own sharpness. Nothing is bundled: every
-- tile is the client's file. Self-contained: it never needs (or looks at) any other addon's files.
-- Rules (ideas from OpenMap's Map/Close.lua, MIT; see LICENSES/THIRD_PARTY.md):
--   * tiles are 533.33 yards; tile x = 32 - worldY / 533.33 (runs east), tile y = 32 - worldX / 533.33 (runs south)
--   * fades are keyed to screen pixels per yard (ppy): the tiles mix in from 0.20 to 0.34 ppy at the chosen strength and
--     take over toward ~1.9x that strength (85% at the default 45%) from 0.30 to 0.48 ppy (0.48 = one tile pixel per
--     screen pixel). OpenMap's 20-34x / 30-48x zoom points, in Dark Matter's own units.
--   * at most 64 tiles in view; further out there is no middle layer: the parchment zone map alone shows
--   * softened toward the parchment: desaturated 0.35 and tinted (1, 0.93, 0.80)
--   * explored only: a tile is cut into 4 x 4 cells and a cell shows only where its zone's explored overlays
--     (C_MapExplorationInfo) cover it, so unexplored ground is never revealed; cells of one row are merged into strips
--     (no overlap, so no double-dark seams)
-- Taint-safe: own frames and textures only; no hooks, no WorldMapFrame, nothing protected; works in combat.
local _, NS = ...
local MD = NS.MapData
local C = { pool = {}, cells = {}, frames = {}, failed = {}, loaded = 0, fails = 0 }
NS.MapCloseUp = C

C.TILE = 1600 / 3
C.NATIVE_PPY = 256 / C.TILE          -- 0.48: one minimap pixel per screen pixel
C.MIX_FADE = { 0.20, 0.34 }          -- ppy where the tiles mix in (to the chosen strength)
C.DEEP_FADE = { 0.30, 0.48 }         -- ppy where they take over (toward DEEP_K x the strength, at most 1)
C.DEEP_K = 1.9
C.SOFT_FADE = { 0.08, 0.18 }         -- ppy where the paper grain comes in
C.GRAIN_ALPHA = 0.16
C.MAX_PPY = 2 * C.NATIVE_PPY         -- the deepest zoom: twice the minimap's own sharpness
C.MAX_TILES = 64
C.CELLS = 4
C.DESAT = 0.35
C.PAPER = { 1, 0.93, 0.80 }
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
function C.Mix(ppy, strength)
  strength = strength or C.Strength()
  if strength <= 0 then return 0 end
  local mix = strength * Smooth(ppy, C.MIX_FADE)
  local deep = math.min(1, strength * C.DEEP_K)
  return mix + (deep - mix) * Smooth(ppy, C.DEEP_FADE)
end

---------------------------------------------------------------------------
-- explored only: a tile's 4 x 4 cells, shown only where the zone's explored overlays cover them; merged into row strips
---------------------------------------------------------------------------
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
-- strips { col1, col2, row } (cells 0..3) of a tile on continent `cont`; cached until the explored map changes
function C.Strips(cont, F, tx, ty)
  local key = cont * 65536 + tx * 64 + ty
  local s = C.cells[key]
  if s then return s end
  s = {}
  local x1, x2, y1, y2 = C.TileRect(F, tx, ty)
  local n = C.CELLS
  for row = 0, n - 1 do
    local run
    for col = 0, n - 1 do
      local cx, cy = x1 + (col + 0.5) / n * (x2 - x1), y1 + (row + 0.5) / n * (y2 - y1)
      local z, zx, zy = MD.ZoneAt(cont, cx, cy)
      local on = z and Explored(z, zx, zy) or false
      if on then
        if run then run[2] = col else run = { col, col, row } s[#s + 1] = run end
      else run = nil end
    end
  end
  C.cells[key] = s
  return s
end
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
  local ok, r = pcall(t.SetTexture, t, fid, nil, nil, "LINEAR")
  if not ok or r == false then
    C.failed[fid] = true
    C.fails = C.fails + 1
    if C.loaded == 0 and C.fails >= 4 then C.unavailable = true end
    return false
  end
  C.loaded = C.loaded + 1
  return true
end

---------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------
local function Piece(host, i)
  local t = C.pool[i]
  if not t then
    t = host:CreateTexture(nil, "ARTWORK")
    if t.SetDesaturation then pcall(t.SetDesaturation, t, C.DESAT) end
    t:SetVertexColor(C.PAPER[1], C.PAPER[2], C.PAPER[3], 1)
    C.pool[i] = t
  end
  return t
end

-- ctx = { host, conts = { { id = cont, alpha } }, place(cont) -> {x1,x2,y1,y2} on the world, toScreen(wx, wy), vw, vh }
-- Returns a summary { shown pieces, tiles in view, mix, ppy } for tests and the probe.
function C.Layout(ctx)
  local host = ctx.host
  local used = 0
  local sum = { pieces = 0, tiles = 0, mix = 0, ppy = 0 }
  local on = C.Enabled() and C.Available()
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
      local mix = C.Mix(ppy) * calpha
      sum.ppy, sum.mix = math.max(sum.ppy, ppy), math.max(sum.mix, mix)
      if mix > 0.005 and cw > 0 and ch > 0 then
        -- the view on this continent's map (map coords), then in tiles
        local vx1, vx2 = (0 - l) / cw, (ctx.vw - l) / cw
        local vy1, vy2 = (0 - t) / ch, (ctx.vh - t) / ch
        local Xa, Ya = C.ToYards(F, vx1, vy1)
        local Xb, Yb = C.ToYards(F, vx2, vy2)
        local tx1, ty1 = C.TileAt(math.max(Xa, Xb), math.max(Ya, Yb))
        local tx2, ty2 = C.TileAt(math.min(Xa, Xb), math.min(Ya, Yb))
        tx1, ty1, tx2, ty2 = Clamp(tx1, 0, 63), Clamp(ty1, 0, 63), Clamp(tx2, 0, 63), Clamp(ty2, 0, 63)
        local count = (tx2 - tx1 + 1) * (ty2 - ty1 + 1)
        sum.tiles = sum.tiles + count
        if count <= C.MAX_TILES then
          for tx = tx1, tx2 do
            for ty = ty1, ty2 do
              local fid = C.FileFor(inst, tx, ty)
              if fid and not C.failed[fid] then
                local x1, x2, y1, y2 = C.TileRect(F, tx, ty)
                local n = C.CELLS
                for _, st in ipairs(C.Strips(cont, F, tx, ty)) do
                  local c1, c2, row = st[1], st[2], st[3]
                  local sx1, sx2 = l + (x1 + c1 / n * (x2 - x1)) * cw, l + (x1 + (c2 + 1) / n * (x2 - x1)) * cw
                  local sy1, sy2 = t + (y1 + row / n * (y2 - y1)) * ch, t + (y1 + (row + 1) / n * (y2 - y1)) * ch
                  if sx2 > 0 and sy2 > 0 and sx1 < ctx.vw and sy1 < ctx.vh then
                    used = used + 1
                    local tex = Piece(host, used)
                    if SetFile(tex, fid) then
                      tex:SetTexCoord(c1 / n, (c2 + 1) / n, row / n, (row + 1) / n)
                      tex:ClearAllPoints()
                      tex:SetPoint("TOPLEFT", host, "TOPLEFT", sx1, -sy1)
                      tex:SetSize(math.max(0.01, sx2 - sx1), math.max(0.01, sy2 - sy1))
                      tex:SetAlpha(mix)
                      tex.dmTile = tx * 64 + ty
                      tex:Show()
                    else
                      tex:Hide()
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  for i = used + 1, #C.pool do C.pool[i]:Hide() C.pool[i].dmTile = nil end
  for i = 1, used do if C.pool[i]:IsShown() then sum.pieces = sum.pieces + 1 end end
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
    local ga = on and C.GRAIN_ALPHA * Smooth(sum.ppy, C.SOFT_FADE) or 0
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
