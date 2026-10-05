# Changelog

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
