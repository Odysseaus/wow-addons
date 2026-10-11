-- WoWThreat Fire: the bar IS the fire (PLAN-visuals 1).
-- Fireplace = baked per-theme flame-wall FlipBook sheets (4x8 frames of
-- 256x64, seamless in x and time), tiled at a fixed texel scale and cropped
-- by a clip frame sized to the threat width: width tracks % by cropping,
-- never by stretching. Extra layers: additive glow, white-hot core above 90%,
-- rising sparks and a tapered tip (MaskTexture, else a black tip cap).
local _, NS = ...

local TEX = "Interface\\AddOns\\WoWThreat\\Textures\\"
local MAX_TILES = 3
local MAX_SPARKS = 4
local REF_INNER = 12        -- bar inner px the sheet was baked for
local REF_H = 22            -- display px one frame covers at REF_INNER (bar + overflow)
local REF_W = 256           -- display px one frame covers at REF_INNER
local LOOP = 4.0            -- fireplace loop seconds at speed 1

local STYLES = {
  fireplace = { rows = 8, cols = 4, frames = 32, blend = "BLEND" },
  classic = { rows = 4, cols = 4, frames = 16, blend = "ADD", tex = TEX .. "Fire_Flipbook" },
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

local maskOK = nil
local function MaskSupported(frame)
  if maskOK == nil then maskOK = (frame and frame.CreateMaskTexture) and true or false end
  return maskOK
end

local function After(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end

local function NewFlipBook(tex, st)
  if NS.FlipBookOK == false or not tex.CreateAnimationGroup then return nil end
  local ag, fb
  local ok = pcall(function()
    ag = tex:CreateAnimationGroup()
    fb = ag:CreateAnimation("FlipBook")
    fb:SetFlipBookRows(st.rows)
    fb:SetFlipBookColumns(st.cols)
    fb:SetFlipBookFrames(st.frames)
    fb:SetFlipBookFrameWidth(0)
    fb:SetFlipBookFrameHeight(0)
    fb:SetDuration(LOOP)
    ag:SetLooping("REPEAT")
  end)
  if not ok then NS.FlipBookOK = false return nil end
  return { ag = ag, fb = fb }
end

local function SheetFor(style)
  if style == "classic" then return STYLES.classic.tex end
  return TEX .. "Fire_Fireplace_" .. (NS.ThemeId and NS.ThemeId() or "emberhall")
end

-- Build the fire layers for one row (once; reused through the row pool).
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
    local t = { }
    t.body = clip:CreateTexture(nil, "ARTWORK", nil, 1)
    t.glow = clip:CreateTexture(nil, "ARTWORK", nil, 2)
    t.glow:SetBlendMode("ADD")
    t.body:Hide(); t.glow:Hide()
    r.tiles[j] = t
  end
  r.core = clip:CreateTexture(nil, "ARTWORK", nil, 3)
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
    local s = clip:CreateTexture(nil, "ARTWORK", nil, 4)
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
      sp.ag, sp.mv = ag, mv
    end)
    r.sparks[j] = sp
  end
  -- Tapered tip: a mask fading the last texels of the crop, else a tip cap.
  if MaskSupported(clip) then
    local ok = pcall(function()
      local m = clip:CreateMaskTexture()
      m:SetTexture(TEX .. "TipMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetAllPoints(clip)
      r.tipMask = m
    end)
    if not ok then r.tipMask = nil end
  end
  if not r.tipMask then
    r.tipCap = clip:CreateTexture(nil, "ARTWORK", nil, 5)
    r.tipCap:SetTexture(TEX .. "TipCap")
    r.tipCap:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
    r.tipCap:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    r.tipCap:SetWidth(8)
  end
  r.fireKey = nil
  clip:Hide()
end

local function StopTiles(r)
  local j
  for j = 1, MAX_TILES do
    local t = r.tiles[j]
    if t.fbB and t.on then pcall(t.fbB.ag.Stop, t.fbB.ag) end
    if t.fbG and t.on then pcall(t.fbG.ag.Stop, t.fbG.ag) end
    t.on = false
    t.body:Hide(); t.glow:Hide()
  end
end

local function StopSparks(r)
  local j
  for j = 1, MAX_SPARKS do
    local sp = r.sparks[j]
    if sp.on and sp.ag then pcall(sp.ag.Stop, sp.ag) end
    sp.on = false
    sp.tex:Hide()
  end
end

function NS.FireStop(r)
  if not r.fireClip then return end
  StopTiles(r)
  StopSparks(r)
  if r.coreOn and r.coreAG then pcall(r.coreAG.Stop, r.coreAG) end
  r.coreOn = false
  r.core:Hide()
  r.fireOn = false
  r.fireClip:Hide()
end

-- (Re)apply sheet + animation setup when style/theme/speed change.
local function Restyle(r, style, sheet, speed)
  StopTiles(r)
  local st = STYLES[style]
  local dur = (style == "classic" and 1.0 or LOOP) / speed
  local j
  for j = 1, MAX_TILES do
    local t = r.tiles[j]
    t.body:SetTexture(sheet)
    t.glow:SetTexture(sheet)
    t.body:SetBlendMode(st.blend)
    if r.tipMask then
      if not t.masked then
        pcall(t.body.AddMaskTexture, t.body, r.tipMask)
        pcall(t.glow.AddMaskTexture, t.glow, r.tipMask)
        t.masked = true
      end
    end
    if t.style ~= style then
      t.fbB = NewFlipBook(t.body, st)
      t.fbG = NewFlipBook(t.glow, st)
      t.style = style
      t.frame, t.acc = (j - 1) * 11 % st.frames, 0
    end
    if t.fbB then pcall(t.fbB.fb.SetDuration, t.fbB.fb, dur) end
    if t.fbG then pcall(t.fbG.fb.SetDuration, t.fbG.fb, dur) end
    if not t.fbB then
      local c = t.frame % st.cols
      local rr = math.floor(t.frame / st.cols)
      t.body:SetTexCoord(c / st.cols, (c + 1) / st.cols, rr / st.rows, (rr + 1) / st.rows)
      t.glow:SetTexCoord(c / st.cols, (c + 1) / st.cols, rr / st.rows, (rr + 1) / st.rows)
    end
  end
  r.fireKey = style .. "|" .. sheet .. "|" .. speed
  r.fireDur = dur
end

local function PlayTile(t, j, dur)
  if t.on then return end
  t.on = true
  t.body:Show()
  if t.fbB then
    -- Phase offset per tile so repeats don't line up (PLAN-visuals 1).
    local delay = (j - 1) * dur * 0.37
    if delay > 0 then
      After(delay, function() if t.on then pcall(t.fbB.ag.Play, t.fbB.ag); if t.glowOn then pcall(t.fbG.ag.Play, t.fbG.ag) end end end)
    else
      pcall(t.fbB.ag.Play, t.fbB.ag)
      if t.glowOn and t.fbG then pcall(t.fbG.ag.Play, t.fbG.ag) end
    end
  end
end

-- pct: 0..1 of the bar; width: eased fill px; barH: bar px; rank: visible index;
-- nrows: visible rows. Returns true when the caller must keep ticking
-- (SetTexCoord fallback only).
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
  local speed = type(db.fireSpeed) == "number" and db.fireSpeed or 1
  if speed < 0.5 then speed = 0.5 elseif speed > 1.5 then speed = 1.5 end
  local sheet = SheetFor(style)
  local key = style .. "|" .. sheet .. "|" .. speed
  if r.fireKey ~= key then Restyle(r, style, sheet, speed) end
  local st = STYLES[style]

  local inner = math.max(2, barH - 2)
  local over = type(db.flameOverflow) == "number" and db.flameOverflow or 10
  local room = math.max(0, (r.rowH or (barH + 14)) - barH - 2)
  if over > room then over = room end
  r.fireClip:SetSize(width, inner + over)
  r.fireClip:Show()
  r.fireOn = true

  -- Fixed texel scale: tiles are cropped, never stretched horizontally.
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
  local alpha = (0.88 + 0.12 * pct) * (0.85 + 0.15 * inten)
  if style == "classic" then alpha = 0.25 + 0.75 * pct * inten end
  if alpha > 1 then alpha = 1 end
  local cr, cg, cb = 1, 1, 1
  if style == "classic" and NS.ThemeFireColor then cr, cg, cb = NS.ThemeFireColor() end
  local glowOn = not reduced and (nrows or 1) <= 20 and style == "fireplace"
  local tick = false
  local j
  for j = 1, MAX_TILES do
    local t = r.tiles[j]
    if j <= need then
      t.body:ClearAllPoints()
      t.body:SetPoint("BOTTOMLEFT", r.fireClip, "BOTTOMLEFT", (j - 1) * tileW, 0)
      t.body:SetSize(tileW, texH)
      t.body:SetAlpha(alpha)
      t.body:SetVertexColor(cr, cg, cb, 1)
      t.glowOn = glowOn
      if glowOn then
        t.glow:ClearAllPoints()
        t.glow:SetAllPoints(t.body)
        t.glow:SetAlpha(0.14)
        t.glow:Show()
        if t.on and t.fbG and not t.glowPlaying then pcall(t.fbG.ag.Play, t.fbG.ag) end
        t.glowPlaying = true
      else
        if t.fbG and t.glowPlaying then pcall(t.fbG.ag.Stop, t.fbG.ag) end
        t.glowPlaying = false
        t.glow:Hide()
      end
      PlayTile(t, j, r.fireDur)
      if not t.fbB then
        -- SetTexCoord fallback.
        t.acc = (t.acc or 0) + (dt or 0)
        local stepT = r.fireDur / st.frames
        if t.acc >= stepT then
          t.frame = (t.frame + math.floor(t.acc / stepT)) % st.frames
          t.acc = t.acc % stepT
          local c = t.frame % st.cols
          local rr = math.floor(t.frame / st.cols)
          t.body:SetTexCoord(c / st.cols, (c + 1) / st.cols, rr / st.rows, (rr + 1) / st.rows)
          t.glow:SetTexCoord(c / st.cols, (c + 1) / st.cols, rr / st.rows, (rr + 1) / st.rows)
        end
        tick = true
      end
    elseif t.on then
      if t.fbB then pcall(t.fbB.ag.Stop, t.fbB.ag) end
      if t.fbG then pcall(t.fbG.ag.Stop, t.fbG.ag) end
      t.on, t.glowPlaying = false, false
      t.body:Hide(); t.glow:Hide()
    end
  end

  -- Sparks: top 10 ranks only when >20 rows; none in reduced/classic.
  local nsp = 0
  if not reduced and style == "fireplace" and ((nrows or 1) <= 20 or (rank or 1) <= 10) then
    nsp = math.ceil(MAX_SPARKS * pct)
  end
  for j = 1, MAX_SPARKS do
    local sp = r.sparks[j]
    if j <= nsp and sp.ag then
      sp.tex:ClearAllPoints()
      sp.tex:SetPoint("BOTTOMLEFT", r.fireClip, "BOTTOMLEFT", sp.frac * (width - 4), inner * 0.45)
      if not sp.on then sp.on = true; sp.tex:Show(); pcall(sp.ag.Play, sp.ag) end
    elseif sp.on then
      pcall(sp.ag.Stop, sp.ag); sp.on = false; sp.tex:Hide()
    end
  end

  -- White-hot core above 90%.
  if pct > 0.9 and not reduced then
    r.core:SetHeight(inner * 0.7)
    r.core:SetAlpha(math.min(1, (pct - 0.9) / 0.1) * 0.36)
    if not r.coreOn then
      r.core:Show()
      if r.coreAG then pcall(r.coreAG.Play, r.coreAG) end
      r.coreOn = true
    end
  elseif r.coreOn then
    if r.coreAG then pcall(r.coreAG.Stop, r.coreAG) end
    r.core:Hide(); r.coreOn = false
  end
  if r.tipCap then r.tipCap:SetWidth(math.min(8, width * 0.25)) end
  return tick
end
