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
-- (1.2.56) a quest event while the map was closed: the icons are redrawn as it opens, in that same frame
-- (until 1.2.55 the events were dropped while it was closed and the redraw came EVERY after it opened, so
-- the icons it was closed with showed first: a completed quest jumped to its turn-in half a second late)
local changedHidden = true      -- (true: the first opening draws them)
local drawnHost                 -- the map underneath when they were last drawn
local poiNote = false           -- (questMapDiag: the next redraw is the opening's QUEST_POI_UPDATE one)

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
	GameTooltip:AddLine(L["Click: show this quest's area and its waypoint; click again to clear it."], 0.6, 0.6, 0.6)
	GameTooltip:Show()
	Hover(pin, true)
end

local function Leave(pin)
	Hover(pin, false)
	GameTooltip_Hide()
end

-- (1.2.48) a click selects the quest, as the Objectives panel's quest button does (O.PoiClick): super-tracked
-- already: cleared, the "off" sound; else super-tracked, the "on" sound. That alone shows its quest area and
-- the minimap's waypoint. Never a watch added or removed (the Objectives panel
-- keeps its own zone rules and pins), no chat link, nothing for Shift, no map move, no details. While
-- CombatQueue's gate is closed (combat, secret auras, the settle after combat) the change waits and runs once
-- it opens. Each click is logged to ValhallaDB.questClickDiag with the super-track and the watch before and after.
local CLICK_LOG = 20
local function Watched(id)
	local f = C_QuestLog and C_QuestLog.GetQuestWatchType
	if f then
		local w = ns.Safe and ns.Safe.Call(f, id)
		return w ~= nil
	end
	f = rawget(_G, "IsQuestWatched")
	local index = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and ns.Safe and ns.Safe.Call(C_QuestLog.GetLogIndexForQuestID, id)
	if f and index then return (ns.Safe.Call(f, index)) and true or false end
end
local function Super()
	local get = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
	return get and ns.Safe and ns.Safe.Call(get) or nil
end
local function NoteClick(q, how, before, watchedBefore, act, ok, err, src)
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local log = db.questClickDiag
	if type(log) ~= "table" then log = {} db.questClickDiag = log end
	log[#log + 1] = {
		quest = q, how = how, act = act, before = before, after = Super(), ok = ok, err = err and tostring(err) or nil,
		watchedBefore = watchedBefore, watchedAfter = Watched(q), src = src,
		clock = date and date("%H:%M:%S") or nil,
	}
	while #log > CLICK_LOG do table.remove(log, 1) end
end

