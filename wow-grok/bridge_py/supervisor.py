"""Restart the bridge on crash; exit 0/2 and Ctrl+C stop cleanly."""
from __future__ import annotations

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


def run_supervised(bridge_argv: Sequence[str] | None = None) -> int:
    """Spawn bridge as a child; restart after 3s on crash."""
    stopping = {"v": False}
    child: dict[str, subprocess.Popen | None] = {"p": None}

    def stop(*_args: object) -> None:
        stopping["v"] = True
        p = child["p"]
        if p and p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
        sys.exit(0)

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    cmd = _bridge_command(bridge_argv)
    while True:
        child["p"] = subprocess.Popen(cmd)
        code = child["p"].wait()
        child["p"] = None
        if stopping["v"]:
            return 0
        if code in (0, 2):
            return code
        print(f"\nbridge exited ({code}); restarting in 3 s", flush=True)
        time.sleep(3)
