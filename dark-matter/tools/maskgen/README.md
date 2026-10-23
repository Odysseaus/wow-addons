# maskgen (box-side, never shipped, never run on the Mac)

Turns `/dm mapshapes` data into Dark Matter's zone shape masks, and reviews every zone border.

1. In game: `/dm mapshapes` (out of combat), wait for `mapshapes done`, then `/reload`.
2. Copy `WTF/Account/<account>/SavedVariables/DarkMatter.lua` to the box. Only read it, never edit it.
3. `python maskgen.py masks DarkMatter.lua ../../DarkMatter --size 256 [--review DIR]` writes `DarkMatter/Media/masks/z<mapID>.tga` (soft pass), `z<mapID>c.tga` (core pass), `DarkMatter/Data_ZoneMasks.lua` and `DarkMatter/Data_ZoneSeams.lua`. With `--review DIR` it also writes the border review. It needs `lupa` and `numpy`.
4. `python maskgen.py testmask ../../DarkMatter/Media/masks` writes the `/dm masktest` star again.

The masks are made only from the game's area answers (which zone owns each point). No game or OpenMap art goes into them.

## What `masks` does (v2, 0.5.2b.8: two passes)
All widths are in continent px (cpx, 1/1002 of the continent picture's width), except the torn-rim cut, which is in zone art px.
- **Ownership.** Each zone's samples are blurred into a smooth ownership field (gaussian, sigma 1.6 cpx) and sharpened (cube) against its neighbours. Where two pictures overlap, the one further from its own torn rim and box edge wins (rim distance: 22 art px cut plus a 2.5 cpx ramp). So the picture that paints that land most cleanly is the one shown.
- **Core pass** (`z<id>c.tga`, drawn one frame level up): the zone's share of the land where it wins. The cores of neighbours add up to about one, so they do not depend on draw order.
- **Soft pass** (`z<id>.tga`, underneath): a wider halo of the zone's own land (sigma 2 cpx) with a 10 art px rim cut. It fills any gap the cores leave at a seam, so no continent picture shows through there.
- **Coast.** Both passes are multiplied by one blurred outline of the whole continent, so coasts fade softly into the continent picture. The game's area answers count near-shore sea as zone land in square blocks, so the coast follows those blocks (rounded), not the drawn shoreline.
- **No capitals.** There is one mask pair per zone and none for the six capitals (they are drawn as a city over their host zone).
- **Zones with no samples.** A zone with no samples of its own (Redridge, Moonglade, 2652: too small for the 0.5.2b.5 `/dm mapshapes`) is cut from the continent samples around it. It gets a `rect` with a 12.5 cpx margin: the mask covers that rectangle of the zone picture. After a new `/dm mapshapes` that samples them, maskgen gives them full masks with no change to the code.
- **Offline sweep.** It prints a sweep per continent:
  - `base-land`: land points no mask covers.
  - `wrong-art`: a point covered only by another zone's mask.
  - `overlap`: points under two masks at full strength.
- **Painted names.** The zone-name words painted into the game's zone art may be cut. The map shows the name under the cursor as its own text.

## Border review (`--review DIR`)
- `borders.txt` / `borders.csv`: every border between two zones, worst first. It is computed on a 0.5 cpx raster in a band of 2 cpx on either side of the border.
- `contact.png`: the 36 worst borders, 44 cpx around each.
  - Each tile is coloured by the zone whose picture wins.
  - Navy is open sea.
  - Red is land showing only the continent picture.
  - Yellow stripes mark a winning picture inside its torn rim.
- `overview-<cont>.png`: the whole continent in the same colours.
- `Data_ZoneSeams.lua` (shipped) lists the worst borders. `/dm seamsweep` uses it to screenshot them in game.

Metrics:
- `leak`: the continent picture shows more than 10%.
- `rimseam`: both pictures are in their torn rim.
- `torn`: the winning picture is in its rim.
- `third`: a third zone's picture wins.
- `score` = 100 x (2 leak + 1.5 rimseam + torn + 2 third), with +5 when a zone made from its neighbours' samples is involved.
