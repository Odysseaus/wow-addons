-- /dm probe: report which APIs this client really has and what they return.
-- Loads the Encounter Journal and Achievement UI on demand first (stock
-- LoadAddOn, pcall-guarded), then records every call's raw return types into
-- DarkMatterDB.probe. Read-only apart from the stock EJ tier/instance/encounter
-- selection (restored afterwards); opens no windows.
local _, NS = ...

-- A leading "?" marks an optional API: reported, but never shown as MISSING.
local API_GROUPS = {
  { "Quest log", { "C_Map", "C_QuestLog", "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo",
      "C_Map.GetBestMapForUnit", "?GetNumQuestLogEntries", "?GetQuestLogTitle",
      "?C_QuestLog.GetTitleForLogIndex" } },
  { "Fishing / professions", { "GetProfessions", "GetProfessionInfo", "?GetSkillLineInfo",
      "?GetNumSkillLines", "?C_TradeSkillUI", "?C_TradeSkillUI.GetProfessionInfoBySkillLineID",
      "?ProfessionsFrame" } },
  { "Adventure Guide", { "EJ_GetNumTiers", "EJ_SelectTier", "EJ_GetInstanceByIndex", "EJ_SelectInstance",
      "EJ_GetEncounterInfoByIndex", "EJ_GetEncounterInfo", "EJ_SelectEncounter", "EJ_GetNumLoot",
      "EJ_GetLootInfoByIndex", "C_EncounterJournal", "EncounterJournal", "?ToggleEncounterJournal" } },
  { "Achievements", { "GetAchievementInfo", "GetCategoryList", "GetTotalAchievementPoints",
      "GetCategoryNumAchievements", "AchievementFrame", "?ToggleAchievementFrame" } },
  { "Settings", { "Settings", "Settings.RegisterAddOnSetting", "Settings.RegisterAddOnCategory",
      "Settings.RegisterCanvasLayoutCategory", "Settings.OpenToCategory", "SettingsPanel" } },
  { "Timers / misc", { "C_Timer", "C_Timer.After", "C_AddOns", "C_AddOns.GetAddOnMetadata",
      "C_AddOns.LoadAddOn", "?LoadAddOn", "?GetMinimapShape", "GameTooltip", "UISpecialFrames" } },
  { "Edit Mode / options", { "EditModeManagerFrame", "C_EditMode", "GameMenuFrame", "SettingsPanel",
      "?InterfaceOptionsFrame", "?AddonCompartmentFrame" } },
}

local function Resolve(path)
  local v = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
    if v == nil then return nil end
  end
  return v
end

local function Trunc(s, n)
  s = tostring(s)
  if #s > n then return string.sub(s, 1, n) .. "..." end
  return s
end

local function Pack(...) return { n = select("#", ...), ... } end

