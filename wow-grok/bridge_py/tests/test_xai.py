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
