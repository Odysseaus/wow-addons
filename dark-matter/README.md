# Dark Matter (P2.8 fishing catalog + item tooltips)

**Version 0.3.2** · Interface `16001` (World of Warcraft: Forever beta, `_classic_beta_`) · Author: Odysseaus

Dark Matter is a one-window overview of your quests, fishing, dungeons and achievements. **P1 builds the real main window**: the WoW theme from the approved previewer mockup, a vertical tab rail on the left, and a working Quests tab. Journals, Map and Dungeons are placeholders for later phases. The P0 probe is still here, unchanged, in its own small window.

## What P1 does

- **Main window** (880x680, the mockup's size; it shrinks on small screens, never grows). Opens at screen centre, drag it by the title plate, the position is saved to SavedVariables. **Reset window position** is in the window's Settings popover (click outside the pop or Esc closes it), in the AddOns page of Settings (Dark Matter), and `/dm reset`. Esc closes it.
- **Left tab rail:** Quests, Journals, Map, Dungeons. The last tab you used is remembered.
  - **Quests** lists your quest log from `C_QuestLog` (read only): zone headers with +/- to collapse, quest rows coloured by level difficulty, and a detail panel with level, zone, status and objectives. **All** collapses or expands every zone. The window never touches Blizzard's quest log.
  - **Journals → Fishing** shows skill, a Waters list (Ready/Locked + logged catch counts / per-item zone %), and a Statistics panel (casts, rate, junk/good, rares, time, streak, gold, got-away, favorite zone/lure, skill history). Stats are per-character (`DarkMatterCharDB`) from your first cast. Adventure Guide and Achievements remain "Coming soon".
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
  | `/dm help` | list commands |

Safety: stock Blizzard frame types only (Frame, Button, ScrollFrame, Slider, Texture, FontString). No secure frames, no hooks on Blizzard code, no `LoadAddOn` of Blizzard UIs, nothing changed in combat. Events live on private frames; quest events are registered only while the Quests tab is showing. The Settings page is registered one frame after login (`C_Timer.After(0)`). The 0.0.4 blocked-action logger is kept.

## Theme layer (data, not code)

Art and layout live in theme data so the nine class themes can be added later without touching the window code.

- `Theme.lua`: registry (`NS.RegisterTheme`), skin hooks (`NS.OnSkin`, `NS.SetTheme`), piece helpers (`NS.SetPiece`, `NS.Color`, `NS.Metric`).
- `Theme_WoW.lua`: the default `wow` theme: colours, metrics (in mockup pixels), tab glyphs and the media paths.
- `Atlas_WoW.lua`: generated; the rectangles of the 58 pieces inside `Media/wow-atlas.tga`.
- `Widgets.lua`: 3-slice and 9-slice builders, buttons, tabs, pills, a custom scrollbar.
- A class theme is a new `Theme_<Class>.lua` + `Atlas_<Class>.lua` + three `Media` files, registered with `NS.RegisterTheme`.

## Textures

Only the previewer's generated raster art is used. `tools/make_wow_textures.py` crops and packs it into power-of-two, uncompressed 32-bit TGA files in `Media/`:

| File | Size | Use |
|---|---|---|
| `wow-atlas.tga` | 1024x512 | frame corners/edges, title plate, buttons, tabs, scrollbar, glyphs, pane borders (3-slice and 9-slice pieces) |
| `wow-parchment.tga` | 1024x1024 | page background (stretched) |
| `wow-slate.tga` | 512x256 | window and rail background (stretched) |
| `dm-icon.tga` | existing | minimap icon |

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

## Adventure Guide data (0.3.0 to 0.3.2)

0.3.2: the dropdown always lists our known-good list of **36 instances (29 dungeons, 7 raids)**: every Classic dungeon and raid (SM and Dire Maul by wing) plus the Forever-only Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands and City of Dalaran. Names and level ranges cite Wowhead WoW Forever (`https://www.wowhead.com/forever/zone=<id>`; the levels are Forever's, e.g. RFC 15-25). Wings and Forever instances with no zone level cite `levelSrc` (fallback: warcraft.wiki.gg, the Wowhead Forever guide, or wowseer.gg for Excavation Site and Dalaran). All 289 bosses are confirmed on Forever. Drops are seeded for 24 Classic dungeons (470 Forever-validated items). Items Forever's database doesn't have yet are left out (469). Raids and Forever-only instances are boss lists only for now ("drops coming soon"). Live LFG rows merge by name or alias ("Scarlet Monastery - Graveyard", "Stormwind Stockade", "Dire Maul - East"). Real LFG dungeons that aren't in our list are kept even with no encounters. Only zones, battlegrounds, random queues and placeholders are filtered out. `/dm agscan` prints and saves (`DarkMatterDB.agscan.noBosses`, `.notInList`) the kept rows that report no LFG bosses and the ones not in our list. The list and seed are generated by `tools/dungeons/resolve_forever.py` and `gen_dungeons.py` from `catalog.json` and checked by `verify_forever.py`.

0.3.1: dungeons come from the LFG rows that are real dungeons/raids only. Zones, battlegrounds, world PvP, empty and placeholder rows are rejected, and placeholder boss names ("No Longer in Use", UNUSED, [PH], zzOld) are dropped. `/dm agscan` writes every LFG row with its kept/rejected reason to `DarkMatterDB.agscan`. Dungeons are picked from a dropdown built from our own frames.

- Primary source: **Wowhead WoW Forever**. URL format: `https://www.wowhead.com/forever/npc=<npcId>` and `https://www.wowhead.com/forever/item=<itemId>` (cited per boss and per drop in `Data_Dungeons.lua`); database root `https://www.wowhead.com/forever/database`.
- `tools/dungeons/seed.json`: our own dungeon/boss/NPC-ID list. `fetch_wowhead.py` caches each boss's drop list from Wowhead Classic (`https://www.wowhead.com/classic/npc=<id>`, the marked fallback for drop attribution; the Forever HTML pages are not reachable from our tooling). `verify_forever.py` validates every NPC and item against Forever via its tooltip API (`https://nether.wowhead.com/forever/tooltip/{npc|item}/<id>`) and exits non-zero on any missing or renamed entry. `gen_dungeons.py` writes `Data_Dungeons.lua` with Forever names/quality/icons; `gen_preview.py` writes the same data into the previewer.
- No other addon's loot table is used.

## Art

All art is original: the minimap icon (`Media/dm-icon.tga`) was generated procedurally for this addon. The minimap ring and background are stock built-in game textures referenced by path (`Interface\Minimap\...`); no Blizzard art is copied into the addon.

## Files

`DarkMatter.toc`, `Core.lua` (namespace, defaults, blocked-action logger), `Probe.lua`, `Theme.lua`, `Atlas_WoW.lua`, `Theme_WoW.lua`, `Widgets.lua`, `ProbeWindow.lua`, `Window.lua`, `Tab_Quests.lua`, `Data_Fishing.lua`, `Data_FishingCatches.lua`, `Fishing.lua`, `Data_Dungeons.lua`, `AdventureGuide.lua`, `Tab_Journals.lua`, `Tab_Stub.lua`, `Minimap.lua`, `Options.lua`, `Slash.lua`, `Media/*.tga`.

### Blocked-action log (0.0.4)

If the client ever reports "DarkMatter has been blocked from an action only available to the Blizzard UI", Dark Matter records the blocked function and the probe step that was running in `DarkMatterDB["blockedLog"]` (also shown as `DarkMatterDB["probe"]["blocked"]`). The probe summary ends with a `[BLOCKED]` line when something was logged, and `/dm blocked` lists the latest entries. Screenshot that line if it happens.
