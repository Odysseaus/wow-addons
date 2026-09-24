"""Unit tests for bridge_py.protocol (mirrors tests/bridge_test.js)."""
from __future__ import annotations

import os
import unittest
from pathlib import Path

from bridge_py import protocol as P


class TestLuaStr(unittest.TestCase):
    def test_escapes(self):
        self.assertEqual(P.lua_str('a"b\\c\nd\re\x01'), '"a\\"b\\\\c\\nde\\001"')
        self.assertEqual(P.lua_str(None), '""')
        self.assertEqual(P.lua_str(42), '"42"')


class TestFlagsAndJobs(unittest.TestCase):
    def test_parse_flags(self):
        self.assertEqual(
            P.parse_flags(""),
            {"newSession": False, "hello": False, "forget": False, "allow": []},
        )
        self.assertEqual(
            P.parse_flags("n"),
            {"newSession": True, "hello": False, "forget": False, "allow": []},
        )
        self.assertEqual(
            P.parse_flags("h"),
            {"newSession": False, "hello": True, "forget": False, "allow": []},
        )
        self.assertEqual(
            P.parse_flags("d"),
            {"newSession": False, "hello": False, "forget": True, "allow": []},
        )
        self.assertEqual(
            P.parse_flags("n;allow=WebSearch, Bash(git:*),"),
            {
                "newSession": True,
                "hello": False,
                "forget": False,
                "allow": ["WebSearch", "Bash(git:*)"],
            },
        )

    def test_jobs_current(self):
        rec = "\x1f".join(
            ["sess", "chat1", "12", "realms", "allow=WebSearch", "My chat", "hello\x1fworld"]
        )
        jobs = P.jobs_from_strip(12, rec)
        self.assertEqual(len(jobs), 1)
        self.assertEqual(jobs[0]["session"], "sess")
        self.assertEqual(jobs[0]["chat"], "chat1")
        self.assertEqual(jobs[0]["id"], 12)
        self.assertEqual(jobs[0]["text"], "hello\x1fworld")
        self.assertEqual(jobs[0]["allow"], ["WebSearch"])
        self.assertEqual(jobs[0]["name"], "My chat")

    def test_jobs_legacy(self):
        a = "\x1f".join(["s", "c1", "3", "", "", "A", "first"])
        b = "\x1f".join(["s", "c2", "4", "C:\\x", "n", "second"])
        c = "\x1f".join(["s", "C:\\y", "", "third"])
        jobs = P.jobs_from_strip(9, "\x1e".join([a, b, c]))
        self.assertEqual(
            [(j["id"], j["chat"], j["text"], j["newSession"]) for j in jobs],
            [(3, "c1", "first", False), (4, "c2", "second", True), (9, "", "third", False)],
        )
        self.assertEqual(P.jobs_from_strip(1, "garbage"), [])


class TestOutbox(unittest.TestCase):
    def test_parse_outbox(self):
        def hex_enc(s: str) -> str:
            return s.encode("utf-8").hex()

        src = (
            'WoWGrokDB = {\n["outbox"] = {\n'
            '["id"] = 7,\n["session"] = "abc123",\n["chat"] = "c1",\n'
            f'["text"] = "{hex_enc("héllo")}",\n'
            f'["cwd"] = "{hex_enc("realms")}",\n'
            '["newSession"] = true,\n},\n["settings"] = {},\n}'
        )
        self.assertEqual(
            P.parse_outbox(src),
            {
                "id": 7,
                "session": "abc123",
                "chat": "c1",
                "text": "héllo",
                "cwd": "realms",
                "newSession": True,
                "via": "reload",
            },
        )
        self.assertIsNone(P.parse_outbox("WoWGrokDB = {}"))
        self.assertIsNone(P.parse_outbox('["outbox"] = { ["text"] = "" }'))


