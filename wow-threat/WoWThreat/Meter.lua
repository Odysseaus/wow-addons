-- WoWThreat single bar meter (Phase 1, v0.2.0). Plain rows, no slide/pop/fire.
local _, NS = ...

local POLL = 0.2
local HEADER = 18
local PAD = 6
local TEX = "Interface\\AddOns\\WoWThreat\\Textures\\"

local main, title, rows = nil, nil, {}
local editModeOpen, editModeBound, dragging = false, false, false
local pollAcc = 0

local function DB()
  if not NS.db and NS.MigrateDB then NS.MigrateDB() end
  return NS.db or {}
end

local function SavePosition()
  if not main then return end
  local lay = NS.Layout and NS.Layout()
  if not lay then return end
  local point, _, relativePoint, xOfs, yOfs = main:GetPoint(1)
  lay.point = point or "CENTER"
  lay.relativePoint = relativePoint or "CENTER"
  lay.xOfs = xOfs or 0
  lay.yOfs = yOfs or 0
end

-- ---------------------------------------------------------------- Edit Mode
local function DragAllowed()
  return editModeOpen and EventRegistry ~= nil and EditModeManagerFrame ~= nil
end

local HIGHLIGHT_KIT = "editmode-actionbar-highlight"
local SELECTION_LAYOUT = {
  TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
  TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
  BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
  BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
  TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
  BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
  LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
  RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
  Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local editHighlight

local function HasEditModeArt()
  if not (NineSliceUtil and NineSliceUtil.ApplyLayout) then return false end
  if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
  local ok, info = pcall(C_Texture.GetAtlasInfo, HIGHLIGHT_KIT .. "-NineSlice-Corner")
  return ok and info ~= nil
end

local function CreateEditHighlight(target)
  local sel = CreateFrame("Frame", nil, target)
  sel:SetAllPoints()
  sel:SetFrameLevel(target:GetFrameLevel() + 20)
  local painted = false
  if HasEditModeArt() then
    sel.art = CreateFrame("Frame", nil, sel)
    sel.art:SetAllPoints()
    painted = pcall(NineSliceUtil.ApplyLayout, sel.art, SELECTION_LAYOUT, HIGHLIGHT_KIT)
  end
  if not painted then
    sel.tint = sel:CreateTexture(nil, "OVERLAY")
    sel.tint:SetAllPoints()
    sel.tint:SetColorTexture(0.25, 0.6, 1, 0.22)
  end
  sel.label = sel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sel.label:SetPoint("BOTTOM", sel, "TOP", 0, 10)
  sel.label:SetText("WoW Threat")
  if sel.SetIgnoreParentAlpha then sel:SetIgnoreParentAlpha(true) end
  sel:Hide()
  return sel
end

local function ApplyDrag()
  if not main then return end
  if editHighlight then
    if editModeOpen then editHighlight:Show() else editHighlight:Hide() end
  end
  if DragAllowed() then
    main:SetMovable(true)
    main:EnableMouse(true)
    main:RegisterForDrag("LeftButton")
  else
    if dragging then
      dragging = false
      main:StopMovingOrSizing()
      SavePosition()
    end
    main:SetMovable(false)
    main:RegisterForDrag()
    main:EnableMouse(false)
  end
end

local function BindEditModeSignals()
  if editModeBound or not main then return end
  if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return end
  -- Listen only. Never RegisterSystemFrame (closed enum, taints the manager).
  EventRegistry:RegisterCallback("EditMode.Enter", function()
    editModeOpen = true
    ApplyDrag()
    if NS.Refresh then NS.Refresh() end
  end, main)
  EventRegistry:RegisterCallback("EditMode.Exit", function()
    editModeOpen = false
    ApplyDrag()
    if NS.Refresh then NS.Refresh() end
  end, main)
  editModeBound = true
end

-- ---------------------------------------------------------------- rows
local ELLIPSIS = "\226\128\166" -- UTF-8 "…"
local COL_GAP = 12
local FADE_TIME = 1.0
local SAFETY_POLL = 0.5
local TEST_TICK = 0.1

local state = {}      -- eased values per member key (GUID or name)
local animFrame = nil
local EASE_RATE = 8
local SNAP_PX = 0.5
local fadeT = nil     -- seconds left in the leave-combat fade, or nil
local lastShown = 0

local function CreateRow(i)
  local r = CreateFrame("Frame", nil, main)
  r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(0.91, 0.77, 0.42, 0.12)
  r.hl:Hide()
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 1, 0)
  r.name:SetJustifyH("LEFT")
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", -1, 0)
  r.value:SetJustifyH("RIGHT")

  r.bar = CreateFrame("Frame", nil, r)
  r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 2)
  r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 2)
  r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(0.04, 0.035, 0.04, 0.9)
  r.fill = r.bar:CreateTexture(nil, "ARTWORK")
  r.fill:SetPoint("TOPLEFT", r.bar, "TOPLEFT", 1, -1)
  r.fill:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", 1, 1)
  r.fill:SetTexture(TEX .. "BarFill")
  r.shine = r.bar:CreateTexture(nil, "OVERLAY")
  r.shine:SetAllPoints(r.fill)
  r.shine:SetTexture(TEX .. "BarShine")
  r.shine:SetBlendMode("ADD")
  r.shine:SetAlpha(0.35)
  r.bevel = r.bar:CreateTexture(nil, "OVERLAY", nil, 1)
  r.bevel:SetAllPoints()
  r.bevel:SetTexture(TEX .. "BarBevel")
  r.border = r.bar:CreateTexture(nil, "OVERLAY", nil, 2)
  r.border:SetPoint("TOPLEFT", r.bar, "TOPLEFT", -1, 1)
  r.border:SetPoint("BOTTOMRIGHT", r.bar, "BOTTOMRIGHT", 1, -1)
  r.border:SetColorTexture(0.91, 0.77, 0.42, 0.25)
  r.border:Hide()
  r:Hide()
  rows[i] = r
  return r
