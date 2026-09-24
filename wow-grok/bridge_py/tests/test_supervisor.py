"""Supervisor must not use ``-m`` when frozen; stop uses killpg on Unix."""
from __future__ import annotations

import signal
import subprocess
import sys
import unittest
from unittest import mock

from bridge_py import supervisor


class TestBridgeCommand(unittest.TestCase):
    def test_dev_uses_module(self):
        # Ensure non-frozen path (attribute may be absent).
        frozen_was = getattr(sys, "frozen", None)
        try:
            if hasattr(sys, "frozen"):
                delattr(sys, "frozen")
            cmd = supervisor._bridge_command(["--wow", "/tmp"])
        finally:
            if frozen_was is not None:
                sys.frozen = frozen_was
            elif hasattr(sys, "frozen"):
                delattr(sys, "frozen")
        self.assertEqual(cmd[0], sys.executable)
        self.assertEqual(cmd[1], "-m")
        self.assertEqual(cmd[2], "bridge_py.bridge")
        self.assertIn("--wow", cmd)

    def test_frozen_uses_no_supervisor_flag(self):
        with mock.patch.object(sys, "frozen", True, create=True), mock.patch.object(
            sys, "executable", "/Apps/WoWGrok.app/Contents/MacOS/WoWGrok"
        ):
            cmd = supervisor._bridge_command(["--once"])
        self.assertEqual(
            cmd,
            [
                "/Apps/WoWGrok.app/Contents/MacOS/WoWGrok",
                "--no-supervisor",
                "--once",
            ],
        )


class TestStopChild(unittest.TestCase):
    def test_stop_uses_killpg_when_child_alive(self):
        """Unix stop path: SIGTERM the process group, then wait."""
        if sys.platform == "win32":
            self.skipTest("killpg path is Unix-only")
        fake = mock.Mock(spec=subprocess.Popen)
        fake.pid = 4242
        fake.poll.return_value = None  # still running
        fake.wait.return_value = 0
        with mock.patch.object(supervisor.os, "killpg") as killpg:
            supervisor._stop_child(fake)
        killpg.assert_called_once_with(4242, signal.SIGTERM)
        fake.wait.assert_called_once_with(timeout=5)
        fake.terminate.assert_not_called()
        fake.kill.assert_not_called()

    def test_stop_killpg_timeout_then_sigkill(self):
        if sys.platform == "win32":
            self.skipTest("killpg path is Unix-only")
        fake = mock.Mock(spec=subprocess.Popen)
        fake.pid = 4242
        fake.poll.return_value = None
        fake.wait.side_effect = [subprocess.TimeoutExpired(cmd="x", timeout=5), 0]
        with mock.patch.object(supervisor.os, "killpg") as killpg:
            supervisor._stop_child(fake)
        self.assertEqual(
            killpg.call_args_list,
            [
                mock.call(4242, signal.SIGTERM),
                mock.call(4242, signal.SIGKILL),
            ],
        )

    def test_stop_falls_back_to_terminate_if_killpg_fails(self):
        if sys.platform == "win32":
            self.skipTest("killpg path is Unix-only")
        fake = mock.Mock(spec=subprocess.Popen)
        fake.pid = 4242
        fake.poll.return_value = None
        fake.wait.return_value = 0
        with mock.patch.object(
            supervisor.os, "killpg", side_effect=ProcessLookupError
        ):
            supervisor._stop_child(fake)
        fake.terminate.assert_called_once()
        fake.wait.assert_called_once_with(timeout=5)

    def test_run_supervised_passes_start_new_session_on_unix(self):
        if sys.platform == "win32":
            self.skipTest("start_new_session is Unix-only")
        fake_proc = mock.Mock(spec=subprocess.Popen)
        fake_proc.wait.return_value = 0
        with mock.patch.object(
            supervisor.subprocess, "Popen", return_value=fake_proc
        ) as popen, mock.patch.object(supervisor.signal, "signal"):
            code = supervisor.run_supervised(["--once"])
        self.assertEqual(code, 0)
        self.assertTrue(popen.call_args.kwargs.get("start_new_session"))


if __name__ == "__main__":
    unittest.main()
