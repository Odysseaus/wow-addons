-- WoWThreat Fire: the bar IS the fire (PLAN-visuals 1).
-- Fireplace = baked per-theme flame-wall sheets (4x8 frames of 256x64,
-- seamless in x and time), tiled at a fixed texel scale and cropped by a
-- clip frame sized to the threat width (never stretched).
--
-- 1.1.2 playback: no FlipBook. One shared clock (seconds * fps * speed)
-- drives every visible fire layer from a single OnUpdate. Each layer is two
-- textures showing frame i and i+1 (SetTexCoord) crossfaded by the fractional
-- part, so motion is continuous at any frame rate. Data updates only resize
-- and re-alpha; they never restart anything. Fire speed changes the clock
-- rate only. With > 20 rows (or Reduced effects) layers just step frames.
local _, NS = ...

local TEX = "Interface\\AddOns\\WoWThreat\\Textures\\"
local MAX_TILES = 3
local MAX_SPARKS = 4
local REF_INNER = 12        -- bar inner px the sheet was baked for
local REF_H = 22            -- display px one frame covers at REF_INNER
local REF_W = 256
local ALPHA_EPS = 0.02

local STYLES = {
  fireplace = { rows = 8, cols = 4, frames = 32, fps = 8, blend = "BLEND" },
  classic = { rows = 4, cols = 4, frames = 16, fps = 16, blend = "ADD", tex = TEX .. "Fire_Flipbook" },
}

local function DB() return WoWThreatDB or {} end

-- 1.3.0: "gem" is a standalone polished-stone bar (no flames over it), so it
-- stays on even with Show fire off; Show fire then only drops its glow/sheen.
-- Anything unknown (incl. the removed "tongues") draws as Fireplace.
local function Style()
  local db = DB()
  local s = db.fireStyle
  if s == "gem" then return "gem" end
  if db.showFire == false then return "off" end
  if s == "classic" or s == "off" or s == "castbar" then return s end
  return "fireplace"
end
NS.FireStyle = Style

local function Reduced() return DB().reducedEffects == true end

local function Speed()
  local s = DB().fireSpeed
  if type(s) ~= "number" then return 1 end
  if s < 0.5 then return 0.5 elseif s > 1.5 then return 1.5 end
  return s
end

-- --------------------------------------------------------------- clock ---
-- clock is in "frames at 1 fps-unit": advances dt*speed each tick, so a
-- speed change alters only the rate, never the position (monotonic).
local clock = 0
local active = {}          -- rows with fire showing
local nActive = 0
NS.fireAnimCalls = 0       -- Play/Stop/SetDuration issued by fire (harness)
local driver = CreateFrame("Frame")
local CBPaint              -- castbar painter (defined below)
local GemPaint             -- gem sheen painter (defined below)

-- Harness counters: fireAnimCalls = Stop/SetDuration (restarts); a first
-- Play of a spark/core pulse when it first appears is counted separately.
NS.fireAnimStarts = 0
local function AnimCall(obj, method)
  if method == "Play" then NS.fireAnimStarts = NS.fireAnimStarts + 1
  else NS.fireAnimCalls = NS.fireAnimCalls + 1 end
  pcall(obj[method], obj)
end

function NS.FireClock() return clock end

local function SetFrame(tex, st, i)
  local c = i % st.cols
  local rr = (i - c) / st.cols
  tex:SetTexCoord(c / st.cols, (c + 1) / st.cols, rr / st.rows, (rr + 1) / st.rows)
end

-- Update one layer pair (a = frame i, b = frame i+1) for frame position fpos.
local function Paint(L, st, fpos, alpha, smooth)
  local n = st.frames
  local base = math.floor(fpos)
  local i = base % n
  if L.i ~= i then
    L.i = i
    SetFrame(L.a, st, i)
    if smooth then SetFrame(L.b, st, (i + 1) % n) end
  end
  local fa, fb
  if smooth then
    local f = fpos - base
    fa, fb = alpha * (1 - f), alpha * f
  else
    fa, fb = alpha, 0
  end
  if math.abs((L.fa or -1) - fa) > ALPHA_EPS or (fa == 0) ~= (L.fa == 0) then L.fa = fa; L.a:SetAlpha(fa) end
  if math.abs((L.fb or -1) - fb) > ALPHA_EPS or (fb == 0) ~= (L.fb == 0) then
    L.fb = fb; L.b:SetAlpha(fb)
    if fb > 0 then if not L.bShown then L.b:Show(); L.bShown = true end
    elseif L.bShown then L.b:Hide(); L.bShown = false end
  end
end

local function PaintRow(r)
  local st = STYLES[r.fStyle]
  if not st then return end
  local j
  for j = 1, r.fNeed or 0 do
    local t = r.tiles[j]
    local fpos = clock * st.fps + t.phase * st.frames
    Paint(t.body, st, fpos, r.fAlpha, r.fSmooth)
    if r.fGlow then Paint(t.glow, st, fpos, 0.14, r.fSmooth) end
  end
