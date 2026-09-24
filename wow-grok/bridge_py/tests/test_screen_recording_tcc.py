"""Linux-safe tests for real capture probe + first-run sheet policy."""
from __future__ import annotations

import sys
import unittest
from unittest import mock


class TestProbeScreenRecording(unittest.TestCase):
    def test_non_darwin_returns_unsure(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "linux"):
            self.assertEqual(capture_mac.probe_screen_recording(), "unsure")

    def test_granted_when_cg_capture_succeeds(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_capture_1x1", return_value="granted"
        ) as cap, mock.patch.object(
            capture_mac, "_screencapture_1x1_probe"
        ) as fallback:
            self.assertEqual(capture_mac.probe_screen_recording(), "granted")
        cap.assert_called_once()
        fallback.assert_not_called()

    def test_denied_when_cg_capture_null(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_capture_1x1", return_value="denied"
        ), mock.patch.object(capture_mac, "_screencapture_1x1_probe") as fallback:
            self.assertEqual(capture_mac.probe_screen_recording(), "denied")
        fallback.assert_not_called()

    def test_window_list_alone_never_grants(self):
        """Regression: non-null CGWindowListCopyWindowInfo must not mean granted."""
        from bridge_py import capture_mac

        fake = mock.Mock()
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_window_list_copy", return_value=fake
        ), mock.patch.object(
            capture_mac, "_cg_capture_1x1", return_value="denied"
        ), mock.patch.object(
            capture_mac, "_screencapture_1x1_probe", return_value="denied"
        ):
            self.assertEqual(capture_mac.probe_screen_recording(), "denied")
        fake.release.assert_not_called()

    def test_fallback_screencapture_when_cg_unsure(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_capture_1x1", return_value="unsure"
        ), mock.patch.object(
            capture_mac, "_screencapture_1x1_probe", return_value="granted"
        ):
            self.assertEqual(capture_mac.probe_screen_recording(), "granted")

    def test_unsure_on_load_failure(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_capture_1x1", side_effect=OSError("no CG")
        ), mock.patch.object(
            capture_mac, "_screencapture_1x1_probe", return_value="unsure"
        ):
            self.assertEqual(capture_mac.probe_screen_recording(), "unsure")

    def test_request_uses_real_capture(self):
        from bridge_py import capture_mac

        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="denied"
        ) as probe:
            self.assertEqual(capture_mac.request_screen_recording(), "denied")
        probe.assert_called_once()

    def test_live_loop_exits_on_unsure(self):
        from bridge_py import capture_mac

        args = mock.Mock(cells=200, cell=4, max_rows=48, interval_ms=250, process_name="WowB")
        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="unsure"
        ):
            code = capture_mac.live_loop(args)
        self.assertEqual(code, capture_mac.PERMISSION_EXIT)

    def test_live_loop_exits_on_denied(self):
        from bridge_py import capture_mac

        args = mock.Mock(cells=200, cell=4, max_rows=48, interval_ms=250, process_name="WowB")
        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="denied"
        ):
            code = capture_mac.live_loop(args)
        self.assertEqual(code, capture_mac.PERMISSION_EXIT)


