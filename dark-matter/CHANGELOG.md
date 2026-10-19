# Changelog

## 0.0.3 (P0.2 probe)
- New probe areas for the Adventure Guide data-source question: Encounter Journal data without the UI (`C_EncounterJournal.InitalizeSelectedTier`/`OnOpen`, tiers, instances, known instance IDs, bosses, loot), map-based discovery (dungeon child maps, entrances, encounters on map), LFG (choice order, category entries, direct scan of dungeon IDs, boss counts), saved instances, items on demand (sample classic item IDs plus a control, checked now and again after 3 seconds), loot-learning feasibility (event registration, loot APIs), game rules (every `Enum.GameRule` read).
- Fixed: the loot-by-index call is `C_EncounterJournal.GetLootInfoByIndex` on this client; `EJ_GetLootInfoByIndex` is no longer required.
- Every call is pcall-wrapped, raw returns are saved in `DarkMatterDB.probe.calls`, and values are checked with `issecretvalue` first.
- The window shows one summary line per area (`[OK]`, `[EMPTY]` or `[MISSING]` with counts); `/dm raw` adds the raw call list. The full raw list is always in SavedVariables.
- An area that errors is recorded under `probe.areaErrors` and no longer stops the rest.

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
