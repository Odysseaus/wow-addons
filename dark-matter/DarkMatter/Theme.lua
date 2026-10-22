-- Theme layer. A theme is plain DATA: an atlas (texture file + piece rectangles), a few big textures,
-- metrics (sizes and offsets in UI units, taken from the approved previewer mockup), colours and a title.
-- Window code never branches on a theme id; it asks NS.theme for numbers, colours and atlas pieces.
-- Class themes (Theme_Classes.lua, 0.4.2) set base = "wow": they share the WoW layout (metrics, atlas, glyphs)
-- and add data only: colours, flat widget looks (theme.flat), tinted surfaces (theme.surface) and frame art (theme.classArt).
local _, NS = ...

NS.themes = NS.themes or {}
NS.themeOrder = NS.themeOrder or {}
NS.atlases = NS.atlases or {}
NS.theme = nil

local skins = {}
local WHITE = "Interface\\Buttons\\WHITE8X8"
NS.WHITE = WHITE
local flatTex = setmetatable({}, { __mode = "k" }) -- textures currently painted flat (side table: no fields on regions)

local function Hex(h)
  local r, g, b, a = string.match(h, "^#?(%x%x)(%x%x)(%x%x)(%x?%x?)$") -- #rrggbb or #rrggbbaa
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, a ~= "" and tonumber(a, 16) / 255 or nil }
end
NS.Hex = Hex

