"""Linux-safe tests for in-process Screen Recording probe + first-run sheet policy."""
from __future__ import annotations

import sys
import unittest
from unittest import mock


class TestProbeScreenRecording(unittest.TestCase):
    def test_non_darwin_returns_unsure(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "linux"):
            self.assertEqual(capture_mac.probe_screen_recording(), "unsure")

    def test_granted_when_cg_returns_array(self):
        from bridge_py import capture_mac

        fake = mock.Mock()
        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_window_list_copy", return_value=fake
        ):
            self.assertEqual(capture_mac.probe_screen_recording(), "granted")
        fake.release.assert_called_once()

    def test_denied_when_cg_returns_null(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_window_list_copy", return_value=None
        ):
            self.assertEqual(capture_mac.probe_screen_recording(), "denied")

    def test_unsure_on_load_failure(self):
        from bridge_py import capture_mac

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            capture_mac, "_cg_window_list_copy", side_effect=OSError("no CG")
        ):
            self.assertEqual(capture_mac.probe_screen_recording(), "unsure")

    def test_request_delegates_to_probe(self):
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


class TestPromptMacScreenRecording(unittest.TestCase):
    def test_granted_skips_dialog(self):
        from bridge_py import first_run

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="granted"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog"
        ) as dlg:
            first_run.prompt_mac_screen_recording()
        dlg.assert_not_called()
        req.assert_not_called()

    def test_denied_shows_dialog_and_requests(self):
        from bridge_py import first_run

        with mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch(
            "bridge_py.capture_mac.probe_screen_recording", return_value="denied"
        ), mock.patch(
            "bridge_py.capture_mac.request_screen_recording", return_value="denied"
        ) as req, mock.patch.object(
            first_run.tk_util, "show_screen_recording_dialog", return_value="continue"
        ) as dlg:
            first_run.prompt_mac_screen_recording()
        req.assert_called_once()
        dlg.assert_called_once()

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
        ) as dlg:
            first_run.prompt_mac_screen_recording()
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
        ) as dlg:
            first_run.prompt_mac_screen_recording()
        # Import succeeded so request is still available after probe error.
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
        ), self.assertRaises(SystemExit) as cm:
            first_run.prompt_mac_screen_recording()
        self.assertEqual(cm.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
