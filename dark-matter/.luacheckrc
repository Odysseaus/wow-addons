std = "lua51"
max_line_length = false
-- WoW client API used by this addon
read_globals = {
  "CreateFrame","UIParent","Minimap","GameTooltip","GetCursorPosition","GetBuildInfo","GetLocale",
  "GetMinimapShape","InCombatLockdown","C_Timer","C_AddOns","C_Map","GetAddOnMetadata",
  "WOW_PROJECT_ID","WOW_PROJECT_MAINLINE","Settings","BackdropTemplateMixin","UISpecialFrames",
  "GetNumQuestLogEntries","GetProfessions","GetProfessionInfo","EJ_GetNumTiers",
  "GetTotalAchievementPoints","GetCategoryList","tinsert","strmatch","strlower","strtrim","date",
}
globals = { "DarkMatter", "DarkMatterDB", "SLASH_DARKMATTER1", "SLASH_DARKMATTER2", "SlashCmdList" }
