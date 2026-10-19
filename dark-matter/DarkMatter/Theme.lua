-- Theme layer. A theme is plain DATA: an atlas (texture file + piece rectangles), a few big textures,
-- metrics (sizes and offsets in UI units, taken from the approved previewer mockup), colours and a title.
-- Window code never branches on a theme id; it asks NS.theme for numbers, colours and atlas pieces.
-- Adding a class theme later = one more NS.RegisterTheme({...}) (+ its atlas file); no widget code changes.
local _, NS = ...

NS.themes = NS.themes or {}
NS.themeOrder = NS.themeOrder or {}
NS.atlases = NS.atlases or {}
NS.theme = nil

local skins = {}

local function Hex(h)
  local r, g, b = string.match(h, "^#?(%x%x)(%x%x)(%x%x)$")
  return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end
NS.Hex = Hex

function NS.RegisterTheme(def)
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
  for _, fn in ipairs(skins) do pcall(fn) end
  return true
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

-- Point a texture at one atlas piece (half a texel inset so neighbouring pieces never bleed in).
function NS.SetPiece(tex, key)
  local a = NS.atlases[NS.theme.atlas]
  local r = a and a.rects[key]
  if not r then return end
  tex:SetTexture(a.file)
  local e = 0.5
  tex:SetTexCoord((r[1] + e) / a.width, (r[1] + r[3] - e) / a.width, (r[2] + e) / a.height, (r[2] + r[4] - e) / a.height)
end

function NS.PieceSize(key)
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

-- "|cffrrggbb" escape for a theme colour key (for coloured lines inside one FontString).
function NS.ColorCode(key)
  local r, g, b = NS.Color(key)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
