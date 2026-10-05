# Changelog

## 0.2.0 — P1 live questing

- Live quest log read (`Quests.lua`) with C_QuestLog + legacy GetQuestLog* guards for Forever
- Prioritized incomplete quests; stable selected index; `/qg next` / `/qg prev`
- `NS.GetLiveRoute()` / `NS.RefreshLive()` / `NS.Refresh()` — MockRoute-compatible structure
- Distance + compass needle updates on ~0.25s ticker (`Route.lua`)
- World map pin + minimap arrow toward objective when coords known (`Map.lua`)
- Events: QUEST_ACCEPTED / REMOVED / TURNED_IN, QUEST_LOG_UPDATE, UNIT_QUEST_LOG_CHANGED, PLAYER_ENTERING_WORLD, ZONE_CHANGED_*
- Fallback to mocked Barrens Loop when log empty; `/qg mock` toggles force-mock; `/qg refresh` forces live
- Version 0.2.0; Notes updated for P1
- Themes / Edit Mode / Ask SI stub unchanged (P2 bridge still stubbed)

## 0.1.0 — P0 scaffold

- Addon shell under `quest-grind/QuestGrind/` (`## Interface: 16001`)
- Modes: Full / Less / Compass (cycle, movable, minimize)
- Mocked quest data matching mockups (Barrens Loop, Smart Drinks, Lushwater Oasis, etc.)
- Theme system (default + Forever classes) via `SavedVariables: QuestGrindDB`; themes apply to **all three modes**
- Edit Mode theme picker (in-game)
- Ask SI stub dialog (xAI + Claude note; companion = extend WoWGrok)
- Layered UI frames + transparent outer padding (no edge clipping)
- Solid-color themed textures (art polish deferred to P4)
- Release rules documented: tags `quest-grind-v*`, zip root `QuestGrind/`, `make_latest: false`
