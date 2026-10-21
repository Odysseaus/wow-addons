"""Sharp class-frame edges (0.4.3).

0.4.2 packed each 440x120 css edge band at 0.75 texels per css px and the client stretched it ~1.5x (blurry sides),
while the corner ornaments had ~1.4. Now every frame/overlay layer becomes:
  * 4 corners (120x120 css) at the source art's own density (2 texels per css px) in one 512x512 sheet; each corner's
    inner 8 css fade to transparent so it blends into the strip underneath;
  * 4 edge strips at the same density, made seamless and drawn with texcoord REPEAT along their length:
    top+bottom in one 512x512 file (repeat horizontally), left+right in another (repeat vertically).
The tile length is a whole number of the edge pattern's period (found by autocorrelation), cross-faded over 16 px
at the wrap. Nothing is drawn here: every pixel comes from the previewer's generated art (2x css, 1760x1360).
"""
from PIL import Image, ImageChops, ImageStat

D = 2          # source / texture pixels per css px
C = 120        # corner size, css
F = 8          # corner fade into the strip, css
B = 16         # wrap cross-fade, texture px
TILE = 512     # tile length in the texture, px (a whole number of periods <= TILE, never squeezed)
DEPTH = 240    # strip depth (120 css), px


def _diff(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean)


