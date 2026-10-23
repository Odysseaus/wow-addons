-- Text contrast check (0.4.4). For every visible label it composites, in the client's draw order, everything drawn
-- underneath it at a grid of sample points: real texels from Media/*.tga (texcoords, REPEAT wrap, 8-number coords),
-- solid colours, vertex colours and gradients, alpha chain, BLEND/ADD/MOD. HIGHLIGHT-layer textures count only on a
-- hovered or highlight-locked button. Labels mostly covered by something drawn later (an open popover) are skipped.
-- Result: WCAG 2 contrast of the label colour against the mean background it sits on.
local C = {}
local MEDIA = arg[1] .. "/Media/"
local WORLD = { 0.12, 0.12, 0.14 } -- the game world behind the window (only shows where nothing is drawn)
local cache = {}
-- 0.5.1: the game's own (stock) textures are not on this machine, so each one the WoW theme draws under text is modelled
-- as a solid colour. These are ESTIMATES, not measured texels: every one has a light and a dark bound (C.tone picks
-- one) and the WoW theme is scanned at both bounds, so a label passes only if it reads on either.
C.tone = "light"
C.STOCK = {
  ["interface\\framegeneral\\ui-background-rock"] = { light = { 0.36, 0.36, 0.36 }, dark = { 0.12, 0.12, 0.12 } },
  ["interface\\dialogframe\\ui-dialogbox-background-dark"] = { light = { 0.16, 0.16, 0.16 }, dark = { 0, 0, 0 } },
  ["interface\\questframe\\questbg"] = { light = { 0.96, 0.90, 0.76 }, dark = { 0.74, 0.64, 0.46 } },
  ["interface\\dialogframe\\ui-dialogbox-header"] = { light = { 0.26, 0.22, 0.16 }, dark = { 0.04, 0.04, 0.04 } },
  ["interface\\buttons\\ui-panel-button-up"] = { light = { 0.62, 0.10, 0.06 }, dark = { 0.26, 0.02, 0.02 } },
  ["interface\\buttons\\ui-panel-button-down"] = { light = { 0.52, 0.08, 0.05 }, dark = { 0.20, 0.02, 0.02 } },
  ["interface\\buttons\\ui-panel-button-disabled"] = { light = { 0.32, 0.32, 0.32 }, dark = { 0.10, 0.10, 0.10 } },
  ["interface\\common\\common-input-border"] = { light = { 0.24, 0.24, 0.24 }, dark = { 0.04, 0.04, 0.04 } },
  ["interface\\paperdollinfoframe\\ui-character-activetab"] = { light = { 0.30, 0.27, 0.22 }, dark = { 0.08, 0.07, 0.06 } },
  ["interface\\paperdollinfoframe\\ui-character-inactivetab"] = { light = { 0.24, 0.22, 0.18 }, dark = { 0.05, 0.05, 0.04 } },
  ["interface\\questframe\\ui-questtitlehighlight"] = { light = { 0.30, 0.26, 0.10 }, dark = { 0.10, 0.10, 0.10 } }, -- ADD glow
}

local function load(file)
  if cache[file] ~= nil and not C.STOCK[tostring(file):lower()] then return cache[file] end
  local res = false
  local f = tostring(file)
  local st = C.STOCK[f:lower()]
  if st then
    res = { solid = st[C.tone] or st.light }
  elseif f:upper():find("WHITE8X8", 1, true) then
    res = "white"
  else
    local name = f:match("[Mm]edia\\(.+)$")
    if name then
      if not name:lower():find("%.tga$") then name = name .. ".tga" end
      local fh = io.open(MEDIA .. name, "rb")
      if fh then
        local d = fh:read("*a") fh:close()
        res = { d = d, off = 18 + d:byte(1), w = d:byte(13) + d:byte(14) * 256, h = d:byte(15) + d:byte(16) * 256,
          px = d:byte(17) / 8, top = (d:byte(18) % 64) >= 32 }
      end
    end
  end
  cache[file] = res
  return res
end

local function texel(img, u, v)
  local x = math.max(0, math.min(img.w - 1, math.floor(u * img.w)))
  local y = math.max(0, math.min(img.h - 1, math.floor(v * img.h)))
  if not img.top then y = img.h - 1 - y end
  local p = img.off + (y * img.w + x) * img.px + 1
  local b, g, r, a = img.d:byte(p, p + 3)
  if img.px == 3 then a = 255 end
  return r / 255, g / 255, b / 255, a / 255
end

local function chainAlpha(r)
  local a, x = 1, r
  while x and x ~= UIParent do a = a * (x._alpha or 1) x = x._parent end
  return a
end

local function hovered(r)
  local x = r._parent
  while x and x ~= UIParent do
    if x._hover or x._locked then return true end
    x = x._parent
  end
  return false
end

-- colour of texture entry e at screen point (x, y); nil when it draws nothing known there
local function sample(e, x, y)
  local r = e.r
  local fx, fy = (x - e.l) / (e.rr - e.l), (e.t - y) / (e.t - e.b)
  local cr, cg, cb, ca
  if r._color then
    cr, cg, cb, ca = r._color[1], r._color[2], r._color[3], r._color[4] or 1
  else
    if r._file == nil then return nil end
    local img = load(r._file)
    if not img then return nil end
    if img == "white" then
      cr, cg, cb, ca = 1, 1, 1, 1
    elseif img.solid then
      cr, cg, cb, ca = img.solid[1], img.solid[2], img.solid[3], 1
    else
      local tc = r._tc or { 0, 1, 0, 1 }
      local u, v
      if #tc == 8 then
        local tu, tv = tc[1] + (tc[5] - tc[1]) * fx, tc[2] + (tc[6] - tc[2]) * fx
        local bu, bv = tc[3] + (tc[7] - tc[3]) * fx, tc[4] + (tc[8] - tc[4]) * fx
        u, v = tu + (bu - tu) * fy, tv + (bv - tv) * fy
      else
        u, v = tc[1] + (tc[2] - tc[1]) * fx, tc[3] + (tc[4] - tc[3]) * fy
      end
      if r._wrapH == "REPEAT" then u = u % 1 end
      if r._wrapV == "REPEAT" then v = v % 1 end
      cr, cg, cb, ca = texel(img, u, v)
    end
  end
  local m = r._vc
  if r._grad then
    local t = r._grad[1] == "VERTICAL" and (1 - fy) or fx
    local lo, hi = r._grad[2], r._grad[3]
    m = { lo[1] + (hi[1] - lo[1]) * t, lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t, (lo[4] or 1) + ((hi[4] or 1) - (lo[4] or 1)) * t }
  end
  if m then cr, cg, cb, ca = cr * m[1], cg * m[2], cb * m[3], ca * (m[4] or 1) end
  if r._desat then local g = 0.3 * cr + 0.59 * cg + 0.11 * cb cr, cg, cb = g, g, g end
  return cr, cg, cb, ca * chainAlpha(r), r._blend or "BLEND"
end

local function lum(c)
  local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
  return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
function C.ratio(a, b)
  local la, lb = lum(a), lum(b)
  if la < lb then la, lb = lb, la end
  return (la + 0.05) / (lb + 0.05)
end

local function scrollClip(r)
  local x = r._parent
  while x and x ~= UIParent do
    if x._ftype == "ScrollFrame" then return x end
    x = x._parent
  end
end

local function inside(e, x, y) return e.l and x >= e.l and x <= e.rr and y <= e.t and y >= e.b end

local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end

-- Check every visible label under root. Returns a list of { text, ratio, need, fg, bg, size, owner, roles }.
function C.Scan(root, colors, only)
  local list = LayoutOf(root)
  local out = {}
  for i, e in ipairs(list) do
    local r = e.r
    local mine = true
    if only and e.kind == "fontstring" then
      mine = false
      local x = r._parent
      while x and x ~= UIParent do if x == only then mine = true break end x = x._parent end
    end
    if mine and e.kind == "fontstring" and e.l and plain(r._text):find("%S") and chainAlpha(r) > 0.05 then
      local l, t, rr, b = e.l, e.t, e.rr, e.b
      local sc = scrollClip(r)
      if sc then
        local sl, st, sr, sb = C.rect(sc)
        if sl then l, t, rr, b = math.max(l, sl), math.min(t, st), math.min(rr, sr), math.max(b, sb) end
      end
      if rr - l > 2 and t - b > 2 then
        local acc, n, hid, pacc = { 0, 0, 0 }, 0, 0, { 0, 0, 0 }
        local top = "world"
        for gx = 1, 5 do
          for gy = 1, 3 do
            local x, y = l + (rr - l) * (gx - 0.5) / 5, b + (t - b) * (gy - 0.5) / 3
            local cover, post = false, { 0, 0, 0 }
            for j = i + 1, #list do
              local o = list[j]
              if o.kind == "texture" and inside(o, x, y) and (o.r._layer ~= "HIGHLIGHT" or hovered(o.r)) then
                local pr, pg, pb, a, bl = sample(o, x, y)
                if pr and bl == "ADD" then post[1], post[2], post[3] = post[1] + pr * a, post[2] + pg * a, post[3] + pb * a end
                if a and a > 0.6 and bl == "BLEND" then cover = true break end
              end
            end
            if cover then
              hid = hid + 1
            else
              local c = { WORLD[1], WORLD[2], WORLD[3] }
              for j = 1, i - 1 do
                local o = list[j]
                if o.kind == "texture" and inside(o, x, y) and (o.r._layer ~= "HIGHLIGHT" or hovered(o.r)) then
                  local cr, cg, cb, a, bl = sample(o, x, y)
                  if cr and a > 0 then
                    if a > 0.3 and gx == 3 and gy == 2 then top = tostring(o.r._file or "color"):match("([^\\/]*)$") end
                    if bl == "ADD" then
                      c = { math.min(1, c[1] + cr * a), math.min(1, c[2] + cg * a), math.min(1, c[3] + cb * a) }
                    elseif bl == "MOD" then
                      c = { c[1] * cr, c[2] * cg, c[3] * cb }
                    else
                      a = math.min(1, a)
                      c = { c[1] * (1 - a) + cr * a, c[2] * (1 - a) + cg * a, c[3] * (1 - a) + cb * a }
                    end
                  end
                end
              end
              acc[1], acc[2], acc[3], n = acc[1] + c[1], acc[2] + c[2], acc[3] + c[3], n + 1
              pacc[1], pacc[2], pacc[3] = pacc[1] + post[1], pacc[2] + post[2], pacc[3] + post[3]
            end
          end
        end
        if n >= 8 then
          local bg = { acc[1] / n, acc[2] / n, acc[3] / n }
          local fc = r._tcol or { 1, 1, 1, 1 }
          local hex = tostring(r._text):match("^|c%x%x(%x%x%x%x%x%x)")
          if hex then fc = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 } end
          local a = (fc[4] or 1) * chainAlpha(r)
          local fg = { fc[1] * a + bg[1] * (1 - a), fc[2] * a + bg[2] * (1 - a), fc[3] * a + bg[3] * (1 - a) }
          -- ADD textures drawn over the label (e.g. a HIGHLIGHT glow) brighten text and background alike
          for q = 1, 3 do fg[q] = math.min(1, fg[q] + pacc[q] / n) bg[q] = math.min(1, bg[q] + pacc[q] / n) end
          local roles = {}
          for k, v in pairs(colors or {}) do
            if type(v) == "table" and math.abs(v[1] - fc[1]) < 0.002 and math.abs(v[2] - fc[2]) < 0.002 and math.abs(v[3] - fc[3]) < 0.002 then roles[#roles + 1] = k end
          end
          table.sort(roles)
          local size = r._fsize or 12
          -- an OUTLINE label carries its own black halo: it is read against that halo
          local outlined = tostring(r._fflags or ""):find("OUTLINE") ~= nil
          out[#out + 1] = { text = (plain(r._text):gsub("\n", " "):gsub("[\128-\255]+", "~"):sub(1, 40)), ratio = outlined and C.ratio(fg, { 0, 0, 0 }) or C.ratio(fg, bg), need = size >= 18 and 3 or 4.5,
            fg = fg, bg = bg, size = size, r = r, roles = table.concat(roles, "/") .. "@" .. top }
        end
      end
    end
  end
  return out
end

return C
