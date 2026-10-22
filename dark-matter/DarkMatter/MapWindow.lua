-- 0.5.1.4 (0.5.1.5: on-screen size): the game's own map window (WorldMapFrame), read only. Dark Matter takes its size (so our window is as large
-- as the game's map window) and, in the WoW theme, the look of its frame: the border pieces, title, close button and
-- portrait, which it draws again on its own frame with the same game textures (by atlas, path or file ID; nothing is
-- copied into the addon). It never shows, hides, sizes, hooks or writes to WorldMapFrame, so nothing is tainted and it
-- is safe in combat. Anything unreadable falls back: Dark Matter's own 880x680 size and its own thin frame.
-- /dm frameprobe lists what was read (saved to DarkMatterDB.frameprobe).
local _, NS = ...

local MW = {}
NS.MapWindow = MW
MW.BASE_W, MW.BASE_H = 880, 680       -- Dark Matter's own size (the fallback)
MW.MIN_W, MW.MIN_H = 880, 500         -- every tab still lays out at this size (the Journals section tabs need 880 across)
MW.MAX_W, MW.MAX_H = 1800, 1300
MW.NINE = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }

local function N(v) local r = NS.Num(v) return r end
local function S(v) local r = NS.Str(v) return r end
local function Field(o, k)
  if type(o) ~= "table" then return nil end
  local ok, v = pcall(function() return o[k] end)
  if ok then return v end
end
local function Call(o, m, ...)
  local f = Field(o, m)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, o, ...) }
  if r[1] then return unpack(r, 2, 9) end
end
MW.Call, MW.Field = Call, Field

local function Frame() local W = _G.WorldMapFrame if type(W) == "table" then return W end end

-- 0.5.1.6: OUTER bounds. Each window is measured by everything its frame draws: the frame itself plus the border pieces
-- that reach past it (the map window: its NineSlice corners' offsets; ours: the theme's border art). Our window's outer
-- bounds equal the map window's outer bounds on screen, width and height, in every theme; our layout takes the map's
-- exact shape. Sizes are in UIParent units. One rule, maximized or windowed; only when the map's size cannot be read
-- does its windowed size (minimizedWidth + questLogWidth, minimizedHeight) stand in.
function MW.Scales()
  local W = Frame()
  local es = W and N(Call(W, "GetEffectiveScale"))
  local ues = UIParent and N(Call(UIParent, "GetEffectiveScale"))
  local f = _G.DarkMatterFrame
  local des = type(f) == "table" and N(Call(f, "GetEffectiveScale"))
  return es, ues, des
end
local CORNERS = { TopLeftCorner = true, TopRightCorner = true, BottomLeftCorner = true, BottomRightCorner = true }
-- how far the map window's border corners reach past its frame (map units): left, top, right, bottom
function MW.MapBorder()
  local A = MW.Art()
  local l, t, r, b = 0, 0, 0, 0
  if A and A.nine then
    for k, p in pairs(A.nine) do
      if CORNERS[k] then
        local pt, x, y = p.point or "", N(p.x) or 0, N(p.y) or 0
        if pt:find("LEFT") then l = math.max(l, -x) end
        if pt:find("RIGHT") then r = math.max(r, x) end
        if pt:find("TOP") then t = math.max(t, y) end
        if pt:find("BOTTOM") then b = math.max(b, -y) end
      end
    end
  end
  return l, t, r, b
end
-- 0.5.1.6: the map window's OUTER rectangle on screen, in UIParent units (left, top, right, bottom; y up as the game's):
-- the union of WorldMapFrame's own rect, the border corner pieces drawn around it (they can reach past it) and the quest
-- log panel when it is shown on the map window. Read-only (GetLeft/GetRight/GetTop/GetBottom). nil when not readable.
local function RectOf(o, k)
  local l, r, t, b = N(Call(o, "GetLeft")), N(Call(o, "GetRight")), N(Call(o, "GetTop")), N(Call(o, "GetBottom"))
  if l and r and t and b and r > l and t > b then return l * k, t * k, r * k, b * k end
