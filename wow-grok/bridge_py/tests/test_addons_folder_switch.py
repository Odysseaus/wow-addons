"""0.1.32: pick any AddOns folder in the wizard; addonDir / inboxFile /
savedVariablesFile move together; Setup… reinstalls + restarts (display-free)."""
from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bridge_py import config as cfgmod
from bridge_py import first_run
from bridge_py import onboard_wizard as wiz
from bridge_py import setup_detect
from bridge_py.tests.test_setup_detect import make_wow_tree


def _addons(root: Path, flavor: str) -> Path:
    return root / flavor / "Interface" / "AddOns"


def _sv(root: Path, flavor: str, acct: str) -> str:
    return str(root / flavor / "WTF" / "Account" / acct / "SavedVariables" / "WoWGrok.lua")


class DerivePathsTests(unittest.TestCase):
    def test_account_from_saved_variables(self):
        self.assertEqual(
            cfgmod.account_from_saved_variables(
                "/A/World of Warcraft/_classic_beta_/WTF/Account/ODY#1/SavedVariables/WoWGrok.lua"
            ),
            "ODY#1",
        )
        self.assertIsNone(
            cfgmod.account_from_saved_variables(
                "/A/_forever_/WTF/Account/YOUR_ACCOUNT/SavedVariables/WoWGrok.lua"
            )
        )
        self.assertIsNone(cfgmod.account_from_saved_variables(""))
        self.assertIsNone(cfgmod.account_from_saved_variables("/tmp/x.lua"))

    def test_switch_flavor_moves_all_three_paths(self):
        """Regression: savedVariablesFile used to stay on _classic_beta_."""
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            cfg = {
                "addonDir": str(_addons(root, "_classic_beta_")),
                "inboxFile": str(_addons(root, "_classic_beta_") / "WoWGrok" / "Inbox.lua"),
                "savedVariablesFile": _sv(root, "_classic_beta_", "ODY"),
            }
            out = cfgmod.derive_paths_from_addon_dir(cfg, str(_addons(root, "_forever_")))
            self.assertEqual(out["addonDir"], str(_addons(root, "_forever_")))
            self.assertEqual(out["inboxFile"], str(_addons(root, "_forever_") / "WoWGrok" / "Inbox.lua"))
            self.assertEqual(out["savedVariablesFile"], _sv(root, "_forever_", "ODY"))
            for k in ("addonDir", "inboxFile", "savedVariablesFile"):
                self.assertNotIn("_classic_beta_", out[k], k)
            # Only computed — nothing created under WTF.
            self.assertFalse((root / "_forever_" / "WTF").exists())
            # Caller's dict untouched.
            self.assertIn("_classic_beta_", cfg["savedVariablesFile"])

    def test_explicit_account_and_placeholder(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            out = cfgmod.derive_paths_from_addon_dir({}, str(_addons(root, "_forever_")), "ACC2")
            self.assertEqual(out["savedVariablesFile"], _sv(root, "_forever_", "ACC2"))
            out = cfgmod.derive_paths_from_addon_dir({}, str(_addons(root, "_forever_")))
            self.assertEqual(out["savedVariablesFile"], _sv(root, "_forever_", "YOUR_ACCOUNT"))


class ApplyAddonDirTests(unittest.TestCase):
    def test_choose_account(self):
        self.assertEqual(first_run.choose_account(["A", "B"], "B"), "B")
        self.assertEqual(first_run.choose_account(["A", "B"], "C"), "A")
        self.assertEqual(first_run.choose_account([], "C"), "C")
        self.assertIsNone(first_run.choose_account([], None))

    def test_apply_keeps_account_when_new_flavor_has_none_yet(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            cfg = {
                "addonDir": str(_addons(root, "_classic_beta_")),
                "savedVariablesFile": _sv(root, "_classic_beta_", "ODY"),
                "capture": {"processName": "WowB"},
            }
            out = first_run._apply_addon_dir(cfg, _addons(root, "_forever_"))
            self.assertEqual(out["savedVariablesFile"], _sv(root, "_forever_", "ODY"))
            self.assertFalse((root / "_forever_" / "WTF").exists())

    def test_apply_uses_existing_account_in_new_flavor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            (root / "_forever_" / "WTF" / "Account" / "FOREVERACCT").mkdir(parents=True)
            cfg = {"savedVariablesFile": _sv(root, "_classic_beta_", "ODY")}
            out = first_run._apply_addon_dir(cfg, _addons(root, "_forever_"))
            self.assertEqual(out["savedVariablesFile"], _sv(root, "_forever_", "FOREVERACCT"))
            (root / "_forever_" / "WTF" / "Account" / "ODY").mkdir(parents=True)
            out = first_run._apply_addon_dir(cfg, _addons(root, "_forever_"))
            self.assertEqual(out["savedVariablesFile"], _sv(root, "_forever_", "ODY"))


class WizardFolderHelpersTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = make_wow_tree(Path(self._tmp.name))
        self.beta = _addons(self.root, "_classic_beta_")
        self.forever = _addons(self.root, "_forever_")
        self.era = _addons(self.root, "_classic_era_")
        self.cands = [self.beta, self.forever, self.era]  # detection order pre-0.1.32

    def tearDown(self):
        self._tmp.cleanup()

    def test_rows_forever_first_and_current_flagged(self):
        rows = wiz.addon_choice_rows(self.cands, self.beta)
        self.assertEqual([r["flavor"] for r in rows], ["_forever_", "_classic_beta_", "_classic_era_"])
        self.assertEqual([r["current"] for r in rows], [False, True, False])
        self.assertEqual(rows[0]["label"], "WoW Forever (_forever_)")

    def test_rows_include_configured_folder_not_detected(self):
        custom = Path(self._tmp.name) / "Elsewhere" / "_forever_" / "Interface" / "AddOns"
        custom.mkdir(parents=True)
        rows = wiz.addon_choice_rows([self.beta], custom)
        self.assertEqual(len(rows), 2)
        self.assertTrue(any(r["current"] and r["path"] == str(custom) for r in rows))

    def test_forever_preselected_over_classic_beta(self):
        self.assertEqual(
            wiz.initial_addon_selection(self.beta, self.cands, chosen=False), str(self.forever)
        )
        self.assertEqual(wiz.initial_addon_selection(None, self.cands), str(self.forever))

    def test_explicit_pick_is_kept(self):
        self.assertEqual(
            wiz.initial_addon_selection(self.beta, self.cands, chosen=True), str(self.beta)
        )

    def test_current_forever_kept_and_no_candidates(self):
        self.assertEqual(wiz.initial_addon_selection(self.forever, self.cands), str(self.forever))
        self.assertEqual(wiz.initial_addon_selection(self.beta, []), str(self.beta))
        self.assertIsNone(wiz.initial_addon_selection(None, []))

    def test_download_needs_review(self):
        sel = wiz.initial_addon_selection(self.beta, self.cands)
        self.assertTrue(wiz.download_needs_review(self.beta, self.cands, sel))
        # Several folders, never picked → review even when selection == config.
        self.assertTrue(wiz.download_needs_review(self.forever, self.cands, self.forever))
        # Picked before → skip straight to Connect as before.
        self.assertFalse(
            wiz.download_needs_review(self.forever, self.cands, self.forever, chosen=True)
        )
        self.assertFalse(wiz.download_needs_review(self.forever, [self.forever], self.forever))

    def test_state_result_addon_dir(self):
        st = wiz.WizardState(current_addon_dir=str(self.beta), addon_dir=str(self.forever))
        # Preselected but never confirmed → never silently switch.
        self.assertEqual(st.result_addon_dir(), str(self.beta))
        st.select_addon_dir(str(self.forever))
        self.assertTrue(st.addon_dir_confirmed)
        self.assertEqual(st.result_addon_dir(), str(self.forever))

    def test_apply_result_marks_chosen(self):
        cfg: dict = {}
        wiz.apply_wizard_result(
            cfg, wiz.WizardResult(status="done", addon_dir=str(self.forever), addon_dir_confirmed=True)
        )
        self.assertTrue(cfg[wiz.ADDON_DIR_CHOSEN_KEY])
        cfg2: dict = {}
        wiz.apply_wizard_result(cfg2, wiz.WizardResult(status="done", addon_dir=str(self.beta)))
        self.assertNotIn(wiz.ADDON_DIR_CHOSEN_KEY, cfg2)

    def test_unpack_pick_result(self):
        self.assertEqual(wiz.unpack_pick_result(None), (None, None))
        self.assertEqual(wiz.unpack_pick_result(self.forever), (self.forever, None))
        self.assertEqual(wiz.unpack_pick_result((None, "bad")), (None, "bad"))
        self.assertEqual(wiz.unpack_pick_result((str(self.forever), None)), (self.forever, None))

    def test_wizard_source_has_folder_rows_and_choose_another(self):
        src = Path(wiz.__file__).read_text(encoding="utf-8")
        self.assertIn("Radiobutton", src)
        self.assertEqual(wiz.CHOOSE_OTHER_FOLDER_LABEL, "Choose another folder…")
        self.assertIn("Currently using (config.json)", src)


class NativePickerTests(unittest.TestCase):
    class _Parent:
        def __init__(self):
            self.top = 1
            self.calls: list = []

        def attributes(self, name, value=None):
            if value is None:
                return self.top
            self.calls.append((name, value))
            self.top = 1 if value else 0

        def update_idletasks(self):
            pass

        def lift(self):
            self.calls.append(("lift",))

    def _run(self, chosen, parent):
        fd = mock.Mock()
        fd.askdirectory.return_value = chosen
        with mock.patch.object(first_run, "_tk", return_value=(None, fd)), mock.patch.object(
            first_run, "_append_bridge_log"
        ), mock.patch.object(setup_detect.sys, "platform", "darwin"):
            out = first_run.pick_addons_dir_native(parent, initialdir=None)
        return out, fd

    def test_picker_result_is_used_and_parented_on_wizard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            parent = self._Parent()
            (picked, err), fd = self._run(str(root / "_forever_"), parent)
            self.assertIsNone(err)
            self.assertEqual(picked, _addons(root, "_forever_"))
            self.assertIs(fd.askdirectory.call_args.kwargs["parent"], parent)
            # topmost dropped while open, restored after
            self.assertEqual(parent.calls[0], ("-topmost", False))
            self.assertIn(("-topmost", True), parent.calls)

    def test_picking_wow_root_returns_forever(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            (picked, err), _ = self._run(str(root), self._Parent())
            self.assertEqual(picked, _addons(root, "_forever_"))

    def test_cancel_and_invalid(self):
        (picked, err), _ = self._run("", self._Parent())
        self.assertEqual((picked, err), (None, None))
        with tempfile.TemporaryDirectory() as tmp:
            (picked, err), _ = self._run(tmp, self._Parent())
            self.assertIsNone(picked)
            self.assertIn("_forever_", err)

    def test_legacy_prompt_multiple_offers_forever(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            cands = [_addons(root, f) for f in ("_classic_beta_", "_forever_", "_classic_era_")]
            with mock.patch.object(first_run.tk_util, "ask_yes_no", return_value=True) as ask:
                got = first_run.prompt_addons_dir(cands)
            self.assertEqual(got, _addons(root, "_forever_"))
            self.assertIn("_forever_", ask.call_args[0][1].split("Use ")[1])


class SetupSwitchFolderTests(unittest.TestCase):
    """Setup… switching _classic_beta_ → _forever_: saves, reinstalls, restarts."""

    def _cfg(self, root: Path) -> dict:
        beta = _addons(root, "_classic_beta_")
        return {
            "addonDir": str(beta),
            "inboxFile": str(beta / "WoWGrok" / "Inbox.lua"),
            "savedVariablesFile": _sv(root, "_classic_beta_", "ODY"),
            "provider": "xai",
            "apiKey": "xai-a",
            "capture": {},
            "slots": 3,
            "lastSeenAppVersion": first_run.current_app_version(),
        }

    def _run(self, cfg, cands, wizard_side_effect, *, real_install=False):
        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)
        saved: list[dict] = []
        patches = [
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(first_run, "_gui_available", return_value=True),
            mock.patch.object(wiz.sys, "platform", "darwin"),
            mock.patch.object(wiz, "run_onboard_wizard", side_effect=wizard_side_effect),
            mock.patch.object(first_run.setup_detect, "find_existing_addons", return_value=cands),
            mock.patch.object(first_run.cfgmod, "load_config", return_value=cfg),
            mock.patch.object(
                first_run.cfgmod, "save_config", side_effect=lambda c: saved.append(dict(c))
            ),
            mock.patch.object(first_run, "_append_bridge_log"),
        ]
        if real_install:
            patches.append(
                mock.patch("bridge_py.install_addon._install_progress_ui", side_effect=RuntimeError("no gui"))
            )
        else:
            patches.append(mock.patch("bridge_py.install_addon.ensure_game_files"))
        started = [p.start() for p in patches]
        try:
            code = first_run.run_setup_wizard_on_demand()
        finally:
            for p in reversed(patches):
                p.stop()
        install = None if real_install else started[-1]
        return code, saved, install, started[3]

    def test_click_forever_row_saves_reinstalls_and_restarts(self):
        from bridge_py import menubar

        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            forever = _addons(root, "_forever_")
            cands = [_addons(root, f) for f in ("_classic_beta_", "_forever_", "_classic_era_")]
            seen: dict = {}

            def fake_wizard(**kw):
                seen.update(kw)
                # Player clicks the _forever_ row: saved immediately.
                info = kw["on_addon_dir_selected"](str(forever))
                seen["info"] = info
                return wiz.WizardResult(
                    status="finish_later", addon_dir=str(forever), addon_dir_confirmed=True
                )

            code, saved, install, run_wiz = self._run(self._cfg(root), cands, fake_wizard)
            self.assertEqual(code, first_run.SETUP_EXIT_APPLIED)
            self.assertEqual(menubar.setup_result_action(code), "restart")
            # Wizard got every folder, _forever_ first.
            self.assertEqual(
                [setup_detect.flavor_of(p) for p in seen["addon_candidates"]],
                ["_forever_", "_classic_beta_", "_classic_era_"],
            )
            self.assertEqual(seen["info"]["addonDir"], str(forever))
            # First save happened at click time (before the wizard closed).
            self.assertGreaterEqual(len(saved), 2)
            first = saved[0]
            self.assertEqual(first["addonDir"], str(forever))
            final = saved[-1]
            self.assertEqual(final["addonDir"], str(forever))
            self.assertEqual(final["inboxFile"], str(forever / "WoWGrok" / "Inbox.lua"))
            self.assertEqual(final["savedVariablesFile"], _sv(root, "_forever_", "ODY"))
            self.assertTrue(final[wiz.ADDON_DIR_CHOSEN_KEY])
            install.assert_called_once()
            self.assertEqual(install.call_args[0][0]["addonDir"], str(forever))
            self.assertFalse((root / "_forever_" / "WTF").exists())

    def test_real_reinstall_lands_in_new_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            forever = _addons(root, "_forever_")

            def fake_wizard(**kw):
                kw["on_addon_dir_selected"](str(forever))
                return wiz.WizardResult(status="done", addon_dir=str(forever), addon_dir_confirmed=True)

            code, saved, _install, _ = self._run(
                self._cfg(root), [forever], fake_wizard, real_install=True
            )
            self.assertEqual(code, first_run.SETUP_EXIT_APPLIED)
            self.assertTrue((forever / "WoWGrok" / "WoWGrok.toc").is_file())
            self.assertTrue((forever / "WoWGrok_S001" / "Inbox.lua").is_file())
            self.assertFalse((_addons(root, "_classic_beta_") / "WoWGrok").exists())

    def test_closing_without_pick_keeps_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = make_wow_tree(Path(tmp))
            cfg = self._cfg(root)
            beta = cfg["addonDir"]

            def fake_wizard(**kw):
                st = wiz.WizardState(current_addon_dir=kw["initial_addon_dir"])
                st.addon_dir = wiz.initial_addon_selection(
                    kw["initial_addon_dir"], kw["addon_candidates"]
                )
                return wiz.WizardResult(status="finish_later", addon_dir=st.result_addon_dir())

            code, saved, install, _ = self._run(
                cfg, [_addons(root, "_classic_beta_"), _addons(root, "_forever_")], fake_wizard
            )
            self.assertEqual(code, first_run.SETUP_EXIT_UNCHANGED)
            self.assertEqual(saved[-1]["addonDir"], beta)
            install.assert_not_called()

    def test_fingerprint_includes_saved_variables(self):
        a = {"addonDir": "/x", "savedVariablesFile": "/x/a.lua", "inboxFile": "/x/i.lua"}
        b = dict(a, savedVariablesFile="/y/a.lua")
        self.assertNotEqual(first_run._setup_fingerprint(a), first_run._setup_fingerprint(b))


if __name__ == "__main__":
    unittest.main()
