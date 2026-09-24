"""Windows pixel-strip capture: prefer PowerShell capture.ps1 for this milestone.

Structured so PyInstaller builds can later embed a pure-Python path.
Stdout: one JSON object per line (same protocol as capture.ps1 / capture-mac.js).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def find_capture_ps1() -> Path | None:
    here = Path(__file__).resolve().parent
    # Prefer sibling Node bridge script during dual-stack period
    candidates = [
        here.parent / "bridge" / "capture.ps1",
        here / "capture.ps1",
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="WoWGrok Windows capture")
    ap.add_argument("--cell", type=int, default=4)
    ap.add_argument("--cells", type=int, default=200)
    ap.add_argument("--max-rows", type=int, default=48)
    ap.add_argument("--interval-ms", type=int, default=250)
    ap.add_argument("--process-name", default="WowB")
    args = ap.parse_args(argv)

    if sys.platform != "win32":
        emit({"error": "capture_win.py is Windows only. Use capture_mac on macOS."})
        return 1

    ps1 = find_capture_ps1()
    if not ps1:
        emit(
            {
                "error": "capture.ps1 not found next to bridge_py / bridge. "
                "Copy bridge/capture.ps1 alongside the frozen exe for now."
            }
        )
        return 1

    emit({"info": f"delegating to PowerShell {ps1.name} (processName={args.process_name})"})
    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ps1),
        "-CellPx",
        str(args.cell),
        "-CellsPerRow",
        str(args.cells),
        "-MaxRows",
        str(args.max_rows),
        "-IntervalMs",
        str(args.interval_ms),
        "-ProcessName",
        args.process_name,
    ]
    # Parameter names may differ in capture.ps1 — fall back to positional-free env
    try:
        return subprocess.call(cmd)
    except FileNotFoundError:
        emit({"error": "powershell.exe not found"})
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
