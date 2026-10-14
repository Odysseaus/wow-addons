#!/usr/bin/env python3
"""Bake WoW Threat 1.3.0 "Gem" style + shared bevel frame textures. Original procedural art.

Port of the approved previewer (previews/wow-threat/threat.js: stone(), gemFill(), bevelFrame(), seatShade()).
Usage: bake_gem.py OUTDIR [--preview DIR]
Writes (all 32-bit TGA, power-of-two):
  Gem_Stone.tga  256x32  grey polished stone: vertical depth gradient, fbm mottling, dark veins, pale flecks (tinted per rank in game)
  Gem_Gloss.tga  128x32  polish: glassy top band + sharp specular streak fading right (stretched to the fill)
  Gem_Glow.tga    64x32  soft inner glow (radial, centre low)
  Gem_Spot.tga    32x16  small specular hot spot
  Gem_End.tga     32x8   dark end shading (alpha ramp, mirrored for the right end)
  Gem_Sheen.tga   32x8   soft light sheen band
  Bar_Bevel.tga   64x32  beveled bronze frame, 3-slice (16|32|16), opaque dark seat inside, dark inner rim
  Seat_Shade.tga   8x32  top/bottom inner shadow over fire styles
"""
import os, sys
import numpy as np
from PIL import Image

def save(path, rgba):
    Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA").save(path)

def vnoise(w, h, cx, cy, seed):
    g = np.random.default_rng(seed).random((cy, cx))
    fx = np.arange(w) / w * cx; fy = np.arange(h) / h * cy
    x0 = np.floor(fx).astype(int); y0 = np.floor(fy).astype(int)
    tx = fx - x0; ty = fy - y0; tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    x1 = (x0 + 1) % cx; y1 = (y0 + 1) % cy; x0 %= cx; y0 %= cy
    a = g[y0][:, x0]; b = g[y0][:, x1]; c = g[y1][:, x0]; d = g[y1][:, x1]
    TX = tx[None, :]; TY = ty[:, None]
    top = a + (b - a) * TX; bot = c + (d - c) * TX
    return top + (bot - top) * TY

def stone():
    W, H = 256, 32
    c = vnoise(W, H, 16, 2, 11) * .45 + vnoise(W, H, 40, 5, 12) * .35 + vnoise(W, H, 112, 14, 13) * .2
    vein = np.abs(vnoise(W, H, 12, 3, 14) - .5)
    v = c * 200 + 28
    v = np.where(vein < .025, v - 70 * (1 - vein / .025), v) / 255.0
    # depth gradient (preview: 1.12, 1, .8, .5 at 0, .35, .7, 1), normalised so the top is 1.0
    y = np.linspace(0, 1, H)
    grad = np.interp(y, [0, .35, .7, 1], [1.12, 1, .8, .5]) / 1.12
    # overlay(.5) + multiply(.22) of the stone on the base, approximated on luminance
    base = grad[:, None] * np.ones((1, W))
    ov = np.where(base < .5, 2 * base * v, 1 - 2 * (1 - base) * (1 - v))
    lum = base * .5 + ov * .5
    lum = lum * (1 - .22 + .22 * v)
    rng = np.random.default_rng(15)
    for _ in range(40):                                  # pale inclusions / flecks
        px, py, r, a = rng.random() * W, rng.random() * H, .4 + rng.random() * 1.1, .15 + rng.random() * .35
        yy, xx = np.mgrid[0:H, 0:W]
        dx = np.minimum(np.abs(xx - px), W - np.abs(xx - px))
        m = np.clip(r + .5 - np.sqrt(dx ** 2 + (yy - py) ** 2), 0, 1) * a
        lum = lum * (1 - m) + 1.0 * m
    lum = np.clip(lum, 0, 1) * 255
    out = np.zeros((H, W, 4)); out[..., 0] = lum; out[..., 1] = lum * .97; out[..., 2] = lum * .92; out[..., 3] = 255
    return out

def gloss():
    W, H = 128, 32
    out = np.zeros((H, W, 4)); out[..., :3] = (255, 244, 225)
    y = (np.arange(H) + .5) / H; x = (np.arange(W) + .5) / W
    band = np.interp(y, [0, .225, .45, 1], [.32, .1, 0, 0])            # glassy top band
    a = np.tile(band[:, None], (1, W))
    sx = np.interp(x, [0, .06, .3, .75, 1], [0, .7, .4, .12, .05])        # sharp specular streak
    sy = np.clip(1 - np.abs(y - .165) / .06, 0, 1) ** .7
    s = sy[:, None] * sx[None, :]
    a = a + s * (1 - a)
    out[..., 3] = np.clip(a, 0, 1) * 255
    return out

