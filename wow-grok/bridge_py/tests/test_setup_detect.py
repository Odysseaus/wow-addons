"""Unit tests for AddOns path candidates (no real WoW required)."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bridge_py import setup_detect


def make_wow_tree(base: Path, flavors=("_classic_beta_", "_forever_", "_classic_era_")) -> Path:
    """``base/World of Warcraft/<flavor>/Interface/AddOns`` for each flavor."""
    root = base / "World of Warcraft"
    for f in flavors:
        (root / f / "Interface" / "AddOns").mkdir(parents=True)
    return root.resolve()


class TestCandidates(unittest.TestCase):
    def test_mac_candidates_include_all_flavors(self):
        paths = setup_detect.addon_candidates("darwin")
        joined = "\n".join(paths)
        self.assertIn(
            "/Applications/World of Warcraft/_forever_/Interface/AddOns",
            joined,
        )
        self.assertIn(
            "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns",
            joined,
        )
        self.assertTrue(any("_retail_" in p for p in paths))
        self.assertTrue(any("_classic_era_" in p for p in paths))
        self.assertTrue(any(p.endswith("_classic_/Interface/AddOns") or "/_classic_/Interface/AddOns" in p for p in paths))

    def test_mac_candidates_forever_before_classic_beta(self):
        paths = setup_detect.addon_candidates("darwin")
        forever = paths.index("/Applications/World of Warcraft/_forever_/Interface/AddOns")
        beta = paths.index("/Applications/World of Warcraft/_classic_beta_/Interface/AddOns")
        self.assertLess(forever, beta)

    def test_normalize_addons(self):
        # Pure path logic without needing dirs to exist on disk for coerce of AddOns-shaped path
        fake = Path("/Applications/World of Warcraft/_forever_/Interface/AddOns")
        with mock.patch.object(Path, "expanduser", return_value=fake):
            with mock.patch.object(Path, "resolve", return_value=fake):
                # name AddOns under Interface
                self.assertEqual(
                    setup_detect.normalize_addons_selection(fake),
                    fake,
                )

    def test_flavors_order(self):
        self.assertEqual(setup_detect.FLAVORS[0], "_forever_")
        self.assertLess(
            setup_detect.FLAVORS.index("_forever_"),
            setup_detect.FLAVORS.index("_classic_beta_"),
        )
        self.assertEqual(
            set(setup_detect.FLAVORS),
            {"_forever_", "_classic_beta_", "_retail_", "_classic_era_", "_classic_"},
        )


class TestFolderSelection(unittest.TestCase):
    def test_normalize_forever_flavor_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            got = setup_detect.normalize_addons_selection(root / "_forever_")
            self.assertEqual(got, root / "_forever_" / "Interface" / "AddOns")

    def test_normalize_forever_addons_folder_is_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            addons = root / "_forever_" / "Interface" / "AddOns"
            self.assertEqual(setup_detect.normalize_addons_selection(addons), addons)

    def test_normalize_folder_inside_addons(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            addons = root / "_forever_" / "Interface" / "AddOns"
            (addons / "WoWGrok").mkdir()
            self.assertEqual(setup_detect.normalize_addons_selection(addons / "WoWGrok"), addons)

    def test_normalize_interface_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            iface = root / "_forever_" / "Interface"
            self.assertEqual(setup_detect.normalize_addons_selection(iface), iface / "AddOns")

    def test_picking_wow_root_prefers_forever_not_classic_beta(self):
        """Regression: the WoW root used to coerce to _classic_beta_ (first in FLAVORS)."""
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            with mock.patch.object(setup_detect.sys, "platform", "darwin"):
                got = setup_detect.normalize_addons_selection(root)
            self.assertEqual(got, root / "_forever_" / "Interface" / "AddOns")

    def test_normalize_rejects_random_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(setup_detect.normalize_addons_selection(tmp))

    def test_flavor_clients_under(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            got = [p.name for p in setup_detect.flavor_clients_under(root)]
            self.assertEqual(got, ["_forever_", "_classic_beta_", "_classic_era_"])
            self.assertEqual(setup_detect.flavor_clients_under(Path(tmp) / "nope"), [])

    def test_flavor_helpers(self):
        p = Path("/Applications/World of Warcraft/_forever_/Interface/AddOns")
        self.assertEqual(setup_detect.flavor_of(p), "_forever_")
        self.assertEqual(setup_detect.flavor_of("/tmp/whatever"), "")
        self.assertEqual(
            setup_detect.client_root_for_addons(p),
            Path("/Applications/World of Warcraft/_forever_"),
        )
        self.assertEqual(setup_detect.flavor_label(p), "WoW Forever (_forever_)")
        self.assertEqual(
            setup_detect.flavor_label(str(p).replace("_forever_", "_classic_beta_")),
            "Classic beta (_classic_beta_)",
        )

    def test_sort_and_preferred(self):
        base = Path("/Applications/World of Warcraft")
        beta = base / "_classic_beta_" / "Interface" / "AddOns"
        forever = base / "_forever_" / "Interface" / "AddOns"
        era = base / "_classic_era_" / "Interface" / "AddOns"
        odd = Path("/Volumes/Games/AddOns")
        self.assertEqual(setup_detect.sort_by_flavor([beta, odd, era, forever]), [forever, beta, era, odd])
        self.assertEqual(setup_detect.preferred_addons_dir([beta, forever, era]), forever)
        self.assertEqual(setup_detect.preferred_addons_dir([beta, era]), beta)
        self.assertIsNone(setup_detect.preferred_addons_dir([]))

    def test_find_existing_addons_forever_first_and_deduped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            with mock.patch.object(setup_detect, "candidate_roots", return_value=[root, root]):
                found = setup_detect.find_existing_addons()
            self.assertEqual(
                [setup_detect.flavor_of(p) for p in found],
                ["_forever_", "_classic_beta_", "_classic_era_"],
            )


if __name__ == "__main__":
    unittest.main()