end

local function Drive(_, elapsed)
  local dt = (elapsed or 0) * Speed()
  clock = clock + dt
  local r
  for r in pairs(active) do
    if r.fStyle == "castbar" then CBPaint(r, dt)
    elseif r.fStyle == "gem" then GemPaint(r)
    else PaintRow(r) end
  end
end

-- ------------------------------------------------------- castbar (1.2.0) ---
-- Layered scrolling-texture fire (our own baked art, tools/bake_castbar.py):
-- base (BLEND), flow (ADD, scrolls upward, flickering alpha), veil (ADD, slow
-- drift) on the black bar, all sized to the FULL bar and cropped by the clip,
-- so the texel scale is fixed (k = inner/64) at any bar size. Offsets advance
-- from the shared fire clock's dt; speeds drift through a sum of sines. A
-- leading-edge spark and a few pooled embers ride on top. No AnimationGroups,
-- so nothing can restart; data updates only resize and re-alpha.
local CB_W, CB_VW, CB_H = 512, 256, 64
local MAX_EMBERS = 6
local TAU = 6.2831853
local VEIL_R, VEIL_G, VEIL_B = 1, 0.47, 0.12
local sin = math.sin
NS.castbarPaints = 0

local function CBWob(cb, t, o)
  return sin(t * cb.f1 * TAU + cb.p1 + o) * 0.5 + sin(t * cb.f2 * TAU + cb.p2 + o * 1.7) * 0.3
    + sin(t * cb.f3 * TAU + cb.p3 + o * 2.3) * 0.2
end

local function CBAlpha(tex, cb, key, a)
  if math.abs((cb[key] or -1) - a) > ALPHA_EPS then cb[key] = a; tex:SetAlpha(a) end
end

local function CBRespawn(e, cb, first)
  e.x = math.random() * (cb.fillW or 10)
  e.y = (cb.inner or 12) * math.random() * 0.65
  e.age = first and -math.random() * 0.8 or 0
  e.max = 0.5 + math.random() * 0.7
  e.vx = (math.random() - 0.5) * 16
  e.vy = 15 + math.random() * 30
  e.sw = math.random() * TAU
  e.sz = 2 + math.random() * 2
end

CBPaint = function(r, dt)
  local cb = r.cb
  if not cb or not cb.on then return end
  NS.castbarPaints = NS.castbarPaints + 1
  local t = clock
  local sm = 1 + 0.45 * CBWob(cb, t, 0)
  cb.u = (cb.u + 0.02 * sm * dt) % 1
  cb.u2 = (cb.u2 + 0.025 * sm * dt) % 1
  cb.v = (cb.v + 0.55 * dt * (1 + 0.3 * CBWob(cb, t + 9, 1))) % 1
  cb.uv = (cb.uv + 0.015 * dt) % 1
  local span = cb.span
  cb.base:SetTexCoord(cb.u, cb.u + span, 0, 1)
  cb.flow:SetTexCoord(cb.u2, cb.u2 + span, cb.v, cb.v + 1)
  local I = cb.inten
  if cb.flicker then
    CBAlpha(cb.flow, cb, "fa", (0.5 + 0.45 * (0.5 + 0.5 * CBWob(cb, t * 6, 3))) * (0.55 + 0.45 * I))
  end
  if cb.veilOn then
    cb.veil:SetTexCoord(cb.uv, cb.uv + cb.vspan, 0, 1)
    CBAlpha(cb.veil, cb, "va", (0.35 + 0.2 * CBWob(cb, t + 3, 5)) * (0.6 + 0.4 * I))
  end
  if cb.sparkOn then CBAlpha(cb.spark, cb, "sa", (0.75 + 0.25 * CBWob(cb, t * 6, 1)) * (0.6 + 0.4 * I)) end
  local j
  for j = 1, cb.nEmbers do
    local e = cb.embers[j]
    e.age = e.age + dt
    if e.age >= e.max then CBRespawn(e, cb, false) end
    if e.age < 0 then
      if e.shown then e.tex:Hide(); e.shown = false end
    else
      local tt = e.age / e.max
      e.vx = e.vx + sin(e.age * 6 + e.sw) * 20 * dt
      local a = (1 - tt) * math.min(1, tt * 6) * (0.6 + 0.4 * I)
      e.tex:SetPoint("CENTER", r.fireClip, "BOTTOMLEFT", e.x + e.vx * e.age * 0.3, e.y + e.vy * e.age * 0.35)
      e.tex:SetAlpha(a)
      if not e.shown then e.tex:Show(); e.shown = true end
    end
  end
end

