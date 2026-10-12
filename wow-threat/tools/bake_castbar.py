#!/usr/bin/env python3
"""Bake WoW Threat "Castbar fire" textures (1.2.0). Original procedural art.

Port of the approved previewer's fire.js castbar() texture generator: periodic
value noise + fbm, domain-warped, tinted with the Ironforged ramp. Every layer
tiles seamlessly in x (and the flow layer also in y, it scrolls upward).

Usage: bake_castbar.py OUTDIR [--preview DIR]
Writes CB_Base.tga, CB_Flow.tga (512x64), CB_Veil.tga (256x64),
CB_Spark.tga (32x64), CB_Ember.tga (16x16); all 32-bit, power of two.
"""
import os, sys
import numpy as np
from PIL import Image

HOT, MID, COOL = (255, 220, 150), (255, 95, 20), (210, 25, 10)   # Ironforged tint (shared fire)
W, H = 512, 64

def pnoise(w, h, cx, cy, seed):
    """Periodic value noise: tiles in x over cx cells and in y over cy cells."""
    g = np.random.default_rng(seed).random((cy, cx))
    fx = np.arange(w) / w * cx; fy = np.arange(h) / h * cy
    x0 = np.floor(fx).astype(int); y0 = np.floor(fy).astype(int)
    tx = fx - x0; ty = fy - y0
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    x1 = (x0 + 1) % cx; y1 = (y0 + 1) % cy; x0 %= cx; y0 %= cy
    a = g[y0][:, x0]; b = g[y0][:, x1]; c = g[y1][:, x0]; d = g[y1][:, x1]
    TX = tx[None, :]; TY = ty[:, None]
    top = a + (b - a) * TX; bot = c + (d - c) * TX
    return top + (bot - top) * TY

def fbm(w, h, cx, cy, octs, seed):
    o = np.zeros((h, w)); amp, tot = .5, 0
    for k in range(octs):
        o += pnoise(w, h, cx << k, cy << k, seed + k * 977) * amp; tot += amp; amp *= .5
    return o / tot

def warp(arr, dx, dy):
    h, w = arr.shape
    yy, xx = np.mgrid[0:h, 0:w]
    return arr[(np.round(yy + dy).astype(int)) % h, (np.round(xx + dx).astype(int)) % w]

def ramp(v):
    dark = (COOL[0] * .18, COOL[1] * .1, COOL[2] * .06)
    stops = np.array([dark, COOL, MID, HOT, (255, 245, 215)], float)
    t = np.clip(v, 0, 1) * 4; k = np.minimum(3, np.floor(t)).astype(int); f = (t - k)[..., None]
    return stops[k] + (stops[k + 1] - stops[k]) * f

