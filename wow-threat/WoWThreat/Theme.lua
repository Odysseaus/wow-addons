-- WoWThreat Theme: textured frames (previewer art exported to TGA) and the
-- cheap AnimationGroup effects per theme (PLAN-visuals 2). Nothing here runs
-- Lua per frame; animations are engine-driven and stop when hidden/reduced.
local _, NS = ...

local ART = "Interface\\AddOns\\WoWThreat\\Textures\\Themes\\"
local B, TB = 20, 36          -- border and title band (previewer FB/FT)
NS.FRAME_B, NS.FRAME_TB = B, TB

local function hex(s, a)
  s = s:gsub("#", "")
  return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, a or 1
end

NS.THEME_IDS = { "emberhall", "ironforged", "ursinegrove", "dawnward", "voidbound" }
local THEMES = {
  emberhall = { title = "Ember Hall", trim = { "#fff0b0", "#c8962e", "#5a3a0c" }, well = { 8, 4, 2, 0.35 }, header = { 0, 0, 0, 0.35 },
    plaque = "#f6d47a", rowBg = "#140f0e", you = "#e9c46a", youText = "#ffe6a3", text = "#eee3cc", fire = "#ff9628", studs = 1, studSize = 11, studStep = 34, pivot = 14 },
  ironforged = { title = "Ironforged", trim = { "#e4e8ec", "#7a8189", "#25282c" }, well = { 0, 0, 0, 0.25 }, header = { 60, 0, 0, 0.45 },
    plaque = "#f6e7d2", rowBg = "#161214", you = "#ff5a40", youText = "#ffd2c8", text = "#f1e8e4", fire = "#ff5f14", studs = 1, studSize = 11, studStep = 34, pivot = 20 },
  ursinegrove = { title = "Ursine Grove", trim = { "#c99a5c", "#6a4422", "#21140a" }, well = { 0, 6, 0, 0.25 }, header = { 0, 20, 0, 0.35 },
    plaque = "#f3e2a6", rowBg = "#11150f", you = "#a6d16a", youText = "#d8f5a8", text = "#e9eed8", fire = "#ffa528", studs = 1, studSize = 17, studStep = 30, pivot = 10 },
  dawnward = { title = "Dawnward", trim = { "#fff8d2", "#d8aa44", "#7a5510" }, well = { 10, 6, 0, 0.30 }, header = { 255, 230, 160, 0.10 },
    plaque = "#6a4508", rowBg = "#1b1610", you = "#ffe08a", youText = "#fff1b8", text = "#f7f0de", fire = "#ffc346", studs = 1, studSize = 11, studStep = 34, pivot = 13 },
  voidbound = { title = "Voidbound", trim = { "#d6b0ff", "#5a3290", "#100616" }, well = { 4, 0, 10, 0.35 }, header = { 60, 10, 110, 0.30 },
    plaque = "#ead2ff", rowBg = "#0f0a15", you = "#8cff5a", youText = "#c9ff9e", text = "#ece2f7", fire = "#a046fa", studs = 4, studSize = 10, studStep = 16, pivot = 14 },
}
NS.THEMES = THEMES

local CLASS_THEME = { WARRIOR = "ironforged", DRUID = "ursinegrove", PALADIN = "dawnward", WARLOCK = "voidbound" }

function NS.AutoTheme(classFile)
  if not classFile and UnitClass then
    local _, c = UnitClass("player")
    classFile = c
  end
  return CLASS_THEME[classFile or ""] or "emberhall"
end

function NS.ThemeId()
  local t = WoWThreatDB and WoWThreatDB.theme
  if THEMES[t or ""] then return t end
  return NS.AutoTheme()
end

local function T() return THEMES[NS.ThemeId()] end

function NS.ThemeColor(key)
  local th = T()
  return hex(th[key] or "#ffffff")
end

-- 1.1.4: every theme (and Classic / Off) uses the Ironforged fire tint.
NS.FIRE_THEME = "ironforged"
function NS.ThemeFireColor()
  local r, g, b = hex(THEMES[NS.FIRE_THEME].fire)
  return r, g, b
