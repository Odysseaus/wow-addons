-- Box tests for 1.2.57: the zone underneath gets no Valhalla quest copies (the game's own pins only), and a
-- left click on one of the game's quest pins (QuestPinTemplate, its waypoint pin too) is Valhalla's quest click
-- (Map/Quests.lua: mod.GameQuestPinAction, from Map/WorldMap.lua: OnBlizzardPinAction). Lua 5.1.
-- Run: lua5.1 valhalla/tests/worldmap/gamequestpin_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
	if cond then pass = pass + 1 print("PASS  " .. name)
	else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local now = 100
function GetTime() return now end
C_Timer = { After = function(_, fn) end }
function date() return "17:20:00" end

-- the stitched map's pin set
local set = { pins = {} }
local S = {
	WORLD = 947,
	IsBuilt = function() return true end,
	PinSet = function() return set end,
	ClearPinSet = function(s) s.pins = {} end,
	SetPinSetOn = function(s, on) s.on = on end,
	-- Tanaris (1446) on the left half, Un'Goro (1449) on the right
	Rect = function(id) if id == 1446 then return 0, 0.5, 0, 1 elseif id == 1449 then return 0.5, 1, 0, 1 end end,
	AddPin = function(s, u, v, look, data)
		local pin = { u = u, v = v, data = data, SetScale = function() end, SetSize = function() end, Hide = function() end,
			SetScript = function() end, Icon = { SetAlpha = function() end }, Highlight = { SetAlpha = function() end } }
		s.pins[#s.pins + 1] = pin
		return pin
	end,
}
local host = 1446
local mod = { defaults = {}, db = { allQuests = true } }
mod.HostMap = function() return host end
mod.IsStitched = function() return true end
mod.ToWorld = function(mapID, x, y) if mapID == 1446 then return x / 2, y else return 0.5 + x / 2, y end end
local ns = { MapStitch = S, L = setmetatable({}, { __index = function(_, k) return k end }) }
function ns:GetModule() return mod end
ns.Parts = { QuestPoi = function() return { ClearAllPoints = function() end, SetPoint = function() end, Show = function() end } end,
	PaintQuestPoi = function() end }
ns.Safe = { Call = function(f, ...) return f(...) end }
-- CombatQueue: open, or holding (the change waits)
local blocked, queue = false, {}
ns.Combat = { Run = function(_, fn) if blocked then queue[#queue + 1] = fn return false end fn() return true end,
	Blocked = function() return blocked end }
Enum = { UIMapType = { Continent = 2, Zone = 3 } }
local quests = {
	[1446] = { { questID = 30, x = 0.40, y = 0.50 }, { questID = 31, x = 0.60, y = 0.30 } },
	[1449] = { { questID = 40, x = 0.20, y = 0.40 }, { questID = 31, x = -0.80, y = 0.30 } },   -- (31's area reaches into Tanaris)
}
local calls = {}
local function Note(name) calls[#calls + 1] = name end
C_QuestLog = {
	GetQuestsOnMap = function(id) return quests[id] or {} end,
	IsComplete = function() return false end,
	AddQuestWatch = function() Note("AddQuestWatch") end,
	RemoveQuestWatch = function() Note("RemoveQuestWatch") end,
	GetQuestWatchType = function() return nil end,
}
C_Map = { GetMapChildrenInfo = function() return { { mapID = 1446 }, { mapID = 1449 } } end, GetMapInfo = function() return { mapType = 3 } end,
	GetBestMapForUnit = function() return 1446 end }
local super = 0
C_SuperTrack = {
	GetSuperTrackedQuestID = function() return super end,
	SetSuperTrackedQuestID = function(id) Note("SetSuperTracked:" .. id) super = id end,
	ClearAllSuperTracked = function() Note("ClearAllSuperTracked") super = 0 end,
}
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
local sounds = {}
function PlaySound(id) sounds[#sounds + 1] = id end
function GetCVarBool() return true end
function InCombatLockdown() return false end
ValhallaDB = {}
local shift = false
function IsShiftKeyDown() return shift end
local chatOpen, linked = false, {}
ChatFrameUtil = {
	GetActiveWindow = function() return chatOpen and {} or nil end,
	TryInsertQuestLinkForQuestID = function(id) linked[#linked + 1] = id return true end,
}
MapCanvasMixin = { MouseAction = { Up = 1, Down = 2, Click = 3 } }
local A = MapCanvasMixin.MouseAction

-- the game's pins: plain tables as the map pools them (only read)
local function GamePin(template, id, extra)
	local p = { pinTemplate = template, questID = id, shown = true, over = false }
	function p:IsShown() return self.shown end
	function p:IsMouseOver() return self.over end
	for k, v in pairs(extra or {}) do p[k] = v end
	return p
end
local gamePins = {}
local canvas = {}
function canvas:EnumeratePinsByTemplate(t)
	local i = 0
	return function() repeat i = i + 1 until not gamePins[i] or gamePins[i].pinTemplate == t return gamePins[i] end
end
local focus
function GetMouseFoci() return { focus } end
local map = { IsShown = function() return true end, HookScript = function() end }
function hooksecurefunc() end
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end

assert(loadfile(root .. "Map/Quests.lua"))("Valhalla", ns)
mod:SetupQuests(map)
local function PinOf(q) for _, p in ipairs(set.pins) do if p.data.id == q then return p end end end
local function Reset() calls, sounds, linked = {}, {}, {} ValhallaDB.questPinDiag = nil ValhallaDB.questClickDiag = nil end
local function Has(name) for _, c in ipairs(calls) do if c == name then return true end end end
local function Tracking() for _, c in ipairs(calls) do if c:find("QuestWatch") then return true end end end
local function LastDiag() local d = ValhallaDB.questPinDiag return d and d[#d] end

print("== 1. the zone underneath: no Valhalla copies; the neighbours unchanged, still deduped")
mod:RefreshQuests()
ok(not PinOf(30), "Tanaris (underneath): its quest is the game's pin only, no copy")
ok(PinOf(40) and PinOf(40).data.map == 1449, "Un'Goro (a neighbour): its quest is Valhalla's icon")
ok(not PinOf(31), "a neighbour's place inside the zone underneath, for a quest the game draws there: not drawn again")
host = 1449
mod:RefreshQuests()
ok(PinOf(30) and PinOf(31) and PinOf(31).data.map == 1446 and not PinOf(40), "the other zone underneath: the roles swap")
host = 1446
mod:RefreshQuests()

print("== 2. a left click on a game quest pin: the game's action stopped, Valhalla's click runs")
local q30 = GamePin("QuestPinTemplate", 30)
gamePins = { q30, GamePin("FlightPointPinTemplate"), }
focus = q30
Reset()
ok(mod.GameQuestPinAction(canvas, A.Down, "LeftButton") == true, "mouse down: stopped (the game's press)")
ok(#calls == 0, "mouse down: nothing run")
ok(mod.GameQuestPinAction(canvas, A.Up, "LeftButton") == false, "mouse up: goes through to the game")
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == true, "click: stopped")
ok(super == 30 and Has("SetSuperTracked:30") and not Tracking() and #sounds == 1 and sounds[1] == 1,
	"click: selected (area + minimap waypoint), the on sound, no watch call", table.concat(calls, ","))
local cd = ValhallaDB.questClickDiag
ok(cd and cd[#cd].src == "game" and cd[#cd].act == "select" and LastDiag().click == "select" and LastDiag().how == "focus",
	"click noted (questClickDiag src game, questPinDiag select)")

print("== 3. a second click clears it")
Reset()
mod.GameQuestPinAction(canvas, A.Click, "LeftButton")
ok(super == 0 and Has("ClearAllSuperTracked") and not Tracking() and sounds[1] == 2, "cleared, the off sound, no watch call", table.concat(calls, ","))

print("== 4. other buttons and other pins are the game's")
Reset()
ok(mod.GameQuestPinAction(canvas, A.Down, "RightButton") == false and mod.GameQuestPinAction(canvas, A.Click, "RightButton") == false and #calls == 0,
	"right button: not stopped")
focus = gamePins[2]
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == false and #calls == 0 and not LastDiag(), "a flight point pin: not stopped, nothing noted")
focus = nil
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == false, "nothing under the mouse: not stopped")

print("== 5. Shift: the chat closed does nothing; open, the link once")
focus = q30
shift = true
Reset()
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == true and #calls == 0 and #linked == 0 and #sounds == 0
	and LastDiag().shift == "nothing (chat closed)", "chat closed: stopped, nothing at all")
chatOpen = true
Reset()
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == true and #linked == 1 and linked[1] == 30 and #calls == 0
	and LastDiag().shift == "link", "chat open: the link inserted once, no tracking or selection")
shift, chatOpen = false, false

print("== 6. the game's waypoint pin for the selected quest: the same click")
local wp = GamePin("QuestPinTemplate", 30, { isWaypoint = true })
focus = wp
super = 30
Reset()
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == true and super == 0 and not Tracking() and LastDiag().waypoint == true,
	"waypoint pin: stopped, Valhalla's click (selected: cleared), noted as the waypoint")

print("== 7. combat: the change waits in CombatQueue, the game's action still stopped")
blocked = true
Reset()
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == true and super == 0 and #queue == 1, "held: nothing changed yet, one queued")
blocked = false
queue[1]()
ok(super == 30 and not Tracking(), "after combat: selected, no watch call")
queue = {}

print("== 8. guard-miss: the focus isn't the quest pin the mouse is over")
local other = { GetDebugName = function() return "SomeOverlay" end }
focus = other
q30.over = true
super = 0
Reset()
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == true and super == 30 and LastDiag().act == "guard-miss"
	and LastDiag().focus == "SomeOverlay" and LastDiag().how == "over", "still Valhalla's click, a guard-miss entry with the focus")
q30.over = false

print("== 9. a quest pin whose quest can't be read; no MouseAction")
focus = setmetatable({}, { __index = function(_, k) if k == "pinTemplate" then return "QuestPinTemplate" end
	if k == "questID" then error("boom") end end })
local saved = MapCanvasMixin
Reset()
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == true, "a questID that can't be read: stopped (no quest)")
MapCanvasMixin = nil
ok(mod.GameQuestPinAction(canvas, A.Click, "LeftButton") == false, "no MouseAction: not stopped")
MapCanvasMixin = saved

print("== 10. WorldMap.lua's OnBlizzardPinAction: the drop first, then the quest pins")
local wsrc = assert(io.open(root .. "Map/WorldMap.lua")):read("*a")
local body = wsrc:match("(local function OnBlizzardPinAction%(.-\nend)\n")
ok(body ~= nil, "OnBlizzardPinAction found")
local chunk = assert(loadstring("local Dropping, DropAtCursor, mod, map = ... " .. body .. " return OnBlizzardPinAction"))
local dropping, dropped = false, 0
local gq = 0
local fakeMod = { GameQuestPinAction = function(c, a, b) gq = gq + 1 return a ~= A.Up and b == "LeftButton" end }
local OnBlizzardPinAction = chunk(function() return dropping end, function() dropped = dropped + 1 end, fakeMod, canvas)
dropping = true
ok(OnBlizzardPinAction(canvas, A.Down, "LeftButton") == true and OnBlizzardPinAction(canvas, A.Click, "LeftButton") == true
	and OnBlizzardPinAction(canvas, A.Up, "LeftButton") == false and dropped == 1 and gq == 0, "Ctrl / pin mode: the drop, the quest click not run")
dropping = false
ok(OnBlizzardPinAction(canvas, A.Click, "LeftButton") == true and gq == 1 and dropped == 1, "otherwise: the quest pin handler")
ok(wsrc:find("map:AddGlobalPinMouseActionHandler(OnBlizzardPinAction, 1000)", 1, true), "registered as the map's global pin handler")

print("== 11. the source: nothing written on the game's pins")
local src = assert(io.open(root .. "Map/Quests.lua")):read("*a")
local block = src:match("%(1%.2%.57%) the game's own quest pins.-\nfunction mod%.GameQuestPinAction.-\nend\n")
ok(block and not block:find("SetScript", 1, true) and not block:find("EnableMouse", 1, true) and not block:find("SetFrameLevel", 1, true)
	and not block:find("SetMouseClickEnabled", 1, true) and not block:find("Hide", 1, true) and not block:find("SetPoint", 1, true)
	and not block:find("QuestWatch", 1, true) and not block:find("HasSecretRestrictions", 1, true),
	"no SetScript / EnableMouse / frame level / hide / move / watch calls on the game's pins")
ok(src:find("mapID ~= host and C_QuestLog.GetQuestsOnMap(mapID) or NONE", 1, true), "the zone underneath is skipped")

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
