local _, NS = ...

local ROW_N = 10
local POLL = 0.2
local LERP_T = 0.25
local SCALE_MIN, SCALE_MAX = 0.6, 1.6
local TEX_SIZE = 1024
-- ThreatFrame.tga is one 1024 square. The continuous gold border occupies
-- the top-left 617x701; a single texcoord range covers that whole border.
local ART_X, ART_Y = 0, 0
local ART_W, ART_H = 617, 701
local HEADER = 26
local FRAME_W = 320
local FRAME_H = math.floor(FRAME_W * ART_H / ART_W + 0.5)
local IN_L, IN_T, IN_R, IN_B = 0.11, 0.16, 0.11, 0.14
local TITLE_H = 18
-- Clear pixels between the title glyphs and the dial ring.
local TITLE_GAP = 6

local main, content
local barsLayer, platesLayer, dialLayer
local banner, titleFS, modeBtn, plusBtn, minusBtn
local barByKey, barFree = {}, {}
local plateByKey, plateFree = {}, {}
local markByKey, markFree = {}, {}
local barSmooth, plateSmooth, markSmooth = {}, {}, {}
local dial = {}
local pollAcc = 0
local dialVis = { angle = 180, target = 180, ready = false }
-- Arc midline radius / half the dial texture. Percent anchor is an
-- offset from texture center as a fraction of the texture (y down).
-- Uniform 768 -> 1024 resample, so the fraction is unchanged.
local ARC_FRAC = 0.658
local NEEDLE_TEX_W, NEEDLE_TEX_H = 128, 512
local PCT_OX, PCT_OY = 0.0072, 0.1379
local built = false

local RefreshData

local function Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function Lerp(a, b, elapsed)
  local t = elapsed / LERP_T
  if t > 1 then t = 1 end
  if t < 0 then t = 0 end
  return a + (b - a) * t
end

function NS.SetMode(name)
  if not NS.db then return end
  name = string.lower(tostring(name or ''))
  if name == 'bar' then name = 'bars' end
  if name == 'plate' then name = 'plates' end
  if name ~= 'bars' and name ~= 'plates' and name ~= 'dial' then return end
  NS.db.mode = name
  if NS.ApplyMode then NS.ApplyMode() end
  if NS.RefreshChrome then NS.RefreshChrome() end
end

local function ModeWord()
  local m = (NS.db and NS.db.mode) or 'bars'
  m = string.lower(tostring(m))
  if m == 'plates' then return 'Plates' end
  if m == 'dial' then return 'Dial' end
  return 'Bars'
end

local function ClassRGB(class)
  if NS.ClassColor then
    local a, b, c = NS.ClassColor(class)
    if type(a) == 'table' then
      return a.r or a[1] or 1, a.g or a[2] or 1, a.b or a[3] or 1
    end
    if type(a) == 'number' then
      return a, b or 1, c or 1
    end
  end
  return 0.85, 0.85, 0.85
end

local function Heat(rank, n)
  local t = 0
  if n > 1 then t = (rank - 1) / (n - 1) end
  if t < 0 then t = 0 end
  if t > 1 then t = 1 end
  local r, g, b
  if t < 0.5 then
    local u = t / 0.5
    r = 1
    g = 0.12 + (0.50 - 0.12) * u
    b = 0.05 * (1 - u)
  else
    local u = (t - 0.5) / 0.5
    r = 1
    g = 0.50 + (0.86 - 0.50) * u
    b = 0
  end
  return r, g, b
end

local function PctNumber(e)
  local p = tonumber(e.pct or e.percent or e.threatPct or e.scaled or e.value) or 0
  return p
end

local function DisplayName(e)
  local n = e.name or e.unitName or 'Unknown'
  if NS.ShortName then
    local s = NS.ShortName(n)
    if s and s ~= '' then n = s end
  end
  return n
end

local function EntryKey(e, i)
  if e.guid and e.guid ~= '' then return e.guid end
  if e.GUID and e.GUID ~= '' then return e.GUID end
  if e.name and e.name ~= '' then return 'n:' .. e.name end
  return 'i:' .. tostring(i)
end

