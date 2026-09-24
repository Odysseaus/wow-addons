"""Restart the bridge on crash; exit 0/2 and Ctrl+C stop cleanly."""
from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from typing import Sequence


def _bridge_command(bridge_argv: Sequence[str] | None) -> list[str]:
    """Build argv to run the bridge as a child process.

    Frozen PyInstaller apps are not a CPython interpreter: ``exe -m package``
    does not work and exits immediately (silent when console=False). Re-invoke
    the same binary with ``--no-supervisor`` instead.
    """
    args = list(bridge_argv or [])
    if getattr(sys, "frozen", False):
        return [sys.executable, "--no-supervisor", *args]
    return [sys.executable, "-m", "bridge_py.bridge", *args]


def _stop_child(p: subprocess.Popen) -> None:
    """Terminate the bridge child (and its process group on Unix)."""
    if p.poll() is not None:
        return
    if sys.platform == "win32":
        p.terminate()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()
        return
    # Unix: child was spawned with start_new_session=True → process-group leader.
    try:
        os.killpg(p.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            p.terminate()
        except ProcessLookupError:
            return
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            try:
                p.kill()
            except ProcessLookupError:
                pass
        try:
            p.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def run_supervised(bridge_argv: Sequence[str] | None = None) -> int:
    """Spawn bridge as a child; restart after 3s on crash."""
    stopping = {"v": False}
    child: dict[str, subprocess.Popen | None] = {"p": None}

    def stop(*_args: object) -> None:
        stopping["v"] = True
        p = child["p"]
        if p is not None:
            _stop_child(p)
        sys.exit(0)

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    cmd = _bridge_command(bridge_argv)
    while True:
        popen_kw: dict = {}
        if sys.platform != "win32":
            popen_kw["start_new_session"] = True
        child["p"] = subprocess.Popen(cmd, **popen_kw)
        code = child["p"].wait()
        child["p"] = None
        if stopping["v"]:
            return 0
        if code in (0, 2):
            return code
        print(f"\nbridge exited ({code}); restarting in 3 s", flush=True)
        time.sleep(3)
