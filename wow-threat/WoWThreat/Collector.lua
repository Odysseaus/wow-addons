-- WoWThreat threat collector (WoW Classic, Lua 5.1).
-- Core.lua has already run: local _, NS = ... and WoWThreat = NS.
local _, NS = ...

-- issecretvalue is the documented tainted-safe test; == on a secret string throws.
local function valueIsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function sortEntries(entries)
    local i
    for i = 1, #entries do
        if entries[i].order == nil then
            entries[i].order = i
        end
    end
    table.sort(entries, function(a, b)
        local av = a.value or 0
        local bv = b.value or 0
        if av ~= bv then
            return av > bv
        end
        local ap = a.pct or 0
        local bp = b.pct or 0
        if ap ~= bp then
            return ap > bp
        end
        local ao = a.order or 0
        local bo = b.order or 0
        if ao ~= bo then
            return ao < bo
        end
        return (a.name or "") < (b.name or "")
    end)
end

-- Holder (isTanking or status == 3) is 100%. Everyone else is raw/holder*100,
-- so a player pulling ahead of the holder reports over 100. With no holder,
-- the highest raw value is treated as 100.
local function applyRelativeScale(entries)
    local holderRaw = nil
    local topRaw = 0
    local i
    for i = 1, #entries do
        local raw = entries[i].raw or 0
        if raw > topRaw then
            topRaw = raw
        end
        if holderRaw == nil and (entries[i].isTanking or entries[i].status == 3) then
            holderRaw = raw
        end
    end

    local base = holderRaw
    if base == nil or base <= 0 then
        base = topRaw
    end

    for i = 1, #entries do
        local e = entries[i]
        local raw = e.raw or 0
        if base > 0 then
            e.pct = (raw / base) * 100
        else
            e.pct = 0
        end
        e.value = raw
    end

    sortEntries(entries)
    return entries
end

function NS.HasThreatAPI()
    return type(UnitDetailedThreatSituation) == "function"
end

local function useSample()
    if NS.forceTest then
        return true
    end
    if NS.apiMissing then
        return true
    end
    return not NS.HasThreatAPI()
end

local function targetIsHostile()
    if not UnitExists("target") then
        return false
    end
    if UnitCanAttack("player", "target") then
        return true
    end
    return false
end

-- GUID token first, unit token "target" when the GUID call yields nothing.
local function queryThreat(unit, mobToken)
    -- Secret GUID/token: UnitIsUnit and ~= are illegal here (AllowedWhenUntainted); query the plain "target" token.
    if valueIsSecret(mobToken) then
        mobToken = "target"
    end
    local isTanking, status, scaledPercentage, rawPercentage, threatValue =
        UnitDetailedThreatSituation(unit, mobToken)
    local empty = isTanking == nil and status == nil and scaledPercentage == nil
        and rawPercentage == nil and threatValue == nil
    if empty and mobToken ~= "target" then
        isTanking, status, scaledPercentage, rawPercentage, threatValue =
            UnitDetailedThreatSituation(unit, "target")
    end
    return isTanking, status, scaledPercentage, rawPercentage, threatValue
end

-- threatValue scale. Retail and Classic document threatValue as raw x100.
-- Auto mode divides by 100, unless a holder (rawPct >= 100) reports a value
-- under 100, which means this client returns unscaled raw threat.
-- WoWThreatDB.threatScale = "auto" | 1 | 100 overrides.
local scaleSeen = nil
local debugPrinted = {}

local function threatDivisor(threatValue, rawPercentage)
    local setting = NS.db and NS.db.threatScale
    if setting == 1 or setting == 100 then
        return setting
    end
    if scaleSeen then
        return scaleSeen
    end
    if type(threatValue) == "number" and type(rawPercentage) == "number"
        and rawPercentage >= 100 and threatValue > 0 then
        if threatValue < 100 then
            scaleSeen = 1
        else
            scaleSeen = 100
        end
        return scaleSeen
    end
    return 100
end

function NS.ResetThreatDebug()
    debugPrinted = {}
    scaleSeen = nil
end

local function numericThreat(threatValue, rawPercentage, scaledPercentage, unit)
    if valueIsSecret(threatValue) then threatValue = nil end
    if valueIsSecret(rawPercentage) then rawPercentage = nil end
    if valueIsSecret(scaledPercentage) then scaledPercentage = nil end
    if type(threatValue) == "number" then
        local div = threatDivisor(threatValue, rawPercentage)
        if NS.debug and unit and not debugPrinted[unit] and threatValue > 0 then
            debugPrinted[unit] = true
            print(string.format("|cffd4af37WoW Threat|r debug %s threatValue=%s rawPct=%s scaledPct=%s divisor=%d -> %.1f",
                tostring(unit), tostring(threatValue), tostring(rawPercentage), tostring(scaledPercentage), div, threatValue / div))
        end
        return threatValue / div
    end
    if type(rawPercentage) == "number" then
        return rawPercentage
    end
    if type(scaledPercentage) == "number" then
        return scaledPercentage
    end
    return 0
