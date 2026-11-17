"""0.1.36: no osascript per capture tick; cached display scale; sticky strategy.

WindowServer crashed under the per-tick ``osascript`` spawns (window finder +
backingScaleFactor). These tests pin the replacement: in-process CoreGraphics
for both, a cached scale, and capture/decode output identical to before.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bridge_py import capture_mac, strip_codec


class _Stop(BaseException):
    """Escapes live_loop's ``except Exception`` to end a bounded run."""


def _spawn_guards():
    """Patch every subprocess entry point with a recording mock."""
    names = ("run", "Popen", "call", "check_call", "check_output")
    mocks = {n: mock.Mock(name=n, side_effect=OSError(f"spawned via {n}")) for n in names}
    patches = [mock.patch.object(capture_mac.subprocess, n, mocks[n]) for n in names]
    patches.append(mock.patch.object(capture_mac.os, "system", mock.Mock(name="system")))
    return mocks, patches


def _wow_row(owner="WowB", x=0.0, y=25.0, w=3440.0, h=1415.0, number=7472, layer=0):
    return {"owner": owner, "layer": layer, "bounds": (x, y, w, h), "number": number}


def _args():
    return mock.Mock(cells=200, cell=4, max_rows=48, interval_ms=250, process_name="WowB")


class ScaleCacheTests(unittest.TestCase):
    WIN = {"name": "WowB", "x": 0, "y": 25, "w": 3440, "h": 1415, "id": 7472}

    def test_scale_read_once_across_ticks(self):
        """1. Same display + size within 30 s: one CoreGraphics read, cached value."""
        with mock.patch.object(capture_mac, "_cg_display_for_window", return_value=1), \
                mock.patch.object(capture_mac, "_cg_display_scale", return_value=2.0) as rd:
            cache = capture_mac.ScaleCache()
            vals = [cache.get(self.WIN, now=100.0 + i * 0.25) for i in range(100)]
        self.assertEqual(set(vals), {2.0})
        self.assertEqual(rd.call_count, 1)
        self.assertEqual(cache.reads, 1)

    def test_scale_refresh_on_display_change_size_change_and_30s(self):
        """2. Re-read on display change, window size change, and the 30 s re-check;
        a failed re-read keeps the last good value."""
        disp = {"id": 1}
        with mock.patch.object(capture_mac, "_cg_display_for_window", side_effect=lambda w: disp["id"]), \
                mock.patch.object(capture_mac, "_cg_display_scale", side_effect=lambda d: {1: 2.0, 2: 1.0}.get(d)) as rd:
            cache = capture_mac.ScaleCache()
            self.assertEqual(cache.get(self.WIN, now=0.0), 2.0)
            self.assertEqual(cache.get(self.WIN, now=29.0), 2.0)
            self.assertEqual(rd.call_count, 1)
            disp["id"] = 2  # window dragged to a non-Retina display
            self.assertEqual(cache.get(self.WIN, now=29.5), 1.0)
            self.assertEqual(rd.call_count, 2)
            resized = dict(self.WIN, w=1720, h=720)
            cache.get(resized, now=30.0)
            self.assertEqual(rd.call_count, 3)
            cache.get(resized, now=59.9)
            self.assertEqual(rd.call_count, 3)
            cache.get(resized, now=60.1)  # 30 s re-check
            self.assertEqual(rd.call_count, 4)
            disp["id"] = 3  # unknown display → read fails → keep last good
            self.assertEqual(cache.get(resized, now=61.0), 1.0)


