#!/usr/bin/env python3
"""Dark Matter zone shape masks (box-side tool; never shipped in the addon, never run on the Mac).

  maskgen.py testmask OUT_DIR
      writes OUT_DIR/dm-masktest.tga: the soft five-point star used by /dm masktest (0.5.2b.5)

  maskgen.py masks SAVEDVARIABLES_FILE ADDON_DIR [--size 256]
      reads DarkMatterDB.mapshapes (from /dm mapshapes) and writes ADDON_DIR/Media/masks/z<mapID>.tga plus
      ADDON_DIR/Data_ZoneMasks.lua (the manifest the map reads). The SavedVariables file is only read.

Masks are uncompressed 32-bit TGA (type 2, bottom-left origin, like the addon's other Media files), white with the
shape in alpha (and in the colour channels), power-of-two square, stretched over the zone's picture by the game.
Smooth masks (0.5.2b.7): per continent, every zone picture gets a work raster (WORK px plus a pad). The coarse area
samples are looked up per raster point (finest grid first), the zone's own land is blurred wide (SIGMA) and
thresholded with a smoothstep, so block corners come out round with an anti-aliased edge of a few px. Each mask is
inset from its picture's torn parchment rim and box edge (RIM, in art px); land the neighbour pictures leave undrawn
there is drawn by this picture instead (a-over-b exact, feathered, so neighbours overlap a little and there is no
gap), a second pass closes the seams where two pictures meet edge to edge (RIM2). Last, all pictures' coverage is
blurred wide (OUTLINE_SIGMA) and faded in, so the zones end in one soft rounded outline over the continent picture
where they border sea or the outside. The result is averaged 2x2 down to --size.
"""
import math
import struct
import sys
from pathlib import Path

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"


def write_tga(path, w, h, alpha_rows):
    """alpha_rows[y][x] in 0..1 (lists or a numpy array), y = 0 at the TOP; written bottom-left origin."""
    try:
        import numpy as np
        a = np.clip(np.rint(np.asarray(alpha_rows, dtype=float)[::-1] * 255), 0, 255).astype(np.uint8)
        px = np.repeat(a[:, :, None], 4, axis=2)
        hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
        Path(path).write_bytes(hdr + px.tobytes())
        return
    except ImportError:
        pass
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


# 0.5.2b.7: smooth masks. All lengths are in the zone picture's art px (a zone picture is 1002 x 668 art px).
ART = (1002, 668)
WORK = 512        # work raster per picture (x and y), averaged 2x2 down to the written size
PAD = 72          # work texels of context around the picture (the blur and the fill see past its edge)
SIGMA = 14.0      # the blur that rounds the game's stair-step area borders
LO, HI = 0.12, 0.36  # blurred ownership -> mask: 0 below LO, full above HI (full on the border itself: neighbours overlap)
FILL = (6.0, 34.0)   # points of no zone (outside the continent's zones): owned by the nearest zone, fading out over FILL
RIM = (22.0, 48.0)   # the picture's own torn parchment rim: nothing within RIM[0] of its edge, full past RIM[1]
RIM2 = (10.0, 26.0)  # a seam no picture covers past RIM: the nearest picture may draw it this close to its edge
RIM_EXTRA = (0.0, 10.0)  # a mask made from neighbours (its rect is not the picture): fade only at the rect


def smoothstep(a, b, x):
    import numpy as np
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def owner_arrays(cont):
    """per sampled grid (finest first): its rect and a numpy array of owners (city -> host zone, no zone -> -1)"""
    import numpy as np
    out = []
    for g in cont.grids:
        a = np.full((g.h, g.w), -1, dtype=np.int64)
        for j, row in enumerate(g.rows):
            for i, v in enumerate(row):
                if v is not None and v is not False:
                    o = cont.owner_of(v)
                    a[j, i] = o if o is not None else -1
        out.append((g.r, a))
    return out