class TestCwd(unittest.TestCase):
    def test_resolve(self):
        base = str(Path("/work/proj").resolve()) if os.name != "nt" else str(Path(r"C:\work\proj").resolve())
        self.assertEqual(P.resolve_cwd("", base), base)
        self.assertEqual(P.resolve_cwd("  ", base), base)
        self.assertEqual(P.resolve_cwd("realms", base), str(Path(base) / "realms"))
        self.assertEqual(P.resolve_cwd("~/x", base), str(Path.home() / "x"))
        if os.name != "nt":
            self.assertEqual(P.resolve_cwd("/elsewhere", base), str(Path("/elsewhere").resolve()))
            self.assertTrue(P.same_folder("/A/b/", "/A/b"))
            self.assertFalse(P.same_folder("/a", "/a/b"))


class TestTools(unittest.TestCase):
    def test_rule_for(self):
        self.assertEqual(P.rule_for({"tool_name": "WebSearch"}), "WebSearch")
        self.assertEqual(
            P.rule_for({"tool_name": "Bash", "tool_input": {"command": "cargo build --release"}}),
            "Bash(cargo:*)",
        )
        self.assertEqual(P.rule_for({}), "Unknown")

    def test_describe(self):
        self.assertEqual(
            P.describe_tool_use({"name": "Bash", "input": {"command": "npm test\nsecond"}}),
            "$ npm test",
        )
        self.assertEqual(
            P.describe_tool_use({"name": "Edit", "input": {"file_path": r"C:\x\player.gd"}}),
            "edit player.gd",
        )


class TestHandled(unittest.TestCase):
    def test_handled_and_prune(self):
        state = {"lastId": 0, "handled": {}, "sessions": {}}
        job = {"session": "s1", "id": 5}
        self.assertFalse(P.already_handled(state, job))
        P.mark_handled(state, job, 1000)
        self.assertTrue(P.already_handled(state, job))
        self.assertFalse(P.already_handled(state, {"session": "s2", "id": 5}))
        self.assertEqual(state["lastId"], 5)
        self.assertEqual(state["seen"]["s1"], 1000)
        for i in range(1, 1201):
            P.mark_handled(state, {"session": "s1", "id": i})
        self.assertLessEqual(len(state["handled"]["s1"]), 1000)
        self.assertTrue(P.already_handled(state, {"session": "", "id": 3}))
        self.assertFalse(P.already_handled(state, {"session": "", "id": 5000}))

        day = 24 * 3600 * 1000
        now = 100 * day
        state = {
            "lastId": 0,
            "handled": {
                "old": {1: 1},
                "fresh": {1: 1},
                "unknown": {1: 1},
                "": {1: 1},
            },
            "seen": {"old": now - 40 * day, "fresh": now - day},
        }
        transcripts = {"chats": {}, "tokens": {"old": now - 40 * day, "fresh": now}}
        removed = P.prune_stale(state, transcripts, now=now)
        self.assertNotIn("old", state["handled"])
        self.assertIn("fresh", state["handled"])
        self.assertIn("", state["handled"])
        self.assertNotIn("old", transcripts["tokens"])
        self.assertGreaterEqual(removed, 1)


class TestSlots(unittest.TestCase):
    def test_pad_slot_keys(self):
        self.assertEqual(P.pad3(7), "007")
        self.assertEqual(P.slot_number(1, 200), 1)
        self.assertEqual(P.slot_number(200, 200), 200)
        self.assertEqual(P.slot_number(201, 200), 1)
        self.assertEqual(P.chat_key({"session": "s", "chat": "c"}), "s:c")
        self.assertEqual(P.sess_key({"chat": "c", "session": "s"}), "chat:c")


class TestSilentWav(unittest.TestCase):
    def test_wav(self):
        self.assertEqual(len(P.SILENT_WAV), 124)
        self.assertTrue(P.SILENT_WAV.startswith(b"RIFF"))


if __name__ == "__main__":
    unittest.main()
