-- WoWThreat Options > AddOns panel (Phase 6). Vertical-layout category with
-- proxy/addon settings (11.x and older signatures probed with pcall), and a
-- canvas fallback built from plain widgets. Every write goes through
-- NS.SetOption so the Edit Mode dialog and this panel stay in sync.
local _, NS = ...

local CATEGORY_NAME = "WoW Threat"
local category, layout
local settings = {}   -- key -> Blizzard setting object (vertical layout)
local shadow = {}     -- variable table for the RegisterAddOnSetting paths
local syncing = false
local canvas = nil

-- Settings values <-> DB values. Columns and number format are strings.
local function ToSetting(key, v)
  if key == "columns" then return tostring(v or "auto") end
  return v
end

local function FromSetting(key, v)
  if key == "columns" then
    if v == "auto" then return "auto" end
    return tonumber(v) or "auto"
  end
  return v
end

local function VarType(kind)
  local vt = Settings and Settings.VarType
  if kind == "number" then return (vt and vt.Number) or "number" end
  if kind == "boolean" then return (vt and vt.Boolean) or "boolean" end
  return (vt and vt.String) or "string"
end

-- Register one setting; returns the setting object or nil.
local function Register(key, kind, name, default)
  local variable = "WoWThreat_" .. key
  local vtype = VarType(kind)
  local function get() return ToSetting(key, NS.GetOption(key)) end
  local function set(v)
    if syncing then return end
    NS.SetOption(key, FromSetting(key, v), "settings")
  end
  local setting

  -- 1) Proxy setting (10.1+/11.x): getter/setter straight into NS options.
  if type(Settings.RegisterProxySetting) == "function" then
    local ok, s = pcall(Settings.RegisterProxySetting, category, variable, vtype, name, default, get, set)
    if ok and s then setting = s end
  end
  -- 2) 11.x RegisterAddOnSetting(category, variable, variableKey, variableTbl, type, name, default)
  if not setting and type(Settings.RegisterAddOnSetting) == "function" then
    shadow[key] = get()
    local ok, s = pcall(Settings.RegisterAddOnSetting, category, variable, key, shadow, vtype, name, default)
    -- Accept only if the object really is our variable (an older client
    -- would read these arguments in a different order).
    local valid = ok and type(s) == "table"
    if valid and s.GetVariable then
      local okV, var = pcall(s.GetVariable, s)
      valid = okV and var == variable
    end
    if valid then
      setting = s
    else
      -- 3) older RegisterAddOnSetting(category, name, variable, type, default)
      ok, s = pcall(Settings.RegisterAddOnSetting, category, name, variable, vtype, default)
      if ok and s and type(s) == "table" then
        setting = s
        pcall(s.SetValue, s, get())
      end
    end
    if setting then
      local cb = function(_, s2, v)
        if type(s2) ~= "table" then v = s2 end
        set(v)
      end
      if not (type(Settings.SetOnValueChangedCallback) == "function"
          and pcall(Settings.SetOnValueChangedCallback, variable, function(_, s2, v) set(v) end)) then
        if setting.SetValueChangedCallback then pcall(setting.SetValueChangedCallback, setting, cb) end
      end
    end
  end
  if setting then settings[key] = setting end
  return setting
end

local function AddSlider(key, name, minV, maxV, step, fmt, tip)
  local s = Register(key, "number", name, NS.GetOption(key))
  if not s then return false end
  local ok = pcall(function()
    local opts = Settings.CreateSliderOptions(minV, maxV, step)
    if opts.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
      opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return string.format(fmt, v) end)
    end
    Settings.CreateSlider(category, s, opts, tip)
  end)
  return ok
end

local function AddCheckbox(key, name, tip)
  local s = Register(key, "boolean", name, NS.GetOption(key) and true or false)
  if not s then return false end
  local create = Settings.CreateCheckbox or Settings.CreateCheckBox
  return create and pcall(create, category, s, tip) or false
end

local function AddDropdown(key, name, choices, tip)
  local s = Register(key, "string", name, ToSetting(key, NS.GetOption(key)))
  if not s then return false end
  local create = Settings.CreateDropdown or Settings.CreateDropDown
  if not create then return false end
  local function options()
    local c = Settings.CreateControlTextContainer()
    local i
    for i = 1, #choices do c:Add(choices[i][1], choices[i][2]) end
    return c:GetData()
  end
  return pcall(create, category, s, options, tip)
end