local function BuildList()
  local raw = nil
  if NS.CollectThreat then raw = NS.CollectThreat() end
  local src = raw
  if type(src) ~= 'table' then return {} end
  if type(src.rows) == 'table' then src = src.rows
  elseif type(src.entries) == 'table' then src = src.entries
  elseif type(src.list) == 'table' then src = src.list end
  local out = {}
  if type(src) == 'table' and src[1] ~= nil then
    for i = 1, #src do
      local e = src[i]
      if type(e) == 'table' then
        out[#out + 1] = {
          name = e.name or e.unitName or 'Unknown',
          class = e.class or e.classFile or e.classToken,
          guid = e.guid or e.GUID,
          pct = PctNumber(e),
          isPlayer = e.isPlayer or e.isMe or e.player,
          unit = e.unit,
        }
      end
    end
  elseif type(src) == 'table' then
    for k, e in pairs(src) do
      if type(e) == 'table' and k ~= 'rows' and k ~= 'entries' and k ~= 'list' then
        out[#out + 1] = {
          name = e.name or e.unitName or tostring(k),
          class = e.class or e.classFile or e.classToken,
          guid = e.guid or e.GUID or (type(k) == 'string' and k or nil),
          pct = PctNumber(e),
          isPlayer = e.isPlayer or e.isMe or e.player,
          unit = e.unit,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.pct == b.pct then
      return (a.name or '') < (b.name or '')
    end
    return a.pct > b.pct
  end)
  return out
end

local function IsPlayerEntry(e, pname, pguid)
  if e.isPlayer then return true end
  if e.unit == 'player' then return true end
  if pguid and e.guid and e.guid == pguid then return true end
  if pname and e.name and e.name == pname then return true end
  return false
end

local function RowPitch()
  local ch = content and content:GetHeight() or 0
  if not ch or ch < 40 then ch = FRAME_H * 0.70 end
  local gap = 2
  local rh = (ch - gap * (ROW_N - 1)) / ROW_N
  if rh < 12 then rh = 12 end
  return rh, gap
end

