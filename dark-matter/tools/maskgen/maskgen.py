#!/usr/bin/env python3
"""Dark Matter zone shape masks (box-side tool; never shipped in the addon, never run on the Mac).

  maskgen.py testmask OUT_DIR
      writes OUT_DIR/dm-masktest.tga: the soft five-point star used by /dm masktest (0.5.2b.5)

  maskgen.py masks SAVEDVARIABLES_FILE ADDON_DIR [--size 256] [--review DIR]
      reads DarkMatterDB.mapshapes (from /dm mapshapes) and writes ADDON_DIR/Media/masks/z<mapID>.tga (soft) and
      z<mapID>c.tga (core), ADDON_DIR/Data_ZoneMasks.lua (the manifest the map reads) and ADDON_DIR/Data_ZoneSeams.lua
      (every border's midpoint, worst first, for /dm seamsweep). --review DIR also writes the border review there:
      borders.txt, borders.csv, contact.png (the worst 36 borders) and overview-<continent>.png. The SavedVariables
      file is only read; no game art is read or drawn (the review paints flat colours per zone).

Masks are uncompressed 32-bit TGA (type 2, bottom-left origin, like the addon's other Media files), white with the
shape in alpha (and in the colour channels), power-of-two square, stretched over the zone's picture by the game.
Two-pass masks (0.5.2b.8), all widths in continent px (cpx, 1/1002 of the continent picture's width) so a feather
is the same on screen for a small and a large zone picture; only the torn parchment rim is in the picture's own art
px. Per zone picture, a work raster (WORK px plus a pad) looks the coarse area samples up per point (finest grid
first). soft: the zone's own land blurred HALO_SIGMA wide, cut before its torn rim: drawn first, under every core,
it closes the seams and fades the coast. core: drawn above all soft masks; every zone's land blurred SIG_C, times
how far that point lies from the zone picture's torn rim, shares w^SHARP / sum w^SHARP, so across a border the
picture that paints the point cleanly wins (a river one picture paints at its edge stays). Last, all pictures'
coverage is blurred (OUTLINE_SIGMA) into one soft rounded outline over the continent picture.
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


# 0.5.2b.8: two masks per zone picture, every width in CONTINENT px (cpx: 1/1002 of the continent picture's width,
# the continent picture is 1002 x 668 cpx), so a feather looks the same on Redridge (a 63 cpx wide picture) as on
# Tanaris (276 cpx) at every zoom. Only the torn parchment rim is in the picture's own art px (it is painted there).
#   soft  z<mapID>.tga   the first pass: the zone's land and a halo HALO_SIGMA past it, cut off before its torn rim;
#                        drawn under every core, it fills each seam and fades the coast into the continent picture
#   core  z<mapID>c.tga  the second pass, drawn above all soft masks: each point of land goes to the picture that
#                        paints it most cleanly. Weight w = (the zone's blurred ownership) x (how far that point lies
#                        from the picture's own torn rim), shares w^SHARP / sum w^SHARP: across a border the picture
#                        whose rim is far away wins, so a river one picture paints at its edge is kept from the other
ART = (1002, 668)   # a zone picture in art px
CPX = (1002, 668)   # the continent picture in cpx (continent map fractions x CPX)
WORK = 512          # work raster per picture (x and y), averaged 2x2 down to the written size
PAD = 72            # work texels of context around the picture
SIG_C = 1.6         # cpx: the blur that rounds the game's stair-step area borders (cells are 0.4 to 1.7 cpx)
SHARP = 3.0         # the core shares: w^SHARP (a crossfade about 2 cpx wide across a border)
FILL_C = (1.0, 5.0) # cpx: points of no zone (sea, unzoned land) count for the nearest zone, fading out over FILL_C
RIM_ART = 22.0      # art px: the core never uses a picture's outer RIM_ART art px (the torn parchment) ...
RIM_RAMP_C = 2.5    # ... and reaches full weight RIM_RAMP_C cpx further in
SOFT_RIM_ART = 10.0 # art px: the soft pass stops this close to the torn edge ...
SOFT_RAMP_C = 1.0   # ... fading in over 1 cpx
HALO_SIGMA = 2.0    # cpx: the soft pass reaches about 2 x HALO_SIGMA past the zone's land
COAST = (0.45, 0.8) # the core fades out where the blurred land (all zones) drops from 0.8 to 0.45 (the coast)
QMIN = 0.2          # the core is full only where its picture's rim weight passes QMIN (a seam both rims share fades)
EXTRA_MARGIN_C = 2 * HALO_SIGMA * 2 + RIM_RAMP_C + 2.0  # cpx around a neighbour-made mask's land (no edge in sight)


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


class Pic:
    """one zone picture: its rect on the continent (a sampled zone: the game's rect; a zone made from its neighbours'
    samples: a rect around its land, the picture beyond it unknown), and its rim weights at any continent point"""

    def __init__(self, zid, name, rect, extra):
        self.id, self.name, self.rect, self.extra = zid, name, rect, extra
        r = rect
        self.wc, self.hc = (r[1] - r[0]) * CPX[0], (r[3] - r[2]) * CPX[1]  # its size in cpx
        self.apx = (ART[0] / self.wc, ART[1] / self.hc)  # art px per cpx (x, y)

    def edge_cpx(self, X, Y):
        """cpx from the picture's (or the rect's) nearest left/right and top/bottom edge; negative outside"""
        import numpy as np
        r = self.rect
        dx = np.minimum(X - r[0], r[1] - X) * CPX[0]
        dy = np.minimum(Y - r[2], r[3] - Y) * CPX[1]
        return dx, dy

    def rim(self, X, Y, soft=False):
        """0 on the torn rim, 1 well inside: the hard cut in art px, the ramp after it in cpx"""
        dx, dy = self.edge_cpx(X, Y)
        if self.extra:  # no picture edge known: only the rect, far from its land (EXTRA_MARGIN_C)
            ramp = SOFT_RAMP_C if soft else RIM_RAMP_C
            return smoothstep(0.5, 0.5 + ramp, dx) * smoothstep(0.5, 0.5 + ramp, dy)
        cut, ramp = (SOFT_RIM_ART, SOFT_RAMP_C) if soft else (RIM_ART, RIM_RAMP_C)
        tx = smoothstep(0.0, ramp, dx - cut / self.apx[0])
        ty = smoothstep(0.0, ramp, dy - cut / self.apx[1])
        return tx * ty

    def overlaps(self, o):
        a, b = self.rect, o.rect
        return a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3]


def pictures(cont):
    pics = [Pic(g.id, g.name, g.r, False) for g in cont.grids]
    for zid in cont.extra:
        b = cont.box[zid]
        mx, my = max((b[1] - b[0]) * 0.06, EXTRA_MARGIN_C / CPX[0]), max((b[3] - b[2]) * 0.06, EXTRA_MARGIN_C / CPX[1])
        pics.append(Pic(zid, NAMES.get(zid, f"zone {zid}"), (b[0] - mx, b[1] + mx, b[2] - my, b[3] + my), True))
    return pics


def fields(P, pics, arrays, X, Y, tx, ty):
    """soft and core of picture P at continent points X, Y (a regular raster: tx, ty cpx per texel)"""
    import numpy as np
    from scipy import ndimage
    lab = labels_at(arrays, X, Y)
    empty = lab < 0
    if empty.all():
        return np.zeros(X.shape), np.zeros(X.shape)
    dist, idx = ndimage.distance_transform_edt(empty, sampling=(ty, tx), return_indices=True)
    near = lab[idx[0], idx[1]]
    wEmpty = 1.0 - smoothstep(FILL_C[0], FILL_C[1], dist)
    sig = (SIG_C / ty, SIG_C / tx)
    byid = {p.id: p for p in pics}
    land = np.zeros(X.shape)
    pw, mine = {}, None
    for j in np.unique(near[near >= 0]):
        j = int(j)
        ind = (near == j) * wEmpty
        ow = ndimage.gaussian_filter(ind, sig, mode="nearest")
        land += ow
        O = byid.get(j)
        if O is None:
            continue
        w = ow * O.rim(X, Y)
        pw[j] = w ** SHARP
        if j == P.id:
            mine = ind
    if mine is None:
        return np.zeros(X.shape), np.zeros(X.shape)
    tot = sum(pw.values()) + 1e-12
    core = pw[P.id] / tot * smoothstep(0.0, QMIN, P.rim(X, Y)) * smoothstep(COAST[0], COAST[1], land)
    halo = ndimage.gaussian_filter(mine, (HALO_SIGMA / ty, HALO_SIGMA / tx), mode="nearest")
    soft = smoothstep(0.03, 0.2, halo) * P.rim(X, Y, soft=True)
    return soft, core


def raster(P):
    import numpy as np
    n = WORK + 2 * PAD
    k = (np.arange(n) - PAD + 0.5) / WORK
    r = P.rect
    X = r[0] + k[None, :] * (r[1] - r[0]) + 0 * k[:, None]
    Y = r[2] + k[:, None] * (r[3] - r[2]) + 0 * k[None, :]
    return X, Y, P.wc / WORK, P.hc / WORK


def continent_masks(cont, size):
    """({ zid: soft mask }, { zid: core mask }, pics); a mask = { name, rect, g (size x size rows, top first), w, h, extra }"""
    arrays = owner_arrays(cont)
    pics = pictures(cont)
    raw = {}
    for P in pics:
        X, Y, tx, ty = raster(P)
        raw[P.id] = (X, Y) + fields(P, pics, arrays, X, Y, tx, ty)
    # the continent's outline: what all the soft masks together cover, blurred wide and faded inward, so the zones end
    # in one soft rounded edge over the continent picture (the game's areas are square blocks out at sea)
    S = outline(pics, {k: v[2] for k, v in raw.items()})
    soft, core = {}, {}
    f = WORK // size
    for P in pics:
        X, Y, s, c = raw[P.id]
        o = S(X, Y)
        for out, a in ((soft, s * o), (core, c * o)):
            g = a[PAD:PAD + WORK, PAD:PAD + WORK].reshape(size, f, size, f).mean(axis=(1, 3))
            out[P.id] = {"name": P.name, "rect": P.rect, "g": g, "w": size, "h": size, "extra": P.extra}
    return soft, core, pics


OUTLINE_CELL = 0.0004   # continent raster for the outline (map fractions)
OUTLINE_SIGMA = 0.0028  # its blur (map fractions: 2.8 cpx)


def outline(pics, fulls):
    """S(X, Y): 1 inside the zones' union, fading to 0 at its blurred, rounded outer edge"""
    import numpy as np
    from scipy import ndimage
    x0 = min(P.rect[0] for P in pics) - 0.01
    x1 = max(P.rect[1] for P in pics) + 0.01
    y0 = min(P.rect[2] for P in pics) - 0.01
    y1 = max(P.rect[3] for P in pics) + 0.01
    w, h = int((x1 - x0) / OUTLINE_CELL) + 1, int((y1 - y0) / OUTLINE_CELL) + 1
    X, Y = np.meshgrid(x0 + (np.arange(w) + 0.5) * OUTLINE_CELL, y0 + (np.arange(h) + 0.5) * OUTLINE_CELL)
    left = np.ones(X.shape)
    for P in pics:
        r = P.rect
        i0, i1 = max(0, int((r[0] - x0) / OUTLINE_CELL) - 2), min(w, int((r[1] - x0) / OUTLINE_CELL) + 3)
        j0, j1 = max(0, int((r[2] - y0) / OUTLINE_CELL) - 2), min(h, int((r[3] - y0) / OUTLINE_CELL) + 3)
        left[j0:j1, i0:i1] *= 1.0 - sample_work(P.rect, fulls[P.id], X[j0:j1, i0:i1], Y[j0:j1, i0:i1])
    cover = (1.0 - left) > 0.5
    b = ndimage.gaussian_filter(cover.astype(float), OUTLINE_SIGMA / OUTLINE_CELL, mode="constant")
    s = smoothstep(0.5, 0.92, b)

    def S(PX, PY):
        u = (PX - x0) / OUTLINE_CELL - 0.5
        v = (PY - y0) / OUTLINE_CELL - 0.5
        return ndimage.map_coordinates(s, [v.ravel(), u.ravel()], order=1, mode="constant", cval=0.0).reshape(PX.shape)
    return S