local function CBCreate(r)
  local clip = r.fireClip
  local cb = { u = math.random(), u2 = math.random(), v = math.random(), uv = math.random(),
    f1 = 0.07 + math.random() * 0.05, f2 = 0.17 + math.random() * 0.09, f3 = 0.37 + math.random() * 0.16,
    p1 = math.random() * TAU, p2 = math.random() * TAU, p3 = math.random() * TAU, span = 1, vspan = 1,
    inten = 0.8, nEmbers = 0, embers = {} }
  local function layer(name, blend, sub)
    local tex = clip:CreateTexture(nil, "ARTWORK", nil, sub)
    tex:SetTexture(TEX .. name, "REPEAT", "REPEAT")
    tex:SetBlendMode(blend)
    tex:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
    tex:Hide()
    return tex
  end
  cb.base = layer("CB_Base", "BLEND", 0)
  cb.flow = layer("CB_Flow", "ADD", 1)
  cb.veil = layer("CB_Veil", "ADD", 2)
  cb.veil:SetVertexColor(VEIL_R, VEIL_G, VEIL_B, 1)
  -- 1.3.0: spark and embers are clipped inside the bevel seat like the rest
  local fx = CreateFrame("Frame", nil, clip)
  fx:SetAllPoints(clip)
  fx:SetFrameLevel(clip:GetFrameLevel() + 1)
  cb.fx = fx
  cb.spark = fx:CreateTexture(nil, "OVERLAY", nil, 6)
  cb.spark:SetTexture(TEX .. "CB_Spark")
  cb.spark:SetBlendMode("ADD")
  cb.spark:Hide()
  local j
  for j = 1, MAX_EMBERS do
    local e = { tex = fx:CreateTexture(nil, "OVERLAY", nil, 5) }
    e.tex:SetTexture(TEX .. "CB_Ember")
    e.tex:SetBlendMode("ADD")
    e.tex:SetSize(3, 3)
    e.tex:Hide()
    CBRespawn(e, cb, true)
    cb.embers[j] = e
  end
  r.cb = cb
  return cb
end

local function CBHide(r)
  local cb = r.cb
  if not cb or not cb.on then return end
  cb.on = false
  cb.base:Hide(); cb.flow:Hide(); cb.veil:Hide(); cb.spark:Hide()
  cb.fa, cb.va, cb.sa = nil, nil, nil
  local j
  for j = 1, MAX_EMBERS do local e = cb.embers[j]; e.tex:Hide(); e.shown = false end
  cb.nEmbers = 0
end
NS._CBHide = CBHide

-- Layout for the castbar style (data update): sizes, flags, counts only.
local function CBUpdate(r, pct, width, inner, inten, reduced, big, alpha)
  local cb = r.cb or CBCreate(r)
  local barW = math.max(8, ((r.bar.GetWidth and r.bar:GetWidth()) or 240) - 2 * (r.bevB or 1))
  local k = inner / CB_H
  if cb.barW ~= barW or cb.inner ~= inner then
    cb.barW, cb.inner = barW, inner
    cb.span, cb.vspan = barW / (CB_W * k), barW / (CB_VW * k)
    cb.base:SetSize(barW, inner); cb.flow:SetSize(barW, inner); cb.veil:SetSize(barW, inner)
    cb.spark:SetSize(inner * 0.9, inner * 1.7)
  end
  cb.fillW, cb.inten = width, inten
  if not cb.on then
    cb.on = true
    cb.base:Show(); cb.flow:Show()
  end
  if math.abs((cb.ba or -1) - alpha) > ALPHA_EPS then cb.ba = alpha; cb.base:SetAlpha(alpha) end
  cb.flicker = not reduced
  if reduced then CBAlpha(cb.flow, cb, "fa", 0.6 * (0.55 + 0.45 * inten)) end
  local veilOn = not reduced and not big
  if veilOn ~= cb.veilOn then cb.veilOn = veilOn; cb.va = nil; if veilOn then cb.veil:Show() else cb.veil:Hide() end end
  local sparkOn = pct > 0.01 and pct < 0.995
  if sparkOn ~= cb.sparkOn then cb.sparkOn = sparkOn; cb.sa = nil; if sparkOn then cb.spark:Show() else cb.spark:Hide() end end
  if sparkOn then cb.spark:SetPoint("CENTER", r.fireClip, "BOTTOMLEFT", width, inner * 0.5) end
  local n = 0
  if not reduced and not big then n = math.ceil(MAX_EMBERS * (0.4 + 0.6 * inten) * (0.3 + 0.7 * pct)) end
  if n > MAX_EMBERS then n = MAX_EMBERS end
  local j
  for j = n + 1, cb.nEmbers do local e = cb.embers[j]; e.tex:Hide(); e.shown = false end
  cb.nEmbers = n
end

local Activate
Activate = function(r, on)
  if on and not active[r] then
    active[r] = true; nActive = nActive + 1
    if nActive == 1 then driver:SetScript("OnUpdate", Drive) end
  elseif not on and active[r] then
    active[r] = nil; nActive = nActive - 1
    if nActive == 0 then driver:SetScript("OnUpdate", nil) end
  end
