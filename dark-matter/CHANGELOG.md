# Changelog

## 0.5.2b.2

- Ready to Turn In (option C): our own frame, DarkMatterReadyFrame on UIParent, placed just below the visible bottom of the whole objective tracker (below Quests, Professions and any other module). The tracker is only read: the lowest bottom of its visible header, its visible modules (ObjectiveTrackerFrame.modules, read with ipairs) and its visible quest blocks, minus the tracker's module spacing (10), and never above the bottom of its visible background (NineSlice). Pixel space via each frame's effective scale; our frame takes the tracker's scale and width. Never parented to, anchored to, inserted into or hooked on the tracker. Root cause of the 0.5.2b overlap: the old placement read only the quest blocks, so the Professions module below them was covered.
- It follows the tracker: re-placed 10 times a second (Tr.READY_POLL = 0.1, our own OnUpdate; only re-anchored when the position changes) and on every tracker layout pass. When Professions is collapsed (header only), hidden or has nothing tracked, the section slides up to sit right under the last visible tracker content: no gap, no overlap. With the tracker hidden (no modules to show) it sits where the tracker would be (its top left).
- The header copies ObjectiveTrackerModuleHeaderTemplate: 260 x 26, the game's UI-QuestTracker-Secondary-Objective-Header atlas, "Ready to Turn In" in ObjectiveTrackerHeaderFont (LEFT 7, width 200; the live module header's text colour read when present) and the same 16 x 16 button at RIGHT 1 (ui-questtrackerbutton-secondary-expand / -collapse, -pressed while held, yellow ADD highlight). Game atlases only, checked at runtime; a missing one draws nothing.
- Collapsed by default: header only. The button expands it to list the ready quests (rows as before: quest and zone; a click sets the game's arrow and opens Dark Matter on that quest). Saved in DarkMatterDB.readyCollapsed. The old pane border is gone; rows sit on a light backdrop below the header.
- /dm trackerprobe shows the section's state and placement.
- Tracker order fixed properly. Root cause of the reversed tracker on 0.5.2b.1: on 1.60.1 the objective tracker (QuestObjectiveTrackerMixin:BuildQuestWatchInfos / CompareQuestWatchInfos) lists quests in watch-index order (callings first, then overridesSortOrder), with no sort setting; the game re-sorts the watch list itself only on zone change (C_QuestLog.SortQuestWatches), and a NEW watch goes to the FRONT (index 1). 0.5.2b.1 re-tracked in log order assuming new watches go to the end, so the list came out exactly reversed. Now Dark Matter learns which end new watches go to from the result of its first re-order (saved in DarkMatterDB.watchInsert, learned at most once per zone change, so it can never flip back and forth) and, on the front end, re-tracks only the quests before the already-correct tail, in reverse log order, so the tracker ends up in log order (lowest level first, as the quest log). A result that shows up a moment later is checked again after the next settle; a client that keeps its own order still makes it stop (no loop, nothing untracked or unpinned).
- /dm trackerprobe now also logs which end new watches go to (and whether learned or saved), the log order of the tracked quests, the watch order (index 1 first), the tracker's blocks top to bottom, and "tracker vs log: SAME order" or "DIFFERENT from position N (...)", so it can be checked from the saved file after /reload.
- Tests: OrderFix on the front end, learning "front" from the reversed 0.5.2b.1 state and then reaching log order, only the needed quests re-tracked, the delayed-result path, a client with its own order, and the new trackerprobe lines.
- Tests: collapsed by default, the header atlas, text and button, pressed atlas, expand / collapse saved, row click, the no-overlap test across 18 tracker heights (Quests growing and shrinking, Professions expanded, collapsed and empty, scale 1 and 0.8: always exactly one spacing below the last visible content), the tracker background, the hidden tracker, a missing atlas, and that the tracker's modules get no script, anchor or parent.

## 0.5.2b.1

- Keep-tracked pins on the objective tracker are bigger: 17 px (were 14).
- Zone auto-track is now ON by default (a one-time switch for existing saves, DarkMatterDB.autoTrackV = 1; `/dm autotrack off` still turns it off). On ZONE_CHANGED_NEW_AREA, PLAYER_ENTERING_WORLD and after a flight lands (PLAYER_CONTROL_GAINED), it tracks this zone's quests plus the kept ones and untracks the rest. Batched, out of combat only. Root cause of "zone change did not update All Objectives" in 0.5.2b: auto-track was off by default, and the game itself does not re-track by zone.
- Keep pins are a sticky flag that only your click on the pin changes. Highlighted (pinned): the quest stays in the All Objectives tracker in every zone. When pinned it is tracked straight away, and if the game drops it on a zone change it is tracked again; with auto-track off it is also tracked again after each zone change. Dim (not pinned): the quest is like any other: zone auto-track tracks it in its own zone and untracks it elsewhere (with auto-track off, the game's normal tracking). Unpinning does not untrack; the quest follows auto-track from the next zone change. Tracking or untracking (the Quests tab and Quest Log panel Track boxes, the game's quest log box, the game's auto-watch, auto-track) never pins or unpins, and the 0.5.2b pin-on-track / unpin-on-untrack link and first-run pinning are gone. Abandoning or turning in a quest still drops its pin. All pins start unpinned: on the first load of 0.5.2b.1, DarkMatterDB.keepTracked is cleared ONCE (flag keepV = 1), because 0.5.2b may have pinned quests on track. Your later clicks are saved per quest across reloads and logouts.
- Track boxes (Quests tab, Quest Log panel) just track and untrack; new tooltip.
- The Map tab glide (zoom out, pan, zoom in, used by Show on map and other fly-tos) is about a third slower: its total time is x1.32 (0.8-1.4 s became about 1.06-1.85 s), with the same easing.
- Removing a map pin (right-click) also clears the game's user waypoint and minimap arrow, but only when that waypoint is this pin's (C_Map.ClearUserWaypoint, and the super-track is cleared). Dark Matter only sets the game's own user waypoint (C_Map.SetUserWaypoint + C_SuperTrack); other addons that show it (OpenMap) follow the game. No OpenMap API is called.
- The objective tracker follows quest-log order (zone groups, lowest level first). The tracker lists quests in watch order, and the game re-sorts that order on zone changes (C_QuestLog.SortQuestWatches). About a second after a watch or zone change, out of combat and not in flight, Dark Matter re-tracks the quests from the first one out of place on, in log order (a new watch goes to the end). Only the public watch API is used, and pins do not change. If the client keeps its own order anyway, it stops until the next zone change (no loop). `/dm trackorder on|off`; /dm trackerprobe shows the status.
- Not shipped: Ready to Turn In between Quests and Professions inside All Objectives. The only ways in are a module registered with the game's tracker container or a top-padding provider. Either one taints the tracker's update, and that update sets up the quest item buttons, which call protected code. The Ready section stays under the tracker as in 0.5.2b.
- Tests: pins change only on a pin click (Track boxes, the game's log, auto-watch and auto-track never pin or unpin), the one-time pin reset, a pinned quest kept with auto-track on and off, an unpinned one following auto-track, auto-track after landing and on PLAYER_ENTERING_WORLD, the defaults and migration, waypoint clearing (only our own), pin size, log-order re-tracking (wait, combat, no pins changed, give-up with no loop, off), and a source scan that nothing is registered with the game's tracker.

## 0.5.2b

- Keep-tracked pins on the objective tracker. Beside each quest row there is a small Dark Matter button (our own button on UIParent, only positioned next to the row's map button; nothing is put into the tracker). A pinned quest stays tracked when the game untracks it on a zone change. Tracking a quest yourself pins it; untracking or abandoning it unpins it. On the first run the quests you track now become pins. Saved in DarkMatterDB.keepTracked.
- The keep icon is a game icon, checked at runtime, never bundled: map pin (atlas Waypoint-MapPin-Tracked / -Untracked, the default when present), lock (Interface\Buttons\LockButton-Locked-Up / -Unlocked-Up) or star (atlas PetJournal-FavoritesIcon). `/dm keepicon pin|lock|star|auto` chooses. A chosen icon this client lacks draws nothing.
- Tracker title click: a transparent area over each quest title opens Dark Matter on the Map tab, glides to the quest and shows its detail in the docked Quest Log panel. The item and map buttons stay uncovered (the area stops before them).
- Ready to Turn In: our own themed section under the tracker (placed by reading the tracker's lowest visible row). Each row shows the quest and its zone; a click sets the game's arrow (super-track) and opens Dark Matter on that quest. The Quests tab and the Quest Log panel also get a "Ready to Turn In" group at the top. NPC names come with 0.6.0.
- Zone auto-track (option, off by default; Settings page or `/dm autotrack on|off`): tracks this zone's quests plus pinned ones and untracks the rest. On a flight it waits for the landing, then switches once. Changes go out in batches of 5 about a second apart, only out of combat.
- Your own map pins: the Pin tool on the map's tool strip now works. Click it, then click the map to drop a pin (saved in DarkMatterDB.userPins, up to 50). The game's own waypoint and minimap arrow point at it. Click a pin to point at it again; right-click removes it. Drawn with the game's Waypoint-MapPin-ChatIcon atlas only (nothing drawn without it).
- M and L keys: M and L open Dark Matter on the Map tab with the Quest Log panel (pressed again they close it); ALT-M opens the game's world map and ALT-L its quest log. Session-only override bindings owned by a Dark Matter frame, set out of combat only (re-applied after combat), never saved to your key bindings. Off with `/dm keys off` or the Settings page.
- New `/dm trackerprobe` (read-only): the tracker, the keep icon candidates (ok / missing) and the counts, saved in DarkMatterDB.probeLog.
- No hooks on the tracker, its clicks or the quest log; no LoadAddOn.
- Tests: keep pins (first run, your track, the game's auto-watch, zone-change re-track, untrack, abandon), the overlays (UIParent parents, anchors, the title area stopping before the item button, no script, anchor or parent on any tracker frame), title click, the Ready section and its click, auto-track (off, flight, combat, batches, pins kept), the keys (owner, combat queue, off, M/L press, SaveBindings never called), your map pins, and source scans for hooks, SaveBindings, LoadAddOn and SetParent.

## 0.5.2a.2

- Clicking a quest pin on the map opens THAT quest's detail in the docked Quest Log panel. If the panel is closed it opens; if it shows the list or another quest it switches to this one. Back still returns to the list. The map stays still (no glide). Shift-click still only sets the game's waypoint. A quest not in your log leaves the panel on its list.
- The window is 26 px narrower in every theme: the width the narrower tab column freed in 0.5.2a.1 now comes off the window instead of going to the content. The content area and the Map tab's map area keep their 0.5.2a size (978x544 map area at the stock map's size). The height stays the stock map's height, and the saved position is kept. Target width = the stock map window's outer width less 26 (theme metric railTrim). Without a readable map window the fallback is 854x680.
- The self-measure check after layout and the size probes use the new target: /dm frameprobe (frame 2, 2b and 2c: "outer ... vs target ... (map ... less 26)") and /dm mapprobe (new line "map 20 target").
- Tests: pin click opens the detail (from closed, from another quest, from the list), Back, unknown quest, no map movement, shift-click leaves the panel alone. Window sizes are now expected at the map's width less 26 in every theme and map size, and the content keeps its 0.5.2a widths.

## 0.5.2a.1

- Map quest pins all use the game's own yellow icons, as the game map does: yellow ? (QuestTurnin / ActiveQuestIcon) for every quest in your log, in progress or ready; yellow ! (QuestNormal / AvailableQuestIcon) for available. No grey, no tints, no red failed tint, nothing bundled.
- Clicking a pin now only selects its quest (the map stays put). Shift-click still sets the game's waypoint. The smooth fly (zoom out, pan, zoom in) is used only by "Show on map".
- New docked quest panel: while the Map tab is open, a Quest Log panel sits beside the window, like the game's map and quest log. It is locked to the window (it moves and scales with it) and themed in every theme.
  - The top is the stock quest log's search bar: the game's SearchBoxTemplate (magnifier, "Search Quest Log") and the yellow "Quests: n/max" count box. The count and maximum come from the game's API. Typing filters the list.
  - Same list, groups and Track boxes as the Quests tab (shared code, no copy), with hover both ways between rows and map pins.
  - A row click selects the quest (its pins glow) and opens its detail: title, objectives with progress, description and rewards (the Quests tab's detail). Back returns to the list with the scroll position and search text kept.
  - Open or close it with the new "Quest log" button on the map's tool strip or the panel's close button. Dark Matter remembers the choice (DarkMatterDB.questPanel).
  - The window plus the panel fit a 1920x1080 screen at UI scale 0.64.
  - The Quests tab stays as it was.
- Left tab column (Quests, Journals, Map, Dungeons): the inset now hugs the buttons with a small margin in every theme. The 26 px freed go to the content area; the window keeps its size.
- Every /dm probe (probe, blocked, agscan, questprobe, questmap, mapprobe, artprobe, frameprobe, achprobe) also saves its output lines with a timestamp in DarkMatterDB.probeLog. Only the last run of each probe is kept, capped at 400 lines of 400 characters and 16 probes. It is written to disk on /reload or logout.
- /dm artprobe re-checks templates asked for since the last check (no false MISSING after a theme change).
- Tests: the panel (docking, count, search, detail and Back, hover both ways, toggle remembered, shown only with the Map tab, fits 1080p at 0.64, no hooks), pin clicks do not move the map, Show on map still flies, yellow untinted pins, the narrower tab column with the window size unchanged, the probe log and its caps.

## 0.5.2a

- Quests on the map, game data only (first part of the quest work; the database and Ready to Turn In come in 0.5.2b / 0.6.0).
- Map quest pins use the game's own icon textures only (file path or atlas, checked at runtime; nothing bundled): grey ? for a quest in progress, yellow ? when it is ready to turn in, a red tint when failed. If this client lacks an icon, no pin is drawn for it (no substitute); `/dm questmap` lists any missing ones.
- Pins are clickable: a click selects the quest in the Quests tab and flies the map there smoothly (zooms out, pans, zooms back in). Shift-click sets the game's own waypoint and arrow. Dragging over a pin still pans the map.
- Hover sync both ways: hovering a pin lights its row in the Quests tab; hovering a row (or selecting it) makes its pins bigger with a glow.
- Quests tab: new "Show on map" button. It opens the Map tab and flies to the quest (and sets the game's waypoint and arrow). If the game gives no location, it shows the quest's zone with a note.
- New `/dm questmap` (read only, saved): which quest, waypoint and arrow APIs this client has; what GetQuestsOnMap returns; what Show on map would use; each candidate game icon (ok or MISSING); the objective tracker's structure, and whether its quest rows could take an extra click target in 0.5.2b.
- New QuestState.lua: the shared selected, hovered and arrow quest. No hooks, no LoadAddOn, no stock frames touched. Waypoint and arrow calls happen only on a click.
- Tests: pins, game icons with a missing icon drawing nothing, click, shift-click, drag over a pin, hover both ways, the hop flight, Show on map (point, zone with note, none), the probe, and taint checks for QuestState.lua.

## 0.5.1.11

- Map: no more empty gaps. The continent art is always drawn as the base under its zones (at any magnification), and the world art shows wherever the continents' full-strength interior doesn't cover the view. Zone edges feather into the continent (never to black, no vignette). Zones fade in over the continent as one fills the view, like the stock map.
- Map: the world fills the whole view when fully zoomed out (cover fit, no empty band).
- Map: drag is free again at every zoom. The hard pan lock is gone; cover framing is used only to open the map, for Find me (which centres on you again), search and fly-to. While dragging, at most one new layer is built per frame, so there are no stalls.
- Map: neighbouring zones come back as you drag off a zone (the zone's share of the view is now the area it actually covers).
- Tests: a coverage sweep (142 views from world to deepest zoom, fit and full-screen sizes, every theme) shows a full-strength map base under every pixel. No darkening vertex colours. Dragging at every zoom moves the view by exactly the drag.

## 0.5.1.10

- Window size: unchanged (passed in 0.5.1.9).
- **Map, zone view fills the box, like the stock map.**
  - A zone (or city) opens and flies in at **cover** scale: its art fills the whole map area.
  - The view is **locked** on that zone: dragging stops at the art's edge.
  - Zooming out at the zone's fit goes up to the continent; right-click does the same.
  - Zooming in at continent level locks on the zone under the middle as soon as that zone fills the view.
  - Moving to a neighbouring zone: zoom out to the continent, then in.
- **Map: no blurry continent or world art.**
  - The continent picture fades out between x1.12 and x1.20 magnification, so it is never drawn above x1.20.
  - The zone pictures (all of a continent's together) take over between x1.00 and x1.12 continent magnification.
  - The world picture is gone by x1.50.
  - Where no art covers the view: plain parchment, or the minimap tiles when they are on.
- **Map: explored overlays** are tiled exactly like the stock map: tile count from the overlay's size
  (ceil(size / 256)), not from the entry's numTextures fields, and the last row/column cut inside a power-of-two
  file. This is the likely cause of the stretched strip left of the IRONFORGE banner.
- mapprobe line 22 adds the zone the view is locked on and the continent art's magnification (drawn / off).
- **No title text** in any theme. The WoW theme's title bar stays empty.
- Class themes: the top crest and the bottom emblem are **centred** on the frame again.
- The status text is **left-aligned** (10 px in) in every theme. In class themes it ends 8 px before the bottom
  emblem, with '...' when it does not fit.
- Tests:
  - zone view covered and locked; panning held at the zone's edge;
  - no continent art above x1.20;
  - uniform texcoord-to-size ratio for every zone-art tile;
  - overlay tiling from the overlay's size;
  - every theme: no title, crests centred, status text clear of the emblem.

## 0.5.1.9

- **Window size is right on the first open, with no need to open the stock map.** A map window that has never been
  shown still reports the old 1002-wide size and a stale rect. That stale size is what built the 1019x713 Warrior
  window: the frameprobe's computed rows used the live size, while the window had been built from the stale one.
  Order now:
  1. The stock map is open: measured on screen.
  2. It was shown earlier this login: measured.
  3. Never shown: `GetSize()` x its scale, if that is a real size (at least 1100x600), plus the client's border
     (16,19,2,10 px).
  4. Otherwise the saved size (same UI scale), then the built-in default for this client: 1232x705 at the map's
     scale, outer 1247x729 UIParent units at UIParent 0.64.

  The metrics are sized at PLAYER_LOGIN and again before every open. After the window is laid out, it is measured
  (frame + the theme's drawn border). If it is more than 1 px off, it is built again (once per theme and size, so it
  can never loop). Box tests: a fresh login with the map never shown (real size, 0x0, stale 1002x694), every theme:
  outer 1247x729 within 0.33 px, no rebuild.
- **Map, zone view: one zone picture.** At zone view only the focused zone's own art and explored overlays are drawn,
  over the continent picture, as on the stock map.
  - Neighbours fade out as the zone fills 55-70% of the view and only come back at continent zoom, together.
  - A city's picture (Ironforge, Stormwind City) is never drawn over its zone. It fades in cleanly on top only when
    the city itself is the focus (it fills 45-60% of the view).
  - mapprobe line 22 lists what is drawn: the zone, the number of other zones, the city.
- **Title and emblems.** In the class themes:
  - The top crest moves beside the title when it would cover a letter.
  - The bottom emblem moves to the right end of the status box when it would cover the status text, and the text
    keeps clear of it on both sides.
  - Tested for every theme.
- Zoom thresholds unchanged: art alone to x2.0, tiles full by x2.6.

## 0.5.1.8

- Map: the drawn place-name labels are gone (code, probe line and tests). The game's own map art carries the names.
- Map zoom layers work like OpenMap's now. The game's map art (continent, zone or city) shows on its own at full
  strength, with no minimap tiles, tint or grain, until that art is magnified past **x2.0** (px per art texel, read
  from the top-most map picture under the middle of the view, so a city uses its own art). The tiles then crossfade
  in quickly and are at full strength by **x2.6**, about one wheel step. Default strength 45% = full tiles
  (DEEP_K 2.25). Without map art under the view the fallback is 5 yd per texel.
- Map: zone pictures fade in over the continent picture quicker: the largest zone at 45-55% of the view, before 40-70%.
- mapprobe line 19 shows the layer ("zone art" / "crossfading" / "tiles"), the art magnification and the
  thresholds. Line 21 shows only the seam counts.
- Window size: the stock map window is measured only while it is open, and that size is saved in DarkMatterDB
  (mapWindowSize). The saved size is used straight away at login and on open, before the stock map was ever opened.
  Dark Matter rebuilds only when the size is more than 1 px off. Applies to every theme.
  Blizzard_WorldMap is NOT force-loaded: the add-on's no-LoadAddOn safety rule stays. It is already loaded at login.

## 0.5.1.7 (fix: place names stay readable up close; no patches at continent/world view; class themes get the WoW theme's map space)
From the in-game 0.5.1.6 check. Frame size and portrait removal passed and are unchanged.
- **Place names on top of the tiles.** The zone pictures carry their names in the art, and the minimap tiles covered them as they took over. Dark Matter now draws the names of the ground you have explored as text above the tiles: the game's explored-area IDs, sampled across the zone (`C_MapExplorationInfo.GetExploredAreaIDsAtPosition`), named by `C_Map.GetAreaInfo`. They fade in as the tiles do (none while the tiles are off, so the art's own names show), and are kept apart so they don't pile up. Read once per zone; read again when exploration changes. Game data only, no art.
- **No patches at continent and world view.** The zone pictures of a continent now fade in together (keyed to the continent's largest zone), so a continent seen whole is no longer a patchwork of zone pictures at different strengths. The breadcrumb still uses each zone's own share. Continent pictures drawn over the world picture are now feathered at their rim too; only the world picture (the base) is not.
- **`/dm mapprobe` line 21:** the place names drawn on top, how many map pictures are on screen, how many are feathered, the base, and the count of unfeathered picture edges (0 expected).
- **Class themes have the WoW theme's map space.** With the game's map window readable, a class theme's frame art is fitted into the same outer rectangle the WoW theme fills: its rim and header band span the map border's reach plus our title area, so the class theme uses the WoW theme's layout. Its Map tab's map rectangle now equals the WoW theme's (1232x705 map: 978x544 in every theme in the tests, before: smaller by the class art's overhang). The art is drawn finer (thinner rim, smaller crest), with crest, base plate and edge sprites kept inside. The footer uses the WoW row, and the title sits on a slim plate (dark or light to suit the theme's title colour). The outer frame size is unchanged.
- **`/dm frameprobe` line 2c** now also prints each theme's map rectangle ("map area").
- **Tests:** every class theme's map rectangle equals the WoW theme's within 2 px (4 map sizes with the client's real border offsets); the outer-bounds test still passes in every theme; place names (from area IDs, off while tiles are off, shown on top when they take over); every picture on screen feathered or the base; a continent's zones drawn at one strength.

## 0.5.1.6 (fix: outer bounds equal the stock map window's in every theme; no portrait; a middle layer up close)
From the in-game 0.5.1.5 check (Wetlands, Dun Morogh, Loch Modan, client 1.60.1).
- **No portrait icon, any theme.** The top-left portrait is gone. In the WoW theme the corner is a plain metal corner: the game's own `UI-Frame-Metal-CornerTopLeft` atlas when the client has it, else its top-right corner drawn mirrored, placed where the map window's own corner sits. The title strip is centred between equal insets.
- **Same outer window, border to border.** The target is the stock Map & Quest Log window's whole visible outer rectangle on screen: `WorldMapFrame`'s rect joined with its border corner pieces (which reach past `GetSize()`) and the quest log panel when shown, read with GetLeft/GetRight/GetTop/GetBottom (read only; size + corner offsets when the rect cannot be read). Our outer rectangle is our frame plus each theme's border (the WoW corners; a class theme's frame art, edge sprites, crest and base), and the layout is sized so the two are equal in width and height, at the map's exact shape. The 0.5.1.5 "map changed shape: /reload" fallback is gone: when the map window changes size, or another theme (another border) is chosen, the window is built again at the right size (asked twice in a row, so a map still resizing is not chased); the saved position keeps its screen spot.
- **`/dm frameprobe`** lines 2c (per theme: outer size vs the map's outer size, and the difference) and 2d (both outer rectangles in screen pixels, the map frame's own rect and how far its border sticks out, and the width/height difference). `/dm mapprobe` line 20 prints both outer sizes and the difference.
- **Close-up: a middle layer.** The crossfade is much wider: from 0.10 to 0.30 px/yd the tiles come in at only 35% of their deep strength, so the zone picture and its explored overlays stay visible under them through mid zoom; they take over only from 0.35 to 0.80 px/yd. Tiles are lighter and warmer (desaturated half way, a warm tint, and a second ADD pass of the same tile in a parchment tone that lifts them toward the zone art's brightness instead of darkening it). No OpenMap texture of any kind is used.
- **No rectangular seams.** Each zone picture and its explored overlays fade to 0 over their outer 64 px (feathered cells with vertex gradients), so zones drawn side by side, and over the continent picture, leave no rectangle edge or square overlay edge.
- **Tests:** every theme x 7 map sizes (incl. 1232x705 at scale 0.64, with the client's real border offsets) asserts our drawn outer bounds equal the map window's outer bounds to 1 px (worst 0.49 px), with the window rebuilt each time; no portrait texture in any theme; the frameprobe per-theme and rectangle lines; the new crossfade and warm pass; zone rims fade to 0.

## 0.5.1.5 (fix: the window matches the map window on screen; the close-up blends across the whole view)
From the in-game 0.5.1.4 check (Wetlands, client 1.60.1).
- **Window size, on screen.** 0.5.1.4 took the map window's size in UIParent units but then shrank our window to fit the screen (the old fit-to-screen scale), so it came out a different size from the game's map (frameprobe: map 1232x705 at effective scale 0.64; ours 1004x689, then scaled down). Now the window covers exactly what the map window covers on screen: its GetWidth / GetHeight times its effective scale over UIParent's. One rule, maximized or windowed. The layout keeps at least 880x500 and at most 1800x1300; beyond that our own scale makes up the difference, so the on-screen size still matches. While our window is shown it re-reads the map window every half second (from our own frame: no hook on WorldMapFrame, read only) and follows a resize with its scale; the saved position keeps its spot on screen. If the map window changes shape, ours fits inside it and frameprobe says "/reload" to re-fit the layout.
- **Close-up detail blends across the whole view.** The explored-only cut into 4x4 cells made hard-edged square patches. Now every minimap tile in view is drawn whole (one texture each, edge to edge, no overlap), explored or not, desaturated and tinted toward the parchment. Where the tiles end (sea, void: no tile in the table, or a file that will not load), the neighbouring tiles fade out over half a tile with vertex alpha gradients, so no block edges. Fades: the tiles mix in from 0.12 px/yd, reach the chosen strength (default 45%) at 0.24 and run deep toward 85% by 0.48. Up to 144 tiles in view, faded out from 96 (no pop).
- **Placement checked.** `/dm mapprobe` line 17 now prints your tile's rectangle on the zone map and whether you are inside it ("map 17 check"). The Wetlands numbers from 0.5.1.4 (corners -2148,-390 / -4904,-4525; you at -4254,-3108 on tile 37_39) are a test case.
- **`/dm mapprobe` line 20 / `/dm frameprobe` line 2b:** the effective scale of the map window, Dark Matter and UIParent, and both windows' on-screen sizes. Line 19 "now" also shows the alpha actually drawn.
- **Tests:** on-screen sizing (the Wetlands case, smaller / larger / maximized maps, the live rescale keeping the position); the close-up covers the whole view with whole tiles, feathers to 0 at a gap, fades between 96 and 144 tiles; the Wetlands tile placement.

## 0.5.1.4 (the game's minimap tiles up close, a window the size of the game's map, the WoW theme as the map window)
- **Close-up detail on the Map tab.** Zoomed in past the zone picture's own sharpness, the Map tab now draws the game's own minimap tiles, loaded from the client at runtime **by file ID** (no file is bundled; Dark Matter needs no other addon). The tile file IDs come from OpenMap's MIT-licensed `Data/Minimap.lua` table, copied as `Data_Minimap.lua` with its licence and credit (`LICENSES/THIRD_PARTY.md`); the drawing is Dark Matter's own code (`MapCloseUp.lua`), after OpenMap's ideas:
  - tiles of 533.33 yards on each continent's 64 x 64 grid; fades keyed to screen pixels per yard: the tiles mix in from 0.20 to 0.34 px/yd at the chosen strength and take over (toward 1.9x the strength, 85% at the default 45%) from 0.30 to 0.48 px/yd;
  - softened toward the parchment (desaturated 0.35, tinted 1 / 0.93 / 0.80) with Dark Matter's own faint paper grain (0.08 to 0.18 px/yd); no middle layer between the zone picture and the tiles;
  - **explored ground only:** each tile is cut into 4 x 4 cells and a cell shows only where the zone's explored overlays (`C_MapExplorationInfo.GetExploredMapTextures`) cover it; the cells of a row are merged into strips (no overlap, no dark seams). Zones without overlays (cities) show the zone picture only;
  - at most 64 tiles in view (further out: the zone picture alone); textures are pooled; a tile that fails to load is remembered and skipped;
  - the deepest zoom is now twice the minimap's own sharpness (0.96 px/yd);
  - new 6th tool on the right strip, **Close-up detail**: on / off and a strength slider (saved in `DarkMatterDB.map.closeUp` / `closeMix`). The status line reads "Map: the game's map pictures + the game's minimap tiles up close" (or "Map: the game's own map pictures" when it is off).
  - Taint-safe: own frames and textures only, no hooks, nothing protected; works in combat. OpenMap is never read: no path into its addon folder anywhere in Dark Matter, and none of OpenMap's textures (its notice says they are not MIT) is copied, referenced or needed.
- **The window is the size of the game's map window.** Dark Matter reads `WorldMapFrame`'s size at runtime (read only: no Show, no hooks, no writes, so nothing is tainted), scaled to UIParent; when the map is maximized it takes the windowed size (`minimizedWidth` + `questLogWidth`, `minimizedHeight`). Clamped to 880-1800 x 500-1300 (every tab still lays out); unreadable: Dark Matter's own 880x680. Every tab follows: lists, detail panes, the map, footer buttons and status line grow with the window; rail, title and tabs keep their places. Class-theme frame art keeps its scale; its edges run longer. The saved position is kept.
- **WoW theme: the game's Map & Quest Log window.** The default theme now wears the map window's own frame, read from `WorldMapFrame` at runtime and drawn again on Dark Matter's frame with the same game textures (atlas, path or file ID; nothing bundled): its 8 border pieces, the slim dark title strip with the gold title, its red close button (Normal / Pushed / Highlight) and its portrait. When the pieces cannot be read, Dark Matter draws its own thin frame (dark outer line, bronze inner line) and the stock close button. The content sits on a dark inset (`FrameGeneral\UI-Background-Marble`). The map breadcrumb looks like the stock map's top-bar buttons: the first (world) on the red button face, the others on the dark field face with a small down arrow, no ">". Class themes are unchanged (their plain breadcrumb keeps ">"). The 0.5.1.3 buttons, scroll bars and tabs (no dots) and the parchment detail panels (no black row boxes) are unchanged.
- **`/dm mapprobe`** (new lines 5 and 16-19): art layer count and min/max scale for the zone, continent and world; the current zone's corners in yards; your minimap tile and its file ID; whether that tile loads by file ID and by path; whether OpenMap is loaded (information only: not used); the close-up setting, the map's source line and what the close-up drew last (tiles, pieces, mix, px/yd).
- **`/dm frameprobe`** (new): the game's map window, read only: its size, scale, maximized and windowed size; the size Dark Matter took and from where; each of the 8 border pieces, the title, close button (normal / pushed / highlight), portrait, background and the map top bar's home button, by atlas / file. Saved to `DarkMatterDB.frameprobe`.
- **`/dm artprobe`:** re-checks a texture that was missing at first look (the crumb arrow loads late on some clients).
- **Tests:** fades and the max zoom; explored-only cells, strips that never overlap; the 64-tile limit; texture pooling; a tile that fails to load; no path into OpenMap's addon folder anywhere in Dark Matter and identical drawing with or without OpenMap installed; `WorldMapFrame` only read (a spy fails on any write or Show); window sizes 1035x640 (also at map scale 1.25), 500x300 (clamped to 880x500), 2400x1600 (clamped to 1800x1300), a maximized map (its windowed size), no map window (880x680), in combat; every tab inside the window at each size (the whole suite runs at 1035x640, 760x500 and 2400x1600 too); WoW theme: the 8 mirrored border pieces, title, close, portrait, breadcrumb faces; the own thin frame when unreadable; class themes unchanged.

## 0.5.1.3 (pressed faces that fill, scroll bars in a gutter, no dots, every theme on the stock kit, late reward items)
- **Pressed buttons fill the button.** Every stock-feel button draws its Normal, Pushed and Disabled face and its Highlight with one geometry, the way `UIPanelButtonTemplate` lays them out: a left and a right cap of a fixed width (12 px for panel buttons, 20 px for the character-frame tabs) at the full height, the middle stretched between. A state change only swaps the file, the anchors never move. 0.5.1.2 scaled the caps with the button height, so on the 48 px nav tabs the Down art's inset edge showed as a dark gap at the right end of the pressed face; and the current nav tab was drawn 14 px wider than the others. All nav tabs are now one width, the held-down one too. The Highlight is the same 3-slice (it used to span the whole button in one piece). Checked at widths 40 / 80 / 132 / 146 / 300 and heights 22 / 48.
- **Scroll bars in their own gutter.** Every scroll bar sits outside its pane, in a 30 px gutter on the pane's right (the stock quest log's placement): top arrow level with the pane's top, bottom arrow level with its bottom, the groove the pane's full height. The pane is 30 px narrower to make room, and its rows use the full content width. Quests list and detail, Adventure Guide boss list and boss detail, Fishing zones, catches and statistics, Achievements categories and list. (The dungeon dropdown keeps its bar inside.)
- **No dots.** The marker dot / red target radial is gone from every tab and toggle in **all** themes (0.5.1.2 removed it in the WoW theme only); the held-down face or the raised tab marks the active one.
- **Class themes on the stock kit.** The nine class themes now use the game's own button, tab and scroll-bar art too (`UI-Panel-Button-*`, `UI-Character-ActiveTab / InActiveTab / Tab-Highlight`, `UI-ScrollBar-*`, `UI-Character-ScrollBar`), desaturated and recoloured in each theme's palette with `SetDesaturated` + `SetVertexColor` (e.g. Hunter: green buttons, brown tabs and scroll bars; Druid: leaf green and bark; Mage: arcane blue). New `Theme_ClassStock.lua` holds the palettes. Labels keep each theme's own button ink (a dark ink on the recoloured faces gives way to a warm light one). Each theme keeps its frame art, crest, ornaments, colours, accents and animations.
  - **The inner content blends into the frame:** no second boxed window. The page and the inner box lose their own fill and frame; the nav rail and the page get a subtle inset divider (dark top and left, faint light bottom and right), and the list borders are softened (`theme.blend`).
- **`/dm artprobe` names the missing piece on one line.** On 1.60.1 the one missing item is the **`CharacterFrameTabButtonTemplate`** template (35 ok, 1 missing). It was never needed: the section tabs are built from the `UI-Character-ActiveTab / InActiveTab` textures, which the client has, so they draw the stock tab art either way. The summary line now says so: `artprobe: 35 ok, 1 missing: CharacterFrameTabButtonTemplate (template) -> tabs use UI-Character-ActiveTab/InActiveTab`; each MISSING line ends with what stands in, and `DarkMatterDB.artprobe.missingNames` keeps the list. (With more than three pieces missing, the summary says the missing pieces use Dark Matter's own art.)
- **Reward items that load late.** A quest reward the client has not loaded yet shows "Loading…" instead of "Item not loaded yet" (name from `GetItemInfo` when the item cache already has it; otherwise `C_Item.RequestLoadItemDataByID` asks for it). The quest detail redraws when `GET_ITEM_INFO_RECEIVED` or `ITEM_DATA_LOAD_RESULT` arrives for an awaited item (other items' events are ignored). The Adventure Guide drop list refreshes on `ITEM_DATA_LOAD_RESULT` too.
- **Tests:** face and highlight anchors identical at five widths and two heights, Up and Pushed, in the WoW, Hunter and Priest themes; one nav-tab width; section tabs and toggles; every scroll bar in its gutter (nine panes, WoW and Hunter) with the groove the pane's height and the stock pieces recoloured in class themes; no marker dot in any of the 10 themes; class themes draw only the recoloured stock kit (no stock window art); the 1.60.1 artprobe case (CharacterFrameTabButtonTemplate missing) on one line, tabs still on the stock art; "Loading…" and the redraw on `ITEM_DATA_LOAD_RESULT`.

## 0.5.1.2 (WoW theme: stock button feel, character-frame tabs, item rows on the parchment, stock scroll groove)
WoW theme only; the nine class themes are unchanged.
- **Buttons feel like the game's own.** Every WoW-theme button (rail tabs Quests / Journals / Map / Dungeons, Settings, Share stats, Exit, Reset window position, the theme picker, the Achievements filter, the quest list's All, the filter toggles) now behaves like `UIPanelButtonTemplate`: Normal / Pushed / Disabled faces from `Buttons\UI-Panel-Button-Up / -Down / -Disabled` (texcoords 0..0.625 x 0..0.6875, as the template's left / middle / right slices), `UI-Panel-Button-Highlight` over the whole button with ADD blend on hover, the label 1px right and down while the mouse is held, the stock click sound (`SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON`, old sound name as fallback), gold normal / white highlight / grey disabled labels. Dark Matter's own hover tint and 1px edge are gone on these buttons. Rail tabs and filter toggles stay held down (Down face, white label) while on; the current theme's button in Settings likewise. A disabled button (Share stats) shows the Disabled face, does not press and has no highlight.
  - Built by hand from the template's own files rather than created from the template: the window switches theme live and a template button cannot drop its art again for the class themes. `/dm artprobe` reports the templates (`UIPanelButtonTemplate`, `CharacterFrameTabButtonTemplate`, `UIPanelScrollFrameTemplate`, `UIPanelScrollBarTemplate`) so the client's set is on record.
- **Section tabs (Adventure Guide / Fishing / Achievements)** behave like the character-frame tabs: the selected tab raised (`UI-Character-ActiveTab`, white label, no hover), the others darker (`UI-Character-InActiveTab`, gold label) with `UI-Character-Tab-Highlight` on hover; no press offset, the tab sound.
- **No marker dots.** The little red target dot is gone from the section tabs, the filter toggles (All levels / Near my level, by zone / by fish, Catches / Statistics) and the quest list's All button (now a plain stock button labelled All). The quest zone headers keep their stock +/- collapse buttons.
- **Item rows straight on the parchment.** Adventure Guide boss drops and quest rewards no longer sit on black name plates: icon plus the item name in its quality colour, darkened just enough to read on the parchment (4.5:1; Common items in the dark quest ink), the detail line ("Rare · 41.0% drop · not seen yet") in dark-brown ink, no text shadow. Hover keeps the tooltip and adds a faint warm highlight.
- **Scroll bars:** the solid dark track is replaced by the stock groove `PaperDollInfoFrame\UI-Character-ScrollBar` (the quest log's: top piece, stretched middle, bottom piece), behind the stock 16x16 buttons and the 18x24 knob; the scroll buttons click with `SOUNDKIT.U_CHAT_SCROLL_BUTTON`. Missing file: the old track.
- **Tests:** stock faces Up / Down / Up across a press, the 1px label offset, gold / white / grey labels, highlight file / layer / blend / texcoords, click sound, a disabled button that does not press; rail tabs held while active; section tabs ActiveTab / InActiveTab with the tab highlight and no press offset; filter toggles; no marker dot anywhere; drop rows and rewards without plates and readable on the parchment; the groove drawn; `/dm artprobe` lists the new files and templates (36 ok); class themes and the missing-art fallback unchanged.

## 0.5.1.1 (fix: every panel fully filled; stock scroll buttons; achievement toast)
- **Parchment no longer stops mid-panel.** The stock `QuestFrame\QuestBG` file is 512x512 but its parchment sheet only covers about the top-left 300x336 texels, with torn edges and transparency beyond. 0.5.1 drew the whole file (texcoords 0..1) over each panel, so the parchment covered only the top-left ~59% x 66% of the page and the quest detail, with a torn edge in the middle. Now:
  - the page (the area behind the lists, on every tab) is the stock `FrameGeneral\UI-Background-Rock`, tiled, a little darker than the window; its text (dungeon header, Fishing skill strip, "Show all", stubs) is gold / white / grey;
  - the **quest detail** and the **Adventure Guide boss detail** are parchment: only the clean inside of the sheet (texcoords 0.04-0.545 x 0.04-0.615) is drawn, anchored corner to corner, so it fills the panel with no torn edge. Dark quest ink there (new `pInk*` colour keys); drop rows sit on dark name plates like the quest rewards;
  - lists stay on `UI-DialogBox-Background-Dark` with light text;
  - `/dm parchment l r t b` adjusts the parchment crop in game if a client's file differs (saved; `/dm parchment reset`);
  - without the stock art the page falls back to the dark slate (never a light parchment under light ink).
- **Scroll bars:** the stock `UI-ScrollBar-ScrollUp/DownButton` at their stock 16x16 size (was stretched to 20x20) with all four states: Up, Down while pressed, Disabled at the top / bottom, Highlight on hover; the thumb is the stock 18x24 `UI-ScrollBar-Knob`. Any missing file: the old art. Class themes unchanged.
- **Achievement toast:** showed only the icon. Its background panel is a child frame (one frame level up) and 0.5.1 put the title, name and points text on the toast itself, i.e. under that panel; with the stock opaque dialog background only the icon (a later child frame) showed. Icon and text now live on a content frame above the background, in every theme. **`/dm testtoast`** shows a sample (nothing is recorded).
- **Tests:** every stock surface fills its panel (Quests, Adventure Guide, Fishing, Achievements, Map, Dungeons); parchment only on the two detail panels and only from inside its torn edge; readable ink on each surface; stock scroll buttons 16x16 with highlight; class themes without stock art; `/dm parchment`; the toast's background, text and icon in all 10 themes.

## 0.5.1 (the WoW theme in the game's own art)
- **The default theme 'WoW' now looks like a stock WoW window** (quest log / character panel). It uses the client's own textures, referenced by path at runtime; no Blizzard file is copied or bundled:
  - frame: `DialogFrame\UI-DialogBox-Border` (edge file, cut like `Backdrop.lua`), title bar `DialogFrame\UI-DialogBox-Header`, portrait icon `QuestFrame\UI-QuestLog-BookIcon`;
  - panes: `Tooltips\UI-Tooltip-Border` edges over `DialogFrame\UI-DialogBox-Background-Dark`; window background `FrameGeneral\UI-Background-Rock`; quest detail on `QuestFrame\QuestBG` parchment, written in dark quest ink, with rewards on dark name plates like the stock quest log;
  - buttons `Buttons\UI-Panel-Button-Up/Down/Disabled`, search field `Common\Common-Input-Border`, section tabs `PaperDollInfoFrame\UI-Character-ActiveTab/InActiveTab`;
  - scroll bars `Buttons\UI-ScrollBar-ScrollUp/DownButton-Up` and `UI-ScrollBar-Knob`, check boxes `Buttons\UI-CheckBox-Up/Check`, +/- `Buttons\UI-PlusButton-Up/UI-MinusButton-Up`, selected row `QuestFrame\UI-QuestTitleHighlight` (a subtle gold tint);
  - the close button is the `UIPanelCloseButton` template.
  - Colours follow the stock fonts: GameFontNormal gold `#ffd100` headers, GameFontHighlight white body. Hover stays a subtle tint.
- **Feature-detected, per piece:** each texture is checked with `GetFileIDFromPath` (or a trial load) and each template with `C_XMLUtil.GetTemplateInfo` (or a protected `CreateFrame`). A missing piece falls back to Dark Matter's own 0.5.0 art, so nothing is ever blank.
- **`/dm artprobe`:** short `ok` / `MISSING` lines for every stock texture and template the WoW theme asks for, plus a summary; saved to `DarkMatterDB.artprobe`.
- The Map tab gets the stock framing in the WoW theme. The nine class themes are unchanged.
- **Roadmap shift:** pins 0.5.2, Starpen + share 0.5.3, Town Pins 0.5.4 (tool-strip tooltips updated).
- **Tests:** the contrast scan covers the WoW theme at light and dark estimates of the stock art and with all stock art missing; new checks for stock art drawn, the template close button, fallback, `/dm artprobe`, and the class themes staying unchanged.

## 0.5.0 (Map tab: the game's own map, world > continent > zone)
- **Map tab** (replaces the "Coming soon" stub):
  - the game's own map pictures (`C_Map.GetMapArtLayerTextures`, per mapID), read at runtime for every Kalimdor and Eastern Kingdoms zone;
  - continuous wheel zoom toward the cursor from the world to a zone, with crossfades between levels;
  - drag to pan; zones are stitched with their `GetMapRectOnMap` rects;
  - breadcrumb, zone search, Find me, player arrow;
  - explored overlays (fog of war), quest markers (`GetQuestsOnMap`) and zone level badges (public data, captioned);
  - zone and player coordinates at the bottom right;
  - a full-screen toggle (its own frame; Esc or the button returns).
- **Right tool strip:** Starpen (0.5.2), Drop a pin (0.5.1) and Town Pins (0.5.3) are present but disabled, with tooltips naming the version.
- **Taint-safe:** no hooks, no `WorldMapFrame`, works in combat.
- **Continent placement:** Forever's continent-on-world rect is unusable (EK x 0.37-1.16), so the land is sampled once with `GetMapInfoAtPosition`, fitted with one scale, and saved in `DarkMatterDB.map.place`.
- **`/dm mapprobe`:**
  - line 5 now shows each level's first and last tile file IDs, proving art is read per mapID (every Classic map shares the 1002x668, 4x3-tile layout, so the geometry looked identical in 0.4.7);
  - map size in yards was swapped (world X runs north-south) and is fixed;
  - new line 15 shows how the Map tab placed your continent.
- **Tests:** a C_Map fixture (world, two continents, seven zones, overlays, quests, player) covers:
  - art per mapID, placement, stitching, zoom-to-cursor, crossfades;
  - breadcrumb, right-click and double-click, drag across a border;
  - search, Find me, the tool strip;
  - badges, full screen and Esc, combat;
  - no WorldMapFrame access or hooks, instances, clients without world art, and clients with no art at all;
  - a 10-theme contrast scan of the live map (1120 label checks).

## 0.4.7 (read-only `/dm mapprobe`)
- `/dm mapprobe`: numbered "map N" lines checking the map APIs the Map tab needs. It is read-only and saved to `DarkMatterDB.mapprobe` (last result + 6 runs).

## 0.4.6 (fix: quest description and rewards on WoW Forever)
- **Bug (0.4.5, in game):** every quest showed "Not available from this client." for description and rewards.
  - Root cause: WoW Forever has no `SelectQuestLogEntry` / `GetQuestLogSelection`. The 0.4.5 reader gave up before calling any reader when `SelectQuestLogEntry` was missing, so even `GetQuestLogRewardXP(questID)` was never called.
- **Fix:** the readers always run, under the first selection method that makes `GetQuestLogQuestText` return text:
  1. `SelectQuestLogEntry(log index)`, restoring `GetQuestLogSelection`.
  2. `C_QuestLog.SetSelectedQuest(questID)`, restoring `C_QuestLog.GetSelectedQuest`.
  3. Direct calls with explicit questID / log-index arguments. This is used only when the client has no selection API at all; otherwise a selection-free read could show the player's selected quest instead.
  - The working method is remembered. Reward tooltips select the same way and pass the questID to `SetQuestLogItem`.
- **Quest data loading:** if there is still no text, Dark Matter asks the client to load the quest once (`C_QuestLog.RequestLoadQuestByID`) and reads it again on `QUEST_DATA_LOAD_RESULT`. Nothing is made up meanwhile.
- **Money:** without `GetCoinTextureString`, the gold/silver/copper string is built with the game's coin icons (`Interface\MoneyFrame\UI-GoldIcon` etc.).
- **Watch cap:**
  - The cap comes from `C_QuestLog.GetMaxNumQuestsCanWatch`, then `Constants.QuestWatchConsts.MAX_QUEST_WATCHES`, then `MAX_WATCHABLE_QUESTS`. Otherwise it is 25, labelled as assumed in the probe.
  - After ticking a box, Dark Matter checks that the game really added the watch. If it didn't, the box stays unticked and chat says so.
- **`/dm questprobe`** now also prints:
  - the selection methods,
  - the client's real quest-log reader functions (a C_QuestLog scan and a global scan),
  - the sample quest's index values (C_QuestLog.GetInfo list index vs GetLogIndexForQuestID vs GetQuestLogIndexByID, current selections, HaveQuestData),
  - one `try <method>` line per method showing whether `GetQuestLogQuestText` returned text,
  - the method the detail panel uses.
- **Detail debug:** when a clicked quest's panel comes back empty, one `detail debug` line per quest is printed to chat.
- **Tests:** the stub runs a WoW Forever mode (no SelectQuestLogEntry) covering text, XP, rewards, coins, selection restore, the tooltip, no-selection reads, the debug line, the load retry, the assumed cap and the probe lines.

## 0.4.5 (quest log: toolbar, search, WoW-style quest details, watch boxes)
- **Toolbar above the quest list, every theme:** All (expand/collapse every zone), a Track Quest box for the selected quest, and a search box at the far right. The old head row above the left nav is gone.
- **Search:** a stock EditBox (no hooks, no UIDropDownMenu). It filters live and ignores case and punctuation. Every word must match the quest's title, zone, objectives summary, objective lines, description or reward item names. Zones expand while searching and headers show matches/total. A "x" button or Esc clears it; with nothing left, "No matching quests" shows.
- **Quest details like the game's quest log:** title, level, zone, quest id and status, then Quest Objectives (summary plus each objective with progress), Description and Rewards. Rewards cover "You will be able to choose one of these rewards", "You will receive / also receive", money with gold, silver and copper coin icons, spells, titles, honor, reputation, experience and required money. Item buttons show the icon, stack count and quality-coloured name, and hovering one shows the real GameTooltip (SetQuestLogItem, then SetHyperlink / SetItemByID). Anything the client does not return reads "Not available from this client."; nothing is made up. The panel scrolls.
- **Watch boxes:** each quest row (not zone headers) has a stock CheckButton tied to the game's quest watch list, both ways. A box only shows when the client has a watch API. At the watch cap the box stays unticked and the game's own "too many" message shows. A change made in combat is queued until combat ends.
- **`/dm questprobe`:** lists which quest-log, reward, tooltip and watch APIs this client has, reads the selected quest, and reports watch count, cap and the tracker refresh used. Results are saved to `DarkMatterDB.questprobe`.
- **Contrast:** the toolbar, search, detail text and watch boxes are part of the contrast test (all 10 themes, 4.5:1, or 3:1 for large text).
- **Tests:** stub checks for search, detail sections, rewards, tooltips, selection restore, watch sync (both directions), the cap message, the combat queue and the probe.

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
