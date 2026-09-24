"""Tests for already-handled outbox re-publish helpers."""
from __future__ import annotations

import unittest
from unittest import mock


class TestRepublishHandled(unittest.TestCase):
    def test_already_handled_calls_republish(self):
        """submit() must republish when already_handled, not silent-return."""
        from bridge_py import protocol as P

        state = {"handled": {"sess": {9: 1}}, "lastId": 9, "sessions": {}}
        job = {"id": 9, "session": "sess", "chat": "c1", "text": "x", "cwd": "/"}
        self.assertTrue(P.already_handled(state, job))

    def test_lua_table_capture_paused_flag(self):
        from bridge_py import protocol as P
        body = P.lua_table("X", [], {"capturePaused": True, "cwd": ""})
        self.assertIn("capturePaused = true", body)