class TestCapturePermissionFailure(unittest.TestCase):
    def test_could_not_create_image_from_rect(self):
        from bridge_py import capture_mac

        self.assertTrue(
            capture_mac.is_capture_permission_failure(
                "could not create image from rect"
            )
        )
        self.assertTrue(
            capture_mac.is_capture_permission_failure(
                "RuntimeError: could not create image from rect"
            )
        )

    def test_empty_and_denied_strings(self):
        from bridge_py import capture_mac

        for msg in (
            "screencapture produced no image (grant Screen Recording to Terminal)",
            "Screen Recording blocked window list",
            "permission denied",
            "not authorized to capture the screen",
            "screencapture failed",
        ):
            self.assertTrue(
                capture_mac.is_capture_permission_failure(msg), msg
            )

    def test_unrelated_errors_not_permission(self):
        from bridge_py import capture_mac

        for msg in (
            "",
            "waiting for Forever window",
            "Pillow required",
            "timeout connecting to xAI",
            "no valid strip in image",
        ):
            self.assertFalse(
                capture_mac.is_capture_permission_failure(msg), msg
            )

    def test_live_loop_exits_when_all_strategies_permission_class(self):
        """All capture strategies permission-class → exit 42."""
        from bridge_py import capture_mac

        args = mock.Mock(
            cells=200, cell=4, max_rows=48, interval_ms=250, process_name="WowB"
        )
        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="granted"
        ), mock.patch.object(
            capture_mac, "backing_scale_factor", return_value=2.0
        ), mock.patch.object(
            capture_mac,
            "find_wow_window",
            return_value={
                "name": "WowB", "id": 42, "x": 0, "y": 0, "w": 800, "h": 600
            },
        ), mock.patch.object(
            capture_mac,
            "capture_strip_cg",
            side_effect=RuntimeError(
                "CGWindowListCreateImage returned null (Screen Recording / window capture)"
            ),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cg_crop",
            side_effect=RuntimeError(
                "CGWindowListCreateImage(full) returned null (Screen Recording / window capture)"
            ),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cli_crop",
            side_effect=RuntimeError(
                "screencapture -l produced no image (grant Screen Recording to WoWGrok)"
            ),
        ), mock.patch.object(
            capture_mac,
            "capture_region",
            side_effect=RuntimeError("could not create image from rect"),
        ), mock.patch.object(capture_mac, "emit"):
            code = capture_mac.live_loop(args)
        self.assertEqual(code, capture_mac.PERMISSION_EXIT)

    def test_live_loop_cli_rect_alone_soft_retries(self):
        """Single CLI-rect failure must not exit 42 when other strategies not exhausted."""
        from bridge_py import capture_mac

        args = mock.Mock(
            cells=200, cell=4, max_rows=48, interval_ms=250, process_name="WowB"
        )
        ticks = {"n": 0}

        def find_once(name):
            ticks["n"] += 1
            if ticks["n"] > 2:
                raise SystemExit(7)  # break soft-retry loop for test
            return {"name": "WowB", "id": 7, "x": 0, "y": 0, "w": 800, "h": 600}

        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="granted"
        ), mock.patch.object(
            capture_mac, "backing_scale_factor", return_value=1.0
        ), mock.patch.object(
            capture_mac, "find_wow_window", side_effect=find_once
        ), mock.patch.object(
            capture_mac,
            "capture_strip_cg",
            side_effect=RuntimeError("transient cg glitch"),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cg_crop",
            side_effect=RuntimeError("transient full glitch"),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cli_crop",
            side_effect=RuntimeError("transient -l glitch"),
        ), mock.patch.object(
            capture_mac,
            "capture_region",
            side_effect=RuntimeError("could not create image from rect"),
        ), mock.patch.object(capture_mac, "emit"), mock.patch.object(
            capture_mac.time, "sleep"
        ):
            with self.assertRaises(SystemExit) as cm:
                capture_mac.live_loop(args)
        self.assertEqual(cm.exception.code, 7)
        self.assertGreaterEqual(ticks["n"], 2)

    def test_live_loop_exits_on_produced_no_image(self):
        """All strategies empty/denied image → exit 42."""
        from bridge_py import capture_mac

        args = mock.Mock(
            cells=200, cell=4, max_rows=48, interval_ms=250, process_name="WowB"
        )
        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="granted"
        ), mock.patch.object(
            capture_mac, "backing_scale_factor", return_value=1.0
        ), mock.patch.object(
            capture_mac,
            "find_wow_window",
            return_value={
                "name": "WowB", "id": 7, "x": 0, "y": 0, "w": 800, "h": 600
            },
        ), mock.patch.object(
            capture_mac,
            "capture_strip_cg",
            side_effect=RuntimeError(
                "CGWindowListCreateImage produced no image (Screen Recording denied)"
            ),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cg_crop",
            side_effect=RuntimeError(
                "CGWindowListCreateImage produced no image (Screen Recording denied)"
            ),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cli_crop",
            side_effect=RuntimeError(
                "screencapture -l produced no image (grant Screen Recording)"
            ),
        ), mock.patch.object(
            capture_mac,
            "capture_region",
            side_effect=RuntimeError(
                "screencapture produced no image (grant Screen Recording)"
            ),
        ), mock.patch.object(capture_mac, "emit"):
            code = capture_mac.live_loop(args)
        self.assertEqual(code, capture_mac.PERMISSION_EXIT)