local function Sound(on)
	local kit = rawget(_G, "SOUNDKIT")
	local id = kit and (on and kit.IG_MAINMENU_OPTION_CHECKBOX_ON or kit.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	if PlaySound and id then pcall(PlaySound, id) end
end

-- (1.2.49) a quest selected on the map is shown in the quest log: its zone header expanded if folded (the
-- game's QuestScrollFrame:ExpandHeaderForQuest, else ExpandQuestHeader) and the log scrolled to it
-- (QuestScrollFrame:ScrollToQuest, the frame after). Not remembered as opened (Objectives/QuestChains.lua's
-- zone memory saves clicks only). Through CombatQueue; the log closed: when it next opens, if the quest is
-- still the selected one. Nothing is written on the game's frames.
local reveal, revealHooked
local function Reveal(id)
	if not id or Super() ~= id then return "not selected" end
	local G = ns.Combat
	if G and G.Blocked and G.Blocked() then return "held" end   -- (only ever run through the gate: RunReveal)
	local C = rawget(_G, "C_QuestLog")
	local sf = rawget(_G, "QuestScrollFrame")
	local expanded = false
	if sf and type(sf.ExpandHeaderForQuest) == "function" then
		expanded = pcall(sf.ExpandHeaderForQuest, sf, id)
	elseif C and C.GetHeaderIndexForQuest and rawget(_G, "ExpandQuestHeader") then
		local h = ns.Safe.Call(C.GetHeaderIndexForQuest, id)
		local info = h and C.GetInfo and ns.Safe.Call(C.GetInfo, h)
		if type(info) == "table" and info.isCollapsed then expanded = pcall(ExpandQuestHeader, h) end
	end
	if sf and type(sf.ScrollToQuest) == "function" and C_Timer and C_Timer.After then
		C_Timer.After(0, function() if Super() == id then pcall(sf.ScrollToQuest, sf, id) end end)
	end
	return expanded and "expanded" or "shown"
end
local function RunReveal()
	local id = reveal
	reveal = nil
	local C = ns.Combat
	local function go() local r = Reveal(id) local db = rawget(_G, "ValhallaDB") if type(db) == "table" then db.questRevealLast = { quest = id, result = r } end end
	if C and C.Run then C.Run("questlog:reveal", go)
	elseif not (InCombatLockdown and InCombatLockdown()) then go() end
end
function mod.RevealQuestInLog(id)
	reveal = id
	local log = rawget(_G, "QuestMapFrame")
	if log and log.IsVisible and log:IsVisible() then RunReveal() return "now" end
	if log and log.HookScript and not revealHooked then
		revealHooked = true
		log:HookScript("OnShow", function() if reveal then RunReveal() end end)
	end
	return "deferred"
end

local function Click(pin)
	local q = pin.data
	if not (q and q.id and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
	local id = q.id
	local before = Super()
	local watchedBefore = Watched(id)
	local act = before == id and "clear" or "select"
	Sound(act == "select")
	local O = ns.GetModule and ns:GetModule("objectives")
	O = O and O.O
	if O and O.ForgetKeepSuper then O.ForgetKeepSuper() end   -- (the player's own selection: Objectives puts nothing back)
	local function Run(how)
		local ok, err
		if act == "clear" then
			if C_SuperTrack.ClearAllSuperTracked then ok, err = pcall(C_SuperTrack.ClearAllSuperTracked)
			else ok, err = pcall(C_SuperTrack.SetSuperTrackedQuestID, 0) end
		else
			ok, err = pcall(C_SuperTrack.SetSuperTrackedQuestID, id)
		end
		NoteClick(id, how, before, watchedBefore, act, ok, not ok and err or nil, q.src)
		if ok and act == "select" then
			local r = mod.RevealQuestInLog(id)
			local log = rawget(_G, "ValhallaDB") and ValhallaDB.questClickDiag
			if type(log) == "table" and log[#log] then log[#log].reveal = r end
		end
	end
	local C = ns.Combat
	if C and C.Run then
		local now = true
		local ran = C.Run("supertrack", function() Run(now and "now" or "queued") end, L["Tracking changed in combat: it applies when combat ends."])
		now = false
		if not ran then NoteClick(id, "waiting", before, watchedBefore, act, true, nil, q.src) end
	elseif not (InCombatLockdown and InCombatLockdown()) then
		Run("now")
	end
end

--------------------------------------------------------------------------------
-- (1.2.57) the game's own quest pins (QuestPinTemplate, on the map underneath: its quests and the selected
-- quest's waypoint) click as Valhalla's do. Called from the map's global pin mouse handler (Map/WorldMap.lua:
-- OnBlizzardPinAction, after the Ctrl / pin-mode drop), which Blizzard runs before a pin's own action
-- (MapCanvasPinMixin:OnClick / OnMouseDown) and stops it when this returns true. A left-button mouse down
-- or click on a quest pin: the game's action is stopped (no watch, no super-track, no ping, no sound, no
-- chat link of its own); on the click, Valhalla's Click for its quest (select / clear, through CombatQueue),
-- or with Shift a chat link when the chat is already open (closed: nothing). Mouse up and other buttons go
-- through. Only read from the game's pins: nothing set on them. Each is noted in ValhallaDB.questPinDiag.
--------------------------------------------------------------------------------
local PIN_TEMPLATE = "QuestPinTemplate"
local PIN_DIAG_KEEP = 20
local function Read(t, k)
	if type(t) ~= "table" then return nil end
	local ok, v = pcall(function() return t[k] end)
	return ok and v or nil
end
local function Call(t, m)
	local f = Read(t, m)
	if type(f) ~= "function" then return nil end
	local ok, v = pcall(f, t)
	return ok and v or nil
end
local function PinDiag(entry)
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local log = db.questPinDiag
	if type(log) ~= "table" then log = {} db.questPinDiag = log end
	entry.clock = date and date("%H:%M:%S") or nil
	log[#log + 1] = entry
	while #log > PIN_DIAG_KEEP do table.remove(log, 1) end
end
local function ChatOpen()
	local CU = rawget(_G, "ChatFrameUtil")
	local get = (type(CU) == "table" and CU.GetActiveWindow) or rawget(_G, "ChatEdit_GetActiveWindow")
	if type(get) ~= "function" then return false end
	local ok, w = pcall(get)
	return ok and w ~= nil or false
end
local function LinkIfChat(id)
	if not ChatOpen() then return "nothing (chat closed)" end
	local CU = rawget(_G, "ChatFrameUtil")
	local try = (type(CU) == "table" and CU.TryInsertQuestLinkForQuestID) or rawget(_G, "ChatEdit_TryInsertQuestLinkForQuestID")
	if type(try) ~= "function" or not id then return "no link" end
	local ok, done = pcall(try, id)
	return ok and done and "link" or "no link"
end
local function Describe(f)
	if type(f) ~= "table" then return tostring(f) end
	return tostring(Call(f, "GetDebugName") or Call(f, "GetName") or Read(f, "pinTemplate") or "frame")
end
-- the quest pin the mouse is on: the mouse focus (the topmost), else (logged as a miss) a shown quest pin
-- that the mouse is over though the focus is something else
local function GameQuestPin(m)
	local foci = rawget(_G, "GetMouseFoci") and select(2, pcall(GetMouseFoci))
	local focus = type(foci) == "table" and foci[1] or nil
	if Read(focus, "pinTemplate") == PIN_TEMPLATE then return focus, "focus" end
	local enum = Read(m, "EnumeratePinsByTemplate")
	if type(enum) == "function" then
		local ok, iter, st, ctl = pcall(enum, m, PIN_TEMPLATE)
		if ok and type(iter) == "function" then
			for pin in iter, st, ctl do
				if Call(pin, "IsShown") and Call(pin, "IsMouseOver") then return pin, "over", focus end
			end
		end
	end
	return nil, nil, focus
end
local function PinAction(m, action, button)
	if button ~= "LeftButton" then return false end
	local MA = rawget(_G, "MapCanvasMixin") and MapCanvasMixin.MouseAction
	if type(MA) ~= "table" or (action ~= MA.Down and action ~= MA.Click) then return false end
	local pin, how, focus = GameQuestPin(m)
	if not pin then return false end
	local id = Read(pin, "questID")
	local click = action == MA.Click
	if click then
		local entry = { quest = id, how = how, waypoint = Read(pin, "isWaypoint") and true or nil }
		if how ~= "focus" then entry.act = "guard-miss" entry.focus = Describe(focus) end
		if IsShiftKeyDown and IsShiftKeyDown() then
			entry.shift = LinkIfChat(id)
		elseif id then
			entry.click = Super() == id and "clear" or "select"
			Click({ data = { id = id, src = "game" } })
		else
			entry.click = "no quest"
		end
		PinDiag(entry)
	end
	return true
end
function mod.GameQuestPinAction(m, action, button)
	local ok, stop = pcall(PinAction, m, action, button)
	if not ok then PinDiag({ act = "error", err = tostring(stop) }) return false end   -- (an error: the game's own click)
	return stop and true or false
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
	if not set then return false end
	drawnHost = mod.HostMap and mod.HostMap() or nil
	S.ClearPinSet(set)
	-- (and as Blizzard's own quests: not with the map's Quest Objectives off, its questPOI)
	local on = mod.db.allQuests ~= false and mod.IsStitched() and C_QuestLog.GetQuestsOnMap ~= nil
		and not (GetCVarBool and not GetCVarBool("questPOI"))
	-- (no quest button template on this client: nothing is drawn, rather than a look that isn't the log's)
	on = on and not poiMissing
	S.SetPinSetOn(set, on)
	if not on then return true end
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
	-- (1.2.57) the map underneath is skipped again, as before 1.2.40: its quests are the game's own pins
	-- only (one icon each, the game's tooltip with the level), and a click on those is Valhalla's
	-- (mod.GameQuestPinAction). A quest already drawn by the game there is not drawn again from a
	-- neighbour. Blizzard's own pins are not moved or hidden.
	for _, mapID in ipairs(Maps()) do
		for _, q in ipairs(mapID ~= host and C_QuestLog.GetQuestsOnMap(mapID) or NONE) do
			local id = q.questID
			if id and q.x and q.y and not q.isMapIndicatorQuest and (not G("HaveQuestData") or G("HaveQuestData")(id))
				and not (continent and id == tracked) then
				local u, v = mod.ToWorld(mapID, q.x, q.y)
				local key = u and (id .. ":" .. math.floor(u / SAME) .. ":" .. math.floor(v / SAME))
				local onHost = u and hostQuests[id] and hl and u >= hl and u <= hr and v >= ht and v <= hb
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
	if poiNote and mod.QuestMapDiagDrawn then poiNote = false mod.QuestMapDiagDrawn("poi") end
	return true
end

-- (a burst of quest log updates: one refresh)
local function Soon()
	if dirty then return end
	dirty = true
	C_Timer.After(EVERY, function() if dirty then mod:RefreshQuests() end end)
end

--------------------------------------------------------------------------------
-- (1.2.56) questMapDiag (ValhallaDB, the last QMD_KEEP): read only. A quest in your zone turning complete
-- while the map is closed: its position then (and the last one before the map opens), then its position at
-- the redraw as the map opens and at the first QUEST_POI_UPDATE redraw after that. It shows whether the
-- game had the turn-in place before the map opened.
--------------------------------------------------------------------------------
local QMD_KEEP = 20
local QMD_POI_WINDOW = 10       -- seconds after opening: a QUEST_POI_UPDATE redraw is the opening's
local wasComplete               -- questID -> complete, in your zone (nil: not read yet)
local openedAt
local function Now() return GetTime and GetTime() or 0 end
local function Clock() return date and date("%H:%M:%S") or nil end
local function DiagLog()
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return nil end
	if type(db.questMapDiag) ~= "table" then db.questMapDiag = {} end
	return db.questMapDiag
end
local function Pos(mapID, id)
	if not (mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return nil end
	local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	if not ok or type(list) ~= "table" then return nil end
	for _, q in ipairs(list) do
		if q.questID == id and q.x and q.y then return { x = math.floor(q.x * 10000 + 0.5) / 10000, y = math.floor(q.y * 10000 + 0.5) / 10000 } end
	end
	return nil
end
local function Same(a, b) return a ~= nil and b ~= nil and a.x == b.x and a.y == b.y end
function mod.QuestMapDiagClosed()
	local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not (here and C_QuestLog and C_QuestLog.GetQuestsOnMap and C_QuestLog.IsComplete) then return end
	local ok, list = pcall(C_QuestLog.GetQuestsOnMap, here)
	if not ok or type(list) ~= "table" then return end
	local log = DiagLog()
	local first = wasComplete == nil
	wasComplete = wasComplete or {}
	for _, q in ipairs(list) do
		local id = q.questID
		if id then
			local done = C_QuestLog.IsComplete(id) and true or false
			if log then
				if done and wasComplete[id] == false and not first then
					log[#log + 1] = { quest = id, map = here, clock = Clock(), t = Now(), closed = Pos(here, id) }
					while #log > QMD_KEEP do table.remove(log, 1) end
				elseif done then
					-- the last position before the map opens (the game may move it after the first event)
					for i = #log, 1, -1 do
						local e = log[i]
						if e.quest == id and not e.open then e.closedLast = Pos(here, id) break end
					end
				end
			end
			wasComplete[id] = done
		end
	end
end
-- which: "open" (the redraw as the map opens) or "poi" (a QUEST_POI_UPDATE redraw just after)
function mod.QuestMapDiagDrawn(which)
	local log = DiagLog()
	if not log then return end
	for _, e in ipairs(log) do
		if which == "open" and not e.open then
			e.open = Pos(e.map, e.quest) or false
			e.openClock = Clock()
			e.sameAtOpen = Same(e.closedLast or e.closed, e.open or nil)
		elseif which == "poi" and e.open ~= nil and e.poi == nil and e.openT == openedAt then
			e.poi = Pos(e.map, e.quest) or false
			e.sameAtPoi = Same(e.open or nil, e.poi or nil)
		end
		if which == "open" and e.openT == nil then e.openT = openedAt end
	end
end

-- (1.2.56) the map opening: redrawn at once when a quest event came while it was closed, and looked at again
-- next frame in case its map underneath is set later in that frame. OnMapChanged still redraws (Soon).
local function Opened()
	openedAt = Now()
	if changedHidden then
		if mod:RefreshQuests() then changedHidden = false end
		mod.QuestMapDiagDrawn("open")
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function()
			if map and map:IsShown() and drawnHost ~= (mod.HostMap and mod.HostMap() or nil) then mod:RefreshQuests() end
		end)
	end
end
mod.QuestsOpened = Opened

function mod:SetupQuests(worldMap)
	map = worldMap
	local events = CreateFrame("Frame")
	for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "CVAR_UPDATE" }) do
		pcall(events.RegisterEvent, events, e)
	end
	events:SetScript("OnEvent", function(_, event, cvar)
		if event == "CVAR_UPDATE" and cvar ~= "questPOI" then return end
		if map:IsShown() then
			-- (the opening's POI update: redrawn after the burst as any, its positions then noted)
			if event == "QUEST_POI_UPDATE" and openedAt and Now() - openedAt <= QMD_POI_WINDOW then poiNote = true end
			Soon()
		else
			changedHidden = true          -- (no work while closed: drawn as it opens)
			if event == "QUEST_LOG_UPDATE" or event == "QUEST_POI_UPDATE" then mod.QuestMapDiagClosed() end
		end
	end)
	hooksecurefunc(map, "OnMapChanged", Soon)
	map:HookScript("OnShow", Opened)
	-- (questMapDiag: what's complete as the map closes is the baseline; only a completion after that is noted)
	map:HookScript("OnHide", function() wasComplete = nil mod.QuestMapDiagClosed() end)
end
