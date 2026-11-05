"""Unit tests for bridge_py.xai (no live API)."""
from __future__ import annotations

import os
import unittest

from bridge_py import xai


class TestExtractText(unittest.TestCase):
    def test_prefers_output_text(self):
        self.assertEqual(xai.extract_text({"output_text": "plain"}), "plain")
        self.assertEqual(
            xai.extract_text(
                {
                    "output": [
                        {
                            "type": "message",
                            "role": "assistant",
                            "content": [{"type": "output_text", "text": "from cells"}],
                        }
                    ]
                }
            ),
            "from cells",
        )
        self.assertEqual(
            xai.extract_text(
                {
                    "output": [
                        {"type": "reasoning", "summary": [{"text": "ignored"}]},
                        {
                            "type": "message",
                            "role": "assistant",
                            "content": [
                                {"type": "output_text", "text": "hello"},
                                {"type": "output_text", "text": "world"},
                            ],
                        },
                    ]
                }
            ),
            "hello\nworld",
        )


class TestChatMissingKey(unittest.TestCase):
    def test_missing_key(self):
        prev = os.environ.pop("XAI_API_KEY", None)
        try:
            with self.assertRaises(xai.XAIError) as ctx:
                xai.chat(input="hi", api_key="")
            self.assertRegex(str(ctx.exception), r"XAI_API_KEY|apiKey")
        finally:
            if prev is not None:
                os.environ["XAI_API_KEY"] = prev


if __name__ == "__main__":
    unittest.main()


def _capture_urlopen(captured):
    class FakeResp:
        status = 200

        def read(self):
            return b'{"id": "resp_t", "output_text": "ok"}'

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def fake_urlopen(req, timeout=None):
        import json
        captured["body"] = json.loads(req.data.decode("utf-8"))
        return FakeResp()

    return fake_urlopen


class TestResponseTools(unittest.TestCase):
    def test_defaults_web_and_x(self):
        self.assertEqual(xai.response_tools(), [{"type": "web_search"}, {"type": "x_search"}])

    def test_x_only(self):
        self.assertEqual(xai.response_tools(web_search=False, x_search=True), [{"type": "x_search"}])

    def test_web_only(self):
        self.assertEqual(xai.response_tools(web_search=True, x_search=False), [{"type": "web_search"}])

    def test_none(self):
        self.assertEqual(xai.response_tools(web_search=False, x_search=False), [])

    def test_instruction_points_to_wowhead_forever(self):
        self.assertIn("https://www.wowhead.com/forever", xai.SEARCH_INSTRUCTIONS)


class TestPostResponseTools(unittest.TestCase):
    def _post(self, **kw):
        import urllib.request
        captured = {}
        prev = urllib.request.urlopen
        urllib.request.urlopen = _capture_urlopen(captured)
        try:
            xai.post_response(api_key="test-key", input="hi", **kw)
        finally:
            urllib.request.urlopen = prev
        return captured["body"]

    def test_includes_tools_when_enabled(self):
        body = self._post(tools=xai.response_tools())
        self.assertEqual(body["tools"], [{"type": "web_search"}, {"type": "x_search"}])

    def test_omits_tools_when_none_or_empty(self):
        self.assertNotIn("tools", self._post())
        self.assertNotIn("tools", self._post(tools=[]))

    def test_instructions_sent_on_resumed_turn(self):
        body = self._post(previous_response_id="resp_prev", system="sys")
        self.assertEqual(body["previous_response_id"], "resp_prev")
        self.assertEqual(body["instructions"], "sys")