local COLUMN_CHOICES = { { "auto", "Auto" }, { "1", "1" }, { "2", "2" }, { "3", "3" }, { "4", "4" } }
local FORMAT_CHOICES = { { "short", "Short (12.3k)" }, { "full", "Full (12345)" } }

local function ResetPositionClicked()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    NS.Print("can't move the meter in combat.")
    return
  end
  if NS.ResetPosition then NS.ResetPosition() end
  NS.NotifyOption("scale", "reset")
  NS.Print("position reset.")
end

local function BuildVertical()
  local ok, cat, lay = pcall(Settings.RegisterVerticalLayoutCategory, CATEGORY_NAME)
  if not ok or not cat then return false end
  category, layout = cat, lay
  local all = true
  all = AddSlider("maxRows", "Max rows", 1, 10, 1, "%d", "Rows per column.") and all
  all = AddDropdown("columns", "Columns", COLUMN_CHOICES, "Auto uses as many columns as the group needs (max 4, capped to 60% of the screen).") and all
  all = AddSlider("barWidth", "Bar width", 160, 320, 4, "%d", "Width of each bar in pixels.") and all
  all = AddSlider("rowHeight", "Row height", 20, 32, 1, "%d", "Height of each row in pixels.") and all
  all = AddSlider("scale", "Scale", 0.6, 1.6, 0.05, "%.2f", "Meter scale for the active Edit Mode layout.") and all
  all = AddCheckbox("showFire", "Show fire", "Fire effect inside the bars.") and all
  all = AddSlider("fireIntensity", "Fire intensity", 0, 1, 0.05, "%.2f", "Fire brightness.") and all
  all = AddCheckbox("showPop", "Show pop", "Flash and glow when a new player takes the top spot.") and all
  all = AddDropdown("numberFormat", "Number format", FORMAT_CHOICES, "How raw threat is shown.") and all
  all = AddCheckbox("onlyInGroup", "Show only in group", "Hide live rows while solo.") and all
  all = AddCheckbox("hideOutOfCombat", "Hide out of combat", "Fade rows out when combat ends.") and all
  all = AddCheckbox("classColors", "Class colors", "Color bars by class.") and all
  all = AddCheckbox("testMode", "Test mode", "Show the fake roster (same as /wtm test).") and all
  if not all then return false end

  -- Reset position button.
  local added = false
  if type(CreateSettingsButtonInitializer) == "function" and layout and layout.AddInitializer then
    added = pcall(function()
      local init = CreateSettingsButtonInitializer("Reset position", "Reset", ResetPositionClicked,
        "Move the meter back to the default spot for this Edit Mode layout.", true)
      layout:AddInitializer(init)
    end)
  end
  NS.resetHint = not added -- /wtm reset is the fallback

  local regOk = pcall(Settings.RegisterAddOnCategory, category)
  return regOk
end

-- --------------------------------------------------------------- canvas
local function CanvasCheck(parent, label, key, y)
  local b = NS.MakeButton(parent, "", 280)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
  b.Sync = function()
    b.text:SetText(label .. ": " .. (NS.GetOption(key) and "On" or "Off"))
  end
  b:SetScript("OnClick", function()
    NS.SetOption(key, not NS.GetOption(key), "settings")
    b.Sync()
  end)
  return b
end

local function CanvasCycle(parent, label, key, choices, y)
  local b = NS.MakeButton(parent, "", 280)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
  b.Sync = function()
    local cur = ToSetting(key, NS.GetOption(key))
    local text = cur
    local i
    for i = 1, #choices do if choices[i][1] == cur then text = choices[i][2] end end
    b.text:SetText(label .. ": " .. tostring(text))
  end
  b:SetScript("OnClick", function()
    local cur = ToSetting(key, NS.GetOption(key))
    local idx = 1
    local i
    for i = 1, #choices do if choices[i][1] == cur then idx = i end end
    idx = idx % #choices + 1
    NS.SetOption(key, FromSetting(key, choices[idx][1]), "settings")
    b.Sync()
  end)
  return b
end

