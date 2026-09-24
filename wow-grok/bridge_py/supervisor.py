"""Restart the bridge on crash; exit 0/2 and Ctrl+C stop cleanly."""
from __future__ import annotations

import signal
import subprocess
import sys
import time
from typing import Sequence


def run_supervised(bridge_argv: Sequence[str] | None = None) -> int:
    """Spawn bridge as a child of this interpreter; restart after 3s on crash."""
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

    # Import-run in-process when possible would block restart; always subprocess.
    cmd = [sys.executable, "-m", "bridge_py.bridge", *(bridge_argv or [])]
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