end
MW.RectOf = RectOf
function MW.MapRect()
  local W = Frame()
  if not W then return nil end
  local es, ues = MW.Scales()
  local k = (es and ues and es > 0 and ues > 0) and es / ues or 1
  local l, t, r, b = RectOf(W, k)
  if not l then return nil end
  local fl, ft, fr, fb = l, t, r, b
  local nine = Field(Field(W, "BorderFrame"), "NineSlice")
  local function U(o)
    if type(o) ~= "table" or Call(o, "IsShown") == false then return end
    local a1, a2, a3, a4 = RectOf(o, k)
    if a1 then l, t, r, b = math.min(l, a1), math.max(t, a2), math.max(r, a3), math.min(b, a4) end
  end
  for kk in pairs(CORNERS) do U(Field(nine, kk)) end
  local q = _G.QuestMapFrame
  if type(q) == "table" and Call(q, "IsShown") == true then U(q) end
  return l, t, r, b, { fl, ft, fr, fb }
end
-- the map window's OUTER size on screen (UIParent units), where it came from, and its frame's own size on screen. From
-- its rectangles when they can be read; else its size plus the border corners' offsets.
function MW.Size()
  local W = Frame()
  if not W then return nil, nil, "no WorldMapFrame" end
  local l, t, r, b, fr = MW.MapRect()
  if l then return r - l, t - b, "WorldMapFrame outer rect on screen", fr[3] - fr[1], fr[2] - fr[4] end
  local es, ues = MW.Scales()
  local k = (es and ues and es > 0 and ues > 0) and es / ues or 1
  local w, h = N(Call(W, "GetWidth")), N(Call(W, "GetHeight"))
  local src = "WorldMapFrame size + border on screen"
  if not (w and h and w >= 200 and h >= 150) then
    local mw, mh = N(Field(W, "minimizedWidth")), N(Field(W, "minimizedHeight"))
    if not (mw and mh and mw >= 200 and mh >= 150) then return nil, nil, "WorldMapFrame size not readable" end
    w, h, src = mw + (N(Field(W, "questLogWidth")) or 0), mh, "WorldMapFrame windowed size + border on screen"
  end
  local bl, bt, br, bb = MW.MapBorder()
  return (w + bl + br) * k, (h + bt + bb) * k, src, w * k, h * k
end

-- Metrics that follow the window's width (dw) or height (dh); everything else keeps its place (rail, title, tabs).
local W_KEYS = { "titleW", "bodyW", "pageW", "statusW", "shareX", "exitX" }
local H_KEYS = { "footerTop", "railH", "bodyH", "pageH", "sectionPageH", "fbtnY", "statusY" }
MW.W_KEYS, MW.H_KEYS = W_KEYS, H_KEYS
local bases = setmetatable({}, { __mode = "k" })
MW.bases = bases -- 0.5.1.4: each metrics table's own 880x680 values (the class art keeps their scale)
local function Base(m)
  local b = bases[m]
  if not b then
    b = {}
    for _, k in ipairs(W_KEYS) do b[k] = m[k] end
    for _, k in ipairs(H_KEYS) do b[k] = m[k] end
    b.w, b.h = m.w, m.h
    bases[m] = b
  end
  return b
end
local function Fill(m, b, cw, ch)
  m.w, m.h = cw, ch
  for _, k in ipairs(W_KEYS) do m[k] = b[k] + (cw - b.w) end
  for _, k in ipairs(H_KEYS) do m[k] = b[k] + (ch - b.h) end
end

-- how far a theme's border art reaches past our frame at metrics m (layout units): left, top, right, bottom
function MW.ThemeBorder(theme, m)
  if theme and theme.classArt and NS.ClassArtBox then
    local box = NS.ClassArtBox(theme.classArt, m)
    if box then return math.max(0, -box[1]), math.max(0, -box[2]), math.max(0, box[3] - m.w), math.max(0, box[4] - m.h) end
  elseif theme and theme.mapWindow then
    local A = MW.Art()
    if A and A.full then return MW.MapBorder() end -- the WoW theme puts the map's own corners at the map's offsets
  end
  return 0, 0, 0, 0
end

