"""0.1.37: recover when the add-on's saved counter goes back (WoW died unsaved).

On 2026-11-16 a WindowServer crash killed WoW before it saved: the add-on came
back with lastSeq 309 while the bridge had handled up to 314, and every hello
was dropped silently (no ack, no log), so Connect said "no answer".
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from bridge_py import protocol as P

ROOT = Path(__file__).resolve().parents[2]  # wow-grok/
SESS = "d92acc52a9fe49"


def _state(last: int = 314) -> dict:
    return {"lastId": 850, "handled": {SESS: {i: 1 for i in range(1, last + 1)}, "b574": {850: 1}}}


def _job(id_: int, hello: bool = False, text: str = "hi") -> dict:
    return {"session": SESS, "chat": "c1", "id": id_, "cwd": "", "hello": hello,
            "forget": False, "text": "" if hello else text, "via": "pixel"}


def _lua() -> str | None:
    for name in (os.environ.get("WOWGROK_LUA") or "", "lua5.1", "lua", "luajit"):
        if name and shutil.which(name):
            return shutil.which(name)
    return None


class RepeatGateTests(unittest.TestCase):
    def test_rewound_hello_is_acked_and_logged_once(self):
        """Hello with an already-handled seq: ack + one 'seq rewind' line."""
        gate, st = P.RepeatGate(), _state()
        action, line = gate.check(st, _job(310, hello=True), now=1000.0)
        self.assertEqual(action, "ack-hello")
        self.assertEqual(
            line,
            f"seq rewind: hello #310@{SESS} already handled (bridge last #314); "
            "acking so the add-on can catch up",
        )
        # Re-read from the strip a tick later: still acked, not logged again.
        self.assertEqual(gate.check(st, _job(310, hello=True), now=1000.3), ("ack-hello", None))
        # The newest seq itself: acked again, not called a rewind.
        self.assertEqual(
            gate.check(st, _job(314, hello=True), now=1001.0),
            ("ack-hello", f"hello #314@{SESS} already handled; acking again"),
        )
        self.assertIsNone(gate.check(st, _job(315, hello=True), now=1002.0))

    def test_duplicate_chat_never_runs_and_is_logged_once(self):
        """Repeated chat job: 'ignore' (never sent to Grok) with one log line."""
        gate, st = P.RepeatGate(), _state()
        self.assertEqual(
            gate.check(st, _job(312, text="where is the flight master"), now=5.0),
            ("ignore", f"duplicate seq 312@{SESS} ignored"),
        )
        for t in (5.25, 6.0, 500.0):
            self.assertEqual(gate.check(st, _job(312), now=t), ("ignore", None))
        self.assertIsNone(gate.check(st, _job(315), now=7.0))

    def test_fresh_repeat_of_a_record_this_run_handled_is_quiet(self):
        """A record still on the strip seconds after we handled it is not news."""
        gate, st = P.RepeatGate(window_s=120.0), _state(313)
        job = _job(314, hello=True)
        self.assertIsNone(gate.check(st, job, now=100.0))
        gate.note(job, now=100.0)
        P.mark_handled(st, job)
        self.assertEqual(gate.check(st, job, now=101.0), ("ack-hello", None))
        chat = _job(315)
        gate.note(chat, now=102.0)
        P.mark_handled(st, chat)
        self.assertEqual(gate.check(st, chat, now=110.0), ("ignore", None))
        # Same seq again long after (e.g. WoW restarted unsaved): logged.
        self.assertEqual(gate.check(st, chat, now=400.0)[1], f"duplicate seq 315@{SESS} ignored")


class SlotDataTests(unittest.TestCase):
    def test_handled_max_and_slot_file_carry_last_seq(self):
        """Slot/Inbox data lists the last handled seq per session."""
        self.assertEqual(P.handled_max(_state()), {SESS: 314, "b574": 850})
        self.assertEqual(P.handled_max({"handled": {"": {3: 1}, "s": {"7": 1, "12": 1}}}), {"s": 12})
        body = P.lua_table("WoWGrok_SlotData", [], {"cwd": "", "seqs": P.handled_max(_state()), "now": 1_763_352_000_000})
        self.assertIn('\tseqs = {\n\t\t["b574"] = 850,\n\t\t["d92acc52a9fe49"] = 314,\n\t},', body)
        self.assertNotIn("seqs", P.lua_table("X", [], {"cwd": ""}))

    def test_bridge_slot_file_wires_seqs(self):
        """bridge.slot_file passes handled_max into the slot data (source check)."""
        src = (ROOT / "bridge_py" / "bridge.py").read_text(encoding="utf-8")
        self.assertIn('"seqs": P.handled_max(state)', src)
        self.assertIn("repeat_gate.check(state, job, now_s)", src)


class AddonLuaTests(unittest.TestCase):
    def test_lua_adopt_seq_and_round_trip(self):
        """Add-on: lastSeq = max(lastSeq, bridge last), incl. the real slot file."""
        lua = _lua()
        if not lua:
            self.skipTest("no Lua interpreter (set WOWGROK_LUA)")
        with tempfile.TemporaryDirectory() as td:
            slot = Path(td) / "Inbox.lua"
            slot.write_text(P.lua_table("WoWGrok_SlotData", [], {"cwd": "", "seqs": P.handled_max(_state())}))
            r = subprocess.run(
                [lua, "addon/tests/seq_test.lua", str(slot), SESS, "314"],
                cwd=ROOT, capture_output=True, text=True, timeout=30,
            )
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("all passed", r.stdout)

    def test_addon_versions_match_app(self):
        """toc and app version agree, so the app's startup sync installs it."""
        from bridge_py import __version__, install_addon as IA

        toc = IA.toc_version(ROOT / "addon" / "WoWGrok" / "WoWGrok.toc")
        self.assertEqual(".".join(map(str, toc)), __version__)


if __name__ == "__main__":
    unittest.main()
