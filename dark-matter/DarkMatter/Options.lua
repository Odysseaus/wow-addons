-- Optional entry in the stock Settings panel (AddOns tab): a canvas page with
-- two stock buttons. Registration is deferred one frame with C_Timer.After(0)
-- so it never runs inside Blizzard's own loading code path.
local _, NS = ...

local function Register()
  if NS.settingsCategory then return end
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end

  local panel = CreateFrame("Frame", "DarkMatterOptionsPanel")
  panel.name = "Dark Matter"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Dark Matter " .. NS.version)

  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  sub:SetText("Dark Matter main window, minimap button and probe. Slash command: /dm   (/dm help lists the rest)")

  local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  reset:SetSize(190, 24)
  reset:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
  reset:SetText("Reset window position")
  reset:SetScript("OnClick", function() NS.ResetWindowPosition() end)

  local probe = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  probe:SetSize(190, 24)
  probe:SetPoint("LEFT", reset, "RIGHT", 8, 0)
  probe:SetText("Run probe")
  probe:SetScript("OnClick", function() NS.RunProbe(false) end)

  -- Theme picker (same 10 themes as the window's Settings popover): stock buttons, no dropdown menus.
  -- A click applies the theme live and saves it (DarkMatterDB.theme); the current one stays highlighted.
  local themeHead = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  themeHead:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -24)
  themeHead:SetText("Theme")
  local themeCur = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  themeCur:SetPoint("LEFT", themeHead, "RIGHT", 10, 0)
  local themeBtns = {}
  for i, id in ipairs(NS.themeOrder) do
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(120, 24)
    local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
    b:SetPoint("TOPLEFT", themeHead, "BOTTOMLEFT", col * 126, -10 - row * 30)
    b:SetText(NS.themes[id].name)
    b:SetScript("OnClick", function() NS.SetTheme(id) end)
    b.themeId = id
    themeBtns[#themeBtns + 1] = b
  end
  local themeNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  themeNote:SetPoint("TOPLEFT", themeHead, "BOTTOMLEFT", 0, -76)
  themeNote:SetText("Also in the window's Settings popover, or type /dm theme <name> (or /dm theme next).")
  NS.OnSkin(function()
    themeCur:SetText(NS.theme.name)
    for _, b in ipairs(themeBtns) do
      if b.themeId == NS.theme.id then b:LockHighlight() else b:UnlockHighlight() end
    end
  end)

  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
  NS.settingsCategory = category
end

function NS.RegisterOptions()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() pcall(Register) end)
  end
end

function NS.OpenOptions()
  if InCombatLockdown() then NS.Print("can't open options in combat.") return end
  if NS.settingsCategory and Settings and Settings.OpenToCategory then
    local id = NS.settingsCategory.GetID and NS.settingsCategory:GetID() or NS.settingsCategory
    Settings.OpenToCategory(id)
  else
    NS.Print("Settings page not available on this client.")
  end
end
