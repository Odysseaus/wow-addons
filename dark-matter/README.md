# Dark Matter (P2.8 fishing catalog + item tooltips)

**Version 0.4.1** · Interface `16001` (World of Warcraft: Forever beta, `_classic_beta_`) · Author: Odysseaus

Dark Matter is a one-window overview of your quests, fishing, dungeons and achievements. **P1 builds the real main window**: the WoW theme from the approved previewer mockup, a vertical tab rail on the left, and a working Quests tab. Journals, Map and Dungeons are placeholders for later phases. The P0 probe is still here, unchanged, in its own small window.

## What P1 does

- **Main window** (880x680, the mockup's size; it shrinks on small screens, never grows). Opens at screen centre, drag it by its frame (edge art, title plate, footer bar or any ornament, in every theme), the position is saved to SavedVariables. **Reset window position** is in the window's Settings popover (click outside the pop or Esc closes it), in the AddOns page of Settings (Dark Matter), and `/dm reset`. Esc closes it.
- **Left tab rail:** Quests, Journals, Map, Dungeons. The last tab you used is remembered.
  - **Quests** lists your quest log from `C_QuestLog` (read only): zone headers with +/- to collapse, quest rows coloured by level difficulty, and a detail panel with level, zone, status and objectives. **All** collapses or expands every zone. The window never touches Blizzard's quest log.
  - **Journals → Fishing** shows skill, a Waters list (Ready/Locked + logged catch counts / per-item zone %), and a Statistics panel (casts, rate, junk/good, rares, time, streak, gold, got-away, favorite zone/lure, skill history). Stats are per-character (`DarkMatterCharDB`) from your first cast. (Adventure Guide since 0.3.0 and Achievements since 0.4.0: see below.)
  - **Fishing → Catches → Show all** lists the static catalog (`Data_FishingCatches.lua`, 121 sourced entries; `classicOnly` ones appear only if `C_Item.DoesItemExistByID` confirms them on your client) plus the per-account **learned catalog** (`DarkMatterDB.fishingCatalogLearned`: any fished item not in the static catalog, with icon, quality, first zone and date) plus your own catches, deduped by item id. Caught first, then learned, then the rest. The header shows "Catalog: N items, M caught". Hovering any row (caught, learned or uncaught) shows the item tooltip plus Dark Matter lines: caught count and last zone/coords, or "Not caught yet" with typical waters and skill. Regenerate the static file with `python3 tools/catalog/gen_catalog.py`.
  - **Map** and **Dungeons** show a "coming in a later phase" page.
- **Minimap button** (round, Dark Matter icon): click toggles the main window, drag moves it around the minimap edge, right-click resets the window position.
- **Probe** (`/dm probe`) is the 0.0.4 probe, unchanged; its report opens in a separate small stock window.
- **Slash commands**

  | Command | What it does |
  |---|---|
  | `/dm` | toggle the main window |
  | `/dm probe` | run the probe (below); opens the probe report window |
  | `/dm fishcheck` | compare the fishing catalog with the client's item names; saves the mismatch list to `DarkMatterDB.fishcheck` |
  | `/dm tipdebug` | toggle logging of fishing tooltip placement (final points and rects of GameTooltip, ShoppingTooltip1/2 and the item icon) to `DarkMatterDB.tipdebug`, with a short chat summary |
  | `/dm raw` | show or hide the raw call list in the probe window |
  | `/dm blocked` | list recorded blocked actions |
  | `/dm reset` | reset window position (`/dm reset all` also puts the minimap button back) |
  | `/dm minimap` | show or hide the minimap button |
  | `/dm icon` | switch the minimap icon between the Dark Matter icon and a stock Blizzard icon |
  | `/dm options` | open the Settings page |
  | `/dm theme`, `/dm theme <name>`, `/dm theme next` | list, apply or cycle the 10 themes |
  | `/dm help` | list commands |

Safety: stock Blizzard frame types only (Frame, Button, ScrollFrame, Slider, Texture, FontString). No secure frames, no hooks on Blizzard code, no `LoadAddOn` of Blizzard UIs, nothing changed in combat. Events live on private frames; quest events are registered only while the Quests tab is showing. The Settings page is registered one frame after login (`C_Timer.After(0)`). The 0.0.4 blocked-action logger is kept.

## Quests tab (0.4.5)
Quest list on the left with a toolbar on top (All, Track Quest, search at the far right). The selected quest's details are on the right, laid out like the game's quest log.

**Quest APIs used (feature-detected; each falls back as listed):**
- Log and objectives: `C_QuestLog.GetNumQuestLogEntries` + `C_QuestLog.GetInfo` for the list (no other fallback; without them the list is empty), `C_QuestLog.GetQuestObjectives` (else `GetNumQuestLeaderBoards` + `GetQuestLogLeaderBoard`), `C_QuestLog.GetLogIndexForQuestID` (else `GetQuestLogIndexByID`, else the log index read with the list).
- Text and rewards: `GetQuestLogQuestText`, `GetQuestLogRewardXP`, `GetQuestLogRewardMoney`, `GetQuestLogRequiredMoney`, `GetNumQuestLogRewards` / `GetQuestLogRewardInfo`, `GetNumQuestLogChoices` / `GetQuestLogChoiceInfo`, `GetQuestLogItemLink`, `GetQuestLogRewardSpell`, `GetQuestLogRewardHonor`, `GetQuestLogRewardTitle`, `GetNumQuestLogRewardFactions` / `GetQuestLogRewardFactionInfo`, `GetQuestLogGroupNum`.
  - These read the *selected* log entry, so Dark Matter selects with `SelectQuestLogEntry` and always restores the previous `GetQuestLogSelection()`.
  - Results are cached per quest; a read is retried (up to 3 times) while item names are still loading.
  - Anything missing reads "Not available from this client."
- Money: `GetCoinTextureString`, else coin icons from `Interface\MoneyFrame`.
- Item tooltip: `GameTooltip:SetQuestLogItem`, else `SetHyperlink` (item link), else `SetItemByID`.
- Watch list:
  - Calls: `C_QuestLog.AddQuestWatch` / `RemoveQuestWatch` / `IsQuestWatched` / `GetQuestWatchType` (questID), else the classic `AddQuestWatch` / `RemoveQuestWatch` / `IsQuestWatched` (log index).
  - Cap: `C_QuestLog.GetMaxNumQuestsCanWatch`, else `MAX_WATCHABLE_QUESTS`; count from `GetNumQuestWatches`.
  - After a change, `QuestWatch_Update` (classic) or `WatchFrame_Update` is called. `ObjectiveTracker_Update` is never called from addon code, because it holds secure buttons; that tracker updates itself from `QUEST_WATCH_LIST_CHANGED`.
  - The boxes re-sync on `QUEST_WATCH_LIST_CHANGED`, `QUEST_WATCH_UPDATE`, `QUEST_LOG_UPDATE`, `QUEST_ACCEPTED`, `QUEST_REMOVED` and `QUEST_TURNED_IN`.
  - In combat, changes are queued until `PLAYER_REGEN_ENABLED`.

**Limits:**
- The 1.x quest-log API has no quest giver, turn-in NPC or quest-chain name. Search finds NPCs only when the objective or description text names them.
- Only quests in your log are listed.
- Whether the client's objective tracker ("All Objectives") follows the quest watch list depends on the client. Check with `/dm questprobe` and by ticking a box in game.

## Theme layer (data, not code)

Art and layout live in theme data; the window code never branches on a theme id. Ten themes ship (0.4.2): **WoW** (default) and the nine class themes from the previewer: Warrior, Paladin, Hunter, Rogue, Priest, Shaman, Mage, Warlock, Druid.

**Picking a theme** (applies live, saved account-wide in `DarkMatterDB.theme`, re-applied at load):
- the window's **Settings** popover: a 2x5 grid of theme buttons, the current one highlighted;
- the stock **Settings > AddOns > Dark Matter** page (Settings canvas API): the same 10 themes as stock buttons;
- `/dm theme` lists them, `/dm theme <name>` applies one, `/dm theme next` cycles (the slash stand-in for the previewer's Ctrl+Alt+T dev cycle).

No dropdown menus (`UIDropDownMenu`/`EasyMenu`) anywhere; only plain Buttons, Textures and FontStrings.

- `Theme.lua`: registry (`NS.RegisterTheme`, with `base = "wow"` inheritance), skin hooks (`NS.OnSkin`, `NS.SetTheme`), piece helpers (`NS.SetPiece`, `NS.Color`, `NS.Metric`), flat looks (`NS.FlatSpec`, `NS.PaintFlat`) and surfaces (`NS.ApplySurface`).
- `Theme_WoW.lua`: the default `wow` theme: colours, metrics (in mockup pixels), tab glyphs and the media paths.
- `Atlas_WoW.lua`: generated; the rectangles of the 58 pieces inside `Media/wow-atlas.tga`.
- `Theme_Classes.lua`: generated by `tools/themes/make_class_textures.py`; the nine class themes as data. Each one shares the WoW layout and adds:
  - colours from the previewer's resolved `--dm-*` variables;
  - `flat`: gradient + 1px border looks for buttons, tabs, pills, badge, pane borders and the selection highlight (where the previewer uses CSS gradients);
  - `surface`: the class texture, tinted, for the window shell, and the previewer's flat colours for the rail, lists and page;
  - `classArt`: the frame and overlay art, corner ornaments, crest and base plate (no backdrop since 0.4.3), plus the class footer layout.
- `Widgets.lua`: 3-slice and 9-slice builders (flat in class themes), buttons, tabs, pills, a custom scrollbar, bars (bar colours are theme keys).
- `Window.lua`: the class art layer. The previewer's 880x680 art space is mapped onto the window's shell box. The frame bands sit under the content; the overlay, ornaments, crest and base sit on a no-mouse child frame above it. The WoW-only chrome (frame border, title plate, medal, footer tint, quest-log head row) is hidden in class themes, as in the previewer.

Regenerate the class themes with `python tools/themes/dump_theme_vars.py` (Chromium, reads the previewer) and `python tools/themes/make_class_textures.py`.

**Text contrast (0.4.4).** Every label must reach 4.5:1 against what is drawn under it (3:1 for 18px+ titles; outlined text is scored against its outline), in all 10 themes, every view, with every button hovered. `tools/stubtest/contrast.lua` (run by the stub tests) composites the real textures, and previewer check DM-35 measures screenshots taken with the text made transparent. Colour keys added for it: `btnInk` (button faces; `gold` is the surface accent), `card` / `cardOn` (achievement cards), `listBg` (the list colour `NS.Legible` aims at, for fixed item-quality colours), `fieldBg` (search boxes and the AG dropdown), `hoverEdge` (the 1px hover edge) and `barText` (outlined bar and badge numbers). The hover tint is drawn under the label and moves away from the label ink. Fix a failing role at the source (the previewer theme data), then regenerate.

## Textures

Only the previewer's generated raster art is used. `tools/make_wow_textures.py` crops and packs it into power-of-two, uncompressed 32-bit TGA files in `Media/`:

| File | Size | Use |
|---|---|---|
| `wow-atlas.tga` | 1024x512 | frame corners/edges, title plate, buttons, tabs, scrollbar, glyphs, pane borders (3-slice and 9-slice pieces) |
| `wow-parchment.tga` | 1024x1024 | page background (stretched) |
| `wow-slate.tga` | 512x256 | window and rail background (stretched) |
| `dm-icon.tga` | existing | minimap icon |
| `cls-<class>-fc.tga` | 512x512 x9 | class frame corners at the source density (2 texels per px), fading into the edge strips |
| `cls-<class>-ftb.tga`, `-flr.tga` | 512x512 x9 each | seamless top/bottom and left/right frame edge tiles, drawn with REPEAT texcoords (sharp, not stretched) |
| `cls-<class>-oc.tga`, `-os.tga` | 512x512, 512x64..512 x9 | overlay corners and overlay edge sprites (glows, vines, crystals), drawn in place above the content |
| `cls-<class>-parts.tga` | 512x256 x9 | 4 corner ornaments, crest, base plate, shell texture |

Inactive pill pieces are repaired during packing (the generated `ptab-i-*` art had a transparent band under the bezel). Regenerate with `python tools/make_wow_textures.py [art dir] [previewer themes.js] [addon dir]`.

## Running the probe (unchanged since 0.0.4)

1. Copy the `DarkMatter` folder into your AddOns folder (Mac: `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/`). If the game is running, type `/reload`; if it doesn't show Dark Matter 0.0.4 in the addon list, quit and relaunch once.
2. Type `/dm probe`. The probe window opens with a **summary: one line per area**, each marked `[OK]` (data came back), `[EMPTY]` (the call works but returned nothing) or `[MISSING]` (the API isn't there), with counts. The summary is short enough for one screenshot (scroll with the mouse wheel if needed).
3. Wait about 5 seconds, then screenshot again: the **Items on demand** line updates once the game has had time to load item data ("[after 3s]").
4. Optional: `/dm raw` shows or hides the full list of raw call returns in the window.
5. For the complete data, type `/reload` (or log out) and share `World of Warcraft/_classic_beta_/WTF/Account/<YOUR ACCOUNT>/SavedVariables/DarkMatter.lua`. The raw returns of every call are in `DarkMatterDB["probe"]["calls"]`. Only read or send that file; nothing else in `WTF` needs touching.

Best results: run `/dm probe` once standing in a city or open world, and once inside a dungeon (the instance lines then show real values).

### What the probe checks (0.0.4, read-only)

| Area | What it tests |
|---|---|
| Quests / Fishing / Achievements | `C_QuestLog` counts, `GetProfessionInfo` Fishing skill, achievement points and categories (no UI is loaded) |
| Journal API | which `EJ_*` functions and `C_EncounterJournal` functions exist |
| Journal data (no UI) | read-only: tiers, instance counts for the current tier, well-known instance IDs, bosses by instance, loot reads for the current selection. It no longer opens, closes or selects anything in the stock journal |
| Map discovery | dungeon child maps of the world map, dungeon entrances and encounters on your current map |
| LFG / dungeons | `C_LFGInfo`, `GetLFDChoiceOrder`, category entries, a scan of dungeon IDs 1 to 1300 with boss counts |
| Saved instances | `GetNumSavedInstances`, `GetSavedInstanceInfo`, `GetInstanceInfo` |
| Items (read-only) | a few well-known classic item IDs plus one that does not exist: `DoesItemExistByID`, `GetItemInfoInstant`, `C_Item.GetItemInfo`, tooltip lines, checked now and again after 3 seconds; it no longer asks the server to load items |
| Loot learning | which loot and boss-kill events the client lets an addon register, and whether the loot APIs exist |
| Game rules | every game rule the client knows, which are active, and which addon restrictions (Combat, Encounter, Map, ...) are active |

Every call is wrapped in `pcall`, secret values are never compared, and nothing opens a window other than Dark Matter's own. The probe never loads Blizzard UI, never changes Encounter Journal state, never requests data from the server, refuses to run in combat, and registers events only on its own private frame.

### About SavedVariables on the beta

Early notes on this beta say the client sometimes does not load saved variables back in. The report line **"SavedVariables: loadCount=... loaded from disk: YES/NO"** tells us.

## Development checks

- `tools/stubtest/mock.py` runs the real addon code in a strict stub client (bad argument types raise like the game; every anchor, size, `SetTexCoord`, frame level and draw layer is modelled). It asserts that every texcoord is within 0..1 with left < right and top < bottom, that every drawn texture is anchored with a non-zero size and no larger than the window, that the window border is exactly 8 pieces spanning corner to corner, that content frames sit above the window art, and that the atlas table matches the real TGA sizes.
- With `MODE=full DM_RENDER_DIR=out`, it also writes `layout-<tab>.json`; `tools/render_preview.py layout-quests.json DarkMatter out.png` composites the window from the same TGAs and texcoords the Lua uses, so the layout can be checked without the game.

## Achievements (0.4.0, layout and per-character in 0.4.1)

**Journals → Achievements** (0.4.1 layout):
- **Top:** a summary bar for this character: Dark Matter points and Legacy Points, each with a progress bar.
- **Left:** search and a Filter button (All / Earned / Not yet) above a collapsible category tree. The game's categories are nested by parent (Classes > Druid), and Dark Matter has its own section with 6 categories. Search covers every category and shows match counts in the tree.
- **Right:** cards with icon, name, description, points badge, earned date, and a progress bar while in progress. Unearned cards are muted. Click a card to expand its criteria in place.

Everything counts for **the current character only**. A game achievement another character earned shows muted as "Not yet (earned on another character)". It is not counted as earned, and not in the counts, the badge or Legacy Points.

- **Legacy Challenges (game data).** Forever 1.60.1 keeps the stock achievement API (`GetCategoryList`, `GetCategoryInfo`, `GetCategoryNumAchievements`, `GetAchievementInfo`, `GetAchievementNumCriteria`, `GetAchievementCriteriaInfo`, `ACHIEVEMENT_EARNED`, `CRITERIA_UPDATE`); Blizzard's own Forever UI (`Blizzard_LegacySystem`, wow-ui-source `forever` branch) reads Legacy Challenges through it. Those are 0-point achievements worth 1 Legacy Point each (`C_Traits.GetTraitCurrencyForAchievement(4225, id)`), account-wide. We read them only (no Blizzard UI is loaded) and show them only when the client returns data; "[DNT]"/placeholder rows are skipped.
- **Dark Matter (our own set, 50 achievements, per character).** General (levels), Quests, Dungeons and Raids, Fishing, Exploration, Loot. Tracked from install on a private event frame (no hooks): `PLAYER_LEVEL_UP`, `QUEST_TURNED_IN`, `ENCOUNTER_END` + `BOSS_KILL` (and, as a fallback, looting a boss corpse, matched to the npc ids in our Wowhead-Forever-cited `Data_Dungeons`; since 0.4.1 the restricted combat log is never touched), the Fishing module's catch log, your own `CHAT_MSG_LOOT` lines (the client's own format strings), zone/instance changes and `PLAYER_MONEY` gains. Saved in `DarkMatterCharDB.ach` (counters, earned dates, criteria). Nothing is awarded retroactively except your current level, which the game confirms; those show "at install". A small toast (our own frame) and a chat line announce each new one.
- **Mode** (`/dm achprobe` prints it with the API counts, 3 game samples and the Dark Matter totals; saved to `DarkMatterDB.achprobe`): `game+dm` when the API has data but is thin (Forever's Legacy Challenges), `dm` when the client returns no achievement data, `game` when the API carries a full set (300+ achievements with points); ours is then off.

## Adventure Guide data (0.3.0 to 0.3.4)

0.3.4: an alias map in our data maps the client's LFG names to our entries ("Stormwind Stockades" -> The Stockade, "Zul'Farak" -> Zul'Farrak, "Onyxia" -> Onyxia's Lair). "Scarlet Monastery" is the parent of the four SM wings, which stay separate in the dropdown. Matching is normalized (case, punctuation, a leading "The") with a unique loose fallback for small variants. `/dm agscan` reports "M of N match our list", the alias mappings, and an informational "ours only" line for our entries the LFG list lacks.

0.3.3: dropdown entries are indented 12px under flush-left gold "Dungeons" / "Raids" headers, which are not clickable. The open dropdown closes on any click outside it, on Esc and when the window hides, and the button still toggles it. This uses our own full-screen catcher frame plus `GLOBAL_MOUSE_DOWN` on a private frame, with Esc through `UISpecialFrames`, and no hooks.

0.3.2: the dropdown always lists our known-good list of **36 instances (29 dungeons, 7 raids)**: every Classic dungeon and raid (SM and Dire Maul by wing) plus the Forever-only Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands and City of Dalaran. Names and level ranges cite Wowhead WoW Forever (`https://www.wowhead.com/forever/zone=<id>`; the levels are Forever's, e.g. RFC 15-25). Wings and Forever instances with no zone level cite `levelSrc` (fallback: warcraft.wiki.gg, the Wowhead Forever guide, or wowseer.gg for Excavation Site and Dalaran). All 289 bosses are confirmed on Forever. Drops are seeded for 24 Classic dungeons (470 Forever-validated items). Items Forever's database doesn't have yet are left out (469). Raids and Forever-only instances are boss lists only for now ("drops coming soon"). Live LFG rows merge by name or alias ("Scarlet Monastery - Graveyard", "Stormwind Stockade", "Dire Maul - East"). Real LFG dungeons that aren't in our list are kept even with no encounters. Only zones, battlegrounds, random queues and placeholders are filtered out. `/dm agscan` prints and saves (`DarkMatterDB.agscan.noBosses`, `.notInList`) the kept rows that report no LFG bosses and the ones not in our list. The list and seed are generated by `tools/dungeons/resolve_forever.py` and `gen_dungeons.py` from `catalog.json` and checked by `verify_forever.py`.

0.3.1: dungeons come from the LFG rows that are real dungeons/raids only. Zones, battlegrounds, world PvP, empty and placeholder rows are rejected, and placeholder boss names ("No Longer in Use", UNUSED, [PH], zzOld) are dropped. `/dm agscan` writes every LFG row with its kept/rejected reason to `DarkMatterDB.agscan`. Dungeons are picked from a dropdown built from our own frames.

- Primary source: **Wowhead WoW Forever**. URL format: `https://www.wowhead.com/forever/npc=<npcId>` and `https://www.wowhead.com/forever/item=<itemId>` (cited per boss and per drop in `Data_Dungeons.lua`); database root `https://www.wowhead.com/forever/database`.
- `tools/dungeons/seed.json`: our own dungeon/boss/NPC-ID list. `fetch_wowhead.py` caches each boss's drop list from Wowhead Classic (`https://www.wowhead.com/classic/npc=<id>`, the marked fallback for drop attribution; the Forever HTML pages are not reachable from our tooling). `verify_forever.py` validates every NPC and item against Forever via its tooltip API (`https://nether.wowhead.com/forever/tooltip/{npc|item}/<id>`) and exits non-zero on any missing or renamed entry. `gen_dungeons.py` writes `Data_Dungeons.lua` with Forever names/quality/icons; `gen_preview.py` writes the same data into the previewer.
- No other addon's loot table is used.

## Art

All art is original: the minimap icon (`Media/dm-icon.tga`) was generated procedurally for this addon. The minimap ring and background are stock built-in game textures referenced by path (`Interface\Minimap\...`); no Blizzard art is copied into the addon.

## Files

`DarkMatter.toc`, `Core.lua` (namespace, defaults, blocked-action logger), `Probe.lua`, `Theme.lua`, `Atlas_WoW.lua`, `Theme_WoW.lua`, `Theme_Classes.lua`, `Widgets.lua`, `ProbeWindow.lua`, `Window.lua`, `Tab_Quests.lua`, `Data_Fishing.lua`, `Data_FishingCatches.lua`, `Fishing.lua`, `Data_Dungeons.lua`, `AdventureGuide.lua`, `Achievements.lua`, `Journal_Achievements.lua`, `Tab_Journals.lua`, `Tab_Stub.lua`, `Minimap.lua`, `Options.lua`, `Slash.lua`, `Media/*.tga`.

### Blocked-action log (0.0.4)

If the client ever reports "DarkMatter has been blocked from an action only available to the Blizzard UI", Dark Matter records the blocked function and the probe step that was running in `DarkMatterDB["blockedLog"]` (also shown as `DarkMatterDB["probe"]["blocked"]`). The probe summary ends with a `[BLOCKED]` line when something was logged, and `/dm blocked` lists the latest entries. Since 0.4.1 it prints `last blocked function: <name>` first, then the time, combat state, the Dark Matter context (which handler was running) and up to 6 lines of Lua stack. `/dm blocked clear` empties it. Screenshot that output if it happens.
