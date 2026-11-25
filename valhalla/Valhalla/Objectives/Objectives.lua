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
--    1.2.52: objective markers no longer count (only a ready quest's turn-in marker, for Ready to Turn In).
--
-- How: Valhalla never edits, hooks or re-parents anything of the game's tracker. It only decides which
-- quests are tracked (C_QuestLog.AddQuestWatch / RemoveQuestWatch) and in what order (re-tracking), and
-- draws its own frames (the pins, the Ready section) beside the tracker, reading where its rows are.
-- Nothing changes while on a flight, during a loading screen or in combat: it waits for the landing,
-- the arrival or the end of the fight. /valhalla objectives off turns it all off (and gives back the
-- quests it untracked).
--
-- v0.4.2.2, progress kept in step: the game can say "9/10" on its quest log update and only have the
-- tenth item counted a moment later, with an event its tracker doesn't listen to. So:
--  * the events that carry it (UNIT_QUEST_LOG_CHANGED, QUEST_WATCH_UPDATE, QUEST_LOG_CRITERIA_UPDATE,
--    QUEST_ITEM_UPDATE, BAG_UPDATE_DELAYED, UI_INFO_MESSAGE) read the log again, 0.5 s after and once more
--    1.5 s after the last one (O.Progress);
--  * those reads (and the Ready to Turn In list) go on in combat, in flight and before a zone's plan:
--    only the watch changes wait, as before;
--  * what the tracker last read is kept (O.Snapshot, at each event it listens to); when a watched quest's
--    objectives change without one, the tracker is made to read again by re-tracking one quest that keeps
--    the order (O.Nudge: out of combat, at most every NUDGE_GAP s). Nothing of the tracker's is called.
--  * ready = the game's ReadyForTurnIn or IsComplete (as its tracker shows it);
--  * /valhalla objectives sync on|off|show: a read-only log (ValhallaDB.objectives.syncLog).
--
-- 1.2.2, new quests: the game can list a quest before its data (its Dungeon tag, its title) is loaded.
--  * QUEST_ACCEPTED asks for the quest's data (C_QuestLog.RequestLoadQuestByID); where it belongs is
--    decided when QUEST_DATA_LOAD_RESULT says it's in (or after DATA_TRIES looks, NEW_GAP apart);
--  * a quest whose log header or tag changes is placed again (O.PlanPartial), not only at a zone change;
--  * a tracker row whose title reads empty gets no pin, and once the quest's data is in the tracker is made
--    to read again (one order-keeping re-track, O.Retrack; at most REDRAW_TRIES a quest);
--  * the game's Quest Timers box (QuestTimerFrame, above the tracker) showing, hiding or resizing: the
--    tracker is made to lay out again once (TIMER_SETTLE after the last), so its header moves below it.
--    (HookScript post-hooks on that frame: nothing of it is changed.)
--
-- 1.2.3, battlegrounds (IsInInstance "pvp"): a battleground quest is one whose log header names a
-- battleground (Alterac Valley, Warsong Gulch, Arathi Basin, their sides' names, or "Battlegrounds").
--  * inside a battleground only its quests are listed (Quests and Ready to Turn In): the header names it, or
--    a battleground quest (that header, or the game's PvP tag 41) with a real pin on its map; pinned as ever;
--  * outdoors and in dungeons battleground quests are hidden, as dungeon quests are (no marker exception);
--  * a quest with the PvP tag under a zone's header (world PvP) stays that zone's quest;
--  * arenas are left as they were (the game's tracker shows no quests there).
--
-- 1.2.15, dungeons by instance ID: inside one, "here" is the game's instance ID -> its Places.lua entry
-- (WoW Forever's own dungeons have no map: City of Dalaran's "best map" can be Alterac Mountains). No outdoor
-- zone's name, map or pins count there; "X: Zone" headers are outdoors only; the entrance zone's Dungeon-tagged
-- quests are this dungeon's; pinned quests still show. /vh objectives why says where each name came from and
-- is kept in ValhallaDB.objectives.lastWhy.
--
-- 1.2.17, a ready dungeon quest outdoors is in Ready to Turn In in the zone of its turn-in (O.TurnIn: the
-- game's marker here, else Valhalla's turn-in data, else the game's map for the quest; unknown: hidden as
-- before); in progress it stays hidden outdoors; inside a dungeon nothing changes. A ready quest tracked
-- again (QUEST_WATCH_LIST_CHANGED) leaves Quests on the quick pass (held in combat, flight, loading).
-- /vh objectives why <id> says the turn-in and its source, the watch type and whether changes are on hold.
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
O.RECHECK_FOR = 4.0             -- 1.2.19: seconds after a zone's plan that "here" is read again (the map may lag)
O.RECHECK_EVERY = 0.5           -- 1.2.19: ...this often
O.RECHECK_CHAIN = 3             -- 1.2.19: re-plans a recheck may start in a row (bounded)
O.LOG_DEBOUNCE = 0.5            -- quest log updates come in bursts
O.NEW_TRIES = 10                -- a new quest's data: looked for this many times, NEW_GAP apart
O.NEW_GAP = 0.4
O.REORDER_TRIES = 3             -- re-order attempts per change before giving up until the next one
O.READY_MAX = 12                -- rows shown in Ready to Turn In
O.PIN_SIZE = 17
O.PIN_OFF_ALPHA = 0.55          -- (1.2.50: was 0.8) an unpinned pin, dimmer
O.GLOW_ATLAS = "UI-QuestPoi-OuterGlow"   -- (1.2.50) a pinned pin's glow: the game's selected quest icon's
O.GLOW_FILE = "Interface\\WorldMap\\UI-QuestPoi-IconGlow"   -- (its file, when the atlas is missing)
O.GLOW_SIZE = 28
O.GLOW_COLOR = { 1, 0.9, 0.55, 0.85 }
O.MARKER_MISSES = 2             -- a quest listed for its marker here goes after this many misses in a row...
O.MARKER_GAP = 0.9              -- ...this many seconds apart (POI data can read empty for a moment)
O.ROW_H = 32
O.SETTLE_READ = 1.5             -- v0.4.2.2: a second read this long after the last progress event
O.NUDGE_GAP = 2.0               -- ...and the tracker made to read again at most this often
O.DATA_TRIES = 6                -- 1.2.2: a new quest's data (tag) waited for this many looks (NEW_GAP apart)
O.REDRAW_TRIES = 3              -- 1.2.2: re-tracks for one quest's empty tracker title (again when its data comes)
O.TIMER_SETTLE = 0.3            -- 1.2.2: after the Quest Timers box shows / hides / resizes, one re-layout
O.SYNC_MAX = 80                 -- /valhalla objectives sync: entries kept
O.SYNC_MINUTES = 30             -- ...and how long it stays on

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

local Now = ns.Util.Clock
-- (1.2.24) "in combat" here is CombatQueue.lua's gate: combat, the player in combat, the game's secret
-- restrictions, or the few seconds after combat; watch, super-track and re-track changes all wait on it
local InCombat = ns.Util.InCombat
local function GateWhy()
	local C = ns.Combat
	if C and C.Why then return C.Why() end
	return InCombat() and { "combat" } or {}
end
local function OnTaxi() return UnitOnTaxi and UnitOnTaxi("player") and true or false end
local Plain, Call = ns.Util.Value, ns.Util.Call
-- (1.2.23) the game's tracker changed only out of combat (CombatQueue.lua: in combat it waits until combat
-- ends, the same quest's or the super-track's last change kept); straight away when that isn't loaded
local TRACK_NOTE = "Tracking changed in combat: it applies when combat ends."
local Defer = ns.Util.Defer
O.Defer = Defer

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
	S.seen = {}             -- v0.4.2.2: [id] = the watched quest's objectives as the tracker last read them
	S.stale = {}            -- [id] = true: changed since, with no event the tracker hears
	S.loaded = {}           -- 1.2.2: [id] = true: QUEST_DATA_LOAD_RESULT said its data is in
	S.keys = {}             -- 1.2.2: [id] = "header|tag" as last placed (a change places it again)
	S.redraw = {}           -- 1.2.2: [id] = re-tracks so far for its empty tracker title
	S.blank = {}            -- 1.2.2: [id] = true: its tracker row's title read empty (waiting)
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
				if not ready then ready = Call(CQ.IsComplete, id) end   -- (v0.4.2.2: either says it, as the tracker)
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

-- 1.2.2: is a quest's data in (its tag readable)? The load result said so, the game's HaveQuestData says so,
-- or this client can't be asked (no RequestLoadQuestByID: decided as before)
function O.DataReady(id)
	if S.loaded[id] then return true end
	local CQ = C_QuestLog
	if not (CQ and CQ.RequestLoadQuestByID) then return true end
	local have = rawget(_G, "HaveQuestData")
	if have and Call(have, id) then return true end
	return false
end
-- (1.2.25) never while CombatQueue.lua's gate holds (combat, secret auras, the settle after combat), and at
-- most once a quest every REQUEST_GAP seconds (it was asked every tick while a tracker row's title read empty)
O.REQUEST_GAP = 10
function O.RequestData(id)
	local CQ = C_QuestLog
	if not (id and CQ and CQ.RequestLoadQuestByID) then return false end
	if InCombat() then return false end
	S.requested = S.requested or {}
	local now = Now()
	local last = S.requested[id]
	if last and now - last < O.REQUEST_GAP then return false end
	S.requested[id] = now
	Call(CQ.RequestLoadQuestByID, id)
	return true
end
-- what places a quest (a change: placed again)
local function KeyOfPlace(e) return tostring(e.header) .. "|" .. tostring(e.tag) end
O.KeyOfPlace = KeyOfPlace

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

local Trim = ns.Util.Trim
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

-- (1.2.3) battlegrounds: their names (and the names their quests' headers use) -> one key each
O.BG_FALLBACK = { "Alterac Valley", "Warsong Gulch", "Arathi Basin" }
O.BG_ALIAS = {
	["silverwing hold"] = "warsong gulch", ["warsong lumber mill"] = "warsong gulch", ["silverwing sentinels"] = "warsong gulch",
	["warsong outriders"] = "warsong gulch",
	["league of arathor"] = "arathi basin", ["defilers"] = "arathi basin", ["trollbane hall"] = "arathi basin",
	["defiler's den"] = "arathi basin",
	["stormpike guard"] = "alterac valley", ["frostwolf clan"] = "alterac valley", ["dun baldar"] = "alterac valley",
	["frostwolf keep"] = "alterac valley",
	["battlegrounds"] = "*", ["battleground"] = "*",   -- (the game's general header: any battleground)
}
local BGS
local function BGs()
	if BGS then return BGS end
	BGS = {}
	for _, n in ipairs(O.BG_FALLBACK) do local k = ZCanon(n) if k then BGS[k] = true end end
	return BGS
end
-- a name's battleground key ("*": any battleground), or nil
function O.BGOf(name)
	local k = ZCanon(name)
	if not k then return nil end
	k = k:gsub("%s+%-%s+.*$", "")
	if O.BG_ALIAS[k] then return O.BG_ALIAS[k] end
	return BGs()[k] and k or nil
end
function O.LearnBG(name) local k = ZCanon(name) if k and not O.BG_ALIAS[k] then BGs()[k] = true end end
O.PVP_TAG = 41   -- Enum.QuestTag.PvP
-- a battleground quest by its header (the PvP tag alone isn't one: world PvP quests sit under their zone)
function O.IsBGQuest(e) return e ~= nil and e.header ~= nil and O.BGOf(e.header) ~= nil end

-- { maps, names (canonical), onMap = { [questID] = true } (the kept pins), pins = { [questID] = { raw pins } },
--   marker = { [questID] = true } (a real marker here that passes every guard: see O.Marker), inst (in a
--   dungeon), instName, instID, instKind, place (Places.lua's entry), entry (the dungeon's entrance zone:
--   canonical name -> name), src (canonical name -> where it came from), skipped (what was left out), key }
--
-- 1.2.15, inside a dungeon: the dungeon is the game's instance ID (GetInstanceInfo's 8th value) -> its
-- Places.lua entry. WoW Forever has no maps of its own dungeons (City of Dalaran, 2959): there the game's
-- "best map" can be the outdoor zone or none, so inside a dungeon
--   * the names are the instance's name and its Places.lua name(s) only; a zone text that names a zone is
--     left out (never an outdoor zone's name);
--   * the map (and its pins) only when it is a real dungeon map (Dungeon type, or named as this dungeon);
--   * the entrance's zone (the Places.lua entry's map) is kept apart: a Dungeon-tagged quest under its header
--     belongs to this dungeon, nothing else of that zone does.
local DUNGEON_MAP = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
O.MAP_TYPES = { [0] = "Cosmic", [1] = "World", [2] = "Continent", [3] = "Zone", [4] = "Dungeon", [5] = "Micro", [6] = "Orphan" }

-- GetInstanceInfo: name, kind, instance ID (Call keeps only two values)
function O.InstanceInfo()
	if type(GetInstanceInfo) ~= "function" then return nil end
	local r = { pcall(GetInstanceInfo) }
	if not r[1] then return nil end
	return Plain(r[2]), Plain(r[3]), tonumber(Plain(r[9]))
end

-- Places.lua's entry for an instance ID: { names = { ... }, map = the entrance zone's uiMapID or nil }
function O.PlaceOf(instID)
	local P = ns.MapPlaces
	if not instID or instID == 0 or type(P) ~= "table" then return nil end
	local out
	for _, it in ipairs(P.instances or {}) do
		for _, d in ipairs(it[4] or {}) do
			if d[1] == instID or (d[1] == 0 and d[6] == instID) then   -- (1.2.18: a 0 entry by its live ID, OpenMap's sixth field)
				out = out or { id = instID, names = {}, map = it.map }
				out.names[#out.names + 1] = d[2]
				if it.map and not out.map then out.map = it.map end
			end
		end
	end
	return out
end

function O.Here()
	local best = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local inInst, kind = nil, nil
	if IsInInstance then inInst, kind = Call(IsInInstance) end
	local inst = inInst and INSTANCE_KINDS[kind] and true or false
	local bg = inInst and kind == "pvp" or false   -- (1.2.3: a battleground, its own kind)
	local zone = (inst or bg) and best or O.ZoneOf(best)
	local here = { maps = {}, names = {}, onMap = {}, pins = {}, marker = {}, guard = {}, best = best, zone = zone, inst = inst, shown = {},
		src = {}, skipped = {}, entry = {}, kind = kind }
	local function AddName(s, from)
		if type(s) ~= "string" or s == "" then return end
		here.shown[s] = true
		local z, d = ZCanon(s), DCanon(s)
		for _, k in ipairs({ z, d }) do
			if k then
				here.names[k] = true
				local list = here.src[k] or {}
				here.src[k] = list
				local seen = false
				for _, f in ipairs(list) do if f == from then seen = true end end
				if not seen then list[#list + 1] = from end
			end
		end
	end
	local function AddMap(m, from)
		if not m or here.maps[m] then return end
		here.maps[m] = true
		local info = MapInfo(m)
		AddName(info and info.name, from or ("map " .. tostring(m)))
	end
	if inst then
		local name, _, id = O.InstanceInfo()
		if type(name) ~= "string" or name == "" then name = nil end
		here.instName, here.instID, here.instKind = name, id, kind
		AddName(name, "instance name")
		O.LearnDungeon(name)
		local place = O.PlaceOf(id)
		here.place = place
		if place then
			for _, n in ipairs(place.names) do AddName(n, "Places.lua " .. tostring(id)) O.LearnDungeon(n) end
			local zi = place.map and MapInfo(place.map)
			local zk = zi and ZCanon(zi.name)
			if zk and not here.names[zk] then here.entry[zk] = zi.name end
		end
		local info = best and MapInfo(best)
		local dk = info and DCanon(info.name)
		if best and info and (info.mapType == DUNGEON_MAP or (dk and here.names[dk])) then
			AddMap(best, "dungeon map " .. tostring(best))
		elseif best then
			here.skipped[#here.skipped + 1] = ("map %s (%s, %s type): not this dungeon's map"):format(tostring(best),
				tostring(info and info.name or "?"), tostring(info and (O.MAP_TYPES[info.mapType] or info.mapType) or "?"))
		end
		for _, t in ipairs({ { GetZoneText, "zone text" }, { GetRealZoneText, "real zone text" } }) do
			local s = t[1] and Call(t[1])
			if type(s) == "string" and s ~= "" then
				local k = ZCanon(s)
				if here.names[k or ""] or here.names[DCanon(s) or ""] or not O.IsZoneName(s) then AddName(s, t[2])
				else here.skipped[#here.skipped + 1] = ("%s \"%s\": an outdoor zone"):format(t[2], s) end
			end
		end
	elseif bg then
		local name = GetInstanceInfo and Call(GetInstanceInfo)
		if type(name) ~= "string" or name == "" then name = GetRealZoneText and Call(GetRealZoneText) end
		O.LearnBG(name)
		here.bg = name or "?"
		here.bgKey = O.BGOf(name) or ZCanon(name) or "?"
		AddName(name, "battleground")
		AddMap(best)
		AddName(GetZoneText and Call(GetZoneText), "zone text")
		AddName(GetRealZoneText and Call(GetRealZoneText), "real zone text")
	else
		AddMap(zone)
		if zone and O.CITY[zone] then AddMap(O.CITY[zone], "the capital's zone") end
		AddName(GetZoneText and Call(GetZoneText), "zone text")
		AddName(GetRealZoneText and Call(GetRealZoneText), "real zone text")
	end
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
	if not inst and not bg then
		for id in pairs(here.onMap) do O.Marker(id, here) end
	end
	local names = {}
	for k in pairs(here.names) do names[#names + 1] = k end
	table.sort(names)
	here.key = tostring(zone) .. (inst and (":inst" .. tostring(here.instID or "") .. ":") or bg and ":bg:" or ":") .. table.concat(names, "|")
	O.ApplyFreeze(here)
	return here
end

-- (1.2.49) a super-track (select or deselect, from any source) never adds a quest to the panel or takes one
-- off: the game's map data for a quest changes when it is selected (its pins, waypoint, local marker), so
-- the quests whose selection changed keep the marker data they had just before, for as long as you stay
-- in this place (here.key). Somewhere else: read afresh (the zone rules). Pins still decide first (Classify).
function O.Freeze(id)
	local here = S.here
	if not (id and id ~= 0 and here) or here.inst then return end
	if S.freezeKey ~= here.key then S.freeze, S.freezeKey = {}, here.key end
	S.freeze = S.freeze or {}
	if S.freeze[id] == nil then
		S.freeze[id] = { marker = here.marker[id] or false, onMap = here.onMap[id] or false,
			pins = here.pins[id] or false, guard = here.guard[id] or false }
	end
end
function O.ApplyFreeze(here)
	if not S.freeze then return end
	if S.freezeKey ~= here.key then S.freeze, S.freezeKey = nil, nil return end
	for id, f in pairs(S.freeze) do
		here.marker[id] = f.marker or nil
		here.onMap[id] = f.onMap or nil
		here.pins[id] = f.pins or nil
		here.guard[id] = f.guard or nil
	end
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

-- 1.2.17, a ready dungeon quest outdoors: listed in Ready to Turn In in the zone of its turn-in. Where that is:
--   1. "marker": the game's marker for it (its turn-in, once ready) on a map of this zone (the zone's own map or
--      one inside it, a city's), not a map indicator or a route's waypoint;
--   2. "data": Valhalla's own turn-in data (ns.QuestTurnIns: [questID] = uiMapID), when it has the quest
--      (none shipped yet: nothing is guessed);
--   3. "game quest map": the game's map for the quest (GetQuestUiMapID, waypoints off: its turn-in marker's
--      map), never a dungeon's map;
--   else "unknown": hidden outdoors as before (/valhalla objectives why says so).
-- Returns the turn-in's map, the source, and whether that's this zone
function O.HereMap(m, here)
	if not m or m == 0 or not here then return false end
	if here.maps[m] then return true end
	local z = O.ZoneOf(m)
	return z ~= nil and (z == here.zone or here.maps[z] == true) or false
end
function O.TurnIn(e, here)
	if not (e and here) then return nil, "unknown", false end
	for _, p in ipairs(here.pins[e.id] or {}) do
		if not p.indicator and not p.waypoint then
			local m = (p.otherMap and p.mapID) or p.map
			if O.HereMap(m, here) then return m, "marker", true end
		end
	end
	local data = type(ns.QuestTurnIns) == "table" and tonumber(ns.QuestTurnIns[e.id]) or nil
	if data then return data, "data", O.HereMap(data, here) end
	local gm = GetQuestUiMapID and tonumber((Call(GetQuestUiMapID, e.id, true)))
	if gm and gm ~= 0 then
		local info = MapInfo(gm)
		if not (info and info.mapType == DUNGEON_MAP) then return gm, "game quest map", O.HereMap(gm, here) end
	end
	return nil, "unknown", false
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
	-- (1.2.3) battlegrounds
	local bgOf = h and O.BGOf(h)
	if here.bg then
		if bgOf and bgOf ~= "*" and bgOf == here.bgKey then return true, ("header \"%s\" is this battleground"):format(h) end
		local pvp = bgOf ~= nil or e.tag == O.PVP_TAG
		if pvp and here.onMap[e.id] then
			return true, ("a battleground quest (%s) with a pin on this battleground's map"):format(bgOf and ("header \"" .. h .. "\"") or "PvP tag")
		end
		if bgOf then return false, ("in a battleground: header \"%s\" is %s"):format(h, bgOf == "*" and "a battleground quest with no pin here" or "another battleground") end
		return false, "in a battleground: only its own quests are listed"
	end
	if bgOf then return false, ("header \"%s\": a battleground quest, listed inside its battleground"):format(h) end
	local function Here(s) return s and (here.names[ZCanon(s) or ""] or here.names[DCanon(s) or ""]) or false end
	-- inside a dungeon (1.2.15: before the "X: Zone" rule, which is outdoors only): its own quests only
	if here.inst then
		if h and Here(h) then return true, ("header \"%s\" is this dungeon"):format(h) end
		local dungeon = O.IsDungeonQuest(e)
		if dungeon and h and here.entry and here.entry[ZCanon(h) or ""] then
			return true, ("a dungeon quest under \"%s\", this dungeon's entrance zone"):format(h)
		end
		if dungeon and here.onMap[e.id] then return true, "a dungeon quest with a pin on this dungeon's map" end
		if h and here.entry and here.entry[ZCanon(h) or ""] then
			return false, ("in a dungeon: header \"%s\" is the outdoor zone around it"):format(h)
		end
		return false, "in a dungeon: only its own quests are listed"
	end
	local dungeon = O.IsDungeonQuest(e)
	if dungeon and e.ready then   -- (1.2.17) ready: in its turn-in's zone too
		local m, src, yes = O.TurnIn(e, here)
		if yes then return true, ("a ready dungeon quest: its turn-in is in this zone (map %s, from the %s)"):format(tostring(m), src) end
		if m then return false, ("a ready dungeon quest: its turn-in is on map %s (from the %s), not this zone"):format(tostring(m), src) end
		return false, "a ready dungeon quest: its turn-in zone is unknown (no marker here, no data): listed inside its dungeon"
	end
	-- "X: Zone" counts as that zone
	local suffix = h and h:match("^[^:]+:%s*(.+)$")
	-- (1.2.52) another zone's quest is never listed for an objective marker here (the game's quest areas reach
	-- into other zones: Goretusk Liver Pie, Westfall Stew in Redridge): the panel is the zone's quests under
	-- its header in the log, plus pinned ones. Only a READY quest's turn-in marker here still counts (Ready to
	-- Turn In's rule: hand it in where you are)
	local function Marked(text)
		if not e.ready or here.inst or O.IsDungeonQuest(e) or not here.marker[e.id] then return false end
		return true, ("%s, but it has %s here"):format(text, e.ready and "a turn-in marker" or "an objective marker")
	end
	if suffix and O.IsZoneName(suffix) then
		if Here(suffix) or Here(h) then return true, ("header \"%s\" counts as %s: here"):format(h, suffix) end
		local text = ("header \"%s\" counts as %s: not here"):format(h, suffix)
		local yes, why = Marked(text)
		if yes then return true, why end
		return false, text
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

-- (1.2.49) every watch change Valhalla makes, as it runs: ValhallaDB.objectives.opsLog (the last OPS_LOG)
O.OPS_LOG = 60
function O.NoteOp(id, what, why)
	local db = mod.db
	if type(db) ~= "table" then return end
	local log = db.opsLog
	if type(log) ~= "table" then log = {} db.opsLog = log end
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
	log[#log + 1] = { clock = date and date("%H:%M:%S") or nil, quest = id, op = what, why = why or "?",
		super = super, event = S.lastEvent }
	while #log > O.OPS_LOG do table.remove(log, 1) end
end
O.KEEP_SUPER = 2                -- seconds: a super-track the game clears after our own watch removal is put back
O.OWN_ADD = 2                   -- seconds: a watch added by Valhalla is its own (not a game's, below)
local function Add(id, why)
	Defer("watch:" .. tostring(id), function()
		S.ownAt = S.ownAt or {}
		S.ownAt[id] = Now()
		O.NoteOp(id, "add", why)
		Call(C_QuestLog.AddQuestWatch, id)
	end)
end
-- (1.2.49) a removal of the super-tracked quest's watch makes the game clear the super-track
-- (SuperTrackEventMixin:OnQuestWatchChanged): it is put back when that clear comes (O.KeepSuper)
local function Remove(id, why)
	Defer("watch:" .. tostring(id), function()
		local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
		if super == id then S.keepSuper = { id = id, untilT = Now() + O.KEEP_SUPER } end
		O.NoteOp(id, "remove", why)
		Call(C_QuestLog.RemoveQuestWatch, id)
	end)
end
-- the selection kept: the game cleared it after our own removal (within KEEP_SUPER)
function O.KeepSuper(super, now)
	local k = S.keepSuper
	if not k then return false end
	if now > k.untilT then S.keepSuper = nil return false end
	if super and super ~= 0 then return false end
	S.keepSuper = nil
	O.NoteOp(k.id, "super", "the game cleared the selection after Valhalla's watch change: put back")
	Defer("supertrack", function() Call(C_SuperTrack.SetSuperTrackedQuestID, k.id) end, TRACK_NOTE)
	return true
end
-- a selection the player changes themselves is theirs: nothing is put back
function O.ForgetKeepSuper() S.keepSuper = nil end

local function Queue(id, add, why, hidden)
	for _, op in ipairs(S.ops) do
		if op.id == id then op.add, op.why, op.hidden = add, why, hidden return end
	end
	S.ops[#S.ops + 1] = { id = id, add = add, why = why, hidden = hidden }
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
		if log[id] and not want[id] then Queue(id, false, "zone plan: not this place's") end
	end
	for _, e in ipairs(target) do
		if not watched[e.id] then Queue(e.id, true, O.IsPinned(e.id) and "zone plan: pinned" or "zone plan: this place's") end
	end
	O.SweepPins(log, n)
	S.keys = {}
	for id, e in pairs(log) do S.keys[id] = KeyOfPlace(e) end
	S.reorderDue, S.reorderTries = Now(), 0
	S.readyDirty = true
	-- (1.2.19) the game's map can lag the zone change: "here" read again for a few seconds (O.Step)
	if (S.recheckChain or 0) < O.RECHECK_CHAIN then
		S.recheckUntil, S.recheckAt = Now() + O.RECHECK_FOR, Now() + O.RECHECK_EVERY
	else
		S.recheckUntil, S.recheckAt, S.recheckChain = nil, nil, 0   -- (the chain's end: the next zone's plan rechecks again)
	end
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
	if new.key ~= old.key then   -- (somewhere else: the full plan that's coming decides)
		if not S.fullDue then O.ZoneDue(now) end   -- (1.2.19: none coming, e.g. after a flight: one now)
		return gained, lost
	end
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

-- (1.2.49) a quest log icon (the game's POIButton: an unwatched quest is watched, then selected) changes
-- nothing in the panel: a watch the game added (not Valhalla's own) with the same quest selected within
-- GAME_WATCH_PAIR seconds is taken back, the quest left as hidden or not as it was; the selection stays
-- (O.KeepSuper). The panel's quests come from the zone rules and pins only.
O.GAME_WATCH_PAIR = 1
O.GAME_WATCH_WAIT = 2
function O.GameWatches(now, watched, log)
	local skip = {}
	for id, g in pairs(S.gameAdd or {}) do
		local sel = S.superAt and S.superAt[id]
		if sel and math.abs(sel - g.t) <= O.GAME_WATCH_PAIR then
			S.gameAdd[id] = nil
			if watched[id] and log[id] then
				skip[id] = true
				Queue(id, false, "quest log icon: the game's watch, not the panel's", g.hidden or false)
			end
		elseif now - g.t > O.GAME_WATCH_WAIT then
			S.gameAdd[id] = nil
		end
	end
	return skip
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
	local skip = O.GameWatches(now, watched, log)
	-- (1.2.2) a quest whose header or tag changed since it was placed (its data came in late): placed again
	local changed = {}
	for id, e in pairs(log) do
		local k = KeyOfPlace(e)
		if S.keys[id] ~= nil and S.keys[id] ~= k and not S.fresh[id] then changed[id] = true end
		if not S.fresh[id] then S.keys[id] = k end
	end
	for id in pairs(S.keys) do if not log[id] then S.keys[id] = nil end end
	for id, e in pairs(log) do
		local listed = O.Listed(e, here)
		if skip[id] then
			-- (1.2.49: the quest log icon's watch, taken back above)
		elseif watched[id] and e.ready then
			Queue(id, false, "ready: Ready to Turn In, not Quests")   -- (ready: shown in Ready to Turn In when listed, never in Quests)
		elseif watched[id] and (lost[id] or changed[id]) and not listed then
			Queue(id, false, lost[id] and "its marker here is gone" or "its place changed")   -- (its marker here is gone, or now it says it's another place's: nothing to do here)
		elseif not watched[id] and not e.ready and listed and (c.hidden[id] or gained[id]) and count < O.MAX_WATCHES then
			Queue(id, true, gained[id] and "a marker here" or "listed again") count = count + 1 added = true
		end
	end
	-- new quests: placed once their entry (and zone header) is there
	for id, f in pairs(S.fresh) do
		if now >= f.due then
			local e = log[id]
			-- (1.2.2) its data in (the Dungeon tag readable), or waited DATA_TRIES looks
			if e and e.header and (O.DataReady(id) or f.tries >= O.DATA_TRIES) then
				S.fresh[id] = nil
				S.keys[id] = KeyOfPlace(e)
				if O.Listed(e, here) then
					if e.ready then
						if watched[id] then Queue(id, false, "new and ready") end
					elseif not watched[id] and count < O.MAX_WATCHES then
						Queue(id, true, "new: this place's") count = count + 1 added = true
					else
						added = true   -- (tracked by the game: put in its place)
					end
				elseif watched[id] then
					Queue(id, false, "new: another place's")   -- another zone's: out until you get there
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

--------------------------------------------------------------------------------
-- v0.4.2.2: progress kept in step (read only, except the one re-track in O.Nudge)
--------------------------------------------------------------------------------

-- a quest's objectives as one string: "9/10- 3/3+ o" (counts, finished, and c when complete)
function O.Sig(id)
	local CQ = C_QuestLog
	if not (id and CQ and CQ.GetQuestObjectives) then return nil end
	local objs = Call(CQ.GetQuestObjectives, id)
	if type(objs) ~= "table" then return nil end
	local parts = {}
	for _, o in ipairs(objs) do
		if type(o) == "table" then
			parts[#parts + 1] = ("%s/%s%s"):format(tostring(Plain(o.numFulfilled)), tostring(Plain(o.numRequired)),
				Plain(o.finished) and "+" or "-")
		end
	end
	parts[#parts + 1] = Call(CQ.IsComplete, id) and "c" or "o"
	return table.concat(parts, " ")
end

-- what the tracker reads now (at each event it listens to, and after Valhalla re-tracks): nothing stale
function O.Snapshot()
	local order = O.WatchOrder()
	local seen = {}
	for _, id in ipairs(order) do seen[id] = O.Sig(id) end
	S.seen = seen
	S.stale = {}
end

-- the log read again (also in combat, in flight, before a zone's plan): the Ready list follows at once;
-- a ready quest still in Quests gets its partial (its watch change waits as ever); a watched quest whose
-- objectives changed since the tracker last read is marked for O.Nudge
function O.Progress(now)
	if not S.here then return end
	local log, n = O.ReadLog()
	if n == 0 then return end
	local old = S.log or {}
	S.log = log
	S.readyDirty = true
	local _, watched = O.WatchOrder()
	local moved = false
	for id, e in pairs(log) do
		local o = old[id]
		if (o and o.ready or false) ~= e.ready or (watched[id] and e.ready) then moved = true end
	end
	if moved then S.partialDue = S.partialDue or now end
	for id in pairs(watched) do
		local e = log[id]
		local sig = e and not e.ready and O.Sig(id)
		if sig then
			local seen = S.seen[id]
			if seen == nil then S.seen[id] = sig
			elseif seen ~= sig then S.stale[id] = true end
		end
	end
	return moved
end

-- the tracker made to read again: one quest re-tracked where it already is (the front one when new
-- watches go to the front, the last when they go to the end), so the order stays; out of combat only
function O.Nudge(now)
	local _, watched = O.WatchOrder()
	local any
	for id in pairs(S.stale) do
		local sig = watched[id] and O.Sig(id)
		if sig and sig ~= S.seen[id] then any = id else S.stale[id] = nil end
	end
	if not any then return nil end
	local lever, order = O.Retrack(any)
	if O.SyncOn() then
		local ids = {}
		for id in pairs(S.stale) do ids[#ids + 1] = id end
		table.sort(ids)
		O.SyncAdd(("nudge: tracker re-read (re-tracked %s) for %s"):format(tostring(lever), table.concat(ids, ",")))
	end
	S.nudges = (S.nudges or 0) + 1
	S.nudgeAt = now + O.NUDGE_GAP
	O.AfterRetrack(now, order)
	return "nudged"
end

-- one quest re-tracked where it already is (the front one when new watches go to the front, the last when
-- they go to the end; else 'any'): the tracker lays out again, the order kept, the super-tracked quest kept.
-- Returns the quest re-tracked and the order before (nil: nothing tracked)
function O.Retrack(any)
	local order = O.WatchOrder()
	if #order == 0 then return nil, order end
	local side = mod.db and mod.db.watchSide
	local lever = (side == "front" and order[1]) or (side == "end" and order[#order]) or any or order[1]
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
	Remove(lever, "re-track (the tracker reads again)") Add(lever, "re-track (the tracker reads again)")
	if super and super ~= 0 and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
		and Call(C_SuperTrack.GetSuperTrackedQuestID) ~= super then
		Defer("supertrack", function() Call(C_SuperTrack.SetSuperTrackedQuestID, super) end)
	end
	return lever, order
end
function O.AfterRetrack(now, order)
	O.Snapshot()
	if not O.Same(O.WatchOrder(), order) then   -- (the side guessed wrong, or not known: put back in order)
		S.reorderDue, S.reorderTries = now + O.TICK, 0
	end
end

-- (1.2.2) tracker rows whose title read empty, their quest's data now in: the tracker made to read again
-- (out of combat, NUDGE_GAP apart, at most REDRAW_TRIES a quest until its data comes again)
function O.Redraw(now)
	local want
	for id in pairs(S.blank) do
		local n = S.redraw[id] or 0
		if n < O.REDRAW_TRIES and O.DataReady(id) then want = want or id S.redraw[id] = n + 1 end
	end
	if not want then return nil end
	local lever, order = O.Retrack(want)
	if not lever then return nil end
	if O.SyncOn() then O.SyncAdd(("redraw: an empty tracker title (quest %s), re-tracked %s"):format(tostring(want), tostring(lever))) end
	S.redraws = (S.redraws or 0) + 1
	S.nudgeAt = now + O.NUDGE_GAP
	O.AfterRetrack(now, order)
	return "redrawn"
end

-- (1.2.2) the Quest Timers box changed: the tracker lays out again once (its header goes below the box)
function O.TimerChanged()
	S.timerDue = Now() + O.TIMER_SETTLE
end
function O.HookTimer()
	if S.timerHooked and O.timerFrame == rawget(_G, "QuestTimerFrame") then return true end
	local f = rawget(_G, "QuestTimerFrame")
	if type(f) ~= "table" or type(f.HookScript) ~= "function" then return false end
	if O.timerFrame ~= f then
		for _, k in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
			pcall(f.HookScript, f, k, function() if mod.enabled ~= false and O.timerFrame == f then O.TimerChanged() end end)
		end
		O.timerFrame = f
	end
	S.timerHooked = true
	return true
end
function O.TimerLayout(now)
	S.timerDue = nil
	local lever, order = O.Retrack()
	if not lever then return nil end
	if O.SyncOn() then O.SyncAdd(("quest timers changed: re-tracked %s"):format(tostring(lever))) end
	S.timerLayouts = (S.timerLayouts or 0) + 1
	O.AfterRetrack(now, order)
	return "timer"
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
				Add(op.id, op.why)
			end
			c.hidden[op.id] = nil
		else
			Remove(op.id, op.why)
			if op.hidden == nil then c.hidden[op.id] = true else c.hidden[op.id] = op.hidden or nil end
		end
		done = done + 1
	end
	if done > 0 then O.Snapshot() end   -- (v0.4.2.2: the watch list changed: the tracker reads it all again)
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
		for _, id in ipairs(fix) do Remove(id, "re-sort") end
		for _, id in ipairs(fix) do Add(id, "re-sort") end
	else
		-- not known yet: all off, then two back on show which end a new one goes to
		for _, id in ipairs(order) do Remove(id, "re-sort") end
		Add(want[1], "re-sort") Add(want[2], "re-sort")
		local now = O.WatchOrder()
		if now[1] == want[1] and now[2] == want[2] then
			side = "end"
			for i = 3, #want do Add(want[i], "re-sort") end
		elseif now[1] == want[2] and now[2] == want[1] then
			side = "front"
			Remove(want[1], "re-sort") Remove(want[2], "re-sort")
			for i = #want, 1, -1 do Add(want[i], "re-sort") end
		else
			for i = 3, #want do Add(want[i], "re-sort") end   -- (the list didn't read back at once: checked next time)
		end
		if side and mod.db then mod.db.watchSide = side end
	end
	if super and super ~= 0 and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
		and Call(C_SuperTrack.GetSuperTrackedQuestID) ~= super then
		Defer("supertrack", function() Call(C_SuperTrack.SetSuperTrackedQuestID, super) end)
	end
	O.Snapshot()   -- (v0.4.2.2: re-tracked: the tracker reads it all again)
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
	-- v0.4.2.2: progress reads are never held (only watch changes are)
	if S.progressDue and now >= S.progressDue then S.progressDue = nil O.Progress(now) end
	if S.settleDue and now >= S.settleDue then S.settleDue = nil O.Progress(now) end
	-- (1.2.19) the taxi just ended: the new zone planned once settled, whether or not PLAYER_CONTROL_GAINED
	-- comes (a zone's plan due from the flight, long past, settles again first). Once per landing
	if S.waitingTaxi and not OnTaxi() then
		S.waitingTaxi = false
		O.ZoneDue(now)
	end
	if O.Blocked() then
		if OnTaxi() then S.waitingTaxi = true end
		return "blocked"
	end
	-- (1.2.19) after a zone's plan: "here" read again a few times; somewhere else now (the map caught up
	-- with no event): planned again, a bounded number of times in a row
	if S.recheckUntil and not S.fullDue and now >= (S.recheckAt or 0) then
		if now > S.recheckUntil or not S.here then
			S.recheckUntil, S.recheckAt, S.recheckChain = nil, nil, 0
		else
			S.recheckAt = now + O.RECHECK_EVERY
			if O.Here().key ~= S.here.key then
				S.recheckUntil, S.recheckAt = nil, nil
				S.recheckChain = (S.recheckChain or 0) + 1
				O.ZoneDue(now)
			end
		end
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
	if next(S.stale) and not S.fullDue and now >= (S.nudgeAt or 0) then   -- (not while a zone's plan is due)
		local r = O.Nudge(now)
		if r then return r end
	end
	if S.timerDue and now >= S.timerDue then
		local r = O.TimerLayout(now)
		if r then return r end
	end
	if next(S.blank) and not S.fullDue and now >= (S.nudgeAt or 0) then
		local r = O.Redraw(now)
		if r then return r end
	end
	if S.reorderDue and now >= S.reorderDue then return O.Reorder() end
end

-- (1.2.49) the selection changed: the quests it left and reached keep their marker data here (O.Freeze);
-- the game's clear after our own removal is put back (O.KeepSuper)
function O.SuperChanged(now)
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
	if S.lastSuper and S.lastSuper ~= 0 then O.Freeze(S.lastSuper) end
	if super and super ~= 0 then
		O.Freeze(super)
		S.superAt = S.superAt or {}
		S.superAt[super] = now
		if S.gameAdd and S.gameAdd[super] then S.partialDue = S.partialDue or now + O.LOG_DEBOUNCE end
	end
	O.KeepSuper(super, now)
	S.lastSuper = super
end
-- a watch added: Valhalla's own (O.OWN_ADD), or the game's (a quest log icon, the Track button...)
function O.WatchAdded(id, now)
	local own = S.ownAt and S.ownAt[id]
	if own and now - own <= O.OWN_ADD then return end
	if O.IconOwns and O.IconOwns(id, now) then return end   -- (1.2.50: the quest log icon's, already taken back)
	S.gameAdd = S.gameAdd or {}
	S.gameAdd[id] = { t = now, hidden = Char().hidden[id] and true or false }
end

--------------------------------------------------------------------------------
-- (1.2.50) the quest log's quest icon: Blizzard's own POI button, kept (QuestLogPins.lua hooks it with
-- HookScript PreClick / OnClick only). POIButtonMixin:OnClick watches an unwatched quest and then selects it
-- (Blizzard_POIButton POIButton.lua:466-474). Its watch is taken back inside that same call, from the
-- QUEST_WATCH_LIST_CHANGED it fires (Blizzard dispatches it inside AddQuestWatch: QuestMapFrame.lua's
-- SetHeaderQuestsTracked brackets its calls with ignoreQuestWatchListChanged), so before the tracker draws
-- (it draws once a frame, when dirty) and before the game selects the quest: no clear follows. Else right
-- after the click ("post-click": the clear that follows is put back, O.KeepSuper); else 1.2.49's pass
-- (O.GameWatches, "late"). In combat it waits on CombatQueue's gate ("queued"). A plain click then flies the
-- map there (QuestFly.lua's Q.Go, the Quest click setting). (1.2.51) Shift-click only links the quest in chat:
-- the chat line is opened just before the game's click when it's closed (ChatFrameUtil.OpenChat), so the
-- game's own first step (ChatFrameUtil.TryInsertQuestLinkForQuestID) links it and returns, touching nothing
-- else. A selected quest (the game clears it before the link) is selected again and linked by Valhalla;
-- whatever else the game did anyway (untrack, track, select) is undone, the watch inside the same event.
-- (1.2.52) In game the chat line opened empty didn't last until the game's click (1.2.51: with the chat closed
-- the quest was tracked and taken back). The chat line deactivates itself when it loses focus while empty
-- (ChatFrameEditBoxMixin:OnEditFocusLost / ShouldDeactivateChatOnEditFocusLost: GetText() == ""), so the
-- link goes into the line in PreClick, right after it opens ("pre-click"): not empty, it stays open, and the
-- game's TryInsertQuestLinkForQuestID finds it, links and returns before any watch call. The game's second
-- copy of the link is taken out after the click (the line put back to the text after ours).
--------------------------------------------------------------------------------
O.ICON_DIAG = 30
local function Super() return C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID) or 0 end
local function Watched(q) local _, set = O.WatchOrder() return set[q] ~= nil end
local function ChatOpen()
	local CU = rawget(_G, "ChatFrameUtil")
	local get = (type(CU) == "table" and CU.GetActiveWindow) or rawget(_G, "ChatEdit_GetActiveWindow")
	if type(get) ~= "function" then return false end
	local ok, w = pcall(get)
	return ok and w ~= nil or false
end
function O.IconDiag(entry)
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local log = db.questLogIconDiag
	if type(log) ~= "table" then log = {} db.questLogIconDiag = log end
	log[#log + 1] = entry
	while #log > O.ICON_DIAG do table.remove(log, 1) end
end
-- the click about to run (PreClick): what the game will change is read against this
function O.IconPre(q, button)
	if not (q and mod.enabled) then S.icon = nil return end
	if button and button ~= "LeftButton" then S.icon = nil return end
	O.ForgetKeepSuper()   -- (the player's own selection)
	local shift = IsShiftKeyDown and IsShiftKeyDown() and true or false
	local chat = ChatOpen()
	local opened, pre = false, nil
	local chatLink = shift and O.ChatLinkClick() or false
	if shift and not chat then
		opened = O.OpenChat()
		chat = ChatOpen()
		if chat then pre = O.PreLink(q) end
	end
	S.icon = { q = q, t = Now(), inClick = true, shift = shift, watched = Watched(q), super = Super(), chat = chat,
		chatOpened = opened and chat or false, pre = pre, chatLink = chatLink }
end
-- (1.2.52) the game links a Shift-click only for its chat-link modifier (IsModifiedClick("CHATLINK"), Shift unless rebound)
function O.ChatLinkClick()
	local f = rawget(_G, "IsModifiedClick")
	if type(f) ~= "function" then return true end
	local ok, v = pcall(f, "CHATLINK")
	return ok and v and true or false
end
-- (1.2.52) the quest's link into the chat line just opened (PreClick): the line is not empty, so it stays open
-- until the game's click. Returns what's needed to take out the game's copy after the click
local function ActiveBox()
	local CU = rawget(_G, "ChatFrameUtil")
	local get = (type(CU) == "table" and CU.GetActiveWindow) or rawget(_G, "ChatEdit_GetActiveWindow")
	if type(get) ~= "function" then return nil end
	local ok, w = pcall(get)
	return ok and type(w) == "table" and w or nil
end
function O.PreLink(q)
	local get = rawget(_G, "GetQuestLink")
	local link = type(get) == "function" and Call(get, q) or nil
	local box = ActiveBox()
	if not (link and box and type(box.Insert) == "function" and type(box.GetText) == "function") then return nil end
	local ok = pcall(box.Insert, box, link)
	if not ok then return nil end
	local okT, after = pcall(box.GetText, box)
	local okC, cursor = false, nil
	if type(box.GetCursorPosition) == "function" then okC, cursor = pcall(box.GetCursorPosition, box) end
	return { box = box, link = link, after = okT and after or nil, cursor = okC and cursor or nil }
end
local function Count(text, part)
	local n, i = 0, 1
	while true do
		local a, b = text:find(part, i, true)
		if not a then return n end
		n, i = n + 1, b + 1
	end
end
-- (1.2.52) after the click: the game's copy of the link (a second one) taken out; "valhalla (pre-click)" and what happened
function O.PreLinkAfter(pre)
	local box = pre.box
	local okT, now = pcall(box.GetText, box)
	if not (okT and type(now) == "string" and type(pre.after) == "string") then return "valhalla (pre-click)" end
	if now == pre.after then return "valhalla (pre-click)" end
	if Count(now, pre.link) == Count(pre.after, pre.link) + 1 and type(box.SetText) == "function" then
		pcall(box.SetText, box, pre.after)
		if pre.cursor and type(box.SetCursorPosition) == "function" then pcall(box.SetCursorPosition, box, pre.cursor) end
		return "valhalla (pre-click; the game's copy taken out)"
	end
	return "valhalla (pre-click)"
end
-- (1.2.51) the game's chat line, opened empty (its own function), for a Shift-click's link
function O.OpenChat()
	local CU = rawget(_G, "ChatFrameUtil")
	local open = (type(CU) == "table" and CU.OpenChat) or rawget(_G, "ChatFrame_OpenChat")
	if type(open) ~= "function" then return false end
	return (pcall(open, "")) and true or false
end
-- the quest's link into the chat line (the game's GetQuestLink and InsertLink); true: inserted
function O.InsertQuestLink(q)
	local get = rawget(_G, "GetQuestLink")
	local link = type(get) == "function" and Call(get, q) or nil
	if not link then return false end
	local CU = rawget(_G, "ChatFrameUtil")
	local insert = (type(CU) == "table" and CU.InsertLink) or rawget(_G, "ChatEdit_InsertLink")
	if type(insert) ~= "function" then return false end
	local ok, done = pcall(insert, link)
	return ok and done and true or false
end
-- Valhalla's own watch call for the click; true: it ran (else waits on the gate)
local function IconWatch(ic, add, why)
	local ran
	if add then
		ran = Defer("watch:" .. tostring(ic.q), function()
			S.ownAt = S.ownAt or {}
			S.ownAt[ic.q] = Now()
			O.NoteOp(ic.q, "add", why)
			Call(C_QuestLog.AddQuestWatch, ic.q)
		end, TRACK_NOTE)
	else
		ran = Defer("watch:" .. tostring(ic.q), function()
			if Super() == ic.q then S.keepSuper = { id = ic.q, untilT = Now() + O.KEEP_SUPER } end
			O.NoteOp(ic.q, "remove", why)
			Call(C_QuestLog.RemoveQuestWatch, ic.q)
		end, TRACK_NOTE)
	end
	return ran and true or false
end
-- QUEST_WATCH_LIST_CHANGED during the click (inside the game's AddQuestWatch / RemoveQuestWatch); true: handled
function O.IconWatchEvent(id, added)
	local ic = S.icon
	if not (ic and ic.inClick and id == ic.q) or ic.busy then return false end
	if ic.shift and not ic.watchEv then ic.watchEv, ic.chatAtWatch = added and "add" or "remove", ChatOpen() end
	if added == true and not ic.watched and not ic.took then
		ic.busy = true
		ic.took, ic.queued = "same-call", not IconWatch(ic, false, "quest log icon: the game's watch, taken back at once")
		ic.busy = nil
		return true
	elseif added == false and ic.shift and ic.watched and not ic.rewatched then
		ic.busy = true
		ic.rewatched, ic.queued = "same-call", not IconWatch(ic, true, "quest log icon Shift-click: the game's untrack undone")
		ic.busy = nil
		return true
	end
	return false
end
-- a watch the click's own handling took back or put back: not a game watch for 1.2.49's pass
function O.IconOwns(id, now)
	local ic = S.icon
	return ic and ic.q == id and (ic.took or ic.rewatched) and now - ic.t <= O.GAME_WATCH_WAIT or false
end
-- the click has run (OnClick post-hook)
function O.IconPost(q)
	local ic = S.icon
	if not (ic and ic.q == q and ic.inClick) then return end
	ic.inClick = false
	local watched, super = Watched(q), Super()
	local entry = { clock = date and date("%H:%M:%S") or nil, source = "icon", surface = "quest log", quest = q, shift = ic.shift or nil }
	if ic.shift then
		entry.act = "shift: link"
		entry.chatOpened = ic.chatOpened or false
		entry.chatLink = ic.chatLink
		if ic.watchEv then entry.gameWatch = ic.watchEv .. (ic.chatAtWatch and " (chat line open)" or " (chat line closed)") end
		local undo = {}
		-- the game took its link step (chat open, nothing changed) or not (selected: cleared first; else
		-- untracked / tracked): then Valhalla links it after undoing the rest
		local gameLinked = not ic.pre and ic.chat and ic.super ~= q and super == ic.super and watched == ic.watched and not ic.took and not ic.rewatched
		if not ic.watched and watched and not ic.took then
			ic.took, ic.queued = "post-click", not IconWatch(ic, false, "quest log icon Shift-click: the game's watch undone")
		end
		if ic.watched and not watched and not ic.rewatched then
			ic.rewatched, ic.queued = "post-click", not IconWatch(ic, true, "quest log icon Shift-click: the game's untrack undone")
		end
		if ic.took then undo[#undo + 1] = "watch taken back (" .. ic.took .. ")" end
		if ic.rewatched then undo[#undo + 1] = "untrack undone (" .. ic.rewatched .. ")" end
		if super ~= ic.super then
			local was = ic.super
			local ran = Defer("supertrack", function()
				if was and was ~= 0 then Call(C_SuperTrack.SetSuperTrackedQuestID, was)
				elseif C_SuperTrack.ClearAllSuperTracked then Call(C_SuperTrack.ClearAllSuperTracked)
				else Call(C_SuperTrack.SetSuperTrackedQuestID, 0) end
			end, TRACK_NOTE)
			if not ran then ic.queued = true end
			undo[#undo + 1] = "selection put back to " .. tostring(was)
		end
		if ic.pre then entry.link = O.PreLinkAfter(ic.pre)
		elseif gameLinked then entry.link = "game"
		elseif O.InsertQuestLink(q) then entry.link = "valhalla"
		else entry.link = "none (no chat line)" end
		entry.undo = #undo > 0 and table.concat(undo, "; ") or "nothing changed"
		entry.takeBack = ic.took or "none"
		entry.queued = ic.queued or false
		entry.fly = "no (Shift)"
		O.IconDiag(entry)
		return
	end
	entry.act = (ic.super == q) and "clear" or (super == q and "select" or "none")
	if not ic.watched and watched and not ic.took then
		ic.took, ic.queued = "post-click", not IconWatch(ic, false, "quest log icon: the game's watch, taken back after the click")
	end
	entry.takeBack = ic.took or (ic.watched and "none (already in the panel)" or "none (no watch added)")
	entry.queued = ic.queued or false
	if entry.act == "select" then
		local wm = ns.GetModule and ns:GetModule("worldmap")
		local Q = wm and wm.QuestFly
		if Q and Q.Go then
			local mapID = GetQuestUiMapID and Call(GetQuestUiMapID, q) or nil
			local ok, moved = pcall(Q.Go, q, mapID, "icon")
			entry.fly = not ok and ("error: " .. tostring(moved)) or (moved and "flew" or ("no (" .. (Q.Mode and Q.Mode() or "?") .. ")"))
		else
			entry.fly = "no (world map off)"
		end
	else
		entry.fly = "no (" .. entry.act .. ")"
	end
	O.IconDiag(entry)
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
	-- v0.4.2.2: progress the tracker doesn't hear (O.Progress), and its own QUEST_AUTOCOMPLETE (O.Snapshot)
	"UNIT_QUEST_LOG_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_LOG_CRITERIA_UPDATE", "QUEST_ITEM_UPDATE",
	"BAG_UPDATE_DELAYED", "UI_INFO_MESSAGE", "QUEST_AUTOCOMPLETE",
	-- 1.2.2: a quest's data loaded (a new quest's tag; an empty tracker title)
	"QUEST_DATA_LOAD_RESULT",
}
O.PROGRESS_EVENTS = { UNIT_QUEST_LOG_CHANGED = true, QUEST_WATCH_UPDATE = true, QUEST_LOG_CRITERIA_UPDATE = true,
	QUEST_ITEM_UPDATE = true, BAG_UPDATE_DELAYED = true, UI_INFO_MESSAGE = true }
-- the events the game's quest tracker updates on (Blizzard_QuestObjectiveTracker.lua): it reads every quest then
O.TRACKER_EVENTS = { QUEST_LOG_UPDATE = true, QUEST_WATCH_LIST_CHANGED = true, QUEST_AUTOCOMPLETE = true,
	SUPER_TRACKING_CHANGED = true, QUEST_TURNED_IN = true, QUEST_POI_UPDATE = true }
-- heard only while the sync log is on
O.SYNC_EVENTS = { "CHAT_MSG_LOOT", "ITEM_PUSH" }
-- ...and the ones it leaves out (frequent, nothing to do with counts)
O.SYNC_SKIP = { QUEST_POI_UPDATE = true, SUPER_TRACKING_CHANGED = true, ZONE_CHANGED = true }

-- a read soon (debounced) and a second one SETTLE_READ after the last event
function O.ProgressDue(now)
	S.progressDue = S.progressDue or now + O.LOG_DEBOUNCE
	S.settleDue = now + O.SETTLE_READ
end

function O.OnEvent(event, a1, a2, ...)
	local now = Now()
	if not O.PROGRESS_EVENTS[event] and event ~= "CHAT_MSG_LOOT" and event ~= "ITEM_PUSH" then S.lastEvent = event end
	if event == "SUPER_TRACKING_CHANGED" then O.SuperChanged(now) end
	-- (1.2.50) a quest log icon click under way: its watch taken back (or a Shift untrack undone) at once
	if event == "QUEST_WATCH_LIST_CHANGED" and a1 and O.IconWatchEvent(a1, a2) then S.partialDue = S.partialDue or now + O.LOG_DEBOUNCE return end
	if event == "QUEST_WATCH_LIST_CHANGED" and a1 and a2 == true then O.WatchAdded(a1, now) end
	if O.SYNC_SKIP[event] == nil and O.SyncOn() then O.SyncEvent(event, a1, a2, now) end
	if O.PROGRESS_EVENTS[event] then
		if event ~= "UNIT_QUEST_LOG_CHANGED" or a1 == "player" then O.ProgressDue(now) end
		return
	end
	if event == "CHAT_MSG_LOOT" or event == "ITEM_PUSH" then return end   -- (the sync log's only)
	if O.TRACKER_EVENTS[event] then
		O.Snapshot()
		if event == "QUEST_LOG_UPDATE" then S.lastQLU = now end
	end
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
		if a1 then
			S.fresh[a1] = { due = now + O.NEW_GAP, tries = 0 }
			S.loaded[a1] = nil
			O.RequestData(a1)   -- (1.2.2: its tag and title; placed when they're in)
		end
	elseif event == "QUEST_DATA_LOAD_RESULT" then
		if a1 and (a2 == nil or a2) and (S.fresh[a1] or (S.log and S.log[a1]) or S.blank[a1]) then
			S.loaded[a1] = true
			S.redraw[a1] = nil   -- (its empty title: tried again now its data is in)
			local f = S.fresh[a1]
			if f then f.due = math.min(f.due, now) end
			S.partialDue = S.partialDue or now + O.LOG_DEBOUNCE
		end
		return
	elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
		if a1 then
			local was = O.Pinned()[a1]
			O.Pinned()[a1] = nil
			Char().hidden[a1] = nil
			S.fresh[a1] = nil
			S.blank[a1], S.redraw[a1], S.loaded[a1], S.keys[a1] = nil, nil, nil, nil
			if S.miss then S.miss[a1] = nil end
			if was then O.NotifyPins(a1) end
		end
		S.partialDue = S.partialDue or now + O.LOG_DEBOUNCE
	elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_POI_UPDATE" or event == "QUEST_WATCH_LIST_CHANGED" then
		-- (1.2.17: a ready quest tracked again, by a click on its marker or by the game, leaves Quests on the
		-- quick pass; held in combat, on a flight or a loading screen and made after)
		S.partialDue = S.partialDue or now + O.LOG_DEBOUNCE
		if event == "QUEST_LOG_UPDATE" then O.ProgressDue(now) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if S.restorePending then O.Restore() end
		-- (1.2.26) turned off: this was only for the restore; once it's done, not heard again
		if not mod.enabled and not S.restorePending and O.events then O.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
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
	if InCombat() then
		S.restorePending = true
		-- (1.2.24) also through the queue: secret auras end with no PLAYER_REGEN_ENABLED
		local C = ns.Combat
		if C and C.Run then C.Run("objectives:restore", function() if S.restorePending then O.Restore() end end) end
		return false
	end
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
		Add(e.id, "turned off: given back") count = count + 1
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
-- (1.2.53) Shift + left-click on our pin never pins or unpins (in game a Shift-click here changed the panel:
-- opsLog 19:17 "zone plan: pinned" then "not this place's"): it puts the quest's link in chat instead, the chat
-- line opened first when it's closed (O.OpenChat, then the link straight into that line: O.PreLink, as 1.2.52's
-- pre-click). Every pin click is logged in questLogIconDiag (source "pin", its surface, Shift, toggled, link)
function O.PinLink(q)
	if ChatOpen() then return O.InsertQuestLink(q) and "valhalla" or "none (no link)", false end
	local opened = O.OpenChat()
	if not ChatOpen() then return "none (no chat line)", false end
	if O.PreLink(q) then return "valhalla", opened end
	return O.InsertQuestLink(q) and "valhalla" or "none (no link)", opened
end
local function PinClick(self, button)
	local q = self.q
	if not q then return end
	if button and button ~= "LeftButton" then return end
	local shift = IsShiftKeyDown and IsShiftKeyDown() and true or false
	local entry = { clock = date and date("%H:%M:%S") or nil, source = "pin", surface = self.surface or "side panel", quest = q, shift = shift }
	if shift then
		entry.act, entry.toggled = "shift: link", false
		entry.link, entry.chatOpened = O.PinLink(q)
		O.IconDiag(entry)
		return
	end
	if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
	local on = not O.IsPinned(q)
	O.SetPinned(q, on)
	entry.act, entry.toggled = on and "pin" or "unpin", true
	O.IconDiag(entry)
	if GameTooltip and GameTooltip:IsOwned(self) then PinTip(self) end
end

local function MakePin(parent, surface)
	local b = CreateFrame("Button", nil, parent or UIParent)
	b.surface = surface or "side panel"   -- (1.2.53: for the click log)
	b:SetSize(O.PIN_SIZE, O.PIN_SIZE)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	-- (1.2.50) pinned: the game's selected-quest glow round our pin (only our own button's texture)
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetSize(O.GLOW_SIZE, O.GLOW_SIZE)
	b.glow:SetPoint("CENTER")
	if not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(O.GLOW_ATLAS) then
		b.glow:SetAtlas(O.GLOW_ATLAS)
	else
		b.glow:SetTexture(O.GLOW_FILE)
	end
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(O.GLOW_COLOR[1], O.GLOW_COLOR[2], O.GLOW_COLOR[3])
	b.glow:SetAlpha(O.GLOW_COLOR[4])
	b.glow:Hide()
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
		b.icon:SetAlpha(on and 1 or O.PIN_OFF_ALPHA)
		if b.glow then b.glow:SetShown(on) end
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
	-- (1.2.26: five times a second: the last pass's table reused, no key strings; strata and level set on a change)
	local blank = S.blankSpare or {}
	S.blankSpare = nil
	for k in pairs(blank) do blank[k] = nil end
	for _, it in ipairs(blocks) do
		local b = it.b
		-- (1.2.2) a row whose title reads empty (its quest's data not in when the tracker drew it): no pin;
		-- the tracker is made to read it again once the data's in (O.Redraw)
		local ht = rawget(b, "HeaderText")
		local text = type(ht) == "table" and ht.GetText and ht:GetText()
		if type(ht) == "table" and (type(text) ~= "string" or text == "") then
			blank[it.q] = true
			O.RequestData(it.q)   -- (1.2.25: gated, at most once a quest every REQUEST_GAP s: asked again if skipped)
		else
			n = n + 1
			local p = UI.pins[n] or MakePin(UIParent)
			UI.pins[n] = p
			local poi = Visible(rawget(b, "poiButton")) and b.poiButton or nil
			if p.key ~= b or p.keyQ ~= it.q or p.keyPoi ~= poi then
				p.key, p.keyQ, p.keyPoi = b, it.q, poi
				p:ClearAllPoints()
				p:SetPoint("RIGHT", poi or rawget(b, "HeaderText") or b, "LEFT", -2, 0)
			end
			local strata, level = b:GetFrameStrata() or "LOW", (b:GetFrameLevel() or 1) + 5
			if p.keyStrata ~= strata then p.keyStrata = strata p:SetFrameStrata(strata) end
			if p.keyLevel ~= level then p.keyLevel = level p:SetFrameLevel(level) end
			PaintPin(p, it.q)
			p:Show()
		end
	end
	for i = n + 1, #UI.pins do UI.pins[i]:Hide() UI.pins[i].key = nil end
	for id in pairs(S.redraw) do if not blank[id] then S.redraw[id] = nil end end
	S.blankSpare = S.blank ~= blank and S.blank or nil
	S.blank = blank
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
	O.ForgetKeepSuper()
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and Call(C_SuperTrack.GetSuperTrackedQuestID)
	if super == q then
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
		Defer("supertrack", function()
			if C_SuperTrack.ClearAllSuperTracked then Call(C_SuperTrack.ClearAllSuperTracked)
			else Call(C_SuperTrack.SetSuperTrackedQuestID, 0) end
		end, TRACK_NOTE)
	else
		if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
			Defer("supertrack", function() Call(C_SuperTrack.SetSuperTrackedQuestID, q) end, TRACK_NOTE)
		end
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
		ns.Parts.PaintQuestPoi(b, b.q, U and U.Style and U.Style.QuestComplete or 3, sel)
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

local function MakePoi(row)
	-- (the game's button: UI/Parts.lua, shared with the world map's quest icons)
	local b = ns.Parts.QuestPoi(row)
	if b then
		b:SetScript("OnClick", O.PoiClick)
		if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
		return b
	end
	-- (no template: drawn the same size, the same toggle)
	b = CreateFrame("Button", nil, row)
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
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		Defer("supertrack", function() Call(C_SuperTrack.SetSuperTrackedQuestID, q) end, TRACK_NOTE)
	end
	if not InCombat() then
		local open = rawget(_G, "QuestMapFrame_OpenToQuestDetails")
		if open then pcall(open, q) end   -- (the map's quest fly-to follows Blizzard's details: Map/QuestFly.lua)
	else
		-- (v0.4.2.4) in combat, with the map open: the fly-to alone (Blizzard's details still wait)
		local wm = ns.GetModule and ns:GetModule("worldmap")
		if wm and wm.FlyToQuest then pcall(wm.FlyToQuest, q) end
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
	if mod.db and mod.db.syncOn and not O.SyncOn() then O.SyncSet(false, "after " .. O.SYNC_MINUTES .. " minutes") end
	O.Step(now)
	if O.SyncOn() then O.SyncLate(now) end
	local LP = O.LogPins
	if LP and LP.IsOn() and not LP.Hooked() then LP.Hook() end   -- (the quest log not there yet: tried again)
	if not S.timerHooked then O.HookTimer() end   -- (1.2.2: Blizzard_QuestTimer may load later)
	if S.readyDirty then O.FillReady() end
	local T = rawget(_G, "ObjectiveTrackerFrame")
	if Visible(T) then O.LayoutPins() else for _, p in ipairs(UI.pins) do p:Hide() p.key = nil end end
	O.PlaceReady()
end

function mod:OnEnable()
	O.Reset()
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", function(_, event, ...) O.OnEvent(event, ...) end)
		O.events = events
	end
	for _, e in ipairs(O.EVENTS) do pcall(events.RegisterEvent, events, e) end
	if O.SyncOn() then for _, e in ipairs(O.SYNC_EVENTS) do pcall(events.RegisterEvent, events, e) end end
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
	out[#out + 1] = ("Here: %s%s (map %s)"):format(here.inst and "in a dungeon: " or here.bg and "in a battleground: " or "", table.concat(shown, ", "), tostring(here.best))
	-- (1.2.15) where that came from: the instance, the map and each name's source
	local inInst, kind = nil, nil
	if IsInInstance then inInst, kind = Call(IsInInstance) end
	if inInst then
		local name, _, id = O.InstanceInfo()
		local place = O.PlaceOf(id)
		out[#out + 1] = ("  instance: ID %s (%s, %s) -> Places.lua: %s"):format(tostring(id), tostring(name), tostring(kind),
			place and (table.concat(place.names, " / ") .. (place.map and (" (entrance on map " .. place.map .. ")") or "")) or "not listed")
	else
		out[#out + 1] = ("  instance: none (%s)"):format(tostring(kind))
	end
	local info = here.best and MapInfo(here.best)
	out[#out + 1] = ("  map: %s%s"):format(tostring(here.best), info and (" " .. tostring(info.name) .. ", " ..
		tostring(O.MAP_TYPES[info.mapType] or info.mapType) .. " type" .. (here.maps[here.best] and ", used" or ", not used")) or "")
	local keys = {}
	for k in pairs(here.src or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = ("%s (%s)"):format(k, table.concat(here.src[k], ", ")) end
	out[#out + 1] = "  names: " .. (#parts > 0 and table.concat(parts, "; ") or "none")
	for k, n in pairs(here.entry or {}) do out[#out + 1] = ("  entrance zone: %s (only its Dungeon-tagged quests count here)"):format(n) end
	for _, t in ipairs(here.skipped or {}) do out[#out + 1] = "  left out: " .. t end
	local function Line(e)
		local listed, why = O.Classify(e, here)
		local where = e.ready and "Ready" or "Quests"
		local tag = e.tag and (" tag " .. e.tag) or ""
		out[#out + 1] = ("%d [%s] %s (%s%s): %s, %s"):format(e.id, tostring(e.level), e.title, tostring(e.header), tag,
			listed and ("listed in " .. where) or "not listed", why)
	end
	if id then
		local e = log[id]
		if not e then out[#out + 1] = ("%d: not in your quest log"):format(id) O.SaveWhy(out, id) return out end
		Line(e)
		for _, p in ipairs(here.pins[id] or {}) do
			out[#out + 1] = ("  map pin on %d: mapID %s at %.3f, %.3f%s%s%s -> %s"):format(p.map, tostring(p.mapID),
				tonumber(p.x) or 0, tonumber(p.y) or 0, p.indicator and ", map indicator" or "", p.waypoint and ", waypoint" or "",
				p.otherMap and ", another map's" or "", p.kept and "kept" or "dropped")
		end
		if not here.pins[id] then out[#out + 1] = "  no map pins here" end
		-- (1.2.17) its turn-in (ready dungeon quests outdoors), its watch, and whether watch changes wait
		local m, src = O.TurnIn(e, here)
		out[#out + 1] = ("  turn-in: %s (from the %s)%s"):format(m and ("map " .. tostring(m) .. (MapInfo(m) and (" " .. tostring(MapInfo(m).name)) or "")) or "unknown",
			src, (m and O.HereMap(m, here)) and ", this zone" or "")
		local wt = C_QuestLog and C_QuestLog.GetQuestWatchType and Call(C_QuestLog.GetQuestWatchType, id)
		local _, watched = O.WatchOrder()
		out[#out + 1] = ("  watch: %s%s"):format(watched[id] and "tracked" or "not tracked",
			wt ~= nil and (" (watch type " .. tostring(wt) .. (wt == 0 and ", automatic" or wt == 1 and ", manual" or "") .. ")") or "")
		local hold = {}
		for _, w in ipairs(GateWhy()) do hold[#hold + 1] = w end
		if OnTaxi() then hold[#hold + 1] = "flight" end
		if S.loading then hold[#hold + 1] = "loading screen" end
		out[#out + 1] = ("  watch changes: %s; queued %d%s"):format(#hold > 0 and ("on hold (" .. table.concat(hold, ", ") .. ")") or "not on hold",
			#(S.ops or {}), (S.partialDue or S.fullDue) and ", a pass is due" or "")
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
	O.SaveWhy(out, id)
	return out
end

-- (1.2.15) the last /valhalla objectives why, kept in ValhallaDB.objectives.lastWhy (read back from the saved file)
O.WHY_MAX = 150
function O.SaveWhy(lines, id)
	local d = mod.db
	if type(d) ~= "table" then return end
	local keep = {}
	for i = 1, math.min(#lines, O.WHY_MAX) do keep[i] = lines[i] end
	if #lines > O.WHY_MAX then keep[#keep + 1] = ("(%d more lines left out)"):format(#lines - O.WHY_MAX) end
	d.lastWhy = { at = date and date("%Y-%m-%d %H:%M:%S") or nil, quest = id, version = ns.version, lines = keep }
end

--------------------------------------------------------------------------------
-- /valhalla objectives sync on|off|show (v0.4.2.2): a read-only log of quest progress as the game reports it,
-- saved in ValhallaDB.objectives.syncLog (the last SYNC_MAX entries; on for SYNC_MINUTES). Each event, with
-- what held Valhalla back then; each watched or ready quest whose objectives changed, with ReadyForTurnIn and
-- IsComplete; re-read 1 s and 3 s later ("late": changed after the event; "noQLU": with no quest log update
-- since, so the tracker didn't hear it). It changes no watches.
--------------------------------------------------------------------------------

local function Epoch() local t = rawget(_G, "time") return type(t) == "function" and t() or nil end
function O.SyncOn()
	local d = mod.db
	if not (d and d.syncOn) then return false end
	local t = Epoch()
	return not (t and d.syncUntil and t >= d.syncUntil)
end

function O.SyncAdd(line)
	local d = mod.db
	if not d then return end
	if type(d.syncLog) ~= "table" then d.syncLog = {} end
	local date = rawget(_G, "date")
	local clock = type(date) == "function" and date("%H:%M:%S") or ""
	local log = d.syncLog
	log[#log + 1] = ("%s %.1f %s"):format(clock, Now(), line)
	while #log > O.SYNC_MAX do table.remove(log, 1) end
end

function O.SyncSet(on, why)
	local d = mod.db
	if not d then return end
	if on then
		d.syncOn, d.syncUntil = true, (Epoch() or 0) + O.SYNC_MINUTES * 60
		if not Epoch() then d.syncUntil = nil end
		d.syncLog = {}
		S.diagSig, S.lateAt = {}, nil
		if events then for _, e in ipairs(O.SYNC_EVENTS) do pcall(events.RegisterEvent, events, e) end end
		O.SyncAdd("sync log on")
		O.SyncQuests("start", Now())
	else
		if d.syncOn then O.SyncAdd("sync log off" .. (why and (" (" .. why .. ")") or "")) end
		d.syncOn, d.syncUntil = nil, nil
		S.diagSig, S.lateAt = nil, nil
		if events and events.UnregisterEvent then for _, e in ipairs(O.SYNC_EVENTS) do pcall(events.UnregisterEvent, events, e) end end
	end
end

local function BlockedWhy()
	local t = {}
	for _, w in ipairs(GateWhy()) do t[#t + 1] = w end
	if OnTaxi() then t[#t + 1] = "taxi" end
	if S.loading then t[#t + 1] = "loading" end
	if S.fullDue then t[#t + 1] = "zone plan due" end
	return #t > 0 and table.concat(t, ",") or "-"
end

-- the watched and ready quests whose objectives changed since last written down
function O.SyncQuests(tag, now)
	S.diagSig = S.diagSig or {}
	local CQ = C_QuestLog
	local log = O.ReadLog()
	local _, watched = O.WatchOrder()
	local ready = {}
	for _, e in ipairs(S.here and O.ReadyList(S.log, S.here) or {}) do ready[e.id] = true end
	local ids = {}
	for id, e in pairs(log) do if watched[id] or e.ready then ids[#ids + 1] = id end end
	table.sort(ids)
	local n = 0
	for _, id in ipairs(ids) do
		local sig = O.Sig(id) or "?"
		local rft, ic = Call(CQ.ReadyForTurnIn, id), Call(CQ.IsComplete, id)
		local key = sig .. "|" .. tostring(rft)
		if S.diagSig[id] ~= key then
			S.diagSig[id] = key
			n = n + 1
			O.SyncAdd(("  %s q%d %s rft=%s ic=%s %s%s%s%s"):format(tag, id, sig, tostring(rft), tostring(ic),
				watched[id] and "watched" or "not watched", ready[id] and ", in Ready" or "",
				((rft and true or false) ~= (ic and true or false)) and " RFT!=IC" or "",
				S.stale[id] and " stale" or ""))
		end
	end
	return n
end

function O.SyncEvent(event, a1, a2, now)
	local args = {}
	if a1 ~= nil then args[#args + 1] = tostring(a1) end
	if a2 ~= nil then args[#args + 1] = tostring(a2) end
	O.SyncAdd(("%s %s [held: %s]"):format(event, table.concat(args, " "), BlockedWhy()))
	O.SyncQuests("at", now)
	S.lateFrom = now
	S.lateAt = { now + 1, now + 3 }
end

-- the re-reads after an event
function O.SyncLate(now)
	local L2 = S.lateAt
	if not L2 then return end
	for i = 1, 2 do
		if L2[i] and now >= L2[i] then
			L2[i] = false
			local heard = S.lastQLU and S.lateFrom and S.lastQLU > S.lateFrom
			O.SyncQuests(("late+%ds%s"):format(i == 1 and 1 or 3, heard and "" or " noQLU"), now)
		end
	end
	if not L2[1] and not L2[2] then S.lateAt = nil end
end

function O.SyncShow()
	local d = mod.db or {}
	local log = type(d.syncLog) == "table" and d.syncLog or {}
	local out = {}
	out[#out + 1] = ("Objectives sync log: %s, %d entries (ValhallaDB.objectives.syncLog); tracker re-reads this session: %d")
		:format(O.SyncOn() and "on" or "off", #log, S.nudges or 0)
	local hits = {}
	for _, line in ipairs(log) do
		if line:find("late%+") or line:find("RFT!=IC") or line:find("nudge:") or line:find(" stale") then hits[#hits + 1] = line end
	end
	if #hits == 0 then out[#out + 1] = "  nothing late or mismatched recorded"
	else for i = math.max(1, #hits - 14), #hits do out[#out + 1] = hits[i] end end
	return out
end

-- /valhalla objectives [on|off|why [questID]|sync on|off|show]
function mod:Slash(arg)
	arg = Trim(arg):lower()
	local word, rest = arg:match("^(%S+)%s*(.-)$")
	if word == "sync" then
		if rest == "on" then
			O.SyncSet(true)
			ns:Print("Objectives sync log on for %d minutes (read only; saved in ValhallaDB.objectives.syncLog). /valhalla objectives sync show|off", O.SYNC_MINUTES)
		elseif rest == "off" then
			O.SyncSet(false, "turned off")
			ns:Print("Objectives sync log off (kept until it's turned on again).")
		else
			for _, line in ipairs(O.SyncShow()) do ns:Print("%s", line) end
		end
		return
	end
	if word == "why" then
		local id = tonumber(rest and rest:match("%d+"))
		for _, line in ipairs(O.Why(id)) do ns:Print("%s", line) end
		ns:Print("%s", "(saved in ValhallaDB.objectives.lastWhy once you /reload or log out)")
		return
	end
	if arg == "on" then O.SetOn(true)
	elseif arg == "off" then O.SetOn(false) end
	ns:Print(L["Objectives (zone quests, Ready to Turn In, pins): %s. /valhalla objectives on|off|why [questID]|sync on|off|show"]:format(
		mod.enabled and L["on"] or L["off"]))
end
