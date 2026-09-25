"""runtime_dir for frozen macOS .app."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bridge_py import config as cfgmod


class TestRuntimeDir(unittest.TestCase):
    def test_default_search_config_is_web_only(self):
        defaults = cfgmod.default_config()
        self.assertTrue(defaults["webSearch"])
        self.assertFalse(defaults["xSearch"])

    def test_frozen_macos_app_uses_application_support(self):
        fake_exe = Path("/Applications/WoWGrok.app/Contents/MacOS/WoWGrok")
        with mock.patch.object(sys, "frozen", True, create=True), mock.patch.object(
            sys, "executable", str(fake_exe)
        ), mock.patch.object(sys, "platform", "darwin"), tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            with mock.patch.object(Path, "home", return_value=home):
                d = cfgmod.runtime_dir()
            self.assertEqual(d, home / "Library" / "Application Support" / "WoWGrok")
            self.assertTrue(d.is_dir())


if __name__ == "__main__":
    unittest.main()
