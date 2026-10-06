local _, NS = ...
QuestGrind = NS

NS.MODES = { "full", "less", "compass" }
NS.db = nil
NS.uiReady = false

-- SelectQuestLogEntry fires QUEST_LOG_UPDATE on some clients. Depth-count so a
-- nested select cannot re-enter Refresh, and a nested pop cannot clear early.
local refreshDepth = 0

function NS.PushRefresh()
  refreshDepth = refreshDepth + 1
  NS._refreshing = true
end

function NS.PopRefresh()
  refreshDepth = refreshDepth - 1
  if refreshDepth <= 0 then
    refreshDepth = 0
    NS._refreshing = false
  end
end

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
  if NS._refreshing then
    return NS.liveRoute
  end
  NS.PushRefresh()
  local ok, err = pcall(function()
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
  end)
  NS.PopRefresh()
  if not ok then
    local shown = false
    if type(geterrorhandler) == "function" then
      local handler = geterrorhandler()
      if type(handler) == "function" then
        handler(err)
        shown = true
      end
    end
    if not shown and NS.Print then
      NS.Print("refresh error: " .. tostring(err))
    end
  end
  return NS.liveRoute
end

local MODE_NAMES = { full = "Full", less = "Less", compass = "Compass" }

--- Cycle Full -> Less -> Compass -> Full (step = -1 goes backwards).
--- Always un-minimizes and never hides the HUD, so the player can't get stuck.
function NS.CycleMode(step)
  if not NS.db then NS.CopyDefaults() end
  step = tonumber(step) or 1
  local i = 1
  local n
  for n = 1, #NS.MODES do
    if NS.MODES[n] == NS.db.mode then i = n end
  end
  i = i + step
  if i > #NS.MODES then i = 1 end
  if i < 1 then i = #NS.MODES end
  NS.SetMode(NS.MODES[i])
end

function NS.SetMode(mode)
  if not NS.db then NS.CopyDefaults() end
  mode = string.lower(tostring(mode or "full"))
  if not MODE_NAMES[mode] then
    Print("unknown mode: " .. tostring(mode) .. " (use full, less, or compass).")
    return
  end
  NS.db.mode = mode
  NS.db.minimized = false
  if NS.root and not NS.root:IsShown() then NS.root:Show() end
  if NS.ApplyMode then NS.ApplyMode() end
  Print("mode " .. MODE_NAMES[mode] .. ".")
end

function NS.SetTheme(id)
  if not NS.db then NS.CopyDefaults() end
  id = string.lower(tostring(id or ""))
  if not (NS.THEMES and NS.THEMES[id]) then
    Print("unknown theme: " .. tostring(id))
    return
  end
  -- Always write + full re-paint (even when re-selecting the same id) so a
  -- stuck chrome/panel from a prior switch is corrected immediately.
  NS.db.theme = id
  if NS.ApplyTheme then NS.ApplyTheme() end
  if NS.RefreshEditMode then NS.RefreshEditMode() end
  Print("theme " .. id .. " (applies to Full, Less, and Compass).")
end

function NS.ToggleMinimize()
  if not NS.db then NS.CopyDefaults() end
  NS.db.minimized = not NS.db.minimized
  if NS.root and not NS.root:IsShown() then NS.root:Show() end
  if NS.ApplyMinimize then NS.ApplyMinimize() end
end

function NS.ToggleLock()
  if not NS.db then NS.CopyDefaults() end
  NS.db.locked = not NS.db.locked
  if NS.ApplyLock then NS.ApplyLock() end
  if NS.db.locked then
    Print("window locked.")
  else
    Print("lock cleared — drag the Move grip (or the title) to move.")
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
  if NS.root then
    NS.root:Show()
    -- Re-run layout so controls / mode are always in a sane, visible state.
    if NS.ApplyMode then NS.ApplyMode() end
  end
  if NS.UpdateMapPins then NS.UpdateMapPins(NS.liveRoute) end
end

function NS.HideHUD()
  if NS.root then NS.root:Hide() end
  if NS.ClearMapPins then NS.ClearMapPins() end
  Print("HUD hidden — type /qg show to bring it back.")
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
    if rest and rest ~= "" then
      NS.SetMode(string.lower(rest))
    else
      NS.CycleMode(1)
    end
  elseif cmd == "full" or cmd == "less" or cmd == "compass" then
    NS.SetMode(cmd)
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
  elseif cmd == "expand" then
    if NS.db and NS.db.minimized then NS.ToggleMinimize() else NS.ShowHUD() end
  elseif cmd == "refresh" then
    NS.forceMock = false
    if NS.db then NS.db.forceMock = false end
    -- Explicit refresh drops a /qg next override and reapplies checked/closest.
    NS.manualFocusID = nil
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
    Print("commands: show | hide | mode [full|less|compass] | theme <id> | edit | lock | ask | min | expand | refresh | mock | next | prev | reset | help")
    Print("HUD buttons: Move (drag) | Full/Less/Compass (cycle view mode) | Edit (themes) | Min / Expand | X (hide; /qg show restores). Full mode: Ask SI.")
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
    Print("ready (0.2.3) — HUD buttons: Full/Less/Compass, Edit, Min, X. /qg help. /qg show if hidden. Ask SI stubs (P2).")
  elseif event == "UNIT_QUEST_LOG_CHANGED" then
    if (arg1 == "player" or arg1 == nil) and NS.uiReady and not NS._refreshing then
      NS.Refresh()
    end
  elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN"
      or event == "QUEST_LOG_UPDATE" or event == "PLAYER_ENTERING_WORLD"
      or event == "ZONE_CHANGED_NEW_AREA" then
    if NS.uiReady and not NS._refreshing then NS.Refresh() end
  end
end)