def period(strip):
    """Best repeat shift (px) along x of an RGBA strip."""
    w, h = strip.size
    small = strip.resize((w // 2, h // 4), Image.BILINEAR)
    sw = small.size[0]
    best, bs = None, 64
    for s in range(16, min(200, sw // 2)):
        d = _diff(small.crop((0, 0, sw - s, small.size[1])), small.crop((s, 0, sw, small.size[1])))
        if best is None or d < best - 1e-6:
            best, bs = d, s
    return bs * 2


def seamless(strip):
    """Seamless tile (TILE x DEPTH) from the start of a horizontal strip; returns (tile, css length it represents)."""
    s = period(strip)
    k = max(1, TILE // s)
    t = k * s
    if t > strip.size[0] - B:
        t = strip.size[0] - B
    seg = strip.crop((0, 0, t + B, strip.size[1]))
    tile = seg.crop((0, 0, t, strip.size[1]))
    head, wrap = seg.crop((0, 0, B, strip.size[1])), seg.crop((t, 0, t + B, strip.size[1]))
    # mask 0 at x=0 (continue from the tile's end: seg[t..]) rising to 255 at x=B (the tile's own start)
    mask = Image.linear_gradient("L").rotate(90, expand=True).resize((B, strip.size[1]))
    mask = mask.transpose(Image.FLIP_LEFT_RIGHT) if mask.getpixel((0, 0)) > 128 else mask
    tile.paste(Image.composite(head, wrap, mask), (0, 0))
    return tile.resize((TILE, strip.size[1]), Image.LANCZOS), t / D


def fade_corner(im, right, bottom, left, top):
    """Fade the inner edges of a corner piece (C*D square) to transparent over F css."""
    n, f = im.size[0], F * D
    ramp = Image.new("L", (n, n), 255)
    px = ramp.load()
    for y in range(n):
        for x in range(n):
            v = 1.0
            if right:
                v = min(v, (n - x) / f)
            if left:
                v = min(v, (x + 1) / f)
            if bottom:
                v = min(v, (n - y) / f)
            if top:
                v = min(v, (y + 1) / f)
            px[x, y] = int(255 * max(0.0, min(1.0, v)))
    a = ImageChops.multiply(im.getchannel("A"), ramp)
    im.putalpha(a)
    return im


def build(src):
    """-> (corners 512x512, tb 512x512, lr 512x512, lengths [top, bottom, left, right] in css)."""
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    assert (W, H) == (1760, 1360), im.size
    n = C * D
    corners = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    spec = {"tl": ((0, 0), (0, 0), (True, True, False, False)), "tr": ((W - n, 0), (256, 0), (False, True, True, False)),
            "bl": ((0, H - n), (0, 256), (True, False, False, True)), "br": ((W - n, H - n), (256, 256), (False, False, True, True))}
    for _, ((x, y), dst, fades) in spec.items():
        corners.paste(fade_corner(im.crop((x, y, x + n, y + n)), *fades), dst)
    o = (C - F) * D  # strips start under the corner fade so the first tile continues the corner exactly
    top = im.crop((o, 0, W - o, DEPTH))
    bot = im.crop((o, H - DEPTH, W - o, H))
    left = im.crop((0, o, DEPTH, H - o)).rotate(90, expand=True)     # vertical strips made horizontal (strip top -> left)
    right = im.crop((W - DEPTH, o, W, H - o)).rotate(90, expand=True)
    tt, lt = seamless(top)
    tb_, lb = seamless(bot)
    tl_, ll = seamless(left)
    tr_, lr_ = seamless(right)
    tb = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    tb.paste(tt, (0, 0))
    tb.paste(tb_, (0, 256))
    lr = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    lr.paste(tl_.rotate(-90, expand=True), (0, 0))
    lr.paste(tr_.rotate(-90, expand=True), (256, 0))
    return corners, tb, lr, [round(lt, 2), round(lb, 2), round(ll, 2), round(lr_, 2)]


def _runs(flags, gap):
    out, s, last = [], None, None
    for i, v in enumerate(flags):
        if v:
            if s is None:
                s = i
            elif last is not None and i - last > gap:
                out.append((s, last + 1))
                s = i
            last = i
    if s is not None:
        out.append((s, last + 1))
    return out


def build_over(src):
    """Overlay layer: its art is a few unique sprites (glows, vines, crystals), so it is NOT tiled.
    -> (corners 512x512 without fades, sprites 512x512, sprite list [[x, y, w, h] css, [tx, ty, tw, th] px]).
    Sprites are the overlay's edge content between the corners, cropped to their bounding boxes at source density
    (scaled down together only if they do not fit one 512x512 sheet)."""
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    n = C * D
    corners = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    for (x, y), dst in (((0, 0), (0, 0)), ((W - n, 0), (256, 0)), ((0, H - n), (0, 256)), ((W - n, H - n), (256, 256))):
        corners.paste(im.crop((x, y, x + n, y + n)), dst)
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    boxes = []
    for x0, y0, x1, y1, horiz in ((n, 0, W - n, DEPTH, True), (n, H - DEPTH, W - n, H, True),
                                  (0, n, DEPTH, H - n, False), (W - DEPTH, n, W, H - n, False)):
        band = a.crop((x0, y0, x1, y1))
        bw, bh = band.size
        if horiz:
            flags = [band.crop((i, 0, i + 1, bh)).getbbox() is not None for i in range(bw)]
        else:
            flags = [band.crop((0, i, bw, i + 1)).getbbox() is not None for i in range(bh)]
        for s, e in _runs(flags, 16):
            sub = (s, 0, e, bh) if horiz else (0, s, bw, e)
            bb = band.crop(sub).getbbox()
            if not bb:
                continue
            gx0, gy0 = x0 + sub[0] + bb[0], y0 + sub[1] + bb[1]
            gx1, gy1 = x0 + sub[0] + bb[2], y0 + sub[1] + bb[3]
            gx0, gy0, gx1, gy1 = gx0 - gx0 % 2, gy0 - gy0 % 2, gx1 + gx1 % 2, gy1 + gy1 % 2   # whole css px
            boxes.append((gx0, gy0, gx1, gy1))
    scale = 1.0
    while True:
        place, cx, cy, rowh, ok = [], 0, 0, 0, True
        for b in sorted(boxes, key=lambda b: -(b[3] - b[1])):
            w, h = max(1, round((b[2] - b[0]) * scale)), max(1, round((b[3] - b[1]) * scale))
            if w > 512 or h > 512:
                ok = False
                break
            if cx + w > 512:
                cx, cy, rowh = 0, cy + rowh + 2, 0
            if cy + h > 512:
                ok = False
                break
            place.append((b, (cx, cy, w, h)))
            cx, rowh = cx + w + 2, max(rowh, h)
        if ok:
            break
        scale *= 0.9
    sheet = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    sprites = []
    for b, (tx, ty, tw, th) in place:
        sheet.paste(im.crop(b).resize((tw, th), Image.LANCZOS), (tx, ty))
        sprites.append([[b[0] // D, b[1] // D, (b[2] - b[0]) // D, (b[3] - b[1]) // D], [tx, ty, tw, th]])
    used = max([p[1][1] + p[1][3] for p in place] + [1])
    h2 = 64
    while h2 < used:
        h2 *= 2
    return corners, sheet.crop((0, 0, 512, h2)), sprites, round(scale, 3)  # height trimmed to a power of two