end

-- Drop one UTF-8 character from the end.
local function DropLastChar(s)
  local n = string.len(s)
  while n > 1 do
    local b = string.byte(s, n)
    n = n - 1
    if b < 128 or b >= 192 then break end
  end
  return string.sub(s, 1, n)
end

function NS.Truncate(fs, text, maxW)
  text = text or "?"
  fs:SetText(text)
  if not fs.GetStringWidth or not maxW or maxW <= 0 then return text end
  local width = fs:GetStringWidth()
  if not width or width <= maxW then return text end
  local s = text
  while string.len(s) > 1 do
    s = DropLastChar(s)
    fs:SetText(s .. ELLIPSIS)
    width = fs:GetStringWidth()
    if not width or width <= maxW then break end
  end
  return s .. ELLIPSIS
end

local function EntryKey(e, i)
  if type(e.guid) == "string" and e.guid ~= "" then return e.guid end
  if type(e.name) == "string" then return "n:" .. e.name end
  return "i:" .. i
end

local function Ease(cur, target, k)
  return cur + (target - cur) * k
end

-- Columns: "auto" = ceil(n / maxRows) clamped 1..4, else 1..4 fixed.
function NS.ColumnCount(n, maxRows, columns)
  if columns == "auto" or columns == nil then
    return math.max(1, math.min(4, math.ceil((n or 0) / math.max(1, maxRows))))
  end
  local c = tonumber(columns) or 1
  if c < 1 then c = 1 elseif c > 4 then c = 4 end
  return math.floor(c)
end

