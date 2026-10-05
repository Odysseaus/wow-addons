# QuestGrind

In-game quest HUD for WoW Forever — prettier than alt-tabbing a guide. Modes **Full / Less / Compass**. **Ask SI** via a desktop companion.

## Status

**P1 live questing** — reads the player quest log, prioritizes incomplete quests, updates distance/compass, and draws simple map + minimap route markers when coordinates are known. Falls back to mocked Barrens Loop when the log is empty (or `/qg mock`). Ask bridge = **P2**. Hide Blizzard objectives = **P3**. Art polish (TGA) = **P4**.

## Install

Copy the `QuestGrind/` folder into `Interface/AddOns/`.

- Interface: **16001**
- Slash: `/questgrind` or `/qg`

## Modes

| Mode | What you see |
|------|----------------|
| **Full** | Route, current step, tracker, compass, status, Ask SI |
| **Less** | Compact step + distance + progress + mode chrome |
| **Compass** | Direction rose + distance |

Cycle with `/qg mode` or the mode control on the HUD. Movable when unlocked (`/qg lock`). Minimize via the HUD button.

## Live vs mock

- **Live** (default): enumerates accepted quests via `C_QuestLog` when present, else legacy `GetQuestLog*`. Incomplete first; objectives preferred; selection stays stable across refreshes.
- **Mock fallback**: if the log is empty, HUD shows the P0 Barrens Loop mock.
- **`/qg mock`**: force mock on/off (saved in `QuestGrindDB.forceMock`).
- **`/qg refresh`**: force a live refresh (clears force-mock).

Distance/bearing need objective coordinates (quest POI / waypoint APIs). When Forever does not expose coords, distance shows `?` and the zone name is used; compass stays idle.

## Themes

**Default** gold/wood plus Forever class themes: warrior, paladin, hunter, rogue, priest, shaman, mage, warlock, druid.

- Themes apply to **Full AND Less AND Compass** (not Full-only).
- Pick in **Edit Mode** (edit button / `/qg edit`).
- Identity is **colors / materials / motifs** — no class names baked into art textures.
- P0/P1 use solid-color `SetColorTexture` layers; TGA/wood/gold polish is **P4**.

## Layered UI

Every visual piece is its own `Frame` (outer chrome, title, quest-bang emblem, route row, current step, tracker, compass, status, Ask SI button, edit/mode controls, etc.) so pieces can be moved later inside the QuestGrind window.

The **root container is larger than the art** with transparent padding (`PAD = 24`) so ornate edges never clip.

## Ask SI

The **Ask SI** button opens a stub dialog.

- First AI providers: **xAI** and **Claude**
- Companion: **recommend extend WoWGrok** (shared bridge / Screen Recording) — one app install, less Gatekeeper pain
- P0/P1 stubs Ask; **P2** wires the bridge. API keys stay on the companion disk/Keychain — **never in Lua**

## Releases

- Tags: `quest-grind-v*`
- Zip root folder: `QuestGrind/`
- **`make_latest: false`** — do **not** touch `/releases/latest` (owned by wow-grok-win)
- Flow: PR → Odysseaus **Approve** → merge → publish zip. No silent merge.
- **Win/Mac companion release HOLD** for this P1 — no `quest-grind` release tag yet.

## Slash commands

```
/questgrind (alias /qg)
  show | hide | mode | theme <id> | edit | lock | ask | min
  refresh | mock | next | prev | reset | help
```

Theme ids: `default`, `warrior`, `paladin`, `hunter`, `rogue`, `priest`, `shaman`, `mage`, `warlock`, `druid`.

## Layout in repo

```
quest-grind/
  README.md
  CHANGELOG.md
  QuestGrind/          ← zip root / AddOns folder name
    QuestGrind.toc
    Core.lua
    Themes.lua
    MockData.lua
    Quests.lua         ← P1 live log
    Route.lua          ← P1 distance/compass ticker
    Map.lua            ← P1 world map + minimap
    UI.lua
    EditMode.lua
    AskSI.lua
```

## Phased delivery

| Phase | Scope |
|-------|--------|
| **P0** | Scaffold (done) |
| **P1** | Live quest log, distance/compass, map pins ← **this** |
| **P2** | Ask SI + companion bridge (extend WoWGrok) |
| **P3** | Hide Blizzard objectives; profession objectives option |
| **P4** | Art polish (TGA/wood/gold) |
