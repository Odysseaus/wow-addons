"""Light unit tests for game-context helpers (no live capture/API)."""
from __future__ import annotations

import unittest

from bridge_py import protocol as P


class TestSystemPromptWiring(unittest.TestCase):
    def test_empty_when_no_context(self):
        self.assertEqual(P.system_prompt(""), "")

    def test_injects_character_line(self):
        sp = P.system_prompt("Character: Alice\nLocation: Stormwind")
        self.assertIn("Alice", sp)
        self.assertIn("Stormwind", sp)


if __name__ == "__main__":
    unittest.main()
