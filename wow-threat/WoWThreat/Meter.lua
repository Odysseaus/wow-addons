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
local function CreateRow(i)
  local r = CreateFrame("Frame", nil, main)
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
  r:Hide()
  rows[i] = r
  return r
end

local function Ellipsize(fs, text, maxW)
  fs:SetText(text)
  if not fs.GetStringWidth or maxW <= 0 then return end
  if fs:GetStringWidth() <= maxW then return end
  local s = text
  while string.len(s) > 1 and fs:GetStringWidth() > maxW do
    s = string.sub(s, 1, string.len(s) - 1)
    fs:SetText(s .. "...")
  end
end

-- Per-member eased state, keyed by GUID or name so a re-sort keeps easing.
local state = {}
local animFrame = nil
local EASE_RATE = 8
local SNAP_PX = 0.5

local function EntryKey(e, i)
  if type(e.guid) == "string" and e.guid ~= "" then return e.guid end
  if type(e.name) == "string" then return "n:" .. e.name end
  return "i:" .. i
end

local function Ease(cur, target, k)
  return cur + (target - cur) * k
end

-- Apply eased values to the visible rows. Returns true while anything moves.
local function Step(dt)
  local db = DB()
  local w = db.barWidth or 240
  local full = w - 2
  local k = 1 - math.exp(-EASE_RATE * (dt or 0))
  local moving = false
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
        r.name:SetWidth(math.max(10, w - vw - 8))
        Ellipsize(r.name, r.label or "?", w - vw - 8)
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
  if animFrame and not animFrame:GetScript("OnUpdate") then
    animFrame:SetScript("OnUpdate", AnimOnUpdate)
  end
end

local function Render(entries)
  if not main then return end
  local db = DB()
  local maxRows = db.maxRows or 5
  local w = db.barWidth or 240
  local rh = db.rowHeight or 28
  local barH = math.max(8, rh - 14)
  entries = type(entries) == "table" and entries or {}

  -- Collector already sorts descending; scale fill to the top % (min 100).
  local top = 100
  local i
  for i = 1, #entries do
    local p = entries[i].pct
    if type(p) == "number" and p > top then top = p end
  end

  local live = {}
  local shown = math.min(#entries, maxRows)
  for i = 1, maxRows do
    local r = rows[i] or CreateRow(i)
    local e = entries[i]
    if e then
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

      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", main, "TOPLEFT", PAD, -(HEADER + (i - 1) * rh))
      r:SetSize(w, rh)
      r.bar:SetHeight(barH)
      if r.key ~= key then r.lastVW = nil end
      r.key = key
      r.label = NS.FirstName(e.name)
      if e.isPlayer then r.name:SetTextColor(1, 0.9, 0.64) else r.name:SetTextColor(0.93, 0.89, 0.8) end
      local cr, cg, cb = 0.5, 0.56, 0.65
      if db.classColors ~= false then cr, cg, cb = NS.ClassColor(e.class) end
      r.fill:SetVertexColor(cr, cg, cb, 1)
      r:Show()
    else
      r.key = nil
      r:Hide()
    end
  end
  for i = maxRows + 1, #rows do rows[i].key = nil; rows[i]:Hide() end
  local k
  for k in pairs(state) do
    if not live[k] then state[k] = nil end
  end

  main:SetSize(w + PAD * 2, HEADER + math.max(1, shown) * rh + 4)
  if shown == 0 and not editModeOpen then
    main:SetAlpha(0)
  else
    main:SetAlpha(1)
  end
  if shown > 0 then
    Step(0)
    StartAnim()
  end
end

local function PollInterval()
  if NS.forceTest or NS.apiMissing then return 0.1 end
  return POLL
end

function NS.Refresh()
  if not main then return end
  local ok, entries = pcall(NS.CollectThreat)
  if not ok then entries = {} end
  -- Live data only while a hostile target exists; test roster always shows.
  if not NS.forceTest and not NS.apiMissing and not editModeOpen then
    if not (UnitExists and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target")) then
      entries = {}
    end
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

  main:SetScript("OnUpdate", function(_, elapsed)
    pollAcc = pollAcc + (elapsed or 0)
    if pollAcc >= PollInterval() then
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
