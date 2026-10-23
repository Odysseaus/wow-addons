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


# 0.5.2b.6: the capital cities (drawn by their own picture only when they are the focus; their land is drawn by the
# zone around them). Every other map the game names is a zone with a mask, sampled or not (Redridge Mountains,
# Moonglade and the like are small but are zones: their masks are made from their neighbours' samples).
CITIES = {1453, 1454, 1455, 1456, 1457, 1458}
NAMES = {1433: "Redridge Mountains", 1450: "Moonglade"}
CONT_ART = (1002, 668)  # continent pictures are 1002 x 668 art px: the aspect of a rectangle in map fractions


class Grid:
    """One sampled zone: its rectangle r = (x1, x2, y1, y2) on the continent and the zone id at each cell centre."""

    def __init__(self, zid, rec):
        self.id = int(zid)
        self.name = str(rec["name"])
        self.w, self.h = int(rec["w"]), int(rec["h"])
        self.r = tuple(float(rec["r"][i + 1]) for i in range(4))
        legend = [int(rec["legend"][i + 1]) for i in range(len(rec["legend"]))]
        self.rows = [decode(rec["rows"][y + 1], legend) for y in range(self.h)]
        self.cell = (self.r[1] - self.r[0]) / self.w

    def contains(self, x, y):
        r = self.r
        return r[0] <= x < r[1] and r[2] <= y < r[3]

    def at(self, x, y):
        r = self.r
        i = min(self.w - 1, max(0, int((x - r[0]) / (r[1] - r[0]) * self.w)))
        j = min(self.h - 1, max(0, int((y - r[2]) / (r[3] - r[2]) * self.h)))
        return self.rows[j][i]

    def centre(self, i, j):
        r = self.r
        return r[0] + (i + 0.5) / self.w * (r[1] - r[0]), r[2] + (j + 0.5) / self.h * (r[3] - r[2])


class Continent:
    def __init__(self, cid, rec):
        self.id = int(cid)
        self.name = str(rec["name"])
        self.grids = sorted((Grid(z, rec["zones"][z]) for z in rec["zones"]), key=lambda g: g.cell)
        self.sampled = {g.id for g in self.grids}
        # every id the game named, with the bounding box of its cells (continent fractions) and a centroid
        box, acc = {}, {}
        for g in self.grids:
            hw, hh = (g.r[1] - g.r[0]) / g.w / 2, (g.r[3] - g.r[2]) / g.h / 2
            for j, row in enumerate(g.rows):
                for i, v in enumerate(row):
                    if v is None:
                        continue
                    x, y = g.centre(i, j)
                    b = box.get(v)
                    box[v] = (min(b[0], x - hw), max(b[1], x + hw), min(b[2], y - hh), max(b[3], y + hh)) if b else (x - hw, x + hw, y - hh, y + hh)
                    s = acc.setdefault(v, [0.0, 0.0, 0])
                    s[0] += x
                    s[1] += y
                    s[2] += 1
        self.box = box
        self.centroid = {v: (s[0] / s[2], s[1] / s[2]) for v, s in acc.items()}
        self.extra = sorted(v for v in box if v not in self.sampled and v not in CITIES)
        # a city's land belongs to the sampled zone that borders it most (the land next to the city's cells)
        votes = {}
        for g in self.grids:
            for j, row in enumerate(g.rows):
                for i, v in enumerate(row):
                    if v not in CITIES:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ni, nj = i + dx, j + dy
                        if 0 <= ni < g.w and 0 <= nj < g.h:
                            u = g.rows[nj][ni]
                            if u in self.sampled:
                                d = votes.setdefault(v, {})
                                d[u] = d.get(u, 0) + 1
        self.host = {c: (max(d.items(), key=lambda t: t[1])[0] if d else None) for c, d in votes.items()}

    def at(self, x, y):
        """the zone id at continent point x, y from the finest sampled grid holding it; False = no grid holds it"""
        for g in self.grids:
            if g.contains(x, y):
                return g.at(x, y)
        return False

    def owner_of(self, v):
        """which mask draws land of id v: the zone itself, or a city's host zone"""
        if v in CITIES:
            return self.host.get(v)
        return v


