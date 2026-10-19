# Dark Matter (P0 scaffold)

**Version 0.0.1** · Interface `16001` (World of Warcraft: Forever beta, `_classic_beta_`) · Author: Odysseaus

Dark Matter will be a dark, one-window overview of your quests, fishing, dungeons and achievements. **P0 is only the scaffold**: it adds a minimap button, a plain placeholder window, and a probe that checks which Blizzard APIs this client really has, so P1 can be built on facts instead of guesses. It does nothing else yet.

## What P0 does

- **Minimap button** (round, Dark Matter icon). Click it to open or close the window. Drag it around the minimap edge; the angle is saved. Right-click resets the window position.
- **Placeholder window** (a stock Blizzard frame, not the final design). Opens at screen centre, drag it to move it, the position is saved. **Reset window position** button in the window, in the AddOns page of Settings (Dark Matter), or `/dm reset`.
- **Slash commands**

  | Command | What it does |
  |---|---|
  | `/dm` | toggle the window |
  | `/dm probe` | run the probe (below) |
  | `/dm reset` | reset window position (`/dm reset all` also puts the minimap button back) |
  | `/dm minimap` | show or hide the minimap button |
  | `/dm icon` | switch the minimap icon between the Dark Matter icon and a stock Blizzard icon (use this if the icon ever shows blank) |
  | `/dm options` | open the Settings page |
  | `/dm help` | list commands |

Safety: stock Blizzard controls only. No secure frames, no hooks on Blizzard code, nothing changed in combat. The Settings page is registered one frame after login (`C_Timer.After(0)`).

## Running the probe (please do this once)

1. Copy the `DarkMatter` folder into your AddOns folder (Mac: `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/`), then log in. If the game was already running, fully quit and relaunch it once so the new addon is picked up.
2. In game, type `/reload` (skip if you just logged in), then type `/dm probe`.
3. Chat prints a short report: client version and build, Interface number, whether SavedVariables came back from disk, and for each group (quest log, fishing/professions, Adventure Guide, achievements, Settings, timers, Edit Mode/options) how many APIs are present and which are **MISSING**. The same text shows inside the Dark Matter window (click the minimap button).
4. **Take a screenshot** of the chat and/or the window and send it.
5. Optional but best: the full result is also **saved in SavedVariables**, so you don't have to copy anything out of chat. After `/dm probe`, type `/reload` (or log out) so the game writes the file, then share this file:
   `World of Warcraft/_classic_beta_/WTF/Account/<YOUR ACCOUNT>/SavedVariables/DarkMatter.lua`
   (the probe is under `DarkMatterDB["probe"]`). Only read or send that file; nothing else in `WTF` needs touching.

What the probe checks: `GetBuildInfo` (version, build, date, Interface), the APIs `C_Map`, `C_QuestLog`, `GetNumQuestLogEntries`; fishing/professions `GetProfessions`, `GetProfessionInfo`, `GetSkillLineInfo`; Adventure Guide `EJ_GetNumTiers`, `EJ_SelectTier`, `EJ_GetInstanceByIndex`, `C_EncounterJournal`, `EncounterJournal`; achievements `GetAchievementInfo`, `GetCategoryList`, `GetTotalAchievementPoints`; `Settings.RegisterAddOnSetting`, `Settings.RegisterAddOnCategory`; `C_Timer`; and whether the stock Edit Mode and Options frames exist. It also makes a few harmless read-only calls (quest count, your Fishing skill, number of Adventure Guide tiers, achievement points) to see what real data looks like. It opens no windows and changes nothing.

### About SavedVariables on the beta

Early notes on this beta say the client sometimes does not load saved variables back in. The probe line **"SavedVariables from disk: YES/no"** and a **load #** counter tell us. If it says `no` on every launch, your window position and minimap angle will reset each time you restart the game; that is a client issue, not this addon.

## Art

All art is original: the minimap icon (`Media/dm-icon.tga`) was generated procedurally for this addon. The minimap ring and background are stock built-in game textures referenced by path (`Interface\Minimap\...`); no Blizzard art is copied into the addon.

## Files

`DarkMatter.toc`, `Core.lua` (namespace, defaults), `Probe.lua`, `Window.lua`, `Minimap.lua`, `Options.lua`, `Slash.lua`, `Media/dm-icon.tga`.
