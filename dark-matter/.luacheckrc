std = "lua51"
max_line_length = false
-- WoW client API used by this addon
read_globals = {
  "CreateFrame","UIParent","Minimap","GameTooltip","GetCursorPosition","GetBuildInfo","GetLocale",
  "GetMinimapShape","InCombatLockdown","C_Timer","C_AddOns","C_Map","GetAddOnMetadata",
  "WOW_PROJECT_ID","WOW_PROJECT_MAINLINE","Settings","BackdropTemplateMixin","UISpecialFrames",
  "GetNumQuestLogEntries","GetProfessions","GetProfessionInfo","EJ_GetNumTiers",
  "GetTotalAchievementPoints",
  "AchievementFrame","EncounterJournal","C_EncounterJournal","EJ_GetInstanceInfo","EJ_GetInstanceForMap","Enum","C_ContentTracking","C_LFGInfo","GetLFGDungeonInfo","GetLFDChoiceOrder","GetNumRFDungeons","GetRFDungeonInfo","GetLFGDungeonNumEncounters","GetLFGDungeonEncounterInfo","GetLFGDungeonRewards","GetNumSavedInstances","RequestRaidInfo","GetSavedInstanceInfo","GetNumSavedWorldBosses","GetInstanceInfo","IsInInstance","C_Item","C_TooltipInfo","GetNumLootItems","GetLootInfo","GetLootSlotInfo","GetLootSourceInfo","C_InstanceEncounter","C_GameRules","EJ_GetInstanceByIndex",
  "issecretvalue","DEFAULT_CHAT_FRAME","STANDARD_TEXT_FONT","GameFontNormal","UnitLevel","LoadAddOn","IsAddOnLoaded","GetAddOnInfo","GetQuestLogTitle","EJ_GetCurrentTier","EJ_GetTierInfo","EJ_SelectTier","EJ_GetInstanceByIndex","EJ_SelectInstance","EJ_GetEncounterInfoByIndex","EJ_GetEncounterInfo","EJ_SelectEncounter","EJ_GetNumLoot","EJ_GetLootInfoByIndex","GetCategoryNumAchievements","GetNumSkillLines","GetSkillLineInfo","GetAchievementInfo","C_QuestLog","C_TradeSkillUI","C_RestrictedActions","GetCategoryList","tinsert","strmatch","strlower","strtrim","date",
}
globals = { "DarkMatter", "DarkMatterDB", "SLASH_DARKMATTER1", "SLASH_DARKMATTER2", "SlashCmdList" }