def sample_work(rect, field, X, Y):
    """a work raster (with its pad) at continent points X, Y (bilinear; 0 outside it)"""
    from scipy import ndimage
    r = rect
    u = (X - r[0]) / (r[1] - r[0]) * WORK + PAD - 0.5
    v = (Y - r[2]) / (r[3] - r[2]) * WORK + PAD - 0.5
    return ndimage.map_coordinates(field, [v.ravel(), u.ravel()], order=1, mode="constant", cval=0.0).reshape(X.shape)


def sample_vec(mask, X, Y):
    """a written mask at continent points X, Y (bilinear like the game; 0 outside its rect)"""
    import numpy as np
    from scipy import ndimage
    r, g, w, h = mask["rect"], np.asarray(mask["g"]), mask["w"], mask["h"]
    u = (X - r[0]) / (r[1] - r[0]) * w - 0.5
    v = (Y - r[2]) / (r[3] - r[2]) * h - 0.5
    a = ndimage.map_coordinates(g, [v.ravel(), u.ravel()], order=1, mode="nearest").reshape(X.shape)
    inside = (X >= r[0]) & (X <= r[1]) & (Y >= r[2]) & (Y <= r[3])
    return np.where(inside, a, 0.0)


def composite(soft, core, X, Y):
    """what the two passes draw at X, Y: { zid: share of the final colour }, and the share left to the continent
    picture. Pass order inside a pass is not fixed in game, so the shares are the order-free estimate: the cores
    first (their sum capped at 1), the softs split what the cores leave by their strength."""
    import numpy as np
    cs = {z: sample_vec(m, X, Y) for z, m in core.items()}
    ss = {z: sample_vec(m, X, Y) for z, m in soft.items()}
    csum = np.minimum(1.0, sum(cs.values()))
    left_s = np.ones(X.shape)
    for a in ss.values():
        left_s = left_s * (1.0 - a)
    ssum = sum(ss.values()) + 1e-9
    rest = 1.0 - csum
    share = {}
    for z in core:
        c = cs[z] / np.maximum(1.0, sum(cs.values()))
        share[z] = c + rest * (1.0 - left_s) * ss[z] / ssum
    base = rest * left_s
    return share, base