class TestPromptMacScreenRecording(unittest.TestCase):
    def test_granted_skips_dialog_and_requests_when_not_onboarded(self):
        from bridge_py import first_run

        cfg = {}
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="granted"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording", return_value="granted"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog"
        ) as dlg, mock.patch.object(
            first_run.cfgmod, "save_config"
        ) as save, mock.patch.object(
            first_run, "_append_bridge_log"
        ):
            first_run.prompt_mac_screen_recording(cfg)
        # First launch after wipe: always request even if probe looks granted
        req.assert_called_once()
        dlg.assert_not_called()
        self.assertTrue(cfg.get("screenRecordingOnboarded"))
        save.assert_called()

    def test_granted_onboarded_skips_request_and_dialog(self):
        from bridge_py import first_run

        cfg = {"screenRecordingOnboarded": True}
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="granted"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog"
        ) as dlg, mock.patch.object(
            first_run, "_append_bridge_log"
        ):
            first_run.prompt_mac_screen_recording(cfg)
        req.assert_not_called()
        dlg.assert_not_called()

    def test_onboarded_denied_skips_request_and_dialog(self):
        """Unsigned-upgrade case: do not re-request TCC every launch when onboarded."""
        from bridge_py import first_run

        cfg = {"screenRecordingOnboarded": True}
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="denied"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog"
        ) as dlg, mock.patch.object(
            first_run, "_append_bridge_log"
        ):
            first_run.prompt_mac_screen_recording(cfg)
        req.assert_not_called()
        dlg.assert_not_called()

    def test_denied_shows_dialog_and_requests(self):
        from bridge_py import first_run

        cfg = {}
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="denied"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording", return_value="denied"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog", return_value="continue"
        ) as dlg, mock.patch.object(
            first_run.cfgmod, "save_config"
        ), mock.patch.object(
            first_run, "_append_bridge_log"
        ):
            first_run.prompt_mac_screen_recording(cfg)
        req.assert_called_once()
        dlg.assert_called_once()
        self.assertTrue(cfg.get("screenRecordingOnboarded"))

    def test_unsure_shows_dialog(self):
        from bridge_py import first_run

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="unsure"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording", return_value="unsure"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog", return_value="continue"
        ) as dlg, mock.patch.object(
            first_run.cfgmod, "save_config"
        ), mock.patch.object(
            first_run, "_append_bridge_log"
        ):
            first_run.prompt_mac_screen_recording({})
        req.assert_called_once()
        dlg.assert_called_once()

    def test_probe_exception_shows_dialog(self):
        from bridge_py import first_run

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording",
            side_effect=RuntimeError("boom"),
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording", return_value="unsure"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog", return_value="continue"
        ) as dlg, mock.patch.object(
            first_run.cfgmod, "save_config"
        ), mock.patch.object(
            first_run, "_append_bridge_log"
        ):
            first_run.prompt_mac_screen_recording({})
        req.assert_called_once()
        dlg.assert_called_once()

    def test_quit_exits_zero(self):
        from bridge_py import first_run

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="denied"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording", return_value="denied"
        ), mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog", return_value="quit"
        ), mock.patch.object(
            first_run, "_append_bridge_log"
        ), self.assertRaises(SystemExit) as cm:
            first_run.prompt_mac_screen_recording({})
        self.assertEqual(cm.exception.code, 0)