end
function NS.FireActiveCount() return nActive end
NS._FireDrive = Drive

-- ---------------------------------------------------------------- build ---
local maskOK = nil
local function NewLayer(clip, sub, blend)
  local L = {}
  L.a = clip:CreateTexture(nil, "ARTWORK", nil, sub)
  L.b = clip:CreateTexture(nil, "ARTWORK", nil, sub + 1)
  L.b:SetPoint("TOPLEFT", L.a, "TOPLEFT"); L.b:SetPoint("BOTTOMRIGHT", L.a, "BOTTOMRIGHT")
  if blend then L.a:SetBlendMode(blend); L.b:SetBlendMode(blend) end
  L.a:Hide(); L.b:Hide()
  return L
end

local function SheetFor(style)
  if style == "classic" then return STYLES.classic.tex end
  -- 1.1.4: one fire for every theme (the Ironforged sheet).
  return TEX .. "Fire_Fireplace_ironforged"
end

function NS.FireCreate(r)
  NS.BarFrameCreate(r)
  local clip = CreateFrame("Frame", nil, r.bar)
  clip:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", 1, 1)  -- re-anchored to the bevel seat by NS.BarFrameUpdate
  clip:SetSize(1, 1)
  if clip.SetClipsChildren then clip:SetClipsChildren(true) end
  clip:SetFrameLevel(r.bar:GetFrameLevel() + 1)
  r.fireClip = clip
  r.tiles = {}
  local j
  for j = 1, MAX_TILES do
    -- fixed per-tile phase so neighbouring tiles never line up
    r.tiles[j] = { body = NewLayer(clip, 0), glow = NewLayer(clip, 3, "ADD"), phase = ((j - 1) * 0.37) % 1 }
  end
  r.core = clip:CreateTexture(nil, "ARTWORK", nil, 5)
  r.core:SetTexture(TEX .. "Fire_Core")
  r.core:SetBlendMode("ADD")
  r.core:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
  r.core:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
  r.core:Hide()
  pcall(function()
    local ag = r.core:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.45); a:SetToAlpha(1); a:SetDuration(0.65)
    ag:SetLooping("BOUNCE")
    r.coreAG = ag
  end)
  r.sparks = {}
  for j = 1, MAX_SPARKS do
    local s = clip:CreateTexture(nil, "ARTWORK", nil, 6)
    s:SetTexture(TEX .. "Spark")
    s:SetBlendMode("ADD")
    s:SetSize(3, 3)
    s:Hide()
    local sp = { tex = s, frac = (j - 0.5) / MAX_SPARKS + (math.random() - 0.5) * 0.18 }
    pcall(function()
      local ag = s:CreateAnimationGroup()
      local mv = ag:CreateAnimation("Translation")
      mv:SetOffset((math.random() - 0.5) * 6, 14 + math.random() * 8)
      mv:SetDuration(1.1 + math.random() * 0.8)
      local fin = ag:CreateAnimation("Alpha")
      fin:SetFromAlpha(0); fin:SetToAlpha(0.9); fin:SetDuration(0.25)
      local fout = ag:CreateAnimation("Alpha")
      fout:SetFromAlpha(0.9); fout:SetToAlpha(0); fout:SetDuration(0.8)
      fout:SetStartDelay(0.3)
      ag:SetLooping("REPEAT")
      if ag.SetToFinalAlpha then ag:SetToFinalAlpha(false) end
      sp.ag = ag
    end)
    r.sparks[j] = sp
  end
  -- Tapered tip: a mask fading the last texels of the crop, else a tip cap.
  if maskOK == nil then maskOK = clip.CreateMaskTexture and true or false end
  if maskOK then
    local ok = pcall(function()
      local m = clip:CreateMaskTexture()
      m:SetTexture(TEX .. "TipMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetAllPoints(clip)
      r.tipMask = m
    end)
    if not ok then r.tipMask = nil end
  end
  if not r.tipMask then
    r.tipCap = clip:CreateTexture(nil, "ARTWORK", nil, 7)
    r.tipCap:SetTexture(TEX .. "TipCap")
    r.tipCap:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
    r.tipCap:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    r.tipCap:SetWidth(8)
  end
  r.fireKey = nil
  clip:Hide()
end

local function HideLayer(L)
  L.a:Hide(); L.b:Hide(); L.bShown = false; L.fa, L.fb, L.i = nil, nil, nil
end

-- Full stop: row released / fire turned off. The clock keeps running, so
-- the fire resumes at the shared phase (no reset look).
function NS.FireStop(r)
  if not r.fireClip then return end
  Activate(r, false)
  local j
  for j = 1, MAX_TILES do HideLayer(r.tiles[j].body); HideLayer(r.tiles[j].glow) end
  r.fNeed = 0
  CBHide(r)
  for j = 1, MAX_SPARKS do
    local sp = r.sparks[j]
    if sp.playing and sp.ag then AnimCall(sp.ag, "Stop") end
    sp.playing = false
    sp.tex:Hide()
  end
  if r.corePlaying and r.coreAG then AnimCall(r.coreAG, "Stop") end
  r.corePlaying = false
  r.core:Hide()
  r.fireOn = false
  r.fireClip:Hide()
  if r.gemOn and NS.GemHide then NS.GemHide(r) end
end

local function Restyle(r, style, sheet)
  local st = STYLES[style]
  local j
  for j = 1, MAX_TILES do
    local t = r.tiles[j]
    local L
    for _, L in ipairs({ t.body, t.glow }) do
      L.a:SetTexture(sheet); L.b:SetTexture(sheet)
      L.i, L.fa, L.fb = nil, nil, nil
    end
    t.body.a:SetBlendMode(st.blend); t.body.b:SetBlendMode(st.blend)
    if r.tipMask and not t.masked then
      for _, L in ipairs({ t.body, t.glow }) do
        pcall(L.a.AddMaskTexture, L.a, r.tipMask); pcall(L.b.AddMaskTexture, L.b, r.tipMask)
      end
      t.masked = true
    end
  end
  r.fireKey = style .. "|" .. sheet
end

-- Layout only (called while the row eases): sizes, counts, alpha. Never
-- touches animation state of the flames.
function NS.FireUpdate(r, pct, width, barH, dt, rank, nrows)
  if not r.fireClip then return false end
  local db = DB()
  local style = Style()
  local inten = type(db.fireIntensity) == "number" and db.fireIntensity or 0.8
  if style == "gem" and width >= 1 and r:IsShown() then
    if r.fireOn or r.fireClip:IsShown() then NS.FireStop(r) end
    NS.GemUpdate(r, inten, db.showFire ~= false)
    return false
  end
  if r.gemOn then NS.GemHide(r) end
  if style == "off" or inten <= 0 or width < 2 or not r:IsShown() then
    if r.fireOn or r.fireClip:IsShown() then NS.FireStop(r) end
    return false
  end
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  local reduced = Reduced()
  local sheet = SheetFor(style)
  if style ~= "castbar" and r.fireKey ~= style .. "|" .. sheet then Restyle(r, style, sheet) end

  -- 1.3.0: fire is clipped inside the bevel seat (no overflow above the bar).
  local inner = math.max(2, r.seatH or (barH - 2))
  width = math.max(2, r.seatW or width)
  r.fireClip:SetSize(width, inner)
  if not r.fireOn then r.fireClip:Show(); r.fireOn = true end

  if style == "castbar" then
    local big = (nrows or 1) > 20
    local alpha = (0.88 + 0.12 * pct) * (0.85 + 0.15 * inten)
    if alpha > 1 then alpha = 1 end
    -- hide the fireplace/classic pieces (once), then lay out the castbar layers
    if r.fStyle ~= "castbar" or (r.fNeed or 0) > 0 then
      local j
      for j = 1, MAX_TILES do HideLayer(r.tiles[j].body); HideLayer(r.tiles[j].glow) end
      r.fNeed = 0
      for j = 1, MAX_SPARKS do r.sparks[j].tex:Hide() end
      if r.tipCap then r.tipCap:Hide() end
    end
    r.fStyle = "castbar"
    CBUpdate(r, pct, width, inner, inten, Reduced(), big, alpha)
    Activate(r, true)
    if pct > 0.9 and not Reduced() then
      r.core:SetHeight(inner * 0.7)
      r.core:SetAlpha(math.min(1, (pct - 0.9) / 0.1) * 0.3)
      if not r.core:IsShown() then r.core:Show() end
      if not r.corePlaying and r.coreAG then r.corePlaying = true; AnimCall(r.coreAG, "Play") end
    elseif r.core:IsShown() then
      r.core:Hide()
    end
    return false
  end
  if r.fStyle == "castbar" then CBHide(r); if r.tipCap then r.tipCap:Show() end end

  local s = inner / REF_INNER
  local tileW, texH
  if style == "classic" then
    tileW = (r.bar:GetWidth() or 240) - 2
    texH = inner * (0.35 + 0.65 * pct)
  else
    tileW = REF_W * s
    texH = REF_H * s * (0.6 + 0.4 * pct) * (0.8 + 0.2 * inten)
  end
  if tileW < 8 then tileW = 8 end
  local need = math.min(MAX_TILES, math.ceil(width / tileW))
  if reduced then need = math.min(need, 1) end
  local big = (nrows or 1) > 20
  local alpha = (0.88 + 0.12 * pct) * (0.85 + 0.15 * inten)
  if style == "classic" then alpha = 0.25 + 0.75 * pct * inten end
  if alpha > 1 then alpha = 1 end
  local cr, cg, cb = 1, 1, 1
  if style == "classic" and NS.ThemeFireColor then cr, cg, cb = NS.ThemeFireColor() end
  local glowOn = not reduced and not big and style == "fireplace"
  local smooth = not reduced and not big

  if smooth ~= r.fSmooth or glowOn ~= r.fGlow then
    local j
    for j = 1, MAX_TILES do
      local t = r.tiles[j]
      t.body.i, t.body.fa, t.body.fb = nil, nil, nil
      if not glowOn then HideLayer(t.glow) end
      if not smooth then t.body.b:Hide(); t.body.bShown = false end
    end
  end
  r.fAlpha, r.fGlow, r.fSmooth = alpha, glowOn, smooth
  local j
  for j = 1, MAX_TILES do
    local t = r.tiles[j]
    if j <= need then
      local a = t.body.a
      if t.x ~= (j - 1) * tileW or t.w ~= tileW or math.abs((t.h or 0) - texH) > 0.25 then
        t.x, t.w, t.h = (j - 1) * tileW, tileW, texH
        a:ClearAllPoints()
        a:SetPoint("BOTTOMLEFT", r.fireClip, "BOTTOMLEFT", t.x, 0)
        a:SetSize(tileW, texH)
        t.glow.a:ClearAllPoints()
        t.glow.a:SetAllPoints(a)
      end
      if t.cr ~= cr or t.cg ~= cg or t.cb ~= cb then
        t.cr, t.cg, t.cb = cr, cg, cb
        a:SetVertexColor(cr, cg, cb, 1); t.body.b:SetVertexColor(cr, cg, cb, 1)
      end
      if not a:IsShown() then a:Show() end
      if glowOn and not t.glow.a:IsShown() then t.glow.a:Show() end
    elseif t.body.a:IsShown() then
      HideLayer(t.body); HideLayer(t.glow)
    end
  end
  r.fNeed = need
  r.fStyle = style
  Activate(r, true)
  PaintRow(r)

  -- Sparks: started once per fire session, then only shown/hidden.
  local nsp = 0
  if not reduced and style == "fireplace" and (not big or (rank or 1) <= 10) then
    nsp = math.ceil(MAX_SPARKS * pct)
  end
  for j = 1, MAX_SPARKS do
    local sp = r.sparks[j]
    if j <= nsp and sp.ag then
      sp.tex:ClearAllPoints()
      sp.tex:SetPoint("BOTTOMLEFT", r.fireClip, "BOTTOMLEFT", sp.frac * (width - 4), inner * 0.45)
      if not sp.tex:IsShown() then sp.tex:Show() end
      if not sp.playing then sp.playing = true; AnimCall(sp.ag, "Play") end
    elseif sp.tex:IsShown() then
      sp.tex:Hide()
    end
  end

  -- White-hot core above 90%: shown/hidden; its pulse plays once per session.
  if pct > 0.9 and not reduced then
    r.core:SetHeight(inner * 0.7)
    r.core:SetAlpha(math.min(1, (pct - 0.9) / 0.1) * 0.36)
    if not r.core:IsShown() then r.core:Show() end
    if not r.corePlaying and r.coreAG then r.corePlaying = true; AnimCall(r.coreAG, "Play") end
  elseif r.core:IsShown() then
    r.core:Hide()
  end
  if r.tipCap then r.tipCap:SetWidth(math.min(8, width * 0.25)) end
  return false
end

-- ------------------------------------------- bevel frame + gem (1.3.0) ---
-- Ported from the approved previewer (threat.js bevelFrame/gemFill). Every
-- style sits in the same beveled bronze frame that wraps the filled length
-- (min. one bar height wide, so the caps never squash). Contents (fire, gem,
-- plain fill) are clipped to the frame's inner seat. Art: tools/bake_gem.py.
local BEV_B = 6 / 32         -- border thickness / bar height (baked 32 px tall, 6 px border)
local GEM_COLORS = {         -- #1 red, #2 orange, #3 gold, rest dark bronze (deepening)
  { 176, 16, 14 }, { 226, 98, 14 }, { 214, 150, 28 }, { 100, 58, 18 },
}
NS.GEM_COLORS = GEM_COLORS

local function GemColor(rank)
  rank = (rank or 1) - 1
  if rank < 3 then local c = GEM_COLORS[rank + 1]; return c[1] / 255, c[2] / 255, c[3] / 255 end
  local k = math.min(1, (rank - 3) / 12)
  local b = GEM_COLORS[4]
  local m = (1 - 0.3 * k) / 255
  return b[1] * m, b[2] * m, b[3] * m
end
NS.GemColor = GemColor

local function Mul(r, g, b, m)
  return math.min(1, r * m), math.min(1, g * m), math.min(1, b * m)
end

function NS.BarFrameCreate(r)
  if r.bevel then return end
  local bar = r.bar
  local L, M, R = bar:CreateTexture(nil, "BORDER", nil, 1), bar:CreateTexture(nil, "BORDER", nil, 1), bar:CreateTexture(nil, "BORDER", nil, 1)
  L:SetTexture(TEX .. "Bar_Bevel"); M:SetTexture(TEX .. "Bar_Bevel"); R:SetTexture(TEX .. "Bar_Bevel")
  L:SetTexCoord(0, 0.25, 0, 1); M:SetTexCoord(0.25, 0.75, 0, 1); R:SetTexCoord(0.75, 1, 0, 1)
  L:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  M:SetPoint("BOTTOMLEFT", L, "BOTTOMRIGHT", 0, 0)
  R:SetPoint("BOTTOMLEFT", M, "BOTTOMRIGHT", 0, 0)
  L:Hide(); M:Hide(); R:Hide()
  r.bevel = { L = L, M = M, R = R }
  -- seat: clipped container for the gem / plain fill
  local seat = CreateFrame("Frame", nil, bar)
  seat:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 1)
  seat:SetSize(1, 1)
  if seat.SetClipsChildren then seat:SetClipsChildren(true) end
  seat:SetFrameLevel(bar:GetFrameLevel() + 1)
  r.seat = seat
  -- inner shadow over fire styles (above the fire clip)
  local shade = CreateFrame("Frame", nil, bar)
  shade:SetAllPoints(seat)
  shade:SetFrameLevel(bar:GetFrameLevel() + 3)
  r.shadeFrame = shade
  r.shade = shade:CreateTexture(nil, "OVERLAY", nil, 0)
  r.shade:SetTexture(TEX .. "Seat_Shade")
  r.shade:SetAllPoints(shade)
  shade:Hide()
