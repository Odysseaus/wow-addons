#!/usr/bin/env python3
"""Bake WoW Threat "Fireplace" flame-wall FlipBook sheets.

Port of the approved previewer's fire.js fireplace() (original code, no game
art). Each frame is a 256x64 texel strip: 256 display px wide, covering the
bar plus ~10 px overflow (24 display px tall at a 14 px bar). The strip tiles
seamlessly in x (wrap crossfade) and the 32-frame loop is seamless in time
(variance-preserving crossfade), played at 8 fps = 4 s.

Usage: bake_fire.py OUTDIR [--preview DIR] [--fallback]
Writes Fire_Fireplace_ironforged.tga (1024x512, 4x8 frames; --all-themes for every tint),
optionally the 2x512x512 fallback halves, plus spark/core/tip/mask textures.
"""
import os, sys
import numpy as np
from PIL import Image

THEMES = {  # previewer themes.js fire tints (hot, mid, cool)
    "emberhall": ((255, 230, 140), (255, 150, 40), (220, 60, 10)),
    "ironforged": ((255, 220, 150), (255, 95, 20), (210, 25, 10)),
    "ursinegrove": ((255, 235, 160), (255, 165, 40), (110, 200, 40)),
    "dawnward": ((255, 240, 165), (255, 195, 70), (225, 130, 25)),
    "voidbound": ((225, 175, 255), (160, 70, 250), (60, 190, 60)),
}
FW, FHT = 256, 64            # frame texels
COLS, ROWS = 4, 8            # sheet grid (32 frames)
FRAMES = COLS * ROWS
LOOP = 4.0                   # seconds at fire speed 1.0 (8 fps)
BAR_H, OVER = 12.0, 10.0     # display px: bar inner (rowHeight 28) + overflow
FH = BAR_H + OVER
CELL = 0.75                  # noise x unit per display px (tuned against the previewer screenshot)
XO = 48                      # wrap crossfade overlap (texels)
NS = 256

def noise_tex(seed=7):
    """Tileable fbm, 5 octaves (fire.js noiseTex)."""
    rng = np.random.default_rng(seed)
    g = np.zeros((NS, NS))
    amp, tot = 1.0, 0.0
    for o in range(5):
        sz = 4 << o
        L = rng.random((sz, sz))
        cs = NS / sz
        f = np.arange(NS) / cs
        i0 = np.floor(f).astype(int)
        t = f - i0
        t = t * t * (3 - 2 * t)
        i0m, i1m = i0 % sz, (i0 + 1) % sz
        a = L[i0m][:, i0m] + (L[i0m][:, i1m] - L[i0m][:, i0m]) * t[None, :]
        b = L[i1m][:, i0m] + (L[i1m][:, i1m] - L[i1m][:, i0m]) * t[None, :]
        g += (a + (b - a) * t[:, None]) * amp
        tot += amp
        amp *= 0.55
    g /= tot
    return (g - g.min()) / (g.max() - g.min())

G = noise_tex()

def ns(x, y):
    x = np.mod(x, NS); y = np.mod(y, NS)
    ix = np.floor(x).astype(int); iy = np.floor(y).astype(int)
    fx = x - ix; fy = y - iy
    ix1 = (ix + 1) & 255; iy1 = (iy + 1) & 255
    a = G[iy, ix] + (G[iy, ix1] - G[iy, ix]) * fx
    b = G[iy1, ix] + (G[iy1, ix1] - G[iy1, ix]) * fx
    return a + (b - a) * fy

def heat_field(t, width, ox=37.0, pct=1.0, inten=1.0):
    """Heat (0..1+) over a width x FHT grid at fire time t (fire.js inner loop)."""
    y = np.arange(FHT)[:, None]
    x = np.arange(width)[None, :]
    yn = 1 - (y + 0.5) / FHT
    yy = yn * FH
    wy = 1 - yn
    base = np.maximum(0, 1 - yy / (BAR_H * 0.55)) * 0.95
    reach = (0.7 + 0.45 * pct) * (0.85 + 0.15 * inten)
    gain = 0.9 + 0.1 * inten
    px = x / CELL
    xx = px + (ns(ox + px * 0.5, yy * 0.8 - t * 6) - 0.5) * (2 + 12 * yn)
    n1 = ns(ox + xx * 3.2 + 200, yy * 0.7 - t * 20)
    n2 = ns(ox + xx * 7 + 60, yy * 1.6 - t * 34)
    r2 = 1 - np.abs(2 * n2 - 1); r4 = r2 * r2
    n = (n1 * 0.55 + r4 * 0.9 - 0.28 - 0.5) * 2.1 + 0.5
    tg = np.clip((ns(ox + xx * 0.9 + 40, -t * 0.3 + 0 * yy) - 0.3) * 1.8, 0, 1)
    fall = np.maximum(0, 1 - yn / (reach * (0.3 + 0.95 * (tg * 0.5 + tg * tg * 0.5))))
    heat = n * fall * 0.95 + base * fall - 0.08
    wisp = (r4 * r4 * 1.3 - 0.68) * wy
    heat = np.maximum(heat, wisp)
    heat = np.where(yn > 0.88, heat * (1 - yn) * 8.3, heat)
    return heat * gain

def vp_blend(a, b, w):
    """Variance-preserving crossfade (keeps flame contrast mid-blend)."""
    th = w * np.pi / 2
    m = 0.5 * (a.mean() + b.mean())
    return m + (a - m) * np.cos(th) + (b - m) * np.sin(th)

def wrap_x(h):
    """Make columns 0..FW-1 tile: blend the overlap tail into the head."""
    out = h[:, :FW].copy()
    w = (np.arange(XO) / XO)[None, :]
    out[:, :XO] = vp_blend(h[:, FW:FW + XO], h[:, :XO], w)
    return out

