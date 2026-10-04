-- WoWThreat threat collector (WoW Classic, Lua 5.1).
-- Core.lua has already run: local _, NS = ... and WoWThreat = NS.
local _, NS = ...

local SAMPLE_TANK_RAW = 10000

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
    if guid then
        if seen[guid] then
            return
        end
        seen[guid] = true
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
        isPlayer = UnitIsUnit(unit, "player") and true or false,
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
        if not mobToken or mobToken == "" then
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

local function osc(t, speed, phase, lo, hi)
    local s = math.sin(t * speed + phase)
    local u = (s + 1) * 0.5
    return lo + (hi - lo) * u
end

local function collectSample()
    local t = 0
    if type(GetTime) == "function" then
        t = GetTime() or 0
    end

    local tankRaw = SAMPLE_TANK_RAW
    local mageRaw = math.floor(osc(t, 0.55, 0.40, 3500, 14500) + 0.5)
    local lockRaw = math.floor(osc(t, 0.37, 1.70, 2800, 11800) + 0.5)
    local druidRaw = math.floor(osc(t, 0.42, 2.80, 4200, 9800) + 0.5)
    local rogueRaw = math.floor(osc(t, 0.63, 4.10, 1800, 13200) + 0.5)

    local function offStatus(raw)
        if raw > tankRaw then
            return 2
        end
        return 1
    end

    local entries = {
        {
            unit = "party1",
            name = "Tank",
            class = "WARRIOR",
            guid = "Player-Sample-1",
            isTanking = true,
            status = 3,
            pct = 0,
            raw = tankRaw,
            value = tankRaw,
            isPlayer = false,
        },
        {
            unit = "player",
            name = "Mage",
            class = "MAGE",
            guid = "Player-Sample-2",
            isTanking = false,
            status = offStatus(mageRaw),
            pct = 0,
            raw = mageRaw,
            value = mageRaw,
            isPlayer = true,
        },
        {
            unit = "party2",
            name = "Warlock",
            class = "WARLOCK",
            guid = "Player-Sample-3",
            isTanking = false,
            status = offStatus(lockRaw),
            pct = 0,
            raw = lockRaw,
            value = lockRaw,
            isPlayer = false,
        },
        {
            unit = "party3",
            name = "Druid",
            class = "DRUID",
            guid = "Player-Sample-4",
            isTanking = false,
            status = offStatus(druidRaw),
            pct = 0,
            raw = druidRaw,
            value = druidRaw,
            isPlayer = false,
        },
        {
            unit = "party4",
            name = "Rogue",
            class = "ROGUE",
            guid = "Player-Sample-5",
            isTanking = false,
            status = offStatus(rogueRaw),
            pct = 0,
            raw = rogueRaw,
            value = rogueRaw,
            isPlayer = false,
        },
    }

    return applyRelativeScale(entries)
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