end

-- Layout of the frame for a fill of `width` px on a bar `barH` tall.
function NS.BarFrameUpdate(r, width, barH, showFrame)
  if not r.bevel then return end
  local b = r.bevel
  if not showFrame or width < 1 then
    if r.bevOn then b.L:Hide(); b.M:Hide(); b.R:Hide(); r.bevOn = false end
    r.seatW = 0
    if r.shadeOn then r.shadeFrame:Hide(); r.shadeOn = false end
    return
  end
  local fw = math.max(barH, width + 2)
  local B = math.max(2, barH * BEV_B)
  local cap = barH / 2
  if r.bevH ~= barH or math.abs((r.bevW or -1) - fw) > 0.25 then
    r.bevH, r.bevW = barH, fw
    b.L:SetSize(cap, barH); b.R:SetSize(cap, barH)
    b.M:SetSize(math.max(0.01, fw - 2 * cap), barH)
  end
  if not r.bevOn then b.L:Show(); b.M:Show(); b.R:Show(); r.bevOn = true end
  local sw, sh = math.max(1, fw - 2 * B), math.max(1, barH - 2 * B)
  if r.bevB ~= B then
    r.bevB = B
    r.seat:ClearAllPoints(); r.seat:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", B, B)
    r.fireClip:ClearAllPoints(); r.fireClip:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", B, B)
  end
  if math.abs((r.seatW or -1) - sw) > 0.1 or r.seatH ~= sh then r.seat:SetSize(sw, sh) end
  r.seatW, r.seatH = sw, sh
  local wantShade = Style() ~= "gem"
  if wantShade ~= r.shadeOn then r.shadeOn = wantShade; if wantShade then r.shadeFrame:Show() else r.shadeFrame:Hide() end end
