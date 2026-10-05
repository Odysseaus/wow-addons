local _, NS = ...
QuestGrind = NS

NS.MODES = { "full", "less", "compass" }
NS.db = nil
NS.uiReady = false

local DEFAULTS = {
  mode = "full",
  theme = "default",
  locked = false,
  minimized = false,
  point = "CENTER",
  relativePoint = "CENTER",
  xOfs = 0,
  yOfs = 80,
  scale = 1,
}

local function Print(msg)
  print("|cffd4af37QuestGrind|r " .. tostring(msg))
end
NS.Print = Print

function NS.CopyDefaults()
  if type(QuestGrindDB) ~= "table" then
    QuestGrindDB = {}
  end
  NS.db = QuestGrindDB
  local k, v
  for k, v in pairs(DEFAULTS) do
    if NS.db[k] == nil then
      NS.db[k] = v
    end
  end
  if NS.db.scale < 0.6 then NS.db.scale = 0.6 end
  if NS.db.scale > 1.6 then NS.db.scale = 1.6 end
  local known = false
  local i
  for i = 1, #NS.MODES do
    if NS.MODES[i] == NS.db.mode then known = true end
  end
  if not known then NS.db.mode = "full" end
  if not (NS.THEMES and NS.THEMES[NS.db.theme]) then
    NS.db.theme = "default"
  end
end

function NS.CycleMode()
  if not NS.db then NS.CopyDefaults() end
  local i = 1
  local n
  for n = 1, #NS.MODES do
    if NS.MODES[n] == NS.db.mode then i = n end
  end
  i = i + 1
  if i > #NS.MODES then i = 1 end
  NS.db.mode = NS.MODES[i]
  NS.db.minimized = false
  if NS.ApplyMode then NS.ApplyMode() end
  Print("mode " .. NS.db.mode .. ".")
end

function NS.SetTheme(id)
  if not NS.db then NS.CopyDefaults() end
  if not (NS.THEMES and NS.THEMES[id]) then
    Print("unknown theme: " .. tostring(id))
    return
  end
  NS.db.theme = id
  if NS.ApplyTheme then NS.ApplyTheme() end
  if NS.RefreshEditMode then NS.RefreshEditMode() end
  Print("theme " .. id .. " (applies to Full, Less, and Compass).")
end

function NS.ToggleMinimize()
  if not NS.db then NS.CopyDefaults() end
  NS.db.minimized = not NS.db.minimized
  if NS.ApplyMinimize then NS.ApplyMinimize() end
end

function NS.ToggleLock()
  if not NS.db then NS.CopyDefaults() end
  NS.db.locked = not NS.db.locked
  if NS.ApplyLock then NS.ApplyLock() end
  if NS.db.locked then
    Print("window locked.")
  else
    Print("lock cleared — drag to move.")
  end
end

function NS.ToggleEditMode()
  if NS.editOpen then
    if NS.CloseEditMode then NS.CloseEditMode() end
  else
    if NS.OpenEditMode then NS.OpenEditMode() end
  end
end

function NS.ResetDB()
  QuestGrindDB = {}
  NS.CopyDefaults()
  if NS.ApplyMode then NS.ApplyMode() end
  if NS.ApplyTheme then NS.ApplyTheme() end
  if NS.ApplyMinimize then NS.ApplyMinimize() end
  if NS.ApplyLock then NS.ApplyLock() end
  if NS.RefreshMock then NS.RefreshMock() end
  Print("settings reset.")
end

function NS.ShowHUD()
  if NS.root then NS.root:Show() end
end

function NS.HideHUD()
  if NS.root then NS.root:Hide() end
end

local function SlashHandler(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = string.lower(cmd or "help")
  if cmd == "show" then
    NS.ShowHUD()
  elseif cmd == "hide" then
    NS.HideHUD()
  elseif cmd == "mode" then
    NS.CycleMode()
  elseif cmd == "theme" then
    if rest and rest ~= "" then
      NS.SetTheme(string.lower(rest))
    else
      Print("usage: /qg theme <default|warrior|paladin|hunter|rogue|priest|shaman|mage|warlock|druid>")
    end
  elseif cmd == "edit" then
    NS.ToggleEditMode()
  elseif cmd == "lock" then
    NS.ToggleLock()
  elseif cmd == "ask" then
    if NS.OpenAskSI then NS.OpenAskSI() end
  elseif cmd == "reset" then
    NS.ResetDB()
  elseif cmd == "min" or cmd == "minimize" then
    NS.ToggleMinimize()
  else
    Print("commands: show | hide | mode | theme <id> | edit | lock | ask | min | reset | help")
  end
end

SLASH_QUESTGRIND1 = "/questgrind"
SLASH_QUESTGRIND2 = "/qg"
SlashCmdList.QUESTGRIND = SlashHandler

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == "QuestGrind" then
    NS.CopyDefaults()
  elseif event == "PLAYER_LOGIN" then
    if not NS.db then NS.CopyDefaults() end
    if NS.BuildUI then NS.BuildUI() end
    if NS.ApplyTheme then NS.ApplyTheme() end
    if NS.ApplyMode then NS.ApplyMode() end
    if NS.ApplyMinimize then NS.ApplyMinimize() end
    if NS.ApplyLock then NS.ApplyLock() end
    if NS.RefreshMock then NS.RefreshMock() end
    NS.uiReady = true
    Print("P0 scaffold ready — /qg help. Themes apply to Full/Less/Compass. Ask SI stubs to extend WoWGrok (P2).")
  end
end)
