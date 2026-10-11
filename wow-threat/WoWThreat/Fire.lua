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

local function Style()
  local db = DB()
  if db.showFire == false then return "off" end
  local s = db.fireStyle
  if s == "classic" or s == "off" then return s end
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
  clock = clock + (elapsed or 0) * Speed()
  local r
  for r in pairs(active) do PaintRow(r) end
end

local function Activate(r, on)
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
  return TEX .. "Fire_Fireplace_" .. (NS.ThemeId and NS.ThemeId() or "emberhall")
end

function NS.FireCreate(r)
  local clip = CreateFrame("Frame", nil, r.bar)
  clip:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", 1, 1)
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
  if style == "off" or inten <= 0 or width < 2 or not r:IsShown() then
    if r.fireOn or r.fireClip:IsShown() then NS.FireStop(r) end
    return false
  end
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  local reduced = Reduced()
  local sheet = SheetFor(style)
  if r.fireKey ~= style .. "|" .. sheet then Restyle(r, style, sheet) end
  r.fStyle = style

  local inner = math.max(2, barH - 2)
  local over = type(db.flameOverflow) == "number" and db.flameOverflow or 10
  local room = math.max(0, (r.rowH or (barH + 14)) - barH - 2)
  if over > room then over = room end
  r.fireClip:SetSize(width, inner + over)
  if not r.fireOn then r.fireClip:Show(); r.fireOn = true end

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
