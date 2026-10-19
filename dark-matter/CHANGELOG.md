# Changelog

## 0.2.4 (P2.4, Catches pill + catalog Show all)
- Top pills are **Catches** and **Statistics**. Inside Catches: **by zone** / **by fish** toggle (persisted per character with Show all).
- **Show all** (fixed): checked lists the static Forever/classic fishing-catch catalog (`Data_FishingCatches.lua`); items you have logged are highlighted and sorted to the top; unchecked lists only logged catches.
- By fish rows show round item icons, count/share, and **last caught zone + map coords** (stored on loot via `C_Map.GetPlayerMapPosition` / `GetPlayerMapPosition` when available).
- Search still filters the active list. Previewer updated to match.

## 0.2.3 (P2.3, Catches by zone / by fish)
- Journals → Fishing: pills **Catches by zone**, **Catches by fish**, and **Statistics**. Zone vs fish choice (and Show all) persist per character in `DarkMatterCharDB.fishing.ui`.
- Catches by fish: aggregated catch types with circular item icons (`GetItemIcon` / `SetPortraitToTexture`), count and share.
- **Show all**: off = fish-focused (excludes quality-0 junk); on = every logged catch type including junk/non-fish.
- Search bar filters the active list (zone names or catch names).
- Item ids stored from loot links for icons. Previewer mockup updated to match.