-- What our window needs in a theme (nothing is changed): layout w x h, our scale, our border, and the outer size it
-- gives on screen. Below MIN_W x MIN_H (or above MAX_W x MAX_H) inside the border, our own scale makes up the rest.
function MW.Need(theme, m)
  theme = theme or NS.theme
  m = m or (theme and theme.m)
  local b = Base(m)
  local tw, th, src = MW.Size()
  local res = { source = src, mapW = tw, mapH = th, readW = tw and math.floor(tw + 0.5), readH = th and math.floor(th + 0.5) }
  if not tw then
    res.fallback, res.w, res.h = true, b.w, b.h
    res.border = { MW.ThemeBorder(theme, m) }
    return res
  end
  local tm = {}
  for k, v in pairs(m) do tm[k] = v end
  bases[tm] = b
  local l, t, r, bo = MW.ThemeBorder(theme, m)
  local s, cw, ch
  for _ = 1, 4 do
    local ox, oy = l + r, t + bo
    s = math.min(1, tw / (MW.MIN_W + ox), th / (MW.MIN_H + oy))
    s = math.max(s, tw / (MW.MAX_W + ox), th / (MW.MAX_H + oy), 0.3)
    cw, ch = math.floor(tw / s - ox + 0.5), math.floor(th / s - oy + 0.5)
    Fill(tm, b, cw, ch)
    l, t, r, bo = MW.ThemeBorder(theme, tm)
  end
  bases[tm] = nil
  res.w, res.h, res.scale, res.border = cw, ch, s, { l, t, r, bo }
  res.outerW, res.outerH = (cw + l + r) * s, (ch + t + bo) * s
  return res
end

-- Sizes the shared metrics table to the game's map window for the current theme. Called before the window is built.
function MW.Apply(m, theme)
  if type(m) ~= "table" then return nil end
  theme = theme or NS.theme
  local res = MW.Need(theme, m)
  Fill(m, Base(m), res.w, res.h)
  res.clamped = (not res.fallback) and res.scale ~= 1 or false
  res.theme = theme and theme.id
  if m == (NS.theme and NS.theme.m) then MW.last = res MW.live = nil end
  return res
end

