"""Windows pixel-strip capture: delegate to bridge/capture.ps1.

Stdout: one JSON object per line (same protocol as capture.ps1 / capture_mac).
Also supports --test-image via strip_codec (pure Python) for decode-only tests
without PowerShell.

Does not invent OMEN / Helper access — packagers build the .exe on a Windows
machine (Windows Helper / OMEN) and ship capture.ps1 beside or inside the bundle.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

try:
    from . import strip_codec
except ImportError:  # pragma: no cover
    from bridge_py import strip_codec  # type: ignore


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def find_capture_ps1() -> Path | None:
    here = Path(__file__).resolve().parent
    meipass = getattr(sys, "_MEIPASS", None)
    candidates = [
        here.parent / "bridge" / "capture.ps1",
        here / "capture.ps1",
        Path(sys.executable).resolve().parent / "bridge" / "capture.ps1",
        Path(sys.executable).resolve().parent / "capture.ps1",
    ]
    if meipass:
        candidates.insert(0, Path(meipass) / "bridge" / "capture.ps1")
        candidates.insert(1, Path(meipass) / "capture.ps1")
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
    ap.add_argument("--test-image", default="")
    args = ap.parse_args(argv)

    if args.test_image:
        try:
            msg = strip_codec.decode_png_file(
                args.test_image,
                cell=args.cell,
                cells=args.cells,
                max_rows=args.max_rows,
            )
            if msg.get("error"):
                emit(msg)
                return 1 if msg["error"] == "no valid strip in image" else 0
            emit({"id": msg["id"], "text": msg["text"]})
            return 0
        except Exception as e:  # noqa: BLE001
            emit({"error": str(e)})
            return 1

    if sys.platform != "win32":
        emit({"error": "capture_win.py is Windows only. Use capture_mac on macOS."})
        return 1

    ps1 = find_capture_ps1()
    if not ps1:
        emit(
            {
                "error": "capture.ps1 not found next to bridge_py / bridge / frozen exe. "
                "Copy bridge/capture.ps1 alongside the frozen exe or bake it with "
                "--add-data (see bridge_py/packaging.md)."
            }
        )
        return 1

    emit({"info": f"delegating to PowerShell {ps1.name} (processName={args.process_name})"})
    # Param names must match capture.ps1: -Cell -Cells -MaxRows -IntervalMs -ProcessName
    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ps1),
        "-Cell",
        str(args.cell),
        "-Cells",
        str(args.cells),
        "-MaxRows",
        str(args.max_rows),
        "-IntervalMs",
        str(args.interval_ms),
        "-ProcessName",
        args.process_name,
    ]
    try:
        return subprocess.call(cmd)
    except FileNotFoundError:
        emit({"error": "powershell.exe not found"})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
