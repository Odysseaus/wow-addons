# Changelog

## 0.2.1 — P0 UX fix (mode cycle, chrome controls, Ask SI)

Fixes Odysseaus P0 FAIL list (P1 features held; existing P1 modules unchanged):

- **Persistent control strip** (`layers.chromeControls`) on Full, Less, Compass and minimized — excluded from `HideAllContent`, frame level above all content, anchored inside art TOPRIGHT. Compass no longer buries the controls.
- **Mode button** shows `Full` / `Less` / `Compass` (was cryptic `M`); tooltip "Cycle view mode"; left-click next, right-click previous; works from every mode (Compass → Full). Less `modeChrome` kept as a secondary control (moved so it no longer overlaps the strip).
- **Edit** button labeled `Edit` (was `E`) with Edit Mode tooltip.
- **Min / Expand**: `Min` collapses to a small bar; when minimized the strip shows `Expand` + `X`, and the `QuestGrind` bar also expands on click.
- **Close (X)** prints `HUD hidden — type /qg show to bring it back.`; extra gap from Min to avoid misclicks. `/qg show`, `/qg mode <full|less|compass>`, `/qg full|less|compass`, `/qg expand` always recover.
- **Move** grip (top-left) + draggable title; tooltip shows lock state; grip reads `Locked` when `/qg lock` is on. Root clamped to screen.
- **Ask SI** button bigger (220×40, 16pt) and fixed: its border texture was drawn over the fill, hiding the button in the chrome.
- Art sizes adjusted so the strip never overlaps content: Full 400×440, Less 440×128, Compass 240×264, minimized 240×40.
- Single `ApplyLayout()` path for mode + minimize (no Hide() of the root on mode change).

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