end

local function Reduced() return WoWThreatDB and WoWThreatDB.reducedEffects == true end
local function Animate() return not Reduced() and not (WoWThreatDB and WoWThreatDB.animateFrame == false) end

-- ---------------------------------------------------------------- build ---
local frame, host
local P = {}        -- static pieces
local studs, fx = {}, {}
local builtFor, sizeW, sizeH = nil, 0, 0

local function Tex(layer, sub, path)
  local t = frame:CreateTexture(nil, layer, nil, sub or 0)
  if path then t:SetTexture(path) end
  return t
end

local function SetTiled(t, path, w, h, tile)
  local ok = pcall(t.SetTexture, t, path, "REPEAT", "REPEAT")
  if not ok then t:SetTexture(path) end
  if ok then t:SetTexCoord(0, w / tile, 0, h / tile) else t:SetTexCoord(0, 1, 0, 1) end
end

local function Rect(name, layer, sub)
  local t = Tex(layer, sub)
  t:SetColorTexture(1, 1, 1, 1)
  P[name] = t
  return t
end

local function Ring(prefix, layer, sub)
  local i
  for i = 1, 4 do Rect(prefix .. i, layer, sub) end
end

local function PlaceRing(prefix, inset, thick, r, g, b, a)
  local L = { P[prefix .. 1], P[prefix .. 2], P[prefix .. 3], P[prefix .. 4] }
  local i
  for i = 1, 4 do L[i]:ClearAllPoints(); L[i]:SetColorTexture(r, g, b, a) end
  L[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset); L[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset); L[1]:SetHeight(thick)
  L[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset); L[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset); L[2]:SetHeight(thick)
  L[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset); L[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset); L[3]:SetWidth(thick)
  L[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset); L[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset); L[4]:SetWidth(thick)
end

local function Build(parent)
  host = parent
  frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints(parent)
  -- Hard guarantee: no theme art or effect can draw outside the meter.
  if frame.SetClipsChildren then frame:SetClipsChildren(true) end
  frame:SetFrameLevel(math.max(0, (parent:GetFrameLevel() or 1)))
  P.body = Tex("BACKGROUND", -8)
  P.body:SetPoint("TOPLEFT", 1, -1); P.body:SetPoint("BOTTOMRIGHT", -1, 1)
  P.shade = Rect("shade", "BACKGROUND", -7)
  P.shade:SetAllPoints(P.body)
  P.well = Tex("BACKGROUND", -5)
  P.well:SetPoint("TOPLEFT", B, -B); P.well:SetPoint("BOTTOMRIGHT", -B, B)
  Rect("wellTint", "BACKGROUND", -4); P.wellTint:SetAllPoints(P.well)
  Rect("header", "BACKGROUND", -3)
  P.header:SetPoint("TOPLEFT", P.well, "TOPLEFT"); P.header:SetPoint("TOPRIGHT", P.well, "TOPRIGHT"); P.header:SetHeight(TB)
  Ring("rim", "BORDER", 0); Ring("trim", "BORDER", 1); Ring("trimHi", "BORDER", 2); Ring("shadow", "BACKGROUND", -2)
  Rect("divider", "BORDER", 3)
  P.divider:SetPoint("TOPLEFT", P.well, "TOPLEFT", 6, -(TB + 1)); P.divider:SetPoint("TOPRIGHT", P.well, "TOPRIGHT", -6, -(TB + 1)); P.divider:SetHeight(1)
  Rect("diamond", "BORDER", 4); P.diamond:SetSize(6, 6); P.diamond:SetPoint("CENTER", P.divider, "CENTER")
  if P.diamond.SetRotation then pcall(P.diamond.SetRotation, P.diamond, math.pi / 4) end
  P.corner = {}
  local i
  for i = 1, 4 do P.corner[i] = Tex("ARTWORK", 2) end
  P.crest = Tex("ARTWORK", 3)
  P.medallion = Tex("ARTWORK", 3)
  P.plaqueL, P.plaqueM, P.plaqueR = Tex("ARTWORK", 1), Tex("ARTWORK", 1), Tex("ARTWORK", 1)
  P.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  P.title:SetShadowColor(0, 0, 0, 0.85); P.title:SetShadowOffset(0, -1)
