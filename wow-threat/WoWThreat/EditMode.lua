-- WoWThreat Edit Mode settings dialog (Phase 5). Addon-owned frame styled
-- like EditModeSystemSettingsDialog. Opened by clicking the selection while
-- Edit Mode is open; hidden on Exit. Never touches secure Edit Mode code.
local _, NS = ...

local dialog
local W, H = 300, 236

local function DB()
  if not NS.db and NS.MigrateDB then NS.MigrateDB() end
  return NS.db or {}
end

local function Apply()
  if NS.Refresh then NS.Refresh() end
end

local function Border(f, r, g, b, a, size)
  local spec = {
    { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
  }
  local i
  for i = 1, 4 do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, a)
    t:SetPoint(spec[i][1], f, spec[i][1], 0, 0)
    t:SetPoint(spec[i][2], f, spec[i][2], 0, 0)
    if spec[i][3] then t:SetHeight(size) else t:SetWidth(size) end
  end
end

-- Plain slider (no template dependency).
local function MakeSlider(parent, label, minV, maxV, step, y, fmt, get, set)
  local row = CreateFrame("Frame", nil, parent)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, y)
  row:SetHeight(32)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.text:SetText(label)
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)

  local s = CreateFrame("Slider", nil, row)
  s:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
  s:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
  s:SetHeight(14)
  s:SetOrientation("HORIZONTAL")
  s:SetMinMaxValues(minV, maxV)
  if s.SetValueStep then s:SetValueStep(step) end
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouse(true)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", s, "LEFT", 0, 0)
  track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
  track:SetHeight(4)
  track:SetColorTexture(0.2, 0.2, 0.22, 1)
  local thumb = s:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(10, 14)
  thumb:SetColorTexture(1, 0.82, 0.2, 1)
  s:SetThumbTexture(thumb)

  row.Sync = function()
    local v = get()
    row.syncing = true
    s:SetValue(v)
    row.syncing = false
    row.value:SetText(string.format(fmt, v))
  end
  s:SetScript("OnValueChanged", function(_, v)
    if row.syncing then return end
    v = math.floor(v / step + 0.5) * step
    if v < minV then v = minV elseif v > maxV then v = maxV end
    set(v)
    row.value:SetText(string.format(fmt, v))
  end)
  s:SetScript("OnMouseWheel", function(_, d)
    local v = get() + (d > 0 and step or -step)
    if v < minV then v = minV elseif v > maxV then v = maxV end
    set(v)
    row.Sync()
  end)
  if s.EnableMouseWheel then s:EnableMouseWheel(true) end
  row.slider = s
  return row
end

local function MakeButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 22)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0.16, 0.12, 0.08, 1)
  Border(b, 0.55, 0.43, 0.18, 1, 1)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetAllPoints()
  b.hl:SetColorTexture(1, 0.82, 0.3, 0.15)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("CENTER")
  b.text:SetText(text)
  return b
end

local COLUMNS = { "auto", 1, 2, 3, 4 }

local function ColumnsLabel(v)
  if v == "auto" or v == nil then return "Columns: Auto" end
  return "Columns: " .. tostring(v)
end

local function Build()
  if dialog then return dialog end
  dialog = CreateFrame("Frame", "WoWThreatEditDialog", UIParent)
  dialog:SetSize(W, H)
  dialog:SetFrameStrata("DIALOG")
  dialog:SetClampedToScreen(true)
  dialog:EnableMouse(true)
  local bg = dialog:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.06, 0.07, 0.94)
  Border(dialog, 0.45, 0.45, 0.5, 1, 2)

  local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", dialog, "TOP", 0, -12)
  title:SetText("WoW Threat")

  local close = MakeButton(dialog, "X", 22)
  close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() dialog:Hide() end)

  dialog.rows = {}
  dialog.rows[1] = MakeSlider(dialog, "Scale", 0.6, 1.6, 0.05, -36, "%.2f",
    function() return (NS.Layout().scale or 1) end,
    function(v) if NS.SetScale then NS.SetScale(v) end; Apply(); NS.AnchorDialog() end)
  dialog.rows[2] = MakeSlider(dialog, "Max rows", 1, 10, 1, -72, "%d",
    function() return DB().maxRows or 5 end,
    function(v) DB().maxRows = v; Apply() end)
  dialog.rows[3] = MakeSlider(dialog, "Bar width", 160, 320, 4, -108, "%d",
    function() return DB().barWidth or 240 end,
    function(v) DB().barWidth = v; Apply() end)

  local cols = MakeButton(dialog, ColumnsLabel(DB().columns), W - 32)
  cols:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -152)
  cols:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  cols:SetScript("OnClick", function(_, button)
    local db = DB()
    local idx = 1
    local i
    for i = 1, #COLUMNS do if COLUMNS[i] == db.columns then idx = i end end
    idx = idx + ((button == "RightButton") and -1 or 1)
    if idx > #COLUMNS then idx = 1 elseif idx < 1 then idx = #COLUMNS end
    db.columns = COLUMNS[idx]
    cols.text:SetText(ColumnsLabel(db.columns))
    Apply()
  end)
  dialog.cols = cols

  local reset = MakeButton(dialog, "Reset position", W - 32)
  reset:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -186)
  reset:SetScript("OnClick", function()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
      NS.Print("can't move the meter in combat.")
      return
    end
    if NS.ResetPosition then NS.ResetPosition() end
    dialog.Sync()
  end)

  dialog.Sync = function()
    local i
    for i = 1, #dialog.rows do dialog.rows[i].Sync() end
    cols.text:SetText(ColumnsLabel(DB().columns))
  end
  dialog:Hide()
  return dialog
end

function NS.AnchorDialog()
  if not dialog or not dialog:IsShown() then return end
  local main = NS.MainFrame and NS.MainFrame()
  if not main then return end
  dialog:ClearAllPoints()
  local right = main:GetRight()
  local screenW = UIParent:GetWidth()
  local ms = main:GetEffectiveScale() or 1
  local us = UIParent:GetEffectiveScale() or 1
  if right and screenW and right * ms / us + W + 20 > screenW then
    dialog:SetPoint("TOPRIGHT", main, "TOPLEFT", -12, 0)
  else
    dialog:SetPoint("TOPLEFT", main, "TOPRIGHT", 12, 0)
  end
end

function NS.ShowDialog()
  if not (NS.IsEditMode and NS.IsEditMode()) then return end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    NS.Print("settings are unavailable in combat.")
    return
  end
  Build()
  dialog.Sync()
  dialog:Show()
  NS.AnchorDialog()
end

function NS.HideDialog()
  if dialog then dialog:Hide() end
end

function NS.ToggleDialog()
  if dialog and dialog:IsShown() then
    dialog:Hide()
  else
    NS.ShowDialog()
  end
end