end

local function pushLive(entries, seen, unit, mobToken)
    if not UnitExists(unit) then
        return
    end
    local guid = UnitGUID(unit)
    -- Secret GUIDs cannot be table keys; group GUIDs are not secret, so dedupe is unchanged.
    if guid and not valueIsSecret(guid) then
        if seen[guid] then
            return
        end
        seen[guid] = true
    elseif valueIsSecret(guid) then
        guid = nil
    end

    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    local isTanking, status = false, 0
    local raw = 0
    if mobToken then
        local scaledPercentage, rawPercentage, threatValue
        isTanking, status, scaledPercentage, rawPercentage, threatValue =
            queryThreat(unit, mobToken)
        raw = numericThreat(threatValue, rawPercentage, scaledPercentage, unit)
    end

    local samePlayer = UnitIsUnit(unit, "player")
    local isPlayer = false
    -- Return may be a secret boolean (SecretWhenUnitComparisonRestricted); do not boolean-test it.
    if not valueIsSecret(samePlayer) then
        isPlayer = samePlayer and true or false
    end

    entries[#entries + 1] = {
        unit = unit,
        name = name or unit,
        class = class or "UNKNOWN",
        guid = guid,
        isTanking = isTanking and true or false,
        status = status or 0,
        pct = 0,
        raw = raw,
        value = raw,
        isPlayer = isPlayer,
    }
end

