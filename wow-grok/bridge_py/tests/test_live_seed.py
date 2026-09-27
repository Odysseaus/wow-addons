"""Tests for live_put LRU + transcript seed (stuck multi-chat Inbox recovery)."""
from __future__ import annotations

import unittest

from bridge_py import protocol as P


class TestLivePut(unittest.TestCase):
    def test_update_moves_key_to_end(self):
        live: dict = {}
        P.live_put(live, "s:a", {"chat": "a", "id": 1, "status": "done", "text": "A"})
        P.live_put(live, "s:b", {"chat": "b", "id": 2, "status": "working", "text": "…"})
        # Re-publish A (done) — must become most recent so values()[-1] is A
        P.live_put(live, "s:a", {"chat": "a", "id": 1, "status": "done", "text": "A2"})
        self.assertEqual([r["chat"] for r in live.values()], ["b", "a"])
        self.assertEqual(list(live.values())[-1]["text"], "A2")

    def test_tail_keeps_refreshed_old_chat_among_many(self):
        live: dict = {}
        for i in range(35):
            P.live_put(
                live,
                f"s:c{i}",
                {"chat": f"c{i}", "id": i, "status": "done", "text": f"t{i}"},
            )
        # Refresh the oldest chat — without live_put it would fall out of [-30:]
        P.live_put(
            live,
            "s:c0",
            {"chat": "c0", "id": 0, "status": "done", "text": "rescued"},
        )
        published = list(live.values())[-30:]
        chats = {r["chat"] for r in published}
        self.assertIn("c0", chats)
        self.assertNotIn("c1", chats)  # still near the front, outside the tail
        self.assertEqual(published[-1]["text"], "rescued")


class TestSeedLiveFromTranscripts(unittest.TestCase):
    def test_hello_reseeds_all_recent_chats(self):
        live: dict = {
            "old:recipes": {
                "chat": "recipes",
                "id": 193,
                "status": "working",
                "text": "Thinking…",
            }
        }
        transcripts = {
            "chats": {
                "itemhunt": {
                    "id": "itemhunt",
                    "cwd": "/x",
                    "updated": 2000,
                    "messages": [
                        {"role": "user", "id": 191, "text": "stave?"},
                        {"role": "assistant", "id": 191, "text": "Golemheart answer"},
                    ],
                },
                "recipes": {
                    "id": "recipes",
                    "cwd": "/x",
                    "updated": 3000,
                    "messages": [
                        {"role": "user", "id": 193, "text": "hello"},
                        {"role": "assistant", "id": 193, "text": "hi back"},
                    ],
                },
            }
        }
        state = {"sessions": {"chat:itemhunt": "resp1", "chat:recipes": "resp2"}}
        n = P.seed_live_from_transcripts(live, transcripts, state, session="sess")
        self.assertEqual(n, 2)
        # Both chats present under hello session; recipes no longer only "working"
        by_chat = {r["chat"]: r for r in live.values()}
        self.assertEqual(by_chat["itemhunt"]["id"], 191)
        self.assertEqual(by_chat["itemhunt"]["status"], "done")
        self.assertEqual(by_chat["itemhunt"]["text"], "Golemheart answer")
        self.assertEqual(by_chat["recipes"]["status"], "done")
        self.assertEqual(by_chat["recipes"]["text"], "hi back")
        # Keys use hello session
        self.assertIn("sess:itemhunt", live)
        self.assertIn("sess:recipes", live)
        # Published tail includes both (only 2)
        published = list(live.values())[-30:]
        self.assertEqual({r["chat"] for r in published}, {"itemhunt", "recipes"})

    def test_skips_chats_without_assistant(self):
        live: dict = {}
        transcripts = {
            "chats": {
                "onlyuser": {
                    "id": "onlyuser",
                    "updated": 1,
                    "messages": [{"role": "user", "id": 1, "text": "hi"}],
                }
            }
        }
        self.assertEqual(P.seed_live_from_transcripts(live, transcripts, {}, "s"), 0)
        self.assertEqual(live, {})


if __name__ == "__main__":
    unittest.main()