def check(cont, soft, core):
    """the offline sweep: every sampled land point of the continent against what the two passes draw there.
    base-land: land where the continent picture still shows more than 10%; wrong-art: land whose own zone's share is
    under 50% while another zone's is over 50% (a neighbour's picture shows: by design within a few cpx of a border,
    where the cleaner picture wins); overlap: land where two zone cores are both 90% or more."""
    import numpy as np
    pts, mine, seen = [], [], set()
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
                o = cont.owner_of(v)
                if o is None:
                    continue
                pts.append((x, y))
                mine.append(o)
    P = np.array(pts)
    X, Y, mine = P[:, 0], P[:, 1], np.array(mine)
    share, base = composite(soft, core, X, Y)
    zs = list(share)
    S = np.stack([share[z] for z in zs])
    own = np.zeros(len(X))
    for k, z in enumerate(zs):
        own = np.where(mine == z, S[k], own)
    other = np.max(np.where(np.array(zs)[:, None] == mine[None, :], 0.0, S), axis=0)
    cs = np.stack([sample_vec(core[z], X, Y) for z in zs])
    strong = (cs >= 0.9).sum(axis=0)
    bad = base > 0.1
    worst = {}
    for z in np.unique(mine[bad]):
        worst[int(z)] = int((mine[bad] == z).sum())
    n = len(X)
    return {"points": n, "base": int(bad.sum()), "wrong": int(((own < 0.5) & (other > 0.5)).sum()), "overlap": int((strong >= 2).sum()),
            "worst": sorted(worst.items(), key=lambda t: -t[1])[:5]}


