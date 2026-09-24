"""WoWGrok pixel-strip codec (matches Codec.lua + capture-mac.js / capture.ps1).

Frame: [0xC7 0x1A] [id hi,lo] [len hi,lo] [payload…] [fletcher s1,s2]
Checksum covers id..payload. Bytes pack MSB-first into 3-bit cells; each cell's
R/G/B channels are fully on or off (bit2=R, bit1=G, bit0=B).
"""
from __future__ import annotations

import io
import math
import random
from pathlib import Path
from typing import Any

from PIL import Image

MAGIC1, MAGIC2 = 0xC7, 0x1A
BITS = 3
MAX_PAYLOAD = 3200


def fletcher16(data: list[int] | bytes, from_idx: int, to_idx_inclusive: int) -> tuple[int, int]:
    """0-based inclusive range (Lua Fletcher16 from=3,to=6+len → here 2..5+len)."""
    s1 = s2 = 0
    for i in range(from_idx, to_idx_inclusive + 1):
        s1 = (s1 + data[i]) % 255
        s2 = (s2 + s1) % 255
    return s1, s2


def encode_cells(id_: int, payload: str | bytes) -> list[int]:
    """Encode id+payload into 3-bit cell values (0..7), same as Codec.lua Encode."""
    if isinstance(payload, str):
        raw = payload.encode("utf-8")
    else:
        raw = bytes(payload)
    length = len(raw)
    if length > MAX_PAYLOAD:
        raise ValueError(f"payload too long: {length} > {MAX_PAYLOAD}")
    data: list[int] = [
        MAGIC1,
        MAGIC2,
        (id_ // 256) % 256,
        id_ % 256,
        (length // 256) % 256,
        length % 256,
        *raw,
    ]
    s1, s2 = fletcher16(data, 2, 5 + length)
    data.append(s1)
    data.append(s2)

    base = 1 << BITS
    cells: list[int] = []
    acc = 0
    nbits = 0
    for b in data:
        acc = (acc << 8) | b
        nbits += 8
        while nbits >= BITS:
            shift = nbits - BITS
            cells.append((acc >> shift) % base)
            nbits = shift
            acc &= (1 << nbits) - 1 if nbits else 0
    if nbits > 0:
        cells.append((acc << (BITS - nbits)) % base)
    return cells


def cell_rgb(v: int) -> tuple[int, int, int]:
    r = ((v // 4) % 2) * 255
    g = ((v // 2) % 2) * 255
    b = (v % 2) * 255
    return r, g, b


def sample_cell(img: Image.Image, c: int, r: int, cell_px: int, scale: int = 1) -> int:
    """Sample center of cell (c,r); channel >= 128 counts as on."""
    side = cell_px * scale
    x = min(img.width - 1, max(0, c * side + side // 2))
    y = min(img.height - 1, max(0, r * side + side // 2))
    px = img.getpixel((x, y))
    if isinstance(px, int):
        R = G = B = px
    else:
        R, G, B = px[0], px[1], px[2]
    v = 0
    if R >= 128:
        v += 4
    if G >= 128:
        v += 2
    if B >= 128:
        v += 1
    return v


def decode_strip(
    img: Image.Image,
    *,
    cell: int = 4,
    cells: int = 200,
    max_rows: int = 48,
    scale: int = 1,
) -> dict[str, Any] | None:
    """Decode strip from a Pillow image. None = magic miss; dict may be error or {id,text}."""
    acc = 0
    nbits = 0
    out: list[int] = []
    needed = 6
    total = cells * max_rows
    for i in range(total):
        c = i % cells
        r = i // cells
        v = sample_cell(img, c, r, cell, scale)
        acc = (acc << 3) | v
        nbits += 3
        while nbits >= 8:
            out.append((acc >> (nbits - 8)) & 0xFF)
            nbits -= 8
            acc &= (1 << nbits) - 1 if nbits else 0
            if len(out) == 2:
                if out[0] != MAGIC1 or out[1] != MAGIC2:
                    return None
            if len(out) == 6:
                length = (out[4] * 256) + out[5]
                needed = 8 + length
                if needed > (total * 3) // 8:
                    return {"error": "length"}
            if len(out) >= needed:
                break
        if len(out) >= needed:
            break
    if len(out) < needed:
        return {"error": "truncated"}
    length = (out[4] * 256) + out[5]
    s1, s2 = fletcher16(out, 2, 5 + length)
    if out[6 + length] != s1 or out[7 + length] != s2:
        return {"error": "checksum"}
    text = bytes(out[6 : 6 + length]).decode("utf-8", errors="replace")
    return {"id": (out[2] * 256) + out[3], "text": text}


def infer_scale(
    img_width: int,
    cells: int = 200,
    cell: int = 4,
    scale_hint: float | int | None = None,
) -> int:
    logical_w = cells * cell
    scale = max(1, round(img_width / logical_w) if logical_w else 1)
    if scale_hint and scale_hint > 1 and img_width == logical_w * int(scale_hint):
        return int(scale_hint)
    return int(scale)


def render_strip_png(
    cells_vals: list[int],
    *,
    cell: int = 4,
    cells_per_row: int = 200,
    max_rows: int = 48,
    path: str | Path | None = None,
    jitter: float = 0,
    gamma: float = 1.0,
    seed: int | None = None,
) -> bytes:
    """Render cell values to an RGB PNG (bg 0x30). Optional jitter/gamma for robustness tests."""
    rng = random.Random(seed)
    w = cells_per_row * cell
    h = max_rows * cell
    img = Image.new("RGB", (w, h), (0x30, 0x30, 0x30))
    px = img.load()
    for i, v in enumerate(cells_vals):
        c = i % cells_per_row
        r = i // cells_per_row
        if r >= max_rows:
            break
        base = cell_rgb(v)
        for dy in range(cell):
            for dx in range(cell):
                rgb = []
                for ch in base:
                    val = float(ch)
                    if gamma != 1.0 and val > 0:
                        val = 255.0 * math.pow(val / 255.0, gamma)
                    if jitter:
                        val += rng.uniform(-jitter, jitter)
                    rgb.append(max(0, min(255, int(round(val)))))
                px[c * cell + dx, r * cell + dy] = (rgb[0], rgb[1], rgb[2])
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    data = buf.getvalue()
    if path is not None:
        Path(path).write_bytes(data)
    return data


def decode_png_file(
    path: str | Path,
    *,
    cell: int = 4,
    cells: int = 200,
    max_rows: int = 48,
    scale_hint: float | int | None = None,
) -> dict[str, Any]:
    img = Image.open(path).convert("RGB")
    scale = infer_scale(img.width, cells=cells, cell=cell, scale_hint=scale_hint)
    msg = decode_strip(img, cell=cell, cells=cells, max_rows=max_rows, scale=scale)
    if msg is None:
        return {"error": "no valid strip in image"}
    return msg
