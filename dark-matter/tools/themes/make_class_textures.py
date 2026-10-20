#!/usr/bin/env python3
"""Class themes for the addon (0.4.2): convert the previewer's generated class art + resolved theme variables.

Inputs (nothing is drawn here; every pixel comes from the previewer's approved generated art):
  addon-previewer/previews/dark-matter/art/<class>/{frame,over,orn-*,crest,base,tex,backdrop}.webp
  addon-previewer/previews/dark-matter/classart-raster.js   (crest/ornament/base geometry, shell tint)
  tools/themes/theme_vars.json                              (dump_theme_vars.py: resolved --dm-* values)
Outputs per class (power of two, 512 max, 32-bit TGA):
  Media/cls-<c>-frame.tga  frame edge bands (the frame interior is transparent, so only bands are kept)
  Media/cls-<c>-over.tga   overlay edge bands (drawn above the content; all overlay pixels lie within 120 css px)
  Media/cls-<c>-parts.tga  4 corner ornaments, crest, base plate, shell texture, backdrop
and DarkMatter/Theme_Classes.lua (theme data: colours, flat widget gradients, surface tints, art geometry).
"""
import json, os, re, sys
from PIL import Image, ImageStat

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.normpath(os.path.join(HERE, "..", "..", "DarkMatter"))
PREV = "/workspace/addon-previewer/previews/dark-matter"
ART = os.path.join(PREV, "art")
ORDER = ["warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"]
NAMES = {c: c.capitalize() for c in ORDER}
F = 0.75  # texture px per css px for the bands (source art is 2x css)
# art-space (css px of the 880x680 window) band -> texture rect in a 512x512 sheet
BANDS = [("tl", (0, 0, 440, 120), (0, 0, 330, 90)), ("tr", (440, 0, 440, 120), (0, 90, 330, 90)),
         ("bl", (0, 560, 440, 120), (0, 180, 330, 90)), ("br", (440, 560, 440, 120), (0, 270, 330, 90)),
         ("l", (0, 120, 120, 440), (330, 0, 90, 330)), ("r", (760, 120, 120, 440), (420, 0, 90, 330))]
PARTS = {"orn_tl": (0, 0, 128, 128), "orn_tr": (128, 0, 128, 128), "orn_bl": (0, 128, 128, 128), "orn_br": (128, 128, 128, 128),
         "crest": (256, 0, 128, 128), "base": (384, 0, 128, 128), "tex": (256, 128, 256, 128), "backdrop": (0, 256, 512, 256)}


def col(s):
    s = (s or "").strip()
    if s == "transparent":
        return (0, 0, 0, 0)
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})", s)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(ch * 2 for ch in h)
        return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, 1.0)
    m = re.fullmatch(r"rgba?\(([^)]*)\)", s)
    if m:
        p = [float(x) for x in m.group(1).split(",")]
        return (p[0] / 255, p[1] / 255, p[2] / 255, p[3] if len(p) > 3 else 1.0)
    return None


def split_top(s):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    out.append(cur.strip())
    return out


def grad(s):
    """First layer of a CSS background -> {dir, a (top/left), b (bottom/right)} or None."""
    s = (s or "").strip()
    c = col(s)
    if c:
        return {"dir": "VERTICAL", "a": c, "b": c}
    i = s.find("linear-gradient(")
    if i < 0:
        return None
    depth, j = 0, i + len("linear-gradient(") - 1
    for k in range(j, len(s)):
        if s[k] == "(":
            depth += 1
        elif s[k] == ")":
            depth -= 1
            if depth == 0:
                j = k
                break
    args = split_top(s[i + len("linear-gradient("):j])
    d = "VERTICAL"
    if args and args[0].endswith("deg"):
        d = "HORIZONTAL" if args[0].strip() in ("90deg", "270deg") else "VERTICAL"
        args = args[1:]
    stops = [col(re.sub(r"\s+[-\d.]+(px|%)?(\s+[-\d.]+(px|%)?)?$", "", a)) for a in args]
    stops = [x for x in stops if x]
    if not stops:
        return None
    return {"dir": d, "a": stops[0], "b": stops[-1]}


def avg(g):
    return tuple((g["a"][i] + g["b"][i]) / 2 for i in range(3))


def hexs(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v * 255))) for v in c[:3])


def lua_num(v):
    return ("%.3f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def lua(v, ind=""):
    if isinstance(v, dict):
        inner = ind + "  "
        parts = []
        for k in v:
            key = k if re.fullmatch(r"[A-Za-z_]\w*", k) else '["%s"]' % k
            parts.append(inner + key + " = " + lua(v[k], inner) + ",")
        return "{\n" + "\n".join(parts) + "\n" + ind + "}"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua(x, ind) for x in v) + " }"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\") + '"'
    if isinstance(v, bool):
        return "true" if v else "false"
    return lua_num(v)