# 0.5.2b.8: border review, step 1 (box-side, from the shape data only: no game art is read or drawn). Per border
# between two zones: the band 2 cpx either side of where the game's areas meet, and what the two passes draw there.
#   leak     share of the band where the continent picture still shows more than 10% (a hole between the pictures)
#   rimseam  share where BOTH pictures are within their torn rim (no picture paints it cleanly)
#   torn     share where the picture that wins is within its own torn rim (a torn edge shows)
#   third    share where a third zone's picture wins (a neighbour's parchment over the border)
#   cell     the sample cell there in cpx (the game's blocks: how far the border may be off)
# score = 100 x (2 leak + 1.5 rimseam + torn + 2 third), +5 for a zone made from its neighbours' samples; worst first.
REVIEW_CELL = 0.5   # cpx
REVIEW_BAND = 2.0   # cpx either side of the border


def zone_colour(z):
    import colorsys
    h = ((z * 2654435761) % 1000) / 1000.0
    r, g, b = colorsys.hsv_to_rgb(h, 0.45, 0.92)
    return (r, g, b)


def borders(cont, soft, core, pics):
    import numpy as np
    from scipy import ndimage
    arrays = owner_arrays(cont)
    x0 = min(P.rect[0] for P in pics)
    x1 = max(P.rect[1] for P in pics)
    y0 = min(P.rect[2] for P in pics)
    y1 = max(P.rect[3] for P in pics)
    cx, cy = REVIEW_CELL / CPX[0], REVIEW_CELL / CPX[1]
    w, h = int((x1 - x0) / cx) + 1, int((y1 - y0) / cy) + 1
    X, Y = np.meshgrid(x0 + (np.arange(w) + 0.5) * cx, y0 + (np.arange(h) + 0.5) * cy)
    lab = labels_at(arrays, X, Y)
    pm = np.full(lab.shape, -1, dtype=np.int64)
    pairs, index = [], {}

    def mark(a, b, sl):
        m = (a >= 0) & (b >= 0) & (a != b)
        if not m.any():
            return
        lo, hi = np.minimum(a, b)[m], np.maximum(a, b)[m]
        keys = lo * 100000 + hi
        ids = np.empty(len(keys), dtype=np.int64)
        for k in np.unique(keys):
            if int(k) not in index:
                index[int(k)] = len(pairs)
                pairs.append((int(k) // 100000, int(k) % 100000))
            ids[keys == k] = index[int(k)]
        sub = pm[sl]
        sub[m] = ids
        pm[sl] = sub
    mark(lab[:, :-1], lab[:, 1:], (slice(None), slice(0, w - 1)))
    mark(lab[:-1, :], lab[1:, :], (slice(0, h - 1), slice(None)))
    land = lab >= 0
    share, base = composite(soft, core, X, Y)
    zs = list(share)
    S = np.stack([share[z] for z in zs])
    dom = np.array(zs)[np.argmax(S, axis=0)]
    domS = np.max(S, axis=0)
    byid = {P.id: P for P in pics}
    qdom = np.zeros(X.shape)
    for z in zs:
        m = dom == z
        if m.any():
            qdom[m] = byid[z].rim(X[m], Y[m])
    dist, idx = ndimage.distance_transform_edt(pm < 0, return_indices=True)
    band = land & (dist * REVIEW_CELL <= REVIEW_BAND)
    pid = pm[idx[0], idx[1]]
    out = []
    for k, (a, b) in enumerate(pairs):
        line = pm == k
        m = band & (pid == k)
        n = int(m.sum())
        if n < 4:
            continue
        qa, qb = byid[a].rim(X[m], Y[m]) if a in byid else 0 * X[m], byid[b].rim(X[m], Y[m]) if b in byid else 0 * X[m]
        leak = float((base[m] > 0.1).mean())
        rimseam = float((np.maximum(qa, qb) < 0.5).mean())
        torn = float(((qdom[m] < 0.5) & (domS[m] > 0.3)).mean())
        third = float((~np.isin(dom[m], [a, b]) & (domS[m] > 0.5)).mean())
        jj, ii = np.nonzero(line)
        mj, mi = jj.mean(), ii.mean()
        c = int(np.argmin((jj - mj) ** 2 + (ii - mi) ** 2))
        mx, my = float(X[jj[c], ii[c]]), float(Y[jj[c], ii[c]])
        cell = None
        for g in cont.grids:
            if g.contains(mx, my):
                cell = g.cell * CPX[0]
                break
        extra = (a in byid and byid[a].extra) or (b in byid and byid[b].extra)
        score = 100.0 * (2 * leak + 1.5 * rimseam + torn + 2 * third) + (5.0 if extra else 0.0)
        out.append({"cont": cont.id, "a": a, "b": b, "an": byid[a].name if a in byid else str(a), "bn": byid[b].name if b in byid else str(b),
                    "len": len(jj) * REVIEW_CELL, "leak": leak, "rimseam": rimseam, "torn": torn, "third": third, "cell": cell,
                    "extra": bool(extra), "score": score, "x": mx, "y": my, "ij": (int(jj[c]), int(ii[c]))})
    out.sort(key=lambda e: -e["score"])
    view = {"X": X, "Y": Y, "lab": lab, "share": share, "base": base, "pm": pm, "qdom": qdom, "domS": domS, "zs": zs}
    return out, view


def render(view, j0, j1, i0, i1):
    """RGB of the two passes over a window of the review raster: each zone's flat colour by its share, the continent
    picture's share in red; torn rims that win striped yellow; the game's borders black"""
    import numpy as np
    sl = (slice(j0, j1), slice(i0, i1))
    rgb = np.zeros((j1 - j0, i1 - i0, 3))
    for z in view["zs"]:
        rgb += view["share"][z][sl][:, :, None] * np.array(zone_colour(z))[None, None, :]
    sea = view["lab"][sl] < 0
    basec = np.where(sea[:, :, None], np.array((0.22, 0.3, 0.42))[None, None, :], np.array((0.85, 0.12, 0.12))[None, None, :])
    rgb += view["base"][sl][:, :, None] * basec
    jj, ii = np.mgrid[j0:j1, i0:i1]
    torn = (view["qdom"][sl] < 0.5) & (view["domS"][sl] > 0.3) & (((jj + ii) // 3) % 2 == 0)
    rgb[torn] = rgb[torn] * 0.4 + np.array((1.0, 0.85, 0.1)) * 0.6
    rgb[view["pm"][sl] >= 0] = (0.05, 0.05, 0.05)
    rgb[sea] = rgb[sea] * 0.55 + np.array((0.35, 0.45, 0.6)) * 0.45
    return (np.clip(rgb, 0, 1) * 255).astype(np.uint8)


def review(results, outdir, version):
    """borders.txt / borders.csv, contact.png (worst first) and an overview per continent"""
    import numpy as np
    from PIL import Image, ImageDraw
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    allb = []
    for cont, bl, view in results:
        for e in bl:
            allb.append((e, view, cont))
    allb.sort(key=lambda t: -t[0]["score"])
    lines = [f"Dark Matter {version} border review (box-side, from DarkMatterDB.mapshapes only; no game art). Worst first.",
             "score = 100 x (2 leak + 1.5 rimseam + torn + 2 third) (+5: a zone made from its neighbours' samples)",
             "leak: continent picture shows >10%  rimseam: both pictures in their torn rim  torn: the winning picture in its rim",
             "third: a third zone's picture wins  cell: game sample block (cpx)  band: 2 cpx either side",
             ""]
    csv = ["rank,cont,a,b,a_name,b_name,score,len_cpx,leak,rimseam,torn,third,cell_cpx,extra,x,y"]
    for r, (e, _, cont) in enumerate(allb, 1):
        e["rank"] = r
        cell = f"{e['cell']:.2f}" if e["cell"] else "?"
        lines.append(f"{r:3d}. {cont.name[:9]:9s} {e['an'][:22]:22s} | {e['bn'][:22]:22s} score {e['score']:6.1f}  len {e['len']:6.1f}  "
                     f"leak {100*e['leak']:5.1f}%  rimseam {100*e['rimseam']:5.1f}%  torn {100*e['torn']:5.1f}%  third {100*e['third']:5.1f}%  "
                     f"cell {cell}{'  (neighbour-made)' if e['extra'] else ''}  at {100*e['x']:.1f},{100*e['y']:.1f}")
        csv.append(f"{r},{cont.id},{e['a']},{e['b']},\"{e['an']}\",\"{e['bn']}\",{e['score']:.2f},{e['len']:.1f},{e['leak']:.4f},{e['rimseam']:.4f},"
                   f"{e['torn']:.4f},{e['third']:.4f},{cell},{int(e['extra'])},{e['x']:.5f},{e['y']:.5f}")
    (outdir / "borders.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (outdir / "borders.csv").write_text("\n".join(csv) + "\n", encoding="utf-8")
    # contact sheet: the worst 36, a 44 cpx window around each border's midpoint
    N, half, tile, cols = min(36, len(allb)), int(22 / REVIEW_CELL), 220, 6
    rows = (N + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile, rows * (tile + 30) + 40), (20, 18, 14))
    d = ImageDraw.Draw(sheet)
    d.text((8, 8), f"Dark Matter {version} border review, worst first. Zone colours by share; red = continent picture shows on land; "
                   f"yellow stripes = torn rim wins; black = the game's border; blue = no zone (sea, unzoned). 44 cpx per tile.", fill=(230, 220, 190))
    for k in range(N):
        e, view, cont = allb[k]
        j, i = e["ij"]
        H, W = view["lab"].shape
        j0, j1, i0, i1 = max(0, j - half), min(H, j + half), max(0, i - half), min(W, i + half)
        im = Image.fromarray(render(view, j0, j1, i0, i1)).resize((tile, tile), Image.NEAREST)
        x, y = (k % cols) * tile, 40 + (k // cols) * (tile + 30)
        sheet.paste(im, (x, y + 30))
        d.text((x + 4, y + 2), f"#{e['rank']} {e['an'][:14]} | {e['bn'][:14]}", fill=(240, 230, 200))
        d.text((x + 4, y + 15), f"s{e['score']:.0f} leak{100*e['leak']:.0f} seam{100*e['rimseam']:.0f} torn{100*e['torn']:.0f} 3rd{100*e['third']:.0f}",
               fill=(200, 190, 160))
    sheet.save(outdir / "contact.png")
    # overview per continent: the whole map, the top 20 ranks marked
    for cont, bl, view in results:
        H, W = view["lab"].shape
        im = Image.fromarray(render(view, 0, H, 0, W)).resize((W, H), Image.NEAREST)  # 2 px per cpx (the review cell is 0.5 cpx)
        dd = ImageDraw.Draw(im)
        for e in sorted(bl, key=lambda e: e["rank"])[:20]:
            j, i = e["ij"]
            dd.ellipse((i - 9, j - 9, i + 9, j + 9), outline=(255, 255, 255), width=2)
            dd.text((i + 11, j - 6), str(e["rank"]), fill=(255, 255, 255))
        im.save(outdir / f"overview-{cont.id}.png")
    return allb, lines


def masks(sv, addon, size=256, review_dir=None):
    shapes = load_shapes(sv)
    addon = Path(addon)
    outdir = addon / "Media" / "masks"
    outdir.mkdir(parents=True, exist_ok=True)
    made, report, results = [], [], []
    when = str(shapes["when"]) if shapes["when"] is not None else "?"
    for cid in shapes["conts"]:
        cont = Continent(cid, shapes["conts"][cid])
        soft, core, pics = continent_masks(cont, size)
        for zid in soft:
            write_tga(outdir / f"z{zid}.tga", size, size, soft[zid]["g"])
            write_tga(outdir / f"z{zid}c.tga", size, size, core[zid]["g"])
            made.append((cont.id, zid, soft[zid]))
        c = check(cont, soft, core)
        cities = sorted(v for v in cont.box if v in CITIES)
        report.append(f"{cont.name} ({cont.id}): {len(soft)} zones x 2 masks ({len(cont.grids)} sampled + {len(cont.extra)} from neighbours: "
                      f"{', '.join(soft[z]['name'] for z in cont.extra) or 'none'}); cities on their zone: "
                      f"{', '.join(f'{c_}->{cont.host.get(c_)}' for c_ in cities) or 'none'}")
        report.append(f"  sweep over {c['points']} land points: base-land {c['base']} ({100.0 * c['base'] / max(1, c['points']):.2f}%), "
                      f"wrong-art {c['wrong']} ({100.0 * c['wrong'] / max(1, c['points']):.2f}%), overlap {c['overlap']} "
                      f"({100.0 * c['overlap'] / max(1, c['points']):.2f}%); base-land most in {c['worst']}")
        bl, view = borders(cont, soft, core, pics)
        results.append((cont, bl, view))
    made.sort(key=lambda t: (t[0], t[1]))
    lines = [
        "-- Data_ZoneMasks.lua: GENERATED by tools/maskgen/maskgen.py from DarkMatterDB.mapshapes (/dm mapshapes). Do not edit by hand.",
        f"-- Shapes sampled {when}. NS.ZoneMasks[mapID] = { '{' } file = soft mask (first pass), core = core mask (second pass, drawn",
        "-- above every soft mask), cont, rect { '}' }. rect (continent map fractions x1, x2, y1, y2) only on a mask made from its",
        "-- neighbours' samples (the zone had none of its own): the masks cover that rectangle of the picture, not all of it.",
        "local _, NS = ...",
        f'NS.ZoneMasksInfo = {{ when = "{when}", version = 2 }}',
        "NS.ZoneMasks = {",
    ]
    lines[1] = lines[1].replace("{ '{' }", "{").replace("{ '}' }", "}")
    lines[2] = lines[2].replace("{ '{' }", "{").replace("{ '}' }", "}")
    for cid, zid, m in made:
        rect = ""
        if m["extra"]:
            rect = ", rect = {{ {:.5f}, {:.5f}, {:.5f}, {:.5f} }}".format(*m["rect"])
        base = "Interface\\\\AddOns\\\\DarkMatter\\\\Media\\\\masks\\\\z"
        lines.append(f'  [{zid}] = {{ file = "{base}{zid}", core = "{base}{zid}c", cont = {cid}{rect} }}, -- {m["name"]}')
    lines.append("}")
    (addon / "Data_ZoneMasks.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    # the borders for /dm seamsweep (worst first per continent): { a, b, x, y, score } in continent map fractions
    sl = ["-- Data_ZoneSeams.lua: GENERATED by tools/maskgen/maskgen.py with Data_ZoneMasks.lua. Do not edit by hand.",
          "-- NS.ZoneSeams[continent] = { { zoneA, zoneB, x, y, score }, ... } worst first: each border's midpoint for /dm seamsweep.",
          "local _, NS = ...", "NS.ZoneSeams = {"]
    for cont, bl, _ in results:
        sl.append(f"  [{cont.id}] = {{ -- {cont.name}")
        for e in bl:
            sl.append(f"    {{ {e['a']}, {e['b']}, {e['x']:.4f}, {e['y']:.4f}, {e['score']:.1f} }}, -- {e['an']} | {e['bn']}")
        sl.append("  },")
    sl.append("}")
    (addon / "Data_ZoneSeams.lua").write_text("\n".join(sl) + "\n", encoding="utf-8")
    print(f"{len(made)} zones x 2 masks ({size}x{size}) -> {outdir}")
    for line in report:
        print(line)
    if review_dir:
        allb, rl = review(results, review_dir, "maskgen v2")
        print(f"border review: {len(allb)} borders -> {review_dir}/borders.txt, contact.png, overview-*.png")
        for line in rl[5:17]:
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
        rv = argv[argv.index("--review") + 1] if "--review" in argv else None
        masks(argv[2], argv[3], size, rv)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
