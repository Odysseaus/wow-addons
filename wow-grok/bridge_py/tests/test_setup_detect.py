"""Unit tests for AddOns path candidates (no real WoW required)."""
from __future__ import annotations

import unittest
from pathlib import Path
from unittest import mock

from bridge_py import setup_detect


class TestCandidates(unittest.TestCase):
    def test_mac_candidates_include_classic_beta(self):
        paths = setup_detect.addon_candidates("darwin")
        joined = "\n".join(paths)
        self.assertIn(
            "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns",
            joined,
        )
        self.assertTrue(any("_forever_" in p for p in paths))
        self.assertTrue(any("_retail_" in p for p in paths))
        self.assertTrue(any("_classic_era_" in p for p in paths))
        self.assertTrue(any(p.endswith("_classic_/Interface/AddOns") or "/_classic_/Interface/AddOns" in p for p in paths))

    def test_normalize_addons(self):
        # Pure path logic without needing dirs to exist on disk for coerce of AddOns-shaped path
        fake = Path("/Applications/World of Warcraft/_classic_beta_/Interface/AddOns")
        with mock.patch.object(Path, "expanduser", return_value=fake):
            with mock.patch.object(Path, "resolve", return_value=fake):
                # name AddOns under Interface
                self.assertEqual(
                    setup_detect.normalize_addons_selection(fake),
                    fake,
                )

    def test_flavors_order(self):
        self.assertEqual(setup_detect.FLAVORS[0], "_classic_beta_")


if __name__ == "__main__":
    unittest.main()