local function BuildCanvas()
  if not (NS.MakeSliderRow and NS.MakeButton) then return false end
  canvas = CreateFrame("Frame", "WoWThreatOptionsCanvas", UIParent)
  canvas:Hide()
  canvas.name = CATEGORY_NAME
  canvas.widgets = {}
  local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16)
  title:SetText(CATEGORY_NAME)
  local y = -48
  local function slider(label, key, a, b, step, fmt)
    local r = NS.MakeSliderRow(canvas, label, a, b, step, y, fmt,
      function() return NS.GetOption(key) end,
      function(v) NS.SetOption(key, v, "settings") end)
    r:SetWidth(300)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, y)
    r:SetWidth(300)
    canvas.widgets[#canvas.widgets + 1] = r
    y = y - 38
  end
  local function add(w) canvas.widgets[#canvas.widgets + 1] = w; y = y - 28 end
  slider("Max rows", "maxRows", 1, 10, 1, "%d")
  add(CanvasCycle(canvas, "Columns", "columns", COLUMN_CHOICES, y))
  slider("Bar width", "barWidth", 160, 320, 4, "%d")
  slider("Row height", "rowHeight", 20, 32, 1, "%d")
  slider("Scale", "scale", 0.6, 1.6, 0.05, "%.2f")
  add(CanvasCheck(canvas, "Show fire", "showFire", y))
  slider("Fire intensity", "fireIntensity", 0, 1, 0.05, "%.2f")
  add(CanvasCheck(canvas, "Show pop", "showPop", y))
  add(CanvasCycle(canvas, "Number format", "numberFormat", FORMAT_CHOICES, y))
  add(CanvasCheck(canvas, "Show only in group", "onlyInGroup", y))
  add(CanvasCheck(canvas, "Hide out of combat", "hideOutOfCombat", y))
  add(CanvasCheck(canvas, "Class colors", "classColors", y))
  add(CanvasCheck(canvas, "Test mode", "testMode", y))
  local reset = NS.MakeButton(canvas, "Reset position", 280)
  reset:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, y)
  reset:SetScript("OnClick", ResetPositionClicked)
  canvas:SetScript("OnShow", function()
    local i
    for i = 1, #canvas.widgets do canvas.widgets[i].Sync() end
  end)

  if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" then
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, canvas, CATEGORY_NAME)
    if ok and cat then
      category = cat
      return pcall(Settings.RegisterAddOnCategory, cat)
    end
  end
  if type(InterfaceOptions_AddCategory) == "function" then
    return pcall(InterfaceOptions_AddCategory, canvas)
  end
  return false
end

-- --------------------------------------------------------------- sync
local function SyncFromOutside(key, value, source)
  if source == "settings" and key ~= "scale" then return end
  if canvas and canvas:IsShown() then
    local i
    for i = 1, #canvas.widgets do canvas.widgets[i].Sync() end
  end
  local s = settings[key]
  if not s then return end
  local v = ToSetting(key, value)
  syncing = true
  shadow[key] = v
  if type(Settings.NotifyUpdate) == "function" then
    pcall(Settings.NotifyUpdate, "WoWThreat_" .. key)
  end
  if s.GetValue and s.SetValue then
    local okGet, cur = pcall(s.GetValue, s)
    if not okGet or cur ~= v then pcall(s.SetValue, s, v) end
  elseif s.NotifyUpdate then
    pcall(s.NotifyUpdate, s)
  end
  syncing = false
end

function NS.BuildSettings()
  if NS.settingsBuilt then return end
  NS.settingsBuilt = true
  local ok = false
  if type(Settings) == "table" and type(Settings.RegisterVerticalLayoutCategory) == "function" then
    local pok, res = pcall(BuildVertical)
    ok = pok and res
    if not ok then
      settings = {}
      category, layout = nil, nil
    end
  end
  if not ok then
    local pok, res = pcall(BuildCanvas)
    ok = pok and res
    NS.settingsMode = ok and "canvas" or "none"
  else
    NS.settingsMode = "vertical"
  end
  NS.OnOptionChanged(SyncFromOutside)
end

function NS.OpenOptions()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    NS.Print("options are unavailable in combat.")
    return
  end
  if not category and not canvas then
    NS.Print("options panel unavailable; use /wtm commands.")
    return
  end
  if category and Settings and type(Settings.OpenToCategory) == "function" then
    local id = category.GetID and category:GetID() or category.ID
    if pcall(Settings.OpenToCategory, id) then return end
  end
  if canvas and type(InterfaceOptionsFrame_OpenToCategory) == "function" then
    pcall(InterfaceOptionsFrame_OpenToCategory, canvas)
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
  if name ~= "WoWThreat" then return end
  self:UnregisterEvent("ADDON_LOADED")
  if NS.MigrateDB and not NS.db then NS.MigrateDB() end
  NS.BuildSettings()
end)
