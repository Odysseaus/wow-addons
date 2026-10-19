-- /dm probe (0.0.3): find out what this client really offers, without guessing.
-- Every call is pcall-wrapped and its raw return types are saved in
-- DarkMatterDB.probe.calls. Values are never compared or concatenated before an
-- issecretvalue() check. The window shows a one-line-per-area summary; the full
-- raw list is in SavedVariables (and in the window with /dm raw).
-- Read-only apart from the stock Encounter Journal selection calls (restored).
local _, NS = ...

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function IsSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end
local function Num(v) if not IsSecret(v) and type(v) == "number" then return v end end
local function Str(v) if not IsSecret(v) and type(v) == "string" then return v end end
local function Tbl(v) if not IsSecret(v) and type(v) == "table" then return v end end

local function Trunc(s, n)
  s = tostring(s)
  if #s > n then return string.sub(s, 1, n) .. "..." end
  return s
end

local function Pack(...) return { n = select("#", ...), ... } end

local function Resolve(path)
  local v = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
    if v == nil then return nil end
  end
  return v
end

local function Count(t)
  t = Tbl(t)
  if not t then return nil end
  local ok, n = pcall(function()
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
  end)
  return ok and n or nil
end

-- Raw description of one value: "number:171", "string:Fishing", "table{id,name}#2".
local function Describe(v)
  local ok, d = pcall(function()
    if IsSecret(v) then return "secret" end
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "number" or t == "boolean" then return t .. ":" .. tostring(v) end
    if t == "string" then return "string:" .. Trunc(v, 48) end
    if t == "table" then
      local keys, n = {}, 0
      for k in pairs(v) do
        n = n + 1
        if n <= 12 and not IsSecret(k) then keys[#keys + 1] = tostring(k) end
      end
      table.sort(keys)
      return "table{" .. table.concat(keys, ",") .. (n > 12 and ",..." or "") .. "}#" .. n
    end
    return t
  end)
  return ok and d or "error"
end

---------------------------------------------------------------------------
-- probe context: Call records, areas record one summary line each
---------------------------------------------------------------------------
local AREA_ORDER = { "quests", "fishing", "achievements", "journalApi", "journal", "map", "lfg",
  "saved", "items", "loot", "rules" }
local AREA_TITLE = {
  quests = "Quests", fishing = "Fishing", achievements = "Achievements",
  journalApi = "Journal API", journal = "Journal data (no UI)", map = "Map discovery",
  lfg = "LFG / dungeons", saved = "Saved instances", items = "Items on demand",
  loot = "Loot learning", rules = "Game rules",
}

local function NewContext(out)
  local c = { out = out }
  local calls, order = out.calls, out.callOrder

  -- Record one call (first time per name only). Returns the packed pcall result.
  function c.call(name, fn, ...)
    local rec = { ok = false }
    local r
    if type(fn) ~= "function" then
      rec.err = "missing"
      r = { n = 1, false }
    else
      r = Pack(pcall(fn, ...))
      rec.ok = r[1] and true or false
      if r[1] then
        rec.n = r.n - 1
        rec.ret = {}
        for i = 2, r.n do rec.ret[i - 1] = Describe(r[i]) end
      else
        rec.err = Trunc(r[2], 80)
      end
    end
    if not calls[name] then calls[name] = rec order[#order + 1] = name end
    return r
  end

  function c.quiet(fn, ...)
    if type(fn) ~= "function" then return { n = 1, false } end
    return Pack(pcall(fn, ...))
  end

  -- Presence of a list of dotted names; returns have, total, missing list.
  function c.presence(names)
    local have, missing = 0, {}
    for _, name in ipairs(names) do
      local v = Resolve(name)
      out.apis[name] = v ~= nil
      out.types[name] = type(v)
      if v ~= nil then have = have + 1 else missing[#missing + 1] = name end
    end
    return have, #names, missing
  end

  function c.line(key, status, text)
    out.areas[key] = { status = status, text = text }
  end

  -- OK when something came back, EMPTY when callable but nothing, MISSING when absent.
  function c.status(present, n)
    if not present then return "MISSING" end
    if n and n > 0 then return "OK" end
    return "EMPTY"
  end
  return c
end

---------------------------------------------------------------------------
-- areas
---------------------------------------------------------------------------
local function AreaQuests(c)
  local d = {}
  c.out.data.quests = d
  local QL = C_QuestLog
  local present = QL and QL.GetNumQuestLogEntries
  if present then
    local r = c.call("C_QuestLog.GetNumQuestLogEntries", QL.GetNumQuestLogEntries)
    d.entries, d.quests = Num(r[2]), Num(r[3])
  end
  if QL and QL.GetInfo then
    local t = Tbl(c.call("C_QuestLog.GetInfo(1)", QL.GetInfo, 1)[2])
    if t then d.info1 = { title = Describe(t.title), questID = Describe(t.questID) } end
  end
  c.line("quests", c.status(present, d.entries),
    string.format("entries=%s quests=%s via C_QuestLog.GetNumQuestLogEntries", tostring(d.entries), tostring(d.quests)))
end

local function AreaFishing(c)
  local d = {}
  c.out.data.fishing = d
  local present = GetProfessions and GetProfessionInfo
  if present then
    local r = c.call("GetProfessions", GetProfessions)
    local fish = r[5]
    if Num(fish) then
      local p = c.call("GetProfessionInfo(fishingIndex)", GetProfessionInfo, fish)
      if Str(p[2]) and Num(p[4]) and Num(p[5]) then
        d.name, d.rank, d.max = p[2], p[4], p[5]
      end
    end
  end
  c.line("fishing", c.status(present, d.rank and 1 or 0),
    d.rank and string.format("%s %s/%s via GetProfessionInfo(select(4, GetProfessions()))", d.name, tostring(d.rank), tostring(d.max))
      or "fishing skill not found")
end

local function AreaAchievements(c)
  local d = {}
  c.out.data.achievements = d
  local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  c.call("LoadAddOn:Blizzard_AchievementUI", loader, "Blizzard_AchievementUI")
  local present = GetTotalAchievementPoints and GetCategoryList and GetAchievementInfo
  if GetTotalAchievementPoints then d.points = Num(c.call("GetTotalAchievementPoints", GetTotalAchievementPoints)[2]) end
  if GetCategoryList then
    local cats = Tbl(c.call("GetCategoryList", GetCategoryList)[2])
    d.categories = cats and #cats or nil
  end
  c.line("achievements", c.status(present, d.categories),
    string.format("points=%s categories=%s frame=%s", tostring(d.points), tostring(d.categories),
      AchievementFrame and "yes" or "no"))
end

local EJ_NAMES = { "EJ_GetNumTiers", "EJ_GetCurrentTier", "EJ_GetTierInfo", "EJ_SelectTier",
  "EJ_GetInstanceByIndex", "EJ_GetInstanceInfo", "EJ_SelectInstance", "EJ_GetEncounterInfoByIndex",
  "EJ_GetEncounterInfo", "EJ_SelectEncounter", "EJ_GetNumLoot", "EJ_GetInstanceForMap",
  "EJ_InstanceIsRaid", "EJ_GetCreatureInfo", "EJ_SetDifficulty" }
local CEJ_NAMES = { "C_EncounterJournal.InitalizeSelectedTier", "C_EncounterJournal.OnOpen",
  "C_EncounterJournal.OnClose", "C_EncounterJournal.GetLootInfoByIndex", "C_EncounterJournal.GetLootInfo",
  "C_EncounterJournal.InstanceHasLoot", "C_EncounterJournal.GetInstanceForGameMap",
  "C_EncounterJournal.GetEncountersOnMap", "C_EncounterJournal.GetDungeonEntrancesForMap",
  "C_EncounterJournal.GetSectionInfo", "C_EncounterJournal.IsEncounterComplete" }
-- Retail journal instance IDs of well-known classic dungeons/raids, plus a bogus control (1).
local SAMPLE_INSTANCES = { 63, 228, 741, 1 }

local function AreaJournal(c)
  local out = c.out
  local d = { tiers = {}, sampleResolved = 0 }
  out.data.journal = d
  local eh, et, em = c.presence(EJ_NAMES)
  local ch, ct, cm = c.presence(CEJ_NAMES)
  local missing = {}
  for _, n in ipairs(em) do missing[#missing + 1] = n end
  for _, n in ipairs(cm) do missing[#missing + 1] = n end
  c.line("journalApi", (#missing == 0) and "OK" or "MISSING",
    string.format("EJ_* %d/%d, C_EncounterJournal %d/%d%s  (frame EncounterJournal: %s)", eh, et, ch, ct,
      #missing > 0 and ("  missing: " .. table.concat(missing, ", ")) or "", EncounterJournal and "yes" or "no"))

  local CEJ = C_EncounterJournal or {}
  if C_EncounterJournal then
    c.call("C_EncounterJournal.InitalizeSelectedTier", CEJ.InitalizeSelectedTier)
    c.call("C_EncounterJournal.OnOpen", CEJ.OnOpen)
  end

  local nt = 0
  local cur
  if EJ_GetNumTiers then nt = Num(c.call("EJ_GetNumTiers", EJ_GetNumTiers)[2]) or 0 end
  if EJ_GetCurrentTier then cur = Num(c.call("EJ_GetCurrentTier", EJ_GetCurrentTier)[2]) end
  if EJ_GetTierInfo then c.call("EJ_GetTierInfo(1)", EJ_GetTierInfo, 1) end
  d.numTiers = nt

  local firstInstance
  local function CountInstances(isRaid)
    local n, first = 0, nil
    for i = 1, 80 do
      local r = c.quiet(EJ_GetInstanceByIndex, i, isRaid)
      if not r[1] or r[2] == nil or IsSecret(r[2]) then break end
      if i == 1 then
        c.call("EJ_GetInstanceByIndex(1," .. tostring(isRaid) .. ")", EJ_GetInstanceByIndex, 1, isRaid)
        first = { id = Num(r[2]), name = Str(r[3]) }
      end
      n = n + 1
    end
    return n, first
  end
  d.dungeons, d.raids = 0, 0
  if EJ_GetInstanceByIndex then
    local dn, df = CountInstances(false)
    local rn, rf = CountInstances(true)
    d.noTierDungeons, d.noTierRaids = dn, rn
    d.dungeons, d.raids = dn, rn
    firstInstance = df or rf
    for tier = 1, math.min(nt, 12) do
      if EJ_SelectTier then c.call("EJ_SelectTier(" .. tier .. ")", EJ_SelectTier, tier) end
      local tn = EJ_GetTierInfo and Str(c.quiet(EJ_GetTierInfo, tier)[2]) or nil
      local a, af = CountInstances(false)
      local b, bf = CountInstances(true)
      d.tiers[#d.tiers + 1] = { tier = tier, name = tn, dungeons = a, raids = b }
      d.dungeons, d.raids = d.dungeons + a, d.raids + b
      firstInstance = firstInstance or af or bf
    end
    if cur and EJ_SelectTier then pcall(EJ_SelectTier, cur) end
  end

  -- Known IDs, straight to EJ_GetInstanceInfo (no tier needed).
  local sampleId
  for _, id in ipairs(SAMPLE_INSTANCES) do
    if EJ_GetInstanceInfo then
      local r = c.call("EJ_GetInstanceInfo(" .. id .. ")", EJ_GetInstanceInfo, id)
      if Str(r[2]) then
        d.sampleResolved = d.sampleResolved + 1
        sampleId = sampleId or id
      end
    end
  end
  local inst = firstInstance and firstInstance.id or sampleId
  d.sampleInstance = inst
  if inst then
    if EJ_SelectInstance then c.call("EJ_SelectInstance", EJ_SelectInstance, inst) end
    if CEJ.InstanceHasLoot then c.call("C_EncounterJournal.InstanceHasLoot", CEJ.InstanceHasLoot, inst) end
    local bosses, enc = 0, nil
    if EJ_GetEncounterInfoByIndex then
      for i = 1, 40 do
        local r = c.quiet(EJ_GetEncounterInfoByIndex, i, inst)
        if not r[1] or r[2] == nil or IsSecret(r[2]) then break end
        if i == 1 then
          c.call("EJ_GetEncounterInfoByIndex(1)", EJ_GetEncounterInfoByIndex, 1, inst)
          enc = Num(r[4])
        end
        bosses = bosses + 1
      end
    end
    d.bosses = bosses
    if enc then
      if EJ_GetEncounterInfo then c.call("EJ_GetEncounterInfo", EJ_GetEncounterInfo, enc) end
      if EJ_SelectEncounter then c.call("EJ_SelectEncounter", EJ_SelectEncounter, enc) end
      if EJ_GetNumLoot then d.numLoot = Num(c.call("EJ_GetNumLoot", EJ_GetNumLoot)[2]) end
      -- Fixed in 0.0.3: the loot-by-index call lives in C_EncounterJournal on this client.
      if CEJ.GetLootInfoByIndex then
        local r = c.call("C_EncounterJournal.GetLootInfoByIndex(1)", CEJ.GetLootInfoByIndex, 1)
        d.lootFirst = Describe(r[2])
        local t = Tbl(r[2])
        if t then
          d.lootFirstName = Describe(t.name)
          local itemId = Num(t.itemID)
          if itemId and CEJ.GetLootInfo then c.call("C_EncounterJournal.GetLootInfo(itemID)", CEJ.GetLootInfo, itemId) end
        end
      end
    end
  end
  -- Map-based instance lookup.
  local map = C_Map and C_Map.GetBestMapForUnit and Num(c.quiet(C_Map.GetBestMapForUnit, "player")[2])
  if map and EJ_GetInstanceForMap then d.forMap = Num(c.call("EJ_GetInstanceForMap(playerMap)", EJ_GetInstanceForMap, map)[2]) end
  if CEJ.GetInstanceForGameMap then c.call("C_EncounterJournal.GetInstanceForGameMap(36)", CEJ.GetInstanceForGameMap, 36) end
  if C_EncounterJournal and CEJ.OnClose then c.call("C_EncounterJournal.OnClose", CEJ.OnClose) end

  local total = d.dungeons + d.raids + d.sampleResolved + (d.bosses or 0)
  local present = EJ_GetNumTiers or EJ_GetInstanceInfo
  local parts = {}
  for _, t in ipairs(d.tiers) do parts[#parts + 1] = string.format("%s:%dd/%dr", tostring(t.name or t.tier), t.dungeons, t.raids) end
  c.line("journal", c.status(present, total),
    string.format("tiers=%d instances d/r=%d/%d%s known-IDs resolved=%d/%d sample=%s bosses=%s loot=%s lootInfo=%s",
      nt, d.dungeons, d.raids, #parts > 0 and (" [" .. table.concat(parts, " ") .. "]") or "",
      d.sampleResolved, #SAMPLE_INSTANCES - 1, tostring(d.sampleInstance), tostring(d.bosses),
      tostring(d.numLoot), tostring(d.lootFirst)))
end

local function AreaMap(c)
  local d = { dungeonMaps = 0 }
  c.out.data.map = d
  local CM = C_Map
  local present = CM and CM.GetMapChildrenInfo
  local dtype = (Enum and Enum.UIMapType and Num(Enum.UIMapType.Dungeon)) or 4
  local map = CM and CM.GetBestMapForUnit and Num(c.call("C_Map.GetBestMapForUnit(player)", CM.GetBestMapForUnit, "player")[2])
  d.playerMap = map
  if map and CM.GetMapInfo then c.call("C_Map.GetMapInfo(playerMap)", CM.GetMapInfo, map) end
  if CM and CM.GetFallbackWorldMapID then d.worldMap = Num(c.call("C_Map.GetFallbackWorldMapID", CM.GetFallbackWorldMapID)[2]) end
  local names = {}
  local function Children(label, mapId)
    if not (present and mapId) then return 0 end
    local t = Tbl(c.call("C_Map.GetMapChildrenInfo(" .. label .. ",Dungeon)", CM.GetMapChildrenInfo, mapId, dtype, true)[2])
    local n = Count(t) or 0
    if t then
      for i = 1, math.min(#t, 4) do
        local nm = Tbl(t[i]) and Str(t[i].name)
        if nm then names[#names + 1] = nm end
      end
    end
    return n
  end
  d.dungeonMaps = Children("Azeroth947", 947)
  if d.worldMap and d.worldMap ~= 947 then d.dungeonMaps = d.dungeonMaps + Children("world", d.worldMap) end
  d.dungeonMapsHere = Children("playerMap", map)
  local CEJ = C_EncounterJournal or {}
  if map and CEJ.GetDungeonEntrancesForMap then
    d.entrances = Count(c.call("C_EncounterJournal.GetDungeonEntrancesForMap(playerMap)", CEJ.GetDungeonEntrancesForMap, map)[2])
  end
  if map and CEJ.GetEncountersOnMap then
    d.encountersOnMap = Count(c.call("C_EncounterJournal.GetEncountersOnMap(playerMap)", CEJ.GetEncountersOnMap, map)[2])
  end
  if C_ContentTracking and C_ContentTracking.GetEncounterTrackingInfo then
    c.call("C_ContentTracking.GetEncounterTrackingInfo(1)", C_ContentTracking.GetEncounterTrackingInfo, 1)
  end
  local n = d.dungeonMaps + (d.dungeonMapsHere or 0) + (d.entrances or 0) + (d.encountersOnMap or 0)
  c.line("map", c.status(present, n),
    string.format("playerMap=%s dungeon maps (world)=%s here=%s entrances=%s encountersOnMap=%s %s",
      tostring(map), tostring(d.dungeonMaps), tostring(d.dungeonMapsHere), tostring(d.entrances),
      tostring(d.encountersOnMap), #names > 0 and ("e.g. " .. table.concat(names, ", ")) or ""))
end

local function AreaLFG(c)
  local d = { scanned = 0, named = 0, withBosses = 0, bosses = 0 }
  c.out.data.lfg = d
  local LI = C_LFGInfo
  local present = GetLFGDungeonInfo
  if LI then
    for _, fn in ipairs({ "IsLFDEnabled", "IsLFREnabled", "CanPlayerUseLFD", "CanPlayerUseLFR", "IsGroupFinderEnabled" }) do
      c.call("C_LFGInfo." .. fn, LI[fn])
    end
    local en = c.quiet(LI.IsLFDEnabled)[2]
    if not IsSecret(en) then d.lfdEnabled = en end
  end
  local choice = GetLFDChoiceOrder and Tbl(c.call("GetLFDChoiceOrder", GetLFDChoiceOrder)[2])
  d.choiceOrder = Count(choice)
  d.categoryEntries = 0
  if LI and LI.GetAllEntriesForCategory then
    for cat = 1, 3 do
      local n = Count(c.call("C_LFGInfo.GetAllEntriesForCategory(" .. cat .. ")", LI.GetAllEntriesForCategory, cat)[2])
      d.categoryEntries = d.categoryEntries + (n or 0)
    end
  end
  if GetNumRFDungeons then d.rfDungeons = Num(c.call("GetNumRFDungeons", GetNumRFDungeons)[2]) end
  if GetRFDungeonInfo then c.call("GetRFDungeonInfo(1)", GetRFDungeonInfo, 1) end
  -- Direct scan of LFG dungeon IDs: finds dungeons even when the choice list is empty.
  local names, firstId = {}, nil
  if present then
    for id = 1, 1300 do
      local r = c.quiet(GetLFGDungeonInfo, id)
      if r[1] and Str(r[2]) and r[2] ~= "" then
        d.named = d.named + 1
        if not firstId then
          firstId = id
          c.call("GetLFGDungeonInfo(" .. id .. ")", GetLFGDungeonInfo, id)
        end
        if #names < 6 then names[#names + 1] = r[2] end
        if GetLFGDungeonNumEncounters then
          local n = Num(c.quiet(GetLFGDungeonNumEncounters, id)[2])
          if n and n > 0 then
            d.withBosses = d.withBosses + 1
            d.bosses = d.bosses + n
            if d.withBosses == 1 then
              c.call("GetLFGDungeonNumEncounters(" .. id .. ")", GetLFGDungeonNumEncounters, id)
              if GetLFGDungeonEncounterInfo then c.call("GetLFGDungeonEncounterInfo(" .. id .. ",1)", GetLFGDungeonEncounterInfo, id, 1) end
              if GetLFGDungeonRewards then c.call("GetLFGDungeonRewards(" .. id .. ")", GetLFGDungeonRewards, id) end
              if LI and LI.GetDungeonInfo then c.call("C_LFGInfo.GetDungeonInfo(" .. id .. ")", LI.GetDungeonInfo, id) end
            end
          end
        end
      end
    end
    d.scanned = 1300
  end
  c.line("lfg", c.status(present, d.named + (d.choiceOrder or 0) + d.categoryEntries),
    string.format("LFD enabled=%s choiceOrder=%s categoryEntries=%s named IDs (1-1300)=%d with bosses=%d (bosses=%d) RF=%s %s",
      tostring(d.lfdEnabled), tostring(d.choiceOrder), tostring(d.categoryEntries), d.named, d.withBosses,
      d.bosses, tostring(d.rfDungeons), #names > 0 and ("e.g. " .. table.concat(names, ", ")) or ""))
end

local function AreaSaved(c)
  local d = {}
  c.out.data.saved = d
  local present = GetNumSavedInstances
  if RequestRaidInfo then c.call("RequestRaidInfo", RequestRaidInfo) end
  if present then
    d.saved = Num(c.call("GetNumSavedInstances", GetNumSavedInstances)[2])
    if d.saved and d.saved > 0 and GetSavedInstanceInfo then c.call("GetSavedInstanceInfo(1)", GetSavedInstanceInfo, 1) end
  end
  if GetNumSavedWorldBosses then d.worldBosses = Num(c.call("GetNumSavedWorldBosses", GetNumSavedWorldBosses)[2]) end
  local r = c.call("GetInstanceInfo", GetInstanceInfo)
  d.here = Str(r[2])
  d.hereType = Str(r[3])
  d.hereInstanceId = Num(r[9])
  if IsInInstance then c.call("IsInInstance", IsInInstance) end
  c.line("saved", c.status(present, d.saved),
    string.format("saved=%s worldBosses=%s here=%s (%s, instanceID %s)", tostring(d.saved), tostring(d.worldBosses),
      tostring(d.here), tostring(d.hereType), tostring(d.hereInstanceId)))
end

-- Well-known classic items; 99999999 is a control that must not exist.
local SAMPLE_ITEMS = { 6948, 25, 2589, 12640, 17182, 19019, 14551, 99999999 }

local function ItemPass(c, phase)
  local d = c.out.data.items
  d.items = d.items or {}
  local CI = C_Item or {}
  local exists, instant, named, tip, quality = 0, 0, 0, 0, 0
  local control
  for _, id in ipairs(SAMPLE_ITEMS) do
    local it = d.items[id] or {}
    d.items[id] = it
    if phase == 1 and CI.RequestLoadItemDataByID then pcall(CI.RequestLoadItemDataByID, id) end
    it.exists = CI.DoesItemExistByID and c.quiet(CI.DoesItemExistByID, id)[2] and true or false
    local ri = c.quiet(CI.GetItemInfoInstant, id)
    it.instantIcon = ri[1] and Num(ri[6]) or nil
    it.instantClass = ri[1] and Str(ri[3]) or nil
    local rn = c.quiet(CI.GetItemInfo, id)
    it.name = rn[1] and Str(rn[2]) or nil
    it.quality = rn[1] and Num(rn[4]) or nil
    local nameById = CI.GetItemNameByID and Str(c.quiet(CI.GetItemNameByID, id)[2]) or nil
    it.name = it.name or nameById
    local tt = C_TooltipInfo and C_TooltipInfo.GetItemByID and Tbl(c.quiet(C_TooltipInfo.GetItemByID, id)[2]) or nil
    it.tooltipLines = tt and Count(tt.lines) or nil
    if id == 99999999 then
      control = it
    else
      if it.exists then exists = exists + 1 end
      if it.instantIcon then instant = instant + 1 end
      if it.name then named = named + 1 end
      if it.quality then quality = quality + 1 end
      if (it.tooltipLines or 0) > 0 then tip = tip + 1 end
    end
  end
  if phase == 1 then
    c.call("C_Item.DoesItemExistByID(6948)", CI.DoesItemExistByID, 6948)
    c.call("C_Item.GetItemInfoInstant(6948)", CI.GetItemInfoInstant, 6948)
    c.call("C_Item.GetItemInfo(6948)", CI.GetItemInfo, 6948)
    c.call("C_Item.GetItemNameByID(6948)", CI.GetItemNameByID, 6948)
    if C_TooltipInfo then c.call("C_TooltipInfo.GetItemByID(6948)", C_TooltipInfo.GetItemByID, 6948) end
  end
  local present = CI.GetItemInfo or CI.GetItemInfoInstant
  d["phase" .. phase] = { exists = exists, instant = instant, named = named, quality = quality, tooltips = tip,
    controlExists = control and control.exists or false }
  local real = #SAMPLE_ITEMS - 1
  c.line("items", c.status(present, math.max(exists, instant, named)),
    string.format("[%s] of %d sample: exist=%d instantInfo=%d name=%d rarity=%d tooltip=%d | control(99999999) exists=%s | ITEM_DATA_LOAD_RESULT events=%d",
      phase == 1 and "now" or "after 3s", real, exists, instant, named, quality, tip,
      tostring(control and control.exists or false), NS.itemEvents or 0))
end

local function AreaItems(c)
  c.out.data.items = {}
  if not NS._itemEventFrame then
    local f = CreateFrame("Frame")
    if pcall(f.RegisterEvent, f, "ITEM_DATA_LOAD_RESULT") then
      f:SetScript("OnEvent", function() NS.itemEvents = (NS.itemEvents or 0) + 1 end)
    end
    NS._itemEventFrame = f
  end
  ItemPass(c, 1)
end

local LOOT_EVENTS = { "LOOT_OPENED", "LOOT_READY", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "CHAT_MSG_LOOT",
  "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "START_LOOT_ROLL", "UPDATE_INSTANCE_INFO",
  "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "COMBAT_LOG_EVENT_UNFILTERED", "ITEM_DATA_LOAD_RESULT" }

local function AreaLoot(c)
  local d = { registrable = 0, failed = {} }
  c.out.data.loot = d
  local f = CreateFrame("Frame")
  for _, ev in ipairs(LOOT_EVENTS) do
    if pcall(f.RegisterEvent, f, ev) then
      d.registrable = d.registrable + 1
      pcall(f.UnregisterEvent, f, ev)
    else
      d.failed[#d.failed + 1] = ev
    end
  end
  local have, total, missing = c.presence({ "GetLootInfo", "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink",
    "GetLootSourceInfo", "C_LootHistory", "C_EncounterEvents", "C_InstanceEncounter", "C_InstanceEncounter.IsEncounterInProgress" })
  if GetNumLootItems then d.openLoot = Num(c.call("GetNumLootItems", GetNumLootItems)[2]) end
  if GetLootInfo then c.call("GetLootInfo", GetLootInfo) end
  if GetLootSlotInfo then c.call("GetLootSlotInfo(1)", GetLootSlotInfo, 1) end
  if GetLootSourceInfo then c.call("GetLootSourceInfo(1)", GetLootSourceInfo, 1) end
  if C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress then
    c.call("C_InstanceEncounter.IsEncounterInProgress", C_InstanceEncounter.IsEncounterInProgress)
  end
  c.line("loot", c.status(have > 0, d.registrable),
    string.format("events registrable %d/%d%s | loot APIs %d/%d%s | open loot slots=%s", d.registrable, #LOOT_EVENTS,
      #d.failed > 0 and (" (refused: " .. table.concat(d.failed, ", ") .. ")") or "", have, total,
      #missing > 0 and (" (missing: " .. table.concat(missing, ", ") .. ")") or "", tostring(d.openLoot)))
end

local function AreaRules(c)
  local d = { active = {} }
  c.out.data.rules = d
  local GR = C_GameRules
  local present = GR and GR.IsGameRuleActive and Enum and Enum.GameRule
  if GR and GR.GetActiveGameMode then d.mode = Describe(c.call("C_GameRules.GetActiveGameMode", GR.GetActiveGameMode)[2]) end
  if GR and GR.IsStandard then c.call("C_GameRules.IsStandard", GR.IsStandard) end
  if GR and GR.IsHardcoreActive then c.call("C_GameRules.IsHardcoreActive", GR.IsHardcoreActive) end
  local total = 0
  if present then
    for name, value in pairs(Enum.GameRule) do
      if not IsSecret(name) and type(name) == "string" and type(value) == "number" then
        total = total + 1
        local r = c.quiet(GR.IsGameRuleActive, value)
        if r[1] and r[2] == true and not IsSecret(r[2]) then d.active[#d.active + 1] = name end
      end
    end
    table.sort(d.active)
    for _, n in ipairs({ "EncounterJournalDisabled", "EjJourneysDisabled" }) do
      if Enum.GameRule[n] then c.call("C_GameRules.IsGameRuleActive(" .. n .. ")", GR.IsGameRuleActive, Enum.GameRule[n]) end
    end
  end
  d.total = total
  c.line("rules", c.status(present, total),
    string.format("mode=%s rules known=%d active=%d: %s", tostring(d.mode), total, #d.active,
      #d.active > 0 and Trunc(table.concat(d.active, ", "), 150) or "none"))
end

---------------------------------------------------------------------------
-- report assembly
---------------------------------------------------------------------------
local function BuildSummary(out)
  local lines = {}
  local sv = out.savedVariables
  local cl = out.client
  lines[1] = string.format("Dark Matter %s probe | client %s build %s (%s) Interface %s %s", out.addonVersion,
    tostring(cl.version), tostring(cl.build), tostring(cl.buildDate), tostring(cl.interface), tostring(cl.locale))
  lines[2] = string.format("SavedVariables: loadCount=%s | loaded from disk: %s | previous session: %s | previous probe present: %s",
    tostring(sv.loadCount), sv.existedAtLoad and "YES" or "NO", tostring(sv.previousSession),
    sv.previousProbePresent and ("YES (" .. tostring(sv.previousProbeWhen) .. ")") or "no")
  local ok, empty, missing = 0, 0, 0
  for _, key in ipairs(AREA_ORDER) do
    local a = out.areas[key]
    if a then
      if a.status == "OK" then ok = ok + 1 elseif a.status == "EMPTY" then empty = empty + 1 else missing = missing + 1 end
    end
  end
  lines[3] = string.format("Areas: %d OK, %d EMPTY (callable, no data), %d MISSING.  %d raw calls saved in SavedVariables.",
    ok, empty, missing, #out.callOrder)
  if out.areaErrors then lines[#lines + 1] = "Area errors (" .. #out.areaErrors .. "): " .. table.concat(out.areaErrors, " | ") end
  for _, key in ipairs(AREA_ORDER) do
    local a = out.areas[key]
    if a then lines[#lines + 1] = string.format("[%s] %s: %s", a.status, AREA_TITLE[key], a.text) end
  end
  return lines
end

function NS.RawLines(out)
  local lines = {}
  for _, name in ipairs(out.callOrder) do
    local c = out.calls[name]
    if c.ok then
      lines[#lines + 1] = name .. " -> " .. (c.n == 0 and "(no return)" or table.concat(c.ret, " | "))
    else
      lines[#lines + 1] = name .. " -> " .. tostring(c.err)
    end
  end
  return lines
end

function NS.Rebuild(out)
  out.summary = BuildSummary(out)
end

function NS.RunProbe(quiet)
  local version, build, bdate, toc = GetBuildInfo()
  local out = {
    when = date("%Y-%m-%d %H:%M:%S"),
    addonVersion = NS.version,
    client = { version = version, build = build, buildDate = bdate, interface = toc,
      locale = GetLocale(), projectId = WOW_PROJECT_ID, projectIdMainline = WOW_PROJECT_MAINLINE },
    savedVariables = {
      loadCount = NS.db and NS.db.loadCount,
      existedAtLoad = NS.sv.existedAtLoad,
      previousSession = NS.sv.previousSession,
      previousLoadCount = NS.sv.previousLoadCount,
      previousProbePresent = NS.sv.previousProbeWhen ~= nil,
      previousProbeWhen = NS.sv.previousProbeWhen,
    },
    apis = {}, types = {}, calls = {}, callOrder = {}, areas = {}, data = {},
  }
  local c = NewContext(out)
  local areas = { AreaQuests, AreaFishing, AreaAchievements, AreaJournal, AreaMap, AreaLFG, AreaSaved,
    AreaItems, AreaLoot, AreaRules }
  for _, fn in ipairs(areas) do
    local ok, err = pcall(fn, c)
    if not ok then
      -- An area that errors must not take the rest down; record why.
      out.areaErrors = out.areaErrors or {}
      out.areaErrors[#out.areaErrors + 1] = Trunc(err, 120)
    end
  end
  NS.Rebuild(out)
  if NS.db then NS.db.probe = out end
  NS.lastProbe = out

  -- Items arrive asynchronously: look again a few seconds later.
  if C_Timer and C_Timer.After then
    C_Timer.After(3, function()
      if NS.lastProbe ~= out then return end
      pcall(ItemPass, c, 2)
      NS.Rebuild(out)
      if NS.RefreshWindow then NS.RefreshWindow() end
    end)
  end

  if not quiet then
    NS.Print("probe done; saved to DarkMatterDB.probe. The window shows the summary (/dm raw toggles the raw call list).")
    for i = 1, 3 do print("  " .. out.summary[i]) end
  end
  if NS.RefreshWindow then NS.RefreshWindow() end
  if not quiet and NS.ToggleWindow then NS.ToggleWindow(true) end
  return out
end
