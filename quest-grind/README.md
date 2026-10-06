# QuestGrind

In-game quest HUD for WoW Forever — prettier than alt-tabbing a guide. Modes **Full / Less / Compass**. **Ask SI** via a desktop companion.

## Status

**P1 live questing (0.2.6)** — reads the player quest log, focuses the checked quest or checked chain (or the closest incomplete), shows the **quest-chain step** (e.g. `Quest Log 3/10`) with one **chain % progress bar**, shows Dungeon/World plus one **Rewards** area (text and **item icon tooltips**), a **compass arrow** toward the focused quest, and a minimap **edge arrow** (or bottom focus badge when coords are missing). Falls back to mocked Barrens Loop when the log is empty (or `/qg mock`). Ask bridge = **P2**. Hide Blizzard objectives = **P3**. Art polish (TGA) = **P4**. Interface stays **16001**.

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

- **Live** (default): enumerates accepted quests via `C_QuestLog` when present, else legacy `GetQuestLog*`. Focus rules (0.2.6):
  - **Checked** = on the Blizzard objective tracker. A checked quest stays in focus when it is **ready to turn in**.
  - **Checked chain**: after you turn in a step of a checked quest, the next step of that chain keeps focus even if it is not checked (same `C_QuestLine` quest line, or the quest you accept right after the turn-in).
  - Checking a quest (including re-checking a turn-in-ready one) brings it into focus. Unchecking drops it (and its chain) from focus.
  - Several checked → stay on the current chain, otherwise closest of the checked quests.
  - Only when **no** quest in the log is checked (or continues a checked chain) → closest incomplete quest (coords beat quests with none; if nobody has coords, log order).
- **Quest Log index / progress**: `Quest Log i/N` is the focused quest's step in its quest chain (`C_QuestLine`); a standalone quest is `1/1`. The single bar under it shows **chain steps complete / steps in chain** with a centered percentage (the current step counts once it is ready to turn in).
- **HUD**: focused quest shows a **Dungeon** or **World** badge. Full mode has one **Rewards** section (header, XP / money / items, or **None**) and **item icons** — hover for a real item tooltip (`SetItemByID` / hyperlink). The status block shows state, last update, and a quest count ("3 quests" / "1 quest"), not a second reward line. Less mode still puts type and rewards on the subtitle.
- **Minimap**: with coords, an **edge arrow** points toward the focus. Without coords, a **bottom focus badge** (not on the player) shows the focus is active; hover shows the quest title. World map pin appears when normalized (or converted) coordinates exist.
- **Compass**: one arrow on each face points from the player toward the focus. 0.2.6: the arrow re-reads facing every frame (position ~20×/s) and eases toward the target, so turning is smooth and responsive. No coordinates hides the arrow instead of pointing north. Distance stays live (re-probes objective position; about 1s for a full log pass). No coords shows `Zone · ?` instead of a leftover mock distance.
- **Mock fallback**: if the log is empty, HUD shows the P0 Barrens Loop mock.
- **`/qg mock`**: force mock on/off (saved in `QuestGrindDB.forceMock`).
- **`/qg refresh`**: force a live refresh (clears force-mock and any `/qg next` override).
- **`/qg next` / `/qg prev`**: cycle the current candidate set (checked / checked-chain quests if any, otherwise incomplete), closest first.

Distance/bearing use objective coordinates when Forever exposes them (quest POI, waypoint, or world yards converted onto the map). Without coords the distance line is `?`, the compass shows the zone, and the minimap shows the bottom focus badge.

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
