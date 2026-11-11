--------------------------------------------------------------------------------
-- Quest fly-to (v0.4.2.4): click a quest (its title in the game's tracker or the quest log, a Ready to
-- Turn In row, one of Valhalla's quest icons on the map) and the map zooms out, glides over and zooms in
-- to it, one smooth flight (FlyPath.lua, WorldMap.lua's `fly`). Blizzard's own click is kept as it is
-- (the log opens on the quest's details, its map is put up): this only moves the camera after it, from a
-- post-hook (hooksecurefunc) on QuestMapFrame_ShowQuestDetails. No Blizzard function is replaced and
-- nothing protected is called, so it runs in combat too.
--   where to:  the game's marker for the quest: the next stop on its route (a boat, a zeppelin) unless its
--              waypoints are turned off; else its objective area while in progress, its turn-in once
--              complete; else its zone whole. A dungeon's quest: the dungeon's entrance. None: a note
--   from:      the view on screen; the map closed when clicked: your character, at its zone's view
--   landing:   Whole zone (the zone's fit, centred on the quest) or Close-up (about twice as close)
--   settings:  Quest click Fly to it | Jump to it | As Blizzard; speed Slow | Normal | Fast; landing;
--              short trips: zoom out by distance (a short hop glides) or always zoom out (at least 2x)
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local L = ns.L
local Safe = ns.Safe

local d = mod.defaults
d.questFly = "fly"              -- a quest clicked: "fly" (fly to it), "jump" (at once), "blizzard" (the zone whole, as Blizzard)
d.questFlySpeed = "normal"      -- "slow" | "normal" | "fast"
d.questFlyLanding = "zone"      -- "zone" (the zone whole, centred on the quest) | "close" (about twice as close)
d.questFlyShort = "auto"        -- "auto" (zoom out by distance: a short hop glides) | "out" (always zoom out, SHORT_OUT)

local Q = {}
mod.QuestFly = Q
Q.LANDING_LEAST = 6             -- never further out than this on landing (Quests.lua's icons' ZOOM_TO)
Q.ZONE_FIT = 1.05               -- Whole zone: just over the zone's fit (the map underneath stays the quest's zone)
Q.CLOSE_FIT = 2                 -- Close-up: about twice the zone's fit
Q.SHORT_OUT = 2                 -- Always zoom out: the trip rises at least this many times out
Q.NOTE_TIME = 3                 -- seconds the "No map location" note shows
Q.RETRY_FRAMES = 3              -- a flight cut by a view Blizzard put up within this many frames of starting: once more

local MODES = { fly = true, jump = true, blizzard = true }
local SPEEDS = { slow = true, normal = true, fast = true }
local map, watcher, note, noteToken
local pending                   -- the flight just started: { q, n, resets, frames, from, to, retried }

function Q.Mode() local m = mod.db.questFly return MODES[m] and m or "fly" end
function Q.Speed() local s = mod.db.questFlySpeed return SPEEDS[s] and s or "normal" end

local function Ping(q)
	if EventRegistry and EventRegistry.TriggerEvent then pcall(EventRegistry.TriggerEvent, EventRegistry, "MapCanvas.PingQuestID", q) end
end
Q.Ping = Ping

local function ZoneType(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone or false
end

-- the deepest zone (or city) of the stitched map at a world point; else the deepest map there
local function ZoneAt(u, v)
	local chain = S.ChainAt and S.ChainAt(u, v) or {}
	for i = #chain, 1, -1 do
		if chain[i] ~= S.WORLD and ZoneType(chain[i]) and S.Rect(chain[i]) then return chain[i] end
	end
	for i = #chain, 1, -1 do
		if chain[i] ~= S.WORLD and S.Rect(chain[i]) then return chain[i] end
	end
end
Q.ZoneAt = ZoneAt

-- the landing zoom: the zone's fit (a zone shown whole), else Whole zone / Close-up round the quest
function Q.Landing(kind, zoneMap)
	local fit = zoneMap and S.Rect(zoneMap) and mod.FitZoom(zoneMap)
	if kind == "zone" and fit then return fit end
	local k = mod.db.questFlyLanding == "close" and Q.CLOSE_FIT or Q.ZONE_FIT
	return math.max(Q.LANDING_LEAST, (fit or 0) * k)
end

-- the quest's details are open and its waypoints turned off there (Blizzard's "show the destination" button)
local function IgnoringWaypoints(q)
	local df = QuestMapFrame and QuestMapFrame.DetailsFrame
	return df and df.questID == q and df.WaypointMapButton and df.WaypointMapButton:IsShown() and true or false
end

-- where to fly for quest q on Blizzard's map for it (mapID): u, v (world, normalized), the map to land
-- on, and what it is: "waypoint" | "poi" | "zone" | "entrance". Nothing: nil and why ("none": the game
-- has no place for it; "other": a map Valhalla doesn't stitch, left to Blizzard)
function Q.Target(q, mapID)
	if not mapID or mapID == 0 then return nil, nil, nil, "none" end
	local eu, ev
	if mod.DungeonEntrance then eu, ev = mod.DungeonEntrance(mapID) end
	if eu then return eu, ev, ZoneAt(eu, ev), "entrance" end
	if not S.Rect(mapID) then return nil, nil, nil, "other" end
	local x, y, kind
	if C_QuestLog.GetNextWaypoint and Safe.Call(C_QuestLog.GetNextWaypoint, q) and not IgnoringWaypoints(q) and C_QuestLog.GetNextWaypointForMap then
		local ok, wx, wy = pcall(C_QuestLog.GetNextWaypointForMap, q, mapID)
		if ok and type(wx) == "number" and type(wy) == "number" then x, y, kind = wx, wy, "waypoint" end
	end
	if not x and C_QuestLog.GetQuestsOnMap then
		for _, info in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
			if info.questID == q and not info.isMapIndicatorQuest and info.x and info.y then
				x, y, kind = info.x, info.y, "poi"
				break
			end
		end
	end
	if x then
		local u, v = mod.ToWorld(mapID, x, y)
		return u, v, mapID, kind
	end
	local l, r, t, b = S.Rect(mapID)
	return (l + r) / 2, (t + b) / 2, mapID, "zone"
end

-- your character's place and its zone's view (the map was closed when the quest was clicked)
function Q.PlayerView()
	local best = Safe.Call(C_Map.GetBestMapForUnit, "player")
	for _ = 1, 8 do
		if not best or S.Rect(best) then break end
		local info = C_Map.GetMapInfo(best)
		best = info and info.parentMapID ~= 0 and info.parentMapID or nil
	end
	if not best or not S.Rect(best) then return end
	local pos = C_Map.GetPlayerMapPosition(best, "player")
	local x, y = Safe.XY(pos)
	if not x or not y or Safe.IsSecret(x) or Safe.IsSecret(y) then return end
	local u, v = mod.ToWorld(best, x, y)
	return u, v, mod.FitZoom(best)
end

-- where the flight starts: the view drawn last (before Blizzard put the quest's map up); the map
-- closed when clicked (it opened just now, or nothing's been drawn yet): from your character
function Q.StartView()
	local lu, lv, lz = mod.LastView()
	if mod.shownAt == GetTime() or not lu then
		local u, v, z = Q.PlayerView()
		if u then return u, v, z end
	end
	if lu then return lu, lv, lz end
	return mod.ViewNow()
end

-- "No map location for this quest", a moment at the top of the map
function Q.Note()
	local parent = map and (map.ScrollContainer or map)
	if not parent then return end
	if not note then
		note = CreateFrame("Frame", nil, parent)
		note:SetSize(300, 26)
		note:SetPoint("TOP", parent, "TOP", 0, -36)
		note:SetFrameStrata("DIALOG")
		local bg = note:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.65)
		note.text = note:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		note.text:SetPoint("CENTER")
		note.text:SetText(L["No map location for this quest"])
		if ns.Style and ns.Style.Title then pcall(ns.Style.Title, note.text, 12) end
	end
	note:Show()
	noteToken = (noteToken or 0) + 1
	local token = noteToken
	C_Timer.After(Q.NOTE_TIME, function() if token == noteToken and note then note:Hide() end end)
end
function Q.NoteShown() return note and note:IsShown() or false end

local function Fly(q, from, to)
	if from then mod.ShowNow(from[1], from[2], from[3]) end   -- (the start, before anything's drawn: no frame of the zone whole)
	mod.FlyTo(to[1], to[2], to[3], { from = from, speed = Q.Speed(),
		zoomOut = mod.db.questFlyShort == "out" and Q.SHORT_OUT or nil, id = q, onDone = function() Ping(q) end })
	local _, n = mod.Flying()
	return n
end

-- quest q to its place on Blizzard's map for it (mapID). how: "details" (Blizzard has just shown its details
-- and pinged it), "icon", "ready". Returns whether the camera moved
function Q.Go(q, mapID, how)
	if not q or not mod.enabled or not map or not map:IsShown() then return false end
	local mode = Q.Mode()
	if mode == "blizzard" then return false end
	local su, sv, sz = Q.StartView()
	local u, v, zoneMap, kind = Q.Target(q, mapID)
	if not u then
		if kind == "none" then Q.Note() end
		return false
	end
	local zoom = Q.Landing(kind, zoneMap)
	local from = su and { su, sv, sz } or nil
	local to = { u, v, zoom }
	local function Start()
		if not mod.IsStitched() then return false end
		if mode == "jump" then
			mod.ShowNow(u, v, zoom)
			if how ~= "details" then Ping(q) end
			return true
		end
		local n = Fly(q, from, to)
		if n and watcher then
			pending = { q = q, n = n, resets = mod.Resets(), frames = 0, from = from, to = to }
			watcher:Show()
		end
		return n ~= nil
	end
	if mod.IsStitched() then return Start() end
	-- a dungeon's quest (D5): the stitched map put up again round its entrance, then the flight (a frame
	-- later, out of Blizzard's click: the map's change isn't made inside it)
	if kind ~= "entrance" or not zoneMap or not S.Valhalla or (mod.PadWaits and mod.PadWaits()) then return false end
	C_Timer.After(0, function()
		if not map:IsShown() or (mod.PadWaits and mod.PadWaits()) then return end
		S.Valhalla(zoneMap)
		Start()
	end)
	return true
end

-- the details' hook: once per quest per moment (Blizzard's SetMapID re-enters ShowQuestDetails)
local function OnDetails(q)
	if not q or Q.Mode() == "blizzard" then return end
	local id, _, at = mod.Flying()
	if id == q and at == GetTime() then return end
	local df = QuestMapFrame and QuestMapFrame.DetailsFrame
	local mapID = df and df.questID == q and df.questMapID
	if mapID == nil and GetQuestUiMapID then mapID = Safe.Call(GetQuestUiMapID, q) end
	Q.Go(q, mapID, "details")
end
Q.OnDetails = OnDetails

-- a flight cut by a view Blizzard put up in the frames right after it began (the map's first layout as it
-- opens), with the quest's details still open: once more, from the same start
local function Watch(self)
	local p = pending
	if not p then self:Hide() return end
	p.frames = p.frames + 1
	local _, n = mod.Flying()
	if n ~= p.n and not p.retried and mod.Resets() > p.resets and map:IsShown() and mod.IsStitched()
		and QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID() == p.q then
		p.retried = true
		p.n = Fly(p.q, p.from, p.to)
		p.resets = mod.Resets()
		p.frames = 0
		return
	end
	if p.frames >= Q.RETRY_FRAMES or n ~= p.n then pending = nil self:Hide() end
end
Q.Watch = function() if watcher then Watch(watcher) end end

-- Valhalla's quest icon on the map (Quests.lua): fly (or jump) there; false: as before (its 0.4 s glide)
function mod.QuestIconClick(q, u, v, mapID)
	local mode = Q.Mode()
	if mode == "blizzard" or not mod.IsStitched() then return false end
	local zone = (mapID and S.Rect(mapID)) and mapID or ZoneAt(u, v)
	local zoom = Q.Landing("poi", zone)
	if mode == "jump" then
		mod.ShowNow(u, v, zoom)
		Ping(q)
		return true
	end
	return Fly(q, nil, { u, v, zoom }) ~= nil
end

-- a Ready to Turn In row clicked in combat with the map open (Objectives.lua: Blizzard's details aren't
-- opened by Valhalla in combat): the flight alone
function mod.FlyToQuest(q)
	if not map or not map:IsShown() or not mod.IsStitched() then return false end
	return Q.Go(q, GetQuestUiMapID and Safe.Call(GetQuestUiMapID, q) or nil, "ready")
end

function mod:QuestFlyOptions(opts, get, set, off)
	opts.questFly = { type = "select", name = L["Quest click"], order = 11.1, get = function() return Q.Mode() end, set = set, disabled = off,
		values = { fly = L["Fly to it"], jump = L["Jump to it"], blizzard = L["As Blizzard"] }, sorting = { "fly", "jump", "blizzard" },
		desc = L["A quest clicked in the tracker, the quest log, Ready to Turn In or on the map. Fly to it: the map zooms out, glides over and zooms in to the quest. Jump to it: straight there. As Blizzard: the quest's zone shown whole."] }
	opts.questFlySpeed = { type = "select", name = L["Flight speed"], order = 11.2, get = function() return Q.Speed() end, set = set,
		disabled = function() return off() or Q.Mode() ~= "fly" end,
		values = { slow = L["Slow"], normal = L["Normal"], fast = L["Fast"] }, sorting = { "slow", "normal", "fast" },
		desc = L["Normal takes about 0.6 to 2 seconds by distance; Slow half as long again, Fast a little over half."] }
	opts.questFlyLanding = { type = "select", name = L["Quest landing"], order = 11.3, get = get, set = set,
		disabled = function() return off() or Q.Mode() == "blizzard" end,
		values = { zone = L["Whole zone"], close = L["Close-up"] }, sorting = { "zone", "close" },
		desc = L["Where a quest's flight ends: its zone shown whole, centred on the quest, or about twice as close."] }
	opts.questFlyShort = { type = "select", name = L["Short trips"], order = 11.4, get = get, set = set,
		disabled = function() return off() or Q.Mode() ~= "fly" end,
		values = { auto = L["Zoom out by distance"], out = L["Always zoom out"] }, sorting = { "auto", "out" },
		desc = L["Zoom out by distance: a short hop barely zooms out, a long one rises to the continent or the world. Always zoom out: every flight rises at least twice as far out first."] }
end

function mod:SetupQuestFly(worldMap)
	map = worldMap
	watcher = CreateFrame("Frame")
	watcher:Hide()
	watcher:SetScript("OnUpdate", Watch)
	if QuestMapFrame_ShowQuestDetails then
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(q)
			local ok, err = pcall(OnDetails, q)
			if not ok then geterrorhandler()(err) end
		end)
	end
end
