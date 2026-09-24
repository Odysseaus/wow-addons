"""Unit tests: install main addon + a few reply slots into a tempdir (no tk)."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from bridge_py import install_addon, install_slots


class TestInstallAddon(unittest.TestCase):
    def test_addon_bundle_dir_resolves_repo(self):
        d = install_addon.addon_bundle_dir()
        self.assertTrue((d / "WoWGrok.toc").is_file())
        self.assertTrue((d / "WoWGrok.lua").is_file())

    def test_install_main_and_slots_tempdir(self):
        with tempfile.TemporaryDirectory() as tmp:
            addons = Path(tmp)
            # Minimal cfg: 3 slots, tiny wav trees for speed
            cfg = {
                "addonDir": str(addons),
                "slots": 3,
                "actMax": 2,
                "presenceMax": 2,
                "tocInterface": "16001",
            }

            main_n = install_addon.install_main_addon(addons)
            self.assertGreaterEqual(main_n, 3)
            dest = addons / "WoWGrok"
            self.assertTrue((dest / "WoWGrok.toc").is_file())
            self.assertTrue((dest / "WoWGrok.lua").is_file())
            self.assertTrue((dest / "Codec.lua").is_file())
            self.assertTrue((dest / "Inbox.lua").is_file())
            inbox_before = (dest / "Inbox.lua").read_text(encoding="utf-8")

            # Slots are top-level siblings (not nested under WoWGrok)
            made, kept = install_slots.install_slots(cfg)
            self.assertGreater(made, 0)
            self.assertEqual(kept, 0)
            for i in (1, 2, 3):
                slot = addons / f"WoWGrok_S00{i}"
                self.assertTrue(slot.is_dir(), msg=f"missing {slot}")
                self.assertTrue((slot / f"WoWGrok_S00{i}.toc").is_file())
                self.assertTrue((slot / "Inbox.lua").is_file())
                # Must be sibling of WoWGrok, not nested
                self.assertEqual(slot.parent, addons)
                self.assertNotEqual(slot.parent, dest)

            # Inbox.lua must not be overwritten when it already exists
            (dest / "Inbox.lua").write_text("-- bridge owned\n", encoding="utf-8")
            n2 = install_addon.install_main_addon(addons)
            self.assertEqual((dest / "Inbox.lua").read_text(encoding="utf-8"), "-- bridge owned\n")
            self.assertNotEqual(
                (dest / "Inbox.lua").read_text(encoding="utf-8"),
                inbox_before,
            )
            # Second slot pass is idempotent
            made2, kept2 = install_slots.install_slots(cfg)
            self.assertEqual(made2, 0)
            self.assertGreater(kept2, 0)

            # ensure_game_files (no GUI) on a fresh empty dir
            addons2 = addons / "fresh"
            addons2.mkdir()
            cfg2 = dict(cfg)
            cfg2["addonDir"] = str(addons2)
            main_w, made3, kept3 = install_addon.ensure_game_files(cfg2, gui=False)
            self.assertGreaterEqual(main_w, 3)
            self.assertGreater(made3, 0)
            self.assertEqual(kept3, 0)
            self.assertTrue((addons2 / "WoWGrok" / "WoWGrok.toc").is_file())
            self.assertTrue((addons2 / "WoWGrok_S001" / "Inbox.lua").is_file())

    def test_install_slots_raises_without_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = {
                "addonDir": tmp,
                "slots": 1,
                "actMax": 1,
                "presenceMax": 1,
            }
            with self.assertRaises(install_slots.InstallError):
                install_slots.install_slots(cfg)


if __name__ == "__main__":
    unittest.main()
