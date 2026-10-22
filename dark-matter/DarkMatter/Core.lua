-- Dark Matter 0.4.1 (P2: Journals > Achievements; no restricted events; richer /dm blocked)
-- Namespace, SavedVariables defaults, event wiring. Stock Blizzard controls only;
-- no secure frames, no hooks on Blizzard code, nothing that can taint.
local ADDON, NS = ...
DarkMatter = NS

NS.name = ADDON
NS.version = "0.5.2b.1"
NS.db = nil
NS.sv = { existedAtLoad = false, previousSession = nil }
NS.step = nil -- name of the probe call in progress (set by Probe.lua)

local DEFAULTS = {
  window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
  minimap = { angle = 215, hide = false },
  stockIcon = false,
  theme = "wow",
  tab = "quests",
  section = "adventure", -- 0.4.4: Journals opens on the Adventure Guide unless a last-used subtab is saved
  questCollapsed = {},
  fishingZone = nil,
  fishingView = "waters",
  loadCount = 0,
  -- 0.5.2b
  keepTracked = {},   -- quests kept in the objective tracker across zone changes
  autoTrack = true,   -- zone auto-track (0.5.2b.1: on by default)
  trackOrder = true,  -- 0.5.2b.1: keep the objective tracker in quest-log order
  mlKeys = true,      -- M and L open Dark Matter (ALT-M / ALT-L the game's own windows)
  userPins = {},      -- your own pins on the map
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
  -- 0.5.2b.1: zone auto-track is on by default; 0.5.2b saved it off for everyone, so turn it on once
  if NS.db.autoTrackV ~= 1 then NS.db.autoTrack = true NS.db.autoTrackV = 1 end
  -- 0.5.2b.1: pins start unpinned and change only by a click; 0.5.2b may have pinned on track, so clear them ONCE
  if NS.db.keepV ~= 1 then NS.db.keepTracked = {} NS.db.keepV = 1 end
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

local function ArgStr(v)
  if v == nil then return "nil" end
  if v == "" then return "(empty)" end
  return SafeStr(v)
end

-- Trimmed Lua stack at the moment of the block (the event is synchronous, so the offending addon caller is on it):
-- drops this recorder's own frames, keeps the first 6 lines.
local function StackLines()
  if type(debugstack) ~= "function" then return nil end
  local ok, st = pcall(debugstack, 3, 12, 0)
  if not ok or type(st) ~= "string" then return nil end
  local out = {}
  for line in st:gmatch("[^\n]+") do
    if not line:find("RecordBlocked", 1, true) and not line:find("[C]: in function `pcall'", 1, true) then
      out[#out + 1] = (line:gsub("^Interface[/\\]AddOns[/\\]", ""))
      if #out >= 6 then break end
    end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

local function RecordBlocked(event, addon, func)
  local db = NS.db
  if not db then return end
  local log = db.blockedLog
  if type(log) ~= "table" then log = {} db.blockedLog = log end
  local inCombat
  if InCombatLockdown then local ok, c = pcall(InCombatLockdown) inCombat = ok and c and true or false end
  local stack = StackLines()
  log[#log + 1] = {
    when = date("%Y-%m-%d %H:%M:%S"),
    event = SafeStr(event),
    addon = ArgStr(addon),
    func = ArgStr(func),
    step = NS.step and SafeStr(NS.step) or "none (not during a probe call)",
    ctx = NS.ctx and SafeStr(NS.ctx) or "none",
    combat = inCombat,
    version = NS.version,
    stack = stack,
  }
  while #log > 50 do table.remove(log, 1) end
  if type(db.probe) == "table" then db.probe.blocked = log end
end

-- Chat lines for /dm blocked: the latest entry first, in full (function, event, context, stack), then older ones.
function NS.BlockedLines(maxOlder)
  local log = NS.db and NS.db.blockedLog or {}
  local lines = {}
  lines[1] = #log .. " blocked action(s) logged" .. (#log > 0 and "." or " (none since the log was cleared).")
  local e = log[#log]
  if e then
    lines[#lines + 1] = "last blocked function: " .. tostring(e.func) .. "  (" .. tostring(e.event or "?") .. ", addon "
      .. tostring(e.addon) .. ")"
    lines[#lines + 1] = "  at " .. tostring(e.when) .. (e.version and (" · v" .. tostring(e.version)) or "")
      .. " · combat " .. (e.combat == nil and "?" or (e.combat and "yes" or "no"))
      .. " · ctx " .. tostring(e.ctx or "n/a") .. " · step " .. tostring(e.step)
    if e.stack then
      for l in tostring(e.stack):gmatch("[^\n]+") do lines[#lines + 1] = "    " .. l end
    else
      lines[#lines + 1] = "    (no Lua stack: the call came from the client, not from addon code)"
    end
  end
  for i = #log - 1, math.max(1, #log - (maxOlder or 4)), -1 do
    local o = log[i]
    lines[#lines + 1] = "  earlier: " .. tostring(o.when) .. " " .. tostring(o.func) .. " (" .. tostring(o.event or "?")
      .. ", ctx " .. tostring(o.ctx or "n/a") .. ")"
  end
  return lines
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
    if NS.MapWindow and NS.MapWindow.Watch then NS.MapWindow.Watch() end
    -- 0.5.2b: the tracker overlays (read only) and the M / L keys (override bindings, out of combat)
    if NS.Tracker and NS.Tracker.Start then NS.Tracker.Start() end
    if NS.Keys and NS.Keys.Start then NS.Keys.Start() end
    -- 0.5.1.9: size the metrics to the map window at login, before Dark Matter is first shown
    if NS.MapWindow and NS.MapWindow.Apply and NS.theme and NS.theme.m then pcall(NS.MapWindow.Apply, NS.theme.m) end
    NS.Print("v" .. NS.version .. " loaded. /dm toggles the window, /dm probe checks this client.")
  end
end)