def shape(labels, zid, cont, w, h):
    """the soft mask (rows of 0..1) of zone zid over a w x h label grid (ids, None = sea / no zone, False = unknown)"""
    from collections import deque
    own = [[1.0 if (v is not None and v is not False and cont.owner_of(v) == zid) else 0.0 for v in row] for row in labels]
    land = [[v is not None and v is not False for v in row] for row in labels]
    # sea: to the nearest land (multi-source BFS over the grid)
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
    # grow one cell, blur once (3x3 box): its own land stays at 1, the edge fades over the next cell or two
    g = [[max(m[yy][xx] for yy in range(max(0, y - 1), min(h, y + 2)) for xx in range(max(0, x - 1), min(w, x + 2))) for x in range(w)] for y in range(h)]
    for _ in range(1):
        g = [[sum(g[yy][xx] for yy in range(max(0, y - 1), min(h, y + 2)) for xx in range(max(0, x - 1), min(w, x + 2)))
              / ((min(h, y + 2) - max(0, y - 1)) * (min(w, x + 2) - max(0, x - 1))) for x in range(w)] for y in range(h)]
    # the outermost half cell of the rectangle fades out (the picture ends there)
    for y in range(h):
        for x in range(w):
            e = min(x + 0.5, w - x - 0.5, y + 0.5, h - y - 0.5) / 0.5
            g[y][x] *= max(0.0, min(1.0, e))
    return g


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


def sample(mask, x, y):
    """a mask's alpha at continent point x, y (bilinear; 0 outside its rectangle)"""
    r, g, w, h = mask["rect"], mask["g"], mask["w"], mask["h"]
    if not (r[0] <= x <= r[1] and r[2] <= y <= r[3]):
        return 0.0
    fx = (x - r[0]) / (r[1] - r[0]) * w - 0.5
    fy = (y - r[2]) / (r[3] - r[2]) * h - 0.5
    x0, y0 = max(0, min(w - 1, int(math.floor(fx)))), max(0, min(h - 1, int(math.floor(fy))))
    x1, y1 = min(w - 1, x0 + 1), min(h - 1, y0 + 1)
    tx, ty = max(0.0, min(1.0, fx - x0)), max(0.0, min(1.0, fy - y0))
    a = g[y0][x0] * (1 - tx) + g[y0][x1] * tx
    b = g[y1][x0] * (1 - tx) + g[y1][x1] * tx
    return a * (1 - ty) + b * ty


def continent_masks(cont):
    """{ zid: { name, rect, g, w, h, extra } } for every zone of the continent (sampled and extra)"""
    out = {}
    for gr in cont.grids:
        out[gr.id] = {"name": gr.name, "rect": gr.r, "g": shape(gr.rows, gr.id, cont, gr.w, gr.h), "w": gr.w, "h": gr.h, "extra": False}
    for zid in cont.extra:
        b = cont.box[zid]
        mx, my = (b[1] - b[0]) * 0.06, (b[3] - b[2]) * 0.06
        rect = (b[0] - mx, b[1] + mx, b[2] - my, b[3] + my)
        w = 160
        h = max(16, min(256, int(round(w * (rect[3] - rect[2]) * CONT_ART[1] / ((rect[1] - rect[0]) * CONT_ART[0])))))
        labels = []
        for j in range(h):
            y = rect[2] + (j + 0.5) / h * (rect[3] - rect[2])
            labels.append([cont.at(rect[0] + (i + 0.5) / w * (rect[1] - rect[0]), y) for i in range(w)])
        out[zid] = {"name": NAMES.get(zid, f"zone {zid}"), "rect": rect, "g": shape(labels, zid, cont, w, h), "w": w, "h": h, "extra": True}
    return out


