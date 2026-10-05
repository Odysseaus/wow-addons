"""Display-free tests for onboard wizard step state + provider mapping (Mac + Windows)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

from bridge_py import onboard_wizard as wiz


class ProviderMappingTests(unittest.TestCase):
    def test_ui_label_grok_maps_to_xai(self):
        self.assertEqual(wiz.ui_label_to_provider("Grok"), "xai")
        self.assertEqual(wiz.ui_label_to_provider("grok"), "xai")
        self.assertEqual(wiz.ui_label_to_provider("xai"), "xai")

    def test_ui_label_claude_maps_to_claude(self):
        self.assertEqual(wiz.ui_label_to_provider("Claude"), "claude")
        self.assertEqual(wiz.ui_label_to_provider("anthropic"), "claude")

    def test_coming_soon_labels_return_none(self):
        for label in ("ChatGPT", "Gemini", "Other", "Unknown"):
            self.assertIsNone(wiz.ui_label_to_provider(label), label)

    def test_live_providers_are_claude_and_grok(self):
        live = wiz.live_provider_ids()
        self.assertEqual(set(live), {"claude", "grok"})
        for row in wiz.PROVIDER_ROWS:
            if row["id"] in live:
                self.assertTrue(row["live"])
                self.assertIsNotNone(row["config_provider"])
                self.assertIsNotNone(row["key_field"])
            else:
                self.assertFalse(row["live"])
                self.assertIsNone(row["config_provider"])

    def test_provider_row_for_config(self):
        self.assertEqual(wiz.provider_row_for_config("xai")["id"], "grok")
        self.assertEqual(wiz.provider_row_for_config("claude")["id"], "claude")
        self.assertIsNone(wiz.provider_row_for_config("openai"))


class WizardStateTests(unittest.TestCase):
    def test_initial_step_is_download(self):
        st = wiz.WizardState()
        self.assertEqual(st.active_step, wiz.STEP_DOWNLOAD)
        self.assertEqual(st.step_status(wiz.STEP_DOWNLOAD), "active")
        self.assertEqual(st.step_status(wiz.STEP_CONNECT), "pending")
        self.assertEqual(st.step_status(wiz.STEP_SAY_HI), "pending")

    def test_mark_download_advances_to_connect(self):
        st = wiz.WizardState()
        st.mark_download_done()
        self.assertIn(wiz.STEP_DOWNLOAD, st.completed_steps)
        self.assertEqual(st.active_step, wiz.STEP_CONNECT)
        self.assertEqual(st.step_status(wiz.STEP_DOWNLOAD), "done")
        self.assertEqual(st.step_status(wiz.STEP_CONNECT), "active")

    def test_mark_connected_sets_provider_and_advances(self):
        st = wiz.WizardState()
        st.mark_download_done()
        row = wiz.provider_row_by_id("grok")
        assert row is not None
        st.mark_connected(row, "xai-test-key")
        self.assertEqual(st.provider, "xai")
        self.assertEqual(st.key_field, "apiKey")
        self.assertEqual(st.api_key, "xai-test-key")
        self.assertEqual(st.connected_label, "Grok")
        self.assertEqual(st.active_step, wiz.STEP_SAY_HI)
        self.assertEqual(st.step_status(wiz.STEP_CONNECT), "done")
        self.assertEqual(st.step_status(wiz.STEP_SAY_HI), "active")

    def test_mark_connected_claude(self):
        st = wiz.WizardState()
        row = wiz.provider_row_by_id("claude")
        assert row is not None
        st.mark_connected(row, "sk-ant-test")
        self.assertEqual(st.provider, "claude")
        self.assertEqual(st.key_field, "claudeApiKey")

    def test_mark_say_hi_done_completes(self):
        st = wiz.WizardState()
        st.mark_say_hi_done()
        self.assertTrue(st.completed)
        self.assertEqual(st.step_status(wiz.STEP_SAY_HI), "done")


class DownloadCompleteTests(unittest.TestCase):
    def test_complete_when_addon_dir_exists(self):
        with mock.patch.object(Path, "is_dir", return_value=True):
            self.assertTrue(
                wiz.download_step_complete(
                    addon_dir="/fake/AddOns",
                    running_from_applications=False,
                    running_frozen=False,
                )
            )

    def test_complete_when_running_from_applications_mac(self):
        with mock.patch.object(wiz.sys, "platform", "darwin"):
            self.assertTrue(
                wiz.download_step_complete(
                    addon_dir=None, running_from_applications=True
                )
            )

    def test_incomplete_on_mac_otherwise(self):
        with mock.patch.object(wiz.sys, "platform", "darwin"):
            self.assertFalse(
                wiz.download_step_complete(
                    addon_dir=None, running_from_applications=False
                )
            )

    def test_complete_on_windows_when_frozen(self):
        with mock.patch.object(wiz.sys, "platform", "win32"):
            self.assertTrue(
                wiz.download_step_complete(
                    addon_dir=None, running_frozen=True
                )
            )

    def test_incomplete_on_windows_when_not_frozen(self):
        with mock.patch.object(wiz.sys, "platform", "win32"):
            self.assertFalse(
                wiz.download_step_complete(
                    addon_dir=None, running_frozen=False
                )
            )

    def test_windows_does_not_require_applications(self):
        """Applications path must not gate Windows download completeness."""
        with mock.patch.object(wiz.sys, "platform", "win32"), mock.patch.object(
            wiz, "is_running_from_applications", return_value=False
        ):
            self.assertTrue(
                wiz.download_step_complete(
                    addon_dir=None, running_frozen=True
                )
            )


class ApplyResultTests(unittest.TestCase):
    def test_apply_wizard_result_merges_fields(self):
        cfg: dict = {"provider": "xai", "apiKey": ""}
        result = wiz.WizardResult(
            status="done",
            provider="claude",
            api_key="sk-ant",
            key_field="claudeApiKey",
            addon_dir="/tmp/AddOns",
        )
        out = wiz.apply_wizard_result(cfg, result)
        self.assertIs(out, cfg)
        self.assertEqual(cfg["provider"], "claude")
        self.assertEqual(cfg["claudeApiKey"], "sk-ant")
        self.assertEqual(cfg["addonDir"], "/tmp/AddOns")


class ShouldUseWizardTests(unittest.TestCase):
    def test_darwin_gui_uses_wizard(self):
        with mock.patch.object(wiz.sys, "platform", "darwin"):
            self.assertTrue(wiz.should_use_wizard(headless=False, gui_available=True))

    def test_headless_skips(self):
        with mock.patch.object(wiz.sys, "platform", "darwin"):
            self.assertFalse(wiz.should_use_wizard(headless=True, gui_available=True))

    def test_windows_gui_uses_wizard(self):
        with mock.patch.object(wiz.sys, "platform", "win32"):
            self.assertTrue(wiz.should_use_wizard(headless=False, gui_available=True))

    def test_windows_headless_skips(self):
        with mock.patch.object(wiz.sys, "platform", "win32"):
            self.assertFalse(wiz.should_use_wizard(headless=True, gui_available=True))

    def test_linux_skips(self):
        with mock.patch.object(wiz.sys, "platform", "linux"):
            self.assertFalse(wiz.should_use_wizard(headless=False, gui_available=True))

    def test_no_gui_skips(self):
        with mock.patch.object(wiz.sys, "platform", "darwin"):
            self.assertFalse(wiz.should_use_wizard(headless=False, gui_available=False))


class FirstRunWizardIntegrationTests(unittest.TestCase):
    def test_mac_first_launch_incomplete_runs_wizard_not_legacy_prompts(self):
        from bridge_py import first_run
        import os
        import tempfile

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)

        with tempfile.TemporaryDirectory() as tmp:
            cfg = {
                "addonDir": "",
                "defaultCwd": tmp,
                "provider": "xai",
                "apiKey": "",
                "claudeApiKey": "",
                "capture": {},
            }

            def fake_wizard(c: dict) -> dict:
                c["provider"] = "xai"
                c["apiKey"] = "xai-from-wizard"
                return first_run._apply_addon_dir(c, Path(tmp))

            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                first_run, "_gui_available", return_value=True
            ), mock.patch.object(
                first_run.sys, "platform", "darwin"
            ), mock.patch.object(
                wiz.sys, "platform", "darwin"
            ), mock.patch.object(
                first_run, "_run_onboard_wizard", side_effect=fake_wizard
            ) as run_wiz, mock.patch.object(
                first_run, "prompt_provider"
            ) as prov, mock.patch.object(
                first_run, "prompt_api_key"
            ) as xai_key, mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(
                first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
            ) as save, mock.patch(
                "bridge_py.install_addon.ensure_game_files"
            ), mock.patch.object(
                first_run, "prompt_mac_screen_recording"
            ):
                out = first_run.ensure_first_run_config(headless=False)
            run_wiz.assert_called_once()
            prov.assert_not_called()
            xai_key.assert_not_called()
            saved = save.call_args[0][0]
            self.assertEqual(saved["apiKey"], "xai-from-wizard")
            self.assertEqual(saved["provider"], "xai")
            self.assertEqual(out["addonDir"], str(Path(tmp).resolve()))



    def test_windows_first_launch_incomplete_runs_wizard_not_legacy_prompts(self):
        from bridge_py import first_run
        import os
        import tempfile

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)

        with tempfile.TemporaryDirectory() as tmp:
            cfg = {
                "addonDir": "",
                "defaultCwd": tmp,
                "provider": "xai",
                "apiKey": "",
                "claudeApiKey": "",
                "capture": {},
            }

            def fake_wizard(c: dict) -> dict:
                c["provider"] = "xai"
                c["apiKey"] = "xai-from-wizard-win"
                return first_run._apply_addon_dir(c, Path(tmp))

            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                first_run, "_gui_available", return_value=True
            ), mock.patch.object(
                first_run.sys, "platform", "win32"
            ), mock.patch.object(
                wiz.sys, "platform", "win32"
            ), mock.patch.object(
                first_run, "_run_onboard_wizard", side_effect=fake_wizard
            ) as run_wiz, mock.patch.object(
                first_run, "prompt_provider"
            ) as prov, mock.patch.object(
                first_run, "prompt_api_key"
            ) as xai_key, mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(
                first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
            ) as save, mock.patch(
                "bridge_py.install_addon.ensure_game_files"
            ), mock.patch.object(
                first_run, "prompt_mac_screen_recording"
            ) as screen:
                out = first_run.ensure_first_run_config(headless=False)
            run_wiz.assert_called_once()
            prov.assert_not_called()
            xai_key.assert_not_called()
            screen.assert_not_called()  # Screen Recording is Mac-only
            saved = save.call_args[0][0]
            self.assertEqual(saved["apiKey"], "xai-from-wizard-win")
            self.assertEqual(saved["provider"], "xai")
            self.assertEqual(out["addonDir"], str(Path(tmp).resolve()))


class ExistingKeyStateTests(unittest.TestCase):
    def test_mark_existing_key_shows_connected_without_new_key(self):
        st = wiz.WizardState()
        st.mark_download_done()
        row = wiz.provider_row_by_id("grok")
        assert row is not None
        st.mark_existing_key(row)
        self.assertEqual(st.connected_label, "Grok")
        self.assertEqual(st.provider, "xai")
        self.assertIsNone(st.api_key)  # nothing new to write back
        self.assertEqual(st.step_status(wiz.STEP_CONNECT), "done")
        # Stays on Connect so the user can still replace the key / switch.
        self.assertEqual(st.active_step, wiz.STEP_CONNECT)
        self.assertTrue(st.can_continue_with("grok"))
        self.assertFalse(st.can_continue_with("claude"))

    def test_can_continue_requires_key_or_existing(self):
        st = wiz.WizardState()
        self.assertFalse(st.can_continue_with("grok"))
        row = wiz.provider_row_by_id("claude")
        assert row is not None
        st.mark_connected(row, "sk-ant-x")
        self.assertTrue(st.can_continue_with("claude"))

    def test_apply_result_without_new_key_keeps_existing_key(self):
        cfg = {"provider": "xai", "apiKey": "xai-old"}
        res = wiz.WizardResult(status="finish_later", provider="xai")
        wiz.apply_wizard_result(cfg, res)
        self.assertEqual(cfg["apiKey"], "xai-old")


class OnboardVersionGateTests(unittest.TestCase):
    def setUp(self):
        from bridge_py import first_run

        self.fr = first_run
        self.cur = self.fr.current_app_version()

    def test_missing_last_seen_is_due(self):
        self.assertTrue(self.fr.app_version_wizard_due({"apiKey": "k"}))
        self.assertTrue(self.fr.app_version_wizard_due(None))
        self.assertTrue(self.fr.app_version_wizard_due({}))

    def test_different_app_version_is_due(self):
        self.assertTrue(self.fr.app_version_wizard_due({"lastSeenAppVersion": "0.0.1"}))
        self.assertTrue(self.fr.app_version_wizard_due({"lastSeenAppVersion": "0.1.28"}))

    def test_same_app_version_not_due(self):
        cfg = {"lastSeenAppVersion": self.cur}
        self.assertFalse(self.fr.app_version_wizard_due(cfg))

    def test_should_show_matrix_version_only(self):
        seen = {"lastSeenAppVersion": self.cur}
        show = self.fr.should_show_onboard_wizard
        # No GUI wizard path → never.
        self.assertFalse(show({}, use_wizard=False))
        self.assertFalse(show(seen, use_wizard=False))
        # Version bump (missing lastSeen) → show once, regardless of setup.
        self.assertTrue(show({}, use_wizard=True))
        # Same version → never auto-show (even if caller would have needs_setup).
        self.assertFalse(show(seen, use_wizard=True))

    def test_mark_seen_writes_app_version(self):
        cfg: dict = {}
        self.fr.mark_onboard_wizard_seen(cfg)
        self.assertEqual(cfg["lastSeenAppVersion"], self.cur)
        self.assertFalse(self.fr.app_version_wizard_due(cfg))

    def test_migrate_legacy_onboard_wizard_version(self):
        cfg = {"onboardWizardVersion": 1, "apiKey": "k"}
        self.assertTrue(self.fr.migrate_legacy_onboard_wizard_version(cfg))
        # Legacy key removed; lastSeen must NOT be invented (wizard still due).
        self.assertNotIn("onboardWizardVersion", cfg)
        self.assertNotIn("lastSeenAppVersion", cfg)
        self.assertTrue(self.fr.app_version_wizard_due(cfg))
        # Idempotent: no legacy key left → no-op.
        self.assertFalse(self.fr.migrate_legacy_onboard_wizard_version(cfg))
        # No legacy key → no migration.
        self.assertFalse(self.fr.migrate_legacy_onboard_wizard_version({"apiKey": "k"}))
        # Legacy key with existing lastSeen: still only deletes the legacy key.
        cfg2 = {"onboardWizardVersion": 1, "lastSeenAppVersion": "0.1.28"}
        self.assertTrue(self.fr.migrate_legacy_onboard_wizard_version(cfg2))
        self.assertNotIn("onboardWizardVersion", cfg2)
        self.assertEqual(cfg2["lastSeenAppVersion"], "0.1.28")


class UpgradeGateIntegrationTests(unittest.TestCase):
    """App-version gate: wizard shows once per build bump, then stays quiet."""

    def _run(
        self,
        cfg: dict,
        tmp: str,
        status: str = "finish_later",
        *,
        prompt_key: str | None = None,
        prompt_addons: "Path | None" = None,
    ):
        from bridge_py import first_run
        import os

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)
        patches = [
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch.object(first_run, "_gui_available", return_value=True),
            mock.patch.object(first_run.sys, "platform", "darwin"),
            mock.patch.object(wiz.sys, "platform", "darwin"),
            mock.patch.object(
                wiz, "run_onboard_wizard", return_value=wiz.WizardResult(status=status)
            ),
            mock.patch.object(first_run.setup_detect, "find_existing_addons", return_value=[]),
            mock.patch.object(first_run.cfgmod, "load_config", return_value=cfg),
            mock.patch.object(
                first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
            ),
            mock.patch("bridge_py.install_addon.ensure_game_files"),
            mock.patch.object(first_run, "prompt_mac_screen_recording"),
            mock.patch.object(first_run, "prompt_provider", return_value="xai"),
            mock.patch.object(first_run, "prompt_api_key", return_value=prompt_key or ""),
            mock.patch.object(
                first_run,
                "prompt_addons_dir",
                return_value=prompt_addons,
            ),
        ]
        with patches[0], patches[1], patches[2], patches[3], patches[4] as run_wiz, patches[
            5
        ], patches[6], patches[7] as save, patches[8], patches[9], patches[10] as prov, patches[
            11
        ] as xai_key, patches[12] as addons:
            out = first_run.ensure_first_run_config(headless=False)
        return out, run_wiz, save, prov, xai_key, addons

    def _configured(self, tmp: str) -> dict:
        return {
            "addonDir": tmp,
            "defaultCwd": tmp,
            "provider": "xai",
            "apiKey": "xai-existing",
            "claudeApiKey": "",
            "capture": {},
        }

    def test_configured_pre_wizard_install_sees_wizard_once(self):
        import tempfile
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._configured(tmp)
            out, run_wiz, save, *_ = self._run(cfg, tmp)
            run_wiz.assert_called_once()
            self.assertTrue(run_wiz.call_args.kwargs["provider_key_present"])
            self.assertEqual(out["lastSeenAppVersion"], first_run.current_app_version())
            self.assertEqual(out["apiKey"], "xai-existing")  # not wiped by finish later
            saved = save.call_args[0][0]
            self.assertEqual(saved["lastSeenAppVersion"], first_run.current_app_version())

            # Next launch: same config now carries lastSeen → no wizard.
            out2, run_wiz2, *_ = self._run(dict(out), tmp)
            run_wiz2.assert_not_called()

    def test_cancelled_also_marks_seen(self):
        import tempfile
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            out, run_wiz, *_ = self._run(self._configured(tmp), tmp, status="cancelled")
            run_wiz.assert_called_once()
            self.assertEqual(out["lastSeenAppVersion"], first_run.current_app_version())

    def test_legacy_onboard_wizard_version_still_shows_after_cleanup(self):
        """Legacy key alone must not suppress the wizard for the current build."""
        import tempfile
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._configured(tmp)
            cfg["onboardWizardVersion"] = 1  # PR #45 leftover; no lastSeen
            out, run_wiz, save, *_ = self._run(cfg, tmp)
            run_wiz.assert_called_once()
            self.assertNotIn("onboardWizardVersion", out)
            self.assertEqual(out["lastSeenAppVersion"], first_run.current_app_version())
            saved = save.call_args[0][0]
            self.assertEqual(saved["lastSeenAppVersion"], first_run.current_app_version())
            self.assertNotIn("onboardWizardVersion", saved)

    def test_same_version_incomplete_uses_sequential_not_wizard(self):
        import tempfile
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._configured(tmp)
            cfg["apiKey"] = ""
            cfg["lastSeenAppVersion"] = first_run.current_app_version()
            out, run_wiz, save, prov, xai_key, addons = self._run(
                cfg, tmp, prompt_key="xai-from-sequential"
            )
            run_wiz.assert_not_called()
            addons.assert_not_called()  # AddOns already set
            prov.assert_called_once()
            xai_key.assert_called_once()
            self.assertEqual(out["apiKey"], "xai-from-sequential")
            # lastSeen must not be rewritten just because setup was incomplete
            self.assertEqual(out["lastSeenAppVersion"], first_run.current_app_version())

    def test_version_bump_finish_later_without_key_still_exits_2(self):
        """After the version-bump wizard closes without a key, exit 2 (not sequential)."""
        import tempfile
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._configured(tmp)
            cfg["apiKey"] = ""
            # No lastSeen → wizard due; finish_later leaves no key → exit 2.
            with self.assertRaises(SystemExit) as cm:
                self._run(cfg, tmp)
            self.assertEqual(cm.exception.code, 2)


class SetupOnDemandTests(unittest.TestCase):
    def _run(self, cfg: dict, result: "wiz.WizardResult", tmp: str):
        from bridge_py import first_run
        import os

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
            first_run, "_gui_available", return_value=True
        ), mock.patch.object(wiz.sys, "platform", "darwin"), mock.patch.object(
            wiz, "run_onboard_wizard", return_value=result
        ), mock.patch.object(
            first_run.setup_detect, "find_existing_addons", return_value=[]
        ), mock.patch.object(
            first_run.cfgmod, "load_config", return_value=cfg
        ), mock.patch.object(
            first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
        ) as save, mock.patch(
            "bridge_py.install_addon.ensure_game_files"
        ) as install:
            code = first_run.run_setup_wizard_on_demand()
        return code, save, install

    def test_unchanged_returns_3_no_reinstall(self):
        import tempfile
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = {"addonDir": tmp, "provider": "xai", "apiKey": "xai-a", "capture": {}}
            code, save, install = self._run(cfg, wiz.WizardResult(status="finish_later"), tmp)
            self.assertEqual(code, first_run.SETUP_EXIT_UNCHANGED)
            save.assert_called()  # lastSeenAppVersion recorded
            install.assert_not_called()

    def test_new_key_returns_0_and_reinstalls(self):
        import tempfile
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = {"addonDir": tmp, "provider": "xai", "apiKey": "xai-a", "capture": {}}
            res = wiz.WizardResult(
                status="done", provider="claude", api_key="sk-ant-new", key_field="claudeApiKey"
            )
            code, save, install = self._run(cfg, res, tmp)
            self.assertEqual(code, first_run.SETUP_EXIT_APPLIED)
            saved = save.call_args[0][0]
            self.assertEqual(saved["provider"], "claude")
            self.assertEqual(saved["claudeApiKey"], "sk-ant-new")
            install.assert_called_once()


class MenubarSetupHelpersTests(unittest.TestCase):
    def test_setup_command_source_run(self):
        from bridge_py import menubar

        with mock.patch.object(sys, "frozen", False, create=True):
            cmd = menubar.setup_wizard_command()
        self.assertEqual(cmd, [sys.executable, "-m", "bridge_py", "--onboard-setup"])

    def test_setup_command_frozen(self):
        from bridge_py import menubar

        exe = "/Applications/WoWGrok.app/Contents/MacOS/WoWGrok"
        with mock.patch.object(sys, "frozen", True, create=True), mock.patch.object(
            sys, "executable", exe
        ):
            self.assertEqual(menubar.setup_wizard_command(), [exe, "--onboard-setup"])

    def test_setup_result_action(self):
        from bridge_py import menubar, supervisor

        self.assertEqual(menubar.setup_result_action(0), "restart")
        for code in (3, 4, 1, -15, None):
            self.assertEqual(menubar.setup_result_action(code), "none")
        self.assertEqual(menubar.RESTART_EXIT_CODE, supervisor.RESTART_EXIT_CODE)

    def test_main_dispatches_onboard_setup(self):
        from bridge_py import __main__ as entry

        with mock.patch(
            "bridge_py.first_run.run_setup_wizard_on_demand", return_value=3
        ) as run:
            self.assertEqual(entry.main(["--onboard-setup"]), 3)
        run.assert_called_once()


if __name__ == "__main__":
    unittest.main()
