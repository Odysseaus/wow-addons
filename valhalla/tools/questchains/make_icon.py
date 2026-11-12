# Valhalla 1.1.0: Media/Textures/ValhallaChain.tga, the quest log's chain button (two interlocked links,
# gold over a dark outline, drawn here; 64x64, 32-bit uncompressed TGA like ValhallaPinOn.tga). Box only.
import struct, sys
from PIL import Image, ImageDraw
S = 512
def links(width, inset, col):
    a = Image.new('RGBA', (S, S), (0, 0, 0, 0)); b = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    for im, box in ((a, (40, 160, 316, 352)), (b, (196, 160, 472, 352))):
        d = ImageDraw.Draw(im)
        bx = (box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset)
        d.rounded_rectangle(bx, radius=(bx[3] - bx[1]) // 2, outline=col, width=width)
    return a, b
def make(out):
    oa, ob = links(84, 0, (24, 14, 4, 255))           # the outline
    fa, fb = links(44, 20, (255, 214, 64, 255))      # the gold
    ha, hb = links(10, 30, (255, 244, 190, 255))     # a light line along the top of the gold
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    for layer in (ob, fb, hb): img = Image.alpha_composite(img, layer)
    # link a over link b on its right-hand crossing only (interlocked)
    top = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    for layer in (oa, fa, ha): top = Image.alpha_composite(top, layer)
    left = top.crop((0, 0, 256, S)); img.alpha_composite(left, (0, 0))
    right = top.crop((256, 256, S, S)); img.alpha_composite(right, (256, 256))
    img = img.rotate(-40, resample=Image.BICUBIC)
    bb = img.getbbox(); img = img.crop(bb)
    s = max(img.size) + 16
    sq = Image.new('RGBA', (s, s), (0, 0, 0, 0)); sq.paste(img, ((s - img.size[0]) // 2, (s - img.size[1]) // 2))
    sq = sq.resize((64, 64), Image.LANCZOS)
    # TGA: type 2, 32 bpp, origin bottom-left (descriptor 8), BGRA rows bottom to top
    hdr = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, 64, 64, 32, 8)
    px = bytearray()
    for y in range(63, -1, -1):
        for x in range(64):
            r, g, b, a = sq.getpixel((x, y)); px += bytes((b, g, r, a))
    open(out, 'wb').write(hdr + bytes(px))
    sq.save(out.replace('.tga', '-preview.png'))
make(sys.argv[1] if len(sys.argv) > 1 else 'ValhallaChain.tga')
