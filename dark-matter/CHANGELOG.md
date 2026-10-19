# Changelog

## 0.0.2 (P0.1)
- Probe loads `Blizzard_EncounterJournal` and `Blizzard_AchievementUI` on demand (pcall-guarded) before checking.
- Probe re-checks quests (`C_QuestLog.GetNumQuestLogEntries`/`GetInfo`), fishing skill (records which function worked), Adventure Guide (tiers, instances, bosses, encounter info, loot) and achievements (points, categories, sample).
- Every call's raw return types are saved under `DarkMatterDB.probe.calls`; optional APIs are no longer reported as MISSING.
- Scrollable report in the window; window enlarged; `/dm probe` opens it.
- Minimap button falls back to a round minimap when `GetMinimapShape` does not exist.
- Clearer SavedVariables report: `loadCount`, loaded-from-disk flag, previous session and previous-probe-present.

## 0.0.1 (P0 scaffold)
- Namespace, SavedVariables (`DarkMatterDB`) defaults.
- Round minimap button, draggable around the edge, angle saved.
- Placeholder stock-frame window: centre by default, position saved, reset command/button/option.
- `/dm`, `/dm probe` (saved to `DarkMatterDB.probe`), `/dm reset`, `/dm minimap`, `/dm icon`, `/dm options`, `/dm help`.
- Settings page (deferred with `C_Timer.After(0)`).
