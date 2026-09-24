"""macOS pixel-strip capture (port of bridge/capture-mac.js).

Strategy: osascript (JXA + CoreGraphics) locates the Forever / World of Warcraft
window, then `screencapture -R` grabs the top-left strip. Retina: macOS reports
window bounds in points; screencapture writes a PNG in pixels. If
backingScaleFactor is 2 (or the PNG is 2× the requested point size), cells are
sampled at cellPx * scale via Pillow (see strip_codec).

**Screen Recording permission (required):**
  System Settings → Privacy & Security → Screen Recording → enable WoWGrok.app
  (or Terminal/iTerm when running from source) — then Quit and reopen the app.
  Probe/request use in-process CoreGraphics so TCC attributes to WoWGrok, not osascript.
Without it, CGWindowListCopyWindowInfo returns null and screencapture may
produce an empty image. SavedVariables `/reload` fallback in the bridge still
works when capture is blocked.

On non-macOS, `--test-image` still decodes synthetic PNGs (unit tests). Live
capture refuses to run off darwin. Prefer stdlib + Pillow; no pyobjc.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

try:
    from . import strip_codec
except ImportError:  # pragma: no cover
    from bridge_py import strip_codec  # type: ignore


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


# Bridge treats this exit code as "do not restart capture" (TCC / Screen Recording).
PERMISSION_EXIT = 42


# CGWindowList option / null window id (CoreGraphics).
_kCGWindowListOptionOnScreenOnly = 1 << 0  # 1
_kCGNullWindowID = 0


def _cg_window_list_copy() -> object | None:
    """In-process ``CGWindowListCopyWindowInfo`` via ctypes (no pyobjc).

    Runs as *this* process (WoWGrok.app when frozen), so TCC attributes Screen
    Recording to WoWGrok — unlike osascript/JXA which probes as osascript.
    Returns the CFArrayRef pointer (c_void_p value) or None if NULL / load fail.
    Caller must CFRelease a non-null return.
    """
    import ctypes
    import ctypes.util

    cg_path = ctypes.util.find_library("CoreGraphics") or (
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    )
    cf_path = ctypes.util.find_library("CoreFoundation") or (
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )
    cg = ctypes.CDLL(cg_path)
    cf = ctypes.CDLL(cf_path)
    cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
    cg.CGWindowListCopyWindowInfo.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None
    # Stash CFRelease on the pointer object for the caller via a small wrapper.
    ptr = cg.CGWindowListCopyWindowInfo(
        _kCGWindowListOptionOnScreenOnly, _kCGNullWindowID
    )
    if not ptr:
        return None

    class _CFArray:
        __slots__ = ("_ptr", "_cf")

        def __init__(self, p: int, coref: object) -> None:
            self._ptr = p
            self._cf = coref

        def release(self) -> None:
            if self._ptr:
                self._cf.CFRelease(self._ptr)
                self._ptr = 0

    return _CFArray(ptr, cf)


def probe_screen_recording() -> str:
    """One-shot in-process CGWindowList probe for *this* app's TCC state.

    Returns:
      - ``granted`` — CoreGraphics returned a non-null window list
      - ``denied`` — CoreGraphics returned NULL (Screen Recording blocked)
      - ``unsure`` — library load / ctypes failure (never treat osascript success
        as granted for WoWGrok)

    Never call this in a tight loop — each real screen-access attempt can
    re-trigger the TCC sheet. Prefer ``request_screen_recording`` once at first run.
    """
    if sys.platform != "darwin":
        return "unsure"
    try:
        arr = _cg_window_list_copy()
    except Exception:  # noqa: BLE001 — load / ABI failure
        return "unsure"
    if arr is None:
        return "denied"
    try:
        arr.release()
    except Exception:  # noqa: BLE001
        pass
    return "granted"


def request_screen_recording() -> str:
    """Perform a real in-process screen-access attempt so macOS lists WoWGrok.

    Uses the same CoreGraphics ``CGWindowListCopyWindowInfo`` call as the probe.
    This may surface the system TCC prompt once and should create a Screen
    Recording row for WoWGrok.app under System Settings. Returns the resulting
    status (``granted`` / ``denied`` / ``unsure``). Do not call in a tight loop.
    """
    return probe_screen_recording()


def _permission_error(msg: str) -> int:
    emit(
        {
            "permission": "screen_recording",
            "error": msg,
        }
    )
    return PERMISSION_EXIT



def _run_osascript(args: list[str], timeout_ms: int = 2500) -> str:
    r = subprocess.run(
        ["osascript", *args],
        capture_output=True,
        text=True,
        timeout=timeout_ms / 1000.0,
    )
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip() or f"osascript exit {r.returncode}"
        raise RuntimeError(msg)
    return (r.stdout or "").strip()


def backing_scale_factor() -> float:
    try:
        out = _run_osascript(
            [
                "-l",
                "JavaScript",
                "-e",
                'ObjC.import("AppKit"); $.NSScreen.mainScreen.backingScaleFactor',
            ],
            timeout_ms=2000,
        )
        n = float(out)
        return n if n > 0 else 1.0
    except (RuntimeError, ValueError, subprocess.TimeoutExpired, FileNotFoundError):
        return 1.0


def find_wow_window(process_name: str) -> dict[str, Any] | None:
    """Locate on-screen WoW / Forever window via CoreGraphics (needs Screen Recording)."""
    want: list[str] = []

    def add(n: str) -> None:
        low = str(n).lower()
        if n and low not in want:
            want.append(low)

    add(process_name)
    add("World of Warcraft Beta")
    add("WowB")
    add("World of Warcraft")
    add("WowClassic")
    # bare "Wow" substring-matches WoWGrok — omit it

    want_json = json.dumps(want)
    jxa = f"""