def check(cont, ms):
    """the offline sweep: every sampled land point of the continent against the masks that would be drawn there.
    base-land: land the zone masks together cover less than 90% (the continent picture shows through); wrong-art: land whose own zone's
    mask is under 50% while another zone's is over 50% (the neighbour's picture shows); overlap: land two zone masks
    both cover at 90% or more (both pictures fully drawn, the top one wins: the grown border cell)."""
    seen = set()
    n = base = wrong = overlap = 0
    worst = {}
    for gr in cont.grids:
        for j, row in enumerate(gr.rows):
            for i, v in enumerate(row):
                if v is None or v is False:
                    continue
                x, y = gr.centre(i, j)
                key = (round(x, 4), round(y, 4))
                if key in seen:
                    continue
                seen.add(key)
                n += 1
                mine = cont.owner_of(v)
                a = {z: sample(m, x, y) for z, m in ms.items()}
                strong = [z for z, s in a.items() if s >= 0.9]
                left = 1.0
                for s in a.values():
                    left *= 1.0 - s
                if left > 0.1:
                    base += 1
                    worst[mine] = worst.get(mine, 0) + 1
                if len(strong) >= 2:
                    overlap += 1
                if a.get(mine, 0) < 0.5 and any(s > 0.5 for z, s in a.items() if z != mine):
                    wrong += 1
    return {"points": n, "base": base, "wrong": wrong, "overlap": overlap, "worst": sorted(worst.items(), key=lambda t: -t[1])[:5]}


def masks(sv, addon, size=256):
    shapes = load_shapes(sv)
    addon = Path(addon)
    outdir = addon / "Media" / "masks"
    outdir.mkdir(parents=True, exist_ok=True)
    made = []
    report = []
    for cid in shapes["conts"]:
        cont = Continent(cid, shapes["conts"][cid])
        ms = continent_masks(cont)
        for zid, m in ms.items():
            write_tga(outdir / f"z{zid}.tga", size, size, resample(m["g"], m["w"], m["h"], size))
            made.append((cont.id, zid, m))
        c = check(cont, ms)
        cities = sorted(v for v in cont.box if v in CITIES)
        report.append(f"{cont.name} ({cont.id}): {len(ms)} masks ({len(cont.grids)} sampled + {len(cont.extra)} from neighbours: "
                      f"{', '.join(ms[z]['name'] for z in cont.extra) or 'none'}); cities on their zone: "
                      f"{', '.join(f'{c_}->{cont.host.get(c_)}' for c_ in cities) or 'none'}")
        report.append(f"  sweep over {c['points']} land points: base-land {c['base']} ({100.0 * c['base'] / max(1, c['points']):.2f}%), "
                      f"wrong-art {c['wrong']} ({100.0 * c['wrong'] / max(1, c['points']):.2f}%), overlap {c['overlap']} "
                      f"({100.0 * c['overlap'] / max(1, c['points']):.2f}%); base-land most in {c['worst']}")
    made.sort(key=lambda t: (t[0], t[1]))
    lines = [
        "-- Data_ZoneMasks.lua: GENERATED by tools/maskgen/maskgen.py from DarkMatterDB.mapshapes (/dm mapshapes).",
        "-- Which zone shape masks ship: NS.ZoneMasks[mapID] = { file = ..., rect = ... }. Do not edit by hand.",
        "-- rect (continent map fractions x1, x2, y1, y2) only on a mask made from its neighbours' samples: the mask covers",
        "-- that rectangle, not the zone's own (the map anchors it there).",
        "local _, NS = ...",
        "NS.ZoneMasks = {",
    ]
    for cid, zid, m in made:
        rect = ""
        if m["extra"]:
            rect = ", rect = {{ {:.5f}, {:.5f}, {:.5f}, {:.5f} }}".format(*m["rect"])
        lines.append(f'  [{zid}] = {{ file = "Interface\\\\AddOns\\\\DarkMatter\\\\Media\\\\masks\\\\z{zid}", cont = {cid}{rect} }}, -- {m["name"]}')
    lines.append("}")
    (addon / "Data_ZoneMasks.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(made)} masks ({size}x{size}) -> {outdir}")
    for line in report:
        print(line)


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
