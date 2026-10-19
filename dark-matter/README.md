# Dark Matter (P0.1 scaffold)

**Version 0.0.2** · Interface `16001` (World of Warcraft: Forever beta, `_classic_beta_`) · Author: Odysseaus

Dark Matter will be a dark, one-window overview of your quests, fishing, dungeons and achievements. **P0 is only the scaffold**: it adds a minimap button, a plain placeholder window, and a probe that checks which Blizzard APIs this client really has, so P1 can be built on facts instead of guesses. It does nothing else yet.

## What P0 does

- **Minimap button** (round, Dark Matter icon). Click it to open or close the window. Drag it around the minimap edge; the angle is saved. Right-click resets the window position.
- **Placeholder window** (a stock Blizzard frame with a scrolling report area, not the final design). Opens at screen centre, drag it to move it, the position is saved. **Reset window position** button in the window, in the AddOns page of Settings (Dark Matter), or `/dm reset`.
- **Slash commands**

  | Command | What it does |
  |---|---|
  | `/dm` | toggle the window |
  | `/dm probe` | run the probe (below); opens the scrolling report |
  | `/dm reset` | reset window position (`/dm reset all` also puts the minimap button back) |
  | `/dm minimap` | show or hide the minimap button |
  | `/dm icon` | switch the minimap icon between the Dark Matter icon and a stock Blizzard icon (use this if the icon ever shows blank) |
  | `/dm options` | open the Settings page |
  | `/dm help` | list commands |

Safety: stock Blizzard controls only. No secure frames, no hooks on Blizzard code, nothing changed in combat. The Settings page is registered one frame after login (`C_Timer.After(0)`).

## Running the probe (please do this twice)

**Round 1: the probe**

1. Copy the `DarkMatter` folder into your AddOns folder (Mac: `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/`), then log in. If the game was already running, fully quit and relaunch it once so the new version is picked up. Check Dark Matter is enabled at character select.
2. In game, type `/reload`, then `/dm probe`.
3. The Dark Matter window opens with the full report. It scrolls with the mouse wheel. **Take screenshots** of the top of the report and of the scrolled-down part (use the mouse wheel), or of chat if easier.

**Round 2: does SavedVariables persist?**

4. Type `/reload` again, then `/dm probe` again. Look at the second line of the report:
   `SavedVariables: loadCount=N | loaded from disk: YES/NO | previous session: ... | previous probe present: ...`
   - `loaded from disk: YES`, `loadCount=2` and `previous probe present: YES` means saving works on this client.
   - `NO` and `loadCount=1` again means the client is not loading SavedVariables (a known beta bug); window position and minimap angle will then reset on every restart.
5. Screenshot that too.

**The full report is also saved in SavedVariables** (`DarkMatterDB["probe"]`), so nothing has to be copied from chat. After the probe, `/reload` (or log out) writes the file, then share:
`World of Warcraft/_classic_beta_/WTF/Account/<YOUR ACCOUNT>/SavedVariables/DarkMatter.lua`
(only read or send that file; nothing else in `WTF` needs touching).

### What the probe does (0.0.2)

1. **Loads the Encounter Journal and Achievement UI on demand** (`Blizzard_EncounterJournal`, `Blizzard_AchievementUI`) with the stock `LoadAddOn`, guarded with `pcall`, then re-checks their frames.
2. **Checks API presence** by group (quest log, fishing/professions, Adventure Guide, achievements, Settings, timers, Edit Mode/options). Optional APIs (`GetMinimapShape`, `GetNumQuestLogEntries`, `InterfaceOptionsFrame`, ...) are shown as "optional absent", not MISSING.
3. **Quest log:** `C_QuestLog.GetNumQuestLogEntries` and `C_QuestLog.GetInfo(1)` as replacements for the missing global.
4. **Fishing skill:** `GetProfessions` + `GetProfessionInfo` (and `C_TradeSkillUI.GetProfessionInfoBySkillLineID`), and it records which function actually produced skill and maximum.
5. **Adventure Guide:** tiers, how many dungeons and raids per tier, one sample instance, its boss count, `EJ_GetEncounterInfo`, and loot (`EJ_GetNumLoot`, `EJ_GetLootInfoByIndex`) for one sample boss. It uses the stock selection calls and puts your tier selection back afterwards.
6. **Achievements:** total points, categories, `GetAchievementInfo` for a sample achievement.
7. **Raw returns:** every call's return types (and short values) are listed at the end of the report and saved under `DarkMatterDB.probe.calls`, so we learn what exists without guessing.

It opens no windows other than the Dark Matter window and changes nothing else.

### About SavedVariables on the beta

Early notes on this beta say the client sometimes does not load saved variables back in. The report line **"SavedVariables: loadCount=... loaded from disk: YES/NO"** tells us.

## Art

All art is original: the minimap icon (`Media/dm-icon.tga`) was generated procedurally for this addon. The minimap ring and background are stock built-in game textures referenced by path (`Interface\Minimap\...`); no Blizzard art is copied into the addon.

## Files

`DarkMatter.toc`, `Core.lua` (namespace, defaults), `Probe.lua`, `Window.lua`, `Minimap.lua`, `Options.lua`, `Slash.lua`, `Media/dm-icon.tga`.