def labels_at(arrays, X, Y):
    """owner zone at continent points X, Y from the finest grid holding each (-1 none, -2 no grid holds it)"""
    import numpy as np
    lab = np.full(X.shape, -2, dtype=np.int64)
    todo = np.ones(X.shape, dtype=bool)
    for r, a in arrays:
        h, w = a.shape
        inside = todo & (X >= r[0]) & (X < r[1]) & (Y >= r[2]) & (Y < r[3])
        if not inside.any():
            continue
        i = np.clip(((X[inside] - r[0]) / (r[1] - r[0]) * w).astype(np.int64), 0, w - 1)
        j = np.clip(((Y[inside] - r[2]) / (r[3] - r[2]) * h).astype(np.int64), 0, h - 1)
        lab[inside] = a[j, i]
        todo &= ~inside
    return lab


class Raster:
    """one zone's work raster: WORK x WORK texels over its rect (plus PAD around), art px per texel px, py"""

    def __init__(self, zid, name, rect, extra, arrays):
        import numpy as np
        from scipy import ndimage
        self.id, self.name, self.rect, self.extra = zid, name, rect, extra
        self.px, self.py = ART[0] / WORK, ART[1] / WORK
        n = WORK + 2 * PAD
        k = (np.arange(n) - PAD + 0.5) / WORK
        self.X = rect[0] + k[None, :] * (rect[1] - rect[0]) + 0 * k[:, None]
        self.Y = rect[2] + k[:, None] * (rect[3] - rect[2]) + 0 * k[None, :]
        lab = labels_at(arrays, self.X, self.Y)
        empty = lab < 0
        if empty.all():
            near, dist = lab, np.full(lab.shape, 1e9)
        else:
            dist, idx = ndimage.distance_transform_edt(empty, sampling=(self.py, self.px), return_indices=True)
            near = lab[idx[0], idx[1]]
        self.lab, self.near = lab, near
        self.wEmpty = 1.0 - smoothstep(FILL[0], FILL[1], dist)  # 1 on zone land (dist 0)
        self.sig = (SIGMA / self.py, SIGMA / self.px)
        self.m = self.field(lambda v: v == zid)
        # the picture's rim
        xa = (k * ART[0])[None, :] + 0 * k[:, None]
        ya = (k * ART[1])[:, None] + 0 * k[None, :]
        dx = np.minimum(xa, ART[0] - xa)
        dy = np.minimum(ya, ART[1] - ya)
        r0, r1 = RIM_EXTRA if extra else RIM
        self.rim = smoothstep(r0, r1, dx) * smoothstep(r0, r1, dy)
        q0, q1 = RIM_EXTRA if extra else RIM2
        self.rim2 = smoothstep(q0, q1, dx) * smoothstep(q0, q1, dy)
        self.a = self.m * self.rim  # what this picture really draws (before it picks up its neighbours' rims)

    def field(self, pick):
        """the smooth mask of the land whose owner passes pick (no-zone points count by their nearest owner, fading)"""
        from scipy import ndimage
        lab, near = self.lab, self.near
        ind = (pick(near) & True) * self.wEmpty
        f = ndimage.gaussian_filter(ind.astype(float), self.sig, mode="nearest")
        return smoothstep(LO, HI, f)

    def sample(self, field, X, Y):
        """this raster's field at continent points X, Y (bilinear; 0 outside the raster)"""
        import numpy as np
        from scipy import ndimage
        r = self.rect
        u = (X - r[0]) / (r[1] - r[0]) * WORK + PAD - 0.5
        v = (Y - r[2]) / (r[3] - r[2]) * WORK + PAD - 0.5
        return ndimage.map_coordinates(field, [v.ravel(), u.ravel()], order=1, mode="constant", cval=0.0).reshape(X.shape)

    def overlaps(self, o):
        a, b = self.rect, o.rect
        return a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3]