function NS.RegisterTheme(def)
  local base = def.base and NS.themes[def.base]
  if base then
    def.atlas = def.atlas or base.atlas
    def.media = def.media or base.media
    def.m = def.m or base.m
    def.glyphs = def.glyphs or base.glyphs
    def.colors = def.colors or {}
    for k, v in pairs(base.colors) do
      if def.colors[k] == nil then def.colors[k] = (base.baseColors and base.baseColors[k]) or v end
    end
    -- 0.5.1.3: a class theme's inner content blends into its frame instead of reading as a second boxed window: the
    -- page behind the lists is see-through (the frame's own surface shows), the rail a light wash of its surface, the
    -- lists a little see-through, and the page / rail edges are subtle inset dividers (dark top-left, faint light
    -- bottom-right) instead of a box border. Alphas per surface; Theme_ClassStock.lua may tune them per theme.
    if def.blend == nil then
      def.blend = { page = 0, rail = 0.35, list = 0.8, edge = 0.5,
        shadow = { 0, 0, 0, 0.5 }, light = { 1, 1, 1, 0.08 } }
    end
  end
  -- colours may be given as "#rrggbb"; convert once
  for k, v in pairs(def.colors or {}) do
    if type(v) == "string" then def.colors[k] = Hex(v) end
  end
  NS.themes[def.id] = def
  NS.themeOrder[#NS.themeOrder + 1] = def.id
  if not NS.theme then NS.theme = def end
end

-- A widget registers a function that (re)applies theme data to itself; it runs now and on every theme change.
function NS.OnSkin(fn)
  fn()
  skins[#skins + 1] = fn
end

function NS.SetTheme(id)
  local def = NS.themes[id]
  if not def then return false end
  NS.theme = def
  if NS.db then NS.db.theme = id end
  NS.lastSkinError = nil
  for _, fn in ipairs(skins) do
    local ok, err = pcall(fn)
    if not ok then NS.lastSkinError = tostring(err) end
  end
  -- rows paint their selection highlight on refresh, so repaint the open tab too
  if NS.RefreshWindow then pcall(NS.RefreshWindow) end
  return true
end

-- Next theme id in registration order (for /dm theme next).
function NS.NextThemeId()
  local cur = NS.theme and NS.theme.id
  for i, id in ipairs(NS.themeOrder) do
    if id == cur then return NS.themeOrder[i % #NS.themeOrder + 1] end
  end
  return NS.themeOrder[1]
end

function NS.Color(key)
  local c = NS.theme.colors[key] or { 1, 0, 1 }
  return c[1], c[2], c[3]
end

function NS.Metric(key)
  return NS.theme.m[key]
end

function NS.Rect(key)
  local a = NS.atlases[NS.theme.atlas]
  return a and a.rects[key]
end

-- Flat look for an atlas piece in the current theme ("btn_red_l" -> theme.flat.btn_red), or nil.
function NS.FlatSpec(key)
  local fl = NS.theme and NS.theme.flat
  if not fl or type(key) ~= "string" then return nil end
  if fl[key] then return fl[key] end
  local p = string.match(key, "^(.-)_[tblrm][lr]?$")
  return p and fl[p] or nil
end

-- Paint a texture as a flat colour or a two-stop gradient (a = top/left, b = bottom/right).
function NS.PaintFlat(tex, a, b, dir)
  b = b or a
  tex:SetTexture(WHITE)
  tex:SetTexCoord(0, 1, 0, 1)
  flatTex[tex] = true
  if CreateColor and tex.SetGradient then
    local lo, hi = a, b
    if dir ~= "HORIZONTAL" then lo, hi = b, a end -- VERTICAL: min colour is the bottom
    local ok = pcall(tex.SetGradient, tex, dir == "HORIZONTAL" and "HORIZONTAL" or "VERTICAL",
      CreateColor(lo[1], lo[2], lo[3], lo[4] or 1), CreateColor(hi[1], hi[2], hi[3], hi[4] or 1))
    if ok then return end
  end
  tex:SetVertexColor((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, ((a[4] or 1) + (b[4] or 1)) / 2)
end

-- Undo PaintFlat before a texture shows atlas art again.
local function Unflat(tex)
  if flatTex[tex] then
    flatTex[tex] = nil
    tex:SetVertexColor(1, 1, 1, 1)
  end
end
NS.Unflat = Unflat

-- Point a texture at one atlas piece (half a texel inset so neighbouring pieces never bleed in).
-- In a class theme the pieces listed in theme.flat are painted as flat gradients instead.
function NS.SetPiece(tex, key)
  local spec = NS.FlatSpec(key)
  if spec then NS.PaintFlat(tex, spec.a, spec.b, spec.dir) return end
  -- 0.5.1: the WoW theme's stock (built-in game) texture for this piece, when the client has it
  local sp = NS.Stock and NS.Stock.Spec(key)
  if sp then NS.Stock.Apply(tex, sp) return end
  local a = NS.atlases[NS.theme.atlas]
  local r = a and a.rects[key]
  if not r then return end
  Unflat(tex)
  if NS.Stock then NS.Stock.Reset(tex) end
  tex:SetTexture(a.file)
  local e = 0.5
  tex:SetTexCoord((r[1] + e) / a.width, (r[1] + r[3] - e) / a.width, (r[2] + e) / a.height, (r[2] + r[4] - e) / a.height)
end

-- Class-theme surface for one area ("shell", "rail", "list", "page"): the class texture tinted ({ tint = rgb }) or a
-- flat colour/gradient ({ flat = true, a, b, dir }) where the previewer uses a plain CSS background.
-- Returns false (texture untouched) when the theme has no surfaces; the caller then applies the WoW media.
-- 0.5.1.3: the surface's alpha follows theme.blend (1 for every surface of a theme without it, e.g. the WoW theme).
function NS.ApplySurface(tex, kind)
  local sf = NS.theme.surface
  local bl = NS.theme.blend
  local a = bl and sf and NS.Num(bl[kind]) or 1
  if tex.SetAlpha then tex:SetAlpha(a) end
  local c = sf and sf[kind]
  if not c then return false end
  if c.flat then NS.PaintFlat(tex, c.a, c.b, c.dir) return true end
  NS.Unflat(tex)
  local r, zw, zh = sf.rect, sf.w, sf.h
  tex:SetTexture(sf.file)
  tex:SetTexCoord((r[1] + 0.5) / zw, (r[1] + r[3] - 0.5) / zw, (r[2] + 0.5) / zh, (r[2] + r[4] - 0.5) / zh)
  tex:SetVertexColor(c.tint[1], c.tint[2], c.tint[3], 1)
  return true
end

function NS.PieceSize(key)
  local sp = NS.Stock and NS.Stock.Spec(key)
  if sp and sp.w then return sp.w, sp.h end
  local r = NS.Rect(key)
  if not r then return 1, 1 end
  return r[3], r[4]
end

-- Safe value readers (secret values are never compared or concatenated).
local function IsSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end
function NS.Num(v) if not IsSecret(v) and type(v) == "number" then return v end end
function NS.Str(v) if not IsSecret(v) and type(v) == "string" then return v end end
function NS.Bool(v) if not IsSecret(v) and type(v) == "boolean" then return v end end
function NS.Tbl(v) if not IsSecret(v) and type(v) == "table" then return v end end

-- Font helper: the game's own standard font (Friz Quadrata in English clients) so the mockup's look carries over.
function NS.SetFont(fs, size, flags)
  local path = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  local ok = fs:SetFont(path, size, flags or "")
  if not ok and GameFontNormal then fs:SetFontObject(GameFontNormal) end
end

-- 0.4.4 contrast helpers. Lum/Contrast follow WCAG 2. NS.Legible keeps a fixed colour's hue (item quality, class
-- colour) but mixes it toward white on dark lists or black on light lists just enough for 6:1 against the theme's
-- list background (theme.colors.listBg); 6:1 so the lighter page areas still clear 4.5:1.
local function Lin(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
function NS.Lum(c) return 0.2126 * Lin(c[1]) + 0.7152 * Lin(c[2]) + 0.0722 * Lin(c[3]) end
function NS.Contrast(a, b)
  local la, lb = NS.Lum(a), NS.Lum(b)
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end
function NS.Legible(r, g, b, bgKey, minC)
  local bg = NS.theme.colors[bgKey or "listBg"] or { 0.07, 0.07, 0.07 }
  local need = minC or 6
  if NS.Contrast({ r, g, b }, bg) >= need then return r, g, b end
  local t = NS.Lum(bg) < 0.25 and 1 or 0
  for i = 1, 20 do
    local k = i / 20
    local m = { r + (t - r) * k, g + (t - g) * k, b + (t - b) * k }
    if NS.Contrast(m, bg) >= need then return m[1], m[2], m[3] end
  end
  return t, t, t
end
-- 0.5.1.2: an item-quality colour for an item row drawn straight on the WoW theme's parchment (quest rewards, boss
-- drops; no name plate): Common (white) becomes the dark quest ink, every other quality keeps its hue, darkened just
-- enough for 4.5:1 against the parchment (theme.colors.parchBg).
function NS.ParchQuality(r, g, b)
  if r > 0.9 and g > 0.9 and b > 0.9 then return NS.Color("pInk") end
  if not NS.theme.colors.parchBg then return NS.Color("pInk") end
  return NS.Legible(r, g, b, "parchBg", 4.5)
end
-- "|cffrrggbb" escape for a theme colour key (for coloured lines inside one FontString).
function NS.ColorCode(key)
  local r, g, b = NS.Color(key)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