ObjC.import('CoreGraphics');
ObjC.import('Foundation');
var opts = $.kCGWindowListOptionOnScreenOnly;
var cfArr = $.CGWindowListCopyWindowInfo(opts, $.kCGNullWindowID);
if (!cfArr) {{
  'NULL_LIST';
}} else {{
  var js = ObjC.deepUnwrap(ObjC.castRefToObject(cfArr)) || [];
  var want = {want_json};
  var hits = [];
  for (var i = 0; i < js.length; i++) {{
    var w = js[i];
    var owner = w.kCGWindowOwnerName || '';
    if ((w.kCGWindowLayer || 0) !== 0) continue;
    var low = String(owner).toLowerCase();
    if (low.indexOf('wowgrok') >= 0) continue;
    var ok = false;
    for (var j = 0; j < want.length; j++) {{
      if (low === want[j] || low.indexOf(want[j]) >= 0 || want[j].indexOf(low) >= 0) {{ ok = true; break; }}
    }}
    if (!ok) {{
      if (low.indexOf('warcraft') < 0 && low.indexOf('wowb') < 0) continue;
    }}
    var b = w.kCGWindowBounds || {{}};
    if (!(b.Width > 100 && b.Height > 100)) continue;
    hits.push([owner, b.X|0, b.Y|0, b.Width|0, b.Height|0].join('\\t'));
  }}
  hits[0] || '';
}}
"""
    out = _run_osascript(["-l", "JavaScript", "-e", jxa], timeout_ms=2500)
    if out == "NULL_LIST":
        raise RuntimeError(
            "Screen Recording blocked window list — System Settings → Privacy & Security "
            "→ Screen Recording → enable WoWGrok.app, then Quit and reopen WoWGrok"
        )
    if not out:
        return None
    parts = out.split("\t")
    if len(parts) < 5:
        return None
    return {
        "name": parts[0],
        "x": int(parts[1]),
        "y": int(parts[2]),
        "w": int(parts[3]),
        "h": int(parts[4]),
    }


def capture_region(x: float, y: float, w: float, h: float, dest: str | Path) -> None:
    dest_s = str(dest)
    region = f"{int(round(x))},{int(round(y))},{int(round(w))},{int(round(h))}"
    r = subprocess.run(
        ["screencapture", "-x", "-t", "png", "-R", region, dest_s],
        capture_output=True,
        text=True,
        timeout=8,
    )
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "screencapture failed").strip() or "screencapture failed")
    p = Path(dest_s)
    if not p.is_file() or p.stat().st_size < 50:
        raise RuntimeError(
            "screencapture produced no image (grant Screen Recording to Terminal / "
            "the frozen app in System Settings → Privacy & Security)"
        )


def _decode_captured(dest: Path, cell: int, cells: int, max_rows: int, scale_hint: float) -> dict[str, Any]:
    from PIL import Image

    img = Image.open(dest).convert("RGB")
    scale = strip_codec.infer_scale(img.width, cells=cells, cell=cell, scale_hint=scale_hint)
    msg = strip_codec.decode_strip(img, cell=cell, cells=cells, max_rows=max_rows, scale=scale)
    return {"msg": msg, "width": img.width, "height": img.height, "scale": scale}


def live_loop(args: argparse.Namespace) -> int:
    dest = Path(tempfile.gettempdir()) / "wow-grok-strip.png"
    last_key = ""
    last_warn = 0.0
    attached_name = ""
    told_scale = False
    cap_w = args.cells * args.cell
    cap_h = args.max_rows * args.cell

    # Probe ONCE in-process. denied *and* unsure are permission failures — do not
    # pretend capture works. Never tight-loop request_screen_recording here; first
    # run already requested once so TCC can create the Settings row.
    status = probe_screen_recording()
    if status != "granted":
        return _permission_error(
            "Screen Recording is not available to this WoWGrok process "
            f"(probe={status}). "
            "System Settings → Privacy & Security → Screen Recording → enable WoWGrok, "
            "then Quit WoWGrok completely and reopen it. "
            "(SavedVariables /reload still works without capture.)"
        )

    declared_scale = backing_scale_factor()
    emit(
        {
            "info": (
                f"experimental mac capture; backingScaleFactor={declared_scale}; "
                f"region {cap_w}x{cap_h} points; looking for '{args.process_name}'."
            )
        }
    )

    while True:
        try:
            win = find_wow_window(args.process_name)
            if not win:
                attached_name = ""
                now = time.time()
                if now - last_warn > 10:
                    last_warn = now
                    emit(
                        {
                            "info": (
                                f"waiting for Forever window (looked for '{args.process_name}' "
                                "and WowB / World of Warcraft). Is the game windowed/borderless "
                                "and on-screen?"
                            )
                        }
                    )
                time.sleep(2)
                continue
            if attached_name != win["name"]:
                attached_name = win["name"]
                emit(
                    {
                        "info": (
                            f"attached to '{win['name']}' at {win['x']},{win['y']} "
                            f"{win['w']}x{win['h']}"
                        )
                    }
                )
            capture_region(win["x"], win["y"], cap_w, cap_h, dest)
            got = _decode_captured(dest, args.cell, args.cells, args.max_rows, declared_scale)
            if not told_scale:
                told_scale = True
                emit(
                    {
                        "info": (
                            f"capture bitmap {got['width']}x{got['height']} px; "
                            f"sample scale={got['scale']} (cell {args.cell}*{got['scale']} px)"
                        )
                    }
                )
            msg = got["msg"]
            if msg and msg.get("error"):
                now = time.time()
                if now - last_warn >= 5:
                    last_warn = now
                    emit({"warn": "strip seen but rejected: " + str(msg["error"])})
            elif msg and "id" in msg:
                key = f"{msg['id']}:{msg['text']}"
                if key != last_key:
                    last_key = key
                    emit({"id": msg["id"], "text": msg["text"]})
        except Exception as e:  # noqa: BLE001
            m = str(e)
            # Any Screen Recording / TCC failure: stop permanently (bridge will not
            # restart). Do not sleep-and-retry — that re-triggers the system sheet.
            low = m.lower()
            if (
                "screen recording" in low
                or "null_list" in low
                or "blocked window list" in low
                or "produced no image" in low
            ):
                return _permission_error(
                    m
                    + " Enable WoWGrok under Screen Recording, then Quit and reopen WoWGrok."
                )
            now = time.time()
            if now - last_warn > 15:
                last_warn = now
                emit({"error": m})
            time.sleep(3)
            continue
        time.sleep(max(args.interval_ms, 50) / 1000.0)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="WoWGrok macOS capture (experimental). Needs Screen Recording permission."
    )
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

    if sys.platform != "darwin":
        emit({"error": "capture_mac.py is macOS only. Use capture_win on Windows."})
        return 1

    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        emit({"error": "Pillow required: pip install Pillow"})
        return 1

    return live_loop(args)


if __name__ == "__main__":
    raise SystemExit(main())