def continent_masks(cont, size):
    """{ zid: { name, rect, g (size x size rows, top first), w, h, extra } } for every zone of the continent"""
    import numpy as np
    arrays = owner_arrays(cont)
    rs = []
    for gr in cont.grids:
        rs.append(Raster(gr.id, gr.name, gr.r, False, arrays))
    for zid in cont.extra:
        b = cont.box[zid]
        mx, my = (b[1] - b[0]) * 0.06, (b[3] - b[2]) * 0.06
        rs.append(Raster(zid, NAMES.get(zid, f"zone {zid}"), (b[0] - mx, b[1] + mx, b[2] - my, b[3] + my), True, arrays))
    fulls = {}
    for R in rs:
        # land of the other zones here that their own pictures leave undrawn (their rim, or beyond their picture):
        # this picture draws it (neighbours overlap a little, feathered: no gap)
        other = R.field(lambda v: (v != R.id) & (v >= 0))
        left = np.ones(R.X.shape)
        for O in rs:
            if O is not R and R.overlaps(O):
                left *= 1.0 - O.sample(O.a, R.X, R.Y)
        # what this picture must add for the others to reach full strength over (1 - their cover): a over b composites
        lost = np.clip((other - (1.0 - left)) / np.maximum(left, 1e-3), 0.0, 1.0)
        fulls[R.id] = R.rim * np.maximum(R.m, lost)
    # a seam where two pictures meet edge to edge (both in their rim): the pictures there draw it from RIM2 on
    fulls2 = {}
    for R in rs:
        land = R.field(lambda v: v >= 0)
        left = np.ones(R.X.shape)
        near = np.zeros(R.X.shape)
        for O in rs:
            if O is not R and R.overlaps(O):
                left = left * (1.0 - O.sample(fulls[O.id], R.X, R.Y))
                near = np.maximum(near, O.sample(O.rim2, R.X, R.Y))
        gap = np.clip((land - (1.0 - left)) / np.maximum(left, 1e-3), 0.0, 1.0) * (near > 0.0)
        fulls2[R.id] = np.maximum(fulls[R.id], R.rim2 * gap)
    fulls = fulls2
    # the continent's outline: what all the zone pictures together draw, blurred wide and faded inward, so the zones
    # end in one soft rounded edge over the continent picture (the game's areas are square blocks out at sea)
    S = outline(rs, fulls)
    out = {}
    for R in rs:
        full = fulls[R.id] * S(R.X, R.Y)
        core = full[PAD:PAD + WORK, PAD:PAD + WORK]
        f = WORK // size
        g = core.reshape(size, f, size, f).mean(axis=(1, 3))
        out[R.id] = {"name": R.name, "rect": R.rect, "g": g, "w": size, "h": size, "extra": R.extra}
    return out


OUTLINE_CELL = 0.0004   # continent raster for the outline (map fractions)
OUTLINE_SIGMA = 0.0028  # its blur (map fractions: about 28 art px of an Elwynn-sized zone picture)


def outline(rs, fulls):
    """S(X, Y): 1 inside the zones' union, fading to 0 at its blurred, rounded outer edge"""
    import numpy as np
    from scipy import ndimage
    x0 = min(R.rect[0] for R in rs) - 0.01
    x1 = max(R.rect[1] for R in rs) + 0.01
    y0 = min(R.rect[2] for R in rs) - 0.01
    y1 = max(R.rect[3] for R in rs) + 0.01
    w, h = int((x1 - x0) / OUTLINE_CELL) + 1, int((y1 - y0) / OUTLINE_CELL) + 1
    X, Y = np.meshgrid(x0 + (np.arange(w) + 0.5) * OUTLINE_CELL, y0 + (np.arange(h) + 0.5) * OUTLINE_CELL)
    left = np.ones(X.shape)
    for R in rs:
        r = R.rect
        i0, i1 = max(0, int((r[0] - x0) / OUTLINE_CELL) - 2), min(w, int((r[1] - x0) / OUTLINE_CELL) + 3)
        j0, j1 = max(0, int((r[2] - y0) / OUTLINE_CELL) - 2), min(h, int((r[3] - y0) / OUTLINE_CELL) + 3)
        left[j0:j1, i0:i1] *= 1.0 - R.sample(fulls[R.id], X[j0:j1, i0:i1], Y[j0:j1, i0:i1])
    cover = (1.0 - left) > 0.5
    b = ndimage.gaussian_filter(cover.astype(float), OUTLINE_SIGMA / OUTLINE_CELL, mode="constant")
    s = smoothstep(0.5, 0.92, b)

    def S(PX, PY):
        u = (PX - x0) / OUTLINE_CELL - 0.5
        v = (PY - y0) / OUTLINE_CELL - 0.5
        return ndimage.map_coordinates(s, [v.ravel(), u.ravel()], order=1, mode="constant", cval=0.0).reshape(PX.shape)
    return S


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
        ms = continent_masks(cont, size)
        for zid, m in ms.items():
            write_tga(outdir / f"z{zid}.tga", size, size, m["g"])
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
