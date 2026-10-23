# maskgen (box-side, never shipped, never run on the Mac)

Turns `/dm mapshapes` data into Dark Matter's zone shape masks.

1. In game: `/dm mapshapes` (out of combat), wait for `mapshapes done`, then `/reload`.
2. Copy `WTF/Account/<account>/SavedVariables/DarkMatter.lua` to the box. Only read it, never edit it.
3. `python maskgen.py masks DarkMatter.lua ../../DarkMatter --size 256` writes `DarkMatter/Media/masks/z<mapID>.tga` and `DarkMatter/Data_ZoneMasks.lua`. It needs `lupa`; the stubtest venv has it.
4. `python maskgen.py testmask ../../DarkMatter/Media/masks` writes the `/dm masktest` star again.

The masks are made only from the game's area answers (which zone owns each point). No game or OpenMap art goes into them.

What `masks` does:
- One mask per zone, none for the six capitals (they are drawn as a city over their host zone).
- A zone with no samples of its own (Redridge, Moonglade, 2652: too small for the 0.5.2b.5 `/dm mapshapes`) is cut from the continent samples around it and gets a `rect`: the mask covers that rectangle of the zone picture.
- It prints an offline sweep per continent: `base-land` (land points no mask covers), `wrong-art` (a point covered only by another zone's mask) and `overlap` (points under two masks at full strength).
