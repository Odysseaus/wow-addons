local _, NS = ...

-- issecretvalue is the documented tainted-safe test; == on a secret string throws.
local function valueIsSecret(value)
  return type(issecretvalue) == 'function' and issecretvalue(value)
end

local ROW_N = 10
-- Bars and plates cap at five visible rows (approved concepts). Dial marks
-- still use ROW_N.
local BAR_ROWS = 5
local PLATE_ROWS = 5
local BAR_GAP = 8
-- Fraction of the bar row used by the glossy bar. Smaller than 0.1.17 so the
-- bars sit clear of the gold frame with a visible inner margin.
local BAR_SLOT_FRAC = 0.68
-- Extra inset inside the content hole so bars never touch the filigree frame.
local BAR_PAD_X = 12
local BAR_PAD_Y = 10
local POLL = 0.2
local LERP_T = 0.25
local SCALE_MIN, SCALE_MAX = 0.6, 1.6
local TEX_SIZE = 1024
-- 0.1.15 art, each cropped from its approved concept (dungeon, torches, and
-- people are not in the textures). Interiors are alpha 0 so Lua draws names,
-- bars, marks, and the percent.
-- Bars: gold filigree frame (ThreatFrame), full 1024 square.
local HEADER = 26
local FRAME_W = 328
local FRAME_H = 328
-- Hole fractions of the frame texture. Top clears the crest; bottom clears the
-- lower gem; sides sit inside the rails.
local IN_L, IN_T, IN_R, IN_B = 0.11, 0.16, 0.11, 0.18
local DIAL_SIZE = 340
local PLATE_W = 372
-- ThreatPlate.tga is 1024x128 (width / height).
local PLATE_ASPECT = 1024 / 128
local PLATE_GAP = 5
local PLATE_BORDER = 8
-- Glossy fill sits in the empty stone groove (fractions of a plate, y from top).
-- Inner well of ThreatPlate.tga (1024x128): gold stroke is about x 73..948 and
-- y 86..123. 0.1.15 stopped the fill at y 0.875 (pixel 112), so the stripe
-- ended above the well floor and the bottom of the gloss was clipped.
-- 0.1.16/0.1.20 insets to the open interior: x 84..944 (0.082..0.922),
-- y 89..120 (0.695..0.938). 0.1.21 locks each plate row to an integer
-- ThreatPlate aspect height and sizes the outer plates window to exactly
-- five of those rows (explicit content SetSize) so bottom gold corners are
-- not scissored and the yellow frame is not taller than five plates.
local GROOVE_L, GROOVE_R = 0.082, 0.922
local GROOVE_T, GROOVE_B = 0.695, 0.938

local main, content, art, plateBorder
local barsLayer, platesLayer, dialLayer
local banner, modeBtn, plusBtn, minusBtn
local barByKey, barFree = {}, {}
local plateByKey, plateFree = {}, {}
local markByKey, markFree = {}, {}
local barSmooth, plateSmooth, markSmooth = {}, {}, {}
local dial = {}
local pollAcc = 0
local dialVis = { angle = 180, target = 180, ready = false }
-- Arc midline radius / half the dial texture (skull ring from the approved dial).
-- 0% is left, 50% up, 100% right. The arc is that upper semicircle.
local ARC_FRAC = 0.670
-- Sword cut from the dial concept. Hub is the texture center; the blade points
-- up. The opaque tip is 7px below the top of the 1024 texture (reach 505/512),
-- so UpdateNeedle lengthens the quad slightly and the tip meets the arc
-- without passing the ring. Not tinted.
local NEEDLE_TEX_W, NEEDLE_TEX_H = 1024, 1024
local NEEDLE_TIP_REACH = 505 / 512
-- Percent sits in the lower interior, under the hub and above the bottom skull.
-- y is down, as a fraction of the dial face.
local PCT_OX, PCT_OY = 0.0, 0.20
local built = false
-- Drag is allowed only after EventRegistry fires EditMode.Enter, and only
-- while EditModeManagerFrame exists. A saved lock flag never enables drag.
local editModeOpen = false
local editModeBound = false
local dragging = false

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

-- Threat color, not class color. High is red, mid orange/gold, low dark gold.
local THREAT_STOPS = {
  { 0.00, 0.42, 0.24, 0.08 },
  { 0.18, 0.58, 0.36, 0.09 },
  { 0.40, 0.86, 0.62, 0.14 },
  { 0.62, 0.93, 0.46, 0.08 },
  { 0.82, 0.78, 0.20, 0.05 },
  { 1.00, 0.62, 0.06, 0.04 },
}

local function ThreatRGB(pct)
  local t = (pct or 0) / 100
  if t < 0 then t = 0 end
  if t > 1 then t = 1 end
  local i = 1
  local n = #THREAT_STOPS
  while i < n and THREAT_STOPS[i + 1][1] < t do
    i = i + 1
  end
  local a = THREAT_STOPS[i]
  local b = THREAT_STOPS[i]
  if i < n then b = THREAT_STOPS[i + 1] end
  local span = b[1] - a[1]
  local u = 0
  if span > 0 then u = (t - a[1]) / span end
  if u < 0 then u = 0 end
  if u > 1 then u = 1 end
  return a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u, a[4] + (b[4] - a[4]) * u
end