def frame_heat(i):
    t = i * LOOP / FRAMES
    a = wrap_x(heat_field(t, FW + XO))
    b = wrap_x(heat_field(t - LOOP, FW + XO))
    return vp_blend(a, b, t / LOOP)

def lut(hot, mid, cool):
    def mix(a, b, t): return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))
    dark = tuple(v * 0.55 for v in cool)
    yel = mix(hot, (255, 205, 60), 0.6)
    core = mix(hot, (255, 240, 175), 0.6)
    st = [(0, dark, 0), (0.12, dark, 0.6), (0.28, cool, 0.95), (0.5, mid, 1), (0.72, yel, 1), (0.9, core, 1), (1, core, 1)]
    L = np.zeros((256, 4))
    for i in range(256):
        h = i / 255; j = 0
        while j < len(st) - 2 and h > st[j + 1][0]: j += 1
        a, b = st[j], st[j + 1]
        tt = min(1, max(0, (h - a[0]) / (b[0] - a[0])))
        c = mix(a[1], b[1], tt)
        L[i] = (*c, 255 * (a[2] + (b[2] - a[2]) * tt))
    return L.astype(np.uint8)

def save_tga(arr, path):
    Image.fromarray(arr, "RGBA").save(path, format="TGA", rle=False)

def main():
    out = sys.argv[1]
    prev = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    fallback = "--fallback" in sys.argv
    os.makedirs(out, exist_ok=True)
    heats = [np.clip(frame_heat(i), 0, 1) for i in range(FRAMES)]
    # 1.1.4: the addon ships one fire (Ironforged) for every theme. Pass
    # --all-themes to bake the other tints for experiments (not shipped).
    names = list(THEMES) if "--all-themes" in sys.argv else ["ironforged"]
    for name in names:
        hot, mid, cool = THEMES[name]
        L = lut(hot, mid, cool)
        sheet = np.zeros((FHT * ROWS, FW * COLS, 4), np.uint8)
        for i, h in enumerate(heats):
            k = (h * 255).astype(int)
            r, c = divmod(i, COLS)
            sheet[r * FHT:(r + 1) * FHT, c * FW:(c + 1) * FW] = L[k]
        save_tga(sheet, os.path.join(out, "Fire_Fireplace_%s.tga" % name))
        if fallback:
            # 2 x 512x512 sheets, 16 frames each (2 cols x 8 rows), for clients
            # that refuse 1024-wide textures. Not shipped by default.
            fb = os.path.join(out, "fallback"); os.makedirs(fb, exist_ok=True)
            for half in range(2):
                sub = np.zeros((512, 512, 4), np.uint8)
                for j in range(16):
                    i = half * 16 + j
                    r, c = divmod(i, COLS)
                    fr = sheet[r * FHT:(r + 1) * FHT, c * FW:(c + 1) * FW]
                    rr, cc = divmod(j, 2)
                    sub[rr * FHT:(rr + 1) * FHT, cc * FW:(cc + 1) * FW] = fr
                save_tga(sub, os.path.join(fb, "Fire_Fireplace_%s_%d.tga" % (name, half)))
        if prev:
            os.makedirs(prev, exist_ok=True)
            bg = Image.new("RGBA", (FW * COLS, FHT * ROWS), (0, 0, 0, 255))
            bg.alpha_composite(Image.fromarray(sheet, "RGBA"))
            bg.convert("RGB").save(os.path.join(prev, "sheet_%s.png" % name))
            # one frame at display aspect (256 x 24 display -> 512 x 48 at 2x), tiled twice to show the x seam
            f0 = Image.fromarray(sheet[0:FHT, 0:FW], "RGBA").resize((512, 48), Image.LANCZOS)
            strip = Image.new("RGBA", (1024, 48), (0, 0, 0, 255))
            strip.alpha_composite(f0, (0, 0)); strip.alpha_composite(f0, (512, 0))
            strip.convert("RGB").save(os.path.join(prev, "frame0x2_%s.png" % name))
    # small helper textures (original)
    yy, xx = np.mgrid[0:8, 0:8] + 0.5
    d = np.sqrt((xx - 4) ** 2 + (yy - 4) ** 2) / 4
    a = np.clip(1 - d, 0, 1) ** 1.6
    spark = np.zeros((8, 8, 4), np.uint8); spark[..., 0] = 255; spark[..., 1] = 215; spark[..., 2] = 120
    spark[..., 3] = (a * 255).astype(np.uint8)
    save_tga(spark, os.path.join(out, "Spark.tga"))
    y = np.linspace(1, 0, 32)[:, None] * np.ones((1, 64))
    core = np.zeros((32, 64, 4), np.uint8); core[..., 0] = 255; core[..., 1] = 250; core[..., 2] = 225
    core[..., 3] = (np.clip(1 - y, 0, 1) ** 2 * 255).astype(np.uint8)
    save_tga(core, os.path.join(out, "Fire_Core.tga"))
    ramp = np.linspace(0, 1, 16)[None, :] * np.ones((16, 1))
    tip = np.zeros((16, 16, 4), np.uint8); tip[..., 3] = (ramp ** 1.3 * 255).astype(np.uint8)
    save_tga(tip, os.path.join(out, "TipCap.tga"))
    m = np.ones((16, 256)); m[:, 240:] = np.linspace(1, 0, 16)[None, :]
    mask = np.zeros((16, 256, 4), np.uint8); mask[..., :3] = (m[..., None] * 255).astype(np.uint8); mask[..., 3] = (m * 255).astype(np.uint8)
    save_tga(mask, os.path.join(out, "TipMask.tga"))
    print("baked", len(names), "theme(s),", FRAMES, "frames each")

if __name__ == "__main__":
    main()
