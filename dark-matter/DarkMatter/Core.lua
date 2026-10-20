-- Dark Matter 0.4.0 (P2: Journals > Achievements)
-- Namespace, SavedVariables defaults, event wiring. Stock Blizzard controls only;
-- no secure frames, no hooks on Blizzard code, nothing that can taint.
local ADDON, NS = ...
DarkMatter = NS

NS.name = ADDON
NS.version = "0.4.0"
NS.db = nil
NS.sv = { existedAtLoad = false, previousSession = nil }
NS.step = nil -- name of the probe call in progress (set by Probe.lua)

local DEFAULTS = {
  window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
  minimap = { angle = 215, hide = false },
  stockIcon = false,
  theme = "wow",
  tab = "quests",
  section = "fishing",
  questCollapsed = {},
  fishingZone = nil,
  fishingView = "waters",
  loadCount = 0,
}

function NS.Print(msg)
  print("|cff9d7bffDark Matter|r " .. tostring(msg))
end

local function CopyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      CopyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function InitCharDB()
  if type(DarkMatterCharDB) ~= "table" then DarkMatterCharDB = {} end
  NS.cdb = DarkMatterCharDB
  if NS.GetFishingDB then NS.GetFishingDB() end
end

local function InitDB()
  -- Blizzard's beta has been seen not to load SavedVariables at all. Remember
  -- what we found so /dm probe can say whether they came back from disk.
  NS.sv.existedAtLoad = type(DarkMatterDB) == "table"
  if not NS.sv.existedAtLoad then DarkMatterDB = {} end
  NS.db = DarkMatterDB
  NS.sv.previousSession = NS.db.lastSession
  NS.sv.previousLoadCount = NS.db.loadCount
  NS.sv.previousProbeWhen = type(NS.db.probe) == "table" and NS.db.probe.when or nil
  CopyDefaults(NS.db, DEFAULTS)
  if type(NS.db.blockedLog) ~= "table" then NS.db.blockedLog = {} end
  InitCharDB()
  if NS.StartFishingTracker then NS.StartFishingTracker() end
  if NS.AG and NS.AG.StartTracker then NS.AG.StartTracker() end
  if NS.Ach and NS.Ach.Start then NS.Ach.Start() end
  if NS.SetTheme and not NS.SetTheme(NS.db.theme) then NS.db.theme = "wow" end
  NS.db.loadCount = (tonumber(NS.db.loadCount) or 0) + 1
  NS.db.lastSession = date("%Y-%m-%d %H:%M:%S")
  NS.db.addonVersion = NS.version
end

---------------------------------------------------------------------------
-- Blocked-action recorder. ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN are
-- synchronous events, so NS.step still names the probe call that was running.
-- Entries are kept in DarkMatterDB.blockedLog and shown as DarkMatterDB.probe.blocked.
---------------------------------------------------------------------------
local function SafeStr(v)
  if type(issecretvalue) == "function" and issecretvalue(v) then return "secret" end
  return tostring(v)
end

local function RecordBlocked(event, addon, func)
  local db = NS.db
  if not db then return end
  local log = db.blockedLog
  if type(log) ~= "table" then log = {} db.blockedLog = log end
  log[#log + 1] = {
    when = date("%Y-%m-%d %H:%M:%S"),
    event = event,
    addon = SafeStr(addon),
    func = SafeStr(func),
    step = NS.step and SafeStr(NS.step) or "none (not during a probe call)",
  }
  while #log > 50 do table.remove(log, 1) end
  if type(db.probe) == "table" then db.probe.blocked = log end
end

local blockedFrame = CreateFrame("Frame")
pcall(blockedFrame.RegisterEvent, blockedFrame, "ADDON_ACTION_BLOCKED")
pcall(blockedFrame.RegisterEvent, blockedFrame, "ADDON_ACTION_FORBIDDEN")
blockedFrame:SetScript("OnEvent", function(_, event, addon, func)
  pcall(RecordBlocked, event, addon, func)
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    InitDB()
    NS.initialized = true
  elseif event == "PLAYER_LOGIN" then
    if not NS.initialized then InitDB() NS.initialized = true end
    if NS.CreateMinimapButton then NS.CreateMinimapButton() end
    if NS.RegisterOptions then NS.RegisterOptions() end
    NS.Print("v" .. NS.version .. " loaded. /dm toggles the window, /dm probe checks this client.")
  end
end)