-- Bar rows only. Rank 1 is the top (highest threat). Not class color, and not
-- a function of fill width, so a width change does not recolor the row.
-- BarFill.tga is a gray gloss (about 0.75), so these tints are what that
-- multiply shows as deep red, orange, gold, darker gold, brown.
local BAR_RANK_RGB = {
  { 1.00, 0.12, 0.08 },
  { 1.00, 0.55, 0.10 },
  { 1.00, 0.82, 0.22 },
  { 0.78, 0.55, 0.14 },
  { 0.50, 0.32, 0.12 },
}

local function BarRankRGB(rank)
  local c = BAR_RANK_RGB[rank] or BAR_RANK_RGB[#BAR_RANK_RGB]
  return c[1], c[2], c[3]
end

local function PctNumber(e)
  local p = tonumber(e.pct or e.percent or e.threatPct or e.scaled or e.value) or 0
  return p
end

local function DisplayName(e)
  -- Dial name marks only. Bars and plates use FirstName.
  local n = e.name or e.unitName or 'Unknown'
  if NS.ShortName then
    local s = NS.ShortName(n)
    if s and s ~= '' then n = s end
  end
  return n
end

-- Full character name for bars and plates. Realm suffix is not part of the
-- first name. Do not run this through ShortName (that keeps dial marks short).
local function FirstName(e)
  local n = e.name or e.unitName or 'Unknown'
  if valueIsSecret(n) then return 'Unknown' end
  if type(n) ~= 'string' then n = tostring(n) end
  local dash = string.find(n, '-', 1, true)
  if dash and dash > 1 then
    n = string.sub(n, 1, dash - 1)
  end
  if n == '' then return 'Unknown' end
  return n
end

local function TextWidth(fs)
  if fs.GetUnboundedStringWidth then
    local w = fs:GetUnboundedStringWidth()
    if w and w > 1 then return w end
  end
  if fs.GetStringWidth then
    local w = fs:GetStringWidth()
    if w and w > 1 then return w end
  end
  return 0
end

local function EntryKey(e, i)
  -- Secret GUIDs cannot be compared or used as table keys; skip them.
  if e.guid and not valueIsSecret(e.guid) and e.guid ~= '' then return e.guid end
  if e.GUID and not valueIsSecret(e.GUID) and e.GUID ~= '' then return e.GUID end
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
          seq = #out + 1,
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
          seq = #out + 1,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.pct == b.pct then
      local as = a.seq or 0
      local bs = b.seq or 0
      if as ~= bs then return as < bs end
      return (a.name or '') < (b.name or '')
    end
    return a.pct > b.pct
  end)
  return out
end

local function IsPlayerEntry(e, pname, pguid)
  if e.isPlayer then return true end
  if e.unit == 'player' then return true end
  -- UnitIsUnit on plain tokens; skip when the token or the boolean result is secret (no == on GUIDs).
  if e.unit and type(UnitIsUnit) == 'function' and not valueIsSecret(e.unit) then
    local same = UnitIsUnit(e.unit, 'player')
    if not valueIsSecret(same) and same then return true end
  end
  if pguid and e.guid and not valueIsSecret(pguid) and not valueIsSecret(e.guid) and e.guid == pguid then return true end
  if pname and e.name and e.name == pname then return true end
  return false
end

local function PlateRowHeight(rw)
  -- ThreatPlate.tga is 1024x128 (type 2 / 32bpp / desc 40). Integer height
  -- from the row width so the full stone plate - including bottom gold
  -- rounded corners - maps into the row with no fractional scissor.
  if not rw or rw < 8 then
    rw = content and content:GetWidth() or 0
  end
  if not rw or rw < 8 then rw = PLATE_W end
  local h = rw / PLATE_ASPECT
  -- ceil so a fractional pixel cannot drop the bottom gold texel row
  h = math.floor(h + 0.999)
  if h < 8 then h = 8 end
  return h
end

local function PlatesStackHeight(rw)
  local ph = PlateRowHeight(rw or PLATE_W)
  return ph * PLATE_ROWS + PLATE_GAP * (PLATE_ROWS - 1), ph
end

local function RowPitch()
  local ch = content and content:GetHeight() or 0
  local m = string.lower(tostring((NS.db and NS.db.mode) or 'bars'))
  local count = ROW_N
  local gap = 2
  if m == 'plates' then
    gap = PLATE_GAP
    count = PLATE_ROWS
    return PlateRowHeight(content and content:GetWidth() or PLATE_W), gap
  elseif m == 'bars' then
    count = BAR_ROWS
    gap = BAR_GAP
  end
  if not ch or ch < 40 then
    if m == 'bars' then
      ch = FRAME_H * (1 - IN_T - IN_B)
    else
      ch = FRAME_H * 0.70
    end
  end
  if m == 'bars' then
    ch = ch - (BAR_PAD_Y * 2)
  end
  local rh = (ch - gap * (count - 1)) / count
  if rh < 8 then rh = 8 end
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

