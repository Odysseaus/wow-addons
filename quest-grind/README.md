# QuestGrind

In-game quest HUD for WoW Forever — prettier than alt-tabbing a guide. Modes **Full / Less / Compass**. **Ask SI** via a desktop companion.

## Status

**P1 live questing (0.2.11)** — reads the player quest log, focuses the **closest checked** quest (recomputed as you move; chain/adopted successor only when nothing is checked), shows the **quest-chain step** (e.g. `Quest Log 3/10`) from `C_QuestLine` or shipped **ChainData** (QuestieDB Forever, GPL-3.0), or **—** with objective % when no chain is known, plus one **Rewards** area (text and **item icon tooltips**), a **compass arrow** toward the focused quest, and a **main world-map route** (up to seven stops; accepted stop = real **Blizzard quest icon** only — no QG badge on that spot; lines from Blizzard pin to later chain steps; QG numbered circles only where there is no live Blizzard pin; first objective is the route **start** — no center→#1 line; chain locations share one order #; each distinct quest a different color; lines stop short of icons). HUD zone line labeled **Current location**. Minimap route/pointer is **off** for now. Falls back to mocked Barrens Loop when the log is empty (or `/qg mock`). Ask bridge = **P2**. Hide Blizzard objectives = **P3**. Art polish (TGA) = **P4**. Interface stays **16001**.

## Install

Copy the `QuestGrind/` folder into `Interface/AddOns/`.

- Interface: **16001**
- Slash: `/questgrind` or `/qg`

## Modes

| Mode | What you see |
|------|----------------|
| **Full** | Route, current step, rewards, tracker, compass, status, Ask SI |
| **Less** | Compact step + distance + progress + mode chrome |
| **Compass** | Direction rose + distance |

### HUD controls (0.2.1+)

An always-visible control strip sits at the top of the HUD in **every** mode (and when minimized):

| Control | What it does |
|---------|--------------|
| **Move** (top-left) | Drag to move. Reads **Locked** when `/qg lock` is on. The title also drags. |
| **Full / Less / Compass** | Mode button — label shows the current mode. Left-click = next, right-click = previous. |
| **Edit** | Opens Edit Mode (theme picker). |
| **Min** / **Expand** | Collapse to a small bar; click **Expand** (or the `QuestGrind` bar) to restore. |
| **X** | Hide the HUD. `/qg show` brings it back (a chat hint is printed). |

Also: `/qg mode [full|less|compass]`, `/qg full`, `/qg less`, `/qg compass`, `/qg expand`.

## Live vs mock

- **Live** (default): enumerates accepted quests via `C_QuestLog` when present, else legacy `GetQuestLog*`. Focus rules (0.2.7):
  - **Checked** = on the Blizzard objective tracker. Several checked → always the **closest checked**, recomputed as you move. Newly checked does **not** pin forever.
  - **Chain / adopted successor** (same `C_QuestLine` / ChainData line, or the quest accepted within ~20s of a scoped turn-in) applies only when **nothing** is checked, or when that successor is itself checked.
  - Unchecking drops that quest from the checked set (and clears sticky/adopt for it). `/qg next` / `/qg prev` temporarily override until the check set changes or `/qg refresh`.
  - Only when **no** quest is checked → closest incomplete (coords beat quests with none; if nobody has coords, log order).
- **Quest Log index / progress**: `Quest Log i/N` is the focused quest's step in its quest chain (`C_QuestLine` first, else shipped **ChainData** from QuestieDB Forever). **No chain data → `—`** (not a fake `1/1`); the bar then follows **objective progress**. With a chain, the bar is steps complete / steps in chain (current step counts once ready to turn in; completed steps use `IsQuestFlaggedCompleted` / `GetAllCompletedQuestIDs`).
- **HUD**: focused quest shows a **Dungeon** or **World** badge. Full mode has one **Rewards** section (header, XP / money / items, or **None**) and **item icons** — hover for a real item tooltip (`SetItemByID` / hyperlink). The status block shows state, last update, and a quest count ("3 quests" / "1 quest"), not a second reward line. Less mode still puts type and rewards on the subtitle.
- **World map route (0.2.11)**: open the main map to see up to **seven** stops in QuestGrind’s best completion order. An accepted stop that already has a live **Blizzard quest icon** keeps that icon only (no QuestGrind numbered badge on the same spot). Route **lines** still run from the Blizzard pin XY to later chain locations. QuestGrind **number circles** appear only on stops **without** a live Blizzard pin (untriggered / upcoming chain steps). The **first objective is the start** of the route (no line from map center / player to #1). Chain locations share the **same order number**; each **distinct quest** gets a **different color**. Lines **stop short** of icons. **Minimap** route/pointer is disabled for now (compass HUD unchanged). HUD zone line is labeled **Current location**.

- **Compass**: one arrow on each face points from the player toward the focus. 0.2.6: the arrow re-reads facing every frame (position ~20×/s) and eases toward the target, so turning is smooth and responsive. No coordinates hides the arrow instead of pointing north. Distance stays live (re-probes objective position; about 1s for a full log pass). No coords shows `Zone · ?` instead of a leftover mock distance.
- **Mock fallback**: if the log is empty, HUD shows the P0 Barrens Loop mock.
- **`/qg mock`**: force mock on/off (saved in `QuestGrindDB.forceMock`).
- **`/qg refresh`**: force a live refresh (clears force-mock and any `/qg next` override).
- **`/qg next` / `/qg prev`**: temporary cycle of the current candidate set (checked quests if any, otherwise incomplete / adopted), closest first — cleared when checks change or on `/qg refresh`.

Distance/bearing use objective coordinates when Forever exposes them (quest POI, waypoint, or world yards converted onto the map). Without coords the distance line is `?` and the compass shows the zone (no false north). The main-map route only draws stops that have usable map coordinates.

## Themes

**Default** gold/wood plus Forever class themes: warrior, paladin, hunter, rogue, priest, shaman, mage, warlock, druid.

- Themes apply to **Full AND Less AND Compass** (not Full-only).
- Pick in **Edit Mode** (edit button / `/qg edit`). Every switch (including returning to a previous theme) re-applies chrome **and** panel colors with contrast preserved (0.2.2).
- Identity is **colors / materials / motifs** — no class names baked into art textures.
- P0/P1 use solid-color layers (white base + vertex tint); TGA/wood/gold polish is **P4**.

## Layered UI

Every visual piece is its own `Frame` so pieces can be moved later inside the QuestGrind window. The **root container is larger than the art** with transparent padding (`PAD = 24`) so ornate edges never clip.

**In-game check — chrome controls:** Move / Mode / Edit / Min / X stay as separate clickable buttons and don’t visually melt into one solid blob with the panel — hover each and see separate hit targets.

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
  show | hide | mode [full|less|compass] | full | less | compass
  theme <id> | edit | lock | ask | min | expand
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
    Map.lua            ← P1 main world-map route (0.2.9; minimap off)
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
