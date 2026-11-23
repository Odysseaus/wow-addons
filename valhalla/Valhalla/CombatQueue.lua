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
-- The gate (Q.Blocked): InCombatLockdown(), or UnitAffectingCombat("player"), or C_Secrets.ShouldAurasBeSecret()
-- (1.2.25: aura reads would be secret now; 1.2.24 asked HasSecretRestrictions, which only says the client build has
-- secrets at all - always true on Forever - and held everything for good), or the settle after combat (SETTLE
-- seconds from PLAYER_REGEN_ENABLED). A secret answer counts as blocked.
-- (1.2.25) the safety net: held only by "secret auras" (no combat, no settle) for SAFETY seconds, the gate opens
-- anyway (one chat line a session), until that hold ends; so nothing waits for good out of combat.
-- (1.2.35) a level-up holds the gate for LEVEL seconds (PLAYER_LEVEL_UP). The game lays Edit Mode out then and
-- reads auras from the tracker's anchor callback; watch, super-track and quest-log changes wait, then flush.
-- Each level-up, and every queued call that actually runs, is appended to ValhallaDB.taintLog (LOG_MAX lines).
--
--   ns.Combat.Run(key, fn, note)   fn() now when clear and nothing queued (true); else queued under key (false):
--                                   a later Run with the same key replaces it (last write wins, moved to the end).
--                                   note: printed once per wait, when given.
--   ns.Combat.Flush()              runs the queue in order when clear (else 0, checked again later); the count run
--   ns.Combat.Pending(key)         queued? (any, with no key)
--   ns.Combat.Blocked()            the gate now; ns.Combat.Why(): its reasons ({} when clear)
--   ns.Combat.Cancel(key)          a queued key dropped
--   ns.Combat.History()            (1.2.25) the last HISTORY calls run: { at = GetTime(), clock = "hh:mm:ss",
--                                   key, how = "now" | "queued" }; /valhalla combat prints them
-- After PLAYER_REGEN_ENABLED the queue waits SETTLE seconds, then runs only if the gate is clear; if not, it's
-- checked again every SETTLE seconds (out of combat lockdown; in it, the next PLAYER_REGEN_ENABLED starts again).
--------------------------------------------------------------------------------
local ADDON, ns = ...

local Q = { order = {}, ops = {}, said = {}, settleUntil = 0, timer = false }
ns.Combat = Q
Q.SETTLE = 3
Q.SAFETY = 30
Q.LEVEL = 2            -- (1.2.35) seconds the gate stays shut after PLAYER_LEVEL_UP
Q.HISTORY = 40
Q.LOG_MAX = 40         -- (1.2.35) ValhallaDB.taintLog, oldest dropped
Q.levelUntil = 0
Q.SAFETY_NOTE = "The game is keeping auras secret out of combat: Valhalla's waiting quest tracker changes go ahead after 30 seconds."
Q.history = {}
Q.secretSince = nil     -- (when the hold by secret auras alone began)
Q.released = false      -- (that hold has passed SAFETY seconds: the gate is open until it ends)
Q.warned = false