-- Raw description of one value: "number:171", "string:Fishing", "table{id,name,...}".
local function Describe(v)
  local ok, d = pcall(function()
    if issecretvalue and issecretvalue(v) then return "secret" end
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "number" or t == "boolean" then return t .. ":" .. tostring(v) end
    if t == "string" then return "string:" .. Trunc(v, 48) end
    if t == "table" then
      local keys, n = {}, 0
      for k in pairs(v) do
        n = n + 1
        if n <= 12 then keys[#keys + 1] = tostring(k) end
      end
      table.sort(keys)
      return "table{" .. table.concat(keys, ",") .. (n > 12 and ",..." or "") .. "}#" .. n
    end
    return t
  end)
  return ok and d or "error"
end

function NS.RunProbe(quiet)
  local version, build, bdate, toc = GetBuildInfo()
  local out = {
    when = date("%Y-%m-%d %H:%M:%S"),
    addonVersion = NS.version,
    client = {
      version = version, build = build, buildDate = bdate, interface = toc,
      locale = GetLocale(), projectId = WOW_PROJECT_ID, projectIdMainline = WOW_PROJECT_MAINLINE,
    },
    savedVariables = {
      loadCount = NS.db and NS.db.loadCount,
      existedAtLoad = NS.sv.existedAtLoad,
      previousSession = NS.sv.previousSession,
      previousLoadCount = NS.sv.previousLoadCount,
      previousProbePresent = NS.sv.previousProbeWhen ~= nil,
      previousProbeWhen = NS.sv.previousProbeWhen,
    },
    apis = {}, types = {}, loaded = {}, calls = {}, callOrder = {}, found = {}, data = {},
  }
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  local calls, order = out.calls, out.callOrder

  -- Record one call (first time per name only). Returns the packed pcall result.
  local function Call(name, fn, ...)
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
  local function Quiet(fn, ...)
    local r = Pack(pcall(fn, ...))
    return r
  end
  local function Num(v) if type(v) == "number" then return v end end

  -- 1) Load the on-demand Blizzard UIs.
  local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
  for _, name in ipairs({ "Blizzard_EncounterJournal", "Blizzard_AchievementUI" }) do
    local before = isLoaded and Quiet(isLoaded, name)[2] or nil
    Call("GetAddOnInfo:" .. name, getInfo, name)
    local r = Call("LoadAddOn:" .. name, loader, name)
    local after = isLoaded and Quiet(isLoaded, name)[2] or nil
    out.loaded[name] = { before = before and true or false, after = after and true or false,
      loadReturn1 = Describe(r[2]), loadReturn2 = Describe(r[3]) }
  end

  -- 2) API presence (frames are checked after the load above).
  for _, group in ipairs(API_GROUPS) do
    local have, missing, optMissing, total = 0, {}, {}, 0
    for _, raw in ipairs(group[2]) do
      local optional = string.sub(raw, 1, 1) == "?"
      local name = optional and string.sub(raw, 2) or raw
      local v = Resolve(name)
      out.apis[name] = v ~= nil
      out.types[name] = type(v)
      if not optional then total = total + 1 end
      if v ~= nil then
        if not optional then have = have + 1 end
      elseif optional then
        optMissing[#optMissing + 1] = name
      else
        missing[#missing + 1] = name
      end
    end
    add(string.format("%s: %d/%d%s%s", group[1], have, total,
      #missing > 0 and ("  MISSING: " .. table.concat(missing, ", ")) or "",
      #optMissing > 0 and ("  (optional absent: " .. table.concat(optMissing, ", ") .. ")") or ""))
  end

  -- 3) Quest log.
  local d = out.data
  local C_QL = C_QuestLog
  if C_QL and C_QL.GetNumQuestLogEntries then
    local r = Call("C_QuestLog.GetNumQuestLogEntries", C_QL.GetNumQuestLogEntries)
    d.questEntries, d.questCount = Num(r[2]), Num(r[3])
    if d.questEntries then out.found.quests = "C_QuestLog.GetNumQuestLogEntries" end
  end
  if C_QL and C_QL.GetInfo then
    local r = Call("C_QuestLog.GetInfo(1)", C_QL.GetInfo, 1)
    local t = r[2]
    if type(t) == "table" then
      d.questInfo1 = { title = Describe(t.title), questID = Describe(t.questID), isHeader = Describe(t.isHeader) }
    end
  end
  if C_QL and C_QL.GetTitleForLogIndex then Call("C_QuestLog.GetTitleForLogIndex(1)", C_QL.GetTitleForLogIndex, 1) end
  if GetQuestLogTitle then Call("GetQuestLogTitle(1)", GetQuestLogTitle, 1) end
  if GetNumQuestLogEntries then Call("GetNumQuestLogEntries", GetNumQuestLogEntries) end
  if C_Map and C_Map.GetBestMapForUnit then
    d.bestMap = Num(Call("C_Map.GetBestMapForUnit(player)", C_Map.GetBestMapForUnit, "player")[2])
  end
  add(string.format("Quests: entries=%s quests=%s via %s", tostring(d.questEntries), tostring(d.questCount),
    tostring(out.found.quests or "nothing worked")))

  -- 4) Fishing skill.
  if GetProfessions then
    local r = Call("GetProfessions", GetProfessions)
    local fish = r[5]
    d.professionIndexes = table.concat({ tostring(r[2]), tostring(r[3]), tostring(r[4]), tostring(r[5]), tostring(r[6]) }, ",")
    if GetProfessionInfo and fish then
      local p = Call("GetProfessionInfo(fishingIndex)", GetProfessionInfo, fish)
      -- name, icon, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier, ...
      if type(p[2]) == "string" and Num(p[4]) and Num(p[5]) then
        d.fishing = { name = p[2], rank = p[4], max = p[5], skillLine = Num(p[8]), rankModifier = Num(p[9]) }
        out.found.fishing = "GetProfessionInfo(select(4, GetProfessions()))"
      end
      d.fishingSkillLine = Num(p[8])
    end
  end
  local TS = C_TradeSkillUI
  if TS and TS.GetProfessionInfoBySkillLineID then
    local id = d.fishingSkillLine or 356
    local r = Call("C_TradeSkillUI.GetProfessionInfoBySkillLineID(" .. tostring(id) .. ")", TS.GetProfessionInfoBySkillLineID, id)
    if type(r[2]) == "table" then
      local t = r[2]
      d.fishingTradeSkill = { skillLevel = Describe(t.skillLevel), maxSkillLevel = Describe(t.maxSkillLevel),
        professionName = Describe(t.professionName) }
      if not out.found.fishing and Num(t.skillLevel) and Num(t.maxSkillLevel) then
        out.found.fishing = "C_TradeSkillUI.GetProfessionInfoBySkillLineID"
      end
    end
  end
  if GetNumSkillLines then Call("GetNumSkillLines", GetNumSkillLines) end
  if GetSkillLineInfo then Call("GetSkillLineInfo(1)", GetSkillLineInfo, 1) end
  if d.fishing then
    add(string.format("Fishing: %s %s/%s via %s", d.fishing.name, tostring(d.fishing.rank), tostring(d.fishing.max), out.found.fishing))
  else
    add("Fishing: not found. professions=" .. tostring(d.professionIndexes))
  end

  -- 5) Adventure Guide (stock Encounter Journal calls).
  d.ej = { tiers = {} }
  if EJ_GetNumTiers then
    local nt = Num(Call("EJ_GetNumTiers", EJ_GetNumTiers)[2]) or 0
    d.ej.numTiers = nt
    local cur = EJ_GetCurrentTier and Num(Call("EJ_GetCurrentTier", EJ_GetCurrentTier)[2]) or nil
    local firstInstance
    local function CountInstances(isRaid)
      local n, first = 0, nil
      for i = 1, 60 do
        local r = Quiet(EJ_GetInstanceByIndex, i, isRaid)
        if not r[1] or r[2] == nil then break end
        if i == 1 then
          Call("EJ_GetInstanceByIndex(1," .. tostring(isRaid) .. ")", EJ_GetInstanceByIndex, 1, isRaid)
          first = { id = Num(r[2]), name = type(r[3]) == "string" and r[3] or nil }
        end
        n = n + 1
      end
      return n, first
    end
    if EJ_GetInstanceByIndex then
      if nt == 0 then
        local dn, df = CountInstances(false)
        local rn, rf = CountInstances(true)
        d.ej.noTier = { dungeons = dn, raids = rn }
        firstInstance = df or rf
      end
      for tier = 1, math.min(nt, 12) do
        if EJ_SelectTier then Call("EJ_SelectTier(" .. tier .. ")", EJ_SelectTier, tier) end
        local tname = EJ_GetTierInfo and Quiet(EJ_GetTierInfo, tier)[2] or nil
        local dn, df = CountInstances(false)
        local rn, rf = CountInstances(true)
        d.ej.tiers[#d.ej.tiers + 1] = { tier = tier, name = type(tname) == "string" and tname or nil, dungeons = dn, raids = rn }
        firstInstance = firstInstance or df or rf
      end
      if cur and EJ_SelectTier then pcall(EJ_SelectTier, cur) end
    end
    -- One sample instance -> bosses -> one encounter -> loot.
    if firstInstance and firstInstance.id and EJ_SelectInstance then
      d.ej.sampleInstance = firstInstance
      Call("EJ_SelectInstance", EJ_SelectInstance, firstInstance.id)
      local bosses, firstEnc = 0, nil
      if EJ_GetEncounterInfoByIndex then
        for i = 1, 30 do
          local r = Quiet(EJ_GetEncounterInfoByIndex, i, firstInstance.id)
          if not r[1] or r[2] == nil then break end
          if i == 1 then
            Call("EJ_GetEncounterInfoByIndex(1)", EJ_GetEncounterInfoByIndex, 1, firstInstance.id)
            firstEnc = { name = type(r[2]) == "string" and r[2] or nil, id = Num(r[4]) }
          end
          bosses = bosses + 1
        end
      end
      d.ej.bosses = bosses
      if firstEnc and firstEnc.id then
        d.ej.sampleEncounter = firstEnc
        if EJ_GetEncounterInfo then Call("EJ_GetEncounterInfo", EJ_GetEncounterInfo, firstEnc.id) end
        if EJ_SelectEncounter then Call("EJ_SelectEncounter", EJ_SelectEncounter, firstEnc.id) end
        if EJ_GetNumLoot then d.ej.numLoot = Num(Call("EJ_GetNumLoot", EJ_GetNumLoot)[2]) end
        if EJ_GetLootInfoByIndex then
          local r = Call("EJ_GetLootInfoByIndex(1)", EJ_GetLootInfoByIndex, 1)
          d.ej.lootFirst = Describe(r[2])
          if type(r[2]) == "table" then d.ej.lootFirstName = Describe(r[2].name) end
        end
      end
    end
  end
  do
    local e = d.ej
    local parts = {}
    for _, t in ipairs(e.tiers) do parts[#parts + 1] = string.format("%s:%dd/%dr", tostring(t.name or t.tier), t.dungeons, t.raids) end
    add(string.format("Adventure Guide data: tiers=%s%s", tostring(e.numTiers),
      #parts > 0 and (" [" .. table.concat(parts, " ") .. "]") or ""))
    if e.noTier then add(string.format("  (no tier selected: %d dungeons, %d raids)", e.noTier.dungeons, e.noTier.raids)) end
    if e.sampleInstance then
      add(string.format("  sample instance %s: bosses=%s, first boss %s, loot=%s first=%s",
        tostring(e.sampleInstance.name), tostring(e.bosses),
        tostring(e.sampleEncounter and e.sampleEncounter.name), tostring(e.numLoot), tostring(e.lootFirst)))
    else
      add("  no instances returned")
    end
  end

  -- 6) Achievements.
  d.ach = {}
  if GetTotalAchievementPoints then d.ach.points = Num(Call("GetTotalAchievementPoints", GetTotalAchievementPoints)[2]) end
  if GetCategoryList then
    local r = Call("GetCategoryList", GetCategoryList)
    local cats = r[2]
    d.ach.categories = type(cats) == "table" and #cats or nil
    if type(cats) == "table" and GetCategoryNumAchievements then
      for _, cat in ipairs(cats) do
        local nr = Quiet(GetCategoryNumAchievements, cat)
        if nr[1] and Num(nr[2]) and nr[2] > 0 then
          Call("GetCategoryNumAchievements(" .. tostring(cat) .. ")", GetCategoryNumAchievements, cat)
          d.ach.sampleCategory, d.ach.sampleCategoryCount = cat, nr[2]
          if GetAchievementInfo then
            local ar = Call("GetAchievementInfo(category,1)", GetAchievementInfo, cat, 1)
            d.ach.sampleId = Num(ar[2])
            d.ach.sampleName = type(ar[3]) == "string" and ar[3] or nil
          end
          break
        end
      end
    end
  end
  if GetAchievementInfo then
    local id = d.ach.sampleId or 6
    local r = Call("GetAchievementInfo(" .. tostring(id) .. ")", GetAchievementInfo, id)
    d.ach.byId = { id = id, name = Describe(r[3]), points = Describe(r[4]), completed = Describe(r[5]) }
  end
  add(string.format("Achievements: points=%s categories=%s sample=%s (%s)", tostring(d.ach.points),
    tostring(d.ach.categories), tostring(d.ach.sampleName), tostring(d.ach.sampleId)))

  -- Head lines go first.
  local head = {}
  head[1] = string.format("Dark Matter %s probe | client %s build %s (%s) Interface %s %s", NS.version,
    tostring(version), tostring(build), tostring(bdate), tostring(toc), tostring(out.client.locale))
  local sv = out.savedVariables
  head[2] = string.format("SavedVariables: loadCount=%s | loaded from disk: %s | previous session: %s | previous probe present: %s",
    tostring(sv.loadCount), sv.existedAtLoad and "YES" or "NO", tostring(sv.previousSession),
    sv.previousProbePresent and ("YES (" .. tostring(sv.previousProbeWhen) .. ")") or "no")
  local ld = {}
  for name, l in pairs(out.loaded) do ld[#ld + 1] = string.format("%s %s->%s", (string.gsub(name, "Blizzard_", "")), l.before and "loaded" or "not loaded", l.after and "loaded" or "NOT loaded") end
  table.sort(ld)
  head[3] = "On-demand UI: " .. table.concat(ld, ", ")
  for i = #head, 1, -1 do table.insert(lines, 1, head[i]) end

  add("-- Raw call returns (type:value) --")
  for _, name in ipairs(order) do
    local c = calls[name]
    if c.ok then
      add(name .. " -> " .. (c.n == 0 and "(no return)" or table.concat(c.ret, " | ")))
    else
      add(name .. " -> " .. tostring(c.err))
    end
  end

  out.summary = lines
  if NS.db then NS.db.probe = out end
  NS.lastProbe = out
  if not quiet then
    NS.Print("probe done; saved to DarkMatterDB.probe. Open the window (/dm) to scroll the full report.")
    for i = 1, 3 do print("  " .. lines[i]) end
  end
  if NS.RefreshWindow then NS.RefreshWindow() end
  if not quiet and NS.ToggleWindow then NS.ToggleWindow(true) end
  return out
end
