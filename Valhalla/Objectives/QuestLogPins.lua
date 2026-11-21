--------------------------------------------------------------------------------
-- Objectives (v0.2.2): the quest pins in the game's quest log too (the log beside Valhalla's map is the
-- game's own QuestMapFrame). A pin left of each quest's quest icon, the same store and art as the All
-- Objectives pins (O.SetPinned / O.OnPinsChanged): pinned here, pinned there, both ways.
--
-- How (Blizzard_UIPanels_Game QuestMapFrame.lua): a quest's row comes from QuestScrollFrame.titleFramePool
-- (pooled: every update releases them all and takes them again), its title measured for the row's height
-- right after it's taken, and its quest icon (a POI button) put at (6, -4) on every update. So:
--   * a secure hook on the pool's Acquire moves each row's title right (x 31 -> 50) before the game sets
--     and measures it, so the row's height is right the first time (a moved anchor stays with the row);
--   * a secure hook after QuestLogQuests_Update moves the quest icon to x 25 and paints our pin at (4, -6).
-- Nothing else: no fields written on the game's frames (our pins live in a table of our own, as children
-- of the rows so the log's scroll frame clips them), no Blizzard function called, no mouse pass-through
-- setters (blocked in combat once map code has met an addon's: Map/Combat.lua). Headers (their own pools)
-- get no pin. Turned off with the objectives module (/valhalla objectives off): no pins, and the titles
-- and icons go back as the rows are next laid out.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("objectives")
local O = mod.O

local LP = {}
O.LogPins = LP

LP.SHIFT = 19            -- the room made: the pin (17) and a gap (2)
LP.TEXT_X, LP.TEXT_Y = 31, -8
LP.POI_X, LP.POI_Y = 6, -4
LP.PIN_X, LP.PIN_Y = 4, -6

local on = false
local hooked = false
local shifted = setmetatable({}, { __mode = "k" })   -- row -> the shift its title has
local pins = setmetatable({}, { __mode = "k" })      -- row -> our pin

local function Scroll() return rawget(_G, "QuestScrollFrame") end
local function Pool()
	local q = Scroll()
	return type(q) == "table" and q.titleFramePool or nil
end
function LP.IsOn() return on end
function LP.Hooked() return hooked end

-- a row's title where it should be (as its template anchors it, moved right while on)
local function Shift(row)
	local want = on and LP.SHIFT or 0
	if (shifted[row] or 0) == want then return end
	local t = row.Text
	if not (t and t.SetPoint) then return end
	t:SetPoint("TOPLEFT", row, "TOPLEFT", LP.TEXT_X + want, LP.TEXT_Y)
	shifted[row] = want
end
LP.Shift = Shift

-- after Acquire: the row just taken (and any other active one) gets its title moved before the game
-- writes and measures it
function LP.OnAcquire(pool)
	if not (pool and pool.EnumerateActive) then return end
	for row in pool:EnumerateActive() do Shift(row) end
end

-- the quest icon the game put on a row (found by its quest, checked to be this row's)
local function PoiOf(row, q)
	local q0 = Scroll()
	local contents = q0 and q0.Contents
	local find = contents and contents.FindButtonByQuestID
	if not (q and find) then return nil end
	local ok, b = pcall(find, contents, q)
	if ok and type(b) == "table" and rawget(b, "parent") == row then return b end
	return nil
end

local function PinFor(row)
	local p = pins[row]
	if not p then
		p = O.MakePin(row)
		p:SetPoint("TOPLEFT", row, "TOPLEFT", LP.PIN_X, LP.PIN_Y)
		pins[row] = p
	end
	p:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
	return p
end

-- after the game lays the log out: icons moved, pins painted for whichever quest each row shows now
function LP.OnUpdate()
	local pool = Pool()
	if not (pool and pool.EnumerateActive) then return end
	for row in pool:EnumerateActive() do
		Shift(row)   -- (a row the game took before we were on: right from the next update)
		local q = row.questID
		if on and q then
			local poi = PoiOf(row, q)
			if poi then poi:SetPoint("TOPLEFT", row, "TOPLEFT", LP.POI_X + LP.SHIFT, LP.POI_Y) end
			local p = PinFor(row)
			O.PaintPin(p, q)
			p:Show()
		elseif pins[row] then
			pins[row]:Hide()
		end
	end
end

-- the store changed (a pin clicked here, on the tracker or in Ready, or a quest turned in): repaint
function LP.Repaint()
	local pool = Pool()
	if not (on and pool and pool.EnumerateActive) then return end
	for row in pool:EnumerateActive() do
		local p, q = pins[row], row.questID
		if p and q and p:IsShown() then O.PaintPin(p, q) end
	end
end
O.OnPinsChanged(function() LP.Repaint() end)

local function Hook()
	if hooked then return true end
	local pool = Pool()
	if not (pool and type(pool.Acquire) == "function" and type(rawget(_G, "QuestLogQuests_Update")) == "function"
		and hooksecurefunc) then return false end
	hooksecurefunc(pool, "Acquire", LP.OnAcquire)
	hooksecurefunc("QuestLogQuests_Update", LP.OnUpdate)
	hooked = true
	return true
end
LP.Hook = Hook

function LP.Enable()
	on = true
	Hook()   -- (no quest log, or a different one: no pins, nothing else changes)
end

function LP.Disable()
	on = false
	for _, p in pairs(pins) do p:Hide() end
end
