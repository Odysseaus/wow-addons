"""runtime_dir for frozen macOS .app, plus provider / Claude key resolution."""
from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

from bridge_py import config as cfgmod


class TestRuntimeDir(unittest.TestCase):
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


class TestProviderAndClaudeKey(unittest.TestCase):
    def test_resolve_provider(self):
        self.assertEqual(cfgmod.resolve_provider(None), "xai")
        self.assertEqual(cfgmod.resolve_provider({}), "xai")
        self.assertEqual(cfgmod.resolve_provider({"provider": "Claude"}), "claude")
        self.assertEqual(cfgmod.resolve_provider({"provider": "  XAI  "}), "xai")
        self.assertEqual(cfgmod.resolve_provider({"provider": "openai"}), "xai")
        self.assertEqual(cfgmod.resolve_provider({"provider": ""}), "xai")

    def test_default_and_example_keys(self):
        d = cfgmod.default_config()
        self.assertEqual(d["provider"], "xai")
        self.assertEqual(d["claudeApiKey"], "")
        self.assertEqual(d["claudeModel"], "claude-sonnet-4-5")
        self.assertEqual(d["claudeApiBase"], "https://api.anthropic.com")
        self.assertEqual(d["apiKey"], "")
        self.assertEqual(d["model"], "grok-4-latest")
        self.assertEqual(d["apiBase"], "https://api.x.ai/v1")
        example = json.loads(cfgmod.example_path().read_text(encoding="utf-8"))
        for key in ("provider", "claudeApiKey", "claudeModel", "claudeApiBase", "apiKey", "model", "apiBase"):
            self.assertEqual(example[key], d[key])

    def test_claude_key_env_wins_over_file(self):
        cfg = {"claudeApiKey": "file-key", "provider": "claude"}
        with mock.patch.dict(
            os.environ,
            {"ANTHROPIC_API_KEY": "env-key", "XAI_API_KEY": ""},
            clear=False,
        ):
            self.assertEqual(cfgmod.resolve_claude_api_key(cfg), "env-key")
            self.assertTrue(cfgmod.has_claude_api_key(cfg))
            self.assertEqual(cfgmod.claude_api_key_source(cfg), "env ANTHROPIC_API_KEY")
            self.assertTrue(cfgmod.has_provider_api_key(cfg))
            # xAI resolution is unchanged by the Claude env var.
            self.assertEqual(cfgmod.resolve_api_key({"apiKey": "xai-file"}), "xai-file")

    def test_claude_key_from_config_and_missing(self):
        env = os.environ.copy()
        env.pop("ANTHROPIC_API_KEY", None)
        with mock.patch.dict(os.environ, env, clear=True):
            cfg = {"claudeApiKey": "file-key", "provider": "claude"}
            self.assertEqual(cfgmod.resolve_claude_api_key(cfg), "file-key")
            self.assertEqual(cfgmod.claude_api_key_source(cfg), "config.json")
            self.assertEqual(cfgmod.resolve_claude_api_key({}), "")
            self.assertFalse(cfgmod.has_claude_api_key({}))
            self.assertIn("ANTHROPIC_API_KEY", cfgmod.claude_api_key_source({}))
            self.assertFalse(cfgmod.has_provider_api_key({"provider": "claude", "apiKey": "xai-only"}))
            self.assertTrue(cfgmod.has_provider_api_key({"apiKey": "xai-only"}))
            self.assertTrue(cfgmod.has_api_key({"apiKey": "xai-only", "provider": "claude"}))

    def _headless_cfg(self, tmp: str, **extra: object) -> dict:
        cfg = {"addonDir": tmp, "defaultCwd": tmp}
        cfg.update(extra)
        return cfg

    def test_headless_xai_missing_key_unchanged(self):
        from bridge_py import first_run

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)
        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._headless_cfg(tmp)
            buf = io.StringIO()
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(first_run.cfgmod, "save_config") as save, redirect_stderr(buf):
                with self.assertRaises(SystemExit) as ctx:
                    first_run.ensure_first_run_config(headless=True)
            self.assertEqual(ctx.exception.code, 2)
            save.assert_not_called()
            text = buf.getvalue()
            self.assertIn("XAI_API_KEY", text)
            self.assertNotIn("ANTHROPIC", text)

    def test_headless_claude_missing_key(self):
        from bridge_py import first_run

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)
        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._headless_cfg(tmp, provider="claude", apiKey="xai-present")
            buf = io.StringIO()
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(first_run.cfgmod, "save_config") as save, redirect_stderr(buf):
                with self.assertRaises(SystemExit) as ctx:
                    first_run.ensure_first_run_config(headless=True)
            self.assertEqual(ctx.exception.code, 2)
            save.assert_not_called()
            text = buf.getvalue()
            self.assertIn("ANTHROPIC_API_KEY", text)
            self.assertIn("claudeApiKey", text)

    def test_headless_claude_env_key_is_not_written_into_config(self):
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._headless_cfg(tmp, provider="CLAUDE", claudeApiKey="")
            with mock.patch.dict(
                os.environ, {"ANTHROPIC_API_KEY": "sk-ant-from-env"}, clear=False
            ), mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(
                first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
            ) as save, mock.patch(
                "bridge_py.install_addon.ensure_game_files"
            ):
                out = first_run.ensure_first_run_config(headless=True)
            saved = save.call_args[0][0]
            self.assertEqual(cfgmod.resolve_provider(saved), "claude")
            self.assertFalse(saved.get("claudeApiKey"))
            self.assertNotIn("sk-ant-from-env", json.dumps(saved))
            self.assertEqual(out, saved)

    def test_gui_prompts_provider_default_xai_then_xai_key(self):
        """Incomplete setup: provider dialog then existing xAI key prompt."""
        from bridge_py import first_run

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)
        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._headless_cfg(tmp)
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                first_run, "_gui_available", return_value=True
            ), mock.patch.object(
                first_run, "prompt_provider", return_value="xai"
            ) as prov, mock.patch.object(
                first_run, "prompt_api_key", return_value="xai-test-key"
            ) as xai_key, mock.patch.object(
                first_run, "prompt_claude_api_key"
            ) as claude_key, mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(
                first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
            ) as save, mock.patch(
                "bridge_py.install_addon.ensure_game_files"
            ):
                out = first_run.ensure_first_run_config(headless=False)
            prov.assert_called_once()
            xai_key.assert_called_once()
            claude_key.assert_not_called()
            saved = save.call_args[0][0]
            self.assertEqual(saved["provider"], "xai")
            self.assertEqual(saved["apiKey"], "xai-test-key")
            self.assertEqual(out["provider"], "xai")

    def test_gui_prompts_provider_claude_then_claude_key(self):
        """Choosing Claude asks for Anthropic key; xAI key prompt stays unused."""
        from bridge_py import first_run

        env = os.environ.copy()
        env.pop("XAI_API_KEY", None)
        env.pop("ANTHROPIC_API_KEY", None)
        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._headless_cfg(tmp)
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(
                first_run, "_gui_available", return_value=True
            ), mock.patch.object(
                first_run, "prompt_provider", return_value="claude"
            ) as prov, mock.patch.object(
                first_run, "prompt_api_key"
            ) as xai_key, mock.patch.object(
                first_run, "prompt_claude_api_key", return_value="sk-ant-test"
            ) as claude_key, mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(
                first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
            ) as save, mock.patch(
                "bridge_py.install_addon.ensure_game_files"
            ):
                out = first_run.ensure_first_run_config(headless=False)
            prov.assert_called_once()
            claude_key.assert_called_once()
            xai_key.assert_not_called()
            saved = save.call_args[0][0]
            self.assertEqual(saved["provider"], "claude")
            self.assertEqual(saved["claudeApiKey"], "sk-ant-test")
            self.assertEqual(out["claudeApiKey"], "sk-ant-test")

    def test_gui_skips_provider_prompt_when_key_already_present(self):
        from bridge_py import first_run

        with tempfile.TemporaryDirectory() as tmp:
            cfg = self._headless_cfg(tmp, apiKey="already", provider="xai")
            with mock.patch.dict(os.environ, {}, clear=False), mock.patch.object(
                first_run, "_gui_available", return_value=True
            ), mock.patch.object(
                first_run, "prompt_provider"
            ) as prov, mock.patch.object(
                first_run, "prompt_api_key"
            ) as xai_key, mock.patch.object(
                first_run.cfgmod, "load_config", return_value=cfg
            ), mock.patch.object(
                first_run.cfgmod, "save_config", return_value=Path(tmp) / "config.json"
            ), mock.patch(
                "bridge_py.install_addon.ensure_game_files"
            ):
                first_run.ensure_first_run_config(headless=False)
            prov.assert_not_called()
            xai_key.assert_not_called()

    def test_ask_provider_dialog_normalizes_default(self):
        from bridge_py import tk_util

        with mock.patch.object(tk_util, "_run_modal_dialog", return_value="xai") as run:
            self.assertEqual(tk_util.ask_provider_dialog(), "xai")
            run.assert_called_once()
            self.assertEqual(run.call_args.kwargs.get("default"), "xai")
        with mock.patch.object(tk_util, "_run_modal_dialog", return_value="CLAUDE"):
            self.assertEqual(tk_util.ask_provider_dialog(), "claude")
        with mock.patch.object(tk_util, "_run_modal_dialog", return_value=None):
            self.assertEqual(tk_util.ask_provider_dialog(), "xai")



if __name__ == "__main__":
    unittest.main()
