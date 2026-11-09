--------------------------------------------------------------------------------
-- Objectives (v0.2.2): the game's "All Objectives" tracker, by zone.
--
--  * Quests lists this zone's in-progress quests plus pinned ones; in a capital, the city's and
--    its surrounding zone's (CITY below). Lowest [level] first, ties by title.
--  * Ready to Turn In: Valhalla's own section under the tracker (below Profession), in the look of
--    the tracker's section headers, listing this zone's (and pinned) quests that are ready.
--  * A pin left of each quest (and of the game's quest icon): a pinned quest stays listed in every zone.
--  * v0.2.1: the quest log's zone header decides where a quest belongs (see Classify); dungeon quests
--    only inside their dungeon; Ready rows use the game's own quest icon button; /vh objectives why.
--  * v0.2.2: another zone's quest with a real objective (or, ready, turn-in) marker here is listed too
--    (O.Marker); pins in the game's quest log as well (QuestLogPins.lua), one store for all.
--
-- How: Valhalla never edits, hooks or re-parents anything of the game's tracker. It only decides which
-- quests are tracked (C_QuestLog.AddQuestWatch / RemoveQuestWatch) and in what order (re-tracking), and
-- draws its own frames (the pins, the Ready section) beside the tracker, reading where its rows are.
-- Nothing changes while on a flight, during a loading screen or in combat: it waits for the landing,
-- the arrival or the end of the fight. /valhalla objectives off turns it all off (and gives back the
-- quests it untracked).
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local mod = ns:NewModule("objectives", { defaults = {
	readyCollapsed = false,     -- the Ready to Turn In section folded to its header
} })

local O = {}                    -- the logic (mod.O: the box's tests drive it)
mod.O = O

O.MAX_WATCHES = 25              -- Constants.QuestWatchConsts.MAX_QUEST_WATCHES on Forever 1.60.1
O.TICK = 0.2                    -- seconds: the pins and the section follow the tracker; queued work runs
O.BATCH = 8                     -- watch changes per tick
O.SETTLE = 1.0                  -- seconds after a zone change / landing / arrival (after the game's own re-sort)
O.LOG_DEBOUNCE = 0.5            -- quest log updates come in bursts
O.NEW_TRIES = 10                -- a new quest's data: looked for this many times, NEW_GAP apart
O.NEW_GAP = 0.4
O.REORDER_TRIES = 3             -- re-order attempts per change before giving up until the next one
O.READY_MAX = 12                -- rows shown in Ready to Turn In
O.PIN_SIZE = 17
O.MARKER_MISSES = 2             -- a quest listed for its marker here goes after this many misses in a row...
O.MARKER_GAP = 0.9              -- ...this many seconds apart (POI data can read empty for a moment)
O.ROW_H = 32

-- the capitals and the zone around each (Forever uiMapIDs, as Data/Forever/Banners.lua's city -> host)
O.CITY = {
	[1453] = 1429,   -- Stormwind City  -> Elwynn Forest
	[1455] = 1426,   -- Ironforge       -> Dun Morogh
	[1457] = 1438,   -- Darnassus       -> Teldrassil
	[1454] = 1411,   -- Orgrimmar       -> Durotar
	[1456] = 1412,   -- Thunder Bluff   -> Mulgore
	[1458] = 1420,   -- Undercity       -> Tirisfal Glades
}

local PIN_ON = ns.Media.path .. "Textures\\ValhallaPinOn"
local PIN_OFF = ns.Media.path .. "Textures\\ValhallaPinOff"

local function Now() return GetTime and GetTime() or 0 end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function OnTaxi() return UnitOnTaxi and UnitOnTaxi("player") and true or false end
local function Plain(v) return ns.Safe and ns.Safe.Value(v) or v end
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return Plain(a), Plain(b) end
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local S = {}
O.S = S
function O.Reset()
	for k in pairs(S) do S[k] = nil end
	S.ops = {}              -- queued watch changes { id, add }
	S.fresh = {}            -- newly accepted quests waiting for their data { [id] = { due, tries } }
	S.loading = false
	S.waitingTaxi = false
end
O.Reset()

local function Char()
	local c = mod.char
	if not c then c = {} mod.char = c end
	if type(c.pinned) ~= "table" then c.pinned = {} end
	if type(c.hidden) ~= "table" then c.hidden = {} end   -- quests Valhalla untracked (given back when turned off)
	return c
end
function O.Pinned() return Char().pinned end
function O.IsPinned(id) return id ~= nil and Char().pinned[id] == true end

--------------------------------------------------------------------------------
-- the quest log (read only)
--------------------------------------------------------------------------------

-- { [questID] = { id, idx, title, header, level, ready, tag (the game's quest tag ID) } }, count
function O.ReadLog()
	local CQ = C_QuestLog
	local out, n = {}, 0
	if not (CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo) then return out, 0 end
	local count = Call(CQ.GetNumQuestLogEntries) or 0
	local header
	for i = 1, count do
		local info = Call(CQ.GetInfo, i)
		if type(info) == "table" then
			if info.isHeader then
				header = Plain(info.title)
			elseif info.questID and not info.isHidden and not info.isTask and not info.isBounty then
				local id = info.questID
				local level = Plain(info.difficultyLevel)
				if not level or level == 0 then level = Plain(info.level) end
				if (not level or level == 0) and CQ.GetQuestDifficultyLevel then level = Call(CQ.GetQuestDifficultyLevel, id) end
				local ready = Call(CQ.ReadyForTurnIn, id)
				if ready == nil then ready = Call(CQ.IsComplete, id) end
				local tag = CQ.GetQuestTagInfo and Call(CQ.GetQuestTagInfo, id)
				out[id] = { id = id, idx = i, title = Plain(info.title) or ("Quest " .. id), header = header,
					level = tonumber(level) or 0, ready = ready and true or false,
					tag = type(tag) == "table" and tonumber(Plain(tag.tagID)) or nil }
				n = n + 1
			end
		end
	end
	return out, n
end

-- the watch list, in the tracker's order: ids, and { [id] = index }
function O.WatchOrder()
	local CQ = C_QuestLog
	local list, set = {}, {}
	if not (CQ and CQ.GetNumQuestWatches and CQ.GetQuestIDForQuestWatchIndex) then return list, set end
	for i = 1, Call(CQ.GetNumQuestWatches) or 0 do
		local id = Call(CQ.GetQuestIDForQuestWatchIndex, i)
		if id then list[#list + 1] = id set[id] = #list end
	end
	return list, set
end

-- lowest [level] first, then title, then id
function O.Before(a, b)
	if a.level ~= b.level then return a.level < b.level end
	if a.title ~= b.title then return a.title < b.title end
	return a.id < b.id
end

--------------------------------------------------------------------------------
-- where the player is, and which quests belong here (v0.2.1)
--
-- The quest log's zone header decides (A3):
--   * "X: Zone" (e.g. "Excavation Site: Wetlands") counts as that zone;
--   * a dungeon quest (the game's Dungeon / Raid tag, or a header that names a dungeon) is listed
--     only inside its dungeon; inside a dungeon only its quests are (no walk up to the outdoor zone);
--   * a header that names a zone: listed in that zone (a capital: with its surrounding zone);
--   * any other header (class, profession, event...): listed where it has a real map pin here
--     (not a map-indicator pin, not a "travel this way" waypoint, not another map's pin).
--   * pinned: always listed.
--------------------------------------------------------------------------------

local function MapInfo(id) return C_Map and C_Map.GetMapInfo and Call(C_Map.GetMapInfo, id) end

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
-- a zone name, compared without case and a leading "The "
local function ZCanon(s)
	if type(s) ~= "string" then return nil end
	s = Trim(s:lower()):gsub("^the%s+", "")
	return s ~= "" and s or nil
end
-- a dungeon name: also without a wing ("Scarlet Monastery - Armory") and through the aliases below
O.DUNGEON_ALIAS = {
	["stormwind stockade"] = "stockade",
	["temple of atal'hakkar"] = "sunken temple",
	["lower blackrock spire"] = "blackrock spire",
	["upper blackrock spire"] = "blackrock spire",
	["ahn'qiraj temple"] = "temple of ahn'qiraj",
}
local function DCanon(s)
	s = ZCanon(s)
	if not s then return nil end
	s = Trim(s:gsub("%s+%-%s+.*$", ""))
	return O.DUNGEON_ALIAS[s] or s
end
O.ZCanon, O.DCanon = ZCanon, DCanon

-- known dungeons and raids: the game's tables (Data/Forever/Places.lua), a fallback list, and every
-- instance you enter
O.DUNGEON_FALLBACK = {
	"Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps",
	"The Stockade", "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs", "Uldaman",
	"Zul'Farrak", "Maraudon", "Sunken Temple", "Blackrock Depths", "Blackrock Spire", "Dire Maul",
	"Scholomance", "Stratholme", "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub",
	"Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", "Naxxramas",
}
local DUNGEONS
local function Dungeons()
	if DUNGEONS then return DUNGEONS end
	DUNGEONS = {}
	local function Add(name) local k = DCanon(name) if k then DUNGEONS[k] = true end end
	for _, n in ipairs(O.DUNGEON_FALLBACK) do Add(n) end
	local P = ns.MapPlaces
	if type(P) == "table" then
		for _, it in ipairs(P.instances or {}) do
			for _, d in ipairs(it[4] or {}) do Add(d[2]) end
		end
		for _, d in ipairs(P.unplaced or {}) do Add(d[2]) end
	end
	return DUNGEONS
end
function O.LearnDungeon(name) local k = DCanon(name) if k then Dungeons()[k] = true end end
function O.IsDungeonName(name) local k = DCanon(name) return k ~= nil and Dungeons()[k] == true end

-- known zones: every Zone-type map in the game's map tree (read once), and the capitals
local ZONES
local function Zones()
	if ZONES and next(ZONES) then return ZONES end
	ZONES = {}
	local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	local function Add(name) local k = ZCanon(name) if k then ZONES[k] = true end end
	for city, around in pairs(O.CITY) do
		local a, b = MapInfo(city), MapInfo(around)
		Add(a and a.name) Add(b and b.name)
	end
	if C_Map and C_Map.GetMapChildrenInfo then
		local roots, seen = { 947, 1414, 1415, 1945 }, {}
		-- (and the top of the player's own map tree)
		local m, top = C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player"), nil
		for _ = 1, 8 do
			local info = m and MapInfo(m)
			if not info then break end
			top = m
			m = info.parentMapID
			if not m or m == 0 then break end
		end
		if top then roots[#roots + 1] = top end
		for _, r in ipairs(roots) do
			if not seen[r] then
				seen[r] = true
				local list = Call(C_Map.GetMapChildrenInfo, r, ZONE, true)
				if type(list) == "table" then
					for _, info in ipairs(list) do
						if info.mapType == nil or info.mapType == ZONE then Add(info.name) end
					end
				end
			end
		end
	end
	return ZONES
end
function O.IsZoneName(name) local k = ZCanon(name) return k ~= nil and Zones()[k] == true end
function O.ForgetNames() ZONES, DUNGEONS = nil, nil end

-- the zone a map belongs to: a capital as it is, a sub-zone / micro map walked up to its zone
function O.ZoneOf(mapID)
	local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	local CONT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	local m = mapID
	for _ = 1, 6 do
		if not m or O.CITY[m] then return m end
		local info = MapInfo(m)
		if not info then return m end
		if info.mapType == ZONE then return m end
		if info.mapType and info.mapType <= CONT then return nil end
		local parent = info.parentMapID
		local pinfo = parent and parent ~= 0 and MapInfo(parent)
		if not pinfo or (pinfo.mapType and pinfo.mapType <= CONT) then return m end   -- (a dungeon's own map)
		m = parent
	end
	return m
end

local INSTANCE_KINDS = { party = true, raid = true, scenario = true }

-- { maps, names (canonical), onMap = { [questID] = true } (the kept pins), pins = { [questID] = { raw pins } },
--   marker = { [questID] = true } (a real marker here that passes every guard: see O.Marker), inst (in a
--   dungeon), instName, key }
function O.Here()
	local best = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local inInst, kind = nil, nil
	if IsInInstance then inInst, kind = Call(IsInInstance) end
	local inst = inInst and INSTANCE_KINDS[kind] and true or false
	local zone = inst and best or O.ZoneOf(best)
	local here = { maps = {}, names = {}, onMap = {}, pins = {}, marker = {}, guard = {}, best = best, zone = zone, inst = inst, shown = {} }
	local function AddName(s)
		if type(s) ~= "string" or s == "" then return end
		here.shown[s] = true
		local z, d = ZCanon(s), DCanon(s)
		if z then here.names[z] = true end
		if d then here.names[d] = true end
	end
	local function AddMap(m)
		if not m or here.maps[m] then return end
		here.maps[m] = true
		local info = MapInfo(m)
		AddName(info and info.name)
	end
	if inst then
		local name = GetInstanceInfo and Call(GetInstanceInfo)
		here.instName = name
		AddName(name)
		O.LearnDungeon(name)
		AddMap(best)
	else
		AddMap(zone)
		if zone and O.CITY[zone] then AddMap(O.CITY[zone]) end
	end
	AddName(GetZoneText and Call(GetZoneText))
	AddName(GetRealZoneText and Call(GetRealZoneText))
	if C_QuestLog and C_QuestLog.GetQuestsOnMap then
		local wayFn = C_QuestLog.GetNextWaypointForMap
		for m in pairs(here.maps) do
			local list = Call(C_QuestLog.GetQuestsOnMap, m)
			if type(list) == "table" then
				for _, q in ipairs(list) do
					local id = q.questID
					if id then
						local p = { map = m, mapID = q.mapID, x = q.x, y = q.y, indicator = q.isMapIndicatorQuest and true or false }
						if wayFn then p.waypoint = Call(wayFn, id, m) ~= nil end
						p.otherMap = q.mapID ~= nil and q.mapID ~= m and not here.maps[q.mapID]
						p.kept = not (p.indicator or p.waypoint or p.otherMap)
						if p.kept then here.onMap[id] = true end
						here.pins[id] = here.pins[id] or {}
						table.insert(here.pins[id], p)
					end
				end
			end
		end
	end
	if not inst then
		for id in pairs(here.onMap) do O.Marker(id, here) end
	end
	local names = {}
	for k in pairs(here.names) do names[#names + 1] = k end
	table.sort(names)
	here.key = tostring(zone) .. (inst and ":inst:" or ":") .. table.concat(names, "|")
	return here
end

-- v0.2.2: a quest from another zone with a real marker here (an objective while in progress, its turn-in once
-- ready). All of these must hold (outdoors only; dungeon quests are left out in Classify):
--   * a kept pin on a current map: not a map indicator, not a waypoint for that map, not another map's pin;
--   * the game's next waypoint for it (GetNextWaypoint) is none, or on a current map;
--   * a pin on the map you stand on (not the capital's surround) also needs the game's own "local POI"
--     (C_QuestLog.IsOnMap's hasLocalPOI).
function O.Marker(id, here)
	local g = { }
	here.guard[id] = g
	local CQ = C_QuestLog
	if CQ.GetNextWaypoint then
		local m = Call(CQ.GetNextWaypoint, id)
		g.nextMap = m
		if m and not here.maps[m] then g.why = ("its next waypoint is on map %s"):format(tostring(m)) return false end
	end
	local localPOI
	if CQ.IsOnMap then local _, l = Call(CQ.IsOnMap, id) localPOI = l and true or false end
	g.localPOI = localPOI
	for _, p in ipairs(here.pins[id] or {}) do
		if p.kept then
			if p.map ~= here.zone or localPOI ~= false then
				here.marker[id] = true
				g.why = nil
				return true
			end
		end
	end
	g.why = "the game says it has no local marker on this map"
	return false
end

local DUNGEON_TAGS = { [81] = true, [62] = true }   -- Constants.QuestConsts QUEST_INFO_DUNGEON_ID / QUEST_INFO_RAID_ID
function O.IsDungeonQuest(e)
	return (e.tag and DUNGEON_TAGS[e.tag]) or (e.header and O.IsDungeonName(e.header)) or false
end

-- is a quest listed here, and why (the reason is what /valhalla objectives why prints)
function O.Classify(e, here, placeOnly)
	if not e then return false, "not in the quest log" end
	if not placeOnly and O.IsPinned(e.id) then return true, "pinned" end
	if not here then return false, "no location yet" end
	local h = e.header
	local function Here(s) return s and (here.names[ZCanon(s) or ""] or here.names[DCanon(s) or ""]) or false end
	-- "X: Zone" counts as that zone
	local suffix = h and h:match("^[^:]+:%s*(.+)$")
	local function Marked(text)
		if here.inst or O.IsDungeonQuest(e) or not here.marker[e.id] then return false end
		return true, ("%s, but it has %s here"):format(text, e.ready and "a turn-in marker" or "an objective marker")
	end
	if suffix and O.IsZoneName(suffix) then
		if Here(suffix) or Here(h) then return true, ("header \"%s\" counts as %s: here"):format(h, suffix) end
		local text = ("header \"%s\" counts as %s: not here"):format(h, suffix)
		local yes, why = Marked(text)
		if yes then return true, why end
		return false, text
	end
	local dungeon = O.IsDungeonQuest(e)
	if here.inst then
		if Here(h) then return true, ("header \"%s\" is this dungeon"):format(h) end
		if dungeon and here.onMap[e.id] then return true, "a dungeon quest with a pin on this dungeon's map" end
		return false, "in a dungeon: only its own quests are listed"
	end
	if dungeon then return false, "a dungeon quest: listed inside its dungeon" end
	if h and Here(h) then return true, ("header \"%s\" is this zone"):format(h) end
	if h and O.IsZoneName(h) then
		local text = ("header \"%s\" is another zone"):format(h)
		local yes, why = Marked(text)
		if yes then return true, why end
		local g = here.guard[e.id]
		if here.onMap[e.id] and g and g.why then text = text .. " (its marker here doesn't count: " .. g.why .. ")" end
		return false, text
	end
	if here.onMap[e.id] then return true, ("header \"%s\" isn't a zone: it has a map pin here"):format(tostring(h)) end
	return false, ("header \"%s\" isn't a zone: no map pin here"):format(tostring(h))
end

function O.InZone(e, here) return e ~= nil and here ~= nil and (O.Classify(e, here, true)) or false end   -- (the place only)
function O.Listed(e, here) return (O.Classify(e, here)) end

--------------------------------------------------------------------------------
-- the plan: which quests the Quests section tracks, in order (pinned stay first when over the limit)
--------------------------------------------------------------------------------

function O.Target(log, here)
	local pinned, other = {}, {}
	for _, e in pairs(log) do
		if not e.ready and O.Listed(e, here) then
			if O.IsPinned(e.id) then pinned[#pinned + 1] = e else other[#other + 1] = e end
		end
	end
	table.sort(pinned, O.Before)
	table.sort(other, O.Before)
	local keep = {}
	for _, e in ipairs(pinned) do if #keep < O.MAX_WATCHES then keep[#keep + 1] = e end end
	for _, e in ipairs(other) do if #keep < O.MAX_WATCHES then keep[#keep + 1] = e end end   -- (the highest levels drop off)
	table.sort(keep, O.Before)
	return keep
end

-- Ready to Turn In: this zone's and the pinned quests that are ready, sorted the same way
function O.ReadyList(log, here)
	local out = {}
	for _, e in pairs(log or {}) do
		if e.ready and O.Listed(e, here) then out[#out + 1] = e end
	end
	table.sort(out, O.Before)
	return out
end

local function Queue(id, add)
	for _, op in ipairs(S.ops) do
		if op.id == id then op.add = add return end
	end
	S.ops[#S.ops + 1] = { id = id, add = add }
end

-- a full plan: on arriving somewhere, a pin changed, the module turned on
function O.PlanFull()
	local log, n = O.ReadLog()
	if n == 0 then return false end   -- (the log isn't loaded yet: tried again later)
	local here = O.Here()
	S.here, S.log = here, log
	local target = O.Target(log, here)
	local want = {}
	for _, e in ipairs(target) do want[e.id] = true end
	local _, watched = O.WatchOrder()
	S.ops = {}
	for id in pairs(watched) do
		if log[id] and not want[id] then Queue(id, false) end
	end
	for _, e in ipairs(target) do
		if not watched[e.id] then Queue(e.id, true) end
	end
	O.SweepPins(log, n)
	S.reorderDue, S.reorderTries = Now(), 0
	S.readyDirty = true
	return true
end

-- a quick pass on quest log changes: ready quests leave Quests, quests Valhalla hid that belong come
-- back, and newly accepted quests are placed. The zone stays as it was planned.
-- the markers here, read again (same place only): a new one counts at once, a lost one after
-- MARKER_MISSES misses MARKER_GAP apart. Returns the quests whose marker was gained and lost.
function O.RefreshMarkers(now)
	local old = S.here
	local gained, lost = {}, {}
	if not old or old.inst then return gained, lost end
	local new = O.Here()
	if new.key ~= old.key then return gained, lost end   -- (somewhere else: the full plan that's coming decides)
	S.miss = S.miss or {}
	for id in pairs(old.marker) do
		if new.marker[id] then
			S.miss[id] = nil   -- (seen again: the count starts over)
		else
			local m = S.miss[id]
			if not m then m = { n = 0, t = -math.huge } S.miss[id] = m end
			if now - m.t >= O.MARKER_GAP then m.n = m.n + 1 m.t = now end
			if m.n < O.MARKER_MISSES then
				new.marker[id] = true   -- (kept for now; looked at again shortly)
				S.partialDue = math.min(S.partialDue or math.huge, now + O.MARKER_GAP + 0.05)
			else
				S.miss[id] = nil
				lost[id] = true
			end
		end
	end
	for id in pairs(new.marker) do
		if not old.marker[id] then gained[id] = true end
	end
	S.here = new
	return gained, lost
end

function O.PlanPartial()
	if not S.here then return end
	local log, n = O.ReadLog()
	if n == 0 then return end
	local now = Now()
	local gained, lost = O.RefreshMarkers(now)
	local here = S.here
	S.log = log
	local c = Char()
	local _, watched = O.WatchOrder()
	local count, added = 0, false
	for _ in pairs(watched) do count = count + 1 end
	for id, e in pairs(log) do
		local listed = O.Listed(e, here)
		if watched[id] and e.ready then
			Queue(id, false)   -- (ready: shown in Ready to Turn In when listed, never in Quests)
		elseif watched[id] and lost[id] and not listed then
			Queue(id, false)   -- (its marker here is gone: nothing left to do here)
		elseif not watched[id] and not e.ready and listed and (c.hidden[id] or gained[id]) and count < O.MAX_WATCHES then
			Queue(id, true) count = count + 1 added = true
		end
	end
	-- new quests: placed once their entry (and zone header) is there
	for id, f in pairs(S.fresh) do
		if now >= f.due then
			local e = log[id]
			if e and e.header then
				S.fresh[id] = nil
				if O.Listed(e, here) then
					if e.ready then
						if watched[id] then Queue(id, false) end
					elseif not watched[id] and count < O.MAX_WATCHES then
						Queue(id, true) count = count + 1 added = true
					else
						added = true   -- (tracked by the game: put in its place)
					end
				elseif watched[id] then
					Queue(id, false)   -- another zone's: out until you get there
				else
					c.hidden[id] = true
				end
			else
				f.tries = f.tries + 1
				f.due = now + O.NEW_GAP
				if f.tries >= O.NEW_TRIES then S.fresh[id] = nil end
			end
		end
	end
	for id in pairs(c.hidden) do if not log[id] then c.hidden[id] = nil end end
	O.SweepPins(log, n)
	if added then S.reorderDue, S.reorderTries = now + 0.3, 0 end
	S.readyDirty = true
end

-- a pin whose quest left the log goes (only while the log reads as loaded)
function O.SweepPins(log, n)
	if not n or n == 0 then return end
	local p = O.Pinned()
	for id in pairs(p) do if not log[id] then p[id] = nil end end
end

-- the queued watch changes, a few at a time
function O.RunOps()
	local c = Char()
	local done = 0
	while done < O.BATCH and #S.ops > 0 do
		local op = table.remove(S.ops, 1)
		if op.add then
			local _, watched = O.WatchOrder()
			local count = 0
			for _ in pairs(watched) do count = count + 1 end
			if not watched[op.id] and count < O.MAX_WATCHES then
				Call(C_QuestLog.AddQuestWatch, op.id)
			end
			c.hidden[op.id] = nil
		else
			Call(C_QuestLog.RemoveQuestWatch, op.id)
			c.hidden[op.id] = true
		end
		done = done + 1
	end
	return done
end

--------------------------------------------------------------------------------
-- the order: re-tracking. Which end a new watch goes to is learned (Forever 1.60.1: the front) and
-- saved (ValhallaDB.objectives.watchSide).
--------------------------------------------------------------------------------

local function KeyOf(id)
	local e = S.log and S.log[id]
	if e then return e end
	return { id = id, level = math.huge, title = "" }
end

-- the order the watched quests should be in
function O.Wanted(order)
	local list = {}
	for _, id in ipairs(order) do list[#list + 1] = KeyOf(id) end
	table.sort(list, O.Before)
	local out = {}
	for i, e in ipairs(list) do out[i] = e.id end
	return out
end

local function Same(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end
O.Same = Same

-- the quests to re-track, in the order to re-track them, for a known side
function O.OrderFix(order, want, side)
	local fix = {}
	if side == "front" then
		local n, k = #order, 0
		while k < n and order[n - k] == want[n - k] do k = k + 1 end
		for i = n - k, 1, -1 do fix[#fix + 1] = want[i] end
	else
		local k = 0
		while k < #order and order[k + 1] == want[k + 1] do k = k + 1 end
		for i = k + 1, #want do fix[#fix + 1] = want[i] end
	end
	return fix
end

local function Add(id) Call(C_QuestLog.AddQuestWatch, id) end
local function Remove(id) Call(C_QuestLog.RemoveQuestWatch, id) end

function O.Reorder()
	S.reorderDue = nil
	local order = O.WatchOrder()
	if #order < 2 then return "short" end
	local want = O.Wanted(order)
	if Same(order, want) then S.reorderTries = 0 return "ok" end
	S.reorderTries = (S.reorderTries or 0) + 1
	if S.reorderTries > O.REORDER_TRIES then return "gaveup" end
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
	local side = mod.db and mod.db.watchSide
	if side == "front" or side == "end" then
		local fix = O.OrderFix(order, want, side)
		for _, id in ipairs(fix) do Remove(id) end
		for _, id in ipairs(fix) do Add(id) end
	else
		-- not known yet: all off, then two back on show which end a new one goes to
		for _, id in ipairs(order) do Remove(id) end
		Add(want[1]) Add(want[2])
		local now = O.WatchOrder()
		if now[1] == want[1] and now[2] == want[2] then
			side = "end"
			for i = 3, #want do Add(want[i]) end
		elseif now[1] == want[2] and now[2] == want[1] then
			side = "front"
			Remove(want[1]) Remove(want[2])
			for i = #want, 1, -1 do Add(want[i]) end
		else
			for i = 3, #want do Add(want[i]) end   -- (the list didn't read back at once: checked next time)
		end
		if side and mod.db then mod.db.watchSide = side end
	end
	if super and super ~= 0 and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
		and Call(C_SuperTrack.GetSuperTrackedQuestID) ~= super then
		Call(C_SuperTrack.SetSuperTrackedQuestID, super)
	end
	-- checked again next tick; a wrong guess of the side is unlearned
	local after = O.WatchOrder()
	if not Same(after, want) then
		if mod.db and mod.db.watchSide and S.reorderTries >= 2 then mod.db.watchSide = nil end
		S.reorderDue = Now() + O.TICK
	end
	return "fixed"
end

--------------------------------------------------------------------------------
-- the scheduler (one ticker while on)
--------------------------------------------------------------------------------

function O.Blocked() return InCombat() or OnTaxi() or S.loading end

function O.Step(now)
	now = now or Now()
	if O.Blocked() then
		if OnTaxi() then S.waitingTaxi = true end
		return "blocked"
	end
	if S.fullDue and now >= S.fullDue then
		S.fullDue = nil
		if not O.PlanFull() then
			S.fullTries = (S.fullTries or 0) + 1
			if S.fullTries < 20 then S.fullDue = now + 1 end
		else
			S.fullTries = 0
		end
	end
	if S.partialDue and now >= S.partialDue and not S.fullDue then
		S.partialDue = nil
		O.PlanPartial()
	end
	if next(S.fresh) and not S.fullDue then
		for _, f in pairs(S.fresh) do if now >= f.due then S.partialDue = S.partialDue or now break end end
	end
	if #S.ops > 0 then
		O.RunOps()
		if #S.ops == 0 then S.reorderDue = math.max(S.reorderDue or 0, now + O.TICK) end
		return "ops"
	end
	if S.reorderDue and now >= S.reorderDue then return O.Reorder() end
end

-- a zone change / arrival / landing: a full plan once settled
function O.ZoneDue(now)
	S.fullDue = (now or Now()) + O.SETTLE
	S.reorderTries = 0
end

O.EVENTS = {
	"QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
	"QUEST_POI_UPDATE", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD",
	"PLAYER_LEAVING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_CONTROL_GAINED",
	"PLAYER_REGEN_ENABLED",
}

function O.OnEvent(event, a1)
	local now = Now()
	if event == "ZONE_CHANGED_NEW_AREA" then
		O.ZoneDue(now)
	elseif event == "ZONE_CHANGED" then
		local best = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
		if best ~= S.lastBest then S.lastBest = best O.ZoneDue(now) end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then
		S.loading = false
		O.ZoneDue(now)
	elseif event == "PLAYER_LEAVING_WORLD" or event == "LOADING_SCREEN_ENABLED" then
		S.loading = true
	elseif event == "PLAYER_CONTROL_GAINED" then
		if S.waitingTaxi or S.fullDue then S.waitingTaxi = false O.ZoneDue(now) end
	elseif event == "QUEST_ACCEPTED" then
		if a1 then S.fresh[a1] = { due = now + O.NEW_GAP, tries = 0 } end
	elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
		if a1 then
			local was = O.Pinned()[a1]
			O.Pinned()[a1] = nil
			Char().hidden[a1] = nil
			S.fresh[a1] = nil
			if S.miss then S.miss[a1] = nil end
			if was then O.NotifyPins(a1) end
		end
		S.partialDue = S.partialDue or now + O.LOG_DEBOUNCE
	elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_POI_UPDATE" then
		S.partialDue = S.partialDue or now + O.LOG_DEBOUNCE
	elseif event == "PLAYER_REGEN_ENABLED" then
		if S.restorePending then O.Restore() end
	end
	S.layoutDirty, S.readyDirty = true, true
end

-- the pin clicked: listed everywhere (or not), at once (out of combat; else after it)
-- the one pin store (ValhallaCharDB.objectives.pinned): every change goes through here, and every place that
-- shows pins (the tracker's rows, Ready to Turn In, the quest log) hears of it
O.pinListeners = {}
function O.OnPinsChanged(fn) O.pinListeners[#O.pinListeners + 1] = fn end
function O.NotifyPins(id)
	S.layoutDirty, S.readyDirty = true, true
	for _, fn in ipairs(O.pinListeners) do pcall(fn, id) end
end
function O.SetPinned(id, on)
	if not id then return end
	O.Pinned()[id] = on and true or nil
	S.fullDue = Now()
	O.NotifyPins(id)
end

-- turned off: the quests Valhalla untracked are tracked again (the game's own tracking from then on)
function O.Restore()
	if InCombat() then S.restorePending = true return false end
	S.restorePending = nil
	local c = Char()
	local log = O.ReadLog()
	local _, watched = O.WatchOrder()
	local count = 0
	for _ in pairs(watched) do count = count + 1 end
	local ids = {}
	for id in pairs(c.hidden) do if log[id] and not watched[id] then ids[#ids + 1] = log[id] end end
	table.sort(ids, function(a, b) return a.idx < b.idx end)
	for _, e in ipairs(ids) do
		if count >= O.MAX_WATCHES then break end
		Add(e.id) count = count + 1
	end
	c.hidden = {}
	return true
end

--------------------------------------------------------------------------------
-- frames: the pins on the tracker's quest rows, and the Ready to Turn In section
--------------------------------------------------------------------------------

local UI = { pins = {}, rows = {} }
O.UI = UI
local MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

local function Visible(f) return type(f) == "table" and f.IsVisible and f:IsVisible() and true or false end
local function Atlas(t, name)
	if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(name) then t:Hide() return false end
	t:SetAtlas(name, true)
	t:Show()
	return true
end
local function TrackerColor(key, r, g, b)
	local T = rawget(_G, "OBJECTIVE_TRACKER_COLOR")
	local c = type(T) == "table" and T[key]
	if type(c) == "table" and c.r then return c.r, c.g, c.b end
	return r, g, b
end

local function PinTip(self)
	if not GameTooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(O.IsPinned(self.q) and L["Unpin"] or L["Pin: keep in list"], 1, 0.82, 0)
	GameTooltip:Show()
end
local function PinClick(self)
	if not self.q then return end
	if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
	O.SetPinned(self.q, not O.IsPinned(self.q))
	if GameTooltip and GameTooltip:IsOwned(self) then PinTip(self) end
end

local function MakePin(parent)
	local b = CreateFrame("Button", nil, parent or UIParent)
	b:SetSize(O.PIN_SIZE, O.PIN_SIZE)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", PinClick)
	b:SetScript("OnEnter", PinTip)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	b:Hide()
	return b
end
local function PaintPin(b, q)
	b.q = q
	local on = O.IsPinned(q)
	if b.on ~= on then
		b.on = on
		b.icon:SetTexture(on and PIN_ON or PIN_OFF)
		b.icon:SetAlpha(on and 1 or 0.8)
	end
end
O.PaintPin = PaintPin
O.MakePin = MakePin

-- the tracker's visible quest rows (read only): { q, block }, top to bottom
function O.Blocks()
	local out = {}
	for _, name in ipairs(MODULES) do
		local m = rawget(_G, name)
		local used = type(m) == "table" and rawget(m, "usedBlocks")
		local set = type(used) == "table" and used[rawget(m, "blockTemplate") or "ObjectiveTrackerQuestPOIBlockTemplate"]
		if type(set) == "table" then
			for id, b in pairs(set) do
				if type(id) == "number" and Visible(b) then out[#out + 1] = { q = id, b = b } end
			end
		end
	end
	table.sort(out, function(a, b) return (a.b:GetTop() or 0) > (b.b:GetTop() or 0) end)
	return out
end

function O.LayoutPins()
	local T = rawget(_G, "ObjectiveTrackerFrame")
	local blocks = Visible(T) and O.Blocks() or {}
	local n = 0
	for _, it in ipairs(blocks) do
		n = n + 1
		local p = UI.pins[n] or MakePin(UIParent)
		UI.pins[n] = p
		local b = it.b
		local poi = Visible(rawget(b, "poiButton")) and b.poiButton or nil
		local key = tostring(b) .. ":" .. it.q .. ":" .. tostring(poi)
		if p.key ~= key then
			p.key = key
			p:ClearAllPoints()
			p:SetPoint("RIGHT", poi or rawget(b, "HeaderText") or b, "LEFT", -2, 0)
		end
		p:SetFrameStrata(b:GetFrameStrata() or "LOW")
		p:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
		PaintPin(p, it.q)
		p:Show()
	end
	for i = n + 1, #UI.pins do UI.pins[i]:Hide() UI.pins[i].key = nil end
	return n
end

-- the Ready to Turn In section
local function PaintToggle()
	local r = UI.ready
	if not r then return end
	local collapsed = mod.db and mod.db.readyCollapsed
	local b = r.toggle
	local name = collapsed and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse"
	if b.native then   -- (the Quests header's own button template: as ObjectiveTrackerModuleHeaderMixin:SetCollapsed)
		local n, p = b:GetNormalTexture(), b:GetPushedTexture()
		if n then n:SetAtlas(name, true) end
		if p then p:SetAtlas(name .. "-pressed", true) end
		return
	end
	if b.down then name = name .. "-pressed" end
	if not Atlas(b.icon, name) then
		b.icon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
		b.icon:SetSize(14, 14)
		b.icon:Show()
	end
end

local function RowEnter(self)
	local r, g, b = TrackerColor("HeaderHighlight", 1, 0.82, 0)
	if not self.colored then self.title:SetTextColor(r, g, b) end
	if GameTooltip then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.plain or "", 1, 0.82, 0)
		GameTooltip:AddLine(_G.QUEST_WATCH_QUEST_READY or L["Ready for turn-in"], 0.5, 0.95, 0.4)
		GameTooltip:AddLine(L["Click: select this quest and open it"], 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end
end
local function RowLeave(self)
	local r, g, b = TrackerColor("Header", 0.75, 0.61, 0)
	if not self.colored then self.title:SetTextColor(r, g, b) end
	if GameTooltip then GameTooltip:Hide() end
end
-- the quest icon on a Ready row: the game's own quest POI button (ObjectiveTrackerPOIButtonTemplate, as the
-- Quests rows), so it looks and sizes the same. Its click is ours, the same toggle as the game's (first click
-- selects the quest, a second clears it) but without the game's "track it if untracked" step (a ready
-- quest stays out of Quests). Nothing here is protected: super-tracking is allowed in combat too.
function O.PoiClick(self, button)
	if button and button ~= "LeftButton" then return end
	local q = self.q
	if not q then return end
	local CU = rawget(_G, "ChatFrameUtil")
	if CU and CU.TryInsertQuestLinkForQuestID then
		local ok, done = pcall(CU.TryInsertQuestLinkForQuestID, q)
		if ok and done then return end
	end
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
	if super == q then
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
		if C_SuperTrack.ClearAllSuperTracked then Call(C_SuperTrack.ClearAllSuperTracked)
		else Call(C_SuperTrack.SetSuperTrackedQuestID, 0) end
	else
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then Call(C_SuperTrack.SetSuperTrackedQuestID, q) end
	end
	S.readyDirty = true
	O.PaintPoi(self)
end

-- the POI button's look for its quest: complete, selected when super-tracked
function O.PaintPoi(b)
	if not (b and b.q) then return end
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
	local sel = super == b.q
	if b.native then
		local U = rawget(_G, "POIButtonUtil")
		local style = U and U.Style and U.Style.QuestComplete or 3
		if b.painted ~= b.q then pcall(b.SetQuestID, b, b.q) end
		pcall(b.SetStyle, b, style)
		pcall(b.SetSelected, b, sel)
		if b.painted ~= b.q or b.sel ~= sel then pcall(b.UpdateButtonStyle, b) end
	else
		if not Atlas(b.icon, "UI-QuestIcon-TurnIn-Normal") then
			b.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon") b.icon:Show()
		end
		b.icon:SetSize(20, 20)
		b.icon:SetAlpha(sel and 1 or 0.6)
		if b.glow then b.glow:SetShown(sel) end
	end
	b.painted, b.sel = b.q, sel
	b:Show()
end

local POI_TEMPLATES = { "ObjectiveTrackerPOIButtonTemplate", "POIButtonTemplate" }
local function MakePoi(row)
	for _, t in ipairs(POI_TEMPLATES) do
		local ok, b = pcall(CreateFrame, "Button", nil, row, t)
		-- (a mixin's methods sit on the frame itself: SetQuestID there means the template took)
		if ok and type(b) == "table" and type(rawget(b, "SetQuestID")) == "function" then
			b.native, b.template = true, t
			b:SetScript("OnClick", O.PoiClick)
			if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
			return b
		end
	end
	-- (no template: drawn the same size, the same toggle)
	local b = CreateFrame("Button", nil, row)
	b:SetSize(20, 20)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("CENTER")
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture("Interface\\WorldMap\\UI-QuestPoi-IconGlow")
	b.glow:SetBlendMode("ADD")
	b.glow:SetSize(50, 50)
	b.glow:SetPoint("CENTER")
	b.glow:Hide()
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", O.PoiClick)
	return b
end

function O.ReadyClick(q)
	if not q then return end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then Call(C_SuperTrack.SetSuperTrackedQuestID, q) end
	if not InCombat() then
		local open = rawget(_G, "QuestMapFrame_OpenToQuestDetails")
		if open then pcall(open, q) end
	end
end

local function MakeRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(O.ROW_H)
	row.title = row:CreateFontString(nil, "ARTWORK")
	row.title:SetFontObject(rawget(_G, "ObjectiveTrackerLineFont") or GameFontNormal)
	row.title:SetJustifyH("LEFT")
	row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 27, 0)
	row.title:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.title:SetWordWrap(false)
	row.zone = row:CreateFontString(nil, "ARTWORK")
	row.zone:SetFontObject(rawget(_G, "ObjectiveTrackerLineFont") or GameFontHighlightSmall)
	row.zone:SetJustifyH("LEFT")
	row.zone:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.zone:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.zone:SetWordWrap(false)
	row.poi = MakePoi(row)
	row.poi:SetPoint("TOPRIGHT", row.title, "TOPLEFT", -7, 5)   -- (where the tracker puts a quest's POI button)
	row.icon = row.poi   -- (v0.2.0's name for it)
	row.pin = MakePin(row)
	row.pin:SetPoint("RIGHT", row.poi, "LEFT", -2, 0)
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", function(self) O.ReadyClick(self.q) end)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	return row
end

local function BuildReady()
	if UI.ready then return UI.ready end
	local f = CreateFrame("Frame", "ValhallaReadyToTurnIn", UIParent)
	f:SetSize(260, 26)
	f:SetFrameStrata("LOW")
	local h = CreateFrame("Frame", nil, f)
	h:SetPoint("TOPLEFT") h:SetPoint("TOPRIGHT") h:SetHeight(26)
	h.bg = h:CreateTexture(nil, "BACKGROUND")
	h.bg:SetPoint("CENTER")
	Atlas(h.bg, "UI-QuestTracker-Secondary-Objective-Header")
	h.text = h:CreateFontString(nil, "ARTWORK")
	h.text:SetFontObject(rawget(_G, "ObjectiveTrackerHeaderFont") or GameFontNormalMed2 or GameFontNormal)
	h.text:SetJustifyH("LEFT")
	h.text:SetWidth(200)
	h.text:SetPoint("LEFT", h, "LEFT", 7, 0)
	h.text:SetText(L["Ready to Turn In"])
	-- (the live Quests header's colour, read only)
	local qh = rawget(_G, "QuestObjectiveTracker")
	qh = type(qh) == "table" and rawget(qh, "Header")
	if type(qh) == "table" and qh.Text and qh.Text.GetTextColor then h.text:SetTextColor(qh.Text:GetTextColor()) end
	-- the collapse button: the Quests header's own template (ObjectiveTrackerModuleMinimizeButtonTemplate:
	-- 16x16, its atlases, its pushed and highlight textures), placed as the tracker places it
	local ok, b = pcall(CreateFrame, "Button", nil, h, "ObjectiveTrackerModuleMinimizeButtonTemplate")
	if ok and type(b) == "table" and b.GetNormalTexture and b:GetNormalTexture() then
		b.native = true
	else
		b = CreateFrame("Button", nil, h)
		b:SetSize(16, 16)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("CENTER")
		b.hl = b:CreateTexture(nil, "HIGHLIGHT")
		b.hl:SetPoint("CENTER")
		if Atlas(b.hl, "ui-questtrackerbutton-yellow-highlight") then b.hl:SetBlendMode("ADD") end
		b:SetScript("OnMouseDown", function(self) self.down = true PaintToggle() end)
		b:SetScript("OnMouseUp", function(self) self.down = nil PaintToggle() end)
	end
	b:SetPoint("RIGHT", h, "RIGHT", 1, 0)
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function()
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
		mod.db.readyCollapsed = not mod.db.readyCollapsed
		S.readyDirty, S.layoutDirty = true, true
		O.FillReady()
	end)
	f.header, f.toggle = h, b
	f.rows = {}
	f:Hide()
	UI.ready = f
	PaintToggle()
	return f
end

local function Title(e)
	local plain = "[" .. tostring(e.level) .. "] " .. e.title
	local fn = rawget(_G, "SetQuestTitleLevelAndDifficultyColor")
	if fn then
		local ok, s = pcall(fn, e.id, e.title)
		if ok and type(s) == "string" then return s, plain, s:find("|c") ~= nil end
	end
	return plain, plain, false
end

function O.FillReady()
	S.readyDirty = false
	local list = S.here and O.ReadyList(S.log, S.here) or {}
	S.readyCount = #list
	if #list == 0 then if UI.ready then UI.ready:Hide() end return 0 end
	local f = BuildReady()
	local n = (mod.db and mod.db.readyCollapsed) and 0 or math.min(#list, O.READY_MAX)
	for i = 1, n do
		local e = list[i]
		local row = f.rows[i] or MakeRow(f)
		f.rows[i] = row
		row.q = e.id
		local text, plain, colored = Title(e)
		row.plain, row.colored = plain, colored
		row.title:SetText(text)
		if not colored then row.title:SetTextColor(TrackerColor("Header", 0.75, 0.61, 0)) end
		row.zone:SetText(e.header or "")
		row.zone:SetTextColor(TrackerColor("Normal", 0.8, 0.8, 0.8))
		row.poi.q = e.id
		O.PaintPoi(row.poi)
		PaintPin(row.pin, e.id)
		row.pin:Show()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -26 - 10 - (i - 1) * O.ROW_H)
		row:SetPoint("RIGHT", f, "RIGHT", -6, 0)
		row:Show()
	end
	for i = n + 1, #f.rows do f.rows[i]:Hide() end
	f:SetHeight(n > 0 and (26 + 10 + n * O.ROW_H) or 26)
	f.n = n
	PaintToggle()
	return #list
end

-- where the section goes: one section gap below the lowest visible part of the tracker (its header,
-- its sections, its rows), in screen pixels; read only
local function Px(f, v) return v and v * (f:GetEffectiveScale() or 1) end
function O.ReadyTarget()
	local T = rawget(_G, "ObjectiveTrackerFrame")
	if type(T) ~= "table" then return nil end
	local left, top = Px(T, T:GetLeft()), Px(T, T:GetTop())
	if not (left and top) then return nil end
	if not Visible(T) then return left, top - Px(T, 38) end   -- (nothing tracked: where its first section would be)
	local low
	local function Take(f)
		if not Visible(f) then return end
		local b = Px(f, f:GetBottom())
		if b and (not low or b < low) then low = b end
	end
	Take(rawget(T, "Header"))
	local mods = rawget(T, "modules")
	if type(mods) == "table" then for _, m in ipairs(mods) do Take(m) end end
	if not low then return left, top end
	return left, low - Px(T, rawget(T, "moduleSpacing") or 10)
end

function O.PlaceReady()
	local f = UI.ready
	if not f then return end
	local T = rawget(_G, "ObjectiveTrackerFrame")
	if (S.readyCount or 0) == 0 or type(T) ~= "table" or rawget(T, "isCollapsed") then f:Hide() return end
	local left, top = O.ReadyTarget()
	if not left then f:Hide() return end
	local us = UIParent:GetEffectiveScale() or 1
	local ts = T:GetEffectiveScale() or us
	local sc = (us > 0 and ts > 0) and ts / us or 1
	if f.sc ~= sc then f:SetScale(sc) f.sc = sc end
	local eff = us * sc
	local x, y, w = left / eff, top / eff, T:GetWidth() or 260
	if f.w ~= w then f:SetWidth(w) f.w = w end
	if f.x ~= x or f.y ~= y then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
		f.x, f.y = x, y
	end
	f:Show()
end

function O.HideFrames()
	for _, p in ipairs(UI.pins) do p:Hide() p.key = nil end
	if UI.ready then UI.ready:Hide() end
end

--------------------------------------------------------------------------------
-- on / off
--------------------------------------------------------------------------------

local events
function O.Tick()
	local now = Now()
	O.Step(now)
	local LP = O.LogPins
	if LP and LP.IsOn() and not LP.Hooked() then LP.Hook() end   -- (the quest log not there yet: tried again)
	if S.readyDirty then O.FillReady() end
	local T = rawget(_G, "ObjectiveTrackerFrame")
	if Visible(T) then O.LayoutPins() else for _, p in ipairs(UI.pins) do p:Hide() p.key = nil end end
	O.PlaceReady()
end

function mod:OnEnable()
	O.Reset()
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", function(_, event, a1) O.OnEvent(event, a1) end)
	end
	for _, e in ipairs(O.EVENTS) do pcall(events.RegisterEvent, events, e) end
	if not S.ticker and C_Timer and C_Timer.NewTicker then S.ticker = C_Timer.NewTicker(O.TICK, O.Tick) end
	S.lastBest = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	O.ZoneDue(Now() - O.SETTLE + 0.5)   -- (the first plan half a second after starting)
	if O.LogPins then O.LogPins.Enable() end   -- (Objectives/QuestLogPins.lua)
end

function mod:OnDisable()
	if events then events:UnregisterAllEvents() end
	if S.ticker then S.ticker:Cancel() S.ticker = nil end
	if O.LogPins then O.LogPins.Disable() end
	O.HideFrames()
	O.Reset()
	if not O.Restore() and events then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")   -- (in combat: given back after it)
	end
end

function O.SetOn(on)
	on = on and true or false
	mod.db.enabled = on
	if on and not mod.enabled then
		mod.enabled = true
		mod:OnEnable()
	elseif not on and mod.enabled then
		mod.enabled = false
		mod:OnDisable()
	end
end

-- /valhalla objectives why [questID]: where Valhalla thinks you are, and why each quest is (not) listed
function O.Why(id)
	local out = {}
	local here = O.Here()
	local log = O.ReadLog()
	local shown = {}
	for k in pairs(here.shown) do shown[#shown + 1] = k end
	table.sort(shown)
	out[#out + 1] = ("Here: %s%s (map %s)"):format(here.inst and "in a dungeon: " or "", table.concat(shown, ", "), tostring(here.best))
	local function Line(e)
		local listed, why = O.Classify(e, here)
		local where = e.ready and "Ready" or "Quests"
		local tag = e.tag and (" tag " .. e.tag) or ""
		out[#out + 1] = ("%d [%s] %s (%s%s): %s, %s"):format(e.id, tostring(e.level), e.title, tostring(e.header), tag,
			listed and ("listed in " .. where) or "not listed", why)
	end
	if id then
		local e = log[id]
		if not e then out[#out + 1] = ("%d: not in your quest log"):format(id) return out end
		Line(e)
		for _, p in ipairs(here.pins[id] or {}) do
			out[#out + 1] = ("  map pin on %d: mapID %s at %.3f, %.3f%s%s%s -> %s"):format(p.map, tostring(p.mapID),
				tonumber(p.x) or 0, tonumber(p.y) or 0, p.indicator and ", map indicator" or "", p.waypoint and ", waypoint" or "",
				p.otherMap and ", another map's" or "", p.kept and "kept" or "dropped")
		end
		if not here.pins[id] then out[#out + 1] = "  no map pins here" end
		local g = here.guard[id]
		if g then
			out[#out + 1] = ("  next waypoint: %s; local marker: %s; counts as a marker here: %s%s"):format(
				g.nextMap and ("map " .. tostring(g.nextMap)) or "none", g.localPOI == nil and "?" or tostring(g.localPOI),
				here.marker[id] and "yes" or "no", g.why and (" (" .. g.why .. ")") or "")
		end
	else
		local list = {}
		for _, e in pairs(log) do list[#list + 1] = e end
		table.sort(list, O.Before)
		for _, e in ipairs(list) do Line(e) end
	end
	return out
end

-- /valhalla objectives [on|off|why [questID]]
function mod:Slash(arg)
	arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local word, rest = arg:match("^(%S+)%s*(.-)$")
	if word == "why" then
		local id = tonumber(rest and rest:match("%d+"))
		for _, line in ipairs(O.Why(id)) do ns:Print("%s", line) end
		return
	end
	if arg == "on" then O.SetOn(true)
	elseif arg == "off" then O.SetOn(false) end
	ns:Print(L["Objectives (zone quests, Ready to Turn In, pins): %s. /valhalla objectives on|off|why [questID]"]:format(
		mod.enabled and L["on"] or L["off"]))
end
