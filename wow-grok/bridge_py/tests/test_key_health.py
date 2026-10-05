"""Key health: auth-failure classification, probe (fake opener), flag roundtrip."""
from __future__ import annotations

import io
import os
import unittest
import urllib.error
from unittest import mock

from bridge_py import key_health as kh
from bridge_py import onboard_wizard as wiz
from bridge_py.tests import ORIGINAL_PROBE

FAKE_XAI = "xai-test-not-real"
FAKE_CLAUDE = "sk-ant-test-not-real"


class _Resp:
    def __init__(self, status: int = 200):
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def _http_error(url: str, code: int, body: str) -> urllib.error.HTTPError:
    return urllib.error.HTTPError(url, code, "err", {}, io.BytesIO(body.encode()))


class IsAuthFailureTests(unittest.TestCase):
    def test_xai(self):
        self.assertTrue(kh.is_auth_failure("xai", 400, "Incorrect API key provided."))
        self.assertTrue(kh.is_auth_failure("xai", 401, ""))
        self.assertTrue(kh.is_auth_failure("xai", 403, ""))
        self.assertFalse(kh.is_auth_failure("xai", 400, "bad previous_response_id"))
        self.assertFalse(kh.is_auth_failure("xai", 500, "api key invalid?"))
        self.assertFalse(kh.is_auth_failure("xai", 429, "rate limited"))
        self.assertFalse(kh.is_auth_failure("xai", None, "network error"))

    def test_claude(self):
        self.assertTrue(kh.is_auth_failure("claude", 401, ""))
        self.assertTrue(kh.is_auth_failure("claude", None, '{"type":"authentication_error"}'))
        self.assertFalse(kh.is_auth_failure("claude", 529, "overloaded"))
        self.assertFalse(kh.is_auth_failure("claude", None, "network error"))


class ProbeTests(unittest.TestCase):
    def setUp(self):
        p = mock.patch.dict(os.environ, {}, clear=True)
        p.start()
        self.addCleanup(p.stop)
        s = mock.patch.object(kh.cfgmod, "_stored_secret", return_value="")
        s.start()
        self.addCleanup(s.stop)

    def _probe(self, cfg, opener):
        return ORIGINAL_PROBE(cfg, opener=opener)

    def test_valid(self):
        seen = {}

        def opener(req, timeout=None):
            seen["url"] = req.full_url
            seen["auth"] = req.get_header("Authorization")
            return _Resp(200)

        self.assertEqual(self._probe({"apiKey": FAKE_XAI}, opener), "valid")
        self.assertEqual(seen["url"], "https://api.x.ai/v1/models")
        self.assertEqual(seen["auth"], f"Bearer {FAKE_XAI}")

    def test_xai_incorrect_key_400_invalid(self):
        def opener(req, timeout=None):
            raise _http_error(req.full_url, 400, '{"error":"Incorrect API key provided."}')

        r = self._probe({"apiKey": FAKE_XAI}, opener)
        self.assertEqual(r, "invalid")
        self.assertNotIn(FAKE_XAI, r)

    def test_claude_401_invalid(self):
        def opener(req, timeout=None):
            self.assertEqual(req.full_url, "https://api.anthropic.com/v1/models")
            self.assertEqual(req.get_header("X-api-key"), FAKE_CLAUDE)
            raise _http_error(req.full_url, 401, '{"error":{"type":"authentication_error"}}')

        cfg = {"provider": "claude", "claudeApiKey": FAKE_CLAUDE}
        self.assertEqual(self._probe(cfg, opener), "invalid")

    def test_network_error_unknown(self):
        def opener(req, timeout=None):
            raise urllib.error.URLError("offline")

        self.assertEqual(self._probe({"apiKey": FAKE_XAI}, opener), "unknown")

    def test_server_error_unknown(self):
        def opener(req, timeout=None):
            raise _http_error(req.full_url, 503, "down")

        self.assertEqual(self._probe({"apiKey": FAKE_XAI}, opener), "unknown")

    def test_missing_key_unknown_no_request(self):
        opener = mock.Mock()
        self.assertEqual(self._probe({"apiKey": ""}, opener), "unknown")
        opener.assert_not_called()