end

-- previewer studPos (skips corners and the crest)
local function StudPositions(W, H, step)
  local out, sx, x, y = {}, B / 2, 46, 46
  while x <= W - 46 do
    if math.abs(x - W / 2) > 40 then out[#out + 1] = { x, -sx, 0 } end
    out[#out + 1] = { x, -(H - sx), math.pi }
    x = x + step
  end
  while y <= H - 46 do
    out[#out + 1] = { sx, -y, -math.pi / 2 }
    out[#out + 1] = { W - sx, -y, math.pi / 2 }
    y = y + step
  end
  return out
end

-- ------------------------------------------------------------ animations ---
local groups = {}     -- every theme AnimationGroup (for stop/start)

local function NewAG(tex, loop)
  local ok, ag = pcall(tex.CreateAnimationGroup, tex)
  if not ok or not ag then return nil end
  ag:SetLooping(loop or "REPEAT")
  groups[#groups + 1] = ag
  return ag
end

local function FxTex(size, r, g, b, path)
  local t = frame:CreateTexture(nil, "OVERLAY", nil, 2)
  t:SetTexture(path or (ART .. "fx_glow"))
  t:SetBlendMode("ADD")
  t:SetVertexColor(r, g, b, 1)
  t:SetSize(size, size)
  t:SetAlpha(0)
  fx[#fx + 1] = t
  return t
end

local function AlphaPulse(t, lo, hi, dur, startDelay)
  local ag = NewAG(t, "BOUNCE")
  if not ag then t:SetAlpha(hi) return end
  local a = ag:CreateAnimation("Alpha")
  a:SetFromAlpha(lo); a:SetToAlpha(hi); a:SetDuration(dur)
  if startDelay then ag.delay = startDelay end
  return ag
end

-- Rocking pieces (1.1.1). Rotation AnimationGroups with SetOrigin swung
-- whole pieces in large arcs on this client, so rocking is driven by one
-- 30 Hz Lua tick calling Texture:SetRotation(radians) about the piece's OWN
-- centre: a bounded sine of a few degrees, smooth both ways (like BOUNCE).
-- NS._motion records every moving piece for the harness bounds check.
local rockers = {}
NS._motion = {}
local function Motion(m) NS._motion[#NS._motion + 1] = m end

local function Rock(t, deg, period, phase, cx, cy, w, h, base)
  rockers[#rockers + 1] = { t = t, amp = math.rad(deg), period = period, phase = phase or 0, base = base or 0 }
  Motion({ kind = "rotate", cx = cx, cy = cy, w = w, h = h, deg = deg })
end

local function Spin(t, period, cx, cy, w, h)
  rockers[#rockers + 1] = { t = t, spin = period, base = 0, phase = 0 }
  Motion({ kind = "spin", cx = cx, cy = cy, w = w, h = h })
end

local driver = CreateFrame("Frame")
local acc, clock = 0, 0
local function DriveRockers(_, elapsed)
  acc = acc + (elapsed or 0)
  clock = clock + (elapsed or 0)
  if acc < 1 / 30 then return end
  acc = 0
  local i
  for i = 1, #rockers do
    local r = rockers[i]
    local a
    if r.spin then
      a = -(clock / r.spin) * 2 * math.pi % (2 * math.pi)
    else
      a = r.base + r.amp * math.sin(2 * math.pi * clock / r.period + r.phase)
    end
    if r.t.SetRotation then r.t:SetRotation(a) end
  end
end
NS._DriveRockers = DriveRockers

-- One-shot burst inside a long cycle: startDelay + dur + endDelay = cycle.
local function Burst(t, cycle, offset, dur, peak, dx, dy, cx, cy, size)
  if cx then Motion({ kind = "move", cx = cx, cy = cy, w = size, h = size, dx = dx or 0, dy = dy or 0 }) end
  local ag = NewAG(t, "REPEAT")
  if not ag then return end
  if ag.SetToFinalAlpha then ag:SetToFinalAlpha(false) end
  local up = ag:CreateAnimation("Alpha"); up:SetFromAlpha(0); up:SetToAlpha(peak); up:SetDuration(dur / 2); up:SetStartDelay(offset); up:SetOrder(1)
  local dn = ag:CreateAnimation("Alpha"); dn:SetFromAlpha(peak); dn:SetToAlpha(0); dn:SetDuration(dur / 2); dn:SetOrder(2)
  dn:SetEndDelay(math.max(0, cycle - offset - dur))
  if dx or dy then
    local m1 = ag:CreateAnimation("Translation"); m1:SetOffset((dx or 0) / 2, (dy or 0) / 2); m1:SetDuration(dur / 2); m1:SetStartDelay(offset); m1:SetOrder(1)
    local m2 = ag:CreateAnimation("Translation"); m2:SetOffset((dx or 0) / 2, (dy or 0) / 2); m2:SetDuration(dur / 2); m2:SetOrder(2)
  end
  return ag
end

local function ClearFx()
  local i
  for i = 1, #rockers do if rockers[i].t.SetRotation then rockers[i].t:SetRotation(rockers[i].base or 0) end end
  rockers = {}
  NS._motion = {}
  for i = 1, #groups do pcall(groups[i].Stop, groups[i]) end
  groups = {}
  for i = 1, #fx do fx[i]:Hide(); fx[i]:ClearAllPoints() end
  -- textures cannot be destroyed; keep them pooled
  NS._fxPool = NS._fxPool or {}
  for i = 1, #fx do NS._fxPool[#NS._fxPool + 1] = fx[i] end
  fx = {}
end

local function PooledFx(size, r, g, b, path)
  local pool = NS._fxPool
  local t = pool and table.remove(pool)
  if t then
    t:SetTexture(path or (ART .. "fx_glow")); t:SetBlendMode("ADD"); t:SetVertexColor(r, g, b, 1)
    t:SetSize(size, size); t:SetAlpha(0); if t.SetRotation then pcall(t.SetRotation, t, 0) end; t:Show()
    fx[#fx + 1] = t
    return t
  end
  return FxTex(size, r, g, b, path)
end

local CORNER_PTS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
local CORNER_SGN = { { 1, -1 }, { -1, -1 }, { 1, 1 }, { -1, 1 } }

local function BuildFx(id, W, H)
  ClearFx()
  local th = THEMES[id]
  local CS = 52
  local i
  if id == "emberhall" then
    local pts = { { 8, -8 }, { W - 8, -8 }, { 8, -(H - 8) }, { W - 8, -(H - 8) }, { W / 2, -12 } }
    for i = 1, 5 do
      local g = PooledFx(i == 5 and 22 or 20, 1, 0.47, 0.16)
      g:SetPoint("CENTER", frame, "TOPLEFT", pts[i][1], pts[i][2])
      AlphaPulse(g, 0.05, 0.45, 1.3 + i * 0.13, i * 0.4)
    end
  elseif id == "ironforged" or id == "ursinegrove" then
    local pv = th.pivot
    for i = 1, 4 do
      local s = CORNER_SGN[i]
      local ccx = (s[1] > 0) and CS / 2 or W - CS / 2
      local ccy = (s[2] < 0) and CS / 2 or H - CS / 2
      Rock(P.corner[i], 2, id == "ironforged" and 4.5 or 3.3, i * 1.6, ccx, ccy, CS, CS)
    end
    Rock(P.crest, 2, 5.5, 1, W / 2, 13, 60, 28)
    if id == "ironforged" then
      Rock(P.medallion, 3, 5, 2.4, B + 3 + 14, B + (TB - 28) / 2 + 2 + 14, 28, 28)
      -- steel glint sliding along a blade, one corner every 5 s (20 s cycle)
      for i = 1, 4 do
        local s = CORNER_SGN[i]
        local g = PooledFx(12, 1, 1, 1)
        -- glint slides along the blade, from the hilt toward the tip (stays in the 52 px corner)
        g:SetPoint("CENTER", frame, CORNER_PTS[i], s[1] * 34, s[2] * 34)
        local gx = (s[1] > 0) and 34 or W - 34
        local gy = (s[2] < 0) and 34 or H - 34
        Burst(g, 20, (i - 1) * 5, 1.2, 0.55, -s[1] * 20, -s[2] * 20, gx, gy, 12)
      end
    else
      -- breeze along the leaf studs + green-gold sheen on a few clusters
      local stride = math.max(1, math.ceil(#studs / 32))
      for i = 1, #studs, stride do
        local st = studs[i]
        if st:IsShown() then Rock(st, 7, 3.3, (st.px + st.py) * 0.012, st.px, st.py, th.studSize, th.studSize, st.base) end
      end
      for i = 1, 3 do
        local st = studs[1 + ((i * 5) % math.max(1, #studs))]
        if st and st:IsShown() then
          local g = PooledFx(th.studSize * 1.15, 0.88, 1, 0.55)
          g:SetPoint("CENTER", st, "CENTER")
          Burst(g, 2.6 * 3, (i - 1) * 2.6, 2.4, 0.32, nil, nil, st.px, st.py, th.studSize * 1.15)
        end
      end
    end
  elseif id == "dawnward" then
    Spin(P.medallion, 48, B + 3 + 14, B + (TB - 28) / 2 + 2 + 14, 28, 28)
    local h1 = PooledFx(40, 1, 0.94, 0.7); h1:SetPoint("CENTER", P.medallion, "CENTER"); AlphaPulse(h1, 0.08, 0.3, 1.6)
    local h2 = PooledFx(32, 1, 0.94, 0.7); h2:SetPoint("CENTER", P.crest, "CENTER"); AlphaPulse(h2, 0.08, 0.3, 1.6, 0.8)
    -- holy motes drifting up from the bottom rail and the side rails
    for i = 1, 10 do
      local m = PooledFx(7, 1, 0.97, 0.84)
      local per = 6 + (i * 0.37 % 1) * 4
      local side = i % 3
      if side == 0 then
        m:SetPoint("CENTER", frame, "BOTTOMLEFT", 30 + ((i * 0.618) % 1) * (W - 60), B * 0.5)
        Burst(m, per, (i * 0.71) % per * 0.5, per * 0.5, 0.5, 0, 28, 30 + ((i * 0.618) % 1) * (W - 60), H - B * 0.5, 7)
      else
        m:SetPoint("CENTER", frame, side == 1 and "BOTTOMLEFT" or "BOTTOMRIGHT", side == 1 and B * 0.5 or -B * 0.5, 30)
        Burst(m, per, (i * 0.53) % per * 0.5, per * 0.5, 0.5, 0, H - 60, side == 1 and B * 0.5 or W - B * 0.5, H - 30, 7)
      end
    end
    -- light sweep across the rails every 8 s
    local rails = { { "TOPLEFT", -B * 0.5 }, { "BOTTOMLEFT", B * 0.5 } }
    for i = 1, 2 do
      local sw = PooledFx(B + 6, 1, 0.98, 0.9, ART .. "fx_sweep")
      sw:SetSize(60, B)
      sw:SetPoint("CENTER", frame, rails[i][1], 30, rails[i][2])
      if sw.SetRotation then pcall(sw.SetRotation, sw, -0.5) end
      Burst(sw, 8, (i - 1) * 0.25, 2.2, 0.28, W - 60, 0, 30, i == 1 and B * 0.5 or H - B * 0.5, B)
    end
  elseif id == "voidbound" then
    local stride = math.max(2, math.ceil(#studs / 32))
    for i = 1, #studs, stride do
      local st = studs[i]
      if st:IsShown() then AlphaPulse(st, 0.45, 1, 1.4 + (i % 5) * 0.2, (i % 9) * 0.3) end
    end
    -- wisps orbiting the border
    local per = 2 * (W + H)
    for i = 1, 5 do
      local w = PooledFx(28, (i % 3 == 0) and 0.43 or 0.67, (i % 3 == 0) and 1 or 0.35, (i % 3 == 0) and 0.43 or 1)
      w:SetAlpha(i % 3 == 0 and 0.28 or 0.35)
      w:SetPoint("CENTER", frame, "TOPLEFT", B * 0.5, -B * 0.5)
      local ag = NewAG(w, "REPEAT")
      if ag then
        local sp = 22 + i * 7
        local legs = { { W - B, 0, W }, { 0, -(H - B), H }, { -(W - B), 0, W }, { 0, H - B, H } }
        local j
        local x, y = B * 0.5, B * 0.5
        for j = 1, 4 do
          x, y = x + legs[j][1], y - legs[j][2]
          Motion({ kind = "path", cx = x, cy = y, w = 0, h = 0, dx = 0, dy = 0 })
          local mv = ag:CreateAnimation("Translation")
          mv:SetOffset(legs[j][1], legs[j][2]); mv:SetDuration(legs[j][3] / sp); mv:SetOrder(j)
        end
        ag.delay = (i - 1) * per / 5 / sp
        w.keepAlpha = true
      end
    end
  end
end

local playing = false
function NS.ThemeAnimate(on)
  on = on and Animate()
  local i
  for i = 1, #groups do
    local ag = groups[i]
    if on then
      if ag.delay and ag.delay > 0 and C_Timer and C_Timer.After then
        local d = ag.delay
        C_Timer.After(d, function() if playing then pcall(ag.Play, ag) end end)
      else
        pcall(ag.Play, ag)
      end
    else
      pcall(ag.Stop, ag)
    end
  end
  for i = 1, #fx do
    if on then fx[i]:Show() else fx[i]:Hide() end
  end
  playing = on and true or false
  if playing and #rockers > 0 then driver:SetScript("OnUpdate", DriveRockers)
  else
    driver:SetScript("OnUpdate", nil)
    for i = 1, #rockers do if rockers[i].t.SetRotation then rockers[i].t:SetRotation(rockers[i].base or 0) end end
  end
end

-- -------------------------------------------------------------- layout ---
local function Skin(id)
  local th = THEMES[id]
  local p = ART .. id .. "_"
  local W, H = sizeW, sizeH
  SetTiled(P.body, p .. "material", W, H, 128)
  P.shade:SetColorTexture(0, 0, 0, 0.18)
  SetTiled(P.well, p .. "panel", W - 2 * B, H - 2 * B, 128)
  P.wellTint:SetColorTexture(th.well[1] / 255, th.well[2] / 255, th.well[3] / 255, th.well[4])
  P.header:SetColorTexture(th.header[1] / 255, th.header[2] / 255, th.header[3] / 255, th.header[4])
  local r1, g1, b1 = hex(th.trim[1]); local r2, g2, b2 = hex(th.trim[2]); local r3, g3, b3 = hex(th.trim[3])
  PlaceRing("rim", 0, 1, 0, 0, 0, 0.95)
  PlaceRing("shadow", B - 5, 2, 0, 0, 0, 0.7)
  PlaceRing("trim", B - 3, 3, r2, g2, b2, 1)
  PlaceRing("trimHi", B - 3, 1, r1, g1, b1, 0.8)
  P.divider:SetColorTexture(r2, g2, b2, 0.85)
  P.diamond:SetColorTexture(r1, g1, b1, 1)
  local CS = 52
  local coords = { { 0, 0.75, 0, 0.75 }, { 0.75, 0, 0, 0.75 }, { 0, 0.75, 0.75, 0 }, { 0.75, 0, 0.75, 0 } }
  local i
  for i = 1, 4 do
    local c = P.corner[i]
    c:SetTexture(p .. "corner")
    c:SetTexCoord(coords[i][1], coords[i][2], coords[i][3], coords[i][4])
    c:SetSize(CS, CS)
    c:ClearAllPoints()
    c:SetPoint(CORNER_PTS[i], frame, CORNER_PTS[i], 0, 0)
  end
  P.crest:SetTexture(p .. "crest"); P.crest:SetTexCoord(0, 0.9375, 0, 0.875)
  P.crest:SetSize(60, 28); P.crest:ClearAllPoints(); P.crest:SetPoint("TOP", frame, "TOP", 0, 1)
  P.medallion:SetTexture(p .. "medallion"); P.medallion:SetTexCoord(0, 0.5625, 0, 0.5625)
  P.medallion:SetSize(28, 28); P.medallion:ClearAllPoints()
  P.medallion:SetPoint("TOPLEFT", frame, "TOPLEFT", B + 3, -(B + (TB - 28) / 2 + 2))
  -- plaque: 3-slice of a 300x56 image in a 512x64 TGA
  local ww = W - 2 * B
  local pw = math.max(80, math.min(176, ww - 110))
  local ph, e = 28, 24
  local u = 1 / 512
  P.plaqueL:SetTexture(p .. "plaque"); P.plaqueL:SetTexCoord(0, 48 * u, 0, 0.875)
  P.plaqueM:SetTexture(p .. "plaque"); P.plaqueM:SetTexCoord(48 * u, 252 * u, 0, 0.875)
  P.plaqueR:SetTexture(p .. "plaque"); P.plaqueR:SetTexCoord(252 * u, 300 * u, 0, 0.875)
  local py = -(B + (TB - ph) / 2 + 2)
  P.plaqueL:ClearAllPoints(); P.plaqueL:SetSize(e, ph); P.plaqueL:SetPoint("TOPLEFT", frame, "TOP", -pw / 2, py)
  P.plaqueR:ClearAllPoints(); P.plaqueR:SetSize(e, ph); P.plaqueR:SetPoint("TOPRIGHT", frame, "TOP", pw / 2, py)
  P.plaqueM:ClearAllPoints(); P.plaqueM:SetPoint("TOPLEFT", P.plaqueL, "TOPRIGHT"); P.plaqueM:SetPoint("BOTTOMRIGHT", P.plaqueR, "BOTTOMLEFT")
  P.title:ClearAllPoints(); P.title:SetPoint("CENTER", P.plaqueM, "CENTER", 0, 0)
  P.title:SetText(th.title); P.title:SetTextColor(hex(th.plaque))
  -- studs
  local pos = StudPositions(W, H, th.studStep)
  for i = 1, math.max(#pos, #studs) do
    local s = studs[i]
    if i <= #pos then
      if not s then s = Tex("ARTWORK", 1); studs[i] = s end
      local k = (i - 1) % th.studs
      s:SetTexture(p .. "stud" .. k)
      local uu = (id == "ursinegrove") and 0.5625 or 0.75
      s:SetTexCoord(0, uu, 0, uu)
      s:SetSize(th.studSize, th.studSize)
      s:ClearAllPoints(); s:SetPoint("CENTER", frame, "TOPLEFT", pos[i][1], pos[i][2])
      if s.SetRotation then pcall(s.SetRotation, s, pos[i][3]) end
      s.px, s.py, s.base = pos[i][1], -pos[i][2], pos[i][3]
      s:SetAlpha(1)
      s:Show()
    elseif s then
      s:Hide()
    end
  end
end

-- Called by the meter when its size or the theme/effect options change.
function NS.ThemeLayout(parent, W, H, force)
  if not frame then Build(parent) end
  W, H = math.floor(W + 0.5), math.floor(H + 0.5)
  local id = NS.ThemeId()
  local key = id .. (Animate() and "a" or "s")
  if not force and builtFor == key and W == sizeW and H == sizeH then return end
  sizeW, sizeH, builtFor = W, H, key
  NS.ThemeAnimate(false)
  Skin(id)
  BuildFx(id, W, H)
  if Animate() and NS.themeActive then NS.ThemeAnimate(true) end
end

function NS.ThemeRefresh()
  if frame and host then NS.ThemeLayout(host, sizeW, sizeH, true) end
  if NS.RestyleRows then NS.RestyleRows() end
end

function NS.ThemeTitle(id) return (THEMES[id or ""] or {}).title end
function NS.ThemeGroupCount() return #groups end
function NS.ThemeRockerCount() return #rockers end
function NS.ThemeSize() return sizeW, sizeH end
