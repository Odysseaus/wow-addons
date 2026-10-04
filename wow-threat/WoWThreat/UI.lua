local _, NS = ...

local ROW_N = 10
local POLL = 0.2
local LERP_T = 0.25
local SCALE_MIN, SCALE_MAX = 0.6, 1.6
local ART_W, ART_H = 859, 722
local TEX_SIZE = 1024
local HEADER = 26
local FRAME_W = 340
local FRAME_H = math.floor(FRAME_W * ART_H / ART_W + 0.5)
local IN_L, IN_T, IN_R, IN_B = 0.24, 0.20, 0.22, 0.16
local TITLE_H = 18

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
  local dot = m:CreateTexture(nil, 'OVERLAY')
  dot:SetSize(8, 8)
  dot:SetTexture('Interface\\Buttons\\WHITE8X8')
  local icon = m:CreateTexture(nil, 'OVERLAY')
  icon:SetSize(12, 12)
  icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
  local nameFS = m:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  nameFS:SetWordWrap(false)
  nameFS:SetWidth(70)
  m.dot = dot
  m.icon = icon
  m.nameFS = nameFS
  m:Hide()
  return m
end

local function PlaceMarker(marker, angle, radius)
  local rad = math.rad(angle)
  local x = math.cos(rad) * radius
  local y = math.sin(rad) * radius
  marker:ClearAllPoints()
  marker:SetPoint('CENTER', dial.hub, 'CENTER', x, y)
  marker.dot:ClearAllPoints()
  marker.icon:ClearAllPoints()
  marker.nameFS:ClearAllPoints()
  marker.dot:SetPoint('CENTER', marker, 'CENTER', 0, 0)
  if x >= 0 then
    marker.icon:SetPoint('LEFT', marker.dot, 'RIGHT', 1, 0)
    marker.nameFS:SetPoint('LEFT', marker.icon, 'RIGHT', 1, 0)
    marker.nameFS:SetJustifyH('LEFT')
  else
    marker.icon:SetPoint('RIGHT', marker.dot, 'LEFT', -1, 0)
    marker.nameFS:SetPoint('RIGHT', marker.icon, 'LEFT', -1, 0)
    marker.nameFS:SetJustifyH('RIGHT')
  end
end

local function UpdateNeedle(angle, length)
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
  if dial.needle and dial.needle.SetRotation then
    dial.needle:Show()
    dial.needle:ClearAllPoints()
    dial.needle:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
    dial.needle:SetSize(3, length * 2)
    dial.needle:SetRotation(math.rad(angle - 90))
  elseif dial.needle then
    dial.needle:Hide()
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
  row.dot:SetVertexColor(r, g, b, 1)
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
  local sz = cw
  if ch < sz then sz = ch end
  if sz < 40 then sz = 160 end
  local face = sz * 0.72
  dial.face:SetSize(face, face)
  if dial.border then
    dial.border:SetSize(face + 28, face + 28)
  end
  return face * 0.40
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
  if dial.pct then
    dial.pct:SetText(string.format('%d%%', math.floor(pp + 0.5)))
  end
  local radius = DialRadius()
  dial.radius = radius
  UpdateNeedle(dialVis.angle, radius)
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
        PlaceMarker(row, st.angle, radius + 8)
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
  if m == 'dial' then dialLayer:Show() else dialLayer:Hide() end
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
  art:SetTexCoord(0, ART_W / TEX_SIZE, 0, ART_H / TEX_SIZE)

  titleFS = main:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
  titleFS:SetText('THREAT METER')
  titleFS:SetTextColor(1, 0.82, 0)

  modeBtn = MakeMiniButton(main, 'WoWThreatModeButton', 'Bars', 72)
  modeBtn:SetPoint('TOPLEFT', main, 'TOPLEFT', 0, 0)
  modeBtn:SetScript('OnClick', function()
    if NS.CycleMode then NS.CycleMode() end
    if NS.ApplyMode then NS.ApplyMode() end
    if NS.RefreshChrome then NS.RefreshChrome() end
  end)

  plusBtn = MakeMiniButton(main, 'WoWThreatPlusButton', '+', 24)
  plusBtn:SetPoint('TOPRIGHT', main, 'TOPRIGHT', 0, 0)
  plusBtn:SetScript('OnClick', function() AdjustScale(0.1) end)
  minusBtn = MakeMiniButton(main, 'WoWThreatMinusButton', '-', 24)
  minusBtn:SetPoint('RIGHT', plusBtn, 'LEFT', -4, 0)
  minusBtn:SetScript('OnClick', function() AdjustScale(-0.1) end)

  content = CreateFrame('Frame', nil, main)
  content:SetPoint('TOPLEFT', art, 'TOPLEFT', FRAME_W * IN_L, -FRAME_H * IN_T)
  content:SetPoint('BOTTOMRIGHT', art, 'BOTTOMRIGHT', -FRAME_W * IN_R, FRAME_H * IN_B)
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
  dial.hub:SetPoint('CENTER', content, 'CENTER', 0, -2)

  dial.face = dialLayer:CreateTexture(nil, 'BACKGROUND')
  dial.face:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
  dial.face:SetTexture('Interface\\Minimap\\UI-Minimap-Background')
  dial.face:SetVertexColor(0.12, 0.1, 0.08, 0.95)
  dial.face:SetSize(150, 150)

  dial.border = dialLayer:CreateTexture(nil, 'BORDER')
  dial.border:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
  dial.border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  dial.border:SetSize(178, 178)
  dial.border:SetVertexColor(1, 0.82, 0.25, 1)

  dial.skull = dialLayer:CreateTexture(nil, 'OVERLAY')
  dial.skull:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')
  dial.skull:SetSize(18, 18)
  dial.skull:SetPoint('TOP', dial.face, 'TOP', 0, 4)

  dial.caution = dialLayer:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  dial.caution:SetPoint('BOTTOM', dial.skull, 'TOP', 0, 0)
  dial.caution:SetText('CAUTION')
  dial.caution:SetTextColor(1, 0.82, 0)

  dial.safe = dialLayer:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  dial.safe:SetPoint('RIGHT', dial.face, 'LEFT', 2, 0)
  dial.safe:SetText('SAFE')
  dial.safe:SetTextColor(0.55, 0.9, 0.45)

  dial.pull = dialLayer:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  dial.pull:SetPoint('LEFT', dial.face, 'RIGHT', -2, 0)
  dial.pull:SetText('PULL')
  dial.pull:SetTextColor(1, 0.35, 0.25)

  local read = CreateFrame('Frame', nil, dialLayer)
  read:SetAllPoints()
  read:SetFrameLevel((dialLayer:GetFrameLevel() or 1) + 6)
  dial.pct = read:CreateFontString(nil, 'OVERLAY', 'GameFontNormalHuge')
  dial.pct:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
  dial.pct:SetTextColor(1, 0.9, 0.55)
  dial.pct:SetText('0%')

  dial.needle = dialLayer:CreateTexture(nil, 'OVERLAY')
  dial.needle:SetTexture('Interface\\Buttons\\WHITE8X8')
  dial.needle:SetVertexColor(1, 0.95, 0.85, 0.35)
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