class FlagTests(unittest.TestCase):
    def setUp(self):
        p = mock.patch.dict(os.environ, {}, clear=True)
        p.start()
        self.addCleanup(p.stop)
        s = mock.patch.object(kh.cfgmod, "_stored_secret", return_value="")
        s.start()
        self.addCleanup(s.stop)

    def test_roundtrip(self):
        cfg = {"provider": "xai", "apiKey": FAKE_XAI}
        self.assertFalse(kh.is_key_flagged_invalid(cfg))
        kh.mark_key_invalid(cfg, "xai", 400, "chat rejected key")
        self.assertTrue(kh.is_key_flagged_invalid(cfg))
        self.assertFalse(kh.is_key_flagged_invalid(cfg, "claude"))
        self.assertNotIn(FAKE_XAI, repr(cfg[kh.INVALID_FLAG_KEY]))
        self.assertTrue(kh.clear_key_invalid(cfg, "xai"))
        self.assertNotIn(kh.INVALID_FLAG_KEY, cfg)
        self.assertFalse(kh.clear_key_invalid(cfg, "xai"))

    def test_token_state(self):
        self.assertEqual(kh.provider_token_state({"apiKey": ""}), "missing")
        cfg = {"apiKey": FAKE_XAI}
        self.assertEqual(kh.provider_token_state(cfg), "ok")
        self.assertEqual(kh.provider_token_state(cfg, probe=lambda c: "unknown"), "ok")
        self.assertEqual(kh.provider_token_state(cfg, probe=lambda c: "valid"), "ok")
        self.assertEqual(kh.provider_token_state(cfg, probe=lambda c: "invalid"), "invalid")
        self.assertTrue(kh.is_key_flagged_invalid(cfg))  # persisted on cfg
        # Flag alone (no probe) still reports invalid
        self.assertEqual(kh.provider_token_state(cfg), "invalid")
        # Missing beats flag
        self.assertEqual(
            kh.provider_token_state({"apiKey": "", kh.INVALID_FLAG_KEY: {"xai": {}}}),
            "missing",
        )

    def test_valid_probe_clears_stale_flag(self):
        cfg = {"apiKey": FAKE_XAI}
        kh.mark_key_invalid(cfg, "xai", 401, "x")
        # Flagged → probe is not consulted; caller only probes unflagged keys.
        self.assertEqual(kh.provider_token_state(cfg, probe=lambda c: "valid"), "invalid")
        kh.clear_key_invalid(cfg)
        self.assertEqual(kh.provider_token_state(cfg, probe=lambda c: "valid"), "ok")

    def test_probe_enabled_default(self):
        self.assertTrue(kh.probe_enabled({}))
        self.assertFalse(kh.probe_enabled({"keyProbeOnStartup": False}))

    def test_wizard_new_key_clears_flag(self):
        cfg = {"provider": "xai", "apiKey": "xai-old"}
        kh.mark_key_invalid(cfg, "xai", 400, "x")
        res = wiz.WizardResult(
            status="done", provider="xai", api_key="xai-new-test", key_field="apiKey"
        )
        wiz.apply_wizard_result(cfg, res)
        self.assertEqual(cfg["apiKey"], "xai-new-test")
        self.assertFalse(kh.is_key_flagged_invalid(cfg))

    def test_wizard_finish_later_keeps_flag(self):
        cfg = {"provider": "xai", "apiKey": "xai-old"}
        kh.mark_key_invalid(cfg, "xai", 400, "x")
        wiz.apply_wizard_result(cfg, wiz.WizardResult(status="finish_later"))
        self.assertTrue(kh.is_key_flagged_invalid(cfg))


if __name__ == "__main__":
    unittest.main()
