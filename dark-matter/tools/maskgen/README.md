# maskgen (box-side, never shipped, never run on the Mac)

Turns `/dm mapshapes` data into Dark Matter's zone shape masks.

1. In game: `/dm mapshapes` (out of combat), wait for `mapshapes done`, then `/reload`.
2. Copy `WTF/Account/<account>/SavedVariables/DarkMatter.lua` to the box. Only read it, never edit it.
3. `python maskgen.py masks DarkMatter.lua ../../DarkMatter --size 256` writes `DarkMatter/Media/masks/z<mapID>.tga` and `DarkMatter/Data_ZoneMasks.lua`. It needs `lupa`; the stubtest venv has it.
4. `python maskgen.py testmask ../../DarkMatter/Media/masks` writes the `/dm masktest` star again.

The masks are made only from the game's area answers (which zone owns each point). No game or OpenMap art goes into them.