local function ReleaseMap(map, free, smooth, seen)
  local dead = {}
  for key in pairs(map) do
    if not seen[key] then dead[#dead + 1] = key end
  end
  for i = 1, #dead do
    local key = dead[i]
    local row = map[key]
    map[key] = nil
    smooth[key] = nil
    row.key = nil
    row:Hide()
    free[#free + 1] = row
  end
end

local function Acquire(map, free, key)
  local row = map[key]
  if row then return row end
  row = table.remove(free)
  if not row then return nil end
  map[key] = row
  row.key = key
  return row
end

local function ApplyIcon(tex, class)
  if NS.ApplyClassIcon then
    NS.ApplyClassIcon(tex, class)
  else
    tex:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
  end
end

local function MakeMiniButton(parent, name, label, w)
  local b = CreateFrame('Button', name, parent, 'UIPanelButtonTemplate')
  b:SetSize(w or 22, 22)
  b:SetText(label)
  return b
end

local function CreateBarRow(parent)
  local row = CreateFrame('Frame', nil, parent)
  row:SetHeight(16)
  local icon = row:CreateTexture(nil, 'ARTWORK')
  icon:SetSize(14, 14)
  icon:SetPoint('LEFT', row, 'LEFT', 0, 0)
  icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
  local nameFS = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  nameFS:SetPoint('LEFT', icon, 'RIGHT', 2, 0)
  nameFS:SetWidth(64)
  nameFS:SetJustifyH('LEFT')
  nameFS:SetWordWrap(false)
  local pctFS = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  pctFS:SetPoint('RIGHT', row, 'RIGHT', 0, 0)
  pctFS:SetWidth(42)
  pctFS:SetJustifyH('RIGHT')
  pctFS:SetTextColor(1, 0.95, 0.8)
  local bar = CreateFrame('StatusBar', nil, row)
  bar:SetPoint('LEFT', nameFS, 'RIGHT', 3, 0)
  bar:SetPoint('RIGHT', pctFS, 'LEFT', -3, 0)
  bar:SetHeight(11)
  bar:SetStatusBarTexture('Interface\\TargetingFrame\\UI-StatusBar')
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)
  local bg = bar:CreateTexture(nil, 'BACKGROUND')
  bg:SetAllPoints()
  bg:SetTexture('Interface\\Buttons\\WHITE8X8')
  bg:SetVertexColor(0, 0, 0, 0.55)
  local tick = bar:CreateTexture(nil, 'OVERLAY')
  tick:SetTexture('Interface\\Buttons\\WHITE8X8')
  tick:SetVertexColor(1, 1, 1, 1)
  tick:SetWidth(2)
  tick:SetPoint('TOPRIGHT', bar, 'TOPRIGHT', 0, 1)
  tick:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT', 0, -1)
  row.icon = icon
  row.nameFS = nameFS
  row.pctFS = pctFS
  row.bar = bar
  row.tick = tick
  row:Hide()
  return row
end

local function CreatePlate(parent)
  local row = CreateFrame('Frame', nil, parent)
  row:SetHeight(18)
  local bg = row:CreateTexture(nil, 'BACKGROUND')
  bg:SetAllPoints()
  bg:SetTexture('Interface\\Buttons\\WHITE8X8')
  bg:SetVertexColor(0.4, 0.15, 0.05, 0.92)
  local edge = row:CreateTexture(nil, 'BORDER')
  edge:SetPoint('TOPLEFT', -1, 1)
  edge:SetPoint('BOTTOMRIGHT', 1, -1)
  edge:SetTexture('Interface\\Buttons\\WHITE8X8')
  edge:SetVertexColor(0.85, 0.68, 0.22, 0.95)
  local inner = row:CreateTexture(nil, 'ARTWORK')
  inner:SetPoint('TOPLEFT', 1, -1)
  inner:SetPoint('BOTTOMRIGHT', -1, 1)
  inner:SetTexture('Interface\\Buttons\\WHITE8X8')
  local glow = row:CreateTexture(nil, 'OVERLAY')
  glow:SetPoint('TOPLEFT', -6, 6)
  glow:SetPoint('BOTTOMRIGHT', 6, -6)
  glow:SetTexture('Interface\\Buttons\\UI-ActionButton-Border')
  glow:SetBlendMode('ADD')
  glow:SetAlpha(0.85)
  local nameFS = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  nameFS:SetPoint('CENTER', row, 'CENTER', 0, 0)
  nameFS:SetJustifyH('CENTER')
  nameFS:SetWordWrap(false)
  row.bg = inner
  row.glow = glow
  row.nameFS = nameFS
  row:Hide()
  return row
end

local function CreateMarker(parent)
  local m = CreateFrame('Frame', nil, parent)
  m:SetSize(90, 14)
  local icon = m:CreateTexture(nil, 'OVERLAY')
  icon:SetSize(14, 14)
  icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
  local nameFS = m:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  nameFS:SetWordWrap(false)
  nameFS:SetWidth(70)
  m.icon = icon
  m.nameFS = nameFS
  m:Hide()
  return m
end

local function PlaceMarker(marker, angle, radius)
  local rad = math.rad(angle)
  local c = math.cos(rad)
  local s = math.sin(rad)
  marker:ClearAllPoints()
  marker:SetPoint('CENTER', dial.hub, 'CENTER', c * radius, s * radius)
  marker.icon:ClearAllPoints()
  marker.nameFS:ClearAllPoints()
  marker.icon:SetPoint('CENTER', marker, 'CENTER', 0, 0)
  -- Name sits just inside the arc, toward the hub, so the crest does not clip it.
  if c > 0.45 then
    marker.nameFS:SetPoint('RIGHT', marker.icon, 'LEFT', -2, 0)
    marker.nameFS:SetJustifyH('RIGHT')
  elseif c < -0.45 then
    marker.nameFS:SetPoint('LEFT', marker.icon, 'RIGHT', 2, 0)
    marker.nameFS:SetJustifyH('LEFT')
  else
    marker.nameFS:SetPoint('TOP', marker.icon, 'BOTTOM', 0, -1)
    marker.nameFS:SetJustifyH('CENTER')
  end
end

local function UpdateNeedle(angle, length)
  if dial.needle and dial.needle.SetRotation then
    local n = #dial.segs
    for i = 1, n do
      dial.segs[i]:Hide()
    end
    local h = length * 2
    if h < 2 then h = 2 end
    dial.needle:Show()
    dial.needle:SetVertexColor(1, 1, 1, 1)
    dial.needle:ClearAllPoints()
    dial.needle:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
    -- Blade is only the top half of a 128x512 texture, so width follows that aspect.
    dial.needle:SetSize(h * (NEEDLE_TEX_W / NEEDLE_TEX_H), h)
    dial.needle:SetRotation(math.rad(angle - 90))
    return
  end
  if dial.needle then dial.needle:Hide() end
  local n = #dial.segs
  for i = 1, n do
    local dist = length * (i / n)
    local rad = math.rad(angle)
    local x = math.cos(rad) * dist
    local y = math.sin(rad) * dist
    local s = dial.segs[i]
    s:ClearAllPoints()
    s:SetPoint('CENTER', dial.hub, 'CENTER', x, y)
    local w = (i == n) and 7 or 4
    s:SetSize(w, w)
    s:Show()
  end
end

local function FillBar(row, e)
  local r, g, b = ClassRGB(e.class)
  ApplyIcon(row.icon, e.class)
  row.nameFS:SetText(DisplayName(e))
  row.nameFS:SetTextColor(r, g, b)
  row.bar:SetStatusBarColor(r, g, b, 1)
  local pct = e.pct or 0
  local v = pct
  if v < 0 then v = 0 end
  if v > 100 then v = 100 end
  row.bar:SetValue(v)
  row.pctFS:SetText(string.format('%d%%', math.floor(pct + 0.5)))
end

local function FillPlate(row, e, rank, n)
  local hr, hg, hb = Heat(rank, n)
  row.bg:SetVertexColor(hr * 0.55, hg * 0.45, hb * 0.35, 0.95)
  row.glow:SetVertexColor(hr, hg, hb, 0.9)
  row.nameFS:SetText(DisplayName(e))
  row.nameFS:SetTextColor(1, 0.95, 0.85)
end

local function FillMarker(row, e)
  local r, g, b = ClassRGB(e.class)
  ApplyIcon(row.icon, e.class)
  row.nameFS:SetText(DisplayName(e))
  row.nameFS:SetTextColor(r, g, b)
end

local function AngleFor(e, rank, n)
  local pct = e.pct or 0
  local t
  if pct > 0 then
    t = pct / 100
  elseif n > 1 then
    t = 1 - ((rank - 1) / (n - 1))
  else
    t = 1
  end
  t = Clamp(t, 0, 1)
  return 180 * (1 - t)
end

local function SyncRows(list)
  local rh, gap = RowPitch()
  local seenB, seenP, seenM = {}, {}, {}
  local n = #list
  if n > ROW_N then n = ROW_N end
  for i = 1, n do
    local e = list[i]
    local key = EntryKey(e, i)
    local y = -(TITLE_H + (i - 1) * (rh + gap))
    seenB[key] = true
    seenP[key] = true
    seenM[key] = true
    local bar = Acquire(barByKey, barFree, key)
    if bar then
      bar:SetHeight(rh)
      FillBar(bar, e)
      bar.targetY = y
      if not barSmooth[key] then barSmooth[key] = { y = y } end
      bar:Show()
    end
    local plate = Acquire(plateByKey, plateFree, key)
    if plate then
      plate:SetHeight(rh)
      FillPlate(plate, e, i, n)
      plate.targetY = y
      if not plateSmooth[key] then plateSmooth[key] = { y = y } end
      plate:Show()
    end
    local mk = Acquire(markByKey, markFree, key)
    if mk then
      FillMarker(mk, e)
      mk.targetAngle = AngleFor(e, i, n)
      if not markSmooth[key] then markSmooth[key] = { angle = mk.targetAngle } end
      mk:Show()
    end
  end
  ReleaseMap(barByKey, barFree, barSmooth, seenB)
  ReleaseMap(plateByKey, plateFree, plateSmooth, seenP)
  ReleaseMap(markByKey, markFree, markSmooth, seenM)
end

local function PlayerPct(list)
  local pname = UnitName and UnitName('player') or nil
  local pguid = UnitGUID and UnitGUID('player') or nil
  for i = 1, #list do
    if IsPlayerEntry(list[i], pname, pguid) then
      return list[i].pct or 0
    end
  end
  return 0
end

local function DialRadius()
  local cw = content:GetWidth() or 0
  local ch = content:GetHeight() or 0
  if not cw or cw < 40 then cw = 160 end
  if not ch or ch < 40 then ch = 160 end
  -- Face sits in the area under the title, not across the whole content.
  local availH = ch - TITLE_H - TITLE_GAP
  if availH < 40 then availH = 40 end
  local sz = cw
  if availH < sz then sz = availH end
  local face = sz * 0.98
  dial.face:SetSize(face, face)
  -- Hub is the center of that lower area. Scale changes content size, so
  -- this is recomputed here rather than baked at build time.
  local hubY = -(TITLE_H + TITLE_GAP) / 2
  dial.hub:ClearAllPoints()
  dial.hub:SetPoint('CENTER', content, 'CENTER', 0, hubY)
  local radius = face * 0.5 * ARC_FRAC
  local px = PCT_OX * face
  local py = -PCT_OY * face
  if dial.pct and dial.pctSign then
    local nw = dial.pct:GetStringWidth() or 0
    local sw = dial.pctSign:GetStringWidth() or 0
    if not nw or nw < 1 then nw = 36 end
    if not sw or sw < 1 then sw = 18 end
    local left = px - (nw + sw) / 2
    dial.pct:ClearAllPoints()
    dial.pct:SetPoint('LEFT', dial.hub, 'CENTER', left, py)
    dial.pctSign:ClearAllPoints()
    dial.pctSign:SetPoint('LEFT', dial.pct, 'RIGHT', 0, 0)
  elseif dial.pct then
    dial.pct:ClearAllPoints()
    dial.pct:SetPoint('CENTER', dial.hub, 'CENTER', px, py)
  end
  return radius
end

RefreshData = function()
  if not built then return end
  local list = BuildList()
  SyncRows(list)
  local pp = PlayerPct(list)
  local t = Clamp(pp / 100, 0, 1)
  dialVis.target = 180 * (1 - t)
  if not dialVis.ready then
    dialVis.angle = dialVis.target
    dialVis.ready = true
  end
  local shown = math.floor(pp + 0.5)
  if dial.pct then
    if dial.pctSign then
      dial.pct:SetText(tostring(shown))
      dial.pctSign:SetText('%')
    else
      dial.pct:SetText(string.format('%d%%', shown))
    end
  end
  local radius = DialRadius()
  dial.radius = radius
  local mode = string.lower(tostring((NS.db and NS.db.mode) or 'bars'))
  if mode == 'dial' and dialLayer and dialLayer:IsShown() then
    UpdateNeedle(dialVis.angle, radius)
  elseif dial.needle then
    dial.needle:Hide()
  end
end

local function Animate(elapsed)
  if barsLayer:IsShown() then
    for key, row in pairs(barByKey) do
      local st = barSmooth[key]
      if st and row.targetY then
        st.y = Lerp(st.y, row.targetY, elapsed)
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', content, 'TOPLEFT', 0, st.y)
        row:SetPoint('TOPRIGHT', content, 'TOPRIGHT', 0, st.y)
      end
    end
  end
  if platesLayer:IsShown() then
    for key, row in pairs(plateByKey) do
      local st = plateSmooth[key]
      if st and row.targetY then
        st.y = Lerp(st.y, row.targetY, elapsed)
        row:ClearAllPoints()
        row:SetPoint('TOPLEFT', content, 'TOPLEFT', 0, st.y)
        row:SetPoint('TOPRIGHT', content, 'TOPRIGHT', 0, st.y)
      end
    end
  end
  if dialLayer:IsShown() then
    local radius = dial.radius or 60
    dialVis.angle = Lerp(dialVis.angle, dialVis.target, elapsed)
    UpdateNeedle(dialVis.angle, radius)
    for key, row in pairs(markByKey) do
      local st = markSmooth[key]
      if st and row.targetAngle then
        st.angle = Lerp(st.angle, row.targetAngle, elapsed)
        PlaceMarker(row, st.angle, radius)
      end
    end
  end
end

local function AdjustScale(delta)
  if not NS.db or not main then return end
  local s = Clamp((NS.db.scale or 1) + delta, SCALE_MIN, SCALE_MAX)
  NS.db.scale = s
  main:SetScale(s)
end

local function SavePosition()
  if not main or not NS.db then return end
  local point, _, relativePoint, xOfs, yOfs = main:GetPoint(1)
  NS.db.point = point or 'CENTER'
  NS.db.relativePoint = relativePoint or 'CENTER'
  NS.db.xOfs = xOfs or 0
  NS.db.yOfs = yOfs or 0
end

function NS.ApplyLock()
  if not main then return end
  local locked = NS.db and (NS.db.locked or NS.db.lock) and true or false
  if locked then
    main:SetMovable(false)
    main:RegisterForDrag()
    if plusBtn then plusBtn:Hide() end
    if minusBtn then minusBtn:Hide() end
  else
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag('LeftButton')
    if plusBtn then plusBtn:Show() end
    if minusBtn then minusBtn:Show() end
  end
end

function NS.ApplyLayout()
  if not main or not NS.db then return end
  local point = NS.db.point or 'CENTER'
  local rel = NS.db.relativePoint or 'CENTER'
  local x = NS.db.xOfs or 0
  local y = NS.db.yOfs or 0
  main:ClearAllPoints()
  main:SetPoint(point, UIParent, rel, x, y)
  local s = Clamp(NS.db.scale or 1, SCALE_MIN, SCALE_MAX)
  NS.db.scale = s
  main:SetScale(s)
  NS.ApplyLock()
end

function NS.ApplyMode()
  if not barsLayer then return end
  local m = string.lower(tostring((NS.db and NS.db.mode) or 'bars'))
  if m ~= 'bars' and m ~= 'plates' and m ~= 'dial' then m = 'bars' end
  if NS.db then NS.db.mode = m end
  if m == 'bars' then barsLayer:Show() else barsLayer:Hide() end
  if m == 'plates' then platesLayer:Show() else platesLayer:Hide() end
  if m == 'dial' then
    dialLayer:Show()
    if dial.face then dial.face:Show() end
    if dial.pct then dial.pct:Show() end
    if dial.pctSign then dial.pctSign:Show() end
  else
    dialLayer:Hide()
    if dial.face then dial.face:Hide() end
    if dial.needle then dial.needle:Hide() end
    if dial.pct then dial.pct:Hide() end
    if dial.pctSign then dial.pctSign:Hide() end
    if dial.segs then
      local i
      for i = 1, #dial.segs do
        dial.segs[i]:Hide()
      end
    end
  end
  if modeBtn then modeBtn:SetText(ModeWord()) end
  RefreshData()
end

function NS.RefreshChrome()
  if not main then return end
  if banner then
    if NS.apiMissing then
      banner:SetText('Threat API not available on this client')
      banner:Show()
    else
      banner:Hide()
    end
  end
  if modeBtn then modeBtn:SetText(ModeWord()) end
  NS.ApplyLock()
end

local function Build()
  if built then return end
  built = true

  main = CreateFrame('Frame', 'WoWThreatFrame', UIParent)
  main:SetFrameStrata('MEDIUM')
  main:SetClampedToScreen(true)
  main:EnableMouse(true)
  main:SetMovable(true)
  main:RegisterForDrag('LeftButton')
  main:SetScript('OnDragStart', function(self)
    if NS.db and (NS.db.locked or NS.db.lock) then return end
    self:StartMoving()
  end)
  main:SetScript('OnDragStop', function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)

  main:SetSize(FRAME_W, FRAME_H + HEADER)

  local art = main:CreateTexture(nil, 'BACKGROUND')
  art:SetPoint('TOPLEFT', main, 'TOPLEFT', 0, -HEADER)
  art:SetSize(FRAME_W, FRAME_H)
  art:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\ThreatFrame')
  art:SetTexCoord(ART_X / TEX_SIZE, (ART_X + ART_W) / TEX_SIZE, ART_Y / TEX_SIZE, (ART_Y + ART_H) / TEX_SIZE)

  titleFS = main:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  titleFS:SetText('THREAT METER')
  titleFS:SetTextColor(1, 0.82, 0)

  modeBtn = MakeMiniButton(main, 'WoWThreatModeButton', 'Bars', 92)
  modeBtn:SetPoint('TOPLEFT', art, 'TOPLEFT', 0, HEADER)
  modeBtn:SetScript('OnClick', function()
    if NS.CycleMode then NS.CycleMode() end
    if NS.ApplyMode then NS.ApplyMode() end
    if NS.RefreshChrome then NS.RefreshChrome() end
  end)

  plusBtn = MakeMiniButton(main, 'WoWThreatPlusButton', '+', 24)
  plusBtn:SetPoint('TOPRIGHT', art, 'TOPRIGHT', 0, HEADER)
  plusBtn:SetScript('OnClick', function() AdjustScale(0.1) end)
  minusBtn = MakeMiniButton(main, 'WoWThreatMinusButton', '-', 24)
  minusBtn:SetPoint('RIGHT', plusBtn, 'LEFT', -4, 0)
  minusBtn:SetScript('OnClick', function() AdjustScale(-0.1) end)
  -- Above the dial, so the face cannot take the click.
  modeBtn:SetFrameStrata('HIGH')
  plusBtn:SetFrameStrata('HIGH')
  minusBtn:SetFrameStrata('HIGH')
  modeBtn:SetFrameLevel(80)
  plusBtn:SetFrameLevel(80)
  minusBtn:SetFrameLevel(80)

  content = CreateFrame('Frame', nil, main)
  content:SetPoint('TOPLEFT', art, 'TOPLEFT', FRAME_W * IN_L, -FRAME_H * IN_T)
  content:SetPoint('BOTTOMRIGHT', art, 'BOTTOMRIGHT', -FRAME_W * IN_R, FRAME_H * IN_B)
  content:SetClipsChildren(true)
  titleFS:SetPoint('TOP', content, 'TOP', 0, 0)

  banner = content:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  banner:SetPoint('TOP', content, 'TOP', 0, 0)
  banner:SetWidth(FRAME_W * 0.76)
  banner:SetJustifyH('CENTER')
  banner:SetTextColor(1, 0.25, 0.2)
  banner:SetWordWrap(true)
  banner:Hide()

  barsLayer = CreateFrame('Frame', nil, content)
  barsLayer:SetAllPoints()
  platesLayer = CreateFrame('Frame', nil, content)
  platesLayer:SetAllPoints()
  dialLayer = CreateFrame('Frame', nil, content)
  dialLayer:SetAllPoints()

  for i = 1, ROW_N do
    barFree[i] = CreateBarRow(barsLayer)
    plateFree[i] = CreatePlate(platesLayer)
    markFree[i] = CreateMarker(dialLayer)
  end

  dial.hub = CreateFrame('Frame', nil, dialLayer)
  dial.hub:SetSize(2, 2)
  dial.hub:SetPoint('CENTER', content, 'CENTER', 0, -(TITLE_H + TITLE_GAP) / 2)

  dial.face = dialLayer:CreateTexture(nil, 'BACKGROUND')
  dial.face:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
  dial.face:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\ThreatDial')
  dial.face:SetSize(150, 150)

  local read = CreateFrame('Frame', nil, dialLayer)
  read:SetAllPoints()
  read:SetFrameLevel((dialLayer:GetFrameLevel() or 1) + 6)
  dial.pct = read:CreateFontString(nil, 'OVERLAY')
  dial.pct:SetFont('Fonts\\FRIZQT__.TTF', 32, '')
  dial.pct:SetTextColor(0.96, 0.91, 0.78, 1)
  dial.pct:SetText('0')
  dial.pctSign = read:CreateFontString(nil, 'OVERLAY')
  dial.pctSign:SetFont('Fonts\\FRIZQT__.TTF', 32, '')
  dial.pctSign:SetTextColor(0.86, 0.16, 0.12, 1)
  dial.pctSign:SetText('%')

  dial.needle = dialLayer:CreateTexture(nil, 'OVERLAY')
  dial.needle:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\ThreatNeedle')
  dial.needle:Hide()

  dial.segs = {}
  for i = 1, 10 do
    local s = dialLayer:CreateTexture(nil, 'OVERLAY')
    s:SetTexture('Interface\\Buttons\\WHITE8X8')
    s:SetVertexColor(1, 0.96, 0.82, 1)
    s:SetSize(4, 4)
    s:Hide()
    dial.segs[i] = s
  end

  main:SetScript('OnUpdate', function(_, elapsed)
    if not elapsed then elapsed = 0 end
    pollAcc = pollAcc + elapsed
    if pollAcc >= POLL then
      pollAcc = 0
      RefreshData()
    end
    Animate(elapsed)
  end)

  NS.ApplyLayout()
  NS.ApplyMode()
  NS.RefreshChrome()
end

local prevReady = NS.OnDBReady
function NS.OnDBReady(...)
  if prevReady and prevReady ~= NS.OnDBReady then
    prevReady(...)
  end
  if not NS.db then return end
  if NS.db.scale == nil then NS.db.scale = 1 end
  if NS.db.mode == nil or NS.db.mode == '' then NS.db.mode = 'bars' end
  if NS.db.point == nil then NS.db.point = 'CENTER' end
  if NS.db.relativePoint == nil then NS.db.relativePoint = 'CENTER' end
  if NS.db.xOfs == nil then NS.db.xOfs = 0 end
  if NS.db.yOfs == nil then NS.db.yOfs = 0 end
  Build()
  NS.ApplyLayout()
  NS.ApplyMode()
  NS.RefreshChrome()
end

if NS.db then
  NS.OnDBReady()
end
