--------------------------------------------------------------------------------
-- Flight paths on the world map (ns.MapFlights, the game's flight network):
--   * every flight master of your faction: learned ones in colour, the rest grey
--     (learned = seen as known at a flight master; remembered per character)
--   * click one, then another: the route you'd fly is drawn along the real
--     flight paths, with the stops and a time estimate
--   * times: measured from your own flights once you've flown a leg, otherwise
--     the path's length at SPEED yards a second
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local F = ns.MapFlights

mod.defaults.flightTimes = {}   -- "from|to" -> seconds, measured (account-wide)

local SPEED = 30                -- yards a second (classic flights, roughly)
local ROUTE_COLOR = { 0.95, 0.78, 0.35 }
local KNOWN_ATLAS = { "TaxiNode_Alliance", "TaxiNode_Horde" }

local nodeAt = {}               -- node id -> { u, v } on the world (normalized)
local edges = {}                -- node id -> { { to, path }, ... }
local pins = {}                 -- node id -> pin
local set, routeSet
local selected                  -- the first node clicked
local factionBit

--------------------------------------------------------------------------------
-- Known flight masters (per character) and measured times
--------------------------------------------------------------------------------

-- the flight masters the game says you've found (C_TaxiMap.GetTaxiNodesForMap: isUndiscovered false),
-- read afresh as the map opens: every one learned, before Valhalla was installed too. The same list
-- names them in the client's own language, so the tables' English is replaced by it here (once the
-- map opens: the tooltips, the route's caption, the search, the learned names and the measured times
-- all read a node's name off this table, and in a client not in English the English ones matched
-- none of the game's). Only Alterac Valley's pair, on neither continent's list, keeps the English.
local found = {}
local function ReadFound()
	wipe(found)
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return end
	local seen, hidden = {}, 0
	local continents = ns.MapWorld and ns.MapWorld.continents or { 1414, 1415 }   -- (Kalimdor, the Eastern Kingdoms; a client's own)
	for _, mapID in ipairs(continents) do
		local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
		if ok and type(list) == "table" then
			for _, info in ipairs(list) do
				if type(info) == "table" and info.nodeID then
					if info.isUndiscovered == false then seen[info.nodeID] = true
					elseif info.isUndiscovered == true then hidden = hidden + 1 end
					local n = F.nodes[info.nodeID]
					if n and type(info.name) == "string" and info.name ~= "" then n[1] = info.name end
				end
			end
		end
	end
	-- (none of them undiscovered: the game isn't saying. WoW Forever lists all 74 as found, learned or
	-- not, and every flight master showed as learned. Then only the ones seen at a flight master count)
	if hidden == 0 then return end
	for id in pairs(seen) do found[id] = true end
end

local function Known(id)
	if found[id] then return true end
	local n = F.nodes[id]
	return n and mod.char.flightsKnown and mod.char.flightsKnown[n[1]]
end

-- learned ones in their colour, the rest grey; both a size up from the map's other icons and outlined
-- in dark, as the boot alone was lost on the parchment (a grey one at 14 and half see-through above all)
local SIZE_KNOWN, SIZE_NOT = 22, 18

local function RefreshLook()
	ReadFound()
	for id, pin in pairs(pins) do
		local known = Known(id)
		pin:SetShown(known or not mod.db.foundOnly)   -- (Only places you've found: learned ones only)
		pin.Icon:SetDesaturated(not known)
		pin.Icon:SetAlpha(known and 1 or 0.9)
		if pin.shadow then pin.shadow:SetAlpha(known and 0.8 or 0.65) end
		local size = known and SIZE_KNOWN or SIZE_NOT
		pin:SetSize(size, size)
	end
end

local taxi = {}                 -- the flight in progress: from, to, start

-- the kinds of node a flight master lists that you've learned. DISTANT is one a flight passes through
-- that you haven't (the game's own flight map shows it only on a route through it); 0.7.5 and before
-- counted it, and every flight master showed as learned (players' reports)
local LEARNED = { CURRENT = true, REACHABLE = true, UNREACHABLE = true }

local function OnTaxiMap()
	mod.char.flightsKnown = mod.char.flightsKnown or {}
	local current
	for i = 1, NumTaxiNodes() do
		local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
		if LEARNED[kind] then mod.char.flightsKnown[name] = true end
		if kind == "CURRENT" then current = name end
	end
	taxi.here = current
	RefreshLook()
end

--------------------------------------------------------------------------------
-- The flight timer (1.2.12): a popup from takeoff to landing. A route flown before (the whole route, or
-- every leg of it) counts down from its measured time; one never flown shows the time so far and
-- "Learning", and is measured as it lands. Nothing is guessed from distances.
--   mod.db.flightRoutes["fromID>toID"] = seconds, the whole route (any stops), by the game's node IDs
--   mod.db.flightTimes["from|to"]      = seconds, direct legs by name (as before; the map's routes use them)
--   mod.char.flightNow                 = the flight in the air (resumed after a /reload)
-- Only our own plain frames: nothing protected, so it works in combat. It moves only while Edit Mode is
-- open (Edit Mode's own Enter / Exit events); Blizzard's Edit Mode frames are never written.
--------------------------------------------------------------------------------

mod.defaults.flightTimer = true      -- (1.2.12) the flight timer popup
mod.defaults.flightRoutes = {}       -- (1.2.12) whole routes' measured seconds, "fromID>toID"
mod.defaults.flightTimerPos = false  -- (1.2.12) where it was moved to: { point, relativePoint, x, y }; false: TOP 0, -110

local T = { TICK = 0.1, FADE_HOLD = 1.5, FADE = 1, MIN_SECS = 5, RELOAD_GAP = 10, WAIT = 10, W = 250, H = 58 }
F.Timer = T
T.POS = { "TOP", "TOP", 0, -110 }

local flight            -- the flight: { key, from, to, dest, legs = { { a, b, nameA, nameB }... }, start, asked, epoch, expect, early, noSave }
local watch = 0         -- (a newer flight stops older watchers)
local popup, editing

local function Round(x) return math.floor(x + 0.5) end
T.Clock = function(secs) secs = math.max(0, Round(secs)) return ("%d:%02d"):format(math.floor(secs / 60), secs % 60) end

-- the game's node ID for a flight master's slot (its own list), else by name among this faction's
local function NodeIDs()
	local ids = {}
	local mapID = GetTaxiMapID and ns.Safe.Call(GetTaxiMapID)
	local list = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and ns.Safe.Call(C_TaxiMap.GetAllTaxiNodes, mapID)
	if type(list) == "table" then
		for _, info in ipairs(list) do
			if type(info) == "table" and info.slotIndex and info.nodeID then ids[info.slotIndex] = info.nodeID end
		end
	end
	return ids
end
local function IDByName(name)
	if not name then return end
	local fb = factionBit or (UnitFactionGroup("player") == "Horde" and 2 or 1)
	for id, n in pairs(F.nodes) do
		if n[1] == name and bit.band(n[5], fb) ~= 0 then return id end
	end
end

-- a route's key: node IDs when known, else the names
local function Key(a, b, nameA, nameB)
	if a and b then return a .. ">" .. b end
	if nameA and nameB then return nameA .. ">" .. nameB end
end
T.Key = Key

-- the time a route takes, measured: the whole route, else (with stops) every leg measured; else nil
function T.Expected(f)
	local db = mod.db
	local t = f.key and db.flightRoutes[f.key]
	if t then return t end
	if #f.legs == 0 then return end
	local sum = 0
	for _, leg in ipairs(f.legs) do
		local lt = db.flightRoutes[Key(leg[1], leg[2], leg[3], leg[4]) or ""]
			or (leg[3] and leg[4] and db.flightTimes[leg[3] .. "|" .. leg[4]])
		if not lt then return end
		sum = sum + lt
	end
	return sum
end

-- the popup ------------------------------------------------------------------

local function ShortName(name)
	local s = (name or ""):match("^[^,]+") or name or ""
	local i = s:find("，", 1, true)
	return i and s:sub(1, i - 1) or s
end

local function Place(f)
	local p = mod.db.flightTimerPos
	f:ClearAllPoints()
	if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2] or p[1], tonumber(p[3]) or 0, tonumber(p[4]) or 0)
	else f:SetPoint(T.POS[1], UIParent, T.POS[2], T.POS[3], T.POS[4]) end
end

local function Colour()
	local th = ns.Style and ns.Style.Theme and ns.Style.Theme()
	local c = th and th.text or { 1, 0.82, 0 }
	return c
end

local function Popup()
	if popup then return popup end
	local f = CreateFrame("Frame", "ValhallaFlightTimer", UIParent)
	f:SetSize(T.W, T.H)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false)
	Place(f)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 10, -8)
	f.title:SetPoint("TOPRIGHT", -10, -8)
	f.title:SetJustifyH("LEFT")
	ns.Look:Font(f.title, 13)
	if ns.Style and ns.Style.Title then ns.Style.Title(f.title, 13) end
	f.time = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.time:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	ns.Look:Font(f.time, 15, "OUTLINE")
	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.status:SetPoint("TOPRIGHT", -10, -29)
	f.status:SetJustifyH("RIGHT")
	ns.Look:Font(f.status, 11)
	f.bar = CreateFrame("StatusBar", nil, f)
	f.bar:SetPoint("BOTTOMLEFT", 10, 8)
	f.bar:SetPoint("BOTTOMRIGHT", -10, 8)
	f.bar:SetHeight(6)
	f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	f.bar:SetMinMaxValues(0, 1)
	f.bar.bg = f.bar:CreateTexture(nil, "BACKGROUND")
	f.bar.bg:SetAllPoints()
	f.bar.bg:SetColorTexture(0, 0, 0, 0.55)
	-- (1.2.13) the look's own popup: Norse heavy bronze with corner brackets, Profession the profession
	-- window's background in a metal and gold edge; the bar bronze or gold (UI/Style.lua's popup)
	if ns.Style and ns.Style.Popup then ns.Style.Popup(f, f.bar) else ns.Look:Panel(f, { alpha = 0.88 }) end
	-- Edit Mode: a blue box over it, as Edit Mode marks what can move
	f.edit = f:CreateTexture(nil, "OVERLAY", nil, 7)
	f.edit:SetAllPoints()
	f.edit:SetColorTexture(0.1, 0.55, 1, 0.3)
	f.edit:Hide()
	f:SetScript("OnMouseDown", function(self, button)
		if not editing then return end
		if button == "RightButton" then T.ResetPosition() return end
		self:StartMoving()
	end)
	f:SetScript("OnMouseUp", function(self)
		if not editing then return end
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint(1)
		if point then mod.db.flightTimerPos = { point, rel or point, Round(x or 0), Round(y or 0) } end
		Place(self)
	end)
	f:Hide()
	popup = f
	T.popup = f
	return f
end

local function Paint()
	local f = popup
	if not f then return end
	local c = Colour()
	f.title:SetTextColor(c[1], c[2], c[3])
	if not (ns.Style and ns.Style.Popup) then f.bar:SetStatusBarColor(c[1], c[2] * 0.85, c[3] + 0.1) end
end

-- what the popup says now: the destination, the time, the bar
function T.Show(now)
	local L = ns.L
	local f = Popup()
	if editing and not flight then
		f.title:SetText(L["Flight timer"])
		f.time:SetText("2:15")
		f.status:SetText(L["Drag to move; right-click: reset"])
		f.bar:SetValue(0.4)
		f.bar:Show()
		Paint()
		f:SetAlpha(1)
		f:Show()
		return
	end
	if not flight or not mod.db.flightTimer then if not editing then f:Hide() end return end
	local elapsed = math.max(0, now - flight.start)
	f.title:SetText(flight.dest and ShortName(flight.dest) or (flight.reloaded and L["In flight (reloaded)"]) or L["In flight"])
	local e = flight.expect
	if e and e > 0 then
		if elapsed <= e then
			f.time:SetText(T.Clock(e - elapsed))
			f.status:SetText("")
			f.bar:SetValue(elapsed / e)
		else
			f.time:SetText(L["Landing soon (+%s)"]:format(T.Clock(elapsed - e)))
			f.status:SetText("")
			f.bar:SetValue(1)
		end
		f.bar:Show()
	else
		f.time:SetText(T.Clock(elapsed))
		f.status:SetText(L["Learning"])
		f.bar:Hide()
	end
	Paint()
	f:SetAlpha(1)
	f:Show()
end

local fadeToken = 0
local function Fade()
	if not popup or editing then return end
	fadeToken = fadeToken + 1
	local token, t0 = fadeToken, GetTime()
	local function step()
		if token ~= fadeToken or editing or flight then return end
		local t = GetTime() - t0 - T.FADE_HOLD
		if t >= T.FADE then popup:Hide() popup:SetAlpha(1) return end
		popup:SetAlpha(t > 0 and (1 - t / T.FADE) or 1)
		C_Timer.After(0.05, step)
	end
	step()
end

function T.ResetPosition()
	mod.db.flightTimerPos = false
	if popup then Place(popup) end
end

function T.SetEditing(on)
	editing = on and true or false
	local f = Popup()
	f:EnableMouse(editing)
	f.edit:SetShown(editing)
	if editing then fadeToken = fadeToken + 1 T.Show(GetTime())
	elseif flight then T.Show(GetTime())
	else f:Hide() end
end

function T.Refresh()
	if flight then T.Show(GetTime()) elseif popup and not editing then popup:Hide() end
end
function mod.RefreshFlightTimer() T.Refresh() end

-- the flight ------------------------------------------------------------------

local function Save()
	if flight and flight.start then
		mod.char.flightNow = { key = flight.key, from = flight.from, to = flight.to, dest = flight.dest, legs = flight.legs,
			epoch = flight.epoch, seen = time(), noSave = flight.noSave, early = flight.early,
			direct = flight.direct, fromName = flight.fromName, unknown = flight.unknown, reloaded = flight.reloaded }
	else
		mod.char.flightNow = nil
	end
end

local function Landed(now)
	local secs = now - flight.start
	if not flight.early and not flight.noSave and secs > T.MIN_SECS then
		if flight.key then mod.db.flightRoutes[flight.key] = Round(secs) end
		-- (direct legs, by name, as before: the map's route times read them)
		if flight.direct and flight.fromName and flight.dest then mod.db.flightTimes[flight.fromName .. "|" .. flight.dest] = Round(secs) end
	end
	flight = nil
	T.flight = nil
	Save()
	if popup and popup:IsShown() then Fade() end
end

local function Tick(token)
	if token ~= watch or not flight then return end
	local now = GetTime()
	if UnitOnTaxi("player") then
		if not flight.start then
			flight.start, flight.epoch = now, time()
			flight.expect = T.Expected(flight)
		end
		if flight.epoch then
			local c = mod.char.flightNow
			if c then c.seen = time() else Save() end
		end
		T.Show(now)
	elseif flight.start then
		Landed(now)
		return
	elseif now - flight.asked > T.WAIT then
		flight, T.flight = nil, nil   -- never took off
		Save()
		return
	end
	C_Timer.After(T.TICK, function() Tick(token) end)
end

local function Watch()
	watch = watch + 1
	local token = watch
	T.flight = flight
	C_Timer.After(T.TICK, function() Tick(token) end)
end

local function OnTakeTaxi(index)
	local ids = NodeIDs()
	local hops = GetNumRoutes and ns.Safe.Call(GetNumRoutes, index) or 0
	local legs = {}
	for h = 1, hops do
		local sa = ns.Safe.Call(TaxiGetNodeSlot, index, h, true)
		local sb = ns.Safe.Call(TaxiGetNodeSlot, index, h, false)
		local na, nb = sa and ns.Safe.Call(TaxiNodeName, sa), sb and ns.Safe.Call(TaxiNodeName, sb)
		legs[#legs + 1] = { (sa and ids[sa]) or IDByName(na), (sb and ids[sb]) or IDByName(nb), na, nb }
	end
	local dest = TaxiNodeName(index)
	local here = taxi.here
	local from = legs[1] and legs[1][1] or IDByName(here)
	local to = ids[index] or (legs[#legs] and legs[#legs][2]) or IDByName(dest)
	flight = { from = from, to = to, dest = dest, fromName = here or (legs[1] and legs[1][3]), legs = legs,
		asked = GetTime(), direct = hops == 1 }
	flight.key = Key(from, to, flight.fromName, dest)
	Watch()
end

-- (1.2.13) a flight Valhalla didn't see start (begun before it loaded, or by a click it didn't hear): shown as
-- "In flight" (after a /reload "In flight (reloaded)") with the time since it was seen, Learning; never saved
local function StartUnknown(reloaded)
	local now = GetTime()
	flight = { legs = {}, unknown = true, reloaded = reloaded and true or nil, noSave = true, asked = now,
		start = now, epoch = time() }
	Save()
	Watch()
	T.Show(now)
end

-- after a /reload in the air: the flight goes on from its start (a log-in later: shown, not measured).
-- `final`: the last look (the world entered): on the ground, a flight saved is forgotten; in the air with
-- none saved, an unknown flight
local function Resume(final)
	if flight then return end
	local c = mod.char.flightNow
	if not UnitOnTaxi("player") then
		if final then mod.char.flightNow = nil end
		return
	end
	if type(c) ~= "table" or not c.epoch then StartUnknown(true) return end
	local now, wall = GetTime(), time()
	flight = { key = c.key, from = c.from, to = c.to, dest = c.dest, legs = c.legs or {}, direct = c.direct,
		fromName = c.fromName, early = c.early, epoch = c.epoch, asked = now, unknown = c.unknown, reloaded = c.reloaded,
		noSave = c.noSave or c.unknown or not c.seen or (wall - c.seen) > T.RELOAD_GAP }
	flight.start = now - math.max(0, wall - c.epoch)
	flight.expect = T.Expected(flight)
	Watch()
	T.Show(now)
end
T.Resume = Resume

-- (1.2.13) control lost: a flight if the player is on a taxi within a moment (a stun or a fear isn't)
local controlToken = 0
local function OnControlLost()
	if flight and flight.start then return end
	controlToken = controlToken + 1
	local token, t0 = controlToken, GetTime()
	local function check()
		if token ~= controlToken or (flight and flight.start) then return end
		if UnitOnTaxi("player") then
			if not flight then StartUnknown(false) end   -- (a click heard: Tick starts it)
			return
		end
		if GetTime() - t0 < 3 then C_Timer.After(0.2, check) end
	end
	check()
end

-- where the flight master is (its list's CURRENT), for the direct legs' names: the timer's own, the map off too
local function OnTaxiOpened()
	for i = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
		if TaxiNodeGetType(i) == "CURRENT" then taxi.here = TaxiNodeName(i) end
	end
end

-- (1.2.13) set up at PLAYER_LOGIN, whatever the map does (off, waiting for the Gamepad UI, Blizzard's map
-- not the kind expected): once; SetupFlights calls it too and finds it done
local function SetupTimer()
	if T.setup then return end
	T.setup = true
	if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", OnTakeTaxi) T.hooked = true T.hooks = (T.hooks or 0) + 1 end
	if TaxiRequestEarlyLanding then
		hooksecurefunc("TaxiRequestEarlyLanding", function() if flight then flight.early = true Save() end end)
	end
	ns.RegisterEvent(T, "TAXIMAP_OPENED", OnTaxiOpened)
	ns.RegisterEvent(T, "PLAYER_CONTROL_LOST", OnControlLost)
	ns.RegisterEvent(T, "PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() Resume(true) end) end)
	local ER = rawget(_G, "EventRegistry")
	if ER and ER.RegisterCallback then
		ER:RegisterCallback("EditMode.Enter", function() T.SetEditing(true) end, T)
		ER:RegisterCallback("EditMode.Exit", function() T.SetEditing(false) end, T)
	end
	if ns.Style and ns.Style.OnLook then ns.Style.OnLook(function() Paint() end) end
	Resume(false)
end
T.Setup = SetupTimer
ns.RegisterEvent(T, "PLAYER_LOGIN", function()
	ns.UnregisterEvent(T, "PLAYER_LOGIN")
	if mod.db and mod.char then SetupTimer() end
end)

-- /valhalla flight: the timer's state, for a report
function T.Debug()
	local L, db = ns.L, mod.db or {}
	local n = 0
	for _ in pairs(db.flightRoutes or {}) do n = n + 1 end
	local look = ns.Style and ns.Style.Look and ns.Style.Look() or "?"
	ns:Print(L["Flight timer: set up %s, TakeTaxiNode heard %s, setting %s, look %s"],
		tostring(T.setup and true or false), tostring(T.hooked and true or false), tostring(db.flightTimer), look)
	local now = GetTime()
	if flight then
		ns:Print(L["In the air: %s, route %s, %s, elapsed %s, %s%s%s"],
			tostring(flight.dest or (flight.reloaded and "In flight (reloaded)") or "In flight"), tostring(flight.key),
			flight.expect and ("expected " .. T.Clock(flight.expect)) or "Learning",
			flight.start and T.Clock(now - flight.start) or "not off yet",
			flight.unknown and "unknown, " or "", flight.noSave and "not saved" or "saved on landing", flight.early and ", landing early" or "")
	else
		ns:Print(L["Not flying (on a taxi: %s); saved flight: %s"], tostring(UnitOnTaxi("player") and true or false),
			tostring(mod.char and mod.char.flightNow ~= nil))
	end
	local p = db.flightTimerPos
	ns:Print(L["Popup: %s, at %s; routes timed: %d"], popup and (popup:IsShown() and "shown" or "hidden") or "not made yet",
		type(p) == "table" and table.concat({ tostring(p[1]), tostring(p[2]), tostring(p[3]), tostring(p[4]) }, " ") or "TOP 0 -110", n)
end

--------------------------------------------------------------------------------
-- Routes
--------------------------------------------------------------------------------

local function Usable(id)
	local n = F.nodes[id]
	return n and bit.band(n[5], factionBit) ~= 0
end

-- cheapest route by flight length; `knownOnly` keeps to learned flight masters
local function Route(from, to, knownOnly)
	local dist, prev, via, done = { [from] = 0 }, {}, {}, {}
	while true do
		local best, bd
		for id, d in pairs(dist) do
			if not done[id] and (not bd or d < bd) then best, bd = id, d end
		end
		if not best then return end
		if best == to then break end
		done[best] = true
		for _, e in ipairs(edges[best] or {}) do
			local nxt, path = e[1], e[2]
			if Usable(nxt) and (not knownOnly or Known(nxt) or nxt == to) then
				local nd = bd + path[3]
				if not dist[nxt] or nd < dist[nxt] then dist[nxt], prev[nxt], via[nxt] = nd, best, path end
			end
		end
	end
	local legs = {}
	local id = to
	while id ~= from do
		tinsert(legs, 1, via[id])
		id = prev[id]
	end
	return legs
end

local function Clock(secs)
	return ("%d:%02d"):format(math.floor(secs / 60), math.floor(secs % 60))
end

-- a node's name without its zone: "Stormwind, Elwynn", the client's own "暴风城，艾尔文森林" too.
-- The full-width comma is searched as plain text: Lua patterns work on bytes, so a class holding it
-- would cut at one of its three UTF-8 bytes, in the middle of a neighbouring character.
local function Short(name)
	local s = name:match("^[^,]+") or name
	local i = s:find("，", 1, true)
	return i and s:sub(1, i - 1) or s
end

-- each leg's time: measured, or estimated from its length
local function LegTime(path)
	local a, b = F.nodes[path[1]], F.nodes[path[2]]
	local t = mod.db.flightTimes[a[1] .. "|" .. b[1]]
	return t or path[3] / SPEED, t ~= nil
end

local label                     -- the route's caption (a pin with no icon)

local function ClearRoute()
	if routeSet then S.ClearPinSet(routeSet) end
	if selected and pins[selected] then pins[selected].ring:Hide() end
	selected = nil
end

local function ShowRoute(from, to)
	S.ClearPinSet(routeSet)
	local legs, knownOnly = Route(from, to, true), true
	if not legs then legs, knownOnly = Route(from, to, false), false end
	if not legs then
		ns:Print(ns.L["No flight route from %s to %s."], F.nodes[from][1], F.nodes[to][1])
		return
	end
	-- (the learned-only search lets the ends through unlearned, to keep to learned stops between
	-- them: a route that starts or ends at one you haven't learned still needs it)
	knownOnly = knownOnly and Known(from) and Known(to) and true or false
	local total, measured, cont = 0, true, F.nodes[from][2]
	local r, g, b = unpack(ROUTE_COLOR)
	local alpha = knownOnly and 0.95 or 0.5
	for _, path in ipairs(legs) do
		local t, m = LegTime(path)
		total = total + t
		measured = measured and m
		local p = path[5]
		local pu, pv = S.FromYards(cont, p[1], p[2])
		for k = 3, #p, 2 do
			local u, v = S.FromYards(cont, p[k], p[k + 1])
			if pu and u then
				local line = S.AddLine(routeSet, pu, pv, u, v, 3, 0.25, 0.16, 0.05, alpha * 0.8)   -- dark edge
				local core = S.AddLine(routeSet, pu, pv, u, v, 1.6, r, g, b, alpha)
				line:SetDrawLayer("ARTWORK", 0)
				core:SetDrawLayer("ARTWORK", 1)
			end
			pu, pv = u, v
		end
	end

	-- the caption, beside the destination
	local du, dv = unpack(nodeAt[to])
	label = S.AddPin(routeSet, du, dv, { texture = "", size = 1 })
	label:EnableMouse(false)
	if not label.caption then           -- pins are pooled: the caption is made once
		label.caption = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label.caption:SetPoint("LEFT", label, "CENTER", 14, 0)
		ns.Look:Font(label.caption, 13, "OUTLINE")
	end
	local fs = label.caption
	local stops = #legs - 1
	local L = ns.L
	fs:SetText(("%s > %s  |cffffffff%s|r%s"):format(
		Short(F.nodes[from][1]), Short(F.nodes[to][1]),
		measured and Clock(total) or L["about %s"]:format(Clock(total)),
		stops > 0 and ("  |cffaaaaaa(" .. (stops == 1 and L["1 stop"] or L["%d stops"]:format(stops)) .. ")|r") or "")
		.. (knownOnly and "" or ("\n|cffff8060" .. L["needs flight masters you haven't learned"] .. "|r")))
end

local function NodeClick(pin)
	local id = pin.node
	if not selected or selected == id then
		ClearRoute()
		selected = id
		pin.ring:Show()
	else
		local from = selected
		pins[from].ring:Hide()
		selected = nil
		ShowRoute(from, id)
	end
end

local function NodeEnter(pin)
	local n = F.nodes[pin.node]
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(n[1], 1, 0.82, 0)
	GameTooltip:AddLine(Known(pin.node) and ns.L["Learned"] or ns.L["Not learned"], 0.8, 0.8, 0.8)
	if selected and selected ~= pin.node then
		local legs = Route(selected, pin.node, true) or Route(selected, pin.node, false)
		if legs then
			local total = 0
			for _, path in ipairs(legs) do total = total + LegTime(path) end
			GameTooltip:AddLine(ns.L["From %s: about %s"]:format(Short(F.nodes[selected][1]), Clock(total)), 1, 1, 1)
		end
		GameTooltip:AddLine(ns.L["Click: show the route"], 0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine(ns.L["Click, then click another flight master: the route and its time"], 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Build (once the stitched map exists)
--------------------------------------------------------------------------------

function mod:BuildFlights()
	if set or not F or not S.IsBuilt() then return end
	local faction = UnitFactionGroup("player")
	factionBit = faction == "Horde" and 2 or 1
	set = S.PinSet("flight", 2.5, 2)
	routeSet = S.PinSet("route", 1, 1)
	for _, path in ipairs(F.paths) do
		edges[path[1]] = edges[path[1]] or {}
		tinsert(edges[path[1]], { path[2], path })
	end
	for id, n in pairs(F.nodes) do
		if Usable(id) then
			local u, v = S.FromYards(n[2], n[3], n[4])
			if u then
				nodeAt[id] = { u, v }
				local look = { atlas = KNOWN_ATLAS[factionBit], size = SIZE_KNOWN }
				local pin = S.AddPin(set, u, v, look)
				pin.node = id
				-- (a dark outline: the boot again, in black, a little bigger, under it)
				pin.shadow = pin.shadow or pin:CreateTexture(nil, "BACKGROUND")
				pin.shadow:ClearAllPoints()
				pin.shadow:SetPoint("TOPLEFT", -3, 3)
				pin.shadow:SetPoint("BOTTOMRIGHT", 3, -3)
				S.Look(pin.shadow, look)
				pin.shadow:SetVertexColor(0, 0, 0)
				pin.shadow:Show()
				pin.ring = pin:CreateTexture(nil, "OVERLAY")
				pin.ring:SetPoint("CENTER")
				pin.ring:SetSize(30, 30)
				S.Look(pin.ring, { atlas = "Waypoint-MapPin-Untracked", texture = "Interface\\Minimap\\Ping\\ping5" })
				pin.ring:SetVertexColor(1, 0.85, 0.3)
				pin.ring:Hide()
				pin:SetScript("OnEnter", NodeEnter)
				pin:SetScript("OnLeave", GameTooltip_Hide)
				pin.OnClick = NodeClick
				pins[id] = pin
			end
		end
	end
	RefreshLook()
end

function mod:ClearFlightRoute() ClearRoute() end
function mod.RefreshFlightsFound() if set then RefreshLook() end end

function mod:SetupFlights()
	-- (those remembered by 0.7.5 and before had DISTANT's unlearned ones in: forgotten once, and counted again at
	-- the next flight master)
	local c = mod.char
	if c and c.flightsKnownV ~= 2 then c.flightsKnown, c.flightsKnownV = nil, 2 end
	ns.RegisterEvent(mod, "TAXIMAP_OPENED", OnTaxiMap)
	ns.RegisterEvent(mod, "TAXI_NODE_STATUS_CHANGED", function() if set then RefreshLook() end end)
	if WorldMapFrame then WorldMapFrame:HookScript("OnShow", function() if set then RefreshLook() end end) end
	SetupTimer()   -- (1.2.12: the flight timer; it watches TakeTaxiNode, measuring direct legs as before)
end