-- BarFill/BarShine stay for plates. Bars use per-rank fills cut from the
-- approved image plus a gold bevel border.
-- Paths use doubled backslashes so Lua keeps Interface\AddOns\... (0.1.18
-- used single \ escapes and Rank/Bevel/plate textures failed to load).
local TEX_FILL = 'Interface\\AddOns\\WoWThreat\\Textures\\BarFill'
local TEX_SHINE = 'Interface\\AddOns\\WoWThreat\\Textures\\BarShine'
local TEX_PLATE = 'Interface\\AddOns\\WoWThreat\\Textures\\ThreatPlate'
local TEX_DIAMOND = 'Interface\\AddOns\\WoWThreat\\Textures\\Diamond'
local TEX_GOLD = 'Interface\\AddOns\\WoWThreat\\Textures\\GoldLine'
local TEX_BEVEL = 'Interface\\AddOns\\WoWThreat\\Textures\\BarBevel'
local TEX_FILL_RANK = {
  'Interface\\AddOns\\WoWThreat\\Textures\\BarFillRank1',
  'Interface\\AddOns\\WoWThreat\\Textures\\BarFillRank2',
  'Interface\\AddOns\\WoWThreat\\Textures\\BarFillRank3',
  'Interface\\AddOns\\WoWThreat\\Textures\\BarFillRank4',
  'Interface\\AddOns\\WoWThreat\\Textures\\BarFillRank5',
}
local BEVEL_CAP = 32 / 256

local function CreateBarRow(parent)
  local row = CreateFrame('Frame', nil, parent)
  row:SetHeight(16)
  local icon = row:CreateTexture(nil, 'ARTWORK')
  icon:SetSize(14, 14)
  icon:SetPoint('LEFT', row, 'LEFT', 0, 0)
  icon:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
  local pctFS = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  pctFS:SetPoint('RIGHT', row, 'RIGHT', 0, 0)
  pctFS:SetWidth(42)
  pctFS:SetJustifyH('RIGHT')
  pctFS:SetWordWrap(false)
  pctFS:SetFont('Fonts\\FRIZQT__.TTF', 14, '')
  pctFS:SetTextColor(0.96, 0.91, 0.78)
  -- Track starts after the icon so every row shares a left edge.
  local slot = CreateFrame('Frame', nil, row)
  slot:SetPoint('LEFT', row, 'LEFT', 20, 0)
  slot:SetPoint('RIGHT', pctFS, 'LEFT', -6, 0)
  slot:SetHeight(12)
  -- StatusBar fill grows from the left. Per-rank art is the StatusBar texture.
  -- SetValue takes the collector percent (or a secret) without arithmetic here.
  local status = CreateFrame('StatusBar', nil, slot)
  status:SetPoint('TOPLEFT', slot, 'TOPLEFT', 0, 0)
  status:SetPoint('BOTTOMRIGHT', slot, 'BOTTOMRIGHT', 0, 0)
  status:SetStatusBarTexture(TEX_FILL_RANK[1])
  status:SetMinMaxValues(0, 100)
  status:SetValue(0)
  if status.SetOrientation then status:SetOrientation('HORIZONTAL') end
  if status.SetReverseFill then status:SetReverseFill(false) end
  -- Art already carries rank color; keep the vertex white.
  status:SetStatusBarColor(1, 1, 1, 1)
  -- Gold bevel is a 3-slice (left cap / stretch mid / right cap) locked to the
  -- StatusBar fill texture so the border shrinks with threat.
  local bevelL = status:CreateTexture(nil, 'OVERLAY', nil, 1)
  bevelL:SetTexture(TEX_BEVEL)
  bevelL:SetTexCoord(0, BEVEL_CAP, 0, 1)
  local bevelM = status:CreateTexture(nil, 'OVERLAY', nil, 1)
  bevelM:SetTexture(TEX_BEVEL)
  bevelM:SetTexCoord(BEVEL_CAP, 1 - BEVEL_CAP, 0, 1)
  local bevelR = status:CreateTexture(nil, 'OVERLAY', nil, 1)
  bevelR:SetTexture(TEX_BEVEL)
  bevelR:SetTexCoord(1 - BEVEL_CAP, 1, 0, 1)
  local nameLayer = CreateFrame('Frame', nil, status)
  nameLayer:SetAllPoints()
  if nameLayer.SetFrameLevel and status.GetFrameLevel then
    nameLayer:SetFrameLevel(status:GetFrameLevel() + 3)
  end
  local nameFS = nameLayer:CreateFontString(nil, 'OVERLAY')
  nameFS:SetPoint('LEFT', nameLayer, 'LEFT', 8, 0)
  nameFS:SetPoint('RIGHT', nameLayer, 'RIGHT', -6, 0)
  nameFS:SetJustifyH('LEFT')
  nameFS:SetJustifyV('MIDDLE')
  nameFS:SetWordWrap(false)
  nameFS:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
  nameFS:SetTextColor(0.97, 0.94, 0.86)
  nameFS:SetShadowColor(0, 0, 0, 1)
  nameFS:SetShadowOffset(1, -1)
  row.icon = icon
  row.nameFS = nameFS
  row.pctFS = pctFS
  row.slot = slot
  row.status = status
  row.bevelL = bevelL
  row.bevelM = bevelM
  row.bevelR = bevelR
  row.rankApplied = nil
  row:Hide()
  return row
end

