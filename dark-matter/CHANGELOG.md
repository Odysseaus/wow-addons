# Changelog

## 0.0.4 (P0.3, taint-safe probe)
- Fix: 0.0.3 could make the client report `ADDON_ACTION_BLOCKED` ("DarkMatter has been blocked from an action only available to the Blizzard UI") when run in a dungeon. The probe is now strictly read-only.
- Removed every call that loads Blizzard UI or mutates/requests shared state: `LoadAddOn("Blizzard_AchievementUI")`, `C_EncounterJournal.InitalizeSelectedTier`/`OnOpen`/`OnClose`, `EJ_SelectTier`/`EJ_SelectInstance`/`EJ_SelectEncounter` and the selection restore, `RequestRaidInfo`, `C_Item.RequestLoadItemDataByID`, `GetLFGDungeonRewards`, and the `ITEM_DATA_LOAD_RESULT` counter.
- Event-registrability test runs on a private frame only and no longer touches `COMBAT_LOG_EVENT_UNFILTERED`.
- Probe refuses to run in combat lockdown. It only runs from the `/dm` command or Dark Matter's own buttons.
- New blocked-action recorder: `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` are logged to `DarkMatterDB.blockedLog` (mirrored in `probe.blocked`) with the probe step that was running; `/dm blocked` lists them and the summary shows a `[BLOCKED]` line.
- Probe now also reads the active addon restrictions (`C_RestrictedActions`) in the Game rules line.
- Journal data without UI is read-only (counts reflect the current selection and the first tier only). Findings confirmed in 0.0.3 are unchanged: Journal API present, journal data empty, LFG scan finds 67 dungeons with bosses, item reads work, loot events registrable, game rules readable.

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
