-- 0.5.1.4 Map tab close-up detail: the game's own minimap tiles, loaded at runtime by file ID (Data_Minimap.lua, OpenMap's
-- MIT table), drawn over the zone maps when you zoom in past the zone picture's own sharpness. Nothing is bundled: every
-- tile is the client's file. Self-contained: it never needs (or looks at) any other addon's files.
-- Rules (ideas from OpenMap's Map/Close.lua, MIT; see LICENSES/THIRD_PARTY.md):
--   * tiles are 533.33 yards; tile x = 32 - worldY / 533.33 (runs east), tile y = 32 - worldX / 533.33 (runs south)
--   * fades are keyed to screen pixels per yard (ppy). 0.5.1.5: the tiles mix in from 0.12 to 0.24 ppy at the chosen
--     strength and take over (toward 1.9x the strength, 85% at the default 45%) from 0.24 to 0.48 ppy (0.48 = one tile
--     pixel per screen pixel), so a zone seen whole already carries them faintly and close up they carry the map
--   * up to 144 tiles in view, faded out from 96 on (no pop); further out the parchment zone map alone shows
--   * softened toward the parchment: desaturated 0.35 and tinted (1, 0.93, 0.80)
--   * 0.5.1.5: blended across the whole view (no explored-only cut-outs, so no square seams). Where the tiles end (open
--     sea, the void: no tile in the table, or a file that will not load) the last half tile fades out: such a tile's
--     neighbours are cut into 4 x 4 cells whose alpha ramps to 0 toward the gap (vertex gradients), so no block edge
-- Taint-safe: own frames and textures only; no hooks, no WorldMapFrame, nothing protected; works in combat.
local _, NS = ...
local MD = NS.MapData
local C = { pool = {}, cells = {}, frames = {}, failed = {}, loaded = 0, fails = 0 }
NS.MapCloseUp = C

C.TILE = 1600 / 3
C.NATIVE_PPY = 256 / C.TILE          -- 0.48: one minimap pixel per screen pixel
C.MIX_FADE = { 0.12, 0.24 }          -- ppy where the tiles mix in (to the chosen strength)
C.DEEP_FADE = { 0.24, 0.48 }         -- ppy where they take over (toward DEEP_K x the strength, at most 1)
C.DEEP_K = 1.9
C.SOFT_FADE = { 0.08, 0.18 }         -- ppy where the paper grain comes in
C.GRAIN_ALPHA = 0.16
C.MAX_PPY = 2 * C.NATIVE_PPY         -- the deepest zoom: twice the minimap's own sharpness
C.MAX_TILES = 144
C.FADE_TILES = 96                    -- from here to MAX_TILES the tiles fade out (no pop)
C.FEATHER = 0.5                      -- tiles: how far the edge fade reaches into a tile next to a gap
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
function C.Cells(inst, tx, ty)
  local key = inst * 65536 + tx * 64 + ty
  local c = C.cells[key]
  if c ~= nil then return c or nil end
  local gap = false
  for dx = -1, 1 do for dy = -1, 1 do if not There(inst, tx + dx, ty + dy) then gap = true end end end
  if not gap then C.cells[key] = false return nil end
  local n = C.CELLS
  local g = {}
  for i = 0, n do g[i] = {} for j = 0, n do g[i][j] = Weight(inst, tx, ty, i / n, j / n) end end
  c = {}
  for r = 0, n - 1 do
    for col = 0, n - 1 do
      local w00, w10, w01, w11 = g[col][r], g[col + 1][r], g[col][r + 1], g[col + 1][r + 1]
      if w00 + w10 + w01 + w11 > 0.001 then
        local dh = math.abs((w10 + w11) - (w00 + w01))
        local dv = math.abs((w01 + w11) - (w00 + w10))
        if dh >= dv then c[#c + 1] = { col, r, (w00 + w01) / 2, (w10 + w11) / 2, "HORIZONTAL" }
        else c[#c + 1] = { col, r, (w00 + w10) / 2, (w01 + w11) / 2, "VERTICAL" } end
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
  local ok, r = pcall(t.SetTexture, t, fid, nil, nil, "LINEAR")
  if not ok or r == false then
    C.failed[fid] = true
    C.cells = {} -- its neighbours now feather toward it
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

local PR, PG, PB = C.PAPER[1], C.PAPER[2], C.PAPER[3]
local CreateColor = _G.CreateColor
-- alpha a1 -> a2 across the texture (orient "HORIZONTAL": left -> right; "VERTICAL": top -> bottom). The game's
-- SetGradient runs min -> max as left -> right and bottom -> top.
local function Grad(t, orient, a1, a2)
  if math.abs(a1 - a2) < 0.01 then t:SetVertexColor(PR, PG, PB, (a1 + a2) / 2) return end
  local lo, hi = a1, a2
  if orient == "VERTICAL" then lo, hi = a2, a1 end
  if t.SetGradient and type(CreateColor) == "function" then
    local ok = pcall(t.SetGradient, t, orient, CreateColor(PR, PG, PB, lo), CreateColor(PR, PG, PB, hi))
    if ok then return end
  end
  if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, orient, PR, PG, PB, lo, PR, PG, PB, hi) then return end
  t:SetVertexColor(PR, PG, PB, (a1 + a2) / 2)
end
C.Grad = Grad

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
        -- 0.5.1.5: fade out as the view holds more tiles (no pop at the limit)
        local a = mix * (1 - Smooth(count, { C.FADE_TILES, C.MAX_TILES }))
        if count <= C.MAX_TILES and a > 0.005 then
          local function Put(fid, u1, u2, v1, v2, x1, x2, y1, y2, orient, a1, a2)
            local sx1, sx2 = l + (x1 + u1 * (x2 - x1)) * cw, l + (x1 + u2 * (x2 - x1)) * cw
            local sy1, sy2 = t + (y1 + v1 * (y2 - y1)) * ch, t + (y1 + v2 * (y2 - y1)) * ch
            if sx2 > 0 and sy2 > 0 and sx1 < ctx.vw and sy1 < ctx.vh then
              used = used + 1
              local tex = Piece(host, used)
              if SetFile(tex, fid) then
                tex:SetTexCoord(u1, u2, v1, v2)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", host, "TOPLEFT", sx1, -sy1)
                tex:SetSize(math.max(0.01, sx2 - sx1), math.max(0.01, sy2 - sy1))
                Grad(tex, orient or "HORIZONTAL", a1 or 1, a2 or 1)
                tex:SetAlpha(a)
                tex.dmA1, tex.dmA2 = a1 or 1, a2 or 1
                tex:Show()
              else
                tex:Hide()
              end
            end
          end
          for tx = tx1, tx2 do
            for ty = ty1, ty2 do
              local fid = There(inst, tx, ty) and C.FileFor(inst, tx, ty)
              if fid then
                local x1, x2, y1, y2 = C.TileRect(F, tx, ty)
                local cells = C.Cells(inst, tx, ty)
                local before = used
                if not cells then
                  Put(fid, 0, 1, 0, 1, x1, x2, y1, y2)
                else
                  local n = C.CELLS
                  for _, cl in ipairs(cells) do
                    Put(fid, cl[1] / n, (cl[1] + 1) / n, cl[2] / n, (cl[2] + 1) / n, x1, x2, y1, y2, cl[5], cl[3], cl[4])
                  end
                end
                for i = before + 1, used do C.pool[i].dmTile = tx * 64 + ty end
              end
            end
          end
        end
        sum.alpha = math.max(sum.alpha or 0, a)
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
