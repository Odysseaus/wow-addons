#!/usr/bin/env python3
"""Export the approved previewer theme art (art/*.png) to power-of-two 32-bit
TGA for WoWThreat, art placed at the top-left of the padded canvas. Also
writes the original FX textures used by theme animations (soft glow, sweep).
Prints the texcoord extents (u1, v1) Theme.lua uses to crop the padding.

Usage: export_theme_art.py ART_DIR OUT_DIR
"""
import os, sys, glob
import numpy as np
from PIL import Image

RENAME = {"default": "emberhall", "warrior": "ironforged", "druid": "ursinegrove",
          "paladin": "dawnward", "voidwalker": "voidbound"}

def p2(n):
    v = 1
    while v < n: v <<= 1
    return v

def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for f in sorted(glob.glob(os.path.join(src, "*.png"))):
        base = os.path.basename(f)[:-4]
        theme, part = base.split("_", 1)
        im = Image.open(f).convert("RGBA")
        w, h = im.size
        W, H = p2(w), p2(h)
        if part in ("material", "panel") and (W, H) != (w, h):
            im = im.resize((W, H), Image.LANCZOS); w, h = W, H
        canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        canvas.paste(im, (0, 0))
        name = "%s_%s.tga" % (RENAME[theme], part)
        canvas.save(os.path.join(out, name), format="TGA", rle=False)
        print("%-28s %4dx%-4d -> %4dx%-4d u1=%.4f v1=%.4f" % (name, w, h, W, H, w / W, h / H))
    # FX: soft radial glow 64x64 and a soft vertical light band 64x64 (original)
    yy, xx = np.mgrid[0:64, 0:64] + 0.5
    d = np.sqrt((xx - 32) ** 2 + (yy - 32) ** 2) / 32
    a = np.clip(1 - d, 0, 1) ** 2
    g = np.zeros((64, 64, 4), np.uint8); g[..., :3] = 255; g[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(g, "RGBA").save(os.path.join(out, "fx_glow.tga"), format="TGA", rle=False)
    band = np.exp(-((xx - 32) / 12.0) ** 2)
    s = np.zeros((64, 64, 4), np.uint8); s[..., :3] = 255; s[..., 3] = (band * 255).astype(np.uint8)
    Image.fromarray(s, "RGBA").save(os.path.join(out, "fx_sweep.tga"), format="TGA", rle=False)
    w1 = np.zeros((8, 8, 4), np.uint8); w1[..., :3] = 255; w1[..., 3] = 255
    Image.fromarray(w1, "RGBA").save(os.path.join(out, "fx_white.tga"), format="TGA", rle=False)

if __name__ == "__main__":
    main()