-- 0.5.1.6: read again while our window is shown (Window.lua polls from its own frame: no hooks on WorldMapFrame).
-- "scale" when only our scale must follow; "layout" when the layout must take another size (another shape, or another
-- theme's border) and the window is rebuilt; nil when the map window cannot be read.
function MW.Check(m)
  m = m or NS.theme.m
  local need = MW.Need(NS.theme, m)
  MW.live = need
  if need.fallback then return nil, need end
  if math.abs(need.w - m.w) >= 1 or math.abs(need.h - m.h) >= 1 then return "layout", need end
  return "scale", need
end

-- One texture or font string, as plain values (secret values read as nil).
function MW.Region(t)
  if type(t) ~= "table" or type(Field(t, "GetObjectType")) ~= "function" then return nil end
  local p = { kind = S(Call(t, "GetObjectType")) }
  if p.kind == "FontString" then
    p.text = S(Call(t, "GetText"))
    local r, g, b = Call(t, "GetTextColor")
    p.color = N(r) and { N(r), N(g) or 1, N(b) or 1 } or nil
    local _, size = Call(t, "GetFont")
    p.size = N(size)
  else
    p.atlas = S(Call(t, "GetAtlas"))
    p.fileID = N(Call(t, "GetTextureFileID"))
    local tex = Call(t, "GetTexture")
    p.file = S(tex) or N(tex)
    local tc = { Call(t, "GetTexCoord") }
    if #tc == 8 then
      for i = 1, 8 do tc[i] = N(tc[i]) end
      if #tc == 8 then p.tc = tc end
    end
    local r, g, b, a = Call(t, "GetVertexColor")
    if N(r) then p.vc = { N(r), N(g) or 1, N(b) or 1, N(a) or 1 } end
    p.horiz = Call(t, "GetHorizTile") == true
    p.vert = Call(t, "GetVertTile") == true
  end
  p.w, p.h = N(Call(t, "GetWidth")), N(Call(t, "GetHeight"))
  local pt, _, rp, x, y = Call(t, "GetPoint", 1)
  p.point, p.relPoint, p.x, p.y = S(pt), S(rp), N(x), N(y)
  p.shown = Call(t, "IsShown") ~= false
  return p
end

local function Has(p) return p and (p.atlas or p.fileID or p.file) and true or false end
MW.Has = Has

-- What the game's map window is drawn with: its frame's 8 border pieces, title, close button, portrait, background
-- and the map's top bar (NavBar) home button. nil when there is no map window to read.
function MW.Art(force)
  if MW.art ~= nil and not force then return MW.art or nil end
  MW.art = false
  local W = Frame()
  local B = Field(W, "BorderFrame")
  if type(B) ~= "table" then return nil end
  local A = { nine = {}, n = 0 }
  local nine = Field(B, "NineSlice")
  for _, k in ipairs(MW.NINE) do
    local p = MW.Region(Field(nine, k))
    if Has(p) then A.nine[k] = p A.n = A.n + 1 end
  end
  local tc = Field(B, "TitleContainer")
  A.title = MW.Region(Field(tc, "TitleText") or Field(B, "TitleText"))
  A.portrait = MW.Region(Field(B, "portrait") or Field(Field(B, "PortraitContainer"), "portrait"))
  A.bg = MW.Region(Field(B, "Bg"))
  local cb = Field(B, "CloseButton")
  if type(cb) == "table" then
    A.close = { w = N(Call(cb, "GetWidth")), h = N(Call(cb, "GetHeight")),
      normal = MW.Region(Call(cb, "GetNormalTexture")), pushed = MW.Region(Call(cb, "GetPushedTexture")),
      highlight = MW.Region(Call(cb, "GetHighlightTexture")), disabled = MW.Region(Call(cb, "GetDisabledTexture")) }
  end
  local nav = Field(W, "NavBar")
  local home = Field(nav, "homeButton") or Field(nav, "home")
  if type(home) == "table" then
    A.navHome = { w = N(Call(home, "GetWidth")), h = N(Call(home, "GetHeight")), normal = MW.Region(Call(home, "GetNormalTexture")) }
  end
  A.full = A.n == 8
  MW.art = A
  return A
end

-- Puts one read region's art on our texture. True when it drew.
function MW.Paint(tex, p)
  if not (tex and Has(p)) then return false end
  local ok = false
  if p.atlas and C_Texture and type(C_Texture.GetAtlasInfo) == "function" and type(tex.SetAtlas) == "function" then
    local s, info = pcall(C_Texture.GetAtlasInfo, p.atlas)
    if s and info then ok = pcall(tex.SetAtlas, tex, p.atlas, false) end
  end
  if not ok then
    local src = p.fileID or p.file
    if not src then return false end
    local s, r = pcall(tex.SetTexture, tex, src, p.horiz and "REPEAT" or nil, p.vert and "REPEAT" or nil)
    if not s or r == false then return false end
    if p.tc then tex:SetTexCoord(unpack(p.tc)) end
  end
  if tex.SetHorizTile then pcall(tex.SetHorizTile, tex, p.horiz) end
  if tex.SetVertTile then pcall(tex.SetVertTile, tex, p.vert) end
  if p.vc then tex:SetVertexColor(p.vc[1], p.vc[2], p.vc[3], p.vc[4]) else tex:SetVertexColor(1, 1, 1, 1) end
  return true
end

local function Name(p)
  if not p then return "none" end
  if p.kind == "FontString" then return string.format("text %q size %s", p.text or "", tostring(p.size and math.floor(p.size + 0.5))) end
  local src = p.atlas and ("atlas " .. p.atlas) or (p.fileID and ("file " .. p.fileID)) or (p.file and ("file " .. tostring(p.file))) or "no texture"
  if p.atlas and p.fileID then src = src .. " (file " .. p.fileID .. ")" end
  local sz = (p.w and p.h) and string.format(" %dx%d", math.floor(p.w + 0.5), math.floor(p.h + 0.5)) or ""
  local at = p.point and string.format(" at %s %s,%s", p.point, tostring(p.x and math.floor(p.x + 0.5)), tostring(p.y and math.floor(p.y + 0.5))) or ""
  return src .. sz .. at .. (p.shown and "" or " (hidden)")
end
MW.Name = Name

function MW.R3(v) v = N(v) return v and string.format("%.3f", v) or "?" end
-- our window's OUTER size on screen now (frame + the current theme's border), UIParent units
function MW.OurOuter()
  local f = _G.DarkMatterFrame
  local _, ues, des = MW.Scales()
  if type(f) ~= "table" or not (des and ues and ues > 0) then return nil end
  local w, h = N(Call(f, "GetWidth")), N(Call(f, "GetHeight"))
  if not (w and h) then return nil end
  local l, t, r, b = MW.ThemeBorder(NS.theme, NS.theme.m)
  return (w + l + r) * des / ues, (h + t + b) * des / ues
