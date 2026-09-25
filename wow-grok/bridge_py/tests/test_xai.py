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



class TestInstructionsEveryTurn(unittest.TestCase):
    def test_post_response_sends_instructions_with_previous(self):
        """instructions must go out even when previous_response_id is set."""
        captured = {}

        class FakeResp:
            status = 200

            def read(self):
                return b'{"id": "resp_1", "output_text": "ok"}'

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        def fake_urlopen(req, timeout=None):
            import json
            captured["body"] = json.loads(req.data.decode("utf-8"))
            return FakeResp()

        import urllib.request
        prev = urllib.request.urlopen
        urllib.request.urlopen = fake_urlopen
        try:
            out = xai.post_response(
                api_key="test-key",
                input="hello again",
                previous_response_id="resp_prev",
                system="Character: Bob\nLocation: Elwynn",
            )
        finally:
            urllib.request.urlopen = prev
        self.assertEqual(out["id"], "resp_1")
        self.assertEqual(captured["body"]["previous_response_id"], "resp_prev")
        self.assertEqual(captured["body"]["instructions"], "Character: Bob\nLocation: Elwynn")
        self.assertEqual(captured["body"]["input"], "hello again")

    def test_post_response_instructions_only_on_first_turn(self):
        captured = {}

        class FakeResp:
            status = 200

            def read(self):
                return b'{"id": "resp_2", "output_text": "hi"}'

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        def fake_urlopen(req, timeout=None):
            import json
            captured["body"] = json.loads(req.data.decode("utf-8"))
            return FakeResp()

        import urllib.request
        prev = urllib.request.urlopen
        urllib.request.urlopen = fake_urlopen
        try:
            xai.post_response(
                api_key="test-key",
                input="hi",
                system="Game: Forever",
            )
        finally:
            urllib.request.urlopen = prev
        self.assertNotIn("previous_response_id", captured["body"])
        self.assertEqual(captured["body"]["instructions"], "Game: Forever")

    def test_with_game_context_prefix(self):
        out = xai.with_game_context_prefix("ask", "Character: Bob")
        self.assertTrue(out.startswith("[Game context]\nCharacter: Bob"))
        self.assertIn("ask", out)
        self.assertEqual(xai.with_game_context_prefix("ask", ""), "ask")
        self.assertEqual(xai.with_game_context_prefix("ask", None), "ask")




class TestResponseTools(unittest.TestCase):
    def test_response_tools_defaults_to_web_only(self):
        self.assertEqual(xai.response_tools(), [{"type": "web_search"}])

    def test_response_tools_both_enabled(self):
        tools = xai.response_tools(web_search=True, x_search=True)
        self.assertEqual(tools, [{"type": "web_search"}, {"type": "x_search"}])

    def test_response_tools_x_only(self):
        tools = xai.response_tools(web_search=False, x_search=True)
        self.assertEqual(tools, [{"type": "x_search"}])

    def test_response_tools_web_only(self):
        tools = xai.response_tools(web_search=True, x_search=False)
        self.assertEqual(tools, [{"type": "web_search"}])

    def test_response_tools_none(self):
        self.assertEqual(xai.response_tools(web_search=False, x_search=False), [])


class TestPostResponseTools(unittest.TestCase):
    def _fake_urlopen(self, captured):
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

    def test_post_response_includes_tools_when_enabled(self):
        captured = {}
        import urllib.request
        prev = urllib.request.urlopen
        urllib.request.urlopen = self._fake_urlopen(captured)
        try:
            tools = xai.response_tools(web_search=True, x_search=True)
            xai.post_response(api_key="test-key", input="hi", tools=tools)
        finally:
            urllib.request.urlopen = prev
        self.assertEqual(
            captured["body"]["tools"],
            [{"type": "web_search"}, {"type": "x_search"}],
        )

    def test_post_response_omits_tools_when_none(self):
        captured = {}
        import urllib.request
        prev = urllib.request.urlopen
        urllib.request.urlopen = self._fake_urlopen(captured)
        try:
            xai.post_response(api_key="test-key", input="hi", tools=None)
        finally:
            urllib.request.urlopen = prev
        self.assertNotIn("tools", captured["body"])

    def test_post_response_omits_tools_when_empty(self):
        captured = {}
        import urllib.request
        prev = urllib.request.urlopen
        urllib.request.urlopen = self._fake_urlopen(captured)
        try:
            xai.post_response(api_key="test-key", input="hi", tools=[])
        finally:
            urllib.request.urlopen = prev
        self.assertNotIn("tools", captured["body"])

    def test_chat_passes_tools(self):
        captured = {}
        import urllib.request
        prev = urllib.request.urlopen
        urllib.request.urlopen = self._fake_urlopen(captured)
        try:
            tools = [{"type": "x_search"}]
            xai.chat(api_key="test-key", input="hi", tools=tools)
        finally:
            urllib.request.urlopen = prev
        self.assertEqual(captured["body"]["tools"], [{"type": "x_search"}])


if __name__ == "__main__":
    unittest.main()