def load_cls():
    js = open(os.path.join(PREV, "classart-raster.js")).read()
    i = js.index("var CLS=") + len("var CLS=")
    j = js.index("\n};", i) + 2
    return json.loads(js[i:j])


def square(im):
    s = max(im.size)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(im, ((s - im.width) // 2, (s - im.height) // 2))
    return out


def bands(src):
    im = Image.open(src).convert("RGBA")
    assert im.size == (1760, 1360), im.size
    sheet = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    for _, (x, y, w, h), (tx, ty, tw, th) in BANDS:
        piece = im.crop((x * 2, y * 2, (x + w) * 2, (y + h) * 2)).resize((tw, th), Image.LANCZOS)
        sheet.paste(piece, (tx, ty))
    return sheet


def lost_outside_bands(src):
    a = Image.open(src).getchannel("A")
    W, H = a.size
    inner = a.crop((240, 240, W - 240, H - 240))
    return sum(inner.histogram()[41:])


def parts(c):
    sheet = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    def put(key, im, keep_square=True):
        x, y, w, h = PARTS[key]
        im = square(im) if keep_square else im
        sheet.paste(im.resize((w, h), Image.LANCZOS), (x, y))
    for k in ("tl", "tr", "bl", "br"):
        put("orn_" + k, Image.open(os.path.join(ART, c, "orn-%s.webp" % k)).convert("RGBA"))
    put("crest", Image.open(os.path.join(ART, c, "crest.webp")).convert("RGBA"))
    put("base", Image.open(os.path.join(ART, c, "base.webp")).convert("RGBA"))
    tex = Image.open(os.path.join(ART, c, "tex.webp")).convert("RGBA")
    put("tex", tex, keep_square=False)
    put("backdrop", Image.open(os.path.join(ART, c, "backdrop.webp")).convert("RGBA"), keep_square=False)
    return sheet, ImageStat.Stat(tex.convert("RGB")).mean


def surface_tint(target, texmean):
    return [round(max(0.0, min(1.0, target[i] / max(texmean[i] / 255, 0.02))), 3) for i in range(3)]


def surf_flat(gr):
    if not gr:
        return None
    return {"flat": True, "dir": gr["dir"], "a": [round(x, 3) for x in gr["a"]], "b": [round(x, 3) for x in gr["b"]]}


def flat(g, border=None):
    if not g:
        return None
    o = {"dir": g["dir"], "a": [round(x, 3) for x in g["a"]], "b": [round(x, 3) for x in g["b"]]}
    b = col(border) if border else None
    if b and b[3] > 0:
        o["border"] = [round(x, 3) for x in b]
    return o


def theme(c, v, C, texmean):
    def g(k):
        return v.get(k, "")
    cl = {}
    for key, var in [("ink", "--dm-ink"), ("inkSoft", "--dm-ink-soft"), ("inkHead", "--dm-ink-head"), ("inkFaint", "--dm-ink-faint"),
                     ("gold", "--dm-btn-ink"), ("goldOn", "--dm-tab-ink-on"), ("greyBtn", "--dm-fbtn-grey-ink"), ("title", "--dm-title-ink"),
                     ("listInk", "--dm-list-ink"), ("listSoft", "--dm-list-soft"), ("listHead", "--dm-lh-ink"), ("liOn", "--dm-li-on-ink"),
                     ("good", "--dm-ink-good"), ("mid", "--dm-hl"), ("low", "--dm-ink-bad"), ("row", "--dm-li-ink"), ("status", "--dm-status-ink"),
                     ("lheadAll", "--dm-tab-ink-on"), ("lheadInk", "--dm-tab-ink"), ("badge", "--dm-badge-ink"), ("popBg", "--dm-select-bg"),
                     ("popBorder", "--dm-hl"), ("popInk", "--dm-select-ink"), ("barInk", "--dm-bar-ink"), ("barBorder", "--dm-bar-border")]:
        x = col(g(var))
        assert x, (c, var, g(var))
        cl[key] = hexs(x)
    cl["barFill"] = hexs(grad(g("--dm-bar-fill"))["a"])
    cl["barTrack"] = hexs(grad(g("--dm-bar-bg"))["a"])
    fl = {"btn_red": flat(grad(g("--dm-btn-bg")), g("--dm-btn-border")),
          "btn_grey": flat(grad(g("--dm-fbtn-grey-bg")), g("--dm-fbtn-grey-border")),
          "btn_field": flat(grad(g("--dm-status-bg")), g("--dm-status-border")),
          "rtab_i": flat(grad(g("--dm-tab-bg")), g("--dm-tab-border")),
          "rtab_a": flat(grad(g("--dm-tab-bg-on")), g("--dm-tab-border")),
          "ptab_i": flat(grad(g("--dm-pill-bg")), g("--dm-pill-border")),
          "ptab_a": flat(grad(g("--dm-pill-on-bg")), g("--dm-pill-border")),
          "badge": flat({"dir": "VERTICAL", "a": (0, 0, 0, 0), "b": (0, 0, 0, 0)}, g("--dm-badge-border")),
          "title": flat({"dir": "VERTICAL", "a": (0, 0, 0, 0), "b": (0, 0, 0, 0)}),
          "hilite": flat(grad(g("--dm-list-active"))),
          "pane": flat({"dir": "VERTICAL", "a": (0, 0, 0, 0), "b": (0, 0, 0, 0)}, g("--dm-list-border"))}
    for k in list(fl):
        assert fl[k], (c, k)
    d = C[c]
    # Surfaces follow the previewer: the shell shows the class texture (tinted like its rgba overlay) when the class
    # has one; rail, list and body are plain CSS colours/gradients there, so they are painted flat here too.
    if d.get("tex"):
        r, gg, b, a = [float(x) for x in d["tex"].split(",")]
        shell = {"tint": surface_tint(tuple((1 - a) * texmean[i] / 255 + a * [r, gg, b][i] / 255 for i in range(3)), texmean)}
    else:
        shell = surf_flat(grad(g("--dm-shell-bg")) or grad(g("--dm-rail-bg")))
    rail = surf_flat(grad(g("--dm-rail-bg"))) or shell
    lst = surf_flat(grad(g("--dm-list-bg"))) or shell
    page = surf_flat(grad(g("--dm-body-bg"))) or shell
    panel = grad(g("--dm-panel-bg"))
    crest = d["crest"]
    m = re.search(r"calc\(50% - (\d+)px\)", crest["left"])
    dx = -int(m.group(1)) if m else 0
    title_size = int(re.sub(r"px", "", d["vars"].get("--dm-title-size", "38px")))
    title_dy = int(re.sub(r"px", "", d["vars"].get("--dm-title-dy", "0px")))
    path = "Interface\\AddOns\\DarkMatter\\Media\\cls-" + c
    return {
        "id": c, "name": NAMES[c], "base": "wow", "title": "Dark Matter",
        "colors": cl,
        "flat": fl,
        "surface": {"file": path + "-parts", "rect": list(PARTS["tex"]), "size": 512,
                    "shell": shell, "rail": rail, "list": lst, "page": page},
        "panelWash": [round(x, 3) for x in avg(panel)] + [0.9] if panel else [1, 1, 1, 0.06],
        "classArt": {"frame": path + "-frame", "over": path + "-over", "parts": path + "-parts", "size": 512,
                     "bands": [[k, list(a), list(t)] for k, a, t in BANDS],
                     "rects": {k: list(r) for k, r in PARTS.items()},
                     "orn": d["orn"], "crest": [crest["size"], dx, int(crest["top"].replace("px", ""))],
                     "base": d["base"], "titleSize": title_size, "titleDy": title_dy,
                     "footer": {"pad": int(re.sub(r"px", "", (g("--dm-footer-pad") or "0 81px").split()[-1])),
                                "cols": [int(x.replace("px", "")) for x in g("--dm-footer-cols").split()], "gap": 10},
                     "close": [int(g("--dm-x-right").replace("px", "")), int(g("--dm-x-top").replace("px", ""))]},
    }


def write_tga(im, path):
    im.convert("RGBA").save(path, format="TGA", compression=None)


def main():
    vars_all = json.load(open(os.path.join(HERE, "theme_vars.json")))
    C = load_cls()
    media = os.path.join(ADDON, "Media")
    out = []
    for c in ORDER:
        fsrc, osrc = os.path.join(ART, c, "frame.webp"), os.path.join(ART, c, "over.webp")
        lost = lost_outside_bands(osrc)
        assert lost == 0, (c, "overlay pixels outside the 120px bands", lost)
        write_tga(bands(fsrc), os.path.join(media, "cls-%s-frame.tga" % c))
        write_tga(bands(osrc), os.path.join(media, "cls-%s-over.tga" % c))
        sheet, texmean = parts(c)
        write_tga(sheet, os.path.join(media, "cls-%s-parts.tga" % c))
        out.append(theme(c, vars_all[c], C, texmean))
        print(c, "ok (frame interior px outside bands: %d)" % lost_outside_bands(fsrc))
    lines = ["-- GENERATED by tools/themes/make_class_textures.py from the previewer's generated class art and its resolved",
             "-- theme variables (tools/themes/theme_vars.json). Do not edit. Nine class themes on top of the WoW theme's layout.",
             "local _, NS = ...", ""]
    for t in out:
        lines.append("NS.RegisterTheme(" + lua(t) + ")")
        lines.append("")
    open(os.path.join(ADDON, "Theme_Classes.lua"), "w").write("\n".join(lines))
    print("wrote Theme_Classes.lua with", len(out), "themes")


if __name__ == "__main__":
    main()
