# Changelog

## 0.2.3 — P1 fix set

- **Rewards + type**: focused live quest shows **Dungeon** or **World** and a short reward line (XP, money, item names) under Current Step, on the Less subtitle, and in the status/XP line.
- **Focus**: watched (checked) incomplete quests win. None checked → closest incomplete. One checked → that quest. Several checked → closest of those. No coords sorts as farthest so a positioned quest wins; if nobody has coords, log order is kept. `/qg next` and `/qg prev` cycle that candidate set until the quest completes, drops, or the watch set changes.
- **Minimap / map**: objective lookup also tries waypoint-for-map, world-map area, task info, and world-yard → normalized conversion. A live focus always shows a minimap pointer — edge arrow with a gold `!` when the bearing is known, center quest-bang when it is not. World map pin uses normalized or converted coords.
- **Compass**: the 0.25s tick recomputes distance and re-probes POI when coords are missing (full log enumerate about once a second). Needles nudge as well as rotate, including the compass-only face while Full is hidden. No coords shows `Zone · ?` instead of a stale mock distance. With no facing API the needle uses absolute bearing vs north.
- Root causes: focus preferred “has objectives” over the tracker and distance; pins and the minimap arrow hid whenever `hasCoords` was false and world yards never became a map pin; the compass tick bailed out before POI was retried and `SetRotation` on a solid needle did not reliably move.

## 0.2.2 — Theme-stick fix

- **Theme stick**: switching themes then returning to a previous theme now always re-applies that theme’s chrome **and** panel/content colors (no more “play it back and forth to recover”).
- **Contrast**: chrome vs inner panel can no longer collapse into the same muddy color after repeated switches.
- Root cause: solids were baked with `SetColorTexture(themeRGB)` and re-themed by calling `SetColorTexture` again; on Forever that re-apply was flaky / could leave a vertex multiply on an old baked solid. Fix: white solid base + `SetVertexColor` tint on every apply (`Themes.lua` helper; `Solid`/chips/dialogs match).
- In-game check for chrome controls: Move / Mode / Edit / Min / X stay as separate clickable buttons and don’t visually melt into one solid blob with the panel — hover each and see separate hit targets.


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
