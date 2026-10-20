# Changelog

## 0.4.4 (readable text in every theme, hover that never whites out, footer and Journals fixes)
- **Hover never washes a label out:** buttons, rail tabs, subtabs, the theme buttons and list rows used an additive glow on the HIGHLIGHT layer, which draws *over* the text. On the light Priest buttons that turned the label white. Hover is now drawn *under* the label (ARTWORK sublevel 7): a soft tint plus a 1px accent edge in the theme's own colour. The tint moves away from the label colour (darker behind light labels, lighter behind dark ones), so hovering can only raise contrast. Scroll arrows and the close X keep their icon glows (no text there).
- **Text contrast, all 10 themes:** a new stub check composites what the client draws under every label (texture texels, texcoords, tiling, vertex colours, alpha, blend modes, in draw order) and scores it with the WCAG 2 ratio. It runs in every view (Quests, Journals x3, Map, Dungeons, Settings), with every button hovered. It requires 4.5:1, or 3:1 for 18px+ titles; outlined text is scored against its outline. First run: 322 labels below the line. Now 0 of 3467. Worst before / after: WoW 1.46 / 4.71, Warrior 2.13 / 5.61, Paladin 1.06 / 4.29 (the 38px title; 3:1 needed), Hunter 2.08 / 5.55, Rogue 2.46 / 5.61, Priest 1.22 / 4.64, Shaman 2.07 / 5.02, Mage 1.81 / 5.61, Warlock 2.35 / 5.61, Druid 1.86 / 5.24.
  - **Priest:** achievement cards were hard-coded dark while the text used Priest's dark inks. Cards now follow the theme (`card` / `cardOn`, light in Priest). The in-progress, good, bad, heading, muted, tab and grey-button inks are darker. The AG dungeon dropdown and the search boxes are themed fields (`fieldBg`) instead of black boxes.
  - **Every theme:** the addon's `gold` (rail tabs, group headers, accents) now uses the theme's surface ink (`--dm-tab-ink`), and button faces got their own `btnInk`. The old mapping made Paladin's labels dark brown on dark stone. The grey (disabled) button and the WoW status inks are lighter. Bar labels and the points number on the badge orb use a light ink with an outline, so they read over both the fill and the track. The badge art itself is unchanged.
  - **Paladin:** a bronze title on the marble plate, a lighter muted ink, a softer red. **Druid / Hunter / Shaman:** slightly deeper button, selected-tab and status fills under their light inks.
  - **WoW:** the AG dungeon title on the parchment page uses the paper ink. "Show all" on the fishing page uses the paper ink. The boss line on the selected (green) row uses the selected-row ink.
  - Item-quality colours (AG loot) keep their hue but are lifted or darkened just enough for 6:1 against the theme's list (`NS.Legible`).
  - All palette changes were made at the source, in the previewer theme data. The class themes are regenerated from it, so the previewer and addon match.
- **Journals:** subtabs are Adventure Guide, Fishing, Achievements (left to right). Adventure Guide opens by default; a saved last-used subtab still wins.
- **Footer:** the status box is centred between the Settings button's right edge and the Share stats button's left edge, with a 10px margin each side, in all 10 themes. It is tall enough for its text with padding, and the text truncates with an ellipsis only if it still does not fit.
- **All / Track Quest** (quest-log head row) is back in every class theme, in the same spot as WoW (above the left nav, below the title). It is clear of the title, crest and tabs.
- **Previewer:** mirrors all of the above (hover tint under the text with an accent edge, palettes, outlined bar and badge text, subtab order and default, footer status box, head row). New checks: DM-35 (contrast from screenshots with the text made transparent, hovered controls included) and DM-36 (subtab order and default, footer centring, head-row placement).

## 0.4.3 (no backdrop, drag by the frame, sharp frame edges)
- **No backdrop:** none of the themes draws a scenic picture around the main frame any more. Only the frame art and the interior panels are drawn, and the game world shows around them. Ornaments that hang over the frame edge stay: the druid vines and leaves, corner ornaments, crests, crystals and base plates. The previewer matches this.
- **Drag by the frame:** the whole frame is a drag handle in every theme, WoW included: the frame art, title bar, footer bar and the overhanging ornaments. The window's mouse area (`SetHitRectInsets`) grows to cover all of the drawn art; the art overlay itself takes no mouse. It uses `StartMoving`/`StopMovingOrSizing`, saves the position and clamps to the screen with the same rect. Controls inside keep working, and a drag never triggers a click. The previewer matches this too.
- **Sharp edges:** in 0.4.2 the top, bottom and side bands were packed at 0.75 texels per px and stretched. Now each class frame has 4 corners at the source art's density (2 texels per px) plus 4 edge strips at the same density. The strips are made seamless (period found by autocorrelation, 16 px cross-fade at the wrap) and drawn with `SetTexture(file, "REPEAT", ...)` texcoord tiling. The corners fade into the strips over 8 px. The overlay layer (glows, vines, crystals) is unique art, so it is not tiled: its corners are kept, and its edge sprites are cropped at source density and drawn in place. All textures are power of two and at most 512 (`cls-<c>-fc/ftb/flr/oc/os/parts.tga`). The parts sheet is 512x256 now that the backdrop is gone. Generator: `tools/themes/edge_tiles.py`.

## 0.4.2 (all 10 themes in Settings + badge icons without numbers)
- **Achievements summary bar:** the Dark Matter points and Legacy Points badges are icons only now. The numbers no longer sit on top of them; the figures stay in the progress-bar text (e.g. "170 / 610"). The previewer has the same change.
- **Gap check, previewer vs addon 0.4.1 (theme options):**

  | Previewer | Addon 0.4.1 | 0.4.2 |
  |---|---|---|
  | Settings: theme select with 10 themes (WoW + 9 classes) | "Theme: WoW" text, "Class themes come in a later phase." | **added:** theme picker (10 buttons) in the Settings popover, applied live and saved |
  | 9 class themes' generated raster art: frame, overlay, corner ornaments, crest, base plate, backdrop, shell texture | missing | **added:** converted from the previewer art, 27 TGAs at 512x512 |
  | per-class colours and CSS looks: buttons, tabs, pills, status field, badges, pane borders, list highlight, bars | WoW only | **added:** colours and flat gradient looks from the previewer's resolved variables |
  | class layout: footer inset from the rim, close button on the frame, larger title, no medal or title plate, quest-log head row hidden | WoW only | **added** |
  | Ctrl+Alt+T theme cycle (dev hotkey) | missing | **added** as `/dm theme next` (plus `/dm theme`, `/dm theme <name>`) |
  | Reset window position | present | unchanged |
  | accent colour, font scale, opacity, frame-art toggle | n/a | the previewer has none of these, so there is nothing to add |