class DecodeUnchangedTests(unittest.TestCase):
    def test_decode_identical_for_any_scale_hint(self):
        """3. The scale hint never changes decoded chat for 1x and 2x strips."""
        cells = strip_codec.encode_cells(321, "hello from Forever — 0.1.36")
        with tempfile.TemporaryDirectory() as td:
            for px_cell in (4, 8):
                dest = Path(td) / f"strip{px_cell}.png"
                strip_codec.render_strip_png(cells, cell=px_cell, path=dest)
                results = [
                    capture_mac._decode_captured(dest, 4, 200, 48, hint)
                    for hint in (None, 1.0, 2.0, 3.0)
                ]
                for got in results:
                    self.assertEqual(got["msg"], {"id": 321, "text": "hello from Forever — 0.1.36"})
                    self.assertEqual(got["scale"], px_cell // 4)


class WindowFinderTests(unittest.TestCase):
    def setUp(self):
        capture_mac._reset_window_finder()

    def test_in_process_finder_matches_jxa_rules_without_spawning(self):
        """4. Same picks as the JXA finder (layer, wowgrok skip, names, size, |0)."""
        rows = [
            {"owner": "Dock", "layer": 20, "bounds": (0, 0, 3440, 1440), "number": 1},
            _wow_row(owner="WoWGrok", number=2),
            _wow_row(owner="Finder", number=3),
            _wow_row(owner="WowB", w=90.0, number=4),  # too small
            _wow_row(owner="WowB", layer=3, number=5),  # not normal layer
            {"owner": "WowB", "layer": None, "bounds": None, "number": 6},  # no bounds
            _wow_row(owner="World of Warcraft", x=-12.7, y=25.9, w=3440.6, h=1415.2, number=7472),
            _wow_row(owner="WowB", number=8),
        ]
        mocks, patches = _spawn_guards()
        with mock.patch.object(capture_mac, "_cg_window_rows", return_value=rows):
            for p in patches:
                p.start()
            try:
                hit = capture_mac.find_wow_window("WowB")
            finally:
                for p in patches:
                    p.stop()
        self.assertEqual(
            hit, {"name": "World of Warcraft", "x": -12, "y": 25, "w": 3440, "h": 1415, "id": 7472}
        )
        for m in mocks.values():
            m.assert_not_called()
        pick = capture_mac.pick_wow_window
        self.assertEqual(pick([_wow_row(owner="Wow")], "WowB")["name"], "Wow")
        self.assertEqual(pick([_wow_row(owner="WowClassic")], "WowB")["name"], "WowClassic")
        self.assertIsNone(pick([_wow_row(owner="Safari")], "WowB"))
        self.assertEqual(pick([_wow_row(owner=None, number=0)], "WowB")["id"], 0)  # JXA: '' matched
        with mock.patch.object(capture_mac, "_cg_window_rows", side_effect=RuntimeError(
            "Screen Recording blocked window list — enable WoWGrok.app")):
            with self.assertRaisesRegex(RuntimeError, "blocked window list"):
                capture_mac.find_wow_window("WowB")

    def test_jxa_fallback_runs_once_when_coregraphics_unavailable(self):
        """7. No in-process CoreGraphics: JXA once (info logged once), then reused."""
        hit = {"name": "WowB", "x": 0, "y": 25, "w": 3440, "h": 1415, "id": 7472}
        with mock.patch.object(capture_mac, "_cg_api", side_effect=capture_mac._CGUnavailable("no CG")), \
                mock.patch.object(capture_mac, "_find_wow_window_jxa", return_value=hit) as jxa, \
                mock.patch.object(capture_mac, "emit") as em:
            got = [capture_mac.find_wow_window("WowB") for _ in range(40)]
        self.assertEqual(got, [hit] * 40)
        self.assertEqual(jxa.call_count, 1)
        infos = [c.args[0]["info"] for c in em.call_args_list if "info" in c.args[0]]
        self.assertEqual(len(infos), 1)
        self.assertIn("one-time osascript", infos[0])


class LiveLoopTests(unittest.TestCase):
    def setUp(self):
        capture_mac._reset_window_finder()

    def _run(self, ticks, extra_patches, capture_fns):
        sleeps = {"n": 0}

        def fake_sleep(_s):
            sleeps["n"] += 1
            if sleeps["n"] >= ticks:
                raise _Stop()

        emitted = []
        mocks, patches = _spawn_guards()
        patches += [
            mock.patch.object(capture_mac, "probe_screen_recording", return_value="granted"),
            mock.patch.object(capture_mac.time, "sleep", side_effect=fake_sleep),
            mock.patch.object(capture_mac, "emit", side_effect=emitted.append),
            mock.patch.object(capture_mac, "_cg_window_rows", return_value=[_wow_row()]),
            mock.patch.object(capture_mac, "_cg_display_for_window", return_value=1),
            mock.patch.object(capture_mac, "_cg_main_display", return_value=1),
        ] + extra_patches
        patches += [mock.patch.object(capture_mac, n, f) for n, f in capture_fns.items()]
        for p in patches:
            p.start()
        try:
            with self.assertRaises(_Stop):
                capture_mac.live_loop(_args())
        finally:
            for p in patches:
                p.stop()
        return mocks, emitted

    def test_live_loop_50_ticks_no_subprocess_and_chat_decodes(self):
        """5. 50 ticks: zero subprocess spawns, attached + chat emitted, scale read once."""
        cells = strip_codec.encode_cells(77, "/grok where is the flight master")

        def cg_strip(wid, x, y, w, h, dest):
            self.assertEqual((wid, x, y, w, h), (7472, 0.0, 25.0, 800.0, 192.0))
            strip_codec.render_strip_png(cells, cell=8, path=dest)  # Retina 2x bitmap

        scale = mock.Mock(return_value=2.0)
        mocks, emitted = self._run(
            50,
            [mock.patch.object(capture_mac, "_cg_display_scale", scale)],
            {"capture_strip_cg": cg_strip},
        )
        for m in mocks.values():
            m.assert_not_called()
        texts = [e.get("info", "") for e in emitted]
        self.assertTrue(any(t.startswith("attached to 'WowB' id=7472") for t in texts), texts)
        self.assertTrue(any("via cg-strip" in t and "sample scale=2" in t for t in texts), texts)
        self.assertIn({"id": 77, "text": "/grok where is the flight master"}, emitted)
        self.assertEqual(scale.call_count, 2)  # startup info line + first tick, then cached

    def test_last_working_strategy_first_and_exit_42_kept(self):
        """6. CG failing + screencapture -l working: -l goes first after one success,
        so the failing strategies are not retried every tick; all-permission
        failures still exit 42 exactly as before."""
        cells = strip_codec.encode_cells(5, "hi")
        order = []

        def failing(name):
            def fn(*a, **k):
                order.append(name)
                raise RuntimeError("CGWindowListCreateImage returned null (window capture)")
            return fn

        def cli(wid, w, h, dest):
            order.append("screencapture-l")
            strip_codec.render_strip_png(cells, cell=4, path=dest)

        self._run(
            6,
            [mock.patch.object(capture_mac, "_cg_display_scale", return_value=1.0)],
            {
                "capture_strip_cg": failing("cg-strip"),
                "capture_window_cg_crop": failing("cg-full-crop"),
                "capture_window_cli_crop": cli,
            },
        )
        self.assertEqual(order[:3], ["cg-strip", "cg-full-crop", "screencapture-l"])
        self.assertEqual(order[3:], ["screencapture-l"] * 5)

        perm = RuntimeError("screencapture -l produced no image (grant Screen Recording to WoWGrok)")
        with mock.patch.object(capture_mac, "probe_screen_recording", return_value="granted"), \
                mock.patch.object(capture_mac, "_cg_window_rows", return_value=[_wow_row()]), \
                mock.patch.object(capture_mac, "_cg_display_scale", return_value=2.0), \
                mock.patch.object(capture_mac, "capture_strip_cg", side_effect=RuntimeError(
                    "CGWindowListCreateImage returned null (Screen Recording / window capture)")), \
                mock.patch.object(capture_mac, "capture_window_cg_crop", side_effect=RuntimeError(
                    "CGWindowListCreateImage(full) returned null (Screen Recording / window capture)")), \
                mock.patch.object(capture_mac, "capture_window_cli_crop", side_effect=perm), \
                mock.patch.object(capture_mac, "capture_region", side_effect=RuntimeError(
                    "could not create image from rect")), \
                mock.patch.object(capture_mac, "emit"):
            self.assertEqual(capture_mac.live_loop(_args()), capture_mac.PERMISSION_EXIT)


if __name__ == "__main__":
    unittest.main()
