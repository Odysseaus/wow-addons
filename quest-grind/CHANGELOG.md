## 0.2.11 — Blizzard pin as start; QG markers on later chain stops only

- **Changed**: main-map route no longer places a QuestGrind numbered badge on the same spot as a live **Blizzard quest icon** (0.2.10 “QG under Blizzard” made badges invisible / competing).
- **Changed**: accepted / current stop = **Blizzard map quest icon only**; route **lines** still start from that Blizzard pin XY and connect to later chain locations.
- **Changed**: QuestGrind **numbered markers** only on stops **without** a live Blizzard pin (untriggered / upcoming chain steps, or accepted stops with no pin). Multi-quest routes use the same per-stop rule (`Map.lua`: `hasBlizzardPin` via live pin snap + `GetQuestsOnMap`).
- **Keep**: ≤7 stops; no center→#1 line; chain shared order #; per-quest colors; icon clear gap; minimap route dropped; HUD **Current location:** label; prioritization / objectives tick / Full·Less·Compass / solo·2+·empty / reload·relog. Interface **16001**.

# Changelog

## 0.2.10 — Current location label; map markers under Blizzard icons

- **Fixed**: HUD zone line is labeled **Current location** (Full step row + Compass no-coords line) so the place name is not a bare unlabeled string (`UI.lua`).
- **Fixed**: main-map QuestGrind route markers use the same MapCanvas placement as Blizzard quest icons (TOPLEFT + inverted Y; same canvas parent) and prefer `C_QuestLog.GetQuestsOnMap` / live pin snap so stop **#1** sits on the real quest bang (`Map.lua` / `Quests.lua`).
- **Fixed**: QG markers and route lines draw **behind** Blizzard quest icons (canvas strata, low frame level — no TOOLTIP overlay).
- **Keep**: ≤7 stops; no center→#1 line; chain shared order #; per-quest colors; icon clear gap; untriggered markers; minimap route dropped. Interface **16001**.

## 0.2.9 — Route start, chain shared #, per-quest colors

- **Fixed**: no route line from map **center / player** to stop **#1** — the first objective is the **start** of the route (`Map.lua`).
- **Changed**: if a quest has a **chain**, lines start at the first chain quest and continue to the next chain step(s); every location in that chain uses the **same order number** (`Quests.lua` / `Map.lua`).
- **Changed**: each **distinct quest** (not each chain node) gets a **different color** on pins and connecting lines.
- **Keep**: ≤7 stops, lines stop short of icons, untriggered chain markers, minimap route dropped. Interface **16001**.

## 0.2.8 — Main world-map route (drop minimap)

- **Changed**: **Minimap route/pointer dropped** for now — no edge arrow, no bottom focus badge (`Map.lua` stubs are no-ops). Compass HUD needles are unchanged.
- **Added**: **Main world map route** — up to **seven** numbered stops in QuestGrind’s best completion order (focus-candidate order: closest checked / scoped, then upcoming **untriggered chain** steps with a POI inserted after their predecessor).
- **Added**: Route **lines** between player → 1 → 2 → … that **stop short** of quest icon centers (do not overlap Blizzard map quest icons).
- **Added**: QuestGrind **number circles** on every stop; untriggered chain steps (no Blizzard pin yet) get their own numbered marker on the route.
- **Notes**: Interface stays **16001**. Objectives progress tick still deferred.

## 0.2.7 — ChainData GPL fallback, closest-checked focus, no fake 1/1

