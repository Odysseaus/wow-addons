--------------------------------------------------------------------------------
-- CombatQueue (1.2.23): what Valhalla would do to the game's quest tracker, quest log or windows while in
-- combat waits until combat ends (PLAYER_REGEN_ENABLED).
--
-- Why: the game's quest tracker and Edit Mode read a player aura in combat (Blizzard_MawBuffs.lua's
-- ShouldShowMawBuffs, from the tracker's update). In combat, auras are secret, and a read from code an
-- addon touched errors ("Auras cannot be accessed when secret while tainted by 'Valhalla'"). Valhalla's
-- watch, super-track, quest-log header and window calls make the tracker lay out from Valhalla's code,
-- so they are kept out of combat.
--
--   ns.Combat.Run(key, fn, note)   fn() now when out of combat (true); in combat queued under key
--                                   (false): a later Run with the same key replaces it (last write wins,
--                                   moved to the end). note: printed once per combat, when given.
--   ns.Combat.Flush()              runs the queue in order (out of combat); the count run
--   ns.Combat.Pending(key)         queued? (any, with no key)
--------------------------------------------------------------------------------

local ADDON, ns = ...

local Q = { order = {}, ops = {}, said = {} }
ns.Combat = Q

function Q.InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

local function Drop(key)
	for i = #Q.order, 1, -1 do
		if Q.order[i] == key then table.remove(Q.order, i) end
	end
end

function Q.Run(key, fn, note)
	if type(fn) ~= "function" then return false end
	if not Q.InCombat() then fn() return true end
	key = key or fn
	if Q.ops[key] then Drop(key) end
	Q.ops[key] = fn
	Q.order[#Q.order + 1] = key
	if note and not Q.said[note] then
		Q.said[note] = true
		if ns.Print then ns:Print(note) end
	end
	return false
end

function Q.Pending(key)
	if key == nil then return #Q.order > 0 end
	return Q.ops[key] ~= nil
end

function Q.Flush()
	if Q.InCombat() then return 0 end
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

if ns.RegisterEvent then ns.RegisterEvent(Q, "PLAYER_REGEN_ENABLED", function() Q.Flush() end) end
