"""Display-free tests for Mac onboard wizard step state + provider mapping."""
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
                    addon_dir="/fake/AddOns", running_from_applications=False
                )
            )

    def test_complete_when_running_from_applications(self):
        self.assertTrue(
            wiz.download_step_complete(
                addon_dir=None, running_from_applications=True
            )
        )

    def test_incomplete_otherwise(self):
        self.assertFalse(
            wiz.download_step_complete(
                addon_dir=None, running_from_applications=False
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

    def test_windows_skips(self):
        with mock.patch.object(wiz.sys, "platform", "win32"):
            self.assertFalse(wiz.should_use_wizard(headless=False, gui_available=True))

    def test_no_gui_skips(self):
        with mock.patch.object(wiz.sys, "platform", "darwin"):
            self.assertFalse(wiz.should_use_wizard(headless=False, gui_available=False))


class FirstRunWizardIntegrationTests(unittest.TestCase):
    def test_mac_incomplete_setup_runs_wizard_not_legacy_prompts(self):
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
                first_run, "_run_mac_onboard_wizard", side_effect=fake_wizard
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


if __name__ == "__main__":
    unittest.main()
