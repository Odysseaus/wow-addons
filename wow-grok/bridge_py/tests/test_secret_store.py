"""Windows Credential Manager key storage (secret_store + config integration).

Most tests install a fake backend so they run on any OS. The final class does a
real Credential Manager round trip and only runs on Windows (CI windows job).
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest import mock

from bridge_py import config as cfgmod
from bridge_py import first_run
from bridge_py import secret_store

SECRET = "xai-TEST-SECRET-do-not-log-1234567890"
CLAUDE_SECRET = "sk-ant-TEST-SECRET-do-not-log-0987654321"


class FakeBackend:
    def __init__(self, *, fail_write: bool = False, drop_write: bool = False, fail_read: bool = False):
        self.items: dict[str, str] = {}
        self.fail_write = fail_write
        self.drop_write = drop_write
        self.fail_read = fail_read
        self.writes: list[str] = []

    def read(self, target):
        if self.fail_read:
            raise secret_store.SecretStoreError("CredReadW failed (winerror 5)")
        return self.items.get(target)

    def write(self, target, value):
        self.writes.append(target)
        if self.fail_write:
            raise secret_store.SecretStoreError("CredWriteW failed (winerror 5)")
        if not self.drop_write:
            self.items[target] = value

    def delete(self, target):
        return self.items.pop(target, None) is not None


class _FakeStoreCase(unittest.TestCase):
    backend_kwargs: dict = {}

    def setUp(self):
        self.backend = FakeBackend(**self.backend_kwargs)
        p = mock.patch.object(secret_store, "_backend_override", self.backend)
        p.start()
        self.addCleanup(p.stop)
        env = mock.patch.dict(os.environ, {"XAI_API_KEY": "", "ANTHROPIC_API_KEY": ""})
        env.start()
        self.addCleanup(env.stop)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        rd = mock.patch.object(cfgmod, "runtime_dir", return_value=Path(self.tmp.name))
        rd.start()
        self.addCleanup(rd.stop)

    def disk(self) -> dict:
        return json.loads(cfgmod.config_path().read_text(encoding="utf-8"))

    def log_text(self) -> str:
        p = cfgmod.log_path()
        return p.read_text(encoding="utf-8") if p.exists() else ""


class TestSecretStoreModule(_FakeStoreCase):
    def test_round_trip_uses_wowgrok_targets(self):
        self.assertTrue(secret_store.available())
        self.assertTrue(secret_store.put("apiKey", SECRET))
        self.assertEqual(self.backend.items, {"WoWGrok/apiKey": SECRET})
        self.assertEqual(secret_store.get("apiKey"), SECRET)
        self.assertEqual(secret_store.get("claudeApiKey"), "")
        self.assertTrue(secret_store.delete("apiKey"))
        self.assertFalse(secret_store.delete("apiKey"))
        self.assertEqual(secret_store.get("apiKey"), "")

    def test_put_empty_is_noop(self):
        self.assertFalse(secret_store.put("apiKey", ""))
        self.assertEqual(self.backend.writes, [])

    def test_put_verifies_read_back(self):
        self.backend.drop_write = True
        self.assertFalse(secret_store.put("apiKey", SECRET))

    def test_errors_never_raise(self):
        self.backend.fail_write = True
        self.assertFalse(secret_store.put("apiKey", SECRET))
        self.backend.fail_read = True
        self.assertEqual(secret_store.get("apiKey"), "")


class TestNoStoreOffWindows(unittest.TestCase):
    def test_unavailable_on_mac_and_linux(self):
        for plat in ("darwin", "linux"):
            with mock.patch.object(secret_store, "_backend_override", None), mock.patch.object(
                sys, "platform", plat
            ):
                self.assertFalse(secret_store.available())
                self.assertEqual(secret_store.get("apiKey"), "")
                self.assertFalse(secret_store.put("apiKey", SECRET))
                self.assertIsNone(cfgmod.secure_store_label())

    def test_mac_save_keeps_key_in_config_json(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(
            secret_store, "_backend_override", None
        ), mock.patch.object(sys, "platform", "darwin"), mock.patch.object(
            cfgmod, "runtime_dir", return_value=Path(tmp)
        ):
            cfgmod.save_config({"apiKey": SECRET, "claudeApiKey": CLAUDE_SECRET})
            disk = json.loads(cfgmod.config_path().read_text(encoding="utf-8"))
        self.assertEqual(disk["apiKey"], SECRET)
        self.assertEqual(disk["claudeApiKey"], CLAUDE_SECRET)


class TestConfigMigration(_FakeStoreCase):
    def test_save_moves_keys_to_store_and_blanks_disk(self):
        cfg = {"provider": "xai", "apiKey": SECRET, "claudeApiKey": CLAUDE_SECRET, "slots": 200}
        cfgmod.save_config(cfg)
        disk = self.disk()
        self.assertEqual(disk["apiKey"], "")
        self.assertEqual(disk["claudeApiKey"], "")
        self.assertEqual(disk["slots"], 200)
        self.assertEqual(self.backend.items["WoWGrok/apiKey"], SECRET)
        self.assertEqual(self.backend.items["WoWGrok/claudeApiKey"], CLAUDE_SECRET)
        # caller's in-memory cfg is untouched (bridge keeps using it this run)
        self.assertEqual(cfg["apiKey"], SECRET)
        raw = cfgmod.config_path().read_text(encoding="utf-8")
        self.assertNotIn(SECRET, raw)
        self.assertNotIn(CLAUDE_SECRET, raw)

    def test_existing_plaintext_install_migrates_on_next_save(self):
        cfgmod.config_path().write_text(json.dumps({"apiKey": SECRET}), encoding="utf-8")
        cfg = cfgmod.load_config()
        cfgmod.save_config(cfg)
        self.assertEqual(self.disk()["apiKey"], "")
        reloaded = cfgmod.load_config()
        self.assertEqual(cfgmod.resolve_api_key(reloaded), SECRET)
        self.assertTrue(cfgmod.has_provider_api_key(reloaded))
        self.assertEqual(cfgmod.api_key_source(reloaded), "Windows Credential Manager")

    def test_write_failure_keeps_plaintext_fallback(self):
        self.backend.fail_write = True
        cfgmod.save_config({"apiKey": SECRET})
        self.assertEqual(self.disk()["apiKey"], SECRET)
        self.assertIn("kept in local config.json", self.log_text())

    def test_unverified_write_keeps_plaintext_fallback(self):
        self.backend.drop_write = True
        cfgmod.save_config({"apiKey": SECRET})
        self.assertEqual(self.disk()["apiKey"], SECRET)

    def test_empty_field_does_not_delete_stored_key(self):
        self.backend.items["WoWGrok/apiKey"] = SECRET
        cfgmod.save_config({"apiKey": "", "capture": {"permissionPaused": True}})
        self.assertEqual(self.backend.items["WoWGrok/apiKey"], SECRET)

    def test_log_never_contains_secret(self):
        cfgmod.save_config({"apiKey": SECRET, "claudeApiKey": CLAUDE_SECRET})
        log = self.log_text()
        self.assertIn("apiKey stored in Windows Credential Manager", log)
        self.assertNotIn(SECRET, log)
        self.assertNotIn(CLAUDE_SECRET, log)
        self.backend.fail_write = True
        cfgmod.save_config({"apiKey": SECRET})
        self.assertNotIn(SECRET, self.log_text())

    def test_resolution_order_env_then_config_then_store(self):
        self.backend.items["WoWGrok/apiKey"] = "store-key"
        self.backend.items["WoWGrok/claudeApiKey"] = "store-claude"
        self.assertEqual(cfgmod.resolve_api_key({}), "store-key")
        self.assertEqual(cfgmod.resolve_api_key({"apiKey": "file-key"}), "file-key")
        self.assertEqual(cfgmod.api_key_source({"apiKey": "file-key"}), "config.json")
        self.assertEqual(cfgmod.resolve_claude_api_key({}), "store-claude")
        self.assertEqual(cfgmod.claude_api_key_source({}), "Windows Credential Manager")
        self.assertTrue(cfgmod.has_provider_api_key({"provider": "claude"}))
        with mock.patch.dict(os.environ, {"XAI_API_KEY": "env-key"}):
            self.assertEqual(cfgmod.resolve_api_key({"apiKey": "file-key"}), "env-key")
            self.assertEqual(cfgmod.api_key_source({}), "env XAI_API_KEY")

    def test_missing_everywhere(self):
        self.assertEqual(cfgmod.resolve_api_key({}), "")
        self.assertFalse(cfgmod.has_api_key({}))
        self.assertIn("MISSING", cfgmod.api_key_source({}))

    def test_forget_stored_keys(self):
        self.backend.items["WoWGrok/apiKey"] = SECRET
        self.assertEqual(cfgmod.forget_stored_keys(), ["apiKey"])
        self.assertEqual(self.backend.items, {})


class TestFirstRunPromptWording(unittest.TestCase):
    def _texts(self, fn):
        info, asked = [], []
        with mock.patch.object(first_run.tk_util, "show_info_dialog", side_effect=lambda t, m: info.append(m)), \
                mock.patch.object(first_run.tk_util, "ask_string_dialog", side_effect=lambda t, m, show=None: asked.append(m) or SECRET):
            self.assertEqual(fn(), SECRET)
        return " ".join(info + asked)

    def test_windows_wording_names_credential_manager(self):
        with mock.patch.object(secret_store, "_backend_override", FakeBackend()):
            xai_text = self._texts(first_run.prompt_api_key)
            claude_text = self._texts(first_run.prompt_claude_api_key)
        for text in (xai_text, claude_text):
            self.assertIn("Windows Credential Manager", text)
            self.assertNotIn("ONLY", text)
            self.assertNotIn(SECRET, text)

    def test_mac_wording_unchanged(self):
        with mock.patch.object(secret_store, "_backend_override", None), mock.patch.object(
            sys, "platform", "darwin"
        ):
            xai_text = self._texts(first_run.prompt_api_key)
            claude_text = self._texts(first_run.prompt_claude_api_key)
        self.assertIn(
            "Your key is stored ONLY in a local config.json on this computer "
            "(next to the bridge). It is never uploaded",
            xai_text,
        )
        self.assertIn("(Stored locally only in config.json — not uploaded, not in the addon.)", xai_text)
        self.assertIn(
            "It is stored ONLY in local config.json as claudeApiKey "
            "(not uploaded, not sent to the WoW addon, not written into Lua).",
            claude_text,
        )
        self.assertNotIn("Credential Manager", xai_text + claude_text)


@unittest.skipUnless(sys.platform == "win32", "real Credential Manager round trip needs Windows")
class TestRealWindowsCredentialManager(unittest.TestCase):
    def test_round_trip(self):
        prefix = f"WoWGrokTest-{uuid.uuid4().hex}/"
        with mock.patch.object(secret_store, "TARGET_PREFIX", prefix), mock.patch.object(
            secret_store, "_backend_override", None
        ):
            self.assertTrue(secret_store.available())
            try:
                self.assertEqual(secret_store.get("apiKey"), "")
                self.assertTrue(secret_store.put("apiKey", SECRET))
                self.assertEqual(secret_store.get("apiKey"), SECRET)
                self.assertTrue(secret_store.put("apiKey", "xai-rotated"))
                self.assertEqual(secret_store.get("apiKey"), "xai-rotated")
            finally:
                secret_store.delete("apiKey")
            self.assertEqual(secret_store.get("apiKey"), "")
            self.assertFalse(secret_store.delete("apiKey"))


if __name__ == "__main__":
    unittest.main()