local function LayoutBarFill(row)
  if not row.slot then return end
  local rh = row:GetHeight() or 16
  local sh = rh * BAR_SLOT_FRAC
  if sh < 8 then sh = 8 end
  if sh > rh - 2 then sh = rh - 2 end
  local icon = sh
  if icon < 12 then icon = 12 end
  if icon > rh - 1 then icon = rh - 1 end
  row.icon:SetSize(icon, icon)
  -- Same left inset on every row. The name is inside the bar and does not shift it.
  row.slot:ClearAllPoints()
  row.slot:SetPoint('LEFT', row, 'LEFT', icon + 6, 0)
  row.slot:SetPoint('RIGHT', row.pctFS, 'LEFT', -6, 0)
  row.slot:SetHeight(sh)
  -- Bevel follows the filled StatusBar texture (grows and shrinks with threat).
  if row.status and row.status.GetStatusBarTexture then
    local sbTex = row.status:GetStatusBarTexture()
    local bevelL, bevelM, bevelR = row.bevelL, row.bevelM, row.bevelR
    if sbTex and bevelL and bevelM and bevelR then
      local pad = 2
      local cap = sh * 0.22
      if cap < 6 then cap = 6 end
      if cap > 14 then cap = 14 end
      bevelL:ClearAllPoints()
      bevelM:ClearAllPoints()
      bevelR:ClearAllPoints()
      bevelL:SetPoint('TOPLEFT', sbTex, 'TOPLEFT', -pad, pad)
      bevelL:SetPoint('BOTTOMLEFT', sbTex, 'BOTTOMLEFT', -pad, -pad)
      bevelL:SetWidth(cap)
      bevelR:SetPoint('TOPRIGHT', sbTex, 'TOPRIGHT', pad, pad)
      bevelR:SetPoint('BOTTOMRIGHT', sbTex, 'BOTTOMRIGHT', pad, -pad)
      bevelR:SetWidth(cap)
      bevelM:SetPoint('TOPLEFT', bevelL, 'TOPRIGHT', 0, 0)
      bevelM:SetPoint('BOTTOMLEFT', bevelL, 'BOTTOMRIGHT', 0, 0)
      bevelM:SetPoint('TOPRIGHT', bevelR, 'TOPLEFT', 0, 0)
      bevelM:SetPoint('BOTTOMRIGHT', bevelR, 'BOTTOMLEFT', 0, 0)
      bevelL:Show()
      bevelM:Show()
      bevelR:Show()
    end
  end
end

-- Collector pct is 0..100 (over 100 clamps to a full bar). A secret value is
-- handed to SetValue and is not read here.
local function ApplyBarValue(status, pct)
  if valueIsSecret(pct) then
    status:SetValue(pct)
    return
  end
  local v = pct or 0
  if type(v) ~= 'number' then
    v = tonumber(v) or 0
  end
  if v < 0 then v = 0 end
  if v > 100 then v = 100 end
  status:SetValue(v)
end

local function CreatePlate(parent)
  local row = CreateFrame('Frame', nil, parent)
  row:SetHeight(PlateRowHeight(PLATE_W))
  if row.SetClipsChildren then row:SetClipsChildren(false) end
  local bg = row:CreateTexture(nil, 'BACKGROUND')
  bg:SetTexture(TEX_PLATE)
  -- Full 1024x128 plate art (ThreatPlate has bottom gold corners in-file).
  -- Parent clip is disabled in ApplyFrame so bottom ornaments are not cut.
  bg:SetTexCoord(0, 1, 0, 1)
  bg:ClearAllPoints()
  bg:SetAllPoints(row)
  local nameFS = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  nameFS:SetJustifyH('CENTER')
  nameFS:SetWordWrap(false)
  nameFS:SetTextColor(0.93, 0.88, 0.74)
  local pctFS = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  pctFS:SetJustifyH('RIGHT')
  pctFS:SetTextColor(0.93, 0.88, 0.74)
  local fill = row:CreateTexture(nil, 'ARTWORK')
  fill:SetTexture(TEX_FILL)
  local shine = row:CreateTexture(nil, 'OVERLAY')
  shine:SetTexture(TEX_SHINE)
  shine:SetBlendMode('ADD')
  shine:SetAlpha(0.85)
  row.bg = bg
  row.nameFS = nameFS
  row.pctFS = pctFS
  row.fill = fill
  row.shine = shine
  row.pctValue = 0
  row:Hide()
  return row
end