- **Also on the stock Settings page** (Settings > AddOns > Dark Matter, canvas API): the same 10 themes as stock buttons, with the current one highlighted.
- **How the class themes work.** `Theme_Classes.lua` is generated by `tools/themes/make_class_textures.py` from the previewer's art and its resolved `--dm-*` variables (`tools/themes/dump_theme_vars.py`).
  - Class themes inherit the WoW layout (`base = "wow"`), so every layout check still applies.
  - The frame art is mapped from the previewer's 880x680 art space onto the window's shell box.
  - The frame bands draw under the content. The overlay, ornaments, crest and base sit on a no-mouse child frame above it, below the Settings popover. The backdrop sits behind the window.
  - The window's clamp rect grows to the art, and the fit-to-screen scale counts the art.
- **Safety:** no dropdown menus (no UIDropDownMenu or EasyMenu), stock frame types only, no new events, nothing touched in combat. A skin error during a theme switch is caught and kept in `NS.lastSkinError` instead of breaking the switch.
- **WoW theme unchanged:** the bar colours moved into theme keys with the same values, and a stubtest proves WoW draws exactly the same after visiting all 9 class themes.
- **Stubtests:**
  - 10 themes in previewer order, textures 512x512 32-bit;
  - popover picker and Settings canvas: apply, save and mark only the current theme;
  - `/dm theme` list, `next` wrap and unknown names;
  - every tab and Journals section in every theme;
  - class art placement, no-mouse overlay and clamp insets;
  - no UIDropDownMenu.

## 0.4.1 (P2 fix + Achievements per character + new layout)
- **Fixed: the "DarkMatter has been blocked from an action only available to the Blizzard UI" popup.**
  - **Cause:** 0.4.0 registered and unregistered `COMBAT_LOG_EVENT_UNFILTERED` on every zone change, including the first `PLAYER_ENTERING_WORLD` after login. That is why Odysseaus' `/dm blocked` showed `UNKNOWN()` out of combat at 12:45:08, the second the achievements tracking started.
  - On Forever 1.60.1 the combat log is a **restricted event**: Blizzard's generated Forever API docs (Gethe/wow-ui-source, `forever` branch, commit 172a387) mark `COMBAT_LOG_EVENT_UNFILTERED` / `COMBAT_LOG_EVENT` with `HasRestrictions = true`, the same as `MINIMAP_PING` and `UNIT_PING_PIN_*`.
  - Touching a restricted event from addon code raises `ADDON_ACTION_FORBIDDEN` with the function `UNKNOWN()`.
- **The fix:** Dark Matter no longer uses the combat log at all. Boss kills come from `ENCOUNTER_END` (success) and `BOSS_KILL`, both unrestricted, which count once together. For encounters the client doesn't report, a fallback counts the boss when you loot its corpse, using the loot GUID the Adventure Guide already reads. That fallback is deduped per corpse and per boss for 10 minutes.
  - Every tracker event is registered once at start-up, through a guard that refuses anything on the restricted list.
  - The stubtests now model restricted events: touching one fails the run, and the 0.4.0 code is verified to fail this check.
  - The old SetPropagateKeyboardInput / Esc catcher paths were rechecked and are not involved. The achievements dropdown and its catcher are gone with the new layout.
- **`/dm blocked`** now prints:
  - the count;
  - `last blocked function: <name>  (<event>, addon <name>)`;
  - when, version, combat yes/no, the Dark Matter context (which event handler was running, e.g. `ach:PLAYER_ENTERING_WORLD`) and the probe step;
  - up to 6 lines of `debugstack` from the moment of the block, followed by the earlier entries.
  - `nil` and empty arguments are shown literally. `/dm blocked clear` empties the log.
- **Achievements count for the current character only.**
  - Game achievements use `GetAchievementInfo`'s `wasEarnedByMe` (and `earnedBy`) and per-character criteria.
  - A completion by another character shows muted as "Not yet (earned on another character)". It is excluded from Earned, category counts, the "Done X/Y" badge and the Legacy Points figure.
  - `/dm achprobe` shows both, e.g. "completed: 7 account / N this character (Name-Realm)", and the same split for Legacy Points.
  - Dark Matter's own data stays in `DarkMatterCharDB` (per character). Any account-wide copy is moved to the current character once, then removed.
- **New Achievements layout** (our own design, no Blizzard art):
  - A per-character summary bar with Dark Matter points and Legacy Points, each with a progress bar.
  - On the left, search plus a Filter button (All / Earned / Not yet) above a collapsible category tree. The game's categories are nested by their parent ids (Classes > Druid), and Dark Matter is its own top-level section with our 6 categories.
  - Search covers every category and shows match counts in the tree.
  - On the right, a scrolling list of cards: icon, name, description, points badge, earned date, and a progress bar for partial ones. Unearned cards are muted grey. Clicking a card expands it in place with its criteria.
  - It fits the window in all 10 themes, with no overlapping or truncated text across all 50 cards, collapsed and expanded.
  - It is ready for generated art (`NS.achArt`, from `tools/achievements`). Until that atlas ships it uses the existing theme art.
- Stubtests: restricted-event model, boss-kill paths (once per kill), logger output, per-character fixtures and migration, the new layout (tree, summary, cards, expand, filter, search) and a layout sweep. Previewer DM-32/33/34 mirror the layout with labelled example data and sweep every card in all 10 themes.