-- Raid: raid1..raidN. Party: player plus party1..partyN. Solo: player.
-- Missing unit tokens are skipped by pushLive.
local function groupUnitTokens()
    local units = {}
    local n = 0
    if type(GetNumGroupMembers) == "function" then
        n = GetNumGroupMembers() or 0
    end
    local i
    if type(IsInRaid) == "function" and IsInRaid() then
        for i = 1, n do
            units[#units + 1] = "raid" .. i
        end
    elseif type(IsInGroup) == "function" and IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, n do
            units[#units + 1] = "party" .. i
        end
    else
        units[#units + 1] = "player"
    end
    return units
end

local function collectLive()
    local mobToken = nil
    if targetIsHostile() then
        mobToken = UnitGUID("target")
        -- Secret target GUID: skip == (tainted compare throws); UnitIsUnit cannot accept a secret token either.
        if valueIsSecret(mobToken) or not mobToken or mobToken == "" then
            mobToken = "target"
        end
    end

    local entries = {}
    local seen = {}
    local units = groupUnitTokens()
    local i
    for i = 1, #units do
        pushLive(entries, seen, units[i], mobToken)
    end
    if #entries == 0 then
        pushLive(entries, seen, "player", mobToken)
    end

    return applyRelativeScale(entries)
end

-- Test roster sim (modeled on the previewer): each fake player has a rate
-- that drifts, plus occasional bursts. Ticks about every 0.1 s.
local SIM_TICK = 0.1
local SIM_RESET = 90
local sim = nil

local function rnd(a, b)
    return a + math.random() * (b - a)
end

local SIM_NAMES = {
    "Aldric", "Brynja-Faerlina", "Caelum", "Dorrin", "Elowen", "Fenwick", "Garrik", "Hesper",
    "Isolde", "Jorund", "Kaelith", "Lirael", "Maelis", "Norric", "Orwen", "Perrin", "Quilla",
    "Rhydian", "Tamsin", "Ulric", "Vesna", "Wystan", "Yrsa", "Zephyrine", "Ansel", "Brannoc",
    "Cressida", "Dagny", "Eamon", "Faelan", "Gwendolyn", "Halvard", "Ingrith", "Joren",
    "Kestrel", "Leofric", "Mirelle", "Nyssa", "Osric",
}
NS.LONG_TEST_NAME = "Seraphinavellewyndmoorthalias"
local DPS = { "ROGUE", "MAGE", "WARLOCK", "HUNTER", "WARRIOR", "SHAMAN", "DRUID", "PALADIN" }
local HEAL = { "PRIEST", "DRUID", "SHAMAN", "PALADIN" }

local function newSim(now, n)
    n = n or 5
    local nTank = (n >= 10) and 2 or 1
    local nHeal = math.max(1, math.floor(n / 5 + 0.5))
    local roster = {}
    local i
    for i = 1, n do
        local m = { unit = "party" .. i }
        if i == n then
            m.name, m.class, m.role, m.isPlayer, m.unit = "You", "MAGE", "dps", true, "player"
        else
            if i == 2 then
                m.name = NS.LONG_TEST_NAME
            else
                m.name = SIM_NAMES[((i - 1) % #SIM_NAMES) + 1]
            end
            if i <= nTank then
                m.role, m.class = "tank", (i % 2 == 0) and "PALADIN" or "WARRIOR"
            elseif i <= nTank + nHeal then
                m.role, m.class = "heal", HEAL[(i % #HEAL) + 1]
            else
                m.role, m.class = "dps", DPS[((i * 3) % #DPS) + 1]
            end
        end
        roster[i] = m
    end
    for i = 1, #roster do
        local m = roster[i]
        m.guid = "Player-Sample-" .. i
        m.threat = 0
        if m.role == "tank" then
            m.base = rnd(1300, 1700)
        elseif m.role == "heal" then
            m.base = rnd(250, 420)
        else
            m.base = rnd(700, 1250)
        end
        if m.isPlayer and n > 10 then
            m.base = rnd(150, 250) -- low threat so the pinned row shows in raids
        end
        m.rate = m.base
    end
    return { start = now, last = now, acc = 0, members = roster, n = n }
end

local function stepSim(dt)
    local i
    for i = 1, #sim.members do
        local m = sim.members[i]
        -- Rate random-walks around its base and is pulled back toward it.
        m.rate = m.rate + (m.base - m.rate) * 0.05 + rnd(-0.08, 0.08) * m.base
        if m.rate < m.base * 0.3 then m.rate = m.base * 0.3 end
        if m.rate > m.base * 2.2 then m.rate = m.base * 2.2 end
        local gain = m.rate * dt
        if m.role ~= "heal" and math.random() < 0.02 then
            gain = gain + m.base * rnd(0.6, 1.8) -- crit / big spell burst
        end
        m.threat = m.threat + gain
    end
end

-- /wtm test swap: every NS.testSwapEvery seconds the runner-up jumps just
-- past the leader, forcing a leader change (0.2 s = rapid back-and-forth).
local function forceSwap()
    local first, second = nil, nil
    local i
    for i = 1, #sim.members do
        local m = sim.members[i]
        if not first or m.threat > first.threat then
            second = first
            first = m
        elseif not second or m.threat > second.threat then
            second = m
        end
    end
    if first and second then
        second.threat = first.threat * 1.12 + 50
    end
end

local function collectSample()
    local now = 0
    if type(GetTime) == "function" then
        now = GetTime() or 0
    end
    local size = NS.testSize or 5
    if not sim or sim.n ~= size or now - sim.start > SIM_RESET or now < sim.last then
        sim = newSim(now, size)
    end
    local elapsed = now - sim.last
    sim.last = now
    if elapsed > 1 then elapsed = 1 end
    sim.acc = sim.acc + elapsed
    while sim.acc >= SIM_TICK do
        sim.acc = sim.acc - SIM_TICK
        stepSim(SIM_TICK)
        if NS.testSwapEvery then
            sim.swapAcc = (sim.swapAcc or 0) + SIM_TICK
            if sim.swapAcc >= NS.testSwapEvery - 1e-6 then
                sim.swapAcc = 0
                forceSwap()
            end
        end
    end

    local top = 0
    local i
    for i = 1, #sim.members do
        if sim.members[i].threat > top then top = sim.members[i].threat end
    end
    local entries = {}
    for i = 1, #sim.members do
        local m = sim.members[i]
        local pct = 0
        if top > 0 then pct = m.threat / top * 100 end
        entries[#entries + 1] = {
            unit = m.unit, name = m.name, class = m.class, guid = m.guid,
            isTanking = m.threat >= top and top > 0, status = (m.threat >= top) and 3 or 1,
            pct = pct, raw = m.threat, value = m.threat, isPlayer = m.isPlayer and true or false,
        }
    end
    sortEntries(entries)
    return entries
end

function NS.ResetSample()
    sim = nil
end

-- Sample names (Tank, Mage, ...) are only the /wtm test and missing-API path.
-- Bars and plates otherwise always get the real group, target or not.
function NS.CollectThreat()
    if useSample() then
        return collectSample()
    end
    return collectLive()
end

function NS.GetPlayerThreatPercent(entries)
    if type(entries) ~= "table" then
        entries = NS.CollectThreat()
    end
    local i
    for i = 1, #entries do
        local e = entries[i]
        if e.isPlayer or e.unit == "player" then
            return e.pct or 0
        end
    end
    return 0
end

-- Event driver: mark dirty on threat/target/roster/combat events. Meter.lua
-- refreshes with a 0.2 s throttle plus a 0.5 s safety poll.
NS.dirty = true
NS.inCombat = false
local drv = CreateFrame("Frame")
local EVENTS = {
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED",
    "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD",
}
local i
for i = 1, #EVENTS do
    pcall(drv.RegisterEvent, drv, EVENTS[i])
end
drv:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        NS.inCombat = true
        NS.ResetThreatDebug()
        if NS.OnCombatStart then NS.OnCombatStart() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        NS.inCombat = false
        if NS.OnCombatEnd then NS.OnCombatEnd() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        NS.inCombat = type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") and true or false
    elseif event == "PLAYER_TARGET_CHANGED" then
        NS.ResetThreatDebug()
    end
    NS.dirty = true
end)
