# Dark Matter (P0.2 probe)

**Version 0.0.3** · Interface `16001` (World of Warcraft: Forever beta, `_classic_beta_`) · Author: Odysseaus

Dark Matter will be a dark, one-window overview of your quests, fishing, dungeons and achievements. **P0 is only the scaffold**: it adds a minimap button, a plain placeholder window, and a probe that checks which Blizzard APIs this client really has, so P1 can be built on facts instead of guesses. It does nothing else yet.

## What P0 does

- **Minimap button** (round, Dark Matter icon). Click it to open or close the window. Drag it around the minimap edge; the angle is saved. Right-click resets the window position.
- **Placeholder window** (a stock Blizzard frame with a scrolling report area, not the final design). Opens at screen centre, drag it to move it, the position is saved. **Reset window position** button in the window, in the AddOns page of Settings (Dark Matter), or `/dm reset`.
- **Slash commands**

  | Command | What it does |
  |---|---|
  | `/dm` | toggle the window |
  | `/dm probe` | run the probe (below); opens the summary window |
  | `/dm raw` | show or hide the raw call list in the probe window |
  | `/dm reset` | reset window position (`/dm reset all` also puts the minimap button back) |
  | `/dm minimap` | show or hide the minimap button |
  | `/dm icon` | switch the minimap icon between the Dark Matter icon and a stock Blizzard icon (use this if the icon ever shows blank) |
  | `/dm options` | open the Settings page |
  | `/dm help` | list commands |

Safety: stock Blizzard controls only. No secure frames, no hooks on Blizzard code, nothing changed in combat. The Settings page is registered one frame after login (`C_Timer.After(0)`).

## Running the probe (0.0.3)

1. Copy the `DarkMatter` folder into your AddOns folder (Mac: `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/`). If the game is running, type `/reload`; if it doesn't show Dark Matter 0.0.3 in the addon list, quit and relaunch once.
2. Type `/dm probe`. The window opens with a **summary: one line per area**, each marked `[OK]` (data came back), `[EMPTY]` (the call works but returned nothing) or `[MISSING]` (the API isn't there), with counts. The summary is short enough for one screenshot (scroll with the mouse wheel if needed).
3. Wait about 5 seconds, then screenshot again: the **Items on demand** line updates once the game has had time to load item data ("[after 3s]").
4. Optional: `/dm raw` shows or hides the full list of raw call returns in the window.
5. For the complete data, type `/reload` (or log out) and share `World of Warcraft/_classic_beta_/WTF/Account/<YOUR ACCOUNT>/SavedVariables/DarkMatter.lua`. The raw returns of every call are in `DarkMatterDB["probe"]["calls"]`. Only read or send that file; nothing else in `WTF` needs touching.

Best results: run `/dm probe` once standing in a city or open world, and once inside a dungeon (the instance lines then show real values).

### What the probe checks (0.0.3)

| Area | What it tests |
|---|---|
| Quests / Fishing / Achievements | `C_QuestLog` counts, `GetProfessionInfo` Fishing skill, achievement points and categories (loads the Achievement UI on demand) |
| Journal API | which `EJ_*` functions and `C_EncounterJournal` functions exist |
| Journal data (no UI) | `C_EncounterJournal.InitalizeSelectedTier` and `OnOpen`, then tiers, instance counts per tier, well-known instance IDs, bosses, loot via `C_EncounterJournal.GetLootInfoByIndex`; the stock journal selection is restored afterwards |
| Map discovery | dungeon child maps of the world map, dungeon entrances and encounters on your current map |
| LFG / dungeons | `C_LFGInfo`, `GetLFDChoiceOrder`, category entries, a scan of dungeon IDs 1 to 1300 with boss counts |
| Saved instances | `GetNumSavedInstances`, `GetSavedInstanceInfo`, `GetInstanceInfo` |
| Items on demand | a few well-known classic item IDs plus one that does not exist: `DoesItemExistByID`, `GetItemInfoInstant`, `C_Item.GetItemInfo`, tooltip lines, checked now and again after 3 seconds |
| Loot learning | which loot and boss-kill events the client lets an addon register, and whether the loot APIs exist |
| Game rules | every game rule the client knows, and which are active |

Every call is wrapped in `pcall`, secret values are never compared, and nothing opens a window other than Dark Matter's own.

### About SavedVariables on the beta

Early notes on this beta say the client sometimes does not load saved variables back in. The report line **"SavedVariables: loadCount=... loaded from disk: YES/NO"** tells us.

## Art

All art is original: the minimap icon (`Media/dm-icon.tga`) was generated procedurally for this addon. The minimap ring and background are stock built-in game textures referenced by path (`Interface\Minimap\...`); no Blizzard art is copied into the addon.

## Files

`DarkMatter.toc`, `Core.lua` (namespace, defaults), `Probe.lua`, `Window.lua`, `Minimap.lua`, `Options.lua`, `Slash.lua`, `Media/dm-icon.tga`.