local Now = ns.Util.Clock
-- a yes/no from the game: a secret answer counts as yes (blocked); a failing call as failed (1.2.26: the combat
-- checks pass false, so a broken one never holds for good; the secret auras check passes true, held as secret:
-- the safety net below still opens it after SAFETY seconds)
local function Yes(fn, failed, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	if not ok then return failed and true or false end
	if issecretvalue and issecretvalue(v) then return true end
	return v and true or false
end

function Q.InCombat() return Yes(InCombatLockdown, false) end
function Q.Why()
	local t = {}
	if Yes(InCombatLockdown, false) then t[#t + 1] = "combat" end
	if Yes(UnitAffectingCombat, false, "player") and #t == 0 then t[#t + 1] = "combat (unit)" end
	local CS = rawget(_G, "C_Secrets")
	if type(CS) == "table" and Yes(CS.ShouldAurasBeSecret, true) then t[#t + 1] = "secret auras" end
	if Now() < (Q.settleUntil or 0) then t[#t + 1] = "settling after combat" end
	if Now() < (Q.levelUntil or 0) then t[#t + 1] = "level-up" end   -- (1.2.35)
	return t
end
-- the gate, with the safety net: secret auras alone (out of combat, settled) hold for SAFETY seconds at most
function Q.Blocked()
	local why = Q.Why()
	if #why == 1 and why[1] == "secret auras" then
		local now = Now()
		if not Q.secretSince then Q.secretSince = now end
		if Q.released or now - Q.secretSince >= Q.SAFETY then
			if not Q.released then
				Q.released = true
				if not Q.warned then
					Q.warned = true
					if ns.Print then ns:Print(ns.L and ns.L[Q.SAFETY_NOTE] or Q.SAFETY_NOTE) end
				end
			end
			return false
		end
		return true
	end
	Q.secretSince, Q.released = nil, false
	return #why > 0
end

-- (1.2.35) one line in ValhallaDB.taintLog. Numbers here are finite, so Core's logout scrub keeps the log
-- and only removes a NaN beside it. No table yet (before ADDON_LOADED): nothing saved.
local function AurasSecret()
	local CS = rawget(_G, "C_Secrets")
	return type(CS) == "table" and Yes(CS.ShouldAurasBeSecret, true) or false
end
function Q.Trace(key, how, extra)
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local log = db.taintLog
	if type(log) ~= "table" then log = {} db.taintLog = log end
	local why = Q.Why()
	local e = {
		t = Now(), clock = date and date("%H:%M:%S") or "",
		key = tostring(key), how = how, why = why,
		combat = Q.InCombat() and true or false, secret = AurasSecret() and true or false,
	}
	if type(extra) == "table" then
		for k, v in pairs(extra) do e[k] = v end
	end
	log[#log + 1] = e
	while #log > Q.LOG_MAX do table.remove(log, 1) end
end
local function Record(key, how)
	local h = Q.history
	h[#h + 1] = { at = Now(), clock = date and date("%H:%M:%S") or "", key = tostring(key), how = how }
	while #h > Q.HISTORY do table.remove(h, 1) end
	Q.Trace(key, how)
end
function Q.History() return Q.history end
-- /valhalla combat: the gate now, what waits, and the last calls run
function Q.Report()
	local out = {}
	local why = Q.Why()
	out[#out + 1] = ("Combat queue: %s; %d waiting%s"):format(#why > 0 and ("held (" .. table.concat(why, ", ") .. ")") or "clear",
		#Q.order, Q.released and "; safety net open (secret auras over " .. Q.SAFETY .. " s)" or "")
	if #Q.order > 0 then out[#out + 1] = "  waiting: " .. table.concat(Q.order, ", ") end
	local h = Q.history
	if #h == 0 then out[#out + 1] = "  nothing run yet"
	else
		out[#out + 1] = ("  last %d run (oldest first):"):format(#h)
		for _, e in ipairs(h) do out[#out + 1] = ("  %s  %s  (%s)"):format(e.clock, e.key, e.how) end
	end
	return out
end

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
	if Q.Blocked() then
		-- (a timed hold: look again when it ends, not a fresh SETTLE later)
		local now, left = Now(), 0
		if now < (Q.levelUntil or 0) then left = Q.levelUntil - now end
		if now < (Q.settleUntil or 0) then left = math.max(left, Q.settleUntil - now) end
		Schedule(left > 0 and left or nil)
		return
	end
	Q.Flush()
end
Q.Tick = Tick

function Q.Run(key, fn, note)
	if type(fn) ~= "function" then return false end
	key = key or fn
	if not Q.Blocked() and #Q.order == 0 then Record(key, "now") fn() return true end
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
			Record(key, "queued")
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
-- (1.2.35) level-up: the gate shuts for LEVEL seconds, then whatever waited (watch, super-track, quest log) flushes
function Q.LevelUp(level)
	local extra
	if type(level) == "number" and level == level and level < math.huge and level > -math.huge then extra = { level = level } end
	Q.Trace("PLAYER_LEVEL_UP", "level-up", extra)
	Q.levelUntil = Now() + Q.LEVEL
	if not Q.InCombat() then Schedule(Q.LEVEL) end
end
if ns.RegisterEvent then
	ns.RegisterEvent(Q, "PLAYER_REGEN_ENABLED", function() Q.CombatEnded() end)
	ns.RegisterEvent(Q, "PLAYER_LEVEL_UP", function(_, _, level) Q.LevelUp(level) end)
end
