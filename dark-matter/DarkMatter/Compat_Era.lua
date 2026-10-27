-- Compat_Era.lua: 0.5.2b.9. Loaded ONLY by DarkMatter_Vanilla.toc (WoW Classic Era 1.15.x, Interface 11509), last in
-- the list; WoW Forever (DarkMatter.toc) never loads this file. Classic Era is a test bench for the shared map code
-- while the Forever beta is down, so this file stays small: it marks the flavor, drops the Forever-only zones from
-- Dark Matter's own data when the game does not have them, and switches off the parts that need Forever-only game
-- systems (waypoints / super tracking, the objective tracker overlays, the game's achievements). No Classic quest
-- helper. Read only toward the game: nothing here calls a state-changing API.
local _, NS = ...

local function N(v) if type(v) == "number" and v == v then return v end end
local build, interface = nil, nil
if type(GetBuildInfo) == "function" then
  local ok, v, _, _, toc = pcall(GetBuildInfo)
  if ok then build, interface = v, N(toc) end
end
local project = N(rawget(_G, "WOW_PROJECT_ID"))
-- WOW_PROJECT_CLASSIC = 2 (Blizzard_FrameXMLBase/Vanilla/Constants.lua); Classic Era interface numbers are 11xxx
local isEra = project == 2 or (project == nil and interface ~= nil and interface >= 11000 and interface < 20000)
if not isEra then return end -- a client that loaded this file but is not Classic Era: change nothing

NS.IsEra = true
NS.Era = { project = project, interface = interface, build = build, dropped = {}, off = {} }
local E = NS.Era

-- 1. Forever-only zones (Mount Hyjal, Riverglades, Shen'dralas, Zephras Isle): out of Dark Matter's own tables when
-- the game does not know the map. The map tree itself comes from the game, so these never show as zones anyway.
E.FOREVER_ZONES = { [2482] = "mount hyjal", [2548] = "riverglades", [2652] = "shen'dralas" }
E.FOREVER_NAMES = { "zephras isle" } -- no known mapID: looked up by name among the game's maps
local function MapKnown(id)
  if not (C_Map and type(C_Map.GetMapInfo) == "function") then return nil end -- cannot tell: keep the data
  local ok, info = pcall(C_Map.GetMapInfo, id)
  return ok and type(info) == "table"
end
local function NameKnown(name)
  if not (C_Map and type(C_Map.GetMapChildrenInfo) == "function") then return nil end
  local ok, list = pcall(C_Map.GetMapChildrenInfo, 947, nil, true)
  if not ok or type(list) ~= "table" then return nil end
  for _, m in ipairs(list) do
    if type(m) == "table" and type(m.name) == "string" and m.name:lower():gsub("^the ", "") == name then return true end
  end
  return false
end
function E.DropForeverZones()
  local gone = {}
  for id, name in pairs(E.FOREVER_ZONES) do if MapKnown(id) == false then gone[id] = name end end
  if type(NS.ZoneMasks) == "table" then
    for id in pairs(gone) do NS.ZoneMasks[id] = nil end
  end
  if type(NS.ZoneSeams) == "table" then
    for _, list in pairs(NS.ZoneSeams) do
      if type(list) == "table" then
        for i = #list, 1, -1 do
          local s = list[i]
          if type(s) == "table" and (gone[s[1]] or gone[s[2]]) then table.remove(list, i) end
        end
      end
    end
  end
  local badges = type(NS.ZoneLevels) == "table" and type(NS.ZoneLevels.zones) == "table" and NS.ZoneLevels.zones
  if badges then
    for id, name in pairs(gone) do badges[name] = nil end
    for _, name in ipairs(E.FOREVER_NAMES) do
      if NameKnown(name) == false then badges[name] = nil gone[name] = name end
    end
  end
  local out = {}
  for k in pairs(gone) do out[#out + 1] = tostring(k) end
  table.sort(out)
  E.dropped = out
  return out
end
E.DropForeverZones()

-- 2. Forever-only systems: off, cleanly (each switch is logged in NS.Era.off for /dm probe)
local function Off(what) E.off[#E.off + 1] = what end
local QS = NS.QS
if type(QS) == "table" then
  -- no C_Map user waypoints, no C_SuperTrack, no C_Navigation on Classic Era
  QS.CanWaypoint = function() return false end
  QS.SetWaypoint = function() return false end
  QS.ClearWaypoint = function() return false end
  QS.TrackQuest = function() return false end
  Off("waypoints / super tracking")
end
local Tr = NS.Tracker
if type(Tr) == "table" then
  -- Classic Era has no ObjectiveTrackerFrame (its quest watch is QuestWatchFrame): no overlays, no auto-track, no
  -- watch re-ordering; the tracker frame is never started
  Tr.Start = function() Tr.eraOff = true end
  Tr.Tick = function() end
  Tr.Report = function() return { "trackerprobe " .. tostring(NS.version) .. " (read-only)", "tracker: off on Classic Era (no objective tracker; Classic Era is a test bench for the map)" } end
  Off("objective tracker overlays, zone auto-track, watch order")
end
local ACH = NS.Ach
if type(ACH) == "table" then
  -- no achievement system in Classic Era (Blizzard_AchievementUI loads only on TBC / Wrath): Dark Matter's own only
  ACH.ApiPresent = function() return false end
  if ACH.InvalidateGame then pcall(ACH.InvalidateGame) end
  Off("game achievements (Dark Matter's own still work)")
end
Off("Encounter Journal (no Journal on Classic Era; the Adventure Guide uses Dark Matter's own seed list)")

-- 3. /dm probe: say which client this is, in chat as well as in DarkMatterDB.probe.client
function E.Line()
  return string.format("client: Classic Era %s, interface %s, WOW_PROJECT_ID %s; Forever-only zones dropped: %s; off: %s",
    tostring(E.build), tostring(E.interface), tostring(E.project), #E.dropped > 0 and table.concat(E.dropped, ", ") or "none",
    table.concat(E.off, "; "))
end
if type(NS.RunProbe) == "function" then
  local run = NS.RunProbe
  NS.RunProbe = function(quiet, ...)
    local out = run(quiet, ...)
    if type(out) == "table" then
      out.era = { project = E.project, interface = E.interface, build = E.build, dropped = E.dropped, off = E.off }
      if not quiet then print("  " .. E.Line()) end
    end
    return out
  end
end
