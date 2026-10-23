#!/usr/bin/env python3
"""Dark Matter zone shape masks (box-side tool; never shipped in the addon, never run on the Mac).

  maskgen.py testmask OUT_DIR
      writes OUT_DIR/dm-masktest.tga: the soft five-point star used by /dm masktest (0.5.2b.5)

  maskgen.py masks SAVEDVARIABLES_FILE ADDON_DIR [--size 256]
      reads DarkMatterDB.mapshapes (from /dm mapshapes) and writes ADDON_DIR/Media/masks/z<mapID>.tga plus
      ADDON_DIR/Data_ZoneMasks.lua (the manifest the map reads). The SavedVariables file is only read.

Masks are uncompressed 32-bit TGA (type 2, bottom-left origin, like the addon's other Media files), white with the
shape in alpha (and in the colour channels), power-of-two square, stretched over the zone's picture by the game.
Per zone: its own land (and the cities inside it) is 1; sea / no-zone points go to the zone whose land is nearest
inside this zone's rectangle; then grown by one grid cell (neighbours overlap a little: no gap) and blurred (a soft
edge), and faded out over the outer two cells of the rectangle.
"""
import math
import struct
import sys
from pathlib import Path

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"


def write_tga(path, w, h, alpha_rows):
    """alpha_rows[y][x] in 0..1, y = 0 at the TOP; written bottom-left origin."""
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    out = bytearray(hdr)
    for y in range(h - 1, -1, -1):
        row = alpha_rows[y]
        for x in range(w):
            a = max(0, min(255, int(round(row[x] * 255))))
            out += bytes((a, a, a, a))  # B G R A
    Path(path).write_bytes(bytes(out))


def star(w=128, h=128, points=5, soft=0.06):
    rows = []
    for y in range(h):
        r = []
        for x in range(w):
            u, v = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
            d = math.hypot(u, v)
            ang = math.atan2(v, u) + math.pi / 2
            k = (math.cos(points * ang) + 1) / 2  # 1 at the tips
            edge = 0.42 + 0.48 * k ** 1.5
            r.append(max(0.0, min(1.0, (edge - d) / soft + 0.5)))
        rows.append(r)
    return rows


def decode(text, legend):
    row = []
    i = 0
    while i < len(text):
        ch = text[i]
        i += 1
        j = i
        while j < len(text) and text[j].isdigit():
            j += 1
        n = int(text[i:j]) if j > i else 1
        i = j
        k = ALPHABET.find(ch)
        row.extend([legend[k] if 0 <= k < len(legend) else None] * n)
    return row


def load_shapes(sv_path):
    import lupa  # the stubtest venv has it
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(Path(sv_path).read_text(encoding="utf-8", errors="replace"))
    db = lua.globals().DarkMatterDB
    shapes = db and db["mapshapes"]
    if shapes is None:
        raise SystemExit("no DarkMatterDB.mapshapes in " + str(sv_path) + " (run /dm mapshapes, then /reload)")
    return shapes


def zone_mask(rec, zid, sampled_ids):
    w, h = int(rec["w"]), int(rec["h"])
    legend = [int(rec["legend"][i + 1]) for i in range(len(rec["legend"]))]
    grid = [decode(rec["rows"][y + 1], legend) for y in range(h)]
    # own land: this zone, or a city (not one of the sampled zones) inside its rectangle
    own = [[1.0 if (v == zid or (v is not None and v not in sampled_ids)) else 0.0 for v in row] for row in grid]
    land = [[v is not None for v in row] for row in grid]
    # sea: to the nearest land (multi-source BFS over the grid)
    from collections import deque
    owner = [[None] * w for _ in range(h)]
    q = deque()
    for y in range(h):
        for x in range(w):
            if land[y][x]:
                owner[y][x] = own[y][x]
                q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and owner[ny][nx] is None:
                owner[ny][nx] = owner[y][x]
                q.append((nx, ny))
    m = [[(owner[y][x] or 0.0) for x in range(w)] for y in range(h)]
    # grow one cell, blur (3x3 box twice)
    g = [[max(m[yy][xx] for yy in range(max(0, y - 1), min(h, y + 2)) for xx in range(max(0, x - 1), min(w, x + 2))) for x in range(w)] for y in range(h)]
    for _ in range(2):
        g = [[sum(g[yy][xx] for yy in range(max(0, y - 1), min(h, y + 2)) for xx in range(max(0, x - 1), min(w, x + 2)))
              / ((min(h, y + 2) - max(0, y - 1)) * (min(w, x + 2) - max(0, x - 1))) for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            e = min(x + 0.5, w - x - 0.5, y + 0.5, h - y - 0.5) / 2.0
            g[y][x] *= max(0.0, min(1.0, e))
    return g, w, h


def resample(g, w, h, size):
    out = []
    for y in range(size):
        fy = (y + 0.5) / size * h - 0.5
        y0 = max(0, min(h - 1, int(math.floor(fy))))
        y1, ty = min(h - 1, y0 + 1), max(0.0, min(1.0, fy - y0))
        r = []
        for x in range(size):
            fx = (x + 0.5) / size * w - 0.5
            x0 = max(0, min(w - 1, int(math.floor(fx))))
            x1, tx = min(w - 1, x0 + 1), max(0.0, min(1.0, fx - x0))
            a = g[y0][x0] * (1 - tx) + g[y0][x1] * tx
            b = g[y1][x0] * (1 - tx) + g[y1][x1] * tx
            r.append(a * (1 - ty) + b * ty)
        out.append(r)
    return out


def masks(sv, addon, size=256):
    shapes = load_shapes(sv)
    addon = Path(addon)
    outdir = addon / "Media" / "masks"
    outdir.mkdir(parents=True, exist_ok=True)
    made = []
    conts = shapes["conts"]
    for cont in conts:
        zones = conts[cont]["zones"]
        sampled = {int(z) for z in zones}
        for zid in zones:
            rec = zones[zid]
            g, w, h = zone_mask(rec, int(zid), sampled)
            write_tga(outdir / f"z{int(zid)}.tga", size, size, resample(g, w, h, size))
            made.append((int(zid), str(rec["name"])))
    made.sort()
    lines = [
        "-- Data_ZoneMasks.lua: GENERATED by tools/maskgen/maskgen.py from DarkMatterDB.mapshapes (/dm mapshapes).",
        "-- Which zone shape masks ship: NS.ZoneMasks[mapID] = { file = ... }. Do not edit by hand.",
        "local _, NS = ...",
        "NS.ZoneMasks = {",
    ]
    for zid, name in made:
        lines.append(f'  [{zid}] = {{ file = "Interface\\\\AddOns\\\\DarkMatter\\\\Media\\\\masks\\\\z{zid}" }}, -- {name}')
    lines.append("}")
    (addon / "Data_ZoneMasks.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(made)} masks ({size}x{size}) -> {outdir}")


def main(argv):
    if len(argv) >= 3 and argv[1] == "testmask":
        out = Path(argv[2])
        out.mkdir(parents=True, exist_ok=True)
        write_tga(out / "dm-masktest.tga", 128, 128, star())
        print("wrote", out / "dm-masktest.tga")
    elif len(argv) >= 4 and argv[1] == "masks":
        size = int(argv[argv.index("--size") + 1]) if "--size" in argv else 256
        if size & (size - 1):
            raise SystemExit("--size must be a power of two")
        masks(argv[2], argv[3], size)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
