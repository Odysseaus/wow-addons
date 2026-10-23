#!/usr/bin/env python3
"""Offline composite of the Dark Matter window, from the REAL layout the addon's Lua computes.

The stub test harness (luatools/mock.lua) runs the actual addon code, resolves every texture's anchors, size,
SetTexCoord, vertex colour, draw layer and frame level, and writes layout-<tab>.json. This script reads that JSON
and the same Media/*.tga files and paints the regions in the game's draw order, so what you see here is what the
Lua asks the client to draw (texture orientation, crops and stretching included).

usage: render_preview.py LAYOUT_JSON ADDON_DIR OUT_PNG [scale]
"""
import json
import math
import os
import re
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def find_font():
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    return None


_tex = {}
def apply_grad(piece, g):
    """SetGradient(orient, min, max): VERTICAL min = bottom, HORIZONTAL min = left; multiplies like vertex colour."""
    w, h = piece.size
    lo, hi = g[1:5], g[5:9]
    ramp = Image.new("RGBA", (w, h))
    px = ramp.load()
    for y in range(h):
        for x in range(w):
            t = (x / max(1, w - 1)) if g[0] == "HORIZONTAL" else (1 - y / max(1, h - 1))
            px[x, y] = tuple(int(255 * (lo[i] + (hi[i] - lo[i]) * t)) for i in range(4))
    return ImageChops.multiply(piece, ramp)




def load_tex(addon, path):
    name = path.replace("\\", "/").split("/")[-1]
    if name == "WHITE8X8":
        return Image.new("RGBA", (8, 8), (255, 255, 255, 255))
    if name not in _tex:
        p = os.path.join(addon, "Media", name + ".tga")
        # game icons (Interface\Icons\...) are not in the addon: draw a neutral placeholder square
        im = Image.open(p) if os.path.exists(p) else Image.new("RGBA", (64, 64), (96, 88, 72, 255))
        _tex[name] = im.convert("RGBA")
    return _tex[name]


def crop_tc(im, tc, w, h):
    """Sample tc = (left, right, top, bottom) in 0..1 (top-left origin, like the client) and resize to w x h."""
    W, H = im.size
    nx, ny = max(1, math.ceil(tc[1] - 1e-9)), max(1, math.ceil(tc[3] - 1e-9))  # REPEAT-wrapped strips run past 1
    if nx > 1 or ny > 1:
        big = Image.new(im.mode, (W * nx, H * ny))
        for i in range(nx):
            for j in range(ny):
                big.paste(im, (i * W, j * H))
        im, tc = big, (tc[0] / nx, tc[1] / nx, tc[2] / ny, tc[3] / ny)
        W, H = im.size
    box = (tc[0] * W, tc[2] * H, tc[1] * W, tc[3] * H)
    return im.resize((max(1, round(w)), max(1, round(h))), Image.BILINEAR, box=box)


def clip_layer(layer, clip, margin, scale):
    cx, cy = round((clip[0] + margin) * scale), round((clip[1] + margin) * scale)
    cw, ch = round(clip[2] * scale), round(clip[3] * scale)
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).rectangle([cx, cy, cx + cw - 1, cy + ch - 1], fill=255)
    layer.putalpha(ImageChops.multiply(layer.split()[3], mask))


def main():
    layout, addon, out = sys.argv[1], sys.argv[2], sys.argv[3]
    scale = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
    data = json.load(open(layout))
    ww, wh = data["w"], data["h"]
    margin = int(os.environ.get("DM_RENDER_MARGIN", "40"))
    W, H = int((ww + margin * 2) * scale), int((wh + margin * 2) * scale)
    # fake game scene behind the window
    scene = Image.new("RGBA", (W, H))
    px = scene.load()
    for y in range(H):
        for x in range(W):
            v = int(70 + 40 * (y / H))
            px[x, y] = (v - 10, v, v + 8, 255)
    fpath = find_font()
    fonts = {}
    for it in data["items"]:
        if it["kind"] == "texture":
            if it.get("layer") == "HIGHLIGHT":
                continue  # mouse-over only
            x = round((it["x"] + margin) * scale)
            y = round((it["y"] + margin) * scale)
            w = max(1, round(it["w"] * scale))
            h = max(1, round(it["h"] * scale))
            if it.get("file"):
                im = load_tex(addon, it["file"])
                tc = it.get("tc") or [0, 1, 0, 1]
                if tc[0] > tc[1] or tc[2] > tc[3]:  # an 8-value (rotated) texcoord dumped as 4: draw it unrotated
                    tc = [min(tc[0], tc[1]), max(tc[0], tc[1]), min(tc[2], tc[3]), max(tc[2], tc[3])]
                if tc[0] == tc[1] or tc[2] == tc[3]:
                    continue
                piece = crop_tc(im, tc, w, h)
            elif it.get("color"):
                c = it["color"]
                piece = Image.new("RGBA", (w, h), tuple(int(v * 255) for v in c))
            else:
                continue
            if it.get("grad"):
                piece = apply_grad(piece, it["grad"])
            vc = it.get("vc") or [1, 1, 1, 1]
            alpha = it.get("alpha", 1)
            if vc[:3] != [1, 1, 1] or vc[3] != 1 or alpha != 1:
                r, g, b, a = piece.split()
                r = r.point(lambda v: int(v * vc[0]))
                g = g.point(lambda v: int(v * vc[1]))
                b = b.point(lambda v: int(v * vc[2]))
                k = vc[3] * alpha
                a = a.point(lambda v: int(v * k))
                piece = Image.merge("RGBA", (r, g, b, a))
            layer = Image.new("RGBA", scene.size, (0, 0, 0, 0))
            layer.paste(piece, (x, y))
            if it.get("clip"):
                clip_layer(layer, it["clip"], margin, scale)
            scene = Image.alpha_composite(scene, layer)
        elif it["kind"] == "fontstring" and it.get("text"):
            txt = re.sub(r"\|c[0-9a-fA-F]{8}", "", it["text"]).replace("|r", "")
            size = max(6, round(it["size"] * scale * 0.9))
            if size not in fonts:
                fonts[size] = ImageFont.truetype(fpath, size) if fpath else ImageFont.load_default()
            col = tuple(int(v * 255) for v in it.get("tcol", [1, 1, 1])) + (255,)
            x = (it["x"] + margin) * scale
            y = (it["y"] + margin) * scale
            w = it["w"] * scale
            d = ImageDraw.Draw(scene)
            lines = txt.split("\n")
            tw = max(d.textlength(l, font=fonts[size]) for l in lines)
            just = it.get("just", "LEFT")
            tx = x + (w - tw) / 2 if just == "CENTER" else (x + w - tw if just == "RIGHT" else x)
            tmp = Image.new("RGBA", scene.size, (0, 0, 0, 0))
            td = ImageDraw.Draw(tmp)
            td.multiline_text((tx + 1, y + 1), "\n".join(lines), font=fonts[size], fill=(0, 0, 0, 200))
            td.multiline_text((tx, y), "\n".join(lines), font=fonts[size], fill=col)
            if it.get("clip"):
                clip_layer(tmp, it["clip"], margin, scale)
            scene = Image.alpha_composite(scene, tmp)
    scene.convert("RGB").save(out)
    print("wrote", out, scene.size)


if __name__ == "__main__":
    main()
