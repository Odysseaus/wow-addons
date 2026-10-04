"""Unit tests for bridge_py.claude (no live API)."""
from __future__ import annotations

import io
import json
import os
import unittest
import urllib.error
from unittest import mock

from bridge_py import claude


class TestExtractText(unittest.TestCase):
    def test_text_blocks(self):
        self.assertEqual(
            claude.extract_text(
                {
                    "id": "msg_1",
                    "content": [
                        {"type": "thinking", "thinking": "hidden"},
                        {"type": "text", "text": "hello"},
                        {"type": "text", "text": "world"},
                    ],
                }
            ),
            "hello\nworld",
        )

    def test_string_content_and_empty(self):
        self.assertEqual(claude.extract_text({"content": "plain"}), "plain")
        self.assertEqual(claude.extract_text(None), "")
        self.assertEqual(claude.extract_text({"content": []}), "")
        self.assertEqual(
            claude.extract_text(
                {"content": [{"type": "redacted_thinking", "data": "x"}]}
            ),
            "",
        )


class TestChatMissingKey(unittest.TestCase):
    def test_missing_key(self):
        prev = os.environ.pop("ANTHROPIC_API_KEY", None)
        try:
            with self.assertRaises(claude.ClaudeError) as ctx:
                claude.chat(input="hi", api_key="", previous_response_id="resp_ignored")
            self.assertRegex(str(ctx.exception), r"ANTHROPIC_API_KEY|claudeApiKey")
        finally:
            if prev is not None:
                os.environ["ANTHROPIC_API_KEY"] = prev


class TestChatRequest(unittest.TestCase):
    def test_posts_messages_and_ignores_previous_response_id(self):
        payload = {
            "id": "msg_123",
            "type": "message",
            "content": [{"type": "text", "text": "hello"}],
        }
        raw = json.dumps(payload).encode()

        class FakeResp:
            status = 200

            def read(self):
                return raw

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        captured: dict = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            captured["timeout"] = timeout
            captured["headers"] = {k.lower(): v for k, v in req.header_items()}
            captured["data"] = json.loads(req.data.decode())
            return FakeResp()

        beats = {"n": 0}

        def on_progress():
            beats["n"] += 1

        with mock.patch("bridge_py.claude.urllib.request.urlopen", fake_urlopen):
            out = claude.chat(
                api_key="sk-ant-testkey",
                model="claude-sonnet-4-5",
                api_base="https://api.anthropic.com/",
                input="hi",
                previous_response_id="resp_should_ignore",
                history=[
                    {"role": "user", "content": "earlier"},
                    {"role": "grok", "content": "ok"},
                ],
                system="be brief",
                on_progress=on_progress,
                timeout=12,
            )
        self.assertEqual(out, {"id": "msg_123", "text": "hello"})
        self.assertEqual(captured["url"], "https://api.anthropic.com/v1/messages")
        self.assertEqual(captured["timeout"], 12)
        self.assertGreaterEqual(beats["n"], 1)
        body = captured["data"]
        self.assertNotIn("previous_response_id", body)
        self.assertNotIn("tools", body)
        self.assertEqual(body["model"], "claude-sonnet-4-5")
        self.assertEqual(body["max_tokens"], 8192)
        self.assertEqual(body["system"], "be brief")
        self.assertEqual(
            body["messages"],
            [
                {"role": "user", "content": "earlier"},
                {"role": "assistant", "content": "ok"},
                {"role": "user", "content": "hi"},
            ],
        )
        headers = captured["headers"]
        self.assertEqual(headers.get("x-api-key"), "sk-ant-testkey")
        self.assertEqual(headers.get("anthropic-version"), "2023-06-01")
        self.assertEqual(headers.get("content-type"), "application/json")
        self.assertNotIn("authorization", headers)
        self.assertNotIn("sk-ant-testkey", json.dumps(body))

    def test_http_error_redacts_key(self):
        secret = "sk-ant-api03-SECRETVALUE"
        body = json.dumps(
            {"type": "error", "error": {"type": "authentication_error", "message": f"bad {secret}"}}
        ).encode()
        err = urllib.error.HTTPError(
            url="https://api.anthropic.com/v1/messages",
            code=401,
            msg="unauthorized",
            hdrs=None,
            fp=io.BytesIO(body),
        )

        def fake_urlopen(req, timeout=None):
            raise err

        with mock.patch("bridge_py.claude.urllib.request.urlopen", fake_urlopen):
            with self.assertRaises(claude.ClaudeError) as ctx:
                claude.chat(api_key=secret, input="hi")
        text = str(ctx.exception)
        self.assertNotIn(secret, text)
        self.assertIn("[redacted]", text)
        self.assertEqual(ctx.exception.status, 401)

    def test_no_messages_does_not_call_network(self):
        with mock.patch("bridge_py.claude.urllib.request.urlopen") as urlopen:
            with self.assertRaises(claude.ClaudeError):
                claude.chat(api_key="sk-ant-testkey", input="", history=[])
            urlopen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
