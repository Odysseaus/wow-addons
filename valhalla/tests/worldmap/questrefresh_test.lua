-- Box tests for Map/Quests.lua (1.2.56): the map's quest icons are redrawn as the map opens after a quest
-- change while it was closed (same frame, no EVERY wait), not redrawn when nothing changed, the open map's
-- bursts still wait EVERY, and the read-only questMapDiag. Lua 5.1.
-- Run: lua5.1 valhalla/tests/worldmap/questrefresh_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
	if cond then pass = pass + 1 print("PASS  " .. name)
	else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- the clock and C_Timer: timers run when the test says (Advance)
local now = 100
function GetTime() return now end
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function Advance(d)
	now = now + d
	local again = true
	while again do
		again = false
		for i, t in ipairs(timers) do
			if t.at <= now then table.remove(timers, i) t.fn() again = true break end
		end
	end
end

-- the stitched map's pin set: each redraw counted, the pins it drew kept
local draws = 0
local set = { pins = {} }
local S = {
	WORLD = 947,
	IsBuilt = function() return true end,
	PinSet = function() return set end,
	ClearPinSet = function(s) s.pins = {} end,
	SetPinSetOn = function(s, on) s.on = on end,
	Rect = function() return 0, 1, 0, 1 end,
	AddPin = function(s, u, v, look, data)
		local pin = { u = u, v = v, data = data, SetScale = function() end, SetSize = function() end, Hide = function() end,
			SetScript = function() end, Icon = { SetAlpha = function() end }, Highlight = { SetAlpha = function() end } }
		s.pins[#s.pins + 1] = pin
		return pin
	end,
}
local host = 1433
local mod = { defaults = {}, db = { allQuests = true } }
mod.HostMap = function() return host end
mod.IsStitched = function() return true end
mod.ToWorld = function(_, x, y) return x, y end
local _RefreshQuests
local ns = { MapStitch = S, L = setmetatable({}, { __index = function(_, k) return k end }) }
function ns:GetModule() return mod end
ns.Parts = { QuestPoi = function() return { ClearAllPoints = function() end, SetPoint = function() end, Show = function() end } end,
	PaintQuestPoi = function() end }
Enum = { UIMapType = { Continent = 2, Zone = 3 } }
-- the game's quest positions: questID -> { x, y } on map 1433 (Redridge)
local qpos = { [20] = { 0.30, 0.60 }, [21] = { 0.50, 0.50 } }
local complete = {}
local onMapCalls = 0
C_QuestLog = {
	GetQuestsOnMap = function(id)
		onMapCalls = onMapCalls + 1
		if id ~= 1433 then return {} end
		local out = {}
		for q, p in pairs(qpos) do out[#out + 1] = { questID = q, x = p[1], y = p[2] } end
		table.sort(out, function(a, b) return a.questID < b.questID end)
		return out
	end,
	IsComplete = function(id) return complete[id] or false end,
}
C_Map = { GetMapChildrenInfo = function() return { { mapID = 1433 } } end, GetMapInfo = function() return { mapType = 3 } end,
	GetBestMapForUnit = function() return 1433 end }
C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end }
function GetCVarBool() return true end
function date() return "21:40:00" end
ValhallaDB = {}
-- the world map: shown or not, its OnShow / OnHide hooks and OnMapChanged post-hook
local shown = false
local hooks = {}
local map = { IsShown = function() return shown end, HookScript = function(_, n, fn) hooks[n] = fn end }
local mapChanged
function hooksecurefunc(t, name, fn) if t == map and name == "OnMapChanged" then mapChanged = fn end end
local ev
CreateFrame = function()
	return { RegisterEvent = function() end, SetScript = function(self, n, fn) if n == "OnEvent" then ev = fn end end }
end
local function Fire(e, a) ev(nil, e, a) end
local function Open() shown = true hooks.OnShow(map) end
local function Close() shown = false hooks.OnHide(map) end

assert(loadfile(root .. "Map/Quests.lua"))("Valhalla", ns)
_RefreshQuests = mod.RefreshQuests
mod.RefreshQuests = function(self) draws = draws + 1 return _RefreshQuests(self) end
mod:SetupQuests(map)
local function PinOf(q) for _, p in ipairs(set.pins) do if p.data.id == q then return p end end end

print("== 1. the first opening draws the icons in that same frame")
Open()
ok(draws == 1 and PinOf(20) and PinOf(21), "drawn as the map opens, no wait", draws)
Advance(1)
Close()

print("== 2. a quest event while the map is closed: no work, drawn the moment it opens")
draws = 0
complete[20] = true
qpos[20] = { 0.70, 0.20 }                      -- (its turn-in)
Fire("QUEST_LOG_UPDATE")
Fire("QUEST_POI_UPDATE")
Advance(2)
ok(draws == 0 and #timers == 0, "closed: nothing redrawn, nothing scheduled", draws)
Open()
ok(draws == 1 and PinOf(20) and PinOf(20).u == 0.70 and PinOf(20).v == 0.20 and PinOf(20).data.complete == true,
	"opening: the completed quest is at its turn-in, complete, in the same frame", PinOf(20) and PinOf(20).u)
Advance(0)
ok(draws == 1, "next frame, the map underneath unchanged: not drawn again", draws)

print("== 3. nothing changed while closed: the drawn icons are kept as it opens")
Close()
draws = 0
Open()
Advance(0)
ok(draws == 0 and PinOf(20), "no quest event: no redraw, the icons as they were", draws)

print("== 4. the map underneath set later in the opening frame: looked at again next frame")
Close()
draws = 0
Open()
host = 1436
Advance(0)
ok(draws == 1, "the host changed after the opening: redrawn next frame", draws)
host = 1433
Advance(1)

print("== 5. the open map: a burst waits EVERY (one redraw); OnMapChanged still redraws")
draws = 0
for _ = 1, 5 do Fire("QUEST_LOG_UPDATE") end
Advance(0.4)
ok(draws == 0, "a burst: not yet at 0.4 s", draws)
Advance(0.2)
ok(draws == 1, "one redraw at 0.5 s", draws)
mapChanged()
Advance(0.6)
ok(draws == 2, "OnMapChanged: redrawn", draws)
Fire("CVAR_UPDATE", "someOtherCVar")
Advance(0.6)
ok(draws == 2, "another CVar: nothing", draws)

print("== 6. questMapDiag: a closed-map completion, its place at opening and at the opening's POI update")
Close()
ValhallaDB.questMapDiag = nil
complete[21] = nil
qpos[21] = { 0.50, 0.50 }
Fire("QUEST_LOG_UPDATE")
ok(ValhallaDB.questMapDiag and #ValhallaDB.questMapDiag == 0, "an event with nothing newly complete: no entry")
complete[21] = true
Fire("QUEST_LOG_UPDATE")                       -- (complete; the game still says the objective's place)
qpos[21] = { 0.10, 0.90 }
Fire("QUEST_POI_UPDATE")                       -- (then the turn-in)
local d = ValhallaDB.questMapDiag
ok(#d == 1 and d[1].quest == 21 and d[1].map == 1433 and d[1].closed.x == 0.5 and d[1].closedLast and d[1].closedLast.x == 0.1 and d[1].t == now,
	"one entry: the quest, its map, the time, the place when it turned complete and the last before opening",
	d[1] and (tostring(d[1].closed and d[1].closed.x) .. " " .. tostring(d[1].closedLast and d[1].closedLast.x)))
Open()
ok(d[1].open and d[1].open.x == 0.1 and d[1].open.y == 0.9 and d[1].sameAtOpen == true and d[1].openClock,
	"at the opening redraw: its place, the same as the last closed one", tostring(d[1].sameAtOpen))
Advance(1)
qpos[21] = { 0.15, 0.85 }
Fire("QUEST_POI_UPDATE")
Advance(0.6)
ok(d[1].poi and d[1].poi.x == 0.15 and d[1].sameAtPoi == false, "the opening's POI update redraw: its place noted (moved)", tostring(d[1].sameAtPoi))
Fire("QUEST_POI_UPDATE")
Advance(0.6)
ok(d[1].poi.x == 0.15, "a later POI update doesn't overwrite it")
local onMap0 = onMapCalls
Fire("QUEST_LOG_UPDATE")
ok(#d == 1, "the open map: no closed-map entries")
print("== 7. questMapDiag: a quest complete before the map closed is not a closed-map completion; the last 20 kept")
Close()
Fire("QUEST_LOG_UPDATE")
ok(#d == 1, "already complete as it closed: no entry", #d)
for i = 1, 25 do
	local q = 100 + i
	qpos[q] = { 0.2, 0.2 } complete[q] = false
	Fire("QUEST_LOG_UPDATE")
	complete[q] = true
	Fire("QUEST_LOG_UPDATE")
end
ok(#ValhallaDB.questMapDiag == 20 and ValhallaDB.questMapDiag[20].quest == 125, "the last 20 kept", #ValhallaDB.questMapDiag)

print("== 8. the source: no layout writes, nothing of the game's moved or hidden, no watch calls")
local src = assert(io.open(root .. "Map/Quests.lua")):read("*a")
ok(not src:find("layoutIndex", 1, true) and not src:find("SetFrameLevel", 1, true) and not src:find("AddQuestWatch", 1, true)
	and not src:find("RemoveQuestWatch", 1, true), "no layout or frame level writes, no watch calls")
ok(src:find('map:HookScript("OnShow", Opened)', 1, true) and src:find('hooksecurefunc(map, "OnMapChanged", Soon)', 1, true),
	"OnShow is hooked (not set), OnMapChanged post-hooked")

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