local function LayoutPlate(row)
  local rw = row:GetWidth() or 0
  if rw < 8 then return end
  -- Integer aspect height; full TexCoord; bg pinned to all four sides so the
  -- bottom gold corners stay in the drawn quad (not cropped or letterboxed).
  local rh = PlateRowHeight(rw)
  if row.SetHeight then row:SetHeight(rh) end
  if row.SetClipsChildren then row:SetClipsChildren(false) end
  if row.bg then
    row.bg:SetTexCoord(0, 1, 0, 1)
    row.bg:ClearAllPoints()
    row.bg:SetPoint('TOPLEFT', row, 'TOPLEFT', 0, 0)
    row.bg:SetPoint('BOTTOMRIGHT', row, 'BOTTOMRIGHT', 0, 0)
  end
  local nameY = rh * 0.16
  row.nameFS:ClearAllPoints()
  row.nameFS:SetPoint('CENTER', row, 'CENTER', 0, nameY)
  local nw = TextWidth(row.nameFS)
  if nw < 8 then
    local label = row.nameFS:GetText() or ''
    nw = 8 * string.len(label)
    if nw < 8 then nw = 8 end
  end
  row.nameFS:SetWidth(nw + 2)
  row.pctFS:ClearAllPoints()
  row.pctFS:SetPoint('RIGHT', row, 'RIGHT', -rw * 0.045, nameY)
  row.pctFS:SetWidth(rw * 0.16)
  local gx = rw * GROOVE_L
  local top = rh * GROOVE_T
  local bot = rh * GROOVE_B
  if top < 1 then top = 1 end
  if bot < top + 3 then bot = top + 3 end
  if bot > rh - 1 then bot = rh - 1 end
  local gw = rw * (GROOVE_R - GROOVE_L)
  local pct = row.pctValue or 0
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  local fw = gw * pct / 100
  row.fill:ClearAllPoints()
  row.shine:ClearAllPoints()
  -- Top and bottom anchors keep the whole gloss gradient inside the well.
  -- A center+height anchor at the old 0.70..0.875 groove cut the stripe off
  -- above the floor of the stone meter.
  row.fill:SetPoint('TOPLEFT', row, 'TOPLEFT', gx, -top)
  row.fill:SetPoint('BOTTOMLEFT', row, 'TOPLEFT', gx, -bot)
  row.fill:SetTexCoord(0, 1, 0, 1)
  row.shine:SetTexCoord(0, 1, 0, 1)
  if fw < 0.5 then
    row.fill:Hide()
    row.shine:Hide()
  else
    row.fill:Show()
    row.shine:Show()
    row.fill:SetWidth(fw)
    row.shine:SetPoint('TOPLEFT', row.fill, 'TOPLEFT', 0, 0)
    row.shine:SetPoint('BOTTOMRIGHT', row.fill, 'BOTTOMRIGHT', 0, 0)
  end
end

local function CreateMarker(parent)
  local m = CreateFrame('Frame', nil, parent)
  m:SetSize(90, 16)
  local icon = m:CreateTexture(nil, 'OVERLAY')
  icon:SetSize(12, 12)
  icon:SetTexture(TEX_DIAMOND)
  local nameFS = m:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
  nameFS:SetWordWrap(false)
  nameFS:SetWidth(70)
  nameFS:SetTextColor(0.96, 0.93, 0.84)
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
  -- Name sits just inside the arc, toward the hub.
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
    local reach = NEEDLE_TIP_REACH
    if not reach or reach < 0.5 then reach = 1 end
    local h = (length * 2) / reach
    if h < 2 then h = 2 end
    dial.needle:Show()
    -- Sword art is already gold. Do not tint it.
    dial.needle:SetVertexColor(1, 1, 1, 1)
    dial.needle:ClearAllPoints()
    dial.needle:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
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

