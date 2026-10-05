# QuestGrind

In-game quest HUD for WoW Forever — prettier than alt-tabbing a guide. Modes **Full / Less / Compass**. **Ask SI** via a desktop companion.

## Status

**P0 scaffold** — mocked Barrens Loop / Smart Drinks data, themed shells, Edit Mode theme picker. Live quest log = **P1**. Ask bridge = **P2**. Art polish (TGA) = **P4**.

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

## Themes

**Default** gold/wood plus Forever class themes: warrior, paladin, hunter, rogue, priest, shaman, mage, warlock, druid.

- Themes apply to **Full AND Less AND Compass** (not Full-only).
- Pick in **Edit Mode** (edit button / `/qg edit`).
- Identity is **colors / materials / motifs** — no class names baked into art textures.
- P0 uses solid-color `SetColorTexture` layers; TGA/wood/gold polish is **P4**.

## Layered UI

Every visual piece is its own `Frame` (outer chrome, title, quest-bang emblem, route row, current step, tracker, compass, status, Ask SI button, edit/mode controls, etc.) so pieces can be moved later inside the QuestGrind window.

The **root container is larger than the art** with transparent padding (`PAD = 24`) so ornate edges never clip.

## Ask SI

The **Ask SI** button opens a stub dialog.

- First AI providers: **xAI** and **Claude**
- Companion: **recommend extend WoWGrok** (shared bridge / Screen Recording) — one app install, less Gatekeeper pain
- P0 stubs Ask; **P2** wires the bridge. API keys stay on the companion disk/Keychain — **never in Lua**

## Releases

- Tags: `quest-grind-v*`
- Zip root folder: `QuestGrind/`
- **`make_latest: false`** — do **not** touch `/releases/latest` (owned by wow-grok-win)
- Flow: PR → Odysseaus **Approve** → merge → publish zip. No silent merge.

## Slash commands

```
/questgrind (alias /qg)
  show | hide | mode | theme <id> | edit | lock | ask | min | reset | help
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
    UI.lua
    EditMode.lua
    AskSI.lua
```

## Phased delivery

| Phase | Scope |
|-------|--------|
| **P0** | This scaffold |
| **P1** | Live quest log, distance/compass, map pins |
| **P2** | Ask SI + companion bridge (extend WoWGrok) |
| **P3** | Hide Blizzard objectives; profession objectives option |
| **P4** | Art polish (TGA/wood/gold) |
