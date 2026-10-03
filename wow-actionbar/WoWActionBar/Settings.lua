local _, NS = ...
if type(NS) ~= "table" then
  WoWActionBarNS = WoWActionBarNS or {}
  NS = WoWActionBarNS
end
local WA = WoWActionBar

local LABELS = { heal = "Healing", instant = "Instants", cast = "Cast time", food = "Food and drink" }

local function checkbox(parent, text, x, y)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", x, y)
  cb:SetSize(24, 24)
  local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  fs:SetText(text)
  cb.label = fs
  return cb
end

function NS.BuildSettings()
  if NS.panel then return NS.panel end
  local f = CreateFrame("Frame", "WoWActionBarSettings", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(340, 390)
  f:SetPoint("CENTER")
  f:Hide()
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.TitleText then f.TitleText:SetText("WoW Action Bar") end
  tinsert(UISpecialFrames, "WoWActionBarSettings")

  local gapLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  gapLabel:SetPoint("TOPLEFT", 16, -36)
  gapLabel:SetText("Empty slots between groups (0-3)")

  local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  edit:SetSize(40, 20)
  edit:SetPoint("LEFT", gapLabel, "RIGHT", 8, 0)
  edit:SetAutoFocus(false)
  edit:SetNumeric(true)
  edit:SetMaxLetters(1)
  f.gap = edit

  local y = -68
  f.bars = {}
  for i = 1, #NS.BARS do
    local b = NS.BARS[i]
    local cb = checkbox(f, b.label, 16, y)
    f.bars[b.key] = cb
    y = y - 26
  end

  local lock = checkbox(f, "Lock (stop reshuffling)", 16, y)
  f.lock = lock
  y = y - 32

  local orderLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  orderLabel:SetPoint("TOPLEFT", 16, y)
  orderLabel:SetText("Group order")
  f.orderText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.orderText:SetPoint("TOPLEFT", 16, y - 18)
  f.orderText:SetJustifyH("LEFT")

  local function move(dir)
    local db = WA.EnsureDB()
    -- selection stored on f.sel
    local sel = f.sel or 1
    local j = sel + dir
    if j < 1 or j > #db.order then return end
    db.order[sel], db.order[j] = db.order[j], db.order[sel]
    f.sel = j
    NS.RefreshSettings()
  end

  local up = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  up:SetSize(70, 22)
  up:SetPoint("BOTTOMLEFT", 16, 54)
  up:SetText("Up")
  up:SetScript("OnClick", function() move(-1) end)

  local down = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  down:SetSize(70, 22)
  down:SetPoint("LEFT", up, "RIGHT", 8, 0)
  down:SetText("Down")
  down:SetScript("OnClick", function() move(1) end)

  local org = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  org:SetSize(140, 22)
  org:SetPoint("BOTTOMRIGHT", -16, 16)
  org:SetText("Organize now")
  org:SetScript("OnClick", function()
    local db = WA.EnsureDB()
    NS.ReadSettings()
    if db.locked then
      NS.Say("Unlock first.")
      return
    end
    WA.Organize(true)
  end)

  local function save()
    NS.ReadSettings()
  end
  edit:SetScript("OnEnterPressed", function(self) save(); self:ClearFocus() end)
  edit:SetScript("OnEditFocusLost", save)
  for _, cb in pairs(f.bars) do
    cb:SetScript("OnClick", save)
  end
  lock:SetScript("OnClick", save)

  NS.panel = f
  return f
end

function NS.ReadSettings()
  local f = NS.panel
  if not f then return end
  local db = WA.EnsureDB()
  local g = tonumber(f.gap:GetText())
  if g == nil then g = db.gap or 1 end
  if g < 0 then g = 0 end
  if g > 3 then g = 3 end
  db.gap = g
  for key, cb in pairs(f.bars) do
    db.bars[key] = cb:GetChecked() and true or false
  end
  db.locked = f.lock:GetChecked() and true or false
end

function NS.RefreshSettings()
  local f = NS.BuildSettings()
  local db = WA.EnsureDB()
  f.gap:SetText(tostring(db.gap or 1))
  for key, cb in pairs(f.bars) do
    cb:SetChecked(db.bars[key] and true or false)
  end
  f.lock:SetChecked(db.locked and true or false)
  local lines = {}
  for i = 1, #db.order do
    local mark = (f.sel == i) and "> " or "  "
    lines[#lines + 1] = mark .. i .. ". " .. (LABELS[db.order[i]] or db.order[i])
  end
  f.orderText:SetText(table.concat(lines, "\n"))
end

function NS.ToggleSettings()
  local f = NS.BuildSettings()
  if f:IsShown() then
    NS.ReadSettings()
    f:Hide()
  else
    NS.RefreshSettings()
    f:Show()
  end
end

local btn = CreateFrame("Button", "WoWActionBarToggle", UIParent, "UIPanelButtonTemplate")
btn:SetSize(36, 22)
btn:SetText("WA")
if MainMenuBar then
  btn:SetPoint("LEFT", MainMenuBar, "RIGHT", 6, 0)
else
  btn:SetPoint("BOTTOM", UIParent, "BOTTOM", 220, 40)
end
btn:SetScript("OnClick", function() NS.ToggleSettings() end)