def radial(W, H, cx, cy, p=1.6):
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xx + .5) / W - cx) ** 2 / .25 + ((yy + .5) / H - cy) ** 2 / .25)
    return np.clip(1 - d, 0, 1) ** p

def bevel():
    W, H, B, R = 64, 32, 6, 4.5
    yy, xx = np.mgrid[0:H, 0:W].astype(float) + .5
    def rrect_mask(x0, y0, x1, y1, r):
        cx = np.clip(xx, x0 + r, x1 - r); cy = np.clip(yy, y0 + r, y1 - r)
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        return np.clip(r - d + .5, 0, 1)
    stops = [(0, (0xd9, 0xc0, 0x8a)), (.25, (0x9c, 0x7f, 0x4c)), (.55, (0x5e, 0x48, 0x26)), (.8, (0x3a, 0x2a, 0x14)), (1, (0x1a, 0x11, 0x08))]
    t = yy / H
    col = np.zeros((H, W, 3))
    for k in range(3):
        col[..., k] = np.interp(t, [s[0] for s in stops], [s[1][k] for s in stops])
    outer = rrect_mask(0, 0, W, H, R)
    inner = rrect_mask(1, 1, W - 1, H - 1, R - 1)
    col = col * inner[..., None] + 0 * (1 - inner[..., None])          # 1px black outline
    # outer chamfer catch-light (top, left)
    hl = ((np.abs(yy - 1.5) < .6) & (xx > R) & (xx < W - R)) | ((np.abs(xx - 1.5) < .6) & (yy > R) & (yy < H - R))
    col[hl] = col[hl] * .5 + np.array((255, 232, 170)) * .5
    ix0, iy0, ix1, iy1 = B, B, W - B, H - B
    # inner chamfer: lit lower lip + right lip
    lip = ((np.abs(yy - (iy1 + .5)) < .6) & (xx >= ix0) & (xx <= ix1 + 1)) | ((np.abs(xx - (ix1 + .5)) < .6) & (yy >= iy0) & (yy <= iy1 + 1))
    col[lip] = col[lip] * .65 + np.array((255, 226, 160)) * .35
    rim = rrect_mask(ix0 - 1.2, iy0 - 1.2, ix1 + 1.2, iy1 + 1.2, 3.2)    # dark inner rim / seat
    col = col * (1 - rim[..., None]) + np.array((10, 5, 2)) * rim[..., None]
    seat = rrect_mask(ix0, iy0, ix1, iy1, 2.2)
    col = col * (1 - seat[..., None]) + np.array((5, 3, 2)) * seat[..., None]
    out = np.zeros((H, W, 4)); out[..., :3] = col; out[..., 3] = outer * 255
    return out

def main():
    od = sys.argv[1]; os.makedirs(od, exist_ok=True)
    T = {}
    T["Gem_Stone"] = stone()
    T["Gem_Gloss"] = gloss()
    g = np.zeros((32, 64, 4)); g[..., :3] = 255; g[..., 3] = radial(64, 32, .5, .7) * 255; T["Gem_Glow"] = g
    s = np.zeros((16, 32, 4)); s[..., :3] = 255; s[..., 3] = radial(32, 16, .5, .5, 1.2) * .5 * 255; T["Gem_Spot"] = s
    e = np.zeros((8, 32, 4)); e[..., 3] = np.tile(np.linspace(.4, 0, 32)[None, :], (8, 1)) * 255; T["Gem_End"] = e
    x = (np.arange(32) + .5) / 32
    sh = np.zeros((8, 32, 4)); sh[..., :3] = (255, 250, 230); sh[..., 3] = np.tile((1 - np.abs(x - .5) * 2)[None, :], (8, 1)) * 255; T["Gem_Sheen"] = sh
    T["Bar_Bevel"] = bevel()
    y = (np.arange(32) + .5) / 32
    ss = np.zeros((32, 8, 4)); ss[..., 3] = np.tile(np.interp(y, [0, .18, .8, 1], [.55, 0, 0, .6])[:, None], (1, 8)) * 255; T["Seat_Shade"] = ss
    for n, a in T.items():
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        im.save(os.path.join(od, n + ".tga"), compression=None)
    if "--preview" in sys.argv:
        pd = sys.argv[sys.argv.index("--preview") + 1]; os.makedirs(pd, exist_ok=True)
        for n, a in T.items():
            im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
            bg = Image.new("RGBA", im.size, (40, 40, 40, 255)); bg.alpha_composite(im)
            bg.resize((im.size[0] * 4, im.size[1] * 4), Image.NEAREST).save(os.path.join(pd, n + ".png"))

if __name__ == "__main__":
    main()