## 0.4.0 (P2, Journals > Achievements)
- **API research (no guessing):** Forever 1.60.1 (`classic_beta`, Interface 16001) keeps the stock achievement API. Blizzard's own Forever UI source (Gethe/wow-ui-source, `forever` branch: `Blizzard_LegacySystem`, `Blizzard_LegacyChallengeTracker`, `Blizzard_AchievementUI`) calls `GetCategoryList`, `GetCategoryInfo`, `GetCategoryNumAchievements`, `GetAchievementInfo`, `GetAchievementNumCriteria`, `GetAchievementCriteriaInfo` and `C_Traits.GetTraitCurrencyForAchievement(Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225, id)`. Wowhead Forever's achievement tooltips (`nether.wowhead.com/forever/tooltip/achievement/<id>`) return Forever-only ids (e.g. 62014 Artisan Alchemist, 62054 Lord Valthalak Laid to Rest, 62035 Conqueror of the Deeps, 62382 Explorer): "Points: 0", "Account-wide progress", "Earn 1 Legacy Point". Classic/WotLK achievement ids 404 there. So the API exists, but the set is thin: the Legacy Challenges (65 at launch per Blizzard's announcement) plus hidden tracking rows.
- **Achievements subtab:** category dropdown in the AG style (gold, non-clickable group headers; entries indented 12px; closes on outside click, `GLOBAL_MOUSE_DOWN` outside, Esc via the named `DarkMatterAchMenuCatcher`, and window hide; the button toggles). Achievement list with icon, points, earned date or progress text, and a progress bar on every row; detail pane with points, status, a progress bar and criteria rows. Filters: All / Earned / Not yet.
- **Game group, "Legacy Challenges":** read-only, shown only when the client returns data. Parent-prefixed category names ("Classes: Warrior"), Legacy Points, completion dates, "another character" for account-wide completions, criteria with quantities. Placeholder rows ("[DNT] ...") are skipped and counted.
- **Dark Matter group, our own 50 achievements** in 6 categories (General 7, Quests 6, Dungeons and Raids 16, Fishing 8, Exploration 6, Loot 7), per character in `DarkMatterCharDB.ach`, with earned dates, counters and criteria progress. Boss achievements resolve to npc ids in our `Data_Dungeons` seed; fish achievements to our catch catalog. Counting starts at install. Only the current level is awarded retroactively, marked "at install", without toasts. A toast (`DarkMatterAchToast`, our own frame) and a chat line announce each new one.
- **Events, all on a private frame, no hooks:** `PLAYER_LEVEL_UP`, `QUEST_TURNED_IN` (one count per quest), `ENCOUNTER_END` (success only) and `COMBAT_LOG_EVENT_UNFILTERED` `UNIT_DIED`/`PARTY_KILL`, registered only inside party/raid instances. One kill is counted once. Also `CHAT_MSG_LOOT` (your own lines, matched with the client's `LOOT_ITEM_SELF` strings), `PLAYER_MONEY` (gains only), `ZONE_CHANGED_NEW_AREA`/`PLAYER_ENTERING_WORLD`, and `ACHIEVEMENT_EARNED`/`CRITERIA_UPDATE` (refresh only). Fishing.lua reports each recorded catch through a plain `NS.OnFishCatch` callback.
- **Modes:** `game+dm` (API with thin data, Forever), `dm` (no data), `game` (a full 300+ set with points; ours off). **`/dm achprobe`** prints the mode, which API functions exist, the game counts (categories, achievements, completed, points, Legacy Points, `GetNumCompletedAchievements`), 3 game samples with criteria, and the Dark Matter totals with 3 samples. It saves to `DarkMatterDB.achprobe`.
- Stubtests: dm-only, a Forever-shaped thin API and a full API, every tracker path, toasts, achprobe in both modes, the dropdown and its close paths, no overlapping or truncated text across all 50 rows, and the taint rules. Previewer DM-32/DM-33 mirror the tab with labelled example data.

## 0.3.4 (P3.0, LFG alias map)
- **Every kept LFG row now maps to our list.** Odysseaus' in-game `/dm agscan` on 0.3.3 said "67 LFG names, 26 dungeons/raids kept (22 match our list); rejected: zone 41". The 4 unmatched were the client's spellings "Stormwind Stockades", "Zul'Farak", "Onyxia" and one "Scarlet Monastery" row.
  - The alias map lives in our data (`tools/dungeons/catalog.json` -> `Data_Dungeons.lua`): "Stormwind Stockades" -> The Stockade, "Zul'Farak" -> Zul'Farrak, "Onyxia" -> Onyxia's Lair.
  - New `parent = "Scarlet Monastery"` on the four SM wings: the single LFG row marks all four live, and the wings stay separate in the dropdown with our names, levels and bosses. A parent row gives the wings no shared LFG level or boss names.
  - Our display names are kept, and our bosses and drops stay the source: Forever's LFG API reports no bosses for any of the 26.
- **Normalized matching** (case, punctuation, a leading "The") applies to names, aliases and parent names. A loose fallback catches small variants the map doesn't list: doubled letters collapse and a plural "s" drops ("Zul'Farrakk", "Blackfathom Deep"). It is used only when exactly one of our entries has that loose key, and never for a known zone, capital or battleground.
- **`/dm agscan`:** the summary now reads "N dungeons/raids kept (M of N match our list)". A replay of the real-client scan in the stubtests gives "67 LFG names, 26 dungeons/raids kept (26 of 26 match our list); rejected: zone 41". New lines:
  - "mapped by alias (N): LFG name -> our entry".
  - "info: ours only, not in the LFG list (N): ..." for our entries the LFG list lacks; in the replay these are Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran, AQ20, AQ40 and Naxxramas. This is informational, not an error.
  - The boss-less line now says our boss lists are used.
  - `DarkMatterDB.agscan.mapped` / `.oursOnly` are saved, and each kept row records `ours` and `matchedBy`.
- Stubtests: the alias merges, the SM parent, `AG.MatchName` cases, the agscan mapped/ours-only lines and a replay of the real-client scan (26 of 26, 7 ours-only, 36 entries, no duplicates). Previewer DM-31 mirrors the alias map.

## 0.3.3 (P3.0, dropdown polish)
- **Indented dropdown:** every dungeon/raid entry sits 12px in from its group header. The "Dungeons" / "Raids" headers stay flush left in the gold header colour and are not clickable (mouse off, no highlight; the click handler also ignores them). Entry rows give the level column 40px and measure the name. A name that doesn't fit the indented row uses the existing compact form, which today is only the three long Scarlet Monastery wings: "SM: Graveyard", "SM: Library", "SM: Cathedral". The full name stays in the header under the bar.
- **Open dropdown closes on any outside click, on Esc and when the window hides; the button still toggles it.** Stock frames only, no hooks:
  - A full-screen invisible catcher (our own `UIParent` child at the list's strata, one frame level under it) takes the outside mouse-down and closes the list; it passes nothing else on.
  - `GLOBAL_MOUSE_DOWN` on a private event frame, registered only while the list is open, closes it when the mouse is over neither the list nor the button (covers frames above the catcher).
  - Esc goes through Blizzard's `UISpecialFrames` list: the named catcher (`DarkMatterAGMenuCatcher`) is listed only while the list is open and the main window comes off the list meanwhile (as with the Settings popup), so Esc closes only the list.
- Stubtests: the 12px indent, flush-left gold non-clickable headers, the row fit and compact names, the catcher (parent, strata, level), the private `GLOBAL_MOUSE_DOWN` frame (inside, on the button, outside), Esc, the button toggle and closing when the window hides.

## 0.3.2 (P3.0, every dungeon and raid)
- **Known-good list, always shown:** the dropdown lists all **36 instances (29 dungeons, 7 raids)**, grouped Dungeons/Raids and sorted by level. Dungeons: RFC, Wailing Caverns, Deadmines, Shadowfang Keep, Blackfathom Deeps, Stockade, Gnomeregan, Razorfen Kraul, Scarlet Monastery (Graveyard, Library, Armory, Cathedral), Razorfen Downs, Uldaman, Zul'Farrak, Maraudon, Sunken Temple, BRD, LBRS, UBRS, Dire Maul (East, West, North), Scholomance, Stratholme. Raids: Molten Core, Onyxia's Lair, Zul'Gurub, BWL, AQ20, AQ40, Naxxramas. Forever-only, from Wowhead WoW Forever: The Hall of Thanes (13-18), Ruins of Lordaeron (15-20), Excavation Site: Wetlands, City of Dalaran (tagged "New in Forever").
- **Sources:** names and level ranges from Wowhead WoW Forever zone data (`/forever/zone=<id>`). Forever's ranges differ from Classic (RFC 15-25, WC 17-27, Deadmines 15-25, SFK 22-30, BFD 22-32). Wing and Forever-only ranges Forever's zone data lacks cite `levelSrc` (marked fallback: warcraft.wiki.gg for 9 entries, the Wowhead Forever guide for Hall of Thanes, wowseer.gg for Excavation Site: Wetlands and City of Dalaran). The list is hand-written in `tools/dungeons/catalog.json`. `resolve_forever.py` resolves every zone and boss on Forever: 289 bosses, 0 unresolved.
- **Bosses for every instance, drops for 24 dungeons:** every instance has a Forever-confirmed boss list. Drops (Classic NPC drop lists as the marked attribution fallback, then validated on Forever) are seeded for 24 Classic 5-player dungeons, 470 drops in total. 469 items that Wowhead Forever's database doesn't have yet are left out rather than seeded from Classic alone, which leaves Dire Maul: West with a boss list only. 17 bosses whose drops are all missing on Forever say "drops coming soon"; bosses with no boss-specific drops say "0 drops". Item 12728 uses its Forever name, "Pattern: Invulnerable Mail". Raids and Forever-only instances are boss lists only ("drops coming soon").
- **LFG merge:** live LFG rows attach to the list by name or alias ("Scarlet Monastery - Graveyard", "Stormwind Stockade", "Dire Maul - East") for the recommended level and any extra live boss names ("live LFG boss · drops coming soon"). LFG dungeons/raids not in the list are kept.
- **No-bosses rule dropped:** the real client's `/dm agscan` showed 21 real instances rejected only because their LFG rows report no encounters. Rows are now kept unless they are a zone, capital, battleground, world PvP or scenario, random queue ("Random ..." or typeID 4/6) or placeholder.
- **`/dm agscan`** prints the kept rows with no LFG bosses and the kept rows not in our list by name (chunked lines) and saves them to `DarkMatterDB.agscan.noBosses` / `.notInList`.
- Instances with no bosses anywhere show "Boss and drop data coming soon." Long wing names use initials in the dropdown label only ("SM: Graveyard"); the header shows the full name.
- Stubtests cover the list integrity (36/29/7, every named instance, Forever citations, boss lists), alias merges, the unlisted LFG row, the new reject stats, agscan names, sorting, the dropdown listing every entry, the "coming soon" states, the pending vs 0-drop bosses and the compact label.

## 0.3.1 (P3.0, Adventure Guide layout + LFG filter)
- **Layout (from the in-game 0.3.0 screenshot):** the left dungeon list is now a **dungeon dropdown** in the top bar, next to the search box and level pills. It's built from our own frames (Button + Panel + Scroll, no `UIDropDownMenu`, which shares Blizzard state). Entries are grouped by type (Dungeons / Raids headers when there is more than one type), with an "N of M dungeons & raids" head. It closes on pick, on a second click, on section change and on hide; the arrow is the scrollbar piece (no font glyphs). The dungeon header (name, level, recommended, size, type, zone, boss count) sits under the bar. **Bosses** take the left column (220px). **Drops** take the wide right panel (374px).
- **No overlapping text:** every AG fontstring is one line with a fixed height (`SetWordWrap(false)` + `SetHeight`); in 0.3.0 the texts only had LEFT/RIGHT anchors in narrow columns, so the client wrapped them into each other. Boss rows are two lines (name / "rare spawn · N drops"), so the count is labelled. Drop rows are name on line 1, "Quality · x% drop · seen N× / not seen yet" on line 2. The drop header is the boss name with "N drops · N seen by you" on its own line under it.
- **Zones/battlegrounds out of the dungeon list:** on Forever the LFG id range also returns zone activities and battlegrounds (Alterac Mountains, Arathi Basin, Ashenvale Forest, ...) that report encounters, so the 0.3.0 "has encounters" test let all 67 through. A row is now kept only if: its type is not zone/random (`typeID` 4/6) or scenario/world PvP (`subtypeID` 4/6), its name is not a classic zone, capital or battleground, it is not a placeholder, and it has at least one real encounter name or matches our seed.
- **Placeholder bosses dropped:** "No Longer in Use", UNUSED, [PH], PH, zz/zzOld, deprecated, "do not use", placeholder, SECRETNAME.
- Seeded dungeons use our seed level range (LFG reported Wailing Caverns as 17-17); LFG keeps the recommended level.
- **`/dm agscan`:** writes every named LFG row (type, subtype, levels, size, encounter names) with its kept/rejected reason to `DarkMatterDB.agscan` and prints a one-line summary, so the real client's data can be checked.
- Stubtests: a zone/battleground/PvP/empty/placeholder LFG mock, scan stats, a 'No Longer in Use' filter test, the placeholder matcher, agscan, dropdown open/group/pick/close, and a bounding-box overlap + one-line-fit test over drop rows, boss rows and both headers.

## 0.3.0 (P3.0, Adventure Guide v1)
- **Journals > Adventure Guide** replaces the placeholder. Left: dungeon list with a search box (dungeon, boss or drop name), level filter (All levels / Near level N: min-2..max) and type pills when the LFG data offers more than one type (Dungeon/Raid/Heroic from `subtypeID`, else `maxPlayers`). Right: dungeon header (level range, recommended level, size, type, zone, boss count), boss list and the selected boss's drops.
- Drop rows: icon with the 2px rarity rim (same widget as fishing), item name from `GetItemInfo` when cached (seed name otherwise), quality, Wowhead drop chance and **seen by you**. Hover uses the shared tooltip path (`NS.ShowItemTooltip`, factored out of the fishing tooltip): leftmost tooltip's bottom-left 4px from the icon's top-right, compares chained right, mirrored only at the screen edge, plus Dark Matter lines (boss, dungeon, chance, seen by you).
- Dungeons and bosses come from the client's LFG data (`GetLFGDungeonInfo` / `GetLFGDungeonNumEncounters` / `GetLFGDungeonEncounterInfo`, read-only, IDs 1-1300, entries with encounters, one per name, secret names skipped), merged by name with our seed; seed dungeons the LFG list lacks are still shown.
- Static drop seed `Data_Dungeons.lua` (generated by `tools/dungeons/gen_dungeons.py` from our own `seed.json`): RFC, Wailing Caverns, Deadmines, Shadowfang Keep, Blackfathom Deeps with full boss lists (39 bosses incl. rares) and 86 boss-specific drops. **Primary source: Wowhead WoW Forever.** Every NPC and item is validated against Forever (`tools/dungeons/verify_forever.py`, Forever tooltip API) and uses its Forever name, quality and icon; each entry cites `https://www.wowhead.com/forever/npc=<id>` / `https://www.wowhead.com/forever/item=<id>`. Drop attribution falls back to the Wowhead Classic NPC drop list (`dropSrc`, marked fallback): boss-specific, Uncommon+, not quest items, >= 2% reported, no seasonal or Season of Discovery IDs. Forever lists all 86 as Rare (41 of them are Uncommon on Classic). No other addon's loot table is used. Entries are gated on `C_Item.DoesItemExistByID`.
- Loot learning (account-wide `DarkMatterDB.agSeen`): on `LOOT_OPENED` inside a party/raid instance each looted item is counted once per loot source GUID, credited to the boss whose NPC ID is in the GUID, else to a boss killed in the last 2 minutes (`ENCOUNTER_END` success / `BOSS_KILL`), else to the dungeon. Private event frame; no hooks, no Blizzard UI loads.
- Stub tests: seed integrity and Forever citations, LFG merge/sort/kinds with a full-tuple LFG mock (raid, secret name, random entry), search/level/type filters, the exist gate, loot learning (NPC-ID credit, GUID dedupe, kill window, other), UI rows, and the AG tooltip placement/compare chain. Minimal client: seed-only fallback.

## 0.2.15 (P2.15, tooltip corner on the item icon)
- New placement rule (replaces all earlier ones): the tooltip's bottom-left corner sits 4px (visible, border-inset corrected) right of and above the **item icon's top-right corner**. With compare tooltips, the leftmost tooltip of the set (the main tooltip) takes that spot and `ShoppingTooltip1/2` chain to its right, bottoms aligned. Same default with or without a compare; the old "no compare goes up-left" default is gone.
- Fallbacks only for screen space: if the set would run off the right edge it is mirrored (main BOTTOMRIGHT 4px left of / above the icon's TOPLEFT, compares chained left); with no room above it goes below the icon with the corners mirrored vertically (tops aligned).
- The anchor is the icon frame itself; the 0.2.12 item-anchor frame (icon + name width) is removed. Tooltips cover the names of the rows above, as intended.
- Kept: `ANCHOR_PRESERVE`, the settle/watch re-apply, `/dm tipdebug` (now labels the anchor `icon` and reports the icon rect).
- Stub tests: the real-client geometries re-checked under the new rule (no compare, two compares, right-edge mirror, no room above). Previewer: same rule; DM-23..25 rewritten.

## 0.2.14 (P2.14, placement diagnostics + settle)
- Investigation of the 0.2.13 "still off" reports using `/dm tipdebug` from the real client: the logged rects match the screen. Oily Blackmouth (no compare): anchor `242,593.5 147.7x28` (icon + name), tooltip frame `390.7,622.5 364.7x172.3`; on screen the tooltip's visible border sits ~4 units right of the end of "Oily Blackmouth" and ~4 above its icon. 103 Pound Mightfish (two compares): anchor right 420.5, tooltip at 421.5,514.5, compares chained right, bottoms aligned. No scale or coordinate-space mismatch: placement is applied exactly as specified.
- Why it chose right/up without a compare: the icon is only 242 units from the screen's left edge and the tooltip is ~365 wide, so "up-left of the icon" does not fit and rule (a) flips it to the item's top-right. Above the row, it necessarily covers the rows above.
- `/dm tipdebug` now also prints effective scales (UIParent, tooltip, anchor, row, icon), the row's and icon's own rects, and the room decision (`room L/R`, `need`, chosen side, "no room on the left"); saved as `decision` with `frames.icon`/`frames.UIParent`.
- Placement watcher re-applies every frame for the first 10 frames after show, then on any size/anchor change.
- Stub tests reproduce both real-client tipdebug geometries exactly and assert no overlap with the hovered item and up-left placement when there is room. Previewer DM-25 adds the left-edge no-compare case.
- Kept `ANCHOR_PRESERVE`: with `ANCHOR_NONE` the client's `GameTooltip_AnchorComparisonTooltips` calls `SetAnchorType(anchorType, dx, 0)` and slides the tooltip (the 0.2.9 cursor jump).

## 0.2.13 (P2.13, tooltip corner on the item)
- **Fix: tooltip "close but not there yet".** Measured on the 0.2.12 screenshot (window on the left, "103 Pound Mightfish" hovered; ~1.19 screen px per UI unit): the tooltip's visible bottom-left was 11 px (~9 units) right of the end of the name and 13 px (~11 units) above the icon's top edge, i.e. ~5 units right and ~7 units up from the target. It sat on the hovered row (not the row above); the gap was just too big. Two causes:
  - The item anchor spanned the full row height, so its top was the row's padded top, 4 units above the icon.
  - The classic tooltip border art is drawn ~3 units inside the frame edge (backdrop insets), so a frame placed 4 units away shows its border ~7 units away.
- The item anchor now uses the icon's top and bottom edges (icon left to the name text end). SetPoint offsets are the 4-unit gap minus a 3-unit border inset (`NS.FISH_TIP_INSET`), so the visible border lands 4 units from the item corner. Mirror, below-row and compare-chain rules unchanged.
- `/dm tipdebug` adds a chat line comparing the anchor rect with the tooltip rect: frame gap and estimated visible gap (frame gap + inset), saved as `delta` in `DarkMatterDB.tipdebug.last`.
- Previewer: anchor on the icon top edge (the HTML tooltip has no inset); DM-25 checks it.

## 0.2.12 (P2.12, tooltips anchor to the item)
- **Fix: tooltip far from the hovered item (default right-side layout).** Root cause: the placement anchored to the catch row frame, which spans the full width of the list (icon + name + count column, out to the scroll area's right edge). "Row TOPRIGHT" was therefore the far right of the list, hundreds of pixels from the item name. The mirrored layout looked right only because the row's TOPLEFT is next to the icon. The rules themselves were applied (in the 0.2.11 screenshot the main tooltip sits 4px above the row and the compare's bottom lines up with it); the anchor was wrong.
- Each fish row now has an invisible **item anchor**: from the icon's left edge to the end of the name text (the name's actual string width, capped at its box), full row height. With compare: main BOTTOMLEFT at the item's TOPRIGHT (+4,+4), compares chained right, bottoms aligned; no compare: main BOTTOMRIGHT at the icon's TOPLEFT (-4,+4). Mirror and below-row rules unchanged.
- Compare tooltips are recognised via `IsOwned` too when `GetOwner` is unavailable.
- `/dm tipdebug` toggles a placement log: after each placement (show, resize, re-anchor) the final `GetPoint`/`GetRect`/scale of GameTooltip, ShoppingTooltip1/2, the item anchor and the row go to `DarkMatterDB.tipdebug` (`last` + `log` of 40), with a one-line chat summary (first 6 per hover). `/reload` writes SavedVariables.
- Previewer: same item anchor (icon + measured name width); DM-25 checks it.

## 0.2.11 (P2.11, compare placement watcher + catalog audit)
- **Fix: odd offset with a compare tooltip.** In 0.2.10 placement ran once after `Show()` and once on the next frame. The client's classic compare code (`GameTooltip_ShowCompareItem` / `GameTooltip_AnchorComparisonTooltips`) anchors `ShoppingTooltip1/2` TOPLEFT to GameTooltip's TOPRIGHT (0,-10) and fills them with a second `SetCompareItem`; sizes and anchors can settle after our pass, and the tooltip `OnUpdate` re-runs it via the owner's update. Also, per-row hover flags could let a list refresh (item data arriving) re-show the tooltip from a row the mouse had already left, so it sat over the neighbouring row.
- Placement now runs from our own watcher frame while a row is hovered: whenever GameTooltip or a compare tooltip changes size, visibility or anchor, the rule set is re-applied (main + compares). Stops when the tooltip is hidden or owned by something else. Still taint-safe: no `hooksecurefunc`, no replaced globals.
- One hover owner: only the row most recently entered (and still under the mouse) can re-show the tooltip on refresh.
- Rules unchanged: 4px gap; no compare -> BOTTOMRIGHT at the row's TOPLEFT (flip right if needed); compare -> BOTTOMLEFT at the row's TOPRIGHT with compares chained right, bottoms aligned (mirrored left if needed); below the row near the top of the screen; never on the cursor.
- **Catalog audit** against Wowhead Classic (`nether.wowhead.com/classic/tooltip/item/<id>`) for all 121 entries: 0 wrong item IDs, 0 duplicate IDs or names. Fixed with that evidence: 36 trophy fish quality Uncommon -> Common, 2 name spellings ("Thick-shelled Clam", "Big-mouth Clam"), 19 icon paths corrected, 85 icons filled in. `tools/catalog/verify_wowhead.py` re-checks.
- Rows show the client's item name once cached; any difference from the catalog is logged.
- `/dm fishcheck`: checks every catalog/learned entry against the client's item data and saves the mismatch list to `DarkMatterDB.fishcheck` (run again after items load).
- Stub client now mimics the classic compare anchoring order; tests cover re-anchoring, late resize, second compare tooltip, single hover row, fishcheck, unique IDs/names.
- Previewer: catalog regenerated from the corrected data.

## 0.2.10 (P2.10, tooltip + compare placement)
- Gap between row and tooltip is now **4px** everywhere.
- **No compare tooltip:** main tooltip BOTTOMRIGHT at the row's TOPLEFT (-4,+4); if it doesn't fit, BOTTOMLEFT at the row's TOPRIGHT (+4,+4).
- **Compare tooltip shown** (shift-compare or `alwaysCompareItems`): main tooltip BOTTOMLEFT at the row's TOPRIGHT (+4,+4), `ShoppingTooltip1` then `ShoppingTooltip2` chained to its right, bottoms aligned. If that set doesn't fit, it is mirrored: main BOTTOMRIGHT at the row's TOPLEFT (-4,+4), compares chained to the left.
- If neither side has room for the main + compare set (wide rows on small screens), the side with more free space is used; the client clamps tooltips to the screen.
- Near the top of the screen everything goes below the row (tops aligned, y -4); the taller of main/compare decides.
- Fix: the item tooltip no longer jumps onto the cursor when a compare tooltip appears. Cause: this client's `GameTooltip_AnchorComparisonTooltips` slides the main tooltip with `SetAnchorType(anchorType, dx, 0)` unless the anchor type is `ANCHOR_PRESERVE`, which threw away our `ANCHOR_NONE` points. We now own the tooltip with `ANCHOR_PRESERVE`, then place the main and compare tooltips ourselves after `Show()` and again on the next frame.
- Shift pressed/released while hovering: our own `MODIFIER_STATE_CHANGED` frame rebuilds the hovered row's tooltip (the client decides compare in `OnTooltipSetItem`; GameTooltip has no modifier handler). Item-load refresh uses the same path.
- Taint-safe: no `hooksecurefunc`, no replaced globals, no fields written on GameTooltip; only `SetOwner`/`SetPoint` on GameTooltip and ShoppingTooltip1/2. The fallback tooltip hides stale compare tooltips via `GameTooltip_HideShoppingTooltips`.
- Previewer: 4px gap, mock "Currently Equipped" compare tooltip with the same rules; DM checks added.

## 0.2.9 (P2.9, row tooltip placement)
- Fishing row tooltips: `SetOwner(row, "ANCHOR_NONE")` + `SetPoint("BOTTOMRIGHT", row, "TOPLEFT", -8, 8)`, so the tooltip sits up-left of the row with an 8px gap instead of corner-to-corner.
- Same placement for the item tooltip, the fallback (uncached) tooltip and the refresh after item data loads; re-checked after `Show()` once the size is known.
- Stays on screen: near the left edge it flips to the row's right (`BOTTOMLEFT` to `TOPRIGHT`, +8,+8); near the top it goes below (`TOP*` to `BOTTOM*`, y -8). The gap is kept in every case.
- Previewer: the example fish tooltip uses the same anchor and gap.

## 0.2.8 (P2.8, catch-type row tooltips)
- Hovering a **by fish** row (own catches and every Show all row, including uncaught and learned) shows `GameTooltip:SetOwner(row, "ANCHOR_RIGHT")` with the real item tooltip: `SetHyperlink` with the stored loot item string, else `SetItemByID(itemId)`.
- When the item isn't in the client cache yet (`C_Item.IsItemDataCachedByID`, fallback `GetItemInfo`), a simple tooltip shows name in quality colour + quality name, and item data is requested; the open list refreshes on `GET_ITEM_INFO_RECEIVED` and a still-hovered row rebuilds into the full item tooltip.
- Dark Matter lines under the item: **Caught N (share %)** + **Last caught zone (coords)**; or **Not caught yet** + first seen (learned) + **Typical waters** / **Fishing skill**; Junk marker.
- OnLeave (and row hide) hides the tooltip only if the row still owns it. No hooks, no secure templates, no scripts on GameTooltip.
- Catches now store the bare loot `item:...` string (`it.link`) for the tooltip; older catches use the item id.
- Previewer: matching hover tooltip on fish rows.

## 0.2.7 (P2.7, fishing catalog: sourced + auto-learned)
- **Auto-learn:** any fishing loot item (with an item link) that is not in the static catalog is saved per account in `DarkMatterDB.fishingCatalogLearned[itemId] = {itemId, name, icon, quality, firstZone, firstSeen}`. Later sightings only fill a missing icon/quality; first zone/date are kept.
- **Show all** = static catalog + learned catalog + your own catches, deduped by itemId (name fallback for old link-less catches). Order: caught → learned (not yet caught by this character) → rest; then count, then name.
- Header shows **"Catalog: N items, M caught"** (Show all on) or "M caught · Show all for the full catalog" (off). Learned rows: "Learned · first seen in <zone> · <date>"; uncaught rows show typical waters and skill hint.
- **Static catalog expanded to 121 entries** (was ~30): classic fish, alchemic/special, quest, trophy, bloated containers, clams, crates, trunks, locked chests, Message in a Bottle / Rumsey rums, crafting reagents, fishing gear, vendor junk. Facts entered from public sources (warcraft.wiki.gg Fishing items / Fishing locations / per-item pages; source URL per section). No other addon's tables were used.
- No public Forever-specific fishing loot list exists yet, so only items seen on a live Forever 1.60.1 client are `forever=true` (Raw Brilliant Smallfish, Raw Longjaw Mud Snapper, Raw Slitherskin Mackerel); the rest are `classicOnly=true` and are shown only when `C_Item.DoesItemExistByID` returns true on the client (hidden if the API is missing).
- Fix: item 13888 is Darkclaw Lobster (12238 is Darkshore Grouper). Removed unsourced entries; post-Classic catches excluded.
- Generator + source data in `tools/catalog/` (reproduces `Data_FishingCatches.lua` byte-for-byte).
- luacheck: 0 warnings (added `GetItemInfoInstant`, `GetItemQualityColor`, `ITEM_QUALITY_COLORS` to read_globals; removed two unused locals).
- Previewer: catalog header count, learned example row, waters/skill sub-text; catalog mirrors the addon's 121 entries; fish-icon colours moved to theme variables (DM-9 check passes again).

## 0.2.6 (P2.6, Forever item icons)
- Fix fish icons rendering as **white squares** on Forever 1.60.1: `SetPortraitToTexture` blanks the texture on this client; icons now use plain `SetTexture` with square crop + **rarity rim** (poor→legendary via `GetItemQualityColor`).
- Fix `GetItemInfoInstant` read: icon is the 5th return (0.2.4/0.2.5 took the 4th, a type/subtype string). Icon values are validated (fileID or `Interface\...` path only).
- Icon sources in order: loot-window texture stored at catch time → `GetItemInfoInstant` → `GetItemIconByID`/`GetItemIcon` → `GetItemInfo` → static `Interface\Icons\...` in `Data_FishingCatches.lua`. `RequestLoadItemDataByID` + `GET_ITEM_INFO_RECEIVED` refresh the list when data arrives.
- Old catches without an item link resolve their item id from the catalog by name.

## 0.2.5 (P2.5, catch-mode toggle + real fish icons)
- Fix **by zone / by fish** toggle stuck on by zone: filter bar raised above content roots; Refresh applies view from CharDB without rewriting catchMode.
- Fix fish icons showing as gold circles: removed opaque Minimap ZoomButton chrome; icons use GetItemIcon / C_Item (RequestLoadItemDataByID when needed) with SetPortraitToTexture or circular mask.
- Icon **rarity border** (poor→legendary) from item quality.
- Previewer: rarity-colored fish icons; zone↔fish toggle verified.

## 0.2.4 (P2.4, Catches pill + catalog Show all)
- Top pills are **Catches** and **Statistics**. Inside Catches: **by zone** / **by fish** toggle (persisted per character with Show all).
- **Show all** (fixed): checked lists the static Forever/classic fishing-catch catalog (`Data_FishingCatches.lua`); items you have logged are highlighted and sorted to the top; unchecked lists only logged catches.
- By fish rows show round item icons, count/share, and **last caught zone + map coords** (stored on loot via `C_Map.GetPlayerMapPosition` / `GetPlayerMapPosition` when available).
- Search still filters the active list. Previewer updated to match.

## 0.2.3 (P2.3, Catches by zone / by fish)
- Journals → Fishing: pills **Catches by zone**, **Catches by fish**, and **Statistics**. Zone vs fish choice (and Show all) persist per character in `DarkMatterCharDB.fishing.ui`.
- Catches by fish: aggregated catch types with circular item icons (`GetItemIcon` / `SetPortraitToTexture`), count and share.
- **Show all**: off = fish-focused (excludes quality-0 junk); on = every logged catch type including junk/non-fish.
- Search bar filters the active list (zone names or catch names).
- Item ids stored from loot links for icons. Previewer mockup updated to match.

## 0.2.2 (P2.2, Fishing UI parity + lure names)
- Journals → Fishing skill strip matches the addon-previewer mockup: horizontal title | bar | subtitle on a light parchment panel (Friz Quadrata). Fixes the clipped unreadable grey line under the skill bar (was slate-grey `listSoft` text overflowing a 52px dark panel).
- Progress bars restyled (rim, dark track, gold/green fill, gloss, cream label); thin share bars for per-zone catch %. View pills renamed to "Catches by zone" / "Statistics"; zone list header "Zones".
- Favorite lure (stat #9) now shows the lure **item name** (e.g. Shiny Bauble) via enchant→item map + `C_Item.GetItemInfo` / `GetItemInfo`, not `Lure #<id>`. Legacy saved keys are migrated on read.
- Waters list: all six Classic main cities (Ironforge, Stormwind City, Orgrimmar, Undercity, Thunder Bluff, Darnassus) with minSkill 1 and fishing-subzone aliases so `GetRealZoneText` / subzone attribution counts under the city row (not Unknown).
- Catch tracking and taint safety unchanged. Adventure Guide still stub.

## 0.2.1 (P2.1, Fishing catch tracking)
- Per-character fishing stats (`DarkMatterCharDB`), starting at zero on first use: zone catch shares, casts/catches, catch rate, junk vs good, rare first-catches, time fishing, best junk-free streak, gold value (when vendor price is known), got-away casts, skill history, favorite zone and lure.
- Tracker runs on a private frame from login (casts via fishing channel, loot via `IsFishingLoot` + loot slots, got-away via UI error / timeout, skill via `GetProfessionInfo`). Zone is inferred from `GetRealZoneText` / subzone against the waters table, else last-known / "Unknown".
- Journals → Fishing: Waters / Statistics views. Waters list shows catch counts; detail shows per-item % of that zone. Statistics cards mirror the previewer layout. No "(Complete)" tags. Adventure Guide / Achievements still stubs.

## 0.2.0 (P2, Journals Fishing)
- Journals → Fishing is a real panel: fishing skill bar from `GetProfessionInfo(select(4, GetProfessions()))` (probe-confirmed), and a waters list with minimum skill floors.
- Zone list is original Dark Matter static data (`Data_Fishing.lua`): this Forever client has no fishing-zone or catch APIs (only profession skill + `IsFishingLoot`). Waters show Ready/Locked by your skill; no fake catch counts or "(Complete)" tags. Catch statistics stay for a later phase.
- Adventure Guide and Achievements sections remain "Coming soon". Quests tab, Settings click-outside, probe and blocked logger are unchanged.
- New `UI.Bar` progress widget; fishing skill events on a private frame while the Fishing section is shown.

## 0.1.3 (Settings pop: click-outside / Esc dismiss)
- Settings popover closes when you click anywhere outside it: a catcher over the main window (above content, below the pop) and a full-screen catcher under the window so a click on the world dismisses too. The Settings button still toggles open; while open, a click on Settings hits the catcher and closes without re-opening.
- Esc closes the Settings pop first (via `UISpecialFrames` on the named `DarkMatterSettingsPop`); Esc again closes the main window as before. Stock frames and private handlers only.

## 0.1.2 (fix: inactive pill fill gap)
- Fix: Journals section pills (Adventure Guide, Achievements) showed a thin horizontal gap of slate background between the metal bezel and the dark burgundy fill. The active (Fishing) pill was fine. Cause: the generated inactive middle piece (`ptab-i-m.webp`) had a transparent band under the top bezel (source rows 5-13 of 64); left/right caps had matching holes. Active pieces are flush. The inactive art is repaired by filling those gaps from the active piece's fill topology with the inactive burgundy; `tools/make_wow_textures.py` applies the same repair when packing the atlas.

## 0.1.1 (fix: window did not assemble)
- Fix: opening 0.1.0 showed one huge stretched frame corner, a flat slate area and no tabs or content. Cause: in `UI.NineSlice` the corner size was stored in a field named `t`, and the top-edge texture used the same key, so it overwrote the number. `SetSize(<texture>, <texture>)` then raised a Lua error in the client; the corners and edges never got a size and the window build aborted before the rail, tabs, body and footer were created. The size now lives in `n.size`.
- The window build now runs under `pcall`: if anything ever errors while building, the half-built window is hidden and discarded, and the error is printed to the chat frame (`Dark Matter: the window could not be built: ...`) instead of leaving a broken window.
- The active section pill no longer draws its marker over the label.
- Test harness: the stub client is now strict (argument types, `SetPoint` forms, draw layers, sublevels) and resolves layout, so the tests now assert valid texcoords (0..1, left < right, top < bottom), anchored non-zero-size textures, no texture larger than the window, an 8-piece corner-to-corner window border, content frames above the window art, and atlas rects/TGA sizes. `tools/render_preview.py` composites the window offline from the Lua's own layout and the real TGAs.

## 0.1.0 (P1, main window)
- New main window built from the approved previewer mockup: WoW theme, title plate with medal and close button, left tab rail (Quests, Journals, Map, Dungeons), footer with Settings, status field, Share stats (disabled) and Exit. Opens at screen centre, position saved on drag, **Reset window position** in the Settings popover, the Settings page, and `/dm reset`. Scales down on small screens.
- Quests tab: reads the quest log from `C_QuestLog` (read only, secret-safe, never the `GetNumQuestLogEntries` global): zone headers with collapse and an All button, difficulty colours, detail panel with objectives. Quest events are registered on a private frame only while the tab is showing, and refreshes are coalesced.
- Journals tab: Fishing, Adventure Guide and Achievements sections as "Coming soon" placeholders. Map and Dungeons: "coming in a later phase" pages.
- Theme layer: `NS.RegisterTheme`, skin hooks and piece helpers; the default WoW theme is data (`Theme_WoW.lua`, generated `Atlas_WoW.lua`) so the nine class themes can be added later as data.
- Textures: the previewer's generated art packed into power-of-two uncompressed TGAs (`Media/wow-atlas.tga` 1024x512, `wow-parchment.tga` 1024x1024, `wow-slate.tga` 512x256) by `tools/make_wow_textures.py`; 3-slice and 9-slice pieces.
- The minimap button toggles the main window.
- The probe is unchanged (0.0.4) but its report now opens in its own small stock window (`/dm probe`, `/dm raw`). The blocked-action logger is kept.
- Taint safety: stock frame types only, no hooks of Blizzard functions, no `LoadAddOn`, deferred Settings registration (`C_Timer.After(0)`), private frames for events.

## 0.0.4 (P0.3, taint-safe probe)
- Fix: 0.0.3 could make the client report `ADDON_ACTION_BLOCKED` ("DarkMatter has been blocked from an action only available to the Blizzard UI") when run in a dungeon. The probe is now strictly read-only.
- Removed every call that loads Blizzard UI or mutates/requests shared state: `LoadAddOn("Blizzard_AchievementUI")`, `C_EncounterJournal.InitalizeSelectedTier`/`OnOpen`/`OnClose`, `EJ_SelectTier`/`EJ_SelectInstance`/`EJ_SelectEncounter` and the selection restore, `RequestRaidInfo`, `C_Item.RequestLoadItemDataByID`, `GetLFGDungeonRewards`, and the `ITEM_DATA_LOAD_RESULT` counter.
- Event-registrability test runs on a private frame only and no longer touches `COMBAT_LOG_EVENT_UNFILTERED`.
- Probe refuses to run in combat lockdown. It only runs from the `/dm` command or Dark Matter's own buttons.
- New blocked-action recorder: `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` are logged to `DarkMatterDB.blockedLog` (mirrored in `probe.blocked`) with the probe step that was running; `/dm blocked` lists them and the summary shows a `[BLOCKED]` line.
- Probe now also reads the active addon restrictions (`C_RestrictedActions`) in the Game rules line.
- Journal data without UI is read-only (counts reflect the current selection and the first tier only). Findings confirmed in 0.0.3 are unchanged: Journal API present, journal data empty, LFG scan finds 67 dungeons with bosses, item reads work, loot events registrable, game rules readable.

## 0.0.3 (P0.2 probe)
- New probe areas for the Adventure Guide data-source question: Encounter Journal data without the UI (`C_EncounterJournal.InitalizeSelectedTier`/`OnOpen`, tiers, instances, known instance IDs, bosses, loot), map-based discovery (dungeon child maps, entrances, encounters on map), LFG (choice order, category entries, direct scan of dungeon IDs, boss counts), saved instances, items on demand (sample classic item IDs plus a control, checked now and again after 3 seconds), loot-learning feasibility (event registration, loot APIs), game rules (every `Enum.GameRule` read).
- Fixed: the loot-by-index call is `C_EncounterJournal.GetLootInfoByIndex` on this client; `EJ_GetLootInfoByIndex` is no longer required.
- Every call is pcall-wrapped, raw returns are saved in `DarkMatterDB.probe.calls`, and values are checked with `issecretvalue` first.
- The window shows one summary line per area (`[OK]`, `[EMPTY]` or `[MISSING]` with counts); `/dm raw` adds the raw call list. The full raw list is always in SavedVariables.
- An area that errors is recorded under `probe.areaErrors` and no longer stops the rest.

## 0.0.2 (P0.1)
- Probe loads `Blizzard_EncounterJournal` and `Blizzard_AchievementUI` on demand (pcall-guarded) before checking.
- Probe re-checks quests (`C_QuestLog.GetNumQuestLogEntries`/`GetInfo`), fishing skill (records which function worked), Adventure Guide (tiers, instances, bosses, encounter info, loot) and achievements (points, categories, sample).
- Every call's raw return types are saved under `DarkMatterDB.probe.calls`; optional APIs are no longer reported as MISSING.
- Scrollable report in the window; window enlarged; `/dm probe` opens it.
- Minimap button falls back to a round minimap when `GetMinimapShape` does not exist.
- Clearer SavedVariables report: `loadCount`, loaded-from-disk flag, previous session and previous-probe-present.

## 0.0.1 (P0 scaffold)
- Namespace, SavedVariables (`DarkMatterDB`) defaults.
- Round minimap button, draggable around the edge, angle saved.
- Placeholder stock-frame window: centre by default, position saved, reset command/button/option.
- `/dm`, `/dm probe` (saved to `DarkMatterDB.probe`), `/dm reset`, `/dm minimap`, `/dm icon`, `/dm options`, `/dm help`.
- Settings page (deferred with `C_Timer.After(0)`).