class TestCocoaToTkAndClamp(unittest.TestCase):
    def test_ultrawide_primary_mapping(self):
        from bridge_py import tk_util

        # main NSScreen frame (0,0,3440,1440); visible inset menu bar ~38px
        main = (0.0, 0.0, 3440.0, 1440.0)
        vis = (0.0, 0.0, 3440.0, 1402.0)  # menu bar at top → smaller height from bottom
        # visTop = 0+1402=1402; mainTop=1440; tkY = 38
        x, y, w, h = tk_util.cocoa_visible_to_tk(main, vis)
        self.assertEqual((x, y, w, h), (0, 38, 3440, 1402))

    def test_laptop_right_of_ultrawide(self):
        from bridge_py import tk_util

        main = (0.0, 0.0, 3440.0, 1440.0)
        # laptop at cocoa x=3440, bottom-aligned, 1512x982 style
        vis = (3440.0, 0.0, 1512.0, 982.0)
        x, y, w, h = tk_util.cocoa_visible_to_tk(main, vis)
        self.assertEqual(x, 3440)
        self.assertEqual(w, 1512)
        self.assertEqual(h, 982)
        # mainTop 1440 - visTop 982 = 458
        self.assertEqual(y, 458)

    def test_clamp_keeps_24px_margin(self):
        from bridge_py import tk_util

        work = (0, 38, 3440, 1402)
        w, h, x, y = tk_util.clamp_window_in_work_area(460, 220, work, margin=24)
        self.assertGreaterEqual(x - work[0], 24)
        self.assertGreaterEqual(y - work[1], 24)
        self.assertGreaterEqual(work[0] + work[2] - (x + w), 24)
        self.assertGreaterEqual(work[1] + work[3] - (y + h), 24)
        # roughly centered horizontally
        self.assertAlmostEqual(x, work[0] + (work[2] - w) // 2, delta=1)

    def test_clamp_prevents_left_clip_on_narrow_guess(self):
        from bridge_py import tk_util

        # Bug class: window wider than remaining space near left edge
        work = (0, 22, 1280, 800)
        w, h, x, y = tk_util.clamp_window_in_work_area(2000, 900, work, margin=24)
        self.assertLessEqual(w, 1280 - 48)
        self.assertLessEqual(h, 800 - 48)
        self.assertGreaterEqual(x, 24)
        self.assertGreaterEqual(y, 22 + 24)



class TestCapturePermissionPaused(unittest.TestCase):
    def test_spawn_blocked_when_permission_paused(self):
        from bridge_py import bridge

        self.assertEqual(
            bridge.capture_spawn_blocked({"enabled": True, "permissionPaused": True}),
            "permissionPaused",
        )
        self.assertEqual(
            bridge.capture_spawn_blocked({"enabled": False, "permissionPaused": True}),
            "disabled",
        )
        self.assertIsNone(
            bridge.capture_spawn_blocked({"enabled": True, "permissionPaused": False})
        )
        self.assertIsNone(bridge.capture_spawn_blocked({"enabled": True}))

    def test_mark_persists_permission_paused(self):
        from bridge_py import bridge

        cfg = {"capture": {"enabled": True}}
        with mock.patch.object(bridge.cfgmod, "save_config") as save:
            bridge.mark_capture_permission_paused(cfg)
            bridge.mark_capture_permission_paused(cfg)  # idempotent
        self.assertTrue(cfg["capture"]["permissionPaused"])
        save.assert_called_once()

    def test_first_run_skips_probe_when_permission_paused(self):
        from bridge_py import first_run

        cfg = {"capture": {"permissionPaused": True}}
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording"
        ) as probe, mock.patch(
            "bridge_py.capture_mac.request_screen_recording"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog"
        ) as dlg, mock.patch.object(
            first_run, "_append_bridge_log"
        ) as log:
            first_run.prompt_mac_screen_recording(cfg)
        probe.assert_not_called()
        req.assert_not_called()
        dlg.assert_not_called()
        self.assertTrue(
            any("permissionPaused" in str(c) for c in log.call_args_list)
        )

    def test_first_run_does_not_clear_paused_on_granted_probe(self):
        """Regression: probe=granted must not clear permissionPaused (we skip probe)."""
        from bridge_py import first_run

        cfg = {
            "capture": {"permissionPaused": True},
            "screenRecordingOnboarded": True,
        }
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch.object(first_run, "_append_bridge_log"):
            first_run.prompt_mac_screen_recording(cfg)
        self.assertTrue(cfg["capture"]["permissionPaused"])



