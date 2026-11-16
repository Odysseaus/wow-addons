# Valhalla

Valhalla is Odysseaus's own WoW Forever world-map addon, a fork of
[OpenMap](https://github.com/openmap-world/openmap) v0.8.2 by OpenMap contributors,
used under the MIT License (`Valhalla/LICENSE.txt`). Library and art licences are in
`Valhalla/LICENSES/` and `Valhalla/Media/Textures/Forever/NOTICE.md`; OpenMap's credits are kept in
`Valhalla/Credits.lua`.

- Install: copy `Valhalla/` to `_forever_/Interface/AddOns/Valhalla` and turn OpenMap off in the AddOns list.
- Commands: `/valhalla` and `/vh`. Settings: `ValhallaDB` / `ValhallaCharDB`.
- History: the first commit on this folder is the pristine OpenMap v0.8.2 import; the second is the rename.
- Upstream sync (Valhalla 1.2.18): WoW Forever map data and a few fixes taken from OpenMap v0.8.9
  (`9ebb7d3`, 2026-11-14), hand-merged into Valhalla's own files: `Data/Forever/Places.lua` (the
  newest dungeons' entrances by instance ID, their bosses, Group Finder level ranges),
  `DungeonDrawn.lua` with its `MapDungeonDrawn/` textures, `FlightData.lua`, `CaveMinimap.lua` with
  the `MapCave/` and `MapCaveMend/` textures, and OpenMap's fixes #113, #224, #229, #241, #37/#64.
  Data by OpenMap contributors (jigrobbulus, puschie286, Nathan and others), MIT; the dungeon maps
  are drawn by Santiago Reyes (<https://sreyesmaps.com/post/proyecto-atlas-de-azeroth-forever>) and
  used with his permission as in OpenMap, not covered by the MIT licence (see the textures' `NOTICE.md`).