def rgba(rgb, a=None):
    out = np.zeros(rgb.shape[:2] + (4,), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = 255 if a is None else np.clip(a * 255, 0, 255).astype(np.uint8)
    return out

def bake():
    yn = (np.arange(H) / (H - 1))[:, None] * np.ones((1, W))     # 0 top .. 1 bottom
    wx, wy = fbm(W, H, 8, 2, 3, 5), fbm(W, H, 8, 2, 3, 9)
    tb, lo = fbm(W, H, 32, 2, 4, 11), fbm(W, H, 6, 1, 2, 23)
    n = warp(tb, (wx - .5) * 70, (wy - .5) * 24); r = 1 - np.abs(2 * n - 1)
    h = yn ** 1.1 * .75 + (r * r - .45) * .75 + (lo - .5) * .5
    base = np.clip((h + .18) * (.45 + .55 * np.minimum(1, yn * 1.6)), 0, 1)
    l1, l2, wf = fbm(W, H, 40, 2, 3, 57), fbm(W, H, 64, 3, 2, 71), fbm(W, H, 12, 2, 2, 83)
    ddx = (wf - .5) * 40
    r1 = 1 - np.abs(2 * warp(l1, ddx, 0) - 1); r2 = 1 - np.abs(2 * warp(l2, ddx * .6, 0) - 1)
    lo2 = warp(lo, 0, 20)  # same idea as the previewer's at(lo, x, y*.5+20)
    flow = np.clip(r1 ** 5 * 1.25 + r2 ** 8 * .7 - .2, 0, None) * (.35 + .65 * lo2)
    flowv = np.minimum(1, flow)
    veil = fbm(256, 64, 6, 2, 5, 41)
    T = {}
    T["CB_Base"] = rgba(ramp(base * .74))
    T["CB_Flow"] = rgba(ramp(.3 + .55 * flowv) * np.minimum(1, flowv * 1.4)[..., None])
    v = np.clip(veil - .3, 0, None) * .75 * 255
    T["CB_Veil"] = rgba(np.stack([v, v, v], -1))
    # spark: soft vertical ellipse, white core -> hot -> mid, alpha falloff
    yy, xx = np.mgrid[0:64, 0:32]
    d = np.sqrt(((xx - 15.5) / 16) ** 2 + ((yy - 31.5) / 32) ** 2)
    a = np.clip(1 - d, 0, 1) ** 2
    col = np.where((d < .25)[..., None], np.array((255, 240, 200), float), np.array(HOT, float))
    T["CB_Spark"] = rgba(col, a)
    yy, xx = np.mgrid[0:16, 0:16]
    d = np.sqrt(((xx - 7.5) / 8) ** 2 + ((yy - 7.5) / 8) ** 2)
    T["CB_Ember"] = rgba(np.ones((16, 16, 3)) * np.array((255, 225, 150), float), np.clip(1 - d, 0, 1) ** 2.2)
    return T

def main():
    out = sys.argv[1]
    prev = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
    os.makedirs(out, exist_ok=True)
    T = bake()
    for name, arr in T.items():
        Image.fromarray(arr, "RGBA").save(os.path.join(out, name + ".tga"), format="TGA", rle=False)
        print(name, arr.shape[1], "x", arr.shape[0])
    if prev:
        os.makedirs(prev, exist_ok=True)
        sheet = Image.new("RGB", (1040, 300), (20, 20, 20))
        y = 8
        for name in ["CB_Base", "CB_Flow", "CB_Veil"]:
            im = Image.fromarray(T[name], "RGBA"); bg = Image.new("RGBA", im.size, (0, 0, 0, 255)); bg.alpha_composite(im)
            sheet.paste(bg.convert("RGB"), (8, y)); sheet.paste(bg.convert("RGB"), (8 + im.size[0], y)); y += 72  # twice: shows x seam
        # composite like the addon: base + flow ADD .7 + veil ADD .45 (tinted), plus spark and embers
        b = T["CB_Base"][..., :3].astype(float); f = T["CB_Flow"][..., :3].astype(float)
        vv = np.tile(T["CB_Veil"][..., :3].astype(float), (1, 2, 1)) * np.array((1, .47, .12))
        comp = np.clip(b + .7 * f + .45 * vv, 0, 255).astype(np.uint8)
        c = Image.fromarray(comp).crop((0, 0, 330, 64)).resize((330, 64))
        bar = Image.new("RGB", (512, 64)); bar.paste(c, (0, 0))
        sp = Image.fromarray(T["CB_Spark"], "RGBA"); bar = bar.convert("RGBA"); bar.alpha_composite(sp, (314, 0))
        sheet.paste(bar.convert("RGB"), (8, y))
        for i, name in enumerate(["CB_Spark", "CB_Ember"]):
            im = Image.fromarray(T[name], "RGBA"); bg = Image.new("RGBA", im.size, (0, 0, 0, 255)); bg.alpha_composite(im)
            sheet.paste(bg.convert("RGB").resize((im.size[0] * 2, im.size[1] * 2)), (540 + i * 80, y - 70))
        sheet.save(os.path.join(prev, "castbar_textures.png")); print("preview", os.path.join(prev, "castbar_textures.png"))

if __name__ == "__main__":
    main()
