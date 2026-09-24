"""macOS pixel-strip capture stub (intent of bridge/capture-mac.js).

Uses `screencapture` + Pillow sampling when available. Requires Screen Recording
permission for Terminal / the frozen .app in System Settings → Privacy & Security.

On non-macOS this module refuses to run. Full CoreGraphics/Quartz path is a
later milestone; this stub mirrors the JSON-lines stdout protocol.
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from pathlib import Path


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="WoWGrok macOS capture (experimental)")
    ap.add_argument("--cell", type=int, default=4)
    ap.add_argument("--cells", type=int, default=200)
    ap.add_argument("--max-rows", type=int, default=48)
    ap.add_argument("--interval-ms", type=int, default=250)
    ap.add_argument("--process-name", default="WowB")
    ap.add_argument("--test-image", default="")
    args = ap.parse_args(argv)

    if sys.platform != "darwin":
        emit({"error": "capture_mac.py is macOS only. Use capture_win on Windows."})
        return 1

    emit(
        {
            "info": (
                f"experimental mac capture stub; cell={args.cell} cells={args.cells} "
                f"maxRows={args.max_rows}; looking for '{args.process_name}'. "
                "Grant Screen Recording to this process. Full Quartz path TBD."
            )
        }
    )

    # Stub loop: try screencapture of a tiny region if possible; otherwise idle.
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        emit({"warn": "Pillow not installed; capture decode disabled until pip install Pillow"})

    while True:
        # Live window find + screencapture is Mac-only and needs accessibility;
        # for this milestone we only keep the process alive so the bridge can attach.
        time.sleep(max(args.interval_ms, 250) / 1000.0)
        # No frame yet — bridge will fall back to SavedVariables poll.

if __name__ == "__main__":
    raise SystemExit(main())