end

local function GemCreate(r)
  local seat = r.seat
  local g = {}
  local function T(name, sub, layer)
    local t = seat:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    if name then t:SetTexture(TEX .. name) end
    t:Hide()
    return t
  end
  g.stone = T(nil, 0)
  g.stone:SetTexture(TEX .. "Gem_Stone", "REPEAT", "CLAMP")
  g.stone:SetPoint("TOPLEFT", seat, "TOPLEFT", 0, 0)
  g.stone:SetPoint("BOTTOMRIGHT", seat, "BOTTOMRIGHT", 0, 0)
  g.glow = T("Gem_Glow", 1); g.glow:SetAllPoints(seat)
  g.endL = T("Gem_End", 2); g.endL:SetPoint("TOPLEFT", seat, "TOPLEFT"); g.endL:SetPoint("BOTTOMLEFT", seat, "BOTTOMLEFT")
  g.endR = T("Gem_End", 2); g.endR:SetPoint("TOPRIGHT", seat, "TOPRIGHT"); g.endR:SetPoint("BOTTOMRIGHT", seat, "BOTTOMRIGHT")
  g.endR:SetTexCoord(1, 0, 0, 1)
  g.sheen = T("Gem_Sheen", 3); g.sheen:SetPoint("TOP", seat, "TOP"); g.sheen:SetPoint("BOTTOM", seat, "BOTTOM")
  g.gloss = T("Gem_Gloss", 4); g.gloss:SetAllPoints(seat)
  g.spot = T("Gem_Spot", 5)
  -- inner bevel of the stone: lit top/left lip, dark bottom/right lip
  g.lt = T(nil, 0, "OVERLAY"); g.lt:SetPoint("TOPLEFT", seat, "TOPLEFT", 0, 0); g.lt:SetPoint("TOPRIGHT", seat, "TOPRIGHT", 0, 0); g.lt:SetHeight(1)
  g.ll = T(nil, 0, "OVERLAY"); g.ll:SetPoint("TOPLEFT", seat, "TOPLEFT", 0, 0); g.ll:SetPoint("BOTTOMLEFT", seat, "BOTTOMLEFT", 0, 0); g.ll:SetWidth(1)
  g.db = T(nil, 1, "OVERLAY"); g.db:SetPoint("BOTTOMLEFT", seat, "BOTTOMLEFT", 0, 0); g.db:SetPoint("BOTTOMRIGHT", seat, "BOTTOMRIGHT", 0, 0); g.db:SetHeight(1)
  g.dr = T(nil, 1, "OVERLAY"); g.dr:SetPoint("TOPRIGHT", seat, "TOPRIGHT", 0, 0); g.dr:SetPoint("BOTTOMRIGHT", seat, "BOTTOMRIGHT", 0, 0); g.dr:SetWidth(1)
  g.db:SetColorTexture(0, 0, 0, 0.55); g.dr:SetColorTexture(0, 0, 0, 0.55)
  g.all = { g.stone, g.glow, g.endL, g.endR, g.gloss, g.spot, g.lt, g.ll, g.db, g.dr }
  r.gem = g
  return g