- **Added**: shipped `ChainData.lua` — questID → chainId/step/total + ordered lists, generated from **QuestieDB Forever** (via [TylerAkins/wow-database](https://github.com/TylerAkins/wow-database) export, commit recorded in `ChainDataMeta`). Quest records are **GPL-3.0**; attributed in this changelog, README, and the file header. `C_QuestLine` is still tried first; ChainData fills misses. Done counts use `C_QuestLog.IsQuestFlaggedCompleted` / `IsQuestFlaggedCompleted`, with a session set from `GetAllCompletedQuestIDs` when present.
- **Fixed**: no chain data no longer shows a fake `1/1`. The Quest Log index reads **—**; the single progress bar uses **objective progress** instead.
- **Fixed**: multiple checked quests → always the **closest checked**, recomputed as the player moves (~1s enumerate). Newly checked no longer pins focus forever. Chain / adopted-successor rules apply only when **nothing** is checked (or the successor itself is checked). `/qg next` / `/qg prev` remain a temporary override until the check set changes or `/qg refresh`. No-coords still sort after coords, then log order.
- **Fixed**: `QuestAreaID` prefers Forever `GetQuestUiMapID(questID)` (legacy world-map area APIs remain as fallbacks).

## 0.2.6 — Chain index + chain progress, checked-chain focus, smooth compass

- **Fixed**: the index next to **Quest Log** is the focused quest's **step in its quest chain** (`C_QuestLine.GetQuestLineInfo` → `GetQuestLineQuests`), e.g. `3/10`. Standalone quests read `1/1`. Root cause: 0.2.3–0.2.5 showed the position in the focus *candidate* list, so it read `1/15` with nothing checked and `1/1` once one quest was checked.
- **Fixed**: focus stays on a **checked chain**. Checked quests remain candidates when **ready to turn in**; after a turn-in, the next step (same quest line, or the quest accepted within 20s of turning in a focused quest) keeps focus even if it is not checked. Focus falls to the nearest quest only when nothing in the log is checked / on a checked chain. Checking a quest (incl. un-check → re-check of a turn-in-ready chain quest) brings it into focus; un-checking drops it. Root cause: candidates were *checked AND incomplete*, so finishing objectives or turning in dropped focus to the nearest quest. `QUEST_WATCH_LIST_CHANGED` now refreshes immediately.
- **Changed**: Quest Log progress (Full and Less) is **one bar** with a centered percentage, same length as the old 5-segment strip. Fill = chain steps complete / steps in chain (current step counts once ready to turn in).
- **Improved**: compass arrow is smoother and more responsive — a per-frame animator re-reads facing every frame and player position ~20×/s, eases toward the target (~0.14s catch-up, big jumps snap), and the rotation deadzone dropped from 0.5° to 0.1°. Text/distance stay on the 0.25s ticker. `Map.lua` bearing unchanged.
- **Deferred**: objectives progress tick; minimap route redesign.

## 0.2.5 — Single Rewards area, simple compass arrow

- **Fixed**: Full mode has one **Rewards** section (header, reward text, item icons). Empty live rewards show **None**. Mock shows **+1240 XP** in that same section. The status column no longer repeats reward text; it shows a quest count ("3 quests" / "1 quest").
- **Fixed**: Each compass face (Full, Less, Compass) is a single arrow toward the focused quest. No live bearing hides the arrow instead of pointing north. Mock `bearingDeg` may still point.
- **Fixed**: Arrow direction math. Bearing is a clockwise compass bearing for both map and world coordinates (world axes: X north, Y west), and the arrow turns by `-bearing - facing` (WoW facing and `SetRotation` are counter-clockwise), so it points at the quest from the player as you turn. The ahead / left / right text uses the same rule.
- **Deferred**: objectives progress tick; minimap route redesign (the minimap edge arrow in `Map.lua` is unchanged).

## 0.2.4 — Item tooltips, minimap route, real needle

- **Item reward hover**: reward items keep `itemID` / texture / link; Full mode shows icon buttons under Current Step. Hover uses `GameTooltip:SetItemByID` (else `SetHyperlink`) like the quest log.
- **Minimap**: removed the center-on-player dead `!`. With coords → edge arrow toward focus. Without coords → bottom focus badge (quest title on hover; never a fake bearing).
- **Compass**: replaced Solid rectangle needles with a geometric tip+tail+hub needle that pivots from face center (sin/cos + glyph). Facing/move updates keep the tip on the focus bearing.
- Root causes: rewards were name-only FontStrings with no item tip; no-coords path pinned a bang on the player; Solid bars + off-center nudge looked like a floating rectangle, not a needle.

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
