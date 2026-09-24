"""Unit tests for strip encode/decode (synthetic PNGs; no live capture)."""
from __future__ import annotations

import io
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from bridge_py import strip_codec as C
from bridge_py.capture_mac import main as mac_main


class TestEncodeDecode(unittest.TestCase):
    def test_roundtrip_simple(self):
        payload = "sess\x1fchat\x1f7\x1f.\x1f\x1fname\x1fhello"
        cells = C.encode_cells(7, payload)
        png = C.render_strip_png(cells, seed=1)
        img = Image.open(io.BytesIO(png)).convert("RGB")
        msg = C.decode_strip(img)
        self.assertEqual(msg, {"id": 7, "text": payload})

    def test_roundtrip_unicode(self):
        payload = 'héllo wörld ✓ — "quotes" & \\backslash\\'
        cells = C.encode_cells(42, payload)
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "s.png"
            C.render_strip_png(cells, path=path, seed=2)
            msg = C.decode_png_file(path)
            self.assertEqual(msg["id"], 42)
            self.assertEqual(msg["text"], payload)

    def test_jitter_gamma(self):
        payload = "sess\x1f\x1f9\x1f\x1f\x1f\x1f" + ("ab " * 80)
        cells = C.encode_cells(9, payload)
        png = C.render_strip_png(cells, jitter=40, gamma=0.7, seed=99)
        img = Image.open(io.BytesIO(png)).convert("RGB")
        msg = C.decode_strip(img)
        self.assertIsInstance(msg, dict)
        self.assertEqual(msg.get("id"), 9)
        self.assertEqual(msg.get("text"), payload)

    def test_retina_scale_2(self):
        payload = "x"
        cells = C.encode_cells(1, payload)
        # Render at logical size then nearest-neighbor upscale 2×
        png = C.render_strip_png(cells, cell=4, cells_per_row=200, max_rows=48, seed=3)
        img = Image.open(io.BytesIO(png)).convert("RGB")
        big = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
        scale = C.infer_scale(big.width, scale_hint=2)
        self.assertEqual(scale, 2)
        msg = C.decode_strip(big, scale=2)
        self.assertEqual(msg, {"id": 1, "text": payload})

    def test_magic_mismatch_returns_none(self):
        img = Image.new("RGB", (800, 192), (0x30, 0x30, 0x30))
        self.assertIsNone(C.decode_strip(img))

    def test_checksum_error(self):
        payload = "hi"
        cells = C.encode_cells(3, payload)
        # Flip last cell to corrupt trailing bits often enough to break checksum
        if cells:
            cells[-1] = (cells[-1] + 1) % 8
            if len(cells) > 1:
                cells[-2] = (cells[-2] + 3) % 8
        png = C.render_strip_png(cells, seed=4)
        img = Image.open(io.BytesIO(png)).convert("RGB")
        msg = C.decode_strip(img)
        # May be None (magic) or checksum/truncated depending on corruption
        self.assertTrue(msg is None or msg.get("error") in ("checksum", "truncated", "length"))

    def test_cell_rgb_bits(self):
        self.assertEqual(C.cell_rgb(0), (0, 0, 0))
        self.assertEqual(C.cell_rgb(7), (255, 255, 255))
        self.assertEqual(C.cell_rgb(4), (255, 0, 0))
        self.assertEqual(C.cell_rgb(2), (0, 255, 0))
        self.assertEqual(C.cell_rgb(1), (0, 0, 255))

    def test_cli_test_image(self):
        payload = "cli-ok"
        cells = C.encode_cells(100, payload)
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "t.png"
            C.render_strip_png(cells, path=path, seed=5)
            # Capture stdout
            import io as _io
            import contextlib

            buf = _io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = mac_main(["--test-image", str(path), "--cell", "4", "--cells", "200", "--max-rows", "48"])
            self.assertEqual(code, 0)
            line = buf.getvalue().strip().splitlines()[-1]
            import json

            ev = json.loads(line)
            self.assertEqual(ev["id"], 100)
            self.assertEqual(ev["text"], payload)


if __name__ == "__main__":
    unittest.main()