end

function NS.GemHide(r)
  local g = r.gem
  if not g or not r.gemOn then return end
  r.gemOn = false
  local i
  for i = 1, #g.all do g.all[i]:Hide() end
  g.sheen:Hide(); g.sheenOn = false
  Activate(r, false)
  if r.fStyle == "gem" then r.fStyle = nil end
end

-- Layout (data update only): colours by rank, sizes; the sheen moves on the
-- shared fire clock (Drive -> GemPaint).
function NS.GemUpdate(r, inten, live)
  local g = r.gem or GemCreate(r)
  local sw, sh = r.seatW or 0, r.seatH or 0
  if sw < 1 then NS.GemHide(r) return end
  local rank = r.rank or 1
  if g.rank ~= rank then
    g.rank = rank
    local cr, cg, cb = GemColor(rank)
    g.stone:SetVertexColor(Mul(cr, cg, cb, 1.12))
    g.glow:SetVertexColor(Mul(cr, cg, cb, 1.5))
    local lr, lg, lb = Mul(cr, cg, cb, 1.8)
    g.lt:SetColorTexture(lr, lg, lb, 0.55); g.ll:SetColorTexture(lr, lg, lb, 0.55)
    g.ofs = ((rank * 61) % 256) / 256
    g.w = nil
  end
  if g.w ~= sw or g.h ~= sh then
    g.w, g.h = sw, sh
    local k = sh / 32
    g.stone:SetTexCoord(g.ofs, g.ofs + sw / (256 * k), 0, 1)
    local e = math.min(sw * 0.45, sh * 1.2)
    g.endL:SetWidth(e); g.endR:SetWidth(e)
    g.spot:ClearAllPoints()
    g.spot:SetSize(math.max(2, math.min(sh * 1.4, sw * 0.16)), math.max(1, sh * 0.3))
    g.spot:SetPoint("CENTER", r.seat, "TOPLEFT", math.min(sw * 0.1, sh) + 2 + math.min(sh * 0.7, sw * 0.08) * 0.5, -sh * 0.16)
    g.sheen:SetWidth(sh * 2.8)
  end
  live = live and inten > 0
  local ga = 0.25 + (live and 0.45 * inten or 0)
  if math.abs((g.ga or -1) - ga) > ALPHA_EPS then g.ga = ga; g.glow:SetAlpha(ga) end
  g.sheenA = live and 0.35 * (0.4 + 0.6 * inten) or 0
  g.live = live and not Reduced()
  if not r.gemOn then
    r.gemOn = true
    local i
    for i = 1, #g.all do g.all[i]:Show() end
  end
  r.fStyle = "gem"
  if g.live then Activate(r, true); GemPaint(r)
  else
    if g.sheenOn then g.sheen:Hide(); g.sheenOn = false end
    Activate(r, false)
  end
end

GemPaint = function(r)
  local g = r.gem
  if not g or not r.gemOn or not g.live then return end
  local sw, sh = g.w or 0, g.h or 0
  local ph = ((clock * 0.35 + ((g.rank or 1) - 1) * 0.13) % 1.6) / 1.6 * 1.25 - 0.1
  local x = -sh * 2 + (sw + sh * 4) * ph
  g.sheen:ClearAllPoints()
  g.sheen:SetPoint("TOP", r.seat, "TOPLEFT", x, 0)
  g.sheen:SetPoint("BOTTOM", r.seat, "BOTTOMLEFT", x, 0)
  g.sheen:SetAlpha(g.sheenA)
  if not g.sheenOn then g.sheen:Show(); g.sheenOn = true end
end