end
local function WH(w, h) return (w and h) and string.format("%dx%d", math.floor(w + 0.5), math.floor(h + 0.5)) or "?" end
local function D(a, b) return (a and b) and string.format("%+d", math.floor(a - b + 0.5)) or "?" end
-- one line: both windows' effective scale and their OUTER on-screen sizes (UIParent units); frameprobe and mapprobe
function MW.ScaleLine(tag)
  local es, ues, des = MW.Scales()
  local mw, mh = MW.Size()
  local ow, oh = MW.OurOuter()
  return string.format("%s: scale: map %s, Dark Matter %s, UIParent %s; on screen: map %s, Dark Matter %s, diff %s,%s",
    tag, MW.R3(es), MW.R3(des), MW.R3(ues), WH(mw, mh), WH(ow, oh), D(ow, mw), D(oh, mh))
end
-- both OUTER rectangles in screen pixels (left, top, right, bottom from the screen's top-left), and the map frame's own
-- rect, so it shows whether the map's border reaches past WorldMapFrame:GetSize()
function MW.RectLines(tag)
  local out = {}
  local _, ues, des = MW.Scales()
  local px, unit = ues or 1, "px"
  local okP, _, ph = pcall(_G.GetPhysicalScreenSize or function() end)
  if okP and N(ph) and ph > 0 then px = (ues or 1) * ph / 768 else unit = "units" end
  local sh = (N(Call(UIParent, "GetTop")) or 768) -- UIParent units; y counted down from the top
  local function R(l, t, r, b)
    if not l then return "?" end
    return string.format("%d,%d to %d,%d = %dx%d", math.floor(l * px + 0.5), math.floor((sh - t) * px + 0.5),
      math.floor(r * px + 0.5), math.floor((sh - b) * px + 0.5), math.floor((r - l) * px + 0.5), math.floor((t - b) * px + 0.5))
  end
  local l, t, r, b, fr = MW.MapRect()
  if l then
    out[#out + 1] = string.format("%s map: outer %s %s (border+quest log)", tag, R(l, t, r, b), unit)
    out[#out + 1] = string.format("%s map: frame %s %s; border sticks out %d,%d,%d,%d", tag, R(fr[1], fr[2], fr[3], fr[4]), unit,
      math.floor((fr[1] - l) * px + 0.5), math.floor((t - fr[2]) * px + 0.5), math.floor((r - fr[3]) * px + 0.5), math.floor((fr[4] - b) * px + 0.5))
  else
    out[#out + 1] = tag .. " map: rect not readable (map never shown?): size + border offsets used"
  end
  local f = _G.DarkMatterFrame
  if type(f) == "table" and des and ues and ues > 0 then
    local k = des / ues
    local a1, a2, a3, a4 = RectOf(f, k)
    if a1 then
      local bl, bt, br, bb = MW.ThemeBorder(NS.theme, NS.theme.m)
      local o1, o2, o3, o4 = a1 - bl * k, a2 + bt * k, a3 + br * k, a4 - bb * k
      out[#out + 1] = string.format("%s ours: outer %s %s (%s border)", tag, R(o1, o2, o3, o4), unit, tostring(NS.theme and NS.theme.id))
      if l then
        out[#out + 1] = string.format("%s diff: width %+d, height %+d %s", tag, math.floor(((o3 - o1) - (r - l)) * px + 0.5),
          math.floor(((o2 - o4) - (t - b)) * px + 0.5), unit)
      end
    end
  end
  return out
end
-- per theme: the outer size each theme gives (the current one measured) against the map's, and the difference
function MW.ThemeLines(tag)
  local out = {}
  local mw, mh = MW.Size()
  for i, id in ipairs(NS.themeOrder or {}) do
    local th = NS.themes[id]
    if th then
      local ow, oh, how
      if th == NS.theme and _G.DarkMatterFrame then ow, oh = MW.OurOuter() how = "current, measured"
      else local need = MW.Need(th, th.m) ow, oh = need.outerW, need.outerH how = "when chosen" end
      out[#out + 1] = string.format("%s.%d %s: outer %s vs map %s, diff %s,%s (%s)", tag, i, id, WH(ow, oh), WH(mw, mh), D(ow, mw), D(oh, mh), how)
    end
  end
  return out
end

-- /dm frameprobe
function MW.Report()
  local lines = { "frameprobe " .. tostring(NS.version) .. " (the game's map window, read only):" }
  local W = Frame()
  local function L(s) lines[#lines + 1] = s end
  if not W then
    L("frame 1: WorldMapFrame no")
  else
    local w, h = N(Call(W, "GetWidth")), N(Call(W, "GetHeight"))
    L(string.format("frame 1: WorldMapFrame yes; size %sx%s; scale %s; shown %s; maximized %s; windowed %sx%s + quest log %s",
      tostring(w and math.floor(w + 0.5)), tostring(h and math.floor(h + 0.5)), tostring(N(Call(W, "GetEffectiveScale"))),
      tostring(Call(W, "IsShown") == true), tostring(Field(W, "isMaximized") == true or Call(W, "IsMaximized") == true),
      tostring(N(Field(W, "minimizedWidth"))), tostring(N(Field(W, "minimizedHeight"))), tostring(N(Field(W, "questLogWidth")))))
  end
  local r = MW.last or {}
  L(string.format("frame 2: Dark Matter window %sx%s from %s%s%s", tostring(r.w), tostring(r.h), tostring(r.source or "not built yet"),
    r.fallback and " (fallback: Dark Matter's own 880x680)" or "", r.readW and string.format(" (map outer %sx%s on screen, our scale %s)", tostring(r.readW), tostring(r.readH), MW.R3(r.scale)) or ""))
  L(MW.ScaleLine("frame 2b"))
  for _, l in ipairs(MW.ThemeLines("frame 2c")) do L(l) end
  for _, l in ipairs(MW.RectLines("frame 2d")) do L(l) end
  local A = MW.Art(true)
  if not A then
    L("frame 3: border: not readable (Dark Matter's own thin frame is drawn)")
  else
    L(string.format("frame 3: border: %d of 8 pieces readable%s", A.n, A.full and " (the WoW theme draws them)" or " (Dark Matter's own thin frame is drawn)"))
    for i, k in ipairs(MW.NINE) do L(string.format("frame 3.%d: %s: %s", i, k, Name(A.nine[k]))) end
    L("frame 4: title: " .. Name(A.title))
    local c = A.close
    if c then
      L(string.format("frame 5: close button %sx%s: %s", tostring(c.w and math.floor(c.w + 0.5)), tostring(c.h and math.floor(c.h + 0.5)), Name(c.normal)))
      L("frame 5 pushed: " .. Name(c.pushed))
      L("frame 5 highlight: " .. Name(c.highlight))
    else
      L("frame 5: close button: none")
    end
    L("frame 6: portrait: " .. Name(A.portrait))
    L("frame 7: background: " .. Name(A.bg))
    L("frame 8: map top bar home button: " .. (A.navHome and Name(A.navHome.normal) or "none"))
  end
  L("frame 9: Dark Matter only reads WorldMapFrame: no Show, no hooks, no changes")
  if NS.db then NS.db.frameprobe = { version = NS.version, lines = lines } end
  return lines
end