## 0.2.2 (P2.2, Fishing UI parity + lure names)
- Journals → Fishing skill strip matches the addon-previewer mockup: horizontal title | bar | subtitle on a light parchment panel (Friz Quadrata). Fixes the clipped unreadable grey line under the skill bar (was slate-grey `listSoft` text overflowing a 52px dark panel).
- Progress bars restyled (rim, dark track, gold/green fill, gloss, cream label); thin share bars for per-zone catch %. View pills renamed to "Catches by zone" / "Statistics"; zone list header "Zones".
- Favorite lure (stat #9) now shows the lure **item name** (e.g. Shiny Bauble) via enchant→item map + `C_Item.GetItemInfo` / `GetItemInfo`, not `Lure #<id>`. Legacy saved keys are migrated on read.
- Waters list: all six Classic main cities (Ironforge, Stormwind City, Orgrimmar, Undercity, Thunder Bluff, Darnassus) with minSkill 1 and fishing-subzone aliases so `GetRealZoneText` / subzone attribution counts under the city row (not Unknown).
- Catch tracking and taint safety unchanged. Adventure Guide still stub.

## 0.2.1 (P2.1, Fishing catch tracking)
- Per-character fishing stats (`DarkMatterCharDB`), starting at zero on first use: zone catch shares, casts/catches, catch rate, junk vs good, rare first-catches, time fishing, best junk-free streak, gold value (when vendor price is known), got-away casts, skill history, favorite zone and lure.
- Tracker runs on a private frame from login (casts via fishing channel, loot via `IsFishingLoot` + loot slots, got-away via UI error / timeout, skill via `GetProfessionInfo`). Zone is inferred from `GetRealZoneText` / subzone against the waters table, else last-known / "Unknown".
- Journals → Fishing: Waters / Statistics views. Waters list shows catch counts; detail shows per-item % of that zone. Statistics cards mirror the previewer layout. No "(Complete)" tags. Adventure Guide / Achievements still stubs.

## 0.2.0 (P2, Journals Fishing)
- Journals → Fishing is a real panel: fishing skill bar from `GetProfessionInfo(select(4, GetProfessions()))` (probe-confirmed), and a waters list with minimum skill floors.
- Zone list is original Dark Matter static data (`Data_Fishing.lua`): this Forever client has no fishing-zone or catch APIs (only profession skill + `IsFishingLoot`). Waters show Ready/Locked by your skill; no fake catch counts or "(Complete)" tags. Catch statistics stay for a later phase.
- Adventure Guide and Achievements sections remain "Coming soon". Quests tab, Settings click-outside, probe and blocked logger are unchanged.
- New `UI.Bar` progress widget; fishing skill events on a private frame while the Fishing section is shown.

## 0.1.3 (Settings pop: click-outside / Esc dismiss)
- Settings popover closes when you click anywhere outside it: a catcher over the main window (above content, below the pop) and a full-screen catcher under the window so a click on the world dismisses too. The Settings button still toggles open; while open, a click on Settings hits the catcher and closes without re-opening.
- Esc closes the Settings pop first (via `UISpecialFrames` on the named `DarkMatterSettingsPop`); Esc again closes the main window as before. Stock frames and private handlers only.

## 0.1.2 (fix: inactive pill fill gap)
- Fix: Journals section pills (Adventure Guide, Achievements) showed a thin horizontal gap of slate background between the metal bezel and the dark burgundy fill. The active (Fishing) pill was fine. Cause: the generated inactive middle piece (`ptab-i-m.webp`) had a transparent band under the top bezel (source rows 5-13 of 64); left/right caps had matching holes. Active pieces are flush. The inactive art is repaired by filling those gaps from the active piece's fill topology with the inactive burgundy; `tools/make_wow_textures.py` applies the same repair when packing the atlas.

## 0.1.1 (fix: window did not assemble)
- Fix: opening 0.1.0 showed one huge stretched frame corner, a flat slate area and no tabs or content. Cause: in `UI.NineSlice` the corner size was stored in a field named `t`, and the top-edge texture used the same key, so it overwrote the number. `SetSize(<texture>, <texture>)` then raised a Lua error in the client; the corners and edges never got a size and the window build aborted before the rail, tabs, body and footer were created. The size now lives in `n.size`.
- The window build now runs under `pcall`: if anything ever errors while building, the half-built window is hidden and discarded, and the error is printed to the chat frame (`Dark Matter: the window could not be built: ...`) instead of leaving a broken window.
- The active section pill no longer draws its marker over the label.
- Test harness: the stub client is now strict (argument types, `SetPoint` forms, draw layers, sublevels) and resolves layout, so the tests now assert valid texcoords (0..1, left < right, top < bottom), anchored non-zero-size textures, no texture larger than the window, an 8-piece corner-to-corner window border, content frames above the window art, and atlas rects/TGA sizes. `tools/render_preview.py` composites the window offline from the Lua's own layout and the real TGAs.

## 0.1.0 (P1, main window)
- New main window built from the approved previewer mockup: WoW theme, title plate with medal and close button, left tab rail (Quests, Journals, Map, Dungeons), footer with Settings, status field, Share stats (disabled) and Exit. Opens at screen centre, position saved on drag, **Reset window position** in the Settings popover, the Settings page, and `/dm reset`. Scales down on small screens.
- Quests tab: reads the quest log from `C_QuestLog` (read only, secret-safe, never the `GetNumQuestLogEntries` global): zone headers with collapse and an All button, difficulty colours, detail panel with objectives. Quest events are registered on a private frame only while the tab is showing, and refreshes are coalesced.
- Journals tab: Fishing, Adventure Guide and Achievements sections as "Coming soon" placeholders. Map and Dungeons: "coming in a later phase" pages.
- Theme layer: `NS.RegisterTheme`, skin hooks and piece helpers; the default WoW theme is data (`Theme_WoW.lua`, generated `Atlas_WoW.lua`) so the nine class themes can be added later as data.
- Textures: the previewer's generated art packed into power-of-two uncompressed TGAs (`Media/wow-atlas.tga` 1024x512, `wow-parchment.tga` 1024x1024, `wow-slate.tga` 512x256) by `tools/make_wow_textures.py`; 3-slice and 9-slice pieces.
- The minimap button toggles the main window.
- The probe is unchanged (0.0.4) but its report now opens in its own small stock window (`/dm probe`, `/dm raw`). The blocked-action logger is kept.
- Taint safety: stock frame types only, no hooks of Blizzard functions, no `LoadAddOn`, deferred Settings registration (`C_Timer.After(0)`), private frames for events.

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
