-- 0.5.2a shared quest state: one place the Quests tab and the Map tab read and write, so they stay in step.
--   selected  the quest picked in the Quests tab or by clicking its marker on the map
--   hovered   the quest under the mouse (a Quests-tab row or a map marker) and where the hover came from
--   arrow     what the game's own arrow points at, when Dark Matter set it (a quest location, or the quest itself)
--   watched   read straight from the game's watch list (QuestLog.lua), never cached here
-- Also: the quest status (ready to turn in / in progress / failed), where a quest is on the map (game data only:
-- GetQuestUiMapID, C_QuestLog.GetQuestsOnMap, C_QuestLog.GetNextWaypoint, the quest log's zone header), the game's
-- own icon for each status (atlas or file path, checked on this client, never bundled), the game's user waypoint and
-- super-track arrow, and /dm questmap (a read-only probe).
-- Taint-safe: no hooks, no LoadAddOn, nothing of Blizzard's is written; the waypoint and arrow calls are the game's
-- public ones, made only on a click; watch-list changes go through QL.SetWatched (queued while in combat).
local _, NS = ...
local QS = { listeners = {} }
NS.QS = QS

local function Get(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end
local function Fn(path) local f = Get(path) if type(f) == "function" then return f end end
local function Call(path, ...) local f = Fn(path) if not f then return end local r = { pcall(f, ...) } if r[1] then return select(2, unpack(r)) end end
local function N(v) return NS.Num(v) end
QS.Fn, QS.Call = Fn, Call

---------------------------------------------------------------------------
-- listeners: fn(what, questID, src) where what is "select", "hover" or "arrow"
---------------------------------------------------------------------------
function QS.On(fn) QS.listeners[#QS.listeners + 1] = fn end
local function Fire(what, q, src)
  for _, fn in ipairs(QS.listeners) do pcall(fn, what, q, src) end
end
function QS.Select(q, src)
  q = N(q)
  QS.selected, QS.selectSrc = q, src
  Fire("select", q, src)
end
function QS.Hover(q, src)
  q = N(q)
  if q == QS.hovered and src == QS.hoverSrc then return end
  if not q and src and QS.hoverSrc and src ~= QS.hoverSrc then return end -- a leave from the other side
  QS.hovered, QS.hoverSrc = q, q and src or nil
  Fire("hover", q, src)
end
function QS.IsHot(q) return q ~= nil and (q == QS.selected or q == QS.hovered) end

---------------------------------------------------------------------------
-- status
---------------------------------------------------------------------------
-- "ready" (objectives done: turn it in), "failed" or "progress"
function QS.Status(q)
  q = N(q)
  if not q then return "progress" end
  if Call("C_QuestLog.IsFailed", q) == true then return "failed" end
  local r = Call("C_QuestLog.ReadyForTurnIn", q)
  if r == nil then r = Call("C_QuestLog.IsComplete", q) end
  if r == true or r == 1 then return "ready" end
  return "progress"
end
function QS.Title(q)
  local t = Call("C_QuestLog.GetTitleForQuestID", q)
  if NS.Str(t) then return t end
  return "Quest " .. tostring(q)
end
function QS.IsWatched(q)
  if not (NS.QL and N(q)) then return nil end
  return NS.QL.IsWatched({ questID = q })
end

---------------------------------------------------------------------------
-- the game's own icons, by role (each candidate is the SAME symbol from the game: an atlas or a file path; checked
-- on this client; none is ever bundled or substituted by another symbol). A role with no candidate on this client
-- draws nothing and is listed by /dm questmap.
---------------------------------------------------------------------------
QS.ICONS = {
  { role = "progress", what = "quest in progress (yellow ?, as the game map)", c = { { atlas = "QuestTurnin" }, { file = "Interface\\GossipFrame\\ActiveQuestIcon" } } },
  { role = "ready", what = "ready to turn in (yellow ?)", c = { { atlas = "QuestTurnin" }, { file = "Interface\\GossipFrame\\ActiveQuestIcon" } } },
  { role = "available", what = "quest available (yellow !)", c = { { atlas = "QuestNormal" }, { file = "Interface\\GossipFrame\\AvailableQuestIcon" } } },
  { role = "trivial", what = "low-level quest available (grey !)", c = { { atlas = "TrivialQuests" }, { atlas = "QuestTrivial" } } },
  { role = "daily", what = "repeatable quest available (blue !)", c = { { file = "Interface\\GossipFrame\\DailyQuestIcon" }, { atlas = "QuestDaily" } } },
  { role = "dailyReady", what = "repeatable quest ready (blue ?)", c = { { file = "Interface\\GossipFrame\\DailyActiveQuestIcon" }, { atlas = "QuestRepeatableTurnin" } } },
  { role = "flight", what = "flight master", c = { { atlas = "TaxiNode_Neutral" }, { atlas = "FlightMaster" }, { file = "Interface\\Minimap\\Tracking\\FlightMaster" } } },
  { role = "graveyard", what = "graveyard / spirit healer", c = { { atlas = "poi-graveyard-neutral" }, { file = "Interface\\Minimap\\Tracking\\SpiritHealer" } } },
  { role = "dungeon", what = "dungeon entrance", c = { { atlas = "Dungeon" }, { file = "Interface\\Minimap\\Dungeon" } } },
  { role = "raid", what = "raid entrance", c = { { atlas = "Raid" } } },
  { role = "inn", what = "innkeeper", c = { { file = "Interface\\Minimap\\Tracking\\Innkeeper" }, { atlas = "Innkeeper" } } },
  { role = "bank", what = "banker", c = { { file = "Interface\\Minimap\\Tracking\\Banker" }, { atlas = "Banker" } } },
  { role = "auction", what = "auctioneer", c = { { file = "Interface\\Minimap\\Tracking\\Auctioneer" }, { atlas = "Auctioneer" } } },
  { role = "mail", what = "mailbox", c = { { file = "Interface\\Minimap\\Tracking\\Mailbox" }, { atlas = "Mailbox" } } },
  { role = "repair", what = "repair vendor", c = { { file = "Interface\\Minimap\\Tracking\\Repair" } } },
  { role = "food", what = "food & drink vendor", c = { { file = "Interface\\Minimap\\Tracking\\Food" } } },
  { role = "stable", what = "stable master", c = { { file = "Interface\\Minimap\\Tracking\\StableMaster" } } },
  { role = "trainer", what = "class trainer", c = { { file = "Interface\\Minimap\\Tracking\\Class" } } },
  { role = "profession", what = "profession trainer", c = { { file = "Interface\\Minimap\\Tracking\\Profession" } } },
  { role = "reagents", what = "reagent vendor", c = { { file = "Interface\\Minimap\\Tracking\\Reagents" } } },
  { role = "poisons", what = "poison vendor", c = { { file = "Interface\\Minimap\\Tracking\\Poisons" } } },
  { role = "battlemaster", what = "battlemaster", c = { { file = "Interface\\Minimap\\Tracking\\BattleMaster" } } },
  -- 0.5.2b: the keep-tracked pin beside each tracker row (three styles, /dm keepicon) and your own pins on the map
  { role = "keepPin", what = "keep tracked, pinned (map pin)", c = { { atlas = "Waypoint-MapPin-Tracked" } } },
  { role = "keepPinOff", what = "keep tracked, not pinned (map pin)", c = { { atlas = "Waypoint-MapPin-Untracked" } } },
  { role = "keepLock", what = "keep tracked, pinned (lock)", c = { { file = "Interface\\Buttons\\LockButton-Locked-Up" } } },
  { role = "keepLockOff", what = "keep tracked, not pinned (open lock)", c = { { file = "Interface\\Buttons\\LockButton-Unlocked-Up" } } },
  { role = "keepStar", what = "keep tracked (favourite star)", c = { { atlas = "PetJournal-FavoritesIcon" } } },
  { role = "userPin", what = "your own pin on the map", c = { { atlas = "Waypoint-MapPin-ChatIcon" }, { atlas = "Waypoint-MapPin-Untracked" } } },
}
QS.ICON_BY_ROLE = {}
for _, e in ipairs(QS.ICONS) do QS.ICON_BY_ROLE[e.role] = e end

local function AtlasOK(a)
  local f = Fn("C_Texture.GetAtlasInfo")
  if not f then return false end
  local ok, info = pcall(f, a)
  return ok and type(info) == "table"
end
local function FileOK(p) return NS.Stock and NS.Stock.TextureOK and NS.Stock.TextureOK(p) or false end
-- every candidate of a role, checked: { {atlas|file, ok}, ... }
function QS.CheckRole(role)
  local e = QS.ICON_BY_ROLE[role]
  local out = {}
  for _, c in ipairs(e and e.c or {}) do
    out[#out + 1] = { atlas = c.atlas, file = c.file, ok = c.atlas and AtlasOK(c.atlas) or (c.file and FileOK(c.file)) or false }
  end
  return out
end
local resolved = {}
-- the first candidate of a role that this client has, or nil (then nothing is drawn for that role)
function QS.Icon(role)
  local r = resolved[role]
  if r == nil then
    r = false
    for _, c in ipairs(QS.CheckRole(role)) do if c.ok then r = c break end end
    resolved[role] = r
  end
  return r or nil
end
function QS.ForgetIcons() resolved = {} end
-- paint a texture with a role's game icon; false when this client has none (the caller hides the marker)
function QS.PaintIcon(tex, role)
  local c = QS.Icon(role)
  if not c then return false end
  if c.atlas and tex.SetAtlas then
    local ok = pcall(tex.SetAtlas, tex, c.atlas, false)
    if ok then return true end
  end
  if c.file then tex:SetTexture(c.file) tex:SetTexCoord(0, 1, 0, 1) return true end
  return false
end
-- the marker role for a quest in the log
function QS.MarkerRole(q)
  local s = QS.Status(q)
  return s == "ready" and "ready" or "progress", s
end

---------------------------------------------------------------------------
-- where a quest is (game data only). Returns a table:
--   { map = id, x = 0..1, y = 0..1, src = "..." }  a point
--   { map = id, zoneOnly = true, src = "..." }     only its zone (no location from the game)
--   nil                                            nothing at all
---------------------------------------------------------------------------
local function OnMap(map, q)
  local list = map and NS.MapData and NS.MapData.Quests(map)
  for _, e in ipairs(list or {}) do if e.id == q then return e end end
end
-- the quest log's zone header above a quest
function QS.HeaderOf(q)
  local idx = N(Call("C_QuestLog.GetLogIndexForQuestID", q))
  for k = idx or 0, 1, -1 do
    local info = Call("C_QuestLog.GetInfo", k)
    if type(info) == "table" and info.isHeader == true then return NS.Str(info.title) end
  end
end
local function MapNamed(name)
  if not (name and NS.MapData) then return nil end
  local low = name:lower()
  for _, r in ipairs(NS.MapData.Search(name, 20)) do
    if type(r.name) == "string" and r.name:lower() == low then return r.id end
  end
end
function QS.Locate(q)
  q = N(q)
  if not q then return nil end
  local MD = NS.MapData
  local uim = N(Call("GetQuestUiMapID", q)) or N(Call("C_QuestLog.GetQuestUiMapID", q))
  if uim and uim > 0 then
    local e = OnMap(uim, q)
    if e then return { map = uim, x = e.x, y = e.y, src = "GetQuestsOnMap" } end
  end
  local wm, wx, wy = Call("C_QuestLog.GetNextWaypoint", q)
  if N(wm) and N(wx) and N(wy) and wm > 0 then return { map = wm, x = wx, y = wy, src = "GetNextWaypoint" } end
  -- the zones of the continent you are on, then every continent's zones
  if MD then
    local here = MD.PlayerMap()
    local cont = here and MD.ContinentOf(here)
    local conts = {}
    if cont then conts[1] = cont end
    for _, c in ipairs(MD.Continents()) do if c.id ~= cont then conts[#conts + 1] = c.id end end
    for _, c in ipairs(conts) do
      for _, z in ipairs(MD.Zones(c)) do
        local e = OnMap(z.id, q)
        if e then return { map = z.id, x = e.x, y = e.y, src = "GetQuestsOnMap" } end
      end
    end
  end
  if uim and uim > 0 then return { map = uim, zoneOnly = true, src = "GetQuestUiMapID" } end
  local hm = MapNamed(QS.HeaderOf(q))
  if hm then return { map = hm, zoneOnly = true, src = "quest log zone" } end
  return nil
end

---------------------------------------------------------------------------
-- the game's own waypoint + arrow (public API, on a click only)
---------------------------------------------------------------------------
function QS.CanWaypoint()
  return Fn("C_Map.SetUserWaypoint") ~= nil and Fn("UiMapPoint.CreateFromCoordinates") ~= nil
end
-- a user waypoint at map/x/y, super-tracked (the game's arrow and minimap point follow it). Returns ok, message.
function QS.SetWaypoint(map, x, y, q)
  if not (N(map) and N(x) and N(y)) then return false, "no location" end
  if not QS.CanWaypoint() then return false, "this client has no waypoint API" end
  if Fn("C_Map.CanSetUserWaypointOnMap") and Call("C_Map.CanSetUserWaypointOnMap", map) ~= true then
    return false, "the game does not allow a waypoint on this map"
  end
  local pt = Call("UiMapPoint.CreateFromCoordinates", map, x, y)
  if not pt then return false, "the game did not make a map point" end
  local ok = pcall(Fn("C_Map.SetUserWaypoint"), pt)
  if not ok then return false, "the game refused the waypoint" end
  if Fn("C_SuperTrack.SetSuperTrackedUserWaypoint") then pcall(Fn("C_SuperTrack.SetSuperTrackedUserWaypoint"), true) end
  QS.arrow = { q = N(q), map = map, x = x, y = y }
  Fire("arrow", N(q), "waypoint")
  return true, string.format("waypoint set (%.1f, %.1f): the game's arrow points there", x * 100, y * 100)
end
-- no location: let the game's arrow follow the quest itself, when it can
function QS.TrackQuest(q)
  q = N(q)
  if not (q and Fn("C_SuperTrack.SetSuperTrackedQuestID")) then return false end
  local ok = pcall(Fn("C_SuperTrack.SetSuperTrackedQuestID"), q)
  if ok then QS.arrow = { q = q } Fire("arrow", q, "quest") end
  return ok
end
function QS.ArrowQuest()
  local q = N(Call("C_SuperTrack.GetSuperTrackedQuestID"))
  if q and q > 0 then return q end
  return QS.arrow and QS.arrow.q or nil
end

---------------------------------------------------------------------------
-- /dm questmap: a read-only probe of what the quest map needs (nothing is set, opened, hooked or registered)
---------------------------------------------------------------------------
local API = {
  "C_QuestLog.ReadyForTurnIn", "C_QuestLog.IsComplete", "C_QuestLog.IsFailed", "C_QuestLog.IsOnMap", "C_QuestLog.GetQuestsOnMap",
  "GetQuestUiMapID", "C_QuestLog.GetNextWaypoint", "C_QuestLog.GetNextWaypointForMap", "C_QuestLog.GetNextWaypointText",
  "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.GetTitleForQuestID", "C_QuestLog.GetLogIndexForQuestID",
  "C_Map.SetUserWaypoint", "C_Map.CanSetUserWaypointOnMap", "C_Map.HasUserWaypoint", "C_Map.ClearUserWaypoint", "UiMapPoint.CreateFromCoordinates",
  "C_SuperTrack.SetSuperTrackedUserWaypoint", "C_SuperTrack.IsSuperTrackingUserWaypoint", "C_SuperTrack.SetSuperTrackedQuestID",
  "C_SuperTrack.GetSuperTrackedQuestID", "C_Navigation.GetDistance", "C_QuestLine.GetQuestLineInfo", "C_QuestLine.GetAvailableQuestLines",
  "QuestPOIGetIconInfo", "C_Texture.GetAtlasInfo", "GetFileIDFromPath",
}
QS.PROBE_API = API
local function YN(v) return v and "yes" or "no" end
local function Short(v) if v == nil then return "nil" end return tostring(v) end

-- the objective tracker, read only: what 0.5.2b's keep-tracked buttons would sit beside
local function TrackerLines(lines)
  local T = _G.ObjectiveTrackerFrame
  if type(T) ~= "table" then
    local qw = _G.QuestWatchFrame or _G.WatchFrame
    lines[#lines + 1] = "tracker 1: ObjectiveTrackerFrame not present; classic watch frame " .. YN(type(qw) == "table")
    lines[#lines + 1] = "tracker 9: extra click target per quest row in 0.5.2b: unknown (no modern tracker)"
    return
  end
  local function M(o, k) return type(o) == "table" and type(o[k]) == "function" end
  local prot = M(T, "IsProtected") and select(2, pcall(T.IsProtected, T))
  local shown = M(T, "IsShown") and select(2, pcall(T.IsShown, T))
  local coll = M(T, "IsCollapsed") and select(2, pcall(T.IsCollapsed, T))
  local mods = type(T.modules) == "table" and #T.modules or nil
  lines[#lines + 1] = string.format("tracker 1: ObjectiveTrackerFrame yes; shown %s; collapsed %s; protected %s; modules %s; Header %s",
    Short(shown), Short(coll), Short(prot), Short(mods), YN(type(T.Header) == "table"))
  local blocks, sample, protBlocks, visible = 0, nil, 0, 0
  for _, name in ipairs({ "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
    local m = _G[name]
    lines[#lines + 1] = string.format("tracker 2: %s %s; usedBlocks %s", name, YN(type(m) == "table"), YN(type(m) == "table" and type(m.usedBlocks) == "table"))
    if type(m) == "table" and type(m.usedBlocks) == "table" then
      for _, set in pairs(m.usedBlocks) do
        if type(set) == "table" then
          for id, b in pairs(set) do
            if type(b) == "table" then
              blocks = blocks + 1
              if M(b, "IsVisible") and select(2, pcall(b.IsVisible, b)) == true then visible = visible + 1 end
              if M(b, "IsProtected") and select(2, pcall(b.IsProtected, b)) == true then protBlocks = protBlocks + 1 end
              sample = sample or { id = id, b = b }
            end
          end
        end
      end
    end
  end
  lines[#lines + 1] = string.format("tracker 3: quest blocks %d (visible %d, protected %d)", blocks, visible, protBlocks)
  if sample then
    local b = sample.b
    local kind = M(b, "GetObjectType") and select(2, pcall(b.GetObjectType, b))
    lines[#lines + 1] = string.format("tracker 4: sample block (quest %s): %s; HeaderText %s; poiButton %s; mouse %s",
      Short(sample.id), Short(kind), YN(type(b.HeaderText) == "table"), YN(type(b.poiButton) == "table"),
      M(b, "IsMouseEnabled") and Short(select(2, pcall(b.IsMouseEnabled, b))) or "?")
  else
    lines[#lines + 1] = "tracker 4: no quest block to sample (track a quest and run /dm questmap again)"
  end
  local can = blocks > 0 and protBlocks == 0 and prot ~= true and sample and (type(sample.b.HeaderText) == "table" or type(sample.b.poiButton) == "table")
  lines[#lines + 1] = "tracker 9: extra click target per quest row in 0.5.2b: " .. (can and "looks possible (unprotected rows with a title or map button to sit beside; our own button on UIParent, nothing inserted)"
    or (blocks == 0 and "not decided yet (no quest rows to read)" or "not safe here (rows protected or no anchor): the pin stays in the Quests tab"))
end

function QS.ProbeReport()
  local lines, have, miss = {}, {}, {}
  for _, a in ipairs(API) do if Fn(a) then have[#have + 1] = a else miss[#miss + 1] = a end end
  lines[#lines + 1] = "questmap " .. tostring(NS.version) .. " (read-only)"
  lines[#lines + 1] = "qmap 1 present: " .. (#have > 0 and table.concat(have, ", ") or "none")
  lines[#lines + 1] = "qmap 1 missing: " .. (#miss > 0 and table.concat(miss, ", ") or "none")
  -- GetQuestsOnMap on your zone: how many, what fields, watched-only or every quest?
  local MD = NS.MapData
  local here = MD and MD.PlayerMap()
  local zone = here and (MD.ZoneOf(here) or here)
  local raw = zone and Call("C_QuestLog.GetQuestsOnMap", zone)
  if type(raw) == "table" then
    local fields, seen = {}, {}
    local watched, ready = 0, 0
    for _, e in ipairs(raw) do
      if type(e) == "table" then
        for k in pairs(e) do if not seen[k] then seen[k] = true fields[#fields + 1] = tostring(k) end end
        local q = N(e.questID)
        if q and QS.IsWatched(q) then watched = watched + 1 end
        if q and QS.Status(q) == "ready" then ready = ready + 1 end
      end
    end
    table.sort(fields)
    local logN, logW = 0, 0
    local n = N(Call("C_QuestLog.GetNumQuestLogEntries")) or 0
    for i = 1, n do
      local info = Call("C_QuestLog.GetInfo", i)
      if type(info) == "table" and info.isHeader ~= true and N(info.questID) then
        logN = logN + 1
        if QS.IsWatched(info.questID) then logW = logW + 1 end
      end
    end
    lines[#lines + 1] = string.format("qmap 2: GetQuestsOnMap(%s %s): %d entries (%d watched, %d ready); fields %s; your log %d quests, %d watched",
      tostring(zone), tostring(MD.Name(zone) or "?"), #raw, watched, ready, #fields > 0 and table.concat(fields, ",") or "none", logN, logW)
  else
    lines[#lines + 1] = "qmap 2: GetQuestsOnMap: " .. (Fn("C_QuestLog.GetQuestsOnMap") and ("no list for map " .. tostring(zone)) or "not available")
  end
  -- one sample quest: the selected one, else the first in the log
  local q = QS.selected
  if not q then
    local n = N(Call("C_QuestLog.GetNumQuestLogEntries")) or 0
    for i = 1, n do
      local info = Call("C_QuestLog.GetInfo", i)
      if type(info) == "table" and info.isHeader ~= true and N(info.questID) then q = info.questID break end
    end
  end
  if q then
    local wm, wx, wy = Call("C_QuestLog.GetNextWaypoint", q)
    local loc = QS.Locate(q)
    lines[#lines + 1] = string.format("qmap 3: sample \"%s\" (%s): ReadyForTurnIn %s; IsComplete %s; IsOnMap %s; GetQuestUiMapID %s; GetNextWaypoint %s",
      QS.Title(q), tostring(q), Short(Call("C_QuestLog.ReadyForTurnIn", q)), Short(Call("C_QuestLog.IsComplete", q)), Short(Call("C_QuestLog.IsOnMap", q)),
      Short(Call("GetQuestUiMapID", q)), wm and string.format("%s %s,%s", tostring(wm), tostring(wx), tostring(wy)) or "nil")
    lines[#lines + 1] = "qmap 4: Show on map would use: " .. (loc and (loc.zoneOnly and ("its zone " .. tostring(loc.map) .. " (no location; " .. loc.src .. ")")
      or string.format("map %s at %.1f, %.1f (%s)", tostring(loc.map), loc.x * 100, loc.y * 100, loc.src)) or "nothing (no location and no zone from the game)")
  else
    lines[#lines + 1] = "qmap 3: no quest in your log to sample"
  end
  lines[#lines + 1] = string.format("qmap 5: waypoint %s; can set on your zone %s; one set now %s; arrow on a waypoint %s; arrow on quest %s",
    YN(QS.CanWaypoint()), zone and Short(Call("C_Map.CanSetUserWaypointOnMap", zone)) or "?", Short(Call("C_Map.HasUserWaypoint")),
    Short(Call("C_SuperTrack.IsSuperTrackingUserWaypoint")), Short(Call("C_SuperTrack.GetSuperTrackedQuestID")))
  -- the game icons, by role
  local missing = {}
  for _, e in ipairs(QS.ICONS) do
    local parts, use = {}, nil
    for _, c in ipairs(QS.CheckRole(e.role)) do
      parts[#parts + 1] = (c.atlas and ("atlas " .. c.atlas) or ("file " .. tostring(c.file))) .. (c.ok and " ok" or " MISSING")
      if c.ok and not use then use = c.atlas or c.file end
    end
    lines[#lines + 1] = string.format("icon %s (%s): %s -> %s", e.role, e.what, table.concat(parts, "; "), use or "NONE (nothing drawn)")
    if not use then missing[#missing + 1] = e.role end
  end
  lines[#lines + 1] = "icons missing on this client: " .. (#missing > 0 and table.concat(missing, ", ") or "none")
  TrackerLines(lines)
  if NS.db then NS.db.questmap = { have = have, missing = miss, iconsMissing = missing, lines = lines } end
  return lines
end
