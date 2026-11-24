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

-- the outer size already matches the quest log. One texture, the log button's own picture,
-- at the same share of that button as the log's display. Not a number plate with a small mark on top.
local POI_OUTER = 20
local POI_TEMPLATES = { "ObjectiveTrackerPOIButtonTemplate", "POIButtonTemplate" }
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
	GameTooltip:AddLine(L["Click: track this quest and zoom to it"], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- a click: the quest tracked (as Blizzard's own quest icons do) and the view in on it, the map kept as it is,
-- full screen or windowed. (It opened the quest's details, and Blizzard opens those in the windowed map
-- with its quest log: full screen was left.) With the quest log beside the map, its details there too
local ZOOM_TO = 6
local function Click(pin)
	local q = pin.data
	if not q then return end
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
		-- (1.2.23) in combat: tracked once combat ends (CombatQueue.lua); the view still goes to it
		local function Track()
			if C_QuestLog.AddQuestWatch and not (C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(q.id)) then
				pcall(C_QuestLog.AddQuestWatch, q.id)
			end
			pcall(C_SuperTrack.SetSuperTrackedQuestID, q.id)
		end
		local C = ns.Combat
		if C and C.Run then C.Run("supertrack", Track, L["Tracking changed in combat: it applies when combat ends."])
		elseif not InCombatLockdown() then Track() end
	end
	-- (v0.4.2.4) the quest fly-to's way there (QuestFly.lua: fly, or jump, by the setting); As Blizzard: the glide
	if not (mod.QuestIconClick and mod.QuestIconClick(q.id, pin.u, pin.v, q.map)) and S.GlideToWorld then
		S.GlideToWorld(pin.u, pin.v, ZOOM_TO)
	end
	-- (in combat with the gamepad's UI, Blizzard's quest details would set the pad's buttons from
	-- Valhalla's code, which combat blocks: they wait, as a dungeon's map does)
	if mod.PadWaits and mod.PadWaits() then return end
	-- (1.2.24) the game's quest details wait on CombatQueue.lua's gate (combat, secret auras, the settle
	-- after combat); when they run, the log beside a windowed map is looked at again
	local function Details()
		local log = map and map.QuestLog
		local details = G("QuestMapFrame_ShowQuestDetails")
		if log and log:IsShown() and details and not (map.IsMaximized and map:IsMaximized()) then details(q.id) end
	end
	local C = ns.Combat
	if C and C.Run then C.Run("details", Details, L["Quest details open when combat ends."])
	elseif not InCombatLockdown() then Details() end
end

-- once: the log button's width, its display's width, and the atlas that style paints
local function AtlasOf(tex)
	if tex and tex.GetAtlas then
		local name = tex:GetAtlas()
		if type(name) == "string" and name ~= "" then return name end
	end
end

local function ReadStyle(button, style)
	if not (button and button.SetStyle and style) then return end
	pcall(button.SetStyle, button, style)
	if button.UpdateButtonStyle then pcall(button.UpdateButtonStyle, button) end
	local display = button.Display or button.Icon
	local atlas = AtlasOf(display)
	if not atlas and button.GetNormalTexture then atlas = AtlasOf(button:GetNormalTexture()) end
	local bw = tonumber(button.GetWidth and button:GetWidth()) or 0
	local dw = tonumber(display and display.GetWidth and display:GetWidth()) or 0
	return bw, dw, atlas
end

local function MeasureQuestPoi()
	if mod.questPoiInfo then return mod.questPoiInfo end
	local info = {
		button = 0, inProgress = 0, complete = 0, ratioIn = 1, ratioDone = 1,
		inProgressAtlas = "Quest-In-Progress-Icon-yellow", completeAtlas = "UI-QuestPoi-QuestBang",
	}
	local button
	if CreateFrame then
		for _, template in ipairs(POI_TEMPLATES) do
			local ok, made = pcall(CreateFrame, "Button", nil, UIParent, template)
			if ok and type(made) == "table" and made.SetStyle then button = made break end
		end
	end
	if button then
		if button.Hide then button:Hide() end
		local styles = rawget(_G, "POIButtonUtil")
		styles = styles and styles.Style or {}
		local bw, dw, atlas = ReadStyle(button, styles.QuestInProgress or 5)
		if bw and bw > 0 then info.button = bw end
		if dw and dw > 0 then info.inProgress = dw end
		if atlas then info.inProgressAtlas = atlas end
		if bw and dw and bw > 0 and dw > 0 then info.ratioIn = dw / bw end
		local bw2, dw2, atlas2 = ReadStyle(button, styles.QuestComplete or 3)
		if bw2 and bw2 > 0 then info.button = bw2 end
		if dw2 and dw2 > 0 then info.complete = dw2 end
		if atlas2 then info.completeAtlas = atlas2 end
		if bw2 and dw2 and bw2 > 0 and dw2 > 0 then info.ratioDone = dw2 / bw2 end
	end
	mod.questPoiInfo = info
	local db = rawget(_G, "ValhallaDB")
	if type(db) == "table" then db.questPoi = info end
	return info
end

local function PoiLook(complete, info)
	return {
		atlas = complete and info.completeAtlas or info.inProgressAtlas,
		texture = complete and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\IncompleteQuestIcon",
		size = POI_OUTER,
	}
end

-- one picture, the share of the badge the log's display uses. The Icon size slider does not apply.
local function FitQuest(pin, complete, info)
	local ratio = complete and info.ratioDone or info.ratioIn
	if type(ratio) ~= "number" or ratio <= 0 then ratio = 1 end
	pin:SetScale(1)
	pin:SetSize(POI_OUTER, POI_OUTER)
	if pin.Icon then
		pin.Icon:ClearAllPoints()
		pin.Icon:SetPoint("CENTER")
		pin.Icon:SetSize(POI_OUTER * ratio, POI_OUTER * ratio)
	end
	if pin.questMark and pin.questMark.Hide then pin.questMark:Hide() end
end

function mod:RefreshQuests()
	dirty = false
	local poi = MeasureQuestPoi()
	if not set and S.IsBuilt() then set = S.PinSet("quests", 1, 5) end   -- (built as the map first opens)
	if not set then return end
	S.ClearPinSet(set)
	-- (and as Blizzard's own quests: not with the map's Quest Objectives off, its questPOI)
	local on = mod.db.allQuests ~= false and mod.IsStitched() and C_QuestLog.GetQuestsOnMap ~= nil
		and not (GetCVarBool and not GetCVarBool("questPOI"))
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
					local pin = S.AddPin(set, u, v, PoiLook(complete, poi), { id = id, complete = complete, map = mapID })
					FitQuest(pin, complete, poi)
					pin:SetScript("OnEnter", Enter)
					pin:SetScript("OnLeave", GameTooltip_Hide)
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
