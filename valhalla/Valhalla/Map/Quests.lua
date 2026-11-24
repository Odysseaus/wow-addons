--------------------------------------------------------------------------------
-- The quests in your log on the stitched map, from every zone and at any zoom. Blizzard's map
-- shows a zone's quests only on that zone's own map (its QuestDataProvider: MapUtil.
-- ShouldMapTypeShowQuests), so zoomed out, or over the next zone, there were none until the map
-- underneath became theirs. Here every stitched map's quests (C_QuestLog.GetQuestsOnMap) are
-- Valhalla's own icons, in the look of Blizzard's (its map legend's); the map underneath keeps
-- Blizzard's own pins for its quests (and a continent its super-tracked quest's).
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local L = ns.L
-- (the quest log's functions: the game's, looked up as they're used)
local function G(name) return _G[name] end

mod.defaults.allQuests = true   -- the quests in your log from every zone (off: Blizzard's, the zone's own map only)

-- (1.2.45) each icon is Valhalla's own instance of the quest button the quest log and Objectives tracker
-- draw (UI/Parts.lua: Parts.QuestPoi), styled as the tracker styles it, so in progress, complete, campaign
-- and the super-tracked glow are the game's own pictures. The click and hover are Valhalla's (the pin's).
local POI_OUTER = 20            -- the button's own size (POIButtonTemplate)
local PIN_LOOK = { size = POI_OUTER }   -- (the pin's own texture is not shown)
local SAME = 0.002              -- world (normalized): one quest's icons this close are one
local EVERY = 0.5               -- seconds: the quest log changes in bursts
local NONE = {}
local set, map, maps
local dirty = false

-- the maps the quests are read from: the stitched zones and cities (a city's quests are its zone's
-- too, at the same place: one icon, SAME)
local function Maps()
	if maps then return maps end
	maps = {}
	for _, info in ipairs(C_Map.GetMapChildrenInfo(S.WORLD, Enum.UIMapType.Zone, true) or NONE) do
		if S.Rect(info.mapID) then maps[#maps + 1] = info.mapID end
	end
	return maps
end

local function Hover(pin, on)
	local hi = pin.poi and pin.poi.HighlightTexture
	if hi and hi.SetShown then hi:SetShown(on) end
end

local function Enter(pin)
	local q = pin.data
	if not q then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q.id)
	GameTooltip:SetText(title or "?", 1, 0.82, 0)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q.id)
	if q.complete then
		GameTooltip:AddLine(_G.QUEST_WATCH_QUEST_READY or L["Completed"], 0.5, 0.95, 0.4)
	elseif index and G("GetNumQuestLeaderBoards") and G("GetQuestLogLeaderBoard") then
		for i = 1, G("GetNumQuestLeaderBoards")(index) or 0 do
			local text, _, finished = G("GetQuestLogLeaderBoard")(i, index)
			if text and not finished then GameTooltip:AddLine((_G.QUEST_DASH or "- ") .. text, 1, 1, 1, true) end
		end
	end
	GameTooltip:AddLine(L["Click: select this quest, as in the quest log. Shift-click: stop tracking it."], 0.6, 0.6, 0.6)
	GameTooltip:Show()
	Hover(pin, true)
end

local function Leave(pin)
	Hover(pin, false)
	GameTooltip_Hide()
end

-- (1.2.46) a click is the game's own: POIButtonMixin.OnClick on this pin's button, as Blizzard's map quest pins
-- (QuestPinMixin:OnMouseClickAction), the quest log's and the tracker's quest buttons do. Selected: cleared;
-- else a chat link when typing, Shift on a watched quest untracks it, an unwatched one is watched, then
-- super-tracked. The view stays where it is and no details open. While CombatQueue's gate is closed (combat,
-- secret auras, the settle after combat) the click waits and runs once it opens, as Valhalla's other tracking calls.
local CLICK_LOG = 20
local function NoteClick(q, how, before, ok, err)
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local log = db.questClickDiag
	if type(log) ~= "table" then log = {} db.questClickDiag = log end
	local get = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
	local after = get and ns.Safe and ns.Safe.Call(get) or nil
	log[#log + 1] = {
		quest = q, how = how, before = before, after = after, ok = ok, err = err and tostring(err) or nil,
		shift = IsShiftKeyDown and IsShiftKeyDown() and true or false,
		clock = date and date("%H:%M:%S") or nil,
	}
	while #log > CLICK_LOG do table.remove(log, 1) end
end

local function Click(pin)
	local q = pin.data
	local b = pin.poi
	local game = rawget(_G, "POIButtonMixin")
	if not (q and b and game and game.OnClick) then return end
	local get = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
	local before = get and ns.Safe and ns.Safe.Call(get) or nil
	local function Run(how)
		local ok, err = pcall(game.OnClick, b, "LeftButton")
		NoteClick(q.id, how, before, ok, not ok and err or nil)
	end
	local C = ns.Combat
	if C and C.Run then
		local now = true
		local ran = C.Run("supertrack", function() Run(now and "now" or "queued") end, L["Tracking changed in combat: it applies when combat ends."])
		now = false
		if not ran then NoteClick(q.id, "waiting", before, true) end
	elseif not (InCombatLockdown and InCombatLockdown()) then
		Run("now")
	end
end

-- the game's button on a pin, made once per pooled pin. The mouse stays on the pin (its Enter and Click);
-- the button's own hover picture is shown from there.
local poiMissing = false
local function QuestButton(pin)
	if pin.poi or poiMissing then return pin.poi end
	local b = ns.Parts and ns.Parts.QuestPoi and ns.Parts.QuestPoi(pin)
	if not b then poiMissing = true return end
	b:ClearAllPoints()
	b:SetPoint("CENTER", pin, "CENTER")
	if b.EnableMouse then b:EnableMouse(false) end
	pin.poi = b
	return b
end

-- the style Blizzard's map pins and log rows ask for (POIButtonUtil.GetStyle: complete, disabled, in progress)
local function StyleOf(id, complete)
	local U = rawget(_G, "POIButtonUtil")
	if U and U.GetStyle then
		local ok, style = pcall(U.GetStyle, id)
		if ok and style then return style end
	end
	local styles = U and U.Style or NONE
	return complete and (styles.QuestComplete or 3) or (styles.QuestInProgress or 2)
end

function mod:RefreshQuests()
	dirty = false
	if not set and S.IsBuilt() then set = S.PinSet("quests", 1, 5) end   -- (built as the map first opens)
	if not set then return end
	S.ClearPinSet(set)
	-- (and as Blizzard's own quests: not with the map's Quest Objectives off, its questPOI)
	local on = mod.db.allQuests ~= false and mod.IsStitched() and C_QuestLog.GetQuestsOnMap ~= nil
		and not (GetCVarBool and not GetCVarBool("questPOI"))
	-- (no quest button template on this client: nothing is drawn, rather than a look that isn't the log's)
	on = on and not poiMissing
	S.SetPinSetOn(set, on)
	if not on then return end
	-- the map underneath: Blizzard draws its quests (a continent, only the super-tracked one)
	local host = mod.HostMap()
	local hostInfo = host and C_Map.GetMapInfo(host)
	local continent = hostInfo and hostInfo.mapType == Enum.UIMapType.Continent
	local tracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	local hostQuests = {}
	if host and not continent then
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(host) or NONE) do hostQuests[q.questID] = true end
	end
	local hl, hr, ht, hb
	if host then hl, hr, ht, hb = S.Rect(host) end
	local seen = {}
	local live = {}
	-- (1.2.40) the map underneath is included too, so its in-progress and complete badges sit on
	-- Valhalla's quest set (level 5), above townsfolk (level 3). A quest already drawn on that map
	-- is not drawn again from a neighbour. Blizzard's own pins are not moved or hidden.
	for _, mapID in ipairs(Maps()) do
		for _, q in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or NONE) do
			local id = q.questID
			if id and q.x and q.y and not q.isMapIndicatorQuest and (not G("HaveQuestData") or G("HaveQuestData")(id))
				and not (continent and id == tracked) then
				local u, v = mod.ToWorld(mapID, q.x, q.y)
				local key = u and (id .. ":" .. math.floor(u / SAME) .. ":" .. math.floor(v / SAME))
				local onHost = mapID ~= host and u and hostQuests[id] and hl and u >= hl and u <= hr and v >= ht and v <= hb
				if key and not seen[key] and not onHost then
					seen[key] = true
					local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
					local pin = S.AddPin(set, u, v, PIN_LOOK, { id = id, complete = complete, map = mapID })
					pin:SetScale(1)                 -- (the Icon size slider does not apply: the log's size)
					pin:SetSize(POI_OUTER, POI_OUTER)
					pin.Icon:SetAlpha(0)            -- (the pin is the mouse target; the game's button is the picture)
					pin.Highlight:SetAlpha(0)
					local b = QuestButton(pin)
					if b then
						ns.Parts.PaintQuestPoi(b, id, StyleOf(id, complete), id == tracked)
						Hover(pin, false)
						b:Show()
					else
						pin:Hide()
					end
					pin:SetScript("OnEnter", Enter)
					pin:SetScript("OnLeave", Leave)
					pin.OnClick = Click
					live[#live + 1] = { map = mapID, x = q.x, y = q.y, complete = complete, id = id }
				end
			end
		end
	end
	mod.liveQuests = live
	if mod.UpdateTownsfolkMinimap then mod:UpdateTownsfolkMinimap() end
end

-- (a burst of quest log updates: one refresh)
local function Soon()
	if dirty then return end
	dirty = true
	C_Timer.After(EVERY, function() if dirty then mod:RefreshQuests() end end)
end

function mod:SetupQuests(worldMap)
	map = worldMap
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "CVAR_UPDATE" }) do
		pcall(events.RegisterEvent, events, e)
	end
	events:SetScript("OnEvent", function(_, event, cvar)
		if event == "CVAR_UPDATE" and cvar ~= "questPOI" then return end
		if map:IsShown() then Soon() end
	end)
	hooksecurefunc(map, "OnMapChanged", Soon)
	map:HookScript("OnShow", Soon)
end
