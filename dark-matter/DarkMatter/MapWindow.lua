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

-- The game's map window size ON SCREEN, in UIParent units (0.5.1.5): its GetWidth/GetHeight times its effective scale
-- over UIParent's. One rule, maximized or windowed: whatever size the map window has now. Only when its size cannot be
-- read does the windowed size (minimizedWidth + questLogWidth, minimizedHeight) stand in.
function MW.Scales()
  local W = Frame()
  local es = W and N(Call(W, "GetEffectiveScale"))
  local ues = UIParent and N(Call(UIParent, "GetEffectiveScale"))
  local f = _G.DarkMatterFrame
  local des = type(f) == "table" and N(Call(f, "GetEffectiveScale"))
  return es, ues, des
end
function MW.Size()
  local W = Frame()
  if not W then return nil, nil, "no WorldMapFrame" end
  local es, ues = MW.Scales()
  local k = (es and ues and es > 0 and ues > 0) and es / ues or 1
  local w, h = N(Call(W, "GetWidth")), N(Call(W, "GetHeight"))
  if w and h and w >= 200 and h >= 150 then return w * k, h * k, "WorldMapFrame size on screen" end
  local mw, mh = N(Field(W, "minimizedWidth")), N(Field(W, "minimizedHeight"))
  if mw and mh and mw >= 200 and mh >= 150 then
    return (mw + (N(Field(W, "questLogWidth")) or 0)) * k, mh * k, "WorldMapFrame windowed size on screen"
  end
  return nil, nil, "WorldMapFrame size not readable"
end

-- Metrics that follow the window's width (dw) or height (dh); everything else keeps its place (rail, title, tabs).
local W_KEYS = { "titleW", "bodyW", "pageW", "statusW", "shareX", "exitX" }
local H_KEYS = { "footerTop", "railH", "bodyH", "pageH", "sectionPageH", "fbtnY", "statusY" }
MW.W_KEYS, MW.H_KEYS = W_KEYS, H_KEYS
local bases = setmetatable({}, { __mode = "k" })
MW.bases = bases -- 0.5.1.4: each metrics table's own 880x680 values (the class art keeps their scale)


-- Sizes the shared metrics table (WoW and class themes) to the game's map window. Called before the window is built.
function MW.Apply(m)
  if type(m) ~= "table" then return nil end
  local b = bases[m]
  if not b then
    b = {}
    for _, k in ipairs(W_KEYS) do b[k] = m[k] end
    for _, k in ipairs(H_KEYS) do b[k] = m[k] end
    b.w, b.h = m.w, m.h
    bases[m] = b
  end
  local w, h, src = MW.Size()
  local res = { source = src, readW = w and math.floor(w + 0.5), readH = h and math.floor(h + 0.5) }
  local cw, ch
  if not w then
    res.fallback = true
    cw, ch = b.w, b.h
  else
    -- 0.5.1.5: the window takes the map window's on-screen size exactly. The layout needs at least MIN_W x MIN_H
    -- (and at most MAX_W x MAX_H), so a smaller (or larger) map window is matched by our own scale instead.
    local s = math.min(1, w / MW.MIN_W, h / MW.MIN_H)
    s = math.max(s, w / MW.MAX_W, h / MW.MAX_H, 0.3)
    cw, ch = math.floor(w / s + 0.5), math.floor(h / s + 0.5)
    res.scale = s
  end
  res.clamped = (not res.fallback) and res.scale ~= 1 or false
  local dw, dh = cw - b.w, ch - b.h
  m.w, m.h = cw, ch
  for _, k in ipairs(W_KEYS) do m[k] = b[k] + dw end
  for _, k in ipairs(H_KEYS) do m[k] = b[k] + dh end
  res.w, res.h = cw, ch
  if m == (NS.theme and NS.theme.m) then MW.last = res MW.live = nil end
  return res
end

-- 0.5.1.5: the scale our window needs so it covers what the map window covers on screen, for the layout it was built
-- with (w x h). Read again while our window is shown (Window.lua polls from its own frame: no hooks on WorldMapFrame).
-- Returns scale, mapW, mapH (UIParent units), and whether the map's shape differs from our layout's.
function MW.LiveScale(w, h)
  local tw, th = MW.Size()
  if not tw or not w or w <= 0 or h <= 0 then return nil end
  local sx, sy = tw / w, th / h
  local s = math.min(sx, sy)
  MW.live = { w = tw, h = th, scale = s, shapeOff = math.abs(sx - sy) / math.max(sx, sy) > 0.01 }
  return s, tw, th, MW.live.shapeOff
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
-- one line: both windows' effective scale and their on-screen sizes (UIParent units); used by frameprobe and mapprobe
function MW.ScaleLine(tag)
  local es, ues, des = MW.Scales()
  local W, f = Frame(), _G.DarkMatterFrame
  local function OnScreen(o, e)
    local w, h = N(Call(o, "GetWidth")), N(Call(o, "GetHeight"))
    if not (w and h and e and ues and ues > 0) then return "?" end
    return string.format("%dx%d", math.floor(w * e / ues + 0.5), math.floor(h * e / ues + 0.5))
  end
  local line = string.format("%s: scale: map %s, Dark Matter %s, UIParent %s; on screen: map %s, Dark Matter %s",
    tag, MW.R3(es), MW.R3(des), MW.R3(ues), W and OnScreen(W, es) or "-", type(f) == "table" and OnScreen(f, des) or "-")
  if MW.live and MW.live.shapeOff then line = line .. " (map changed shape: /reload)" end
  return line
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
    r.fallback and " (fallback: Dark Matter's own 880x680)" or "", r.readW and string.format(" (map on screen %sx%s, our scale %s)", tostring(r.readW), tostring(r.readH), MW.R3(r.scale)) or ""))
  L(MW.ScaleLine("frame 2b"))
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
