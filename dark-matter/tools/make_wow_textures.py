#!/usr/bin/env python3
"""Convert the previewer's GENERATED WoW-theme raster art into addon textures.

Nothing is drawn here: every pixel comes from the generated art in
addon-previewer/previews/dark-matter/art/wow/*.webp (made with the image tool).
This script only crops, resizes, packs and writes uncompressed 32-bit TGA files with
power-of-two sizes, plus the Lua atlas table that tells the addon where each piece is.
The four tab glyphs are the mockup's own SVG paths (darkmatter.js TABS) rasterised as-is.

Usage: make_wow_textures.py [ART_DIR] [PREVIEW_JS] [ADDON_DIR]
"""
import json, os, re, sys
from PIL import Image

ART = sys.argv[1] if len(sys.argv) > 1 else "/workspace/addon-previewer/previews/dark-matter/art/wow"
JS = sys.argv[2] if len(sys.argv) > 2 else "/workspace/addon-previewer/previews/dark-matter/darkmatter.js"
ADDON = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "DarkMatter")
MEDIA = os.path.join(ADDON, "Media")
GUTTER = 2


def load(name):
    return Image.open(os.path.join(ART, name)).convert("RGBA")


def crop(name, box):
    return load(name).crop(box)


def glyphs():
    """Rasterise the mockup's tab glyph SVG paths (white strokes, transparent) with Chromium."""
    from playwright.sync_api import sync_playwright
    src = open(JS).read()
    found = re.findall(r"\{id:'(\w+)',name:'[^']+',icon:'([^']+)'\}", src)
    ids = ["quests", "journals", "map", "dungeons"]
    paths = dict(found)
    out = {}
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 128, "height": 128})
        for i in ids:
            html = ('<html><body style="margin:0;background:transparent"><svg xmlns="http://www.w3.org/2000/svg" '
                    'viewBox="0 0 24 24" width="128" height="128" fill="none" stroke="#fff" stroke-width="1.8" '
                    'stroke-linecap="round" stroke-linejoin="round">%s</svg></body></html>' % paths[i])
            pg.set_content(html)
            png = "/tmp/dm_glyph_%s.png" % i
            pg.screenshot(path=png, omit_background=True)
            out["glyph_" + i] = Image.open(png).convert("RGBA")
        b.close()
    return out


def pieces():
    P = {}
    W, H = 1760, 1360
    c = 32
    P["frame_tl"] = crop("frame.webp", (0, 0, c, c))
    P["frame_tr"] = crop("frame.webp", (W - c, 0, W, c))
    P["frame_bl"] = crop("frame.webp", (0, H - c, c, H))
    P["frame_br"] = crop("frame.webp", (W - c, H - c, W, H))
    P["frame_t"] = crop("frame.webp", (400, 0, 400 + c, c))
    P["frame_b"] = crop("frame.webp", (400, H - c, 400 + c, H))
    P["frame_l"] = crop("frame.webp", (0, 400, c, 400 + c))
    P["frame_r"] = crop("frame.webp", (W - c, 400, W, 400 + c))
    for n, f in [("medal", "medal"), ("xbtn", "x-btn"), ("coin_minus", "coin-minus"), ("coin_plus", "coin-plus"),
                 ("coin_target", "coin-target"), ("sb_up", "sb-up"), ("sb_dn", "sb-dn"), ("hilite", "hilite")]:
        P[n] = load(f + ".webp")
    for n, f in [("title", "title"), ("btn_red", "btn-red"), ("btn_grey", "btn-grey"), ("btn_field", "btn-field"),
                 ("badge", "badge"), ("rtab_i", "rtab-i"), ("rtab_a", "rtab-a"), ("ptab_i", "ptab-i"), ("ptab_a", "ptab-a")]:
        for s in "lmr":
            P["%s_%s" % (n, s)] = load("%s-%s.webp" % (f, s))
    for s in "tmb":
        P["sb_thumb_" + s] = load("sb-thumb-%s.webp" % s)
    # pane border image: slice 34 of 132 (corners 34x34, edges are the 64px between)
    pane = load("pane.webp")
    S = 34
    w, h = pane.size
    P["pane_tl"] = pane.crop((0, 0, S, S))
    P["pane_tr"] = pane.crop((w - S, 0, w, S))
    P["pane_bl"] = pane.crop((0, h - S, S, h))
    P["pane_br"] = pane.crop((w - S, h - S, w, h))
    P["pane_t"] = pane.crop((S, 0, w - S, S))
    P["pane_b"] = pane.crop((S, h - S, w - S, h))
    P["pane_l"] = pane.crop((0, S, S, h - S))
    P["pane_r"] = pane.crop((w - S, S, w, h - S))
    P.update(glyphs())
    return P


def pot(n):
    p = 1
    while p < n:
        p *= 2
    return p


def pack(P):
    items = sorted(P.items(), key=lambda kv: (-kv[1].height, -kv[1].width, kv[0]))
    for width in (512, 1024):
        x = y = rowh = 0
        placed = {}
        ok = True
        for name, im in items:
            w, h = im.size
            if w + GUTTER > width:
                ok = False
                break
            if x + w + GUTTER > width:
                x, y, rowh = 0, y + rowh + GUTTER, 0
            placed[name] = (x, y, w, h)
            x += w + GUTTER
            rowh = max(rowh, h)
        if not ok:
            continue
        height = pot(y + rowh + GUTTER)
        if height <= 1024 or width == 1024:
            return width, height, placed
    raise SystemExit("cannot pack")


def write_tga(im, path):
    im = im.convert("RGBA")
    im.save(path, format="TGA", compression=None)


def main():
    os.makedirs(MEDIA, exist_ok=True)
    P = pieces()
    width, height, placed = pack(P)
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for name, (x, y, w, h) in placed.items():
        atlas.paste(P[name], (x, y))
    write_tga(atlas, os.path.join(MEDIA, "wow-atlas.tga"))
    # big textures: parchment page and dark slate (stretched; sizes are powers of two)
    parch = load("parch.webp").resize((1024, 1024), Image.LANCZOS)
    write_tga(parch, os.path.join(MEDIA, "wow-parchment.tga"))
    slate = load("tex.webp").resize((512, 256), Image.LANCZOS)
    write_tga(slate, os.path.join(MEDIA, "wow-slate.tga"))
    lines = ["-- GENERATED by tools/make_wow_textures.py from the previewer's generated WoW art. Do not edit.",
             "local _, NS = ...", "NS.atlases = NS.atlases or {}", "NS.atlases.wow = {",
             '  file = "Interface\\\\AddOns\\\\DarkMatter\\\\Media\\\\wow-atlas",', "  width = %d, height = %d," % (width, height),
             "  rects = {"]
    for name in sorted(placed):
        x, y, w, h = placed[name]
        lines.append("    %s = { %d, %d, %d, %d }," % (name, x, y, w, h))
    lines += ["  },", "}", ""]
    open(os.path.join(ADDON, "Atlas_WoW.lua"), "w").write("\n".join(lines))
    print("atlas %dx%d, %d pieces; parchment 1024x1024; slate 512x256" % (width, height, len(placed)))


if __name__ == "__main__":
    main()
