--------------------------------------------------------------------------------
-- CombatQueue (1.2.23, gate widened 1.2.24): what Valhalla would do to the game's quest tracker, quest log,
-- waypoint or windows waits while the game could be keeping auras secret, and runs once that's over.
--
-- Why: the game's quest tracker and Edit Mode read a player aura from the tracker's update (Blizzard_MawBuffs.lua's
-- ShouldShowMawBuffs). While auras are secret, a read from code an addon touched errors ("Auras cannot be
-- accessed when secret while tainted by 'Valhalla'"). Valhalla's watch, super-track, waypoint, quest details,
-- quest-log header and window calls make the tracker lay out (on the next frame) from Valhalla's code, so they
-- are kept out of those times.
--
-- The gate (Q.Blocked): InCombatLockdown(), or UnitAffectingCombat("player"), or C_Secrets.HasSecretRestrictions(),
-- or the settle after combat (SETTLE seconds from PLAYER_REGEN_ENABLED). A secret answer counts as blocked.
--
--   ns.Combat.Run(key, fn, note)   fn() now when clear and nothing queued (true); else queued under key (false):
--                                   a later Run with the same key replaces it (last write wins, moved to the end).
--                                   note: printed once per wait, when given.
--   ns.Combat.Flush()              runs the queue in order when clear (else 0, checked again later); the count run
--   ns.Combat.Pending(key)         queued? (any, with no key)
--   ns.Combat.Blocked()            the gate now; ns.Combat.Why(): its reasons ({} when clear)
--   ns.Combat.Cancel(key)          a queued key dropped
-- After PLAYER_REGEN_ENABLED the queue waits SETTLE seconds, then runs only if the gate is clear; if not, it's
-- checked again every SETTLE seconds (out of combat lockdown; in it, the next PLAYER_REGEN_ENABLED starts again).
--------------------------------------------------------------------------------
local ADDON, ns = ...

local Q = { order = {}, ops = {}, said = {}, settleUntil = 0, timer = false }
ns.Combat = Q
Q.SETTLE = 3

local function Now() return GetTime and GetTime() or 0 end
-- a yes/no from the game: a secret (or failing) answer counts as yes (blocked)
local function Yes(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	if not ok then return false end
	if issecretvalue and issecretvalue(v) then return true end
	return v and true or false
end

function Q.InCombat() return Yes(InCombatLockdown) end
function Q.Why()
	local t = {}
	if Yes(InCombatLockdown) then t[#t + 1] = "combat" end
	if Yes(UnitAffectingCombat, "player") and #t == 0 then t[#t + 1] = "combat (unit)" end
	local CS = rawget(_G, "C_Secrets")
	if type(CS) == "table" and Yes(CS.HasSecretRestrictions) then t[#t + 1] = "secret restrictions" end
	if Now() < (Q.settleUntil or 0) then t[#t + 1] = "settling after combat" end
	return t
end
function Q.Blocked() return #Q.Why() > 0 end

local function Drop(key)
	for i = #Q.order, 1, -1 do
		if Q.order[i] == key then table.remove(Q.order, i) end
	end
end

-- the next look at the queue, SETTLE seconds on (one at a time)
local Tick
local function Schedule(delay)
	if Q.timer then return end
	if not (C_Timer and C_Timer.After) then return end
	Q.timer = true
	C_Timer.After(delay or Q.SETTLE, Tick)
end
Q.Schedule = Schedule
Tick = function()
	Q.timer = false
	if #Q.order == 0 then return end
	if Q.InCombat() then return end            -- (PLAYER_REGEN_ENABLED starts the settle again)
	if Q.Blocked() then Schedule() return end   -- (still restricted, or settling: looked at again)
	Q.Flush()
end
Q.Tick = Tick

function Q.Run(key, fn, note)
	if type(fn) ~= "function" then return false end
	key = key or fn
	if not Q.Blocked() and #Q.order == 0 then fn() return true end
	if Q.ops[key] then Drop(key) end
	Q.ops[key] = fn
	Q.order[#Q.order + 1] = key
	if note and not Q.said[note] then
		Q.said[note] = true
		if ns.Print then ns:Print(note) end
	end
	if not Q.InCombat() then Schedule() end      -- (no PLAYER_REGEN_ENABLED will come: looked at in a while)
	return false
end
function Q.Pending(key)
	if key == nil then return #Q.order > 0 end
	return Q.ops[key] ~= nil
end
function Q.Cancel(key)
	if Q.ops[key] == nil then return false end
	Q.ops[key] = nil
	Drop(key)
	return true
end
function Q.Flush()
	if Q.Blocked() then
		if #Q.order > 0 and not Q.InCombat() then Schedule() end
		return 0
	end
	local order, ops = Q.order, Q.ops
	Q.order, Q.ops, Q.said = {}, {}, {}
	local n = 0
	for _, key in ipairs(order) do
		local fn = ops[key]
		if fn then
			n = n + 1
			local ok, err = pcall(fn)
			if not ok and geterrorhandler then geterrorhandler()(err) end
		end
	end
	return n
end

-- combat over: settle first, then the queue (if clear by then)
function Q.CombatEnded()
	Q.settleUntil = Now() + Q.SETTLE
	if #Q.order == 0 then return end
	if C_Timer and C_Timer.After then
		if Q.timer then return end                -- (one already due: it re-checks the gate)
		Schedule(Q.SETTLE)
	else
		Q.settleUntil = 0                         -- (no timers: as 1.2.23, at once)
		Q.Flush()
	end
end
if ns.RegisterEvent then ns.RegisterEvent(Q, "PLAYER_REGEN_ENABLED", function() Q.CombatEnded() end) end
