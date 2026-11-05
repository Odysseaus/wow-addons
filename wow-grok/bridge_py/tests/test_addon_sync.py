"""Startup add-on sync (0.1.34): bundled addon replaces an older installed one."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from bridge_py import install_addon as IA


def _toc(v: str) -> str:
    return f"## Interface: 16001\n## Title: WoW Grok\n## Version: {v}\n"


class TestAddonSync(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.src = root / "bundle" / "WoWGrok"
        self.src.mkdir(parents=True)
        (self.src / "WoWGrok.toc").write_text(_toc("0.1.34"))
        (self.src / "WoWGrok.lua").write_text("-- new main")
        (self.src / "Codec.lua").write_text("-- new codec")
        (self.src / "Inbox.lua").write_text("-- bundled inbox")
        self.addons = root / "AddOns"
        self.dest = self.addons / "WoWGrok"
        self.dest.mkdir(parents=True)
        self.backups = root / "support"
        self.logs: list[str] = []

    def tearDown(self):
        self.tmp.cleanup()

    def _install(self, v: str):
        (self.dest / "WoWGrok.toc").write_text(_toc(v))
        (self.dest / "WoWGrok.lua").write_text("-- old main")
        (self.dest / "Codec.lua").write_text("-- old codec")
        (self.dest / "Inbox.lua").write_text("-- runtime inbox")
        for d in ("ack", "act", "ctl", "presence", "sig"):
            (self.dest / d).mkdir()
            (self.dest / d / "0001.wav").write_bytes(b"x")

    def _run(self):
        return IA.sync_addon_if_older(
            self.addons, self.backups, src=self.src, log=self.logs.append
        )

    def test_older_version_is_updated_with_backup(self):
        self._install("0.1.22")
        self.assertEqual(self._run(), "0.1.34")
        self.assertEqual((self.dest / "WoWGrok.lua").read_text(), "-- new main")
        self.assertEqual((self.dest / "Codec.lua").read_text(), "-- new codec")
        self.assertEqual(IA.toc_version(self.dest / "WoWGrok.toc"), (0, 1, 34))
        (bdir,) = list(self.backups.iterdir())
        self.assertEqual((bdir / "WoWGrok.lua").read_text(), "-- old main")
        self.assertEqual((bdir / "Inbox.lua").read_text(), "-- runtime inbox")
        self.assertIn("Add-on updated to 0.1.34", self.logs[-1])

    def test_inbox_and_runtime_dirs_untouched(self):
        self._install("0.1.9")
        self._run()
        self.assertEqual((self.dest / "Inbox.lua").read_text(), "-- runtime inbox")
        for d in ("ack", "act", "ctl", "presence", "sig"):
            self.assertEqual((self.dest / d / "0001.wav").read_bytes(), b"x")

    def test_numeric_compare_not_string(self):
        self._install("0.1.4")  # "0.1.4" > "0.1.34" as strings
        self.assertEqual(self._run(), "0.1.34")

    def test_same_or_newer_left_alone(self):
        for v in ("0.1.34", "0.2.0"):
            self._install(v) if not (self.dest / "ack").exists() else (
                self.dest / "WoWGrok.toc"
            ).write_text(_toc(v))
            self.assertIsNone(self._run())
            self.assertEqual((self.dest / "WoWGrok.lua").read_text(), "-- old main")
        self.assertFalse(self.backups.exists())

    def test_missing_installed_toc_installs(self):
        self.assertEqual(self._run(), "0.1.34")
        self.assertFalse((self.dest / "Inbox.lua").exists())

    def test_missing_addon_dir_only_logs(self):
        out = IA.sync_addon_if_older(
            Path(self.tmp.name) / "nope", self.backups, src=self.src, log=self.logs.append
        )
        self.assertIsNone(out)
        self.assertIn("addonDir missing", self.logs[-1])
        out = IA.sync_addon_if_older(None, self.backups, src=self.src, log=self.logs.append)
        self.assertIsNone(out)


if __name__ == "__main__":
    unittest.main()