class TestCgFirstStripAndResumeSmoke(unittest.TestCase):
    def test_parse_wow_window_hit_includes_id(self):
        from bridge_py import capture_mac

        hit = capture_mac.parse_wow_window_hit("Wow\t0\t0\t3440\t1440\t12345")
        self.assertEqual(
            hit,
            {"name": "Wow", "x": 0, "y": 0, "w": 3440, "h": 1440, "id": 12345},
        )
        no_id = capture_mac.parse_wow_window_hit("Wow\t1\t2\t800\t600")
        self.assertEqual(
            no_id, {"name": "Wow", "x": 1, "y": 2, "w": 800, "h": 600}
        )
        self.assertIsNone(capture_mac.parse_wow_window_hit("short"))

    def test_live_loop_cg_success_ignores_cli_rect_failure(self):
        """CG strip OK → no exit 42 even if capture_region would fail."""
        from bridge_py import capture_mac
        from pathlib import Path
        import tempfile

        args = mock.Mock(
            cells=200, cell=4, max_rows=48, interval_ms=50, process_name="WowB"
        )
        calls = {"n": 0}

        def cg_ok(wid, x, y, w, h, dest):
            Path(dest).write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 300)

        def decode_fake(dest, cell, cells, max_rows, scale_hint):
            calls["n"] += 1
            # Prove CG path ran; SystemExit bypasses except Exception (not exit 42).
            raise SystemExit(0)

        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="granted"
        ), mock.patch.object(
            capture_mac, "backing_scale_factor", return_value=1.0
        ), mock.patch.object(
            capture_mac, "backing_scale_for_window", return_value=1.0
        ), mock.patch.object(
            capture_mac,
            "find_wow_window",
            return_value={
                "name": "Wow", "id": 99, "x": 0, "y": 0, "w": 3440, "h": 1440
            },
        ), mock.patch.object(
            capture_mac, "capture_strip_cg", side_effect=cg_ok
        ), mock.patch.object(
            capture_mac,
            "capture_region",
            side_effect=RuntimeError("could not create image from rect"),
        ), mock.patch.object(
            capture_mac, "_decode_captured", side_effect=decode_fake
        ), mock.patch.object(capture_mac, "emit"), mock.patch.object(
            capture_mac.time, "sleep"
        ):
            with self.assertRaises(SystemExit) as cm:
                capture_mac.live_loop(args)
        self.assertEqual(cm.exception.code, 0)
        self.assertGreaterEqual(calls["n"], 1)

    def test_live_loop_screencapture_l_success(self):
        """screencapture -l + crop succeeds when CG strip fails."""
        from bridge_py import capture_mac
        from pathlib import Path

        args = mock.Mock(
            cells=200, cell=4, max_rows=48, interval_ms=50, process_name="WowB"
        )
        calls = {"n": 0}

        def cli_l_ok(wid, w, h, dest):
            Path(dest).write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 300)

        def decode_fake(dest, cell, cells, max_rows, scale_hint):
            calls["n"] += 1
            raise SystemExit(0)

        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="granted"
        ), mock.patch.object(
            capture_mac, "backing_scale_factor", return_value=1.0
        ), mock.patch.object(
            capture_mac, "backing_scale_for_window", return_value=1.0
        ), mock.patch.object(
            capture_mac,
            "find_wow_window",
            return_value={
                "name": "Wow", "id": 7472, "x": 0, "y": 0, "w": 3440, "h": 1440
            },
        ), mock.patch.object(
            capture_mac,
            "capture_strip_cg",
            side_effect=RuntimeError("CGWindowListCreateImage returned null"),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cg_crop",
            side_effect=RuntimeError("CG full null"),
        ), mock.patch.object(
            capture_mac, "capture_window_cli_crop", side_effect=cli_l_ok
        ), mock.patch.object(
            capture_mac,
            "capture_region",
            side_effect=RuntimeError("could not create image from rect"),
        ), mock.patch.object(
            capture_mac, "_decode_captured", side_effect=decode_fake
        ), mock.patch.object(capture_mac, "emit"), mock.patch.object(
            capture_mac.time, "sleep"
        ):
            with self.assertRaises(SystemExit) as cm:
                capture_mac.live_loop(args)
        self.assertEqual(cm.exception.code, 0)
        self.assertGreaterEqual(calls["n"], 1)

    def test_live_loop_all_strategies_perm_exits_42(self):
        from bridge_py import capture_mac

        args = mock.Mock(
            cells=200, cell=4, max_rows=48, interval_ms=250, process_name="WowB"
        )
        with mock.patch.object(
            capture_mac, "probe_screen_recording", return_value="granted"
        ), mock.patch.object(
            capture_mac, "backing_scale_factor", return_value=1.0
        ), mock.patch.object(
            capture_mac,
            "find_wow_window",
            return_value={
                "name": "Wow", "id": 1, "x": 0, "y": 0, "w": 800, "h": 600
            },
        ), mock.patch.object(
            capture_mac,
            "capture_strip_cg",
            side_effect=RuntimeError("CGWindowListCreateImage returned null"),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cg_crop",
            side_effect=RuntimeError("CGWindowListCreateImage returned null"),
        ), mock.patch.object(
            capture_mac,
            "capture_window_cli_crop",
            side_effect=RuntimeError("screencapture -l produced no image"),
        ), mock.patch.object(
            capture_mac,
            "capture_region",
            side_effect=RuntimeError("could not create image from rect"),
        ), mock.patch.object(capture_mac, "emit"):
            code = capture_mac.live_loop(args)
        self.assertEqual(code, capture_mac.PERMISSION_EXIT)

    def test_resume_smoke_reason_no_window(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "find_wow_window", return_value=None
        ):
            ok, reason = capture_mac.resume_smoke("WowB")
        self.assertFalse(ok)
        self.assertIn("no WoW window", reason)

    def test_resume_smoke_ok_no_window_false_on_darwin(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "find_wow_window", return_value=None
        ):
            self.assertFalse(capture_mac.resume_smoke_ok("WowB"))

    def test_resume_smoke_ok_cg_strip_true(self):
        from bridge_py import capture_mac
        from pathlib import Path

        def cg_ok(wid, x, y, w, h, dest):
            Path(dest).write_bytes(b"\x89PNG" + b"x" * 400)
            # Pillow open needs a real image — mock open path via writing minimal valid PNG
            from PIL import Image

            Image.new("RGB", (64, 64), (1, 2, 3)).save(dest)

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac,
            "find_wow_window",
            return_value={
                "name": "Wow", "id": 5, "x": 0, "y": 0, "w": 800, "h": 600
            },
        ), mock.patch.object(capture_mac, "capture_strip_cg", side_effect=cg_ok):
            self.assertTrue(capture_mac.resume_smoke_ok("WowB"))

    def test_clear_capture_permission_paused(self):
        from bridge_py import bridge

        cfg = {"capture": {"permissionPaused": True, "enabled": True}}
        with mock.patch.object(bridge.cfgmod, "save_config") as save:
            self.assertTrue(bridge.clear_capture_permission_paused(cfg))
            self.assertFalse(bridge.clear_capture_permission_paused(cfg))
        self.assertFalse(cfg["capture"]["permissionPaused"])
        save.assert_called_once()



if __name__ == "__main__":
    unittest.main()


class TestResumeSmokeAndRepublish(unittest.TestCase):
    def test_resume_smoke_ok_non_darwin(self):
        from bridge_py import capture_mac
        with mock.patch.object(sys, "platform", "linux"):
            self.assertTrue(capture_mac.resume_smoke_ok())

    def test_find_handled_reply_via_transcript_shape(self):
        """Pure helper: assistant message with matching id is preferred."""
        transcripts = {
            "chats": {
                "c1": {
                    "messages": [
                        {"role": "user", "id": 2, "text": "hi"},
                        {"role": "assistant", "id": 2, "text": "hello back"},
                    ]
                }
            }
        }
        job = {"chat": "c1", "id": 2}
        msgs = transcripts["chats"][job["chat"]]["messages"]
        text = None
        for m in msgs:
            if m.get("role") == "assistant" and int(m.get("id") or 0) == job["id"]:
                text = m.get("text")
                break
        self.assertEqual(text, "hello back")

    def test_spawn_blocked_still_permission_paused(self):
        from bridge_py import bridge
        self.assertEqual(
            bridge.capture_spawn_blocked({"enabled": True, "permissionPaused": True}),
            "permissionPaused",
        )
