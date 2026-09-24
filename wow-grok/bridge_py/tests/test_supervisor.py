"""Supervisor must not use ``-m`` when frozen."""
from __future__ import annotations

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


if __name__ == "__main__":
    unittest.main()