local function FillBar(row, e, rank)
  ApplyIcon(row.icon, e.class)
  row.nameFS:SetText(FirstName(e))
  row.nameFS:SetTextColor(0.97, 0.94, 0.86)
  -- Rank art stays on the row. Do not swap textures from pct or fill width.
  if row.rankApplied ~= rank then
    row.rankApplied = rank
    local tex = TEX_FILL_RANK[rank or 1] or TEX_FILL_RANK[#TEX_FILL_RANK]
    row.status:SetStatusBarTexture(tex)
    row.status:SetStatusBarColor(1, 1, 1, 1)
  end
  -- e.pct is the collector's 0-100 percent. Do not fall back to raw threat.
  -- Do not compare or format a secret; SetValue can take it as-is.
  local pct = e.pct
  if valueIsSecret(pct) then
    ApplyBarValue(row.status, pct)
  else
    local shown = pct or 0
    if type(shown) ~= 'number' then shown = tonumber(shown) or 0 end
    row.pctFS:SetText(string.format('%d', math.floor(shown + 0.5)))
    ApplyBarValue(row.status, shown)
  end
  LayoutBarFill(row)
end

local function FillPlate(row, e, rank, n)
  local pct = e.pct or 0
  local v = pct
  if v < 0 then v = 0 end
  if v > 100 then v = 100 end
  row.pctValue = v
  local tr, tg, tb = ThreatRGB(v)
  row.fill:SetVertexColor(tr, tg, tb, 1)
  row.shine:SetVertexColor(1, 0.97, 0.88, 0.9)
  row.nameFS:SetText(FirstName(e))
  row.nameFS:SetTextColor(0.94, 0.89, 0.76)
  row.pctFS:SetText(string.format('%d', math.floor(pct + 0.5)))
  LayoutPlate(row)
end

local function FillMarker(row, e)
  local r, g, b = ClassRGB(e.class)
  row.icon:SetTexture(TEX_DIAMOND)
  row.icon:SetTexCoord(0, 1, 0, 1)
  row.icon:SetVertexColor(r, g, b, 1)
  row.nameFS:SetText(DisplayName(e))
  row.nameFS:SetTextColor(0.96, 0.93, 0.84)
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
  local nBar = n
  if nBar > BAR_ROWS then nBar = BAR_ROWS end
  local nPlate = n
  if nPlate > PLATE_ROWS then nPlate = PLATE_ROWS end
  for i = 1, n do
    local e = list[i]
    local key = EntryKey(e, i)
    local y = -((i - 1) * (rh + gap))
    seenM[key] = true
    if i <= nBar then
      seenB[key] = true
      local bar = Acquire(barByKey, barFree, key)
      if bar then
        bar:SetHeight(rh)
        FillBar(bar, e, i)
        bar.targetY = y
        if not barSmooth[key] then barSmooth[key] = { y = y } end
        bar:Show()
      end
    end
    if i <= nPlate then
      seenP[key] = true
      local plate = Acquire(plateByKey, plateFree, key)
      if plate then
        -- Aspect-locked height (not a shortened slice of a tall/short window).
        plate:SetHeight(PlateRowHeight(plate:GetWidth() or PLATE_W))
        FillPlate(plate, e, i, n)
        plate.targetY = y
        if not plateSmooth[key] then plateSmooth[key] = { y = y } end
        plate:Show()
      end
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
  -- Face fills the content rect (the inner opening). The square uses the
  -- shorter side; the needle scales with that face so the tip stays on the arc.
  local sz = cw
  if ch < sz then sz = ch end
  local face = sz
  if dial.face then dial.face:Hide() end
  dial.hub:ClearAllPoints()
  dial.hub:SetPoint('CENTER', content, 'CENTER', 0, 0)
  local radius = face * 0.5 * ARC_FRAC
  local px = PCT_OX * face
  local py = -PCT_OY * face
  if dial.pct then
    dial.pct:ClearAllPoints()
    dial.pct:SetPoint('CENTER', dial.hub, 'CENTER', px, py)
  end
  if dial.pctSign and dial.pct then
    dial.pctSign:ClearAllPoints()
    dial.pctSign:SetPoint('TOP', dial.pct, 'BOTTOM', 0, 1)
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
        row:SetPoint('TOPLEFT', content, 'TOPLEFT', BAR_PAD_X, st.y - BAR_PAD_Y)
        row:SetPoint('TOPRIGHT', content, 'TOPRIGHT', -BAR_PAD_X, st.y - BAR_PAD_Y)
        -- Position only. Rank texture and StatusBar value are not touched here.
        LayoutBarFill(row)
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
        row:SetHeight(PlateRowHeight(row:GetWidth() or PLATE_W))
        LayoutPlate(row)
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

local function SavedLockFlag()
  return (NS.db and (NS.db.locked or NS.db.lock)) and true or false
end

local function EditModeSignalsPresent()
  return (EventRegistry and EditModeManagerFrame) and true or false
end

-- Edit Mode open, both client objects present, and /wtm has not locked.
-- Outside Edit Mode this is false even when the saved flag is false.
local function DragAllowed()
  if not editModeOpen then return false end
  if not EditModeSignalsPresent() then return false end
  if SavedLockFlag() then return false end
  return true
end

-- Blue Edit Mode box from daves_balls EditModeDialog.lua (CreateSelection /
-- PaintSelection). Blizzard's editmode-actionbar-highlight nine-slice when
-- that atlas exists; otherwise a solid blue via SetColorTexture (built-in
-- white). Shown only while this Edit Mode session is active.
local HIGHLIGHT_KIT = 'editmode-actionbar-highlight'
local SELECTION_LAYOUT = {
  TopRightCorner = { atlas = '%s-NineSlice-Corner', mirrorLayout = true, x = 8, y = 8 },
  TopLeftCorner = { atlas = '%s-NineSlice-Corner', mirrorLayout = true, x = -8, y = 8 },
  BottomLeftCorner = { atlas = '%s-NineSlice-Corner', mirrorLayout = true, x = -8, y = -8 },
  BottomRightCorner = { atlas = '%s-NineSlice-Corner', mirrorLayout = true, x = 8, y = -8 },
  TopEdge = { atlas = '_%s-NineSlice-EdgeTop' },
  BottomEdge = { atlas = '_%s-NineSlice-EdgeBottom' },
  LeftEdge = { atlas = '!%s-NineSlice-EdgeLeft' },
  RightEdge = { atlas = '!%s-NineSlice-EdgeRight' },
  Center = { atlas = '%s-NineSlice-Center', x = -8, y = 8, x1 = 8, y1 = -8 },
}
local HIGHLIGHT_PIECES = {
  'TopLeftCorner', 'TopRightCorner', 'BottomLeftCorner', 'BottomRightCorner',
  'TopEdge', 'BottomEdge', 'LeftEdge', 'RightEdge', 'Center',
}
local editHighlight

local function HasEditModeArt()
  return NineSliceUtil and NineSliceUtil.ApplyLayout and C_Texture and C_Texture.GetAtlasInfo
    and C_Texture.GetAtlasInfo(HIGHLIGHT_KIT .. '-NineSlice-Corner') ~= nil
end

local function PaintEditHighlight(sel)
  if sel.art then
    NineSliceUtil.ApplyLayout(sel.art, SELECTION_LAYOUT, HIGHLIGHT_KIT)
  elseif sel.tint then
    sel.tint:SetColorTexture(0.25, 0.6, 1, 0.22)
  end
end

local function CreateEditHighlight(target)
  local sel = CreateFrame('Frame', nil, target)
  sel:SetAllPoints()
  sel:SetFrameLevel(target:GetFrameLevel() + 20)
  if HasEditModeArt() then
    sel.art = CreateFrame('Frame', nil, sel)
    sel.art:SetAllPoints()
    sel.hover = CreateFrame('Frame', nil, sel)
    sel.hover:SetAllPoints()
    sel.hover:SetAlpha(0.4)
    NineSliceUtil.ApplyLayout(sel.hover, SELECTION_LAYOUT, HIGHLIGHT_KIT)
    local i, key
    for i, key in ipairs(HIGHLIGHT_PIECES) do
      if sel.hover[key] then sel.hover[key]:SetBlendMode('ADD') end
    end
    sel.hover:Hide()
  else
    sel.tint = sel:CreateTexture(nil, 'OVERLAY')
    sel.tint:SetAllPoints()
  end
  sel.label = sel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
  sel.label:SetPoint('BOTTOM', sel, 'TOP', 0, 10)
  sel.label:SetText('WoW Threat')
  PaintEditHighlight(sel)
  sel:SetIgnoreParentAlpha(true)
  sel:Hide()
  sel:SetScript('OnShow', function()
    if not sel.hover then return end
    if target:GetScript('OnEnter') ~= sel.hookedEnter or not sel.hookedEnter then
      target:HookScript('OnEnter', function()
        if sel:IsShown() then sel.hover:Show() end
      end)
      sel.hookedEnter = target:GetScript('OnEnter')
    end
    if target:GetScript('OnLeave') ~= sel.hookedLeave or not sel.hookedLeave then
      target:HookScript('OnLeave', function() sel.hover:Hide() end)
      sel.hookedLeave = target:GetScript('OnLeave')
    end
  end)
  sel:SetScript('OnHide', function()
    if sel.hover then sel.hover:Hide() end
  end)
  return sel
end

local function SyncEditHighlight()
  if not editHighlight then return end
  -- Edit Mode session only. A cleared /wtm lock must not show the box.
  if editModeOpen then
    editHighlight:Show()
  else
    editHighlight:Hide()
  end
end

local function BindEditModeSignals()
  if editModeBound or not main then return end
  if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
    return
  end
  -- Listen only. EditModeSystem is a closed enum; do not register a frame.
  local function onEnter()
    editModeOpen = true
    SyncEditHighlight()
    if NS.ApplyLock then NS.ApplyLock() end
  end
  local function onExit()
    editModeOpen = false
    SyncEditHighlight()
    if dragging and main then
      dragging = false
      main:StopMovingOrSizing()
      SavePosition()
    end
    if NS.ApplyLock then NS.ApplyLock() end
  end
  EventRegistry:RegisterCallback("EditMode.Enter", onEnter, main)
  EventRegistry:RegisterCallback("EditMode.Exit", onExit, main)
  editModeBound = true
end

function NS.ApplyLock()
  if not main then return end
  BindEditModeSignals()
  SyncEditHighlight()
  local allow = DragAllowed()
  if not allow then
    if dragging then
      dragging = false
      main:StopMovingOrSizing()
      SavePosition()
    end
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

local function ApplyFrame(m)
  if not main or not art or not content then return end
  local aw, ah
  if m == 'dial' then
    aw, ah = DIAL_SIZE, DIAL_SIZE
  elseif m == 'plates' then
    -- Outer window is always exactly five plate-rows tall (approved concept),
    -- even when solo shows only one player inside that container.
    local stack = PlatesStackHeight(PLATE_W)
    aw = PLATE_W + PLATE_BORDER * 2
    ah = stack + PLATE_BORDER * 2
  else
    aw, ah = FRAME_W, FRAME_H
  end
  main:SetSize(aw, ah + HEADER)
  if main.SetClipsChildren then main:SetClipsChildren(false) end
  art:ClearAllPoints()
  art:SetPoint('TOPLEFT', main, 'TOPLEFT', 0, -HEADER)
  art:SetSize(aw, ah)
  art:SetTexCoord(0, 1, 0, 1)
  if m == 'dial' then
    art:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\ThreatDial')
    art:Show()
    content:ClearAllPoints()
    content:SetAllPoints(art)
    if content.SetClipsChildren then content:SetClipsChildren(true) end
  elseif m == 'plates' then
    art:Hide()
    local stack = PlatesStackHeight(PLATE_W)
    -- Explicit content size (not BOTTOMRIGHT stretch). Stretching to a stale
    -- FRAME_H-sized main left a tall empty yellow frame under one plate, and
    -- a too-short content scissored each row's bottom gold corners.
    content:ClearAllPoints()
    content:SetPoint('TOPLEFT', main, 'TOPLEFT', PLATE_BORDER, -(HEADER + PLATE_BORDER))
    content:SetSize(PLATE_W, stack)
    if content.SetClipsChildren then content:SetClipsChildren(false) end
    if platesLayer and platesLayer.SetClipsChildren then
      platesLayer:SetClipsChildren(false)
    end
  else
    art:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\ThreatFrame')
    art:Show()
    content:ClearAllPoints()
    content:SetPoint('TOPLEFT', art, 'TOPLEFT', aw * IN_L, -ah * IN_T)
    content:SetPoint('BOTTOMRIGHT', art, 'BOTTOMRIGHT', -aw * IN_R, ah * IN_B)
    if content.SetClipsChildren then content:SetClipsChildren(true) end
  end
  if plateBorder then
    if m == 'plates' then plateBorder:Show() else plateBorder:Hide() end
  end
end

function NS.ApplyMode()
  if not barsLayer then return end
  local m = string.lower(tostring((NS.db and NS.db.mode) or 'bars'))
  if m ~= 'bars' and m ~= 'plates' and m ~= 'dial' then m = 'bars' end
  if NS.db then NS.db.mode = m end
  ApplyFrame(m)
  if m == 'bars' then barsLayer:Show() else barsLayer:Hide() end
  if m == 'plates' then platesLayer:Show() else platesLayer:Hide() end
  if m == 'dial' then
    dialLayer:Show()
    if dial.face then dial.face:Hide() end
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
  -- Locked until EditMode.Enter. Do not register drag or start a move here.
  -- Highlight stays hidden until EditMode.Enter (editModeOpen is false here).
  editHighlight = CreateEditHighlight(main)
  main:SetMovable(false)
  main:SetScript('OnDragStart', function(self)
    if not DragAllowed() then return end
    dragging = true
    self:SetMovable(true)
    self:StartMoving()
  end)
  main:SetScript('OnDragStop', function(self)
    dragging = false
    self:StopMovingOrSizing()
    SavePosition()
  end)

  main:SetSize(FRAME_W, FRAME_H + HEADER)

  art = main:CreateTexture(nil, 'BACKGROUND')
  art:SetPoint('TOPLEFT', main, 'TOPLEFT', 0, -HEADER)
  art:SetSize(FRAME_W, FRAME_H)
  art:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\ThreatFrame')
  art:SetTexCoord(0, 1, 0, 1)

  modeBtn = MakeMiniButton(main, 'WoWThreatModeButton', 'Bars', 92)
  modeBtn:SetPoint('TOPLEFT', main, 'TOPLEFT', 2, -2)
  modeBtn:SetScript('OnClick', function()
    if NS.CycleMode then NS.CycleMode() end
    if NS.ApplyMode then NS.ApplyMode() end
    if NS.RefreshChrome then NS.RefreshChrome() end
  end)

  plusBtn = MakeMiniButton(main, 'WoWThreatPlusButton', '+', 24)
  plusBtn:SetPoint('TOPRIGHT', main, 'TOPRIGHT', -2, -2)
  plusBtn:SetScript('OnClick', function() AdjustScale(0.1) end)
  minusBtn = MakeMiniButton(main, 'WoWThreatMinusButton', '-', 24)
  minusBtn:SetPoint('RIGHT', plusBtn, 'LEFT', -4, 0)
  minusBtn:SetScript('OnClick', function() AdjustScale(-0.1) end)
  plusBtn:Hide()
  minusBtn:Hide()
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
  plateBorder = CreateFrame('Frame', nil, main)
  local edgeTop = plateBorder:CreateTexture(nil, 'ARTWORK')
  edgeTop:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\GoldLine')
  edgeTop:SetPoint('BOTTOMLEFT', content, 'TOPLEFT', -3, 0)
  edgeTop:SetPoint('BOTTOMRIGHT', content, 'TOPRIGHT', 3, 0)
  edgeTop:SetHeight(3)
  local edgeBot = plateBorder:CreateTexture(nil, 'ARTWORK')
  edgeBot:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\GoldLine')
  edgeBot:SetPoint('TOPLEFT', content, 'BOTTOMLEFT', -3, 0)
  edgeBot:SetPoint('TOPRIGHT', content, 'BOTTOMRIGHT', 3, 0)
  edgeBot:SetHeight(3)
  local edgeLeft = plateBorder:CreateTexture(nil, 'ARTWORK')
  edgeLeft:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\GoldLine')
  edgeLeft:SetPoint('TOPRIGHT', content, 'TOPLEFT', 0, 3)
  edgeLeft:SetPoint('BOTTOMRIGHT', content, 'BOTTOMLEFT', 0, -3)
  edgeLeft:SetWidth(3)
  local edgeRight = plateBorder:CreateTexture(nil, 'ARTWORK')
  edgeRight:SetTexture('Interface\\AddOns\\WoWThreat\\Textures\\GoldLine')
  edgeRight:SetPoint('TOPLEFT', content, 'TOPRIGHT', 0, 3)
  edgeRight:SetPoint('BOTTOMLEFT', content, 'BOTTOMRIGHT', 0, -3)
  edgeRight:SetWidth(3)
  plateBorder:Hide()

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
  dial.hub:SetPoint('CENTER', content, 'CENTER', 0, 0)

  dial.face = dialLayer:CreateTexture(nil, 'BACKGROUND')
  dial.face:SetPoint('CENTER', dial.hub, 'CENTER', 0, 0)
  dial.face:Hide()
  dial.face:SetSize(4, 4)

  local read = CreateFrame('Frame', nil, dialLayer)
  read:SetAllPoints()
  read:SetFrameLevel((dialLayer:GetFrameLevel() or 1) + 6)
  dial.pct = read:CreateFontString(nil, 'OVERLAY')
  dial.pct:SetFont('Fonts\\FRIZQT__.TTF', 36, '')
  dial.pct:SetTextColor(0.95, 0.82, 0.42, 1)
  dial.pct:SetText('0')
  dial.pctSign = read:CreateFontString(nil, 'OVERLAY')
  dial.pctSign:SetFont('Fonts\\FRIZQT__.TTF', 18, '')
  dial.pctSign:SetTextColor(0.95, 0.82, 0.42, 1)
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
