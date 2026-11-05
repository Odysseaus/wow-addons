"""Move to Applications (0.1.35): path detection, backup naming, move flow."""
from __future__ import annotations

import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

from bridge_py import move_to_apps as M

HOME = Path("/Users/bob")


def _never_ro(_p):
    return False


class TestNeedsMove(unittest.TestCase):
    def t(self, p, **kw):
        kw.setdefault("is_ro", _never_ro)
        return M.needs_move(p, home=HOME, **kw)

    def test_volumes(self):
        self.assertTrue(self.t("/Volumes/WoWGrok 1/WoWGrok.app"))

    def test_translocation(self):
        self.assertTrue(self.t("/private/var/folders/x/T/AppTranslocation/ABC/d/WoWGrok.app"))

    def test_applications(self):
        self.assertFalse(self.t("/Applications/WoWGrok.app"))

    def test_user_applications(self):
        self.assertFalse(self.t("/Users/bob/Applications/WoWGrok.app"))

    def test_other_ro_mount_or_image(self):
        self.assertTrue(self.t("/tmp/x/WoWGrok.app", is_ro=lambda p: True))
        self.assertTrue(self.t("/mnt/img/WoWGrok.app", image_mounts=lambda: ["/mnt/img"]))
        self.assertFalse(self.t("/Users/bob/Downloads/WoWGrok.app"))
        self.assertFalse(self.t(None))

    def test_bundle_path(self):
        self.assertEqual(
            M.bundle_path("/Volumes/W/WoWGrok.app/Contents/MacOS/WoWGrok"),
            Path("/Volumes/W/WoWGrok.app"),
        )
        self.assertEqual(M.volume_root(Path("/Volumes/WoWGrok 1/WoWGrok.app")), Path("/Volumes/WoWGrok 1"))

    def test_hdiutil_mounts_parse(self):
        out = "image-path : /x.dmg\n/dev/disk4s1\tApple_HFS\t/Volumes/WoWGrok 1\n"
        run = lambda *a, **k: subprocess.CompletedProcess(a, 0, out, "")
        self.assertEqual(M._hdiutil_mounts(run), ["/Volumes/WoWGrok 1"])


def _make_app(path: Path, version: str):
    (path / "Contents" / "MacOS").mkdir(parents=True)
    with open(path / "Contents" / "Info.plist", "wb") as f:
        plistlib.dump({"CFBundleShortVersionString": version}, f)
    (path / "Contents" / "MacOS" / "WoWGrok").write_text(version)


class TestBackupName(unittest.TestCase):
    def test_free_then_timestamped(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            self.assertEqual(M.backup_name(d, "0.1.33"), d / "WoWGrok-0.1.33.app")
            (d / "WoWGrok-0.1.33.app").mkdir()
            n = M.backup_name(d, "0.1.33", now=0)
            self.assertRegex(n.name, r"^WoWGrok-0\.1\.33-\d{8}-\d{6}\.app$")
            n.mkdir()
            self.assertTrue(M.backup_name(d, "0.1.33", now=0).name.endswith("-2.app"))


class FakeRun:
    """Stub subprocess.run: performs ditto as a copy, records calls."""

    def __init__(self, codesign_rc=0, pgrep_out=""):
        self.calls = []
        self.codesign_rc = codesign_rc
        self.pgrep_out = pgrep_out

    def __call__(self, cmd, **kw):
        import shutil

        self.calls.append(cmd)
        if cmd[0].endswith("ditto"):
            shutil.copytree(cmd[1], cmd[2])
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[0].endswith("codesign"):
            return subprocess.CompletedProcess(cmd, self.codesign_rc, "", "bad sig")
        if cmd[0].endswith("pgrep"):
            return subprocess.CompletedProcess(cmd, 0, self.pgrep_out, "")
        return subprocess.CompletedProcess(cmd, 0, "", "")


class TestMoveFlow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        r = Path(self.tmp.name)
        self.home = r / "home"
        self.apps = r / "Applications"
        self.src = r / "Volumes" / "WoWGrok 1" / "WoWGrok.app"
        _make_app(self.src, "0.1.35")

    def tearDown(self):
        self.tmp.cleanup()

    def test_moves_old_copies_new_verifies(self):
        _make_app(self.apps / "WoWGrok.app", "0.1.33")
        run = FakeRun(pgrep_out="4242\n")
        killed = []

        def kill(pid, sig):
            killed.append((pid, sig))
            if sig == 0:
                raise OSError  # already gone

        dest, fb = M.move_to_applications(
            self.src, home=self.home, dest_dir=self.apps, run=run, kill=kill,
            sleep=lambda s: None, log=lambda m: None,
        )
        self.assertFalse(fb)
        self.assertEqual(M.bundle_version(dest), "0.1.35")
        old = self.home / "Documents" / "WoWGrok-Mac" / "WoWGrok-0.1.33.app"
        self.assertEqual(M.bundle_version(old), "0.1.33")
        self.assertTrue(self.src.exists())  # source never deleted
        self.assertIn((4242, 15), killed)
        names = [c[0] for c in run.calls]
        self.assertIn("/usr/bin/ditto", names)
        self.assertIn("/usr/bin/codesign", names)

    def test_no_existing_app(self):
        dest, _ = M.move_to_applications(
            self.src, home=self.home, dest_dir=self.apps, run=FakeRun(), log=lambda m: None)
        self.assertTrue(dest.exists())
        self.assertFalse((self.home / "Documents" / "WoWGrok-Mac").exists())

    def test_codesign_failure_raises(self):
        with self.assertRaises(M.MoveError):
            M.move_to_applications(
                self.src, home=self.home, dest_dir=self.apps,
                run=FakeRun(codesign_rc=1), log=lambda m: None)

    def test_target_dir_fallback(self):
        d, fb = M.target_dir(self.home)
        if fb:
            self.assertEqual(d, self.home / "Applications")
        else:
            self.assertEqual(d, Path("/Applications"))

    def test_offer_noop_off_mac(self):
        self.assertFalse(M.offer_if_needed(ask=lambda t, b: True, info=lambda t, b: None))


if __name__ == "__main__":
    unittest.main()
