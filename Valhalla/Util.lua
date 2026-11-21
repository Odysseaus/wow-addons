--------------------------------------------------------------------------------
-- Util (1.2.26): the small helpers every part used to keep its own copy of. Pure: no frames, no events, so the
-- box tests load it as the game does (after Core.lua, before the rest). Globals are looked up when called.
--
--   U.Time()            the clock's seconds (time()): saved dates, "how long ago"
--   U.Clock()           the game's seconds (GetTime()): timers within a session
--   U.T(), U.MS()       precise seconds / milliseconds (profiling, time budgets)
--   U.Value(v)          v, or nil when it's a secret value (Safe.Value)
--   U.Call(fn, ...)     pcall(fn, ...): its first four results, each plain (nil for a secret), or nil when it errors
--   U.CallAll(fn, ...)  the same, every result
--   U.InCombat()        CombatQueue's gate (combat, the player in combat, secret auras, the settle after combat)
--   U.Defer(key, fn, note)  fn now when the gate is clear, else when it is (ns.Combat.Run; note: one chat line)
--   U.Trim(s)           s as text, without the spaces around it
--   U.ZoneName(id)      a uiMap's name ("?" when unknown)
--   U.Place(id, x, y)   "Zone  12.3, 45.6": a point on a uiMap as the map's tooltips show it
--   U.Round(x, k)       x rounded to 1/k (k: 1 when not given)
--   U.Smooth(x, a, b)   smoothstep 0..1 across a..b (or a = { from, to })
--   U.SetCVar(name, v)  a game setting, errors ignored
--   U.RealmNames()      (1.2.29) the realm as the game names it now: { { name, how } }, none empty or secret,
--                       GetRealmName's first, then GetNormalizedRealmName's, then UnitFullName's; {} while the game
--                       hasn't said (WoW Forever 1.60.1.71037 gives "" at login)
--   U.PlainRealm(r)     a realm as compared: no spaces, hyphens or apostrophes, lower case ("" for none)
--   U.RealmRaw()        (1.2.30) the game's raw answers, as text (U.REALM_RAW's keys): GetRealmName,
--                       GetNormalizedRealmName, UnitFullName("player"), GetRealmID, C_RealmList.GetRealmInfo(id),
--                       GetCurrentRegion ("(no API)", "(error)", "(secret)", strings quoted: "" shows as "")
--------------------------------------------------------------------------------

local _, ns = ...
local U = {}
ns.Util = U

function U.Time() return time and time() or 0 end
function U.Clock() return GetTime and GetTime() or 0 end
function U.T() return (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and debugprofilestop() / 1000) or U.Time() end
function U.MS() return (debugprofilestop and debugprofilestop()) or U.T() * 1000 end

local function Value(v)
	local Safe = ns.Safe
	if Safe and Safe.Value then return Safe.Value(v) end
	return v
end
U.Value = Value

function U.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return nil end
	return Value(a), Value(b), Value(c), Value(d)
end

function U.CallAll(fn, ...)
	if type(fn) ~= "function" then return nil end
	local got = { pcall(fn, ...) }
	if not got[1] then return nil end
	local n = table.maxn(got)
	for i = 2, n do got[i] = Value(got[i]) end
	return unpack(got, 2, n)
end

function U.InCombat()
	local C = ns.Combat
	if C and C.Blocked then return C.Blocked() end
	return InCombatLockdown and InCombatLockdown() and true or false
end

function U.Defer(key, fn, note)
	local C = ns.Combat
	if C and C.Run then return C.Run(key, fn, note and ns.L and ns.L[note] or note) end
	if U.InCombat() then return false end
	fn()
	return true
end

function U.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function U.ZoneName(id)
	local info = id and C_Map.GetMapInfo(id)
	return info and info.name or "?"
end

function U.Place(id, x, y) return ("%s  %.1f, %.1f"):format(U.ZoneName(id), x * 100, y * 100) end

function U.Round(x, k)
	k = k or 1
	return math.floor(x * k + 0.5) / k
end

function U.Smooth(x, a, b)
	if b == nil then a, b = a[1], a[2] end
	local t = math.max(0, math.min(1, (x - a) / (b - a)))
	return t * t * (3 - 2 * t)
end

function U.RealmNames()
	local out, seen = {}, {}
	local function Add(how, r)
		r = Value(r)
		if type(r) == "string" and r ~= "" and not seen[r] then seen[r] = true out[#out + 1] = { name = r, how = how } end
	end
	Add("GetRealmName", U.Call(GetRealmName))
	Add("GetNormalizedRealmName", U.Call(GetNormalizedRealmName))
	Add("UnitFullName", select(2, U.Call(UnitFullName, "player")))
	return out
end

U.REALM_RAW = { "GetRealmName", "GetNormalizedRealmName", "UnitFullName", "GetRealmID", "C_RealmList.GetRealmInfo", "GetCurrentRegion" }
local function Shown(v)
	if v == nil then return "nil" end
	if Value(v) == nil then return "(secret)" end
	if type(v) == "string" then return ("%q"):format(v) end
	if type(v) == "table" then
		local t = {}
		for k, x in pairs(v) do if type(x) ~= "table" and type(x) ~= "function" then t[#t + 1] = tostring(k) .. "=" .. Shown(x) end end
		table.sort(t)
		return "{" .. table.concat(t, ", ") .. "}"
	end
	return tostring(v)
end
function U.RealmRaw()
	local out = {}
	local function Get(key, fn, ...)
		if type(fn) ~= "function" then out[key] = "(no API)" return end
		local got = { pcall(fn, ...) }
		if not got[1] then out[key] = "(error)" return end
		local t = {}
		for i = 2, math.max(2, table.maxn(got)) do t[#t + 1] = Shown(got[i]) end
		out[key] = table.concat(t, ", ")
	end
	Get("GetRealmName", GetRealmName)
	Get("GetNormalizedRealmName", GetNormalizedRealmName)
	Get("UnitFullName", UnitFullName, "player")
	Get("GetRealmID", GetRealmID)
	Get("C_RealmList.GetRealmInfo", C_RealmList and C_RealmList.GetRealmInfo, U.Call(GetRealmID))
	Get("GetCurrentRegion", GetCurrentRegion)
	return out
end

function U.PlainRealm(r) return type(r) == "string" and (r:gsub("[%s%-']", "")):lower() or "" end

function U.SetCVar(name, value)
	if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, value) elseif SetCVar then pcall(SetCVar, name, value) end
end
