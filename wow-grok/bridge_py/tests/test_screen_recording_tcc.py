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

    def test_live_loop_exits_immediately_on_create_image_from_rect(self):
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
            return_value={"name": "WowB", "x": 0, "y": 0, "w": 800, "h": 600},
        ), mock.patch.object(
            capture_mac,
            "capture_region",
            side_effect=RuntimeError("could not create image from rect"),
        ), mock.patch.object(capture_mac, "emit"):
            code = capture_mac.live_loop(args)
        self.assertEqual(code, capture_mac.PERMISSION_EXIT)

    def test_live_loop_exits_on_produced_no_image(self):
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
            return_value={"name": "WowB", "x": 0, "y": 0, "w": 800, "h": 600},
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


if __name__ == "__main__":
    unittest.main()
