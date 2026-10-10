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

local function numericThreat(threatValue, rawPercentage, scaledPercentage)
    if type(threatValue) == "number" then
        return threatValue
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
        raw = numericThreat(threatValue, rawPercentage, scaledPercentage)
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

local function newSim(now)
    local roster = {
        { name = "Tank", class = "WARRIOR", unit = "party1", role = "tank" },
        { name = "Mage", class = "MAGE", unit = "player", role = "dps", isPlayer = true },
        { name = "Warlock", class = "WARLOCK", unit = "party2", role = "dps" },
        { name = "Druid", class = "DRUID", unit = "party3", role = "heal" },
        { name = "Rogue", class = "ROGUE", unit = "party4", role = "dps" },
    }
    local i
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
        m.rate = m.base
    end
    return { start = now, last = now, acc = 0, members = roster }
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

local function collectSample()
    local now = 0
    if type(GetTime) == "function" then
        now = GetTime() or 0
    end
    if not sim or now - sim.start > SIM_RESET or now < sim.last then
        sim = newSim(now)
    end
    local elapsed = now - sim.last
    sim.last = now
    if elapsed > 1 then elapsed = 1 end
    sim.acc = sim.acc + elapsed
    while sim.acc >= SIM_TICK do
        sim.acc = sim.acc - SIM_TICK
        stepSim(SIM_TICK)
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
