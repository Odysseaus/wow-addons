-- /dm probe: report which APIs this client has and save the result to
-- DarkMatterDB.probe. Read-only: nothing here opens a frame or changes state.
local _, NS = ...

local API_GROUPS = {
  { "Quest log", { "C_Map", "C_QuestLog", "GetNumQuestLogEntries",
      "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_Map.GetBestMapForUnit" } },
  { "Fishing / professions", { "GetProfessions", "GetProfessionInfo", "GetSkillLineInfo",
      "GetNumSkillLines", "C_TradeSkillUI", "ProfessionsFrame" } },
  { "Adventure Guide", { "EJ_GetNumTiers", "EJ_SelectTier", "EJ_GetInstanceByIndex",
      "C_EncounterJournal", "EncounterJournal", "ToggleEncounterJournal" } },
  { "Achievements", { "GetAchievementInfo", "GetCategoryList", "GetTotalAchievementPoints",
      "AchievementFrame", "ToggleAchievementFrame" } },
  { "Settings", { "Settings", "Settings.RegisterAddOnSetting", "Settings.RegisterAddOnCategory",
      "Settings.RegisterCanvasLayoutCategory", "Settings.OpenToCategory", "SettingsPanel" } },
  { "Timers / misc", { "C_Timer", "C_Timer.After", "C_AddOns", "C_AddOns.GetAddOnMetadata",
      "GetMinimapShape", "GameTooltip", "UISpecialFrames" } },
  { "Edit Mode / options", { "EditModeManagerFrame", "C_EditMode", "GameMenuFrame",
      "InterfaceOptionsFrame", "AddonCompartmentFrame" } },
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

local function Try(fn, ...)
  local ok, a, b, c, d, e = pcall(fn, ...)
  if ok then return a, b, c, d, e end
  return nil
end

local function Plain(v)
  local t = type(v)
  if t == "number" or t == "boolean" then return v end
  if t == "string" then return v end
  return nil
end

function NS.RunProbe(quiet)
  local version, build, bdate, toc = GetBuildInfo()
  local out = {
    when = date("%Y-%m-%d %H:%M:%S"),
    addonVersion = NS.version,
    client = {
      version = version, build = build, buildDate = bdate,
      interface = toc,
      tocFileInterface = Try(function()
        return (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(NS.name, "Interface")
      end),
      locale = GetLocale(),
      projectId = WOW_PROJECT_ID,
      projectIdMainline = WOW_PROJECT_MAINLINE,
    },
    savedVariables = {
      existedAtLoad = NS.sv.existedAtLoad,
      previousSession = NS.sv.previousSession,
      previousLoadCount = NS.sv.previousLoadCount,
      loadCount = NS.db and NS.db.loadCount,
    },
    apis = {},
    types = {},
    values = {},
  }

  local lines = {}
  local function add(s) lines[#lines + 1] = s end

  add(string.format("Client %s build %s (%s), Interface %s, locale %s",
    tostring(version), tostring(build), tostring(bdate), tostring(toc), tostring(out.client.locale)))
  add(string.format("SavedVariables from disk: %s (previous session: %s, load #%s)",
    out.savedVariables.previousSession and "YES" or "no",
    tostring(out.savedVariables.previousSession), tostring(out.savedVariables.loadCount)))

  for _, group in ipairs(API_GROUPS) do
    local have, missing = {}, {}
    for _, name in ipairs(group[2]) do
      local v = Resolve(name)
      out.apis[name] = v ~= nil
      out.types[name] = type(v)
      if v ~= nil then have[#have + 1] = name else missing[#missing + 1] = name end
    end
    add(string.format("%s: %d/%d present%s", group[1], #have, #group[2],
      #missing > 0 and ("  MISSING: " .. table.concat(missing, ", ")) or ""))
  end

  -- A few harmless read-only calls so we learn what the data looks like.
  local v = out.values
  if GetNumQuestLogEntries then
    local n, q = Try(GetNumQuestLogEntries)
    v.GetNumQuestLogEntries = tostring(Plain(n)) .. "/" .. tostring(Plain(q))
  end
  if C_Map and C_Map.GetBestMapForUnit then v.bestMapForPlayer = Plain(Try(C_Map.GetBestMapForUnit, "player")) end
  if EJ_GetNumTiers then v.EJ_GetNumTiers = Plain(Try(EJ_GetNumTiers)) end
  if GetTotalAchievementPoints then v.GetTotalAchievementPoints = Plain(Try(GetTotalAchievementPoints)) end
  if GetCategoryList then
    local cats = Try(GetCategoryList)
    v.achievementCategories = type(cats) == "table" and #cats or nil
  end
  if GetProfessions and GetProfessionInfo then
    local p1, p2, arch, fish, cook = Try(GetProfessions)
    v.professionIndexes = table.concat({ tostring(p1), tostring(p2), tostring(arch), tostring(fish), tostring(cook) }, ",")
    if fish then
      local name, _, rank, maxRank = Try(GetProfessionInfo, fish)
      v.fishing = tostring(Plain(name)) .. " " .. tostring(Plain(rank)) .. "/" .. tostring(Plain(maxRank))
    end
  end
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    v.EncounterJournalAddOnLoaded = Plain(Try(C_AddOns.IsAddOnLoaded, "Blizzard_EncounterJournal"))
    v.AchievementUILoaded = Plain(Try(C_AddOns.IsAddOnLoaded, "Blizzard_AchievementUI"))
  end
  add(string.format("Data: quests %s, fishing %s, EJ tiers %s, achievement points %s, categories %s",
    tostring(v.GetNumQuestLogEntries), tostring(v.fishing), tostring(v.EJ_GetNumTiers),
    tostring(v.GetTotalAchievementPoints), tostring(v.achievementCategories)))

  out.summary = lines
  if NS.db then NS.db.probe = out end
  NS.lastProbe = out
  if not quiet then
    NS.Print("probe results (also saved to DarkMatterDB.probe; /reload to write the file):")
    for _, l in ipairs(lines) do print("  " .. l) end
  end
  if NS.RefreshWindow then NS.RefreshWindow() end
  return out
end
