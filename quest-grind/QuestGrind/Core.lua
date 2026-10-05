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
  forceMock = false,
}

local function Print(msg)
  print("|cffd4af37QuestGrind|r " .. tostring(msg))
end
NS.Print = Print

local function SafeRegister(frame, event)
  if not frame or not event then return false end
  local ok = pcall(function() frame:RegisterEvent(event) end)
  return ok
end

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
  NS.forceMock = NS.db.forceMock and true or false
end

--- Primary refresh: live quest log when available; mock if empty or /qg mock.
function NS.Refresh()
  if NS.db and NS.db.forceMock then
    NS.forceMock = true
  end
  local route
  if NS.forceMock then
    if NS.GetLiveRoute then
      route = NS.GetLiveRoute() -- respects forceMock → mock copy
    end
    if NS.ApplyRoute and route then
      NS.ApplyRoute(route)
    elseif NS.RefreshMock then
      NS.RefreshMock()
    end
  else
    if NS.RefreshLive then
      route = NS.RefreshLive()
    elseif NS.GetLiveRoute and NS.ApplyRoute then
      route = NS.GetLiveRoute()
      NS.ApplyRoute(route)
    elseif NS.RefreshMock then
      NS.RefreshMock()
    end
  end
  if NS.UpdateMapPins then
    NS.UpdateMapPins(NS.liveRoute or route)
  end
  if NS.StartRouteTicker then
    NS.StartRouteTicker()
  end
  if NS.TickRoute then
    NS.TickRoute()
  end
  return route or NS.liveRoute
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

function NS.ToggleMock()
  if not NS.db then NS.CopyDefaults() end
  NS.db.forceMock = not NS.db.forceMock
  NS.forceMock = NS.db.forceMock
  if NS.forceMock then
    Print("mock mode ON — Barrens Loop.")
  else
    Print("mock mode OFF — live quest log.")
  end
  NS.Refresh()
end

function NS.ResetDB()
  QuestGrindDB = {}
  NS.CopyDefaults()
  NS.forceMock = false
  if NS.ApplyMode then NS.ApplyMode() end
  if NS.ApplyTheme then NS.ApplyTheme() end
  if NS.ApplyMinimize then NS.ApplyMinimize() end
  if NS.ApplyLock then NS.ApplyLock() end
  NS.Refresh()
  Print("settings reset.")
end

function NS.ShowHUD()
  if NS.root then NS.root:Show() end
  if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
end

function NS.HideHUD()
  if NS.root then NS.root:Hide() end
  if NS.ClearMapPins then NS.ClearMapPins() end
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
  elseif cmd == "refresh" then
    NS.forceMock = false
    if NS.db then NS.db.forceMock = false end
    NS.Refresh()
    local src = (NS.liveRoute and NS.liveRoute.source) or "?"
    Print("refreshed (" .. tostring(src) .. ").")
  elseif cmd == "mock" then
    NS.ToggleMock()
  elseif cmd == "next" then
    if NS.NextQuest then NS.NextQuest() end
  elseif cmd == "prev" then
    if NS.PrevQuest then NS.PrevQuest() end
  else
    Print("commands: show | hide | mode | theme <id> | edit | lock | ask | min | refresh | mock | next | prev | reset | help")
  end
end

SLASH_QUESTGRIND1 = "/questgrind"
SLASH_QUESTGRIND2 = "/qg"
SlashCmdList.QUESTGRIND = SlashHandler

local ev = CreateFrame("Frame")
SafeRegister(ev, "ADDON_LOADED")
SafeRegister(ev, "PLAYER_LOGIN")
SafeRegister(ev, "PLAYER_ENTERING_WORLD")
SafeRegister(ev, "QUEST_ACCEPTED")
SafeRegister(ev, "QUEST_REMOVED")
SafeRegister(ev, "QUEST_TURNED_IN")
SafeRegister(ev, "QUEST_LOG_UPDATE")
SafeRegister(ev, "UNIT_QUEST_LOG_CHANGED")
SafeRegister(ev, "ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == "QuestGrind" then
    NS.CopyDefaults()
  elseif event == "PLAYER_LOGIN" then
    if not NS.db then NS.CopyDefaults() end
    if NS.BuildUI then NS.BuildUI() end
    if NS.ApplyTheme then NS.ApplyTheme() end
    if NS.ApplyMode then NS.ApplyMode() end
    if NS.ApplyMinimize then NS.ApplyMinimize() end
    if NS.ApplyLock then NS.ApplyLock() end
    NS.Refresh()
    NS.uiReady = true
    Print("P1 live questing ready — /qg help. Live log when available; /qg mock for Barrens Loop. Ask SI stubs (P2).")
  elseif event == "UNIT_QUEST_LOG_CHANGED" then
    if arg1 == "player" or arg1 == nil then
      if NS.uiReady then NS.Refresh() end
    end
  elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN"
      or event == "QUEST_LOG_UPDATE" or event == "PLAYER_ENTERING_WORLD"
      or event == "ZONE_CHANGED_NEW_AREA" then
    if NS.uiReady then NS.Refresh() end
  end
end)