-- Global ranking across columns plus player pin. Returns visible list and C.
function NS.LayoutEntries(entries, maxRows, columns)
  local C = NS.ColumnCount(#entries, maxRows, columns)
  local N = math.min(maxRows * C, #entries)
  local vis, you, youVisible = {}, nil, false
  local i
  for i = 1, #entries do
    if entries[i].isPlayer then you = entries[i] end
    if i <= N then
      vis[i] = entries[i]
      if entries[i].isPlayer then youVisible = true end
    end
  end
  if you and not youVisible and N > 0 then
    vis[N] = you
    you.pinned = true
  end
  return vis, C
end

local function Step(dt)
  local db = DB()
  local w = db.barWidth or 240
  local full = w - 2
  local k = 1 - math.exp(-EASE_RATE * (dt or 0))
  local moving = false

  if fadeT then
    fadeT = fadeT - (dt or 0)
    if fadeT <= 0 then
      fadeT = nil
      state = {}
      local i
      for i = 1, #rows do rows[i].key = nil; rows[i]:Hide() end
      lastShown = 0
      if not editModeOpen then main:SetAlpha(0) end
      return false
    end
    main:SetAlpha(fadeT / FADE_TIME)
    moving = true
  end

  local i
  for i = 1, #rows do
    local r = rows[i]
    local st = r.key and state[r.key]
    if st and r:IsShown() then
      local tw = st.tfrac * full
      st.w = Ease(st.w, tw, k)
      if math.abs(tw - st.w) < SNAP_PX then st.w = tw else moving = true end
      st.pct = Ease(st.pct, st.tpct, k)
      if math.abs(st.tpct - st.pct) < 0.05 then st.pct = st.tpct else moving = true end
      st.raw = Ease(st.raw, st.traw, k)
      if math.abs(st.traw - st.raw) < 0.5 then st.raw = st.traw else moving = true end

      r.value:SetText(string.format("%.1f%%  %s", st.pct, NS.FormatThreat(st.raw)))
      local vw = r.value.GetStringWidth and r.value:GetStringWidth() or 60
      if not vw or vw <= 0 then vw = 60 end
      if r.lastVW ~= math.floor(vw) then
        r.lastVW = math.floor(vw)
        -- PLAN 8: names get at most barWidth-90, less if the value text is wider.
        local nameW = math.min(w - 90, w - vw - 8)
        r.name:SetWidth(math.max(10, nameW))
        NS.Truncate(r.name, r.label, nameW)
      end
      if st.w < 1 then
        r.fill:Hide(); r.shine:Hide()
      else
        r.fill:Show(); r.shine:Show()
        r.fill:SetWidth(st.w)
      end
    end
  end
  return moving
end

local function AnimOnUpdate(self, elapsed)
  if not Step(elapsed) then
    self:SetScript("OnUpdate", nil)
  end
end

local function StartAnim()
  if not animFrame then animFrame = CreateFrame("Frame") end
  if not animFrame:GetScript("OnUpdate") then
    animFrame:SetScript("OnUpdate", AnimOnUpdate)
  end
end

local function StartFade()
  if lastShown > 0 and not fadeT then
    fadeT = FADE_TIME
    StartAnim()
  end
end

function NS.OnCombatEnd()
  if not NS.forceTest and not NS.apiMissing then StartFade() end
end

local function Render(entries)
  if not main then return end
  local db = DB()
  local maxRows = db.maxRows or 5
  local w = db.barWidth or 240
  local rh = db.rowHeight or 28
  local barH = math.max(8, rh - 14)
  entries = type(entries) == "table" and entries or {}

  if #entries == 0 then
    if lastShown > 0 and not editModeOpen then StartFade() return end
    if not fadeT then
      local i
      for i = 1, #rows do rows[i].key = nil; rows[i]:Hide() end
      main:SetAlpha(editModeOpen and 1 or 0)
    end
    return
  end
  fadeT = nil

  local i
  for i = 1, #entries do entries[i].pinned = nil end
  local vis, C = NS.LayoutEntries(entries, maxRows, db.columns)

  -- Fill scales to the top % (min 100) so over-aggro rows cap at full.
  local top = 100
  for i = 1, #entries do
    local p = entries[i].pct
    if type(p) == "number" and p > top then top = p end
  end

  local live = {}
  local colW = w + COL_GAP
  for i = 1, #vis do
    local r = rows[i] or CreateRow(i)
    local e = vis[i]
    local key = EntryKey(e, i)
    live[key] = true
    local pct = type(e.pct) == "number" and e.pct or 0
    local raw = type(e.raw) == "number" and e.raw or 0
    local frac = pct / top
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local st = state[key]
    if not st then
      st = { w = 0, pct = 0, raw = 0 }
      state[key] = st
    end
    st.tfrac, st.tpct, st.traw = frac, pct, raw

    local col = math.floor((i - 1) / maxRows)
    local slot = (i - 1) % maxRows
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + col * colW, -(HEADER + slot * rh))
    r:SetSize(w, rh)
    r.bar:SetHeight(barH)
    local label = NS.FirstName(e.name)
    if r.key ~= key or r.label ~= label then r.lastVW = nil end
    r.key = key
    r.label = label
    if e.isPlayer then
      r.name:SetTextColor(1, 0.9, 0.64)
      r.hl:Show(); r.border:Show()
    else
      r.name:SetTextColor(0.93, 0.89, 0.8)
      r.hl:Hide(); r.border:Hide()
    end
    local cr, cg, cb = 0.5, 0.56, 0.65
    if db.classColors ~= false then cr, cg, cb = NS.ClassColor(e.class) end
    r.fill:SetVertexColor(cr, cg, cb, 1)
    r:Show()
  end
  for i = #vis + 1, #rows do rows[i].key = nil; rows[i]:Hide() end
  local k
  for k in pairs(state) do
    if not live[k] then state[k] = nil end
  end

  local usedRows = math.min(#vis, maxRows)
  main:SetSize(C * colW - COL_GAP + PAD * 2, HEADER + math.max(1, usedRows) * rh + 4)
  main:SetAlpha(1)
  lastShown = #vis
  Step(0)
  StartAnim()
end

local function LiveVisible()
  if editModeOpen then return true end
  if not (UnitExists and UnitExists("target")) then return false end
  if not (UnitCanAttack and UnitCanAttack("player", "target")) then return false end
  local combat = NS.inCombat
  if type(UnitAffectingCombat) == "function" then
    combat = combat or (UnitAffectingCombat("player") and true or false)
  end
  return combat and true or false
end

function NS.Refresh()
  if not main then return end
  NS.dirty = false
  local ok, entries = pcall(NS.CollectThreat)
  if not ok then entries = {} end
  if not NS.forceTest and not NS.apiMissing and not LiveVisible() then
    entries = {}
  end
  Render(entries)
end

function NS.ApplyLayout()
  if not main then return end
  local lay = NS.Layout and NS.Layout() or {}
  main:ClearAllPoints()
  main:SetPoint(lay.point or "CENTER", UIParent, lay.relativePoint or "CENTER", lay.xOfs or 0, lay.yOfs or 40)
  main:SetScale(lay.scale or 1)
  ApplyDrag()
end

local function Build()
  if main then return end
  main = CreateFrame("Frame", "WoWThreatFrame", UIParent)
  main:SetFrameStrata("MEDIUM")
  main:SetClampedToScreen(true)
  main:SetSize(252, 80)

  local bg = main:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.07, 0.055, 0.06, 0.75)

  title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + 2, -4)
  title:SetText("WoW Threat")

  editHighlight = CreateEditHighlight(main)
  main:SetMovable(false)
  main:EnableMouse(false)
  main:SetScript("OnDragStart", function(self)
    if not DragAllowed() then return end
    dragging = true
    self:StartMoving()
  end)
  main:SetScript("OnDragStop", function(self)
    if not dragging then return end
    dragging = false
    self:StopMovingOrSizing()
    SavePosition()
  end)

  -- Driver: dirty -> refresh at most every 0.2 s; safety poll every 0.5 s;
  -- test mode ticks every 0.1 s.
  main:SetScript("OnUpdate", function(_, elapsed)
    pollAcc = pollAcc + (elapsed or 0)
    local test = NS.forceTest or NS.apiMissing
    if (test and pollAcc >= TEST_TICK)
      or (NS.dirty and pollAcc >= POLL)
      or pollAcc >= SAFETY_POLL then
      pollAcc = 0
      NS.Refresh()
    end
  end)

  BindEditModeSignals()
  NS.ApplyLayout()
  NS.Refresh()
end

function NS.OnDBReady()
  Build()
  NS.ApplyLayout()
end
