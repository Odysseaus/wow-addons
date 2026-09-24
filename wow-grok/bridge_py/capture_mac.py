"""macOS pixel-strip capture (port of bridge/capture-mac.js).

Strategy: osascript (JXA + CoreGraphics) locates the Forever / World of Warcraft
window, then `screencapture -R` grabs the top-left strip. Retina: macOS reports
window bounds in points; screencapture writes a PNG in pixels. If
backingScaleFactor is 2 (or the PNG is 2× the requested point size), cells are
sampled at cellPx * scale via Pillow (see strip_codec).

**Screen Recording permission (required):**
  System Settings → Privacy & Security → Screen Recording → enable WoWGrok.app
  (or Terminal/iTerm when running from source) — then Quit and reopen the app.
  Probe/request use a real in-process 1×1 capture (CGWindowListCreateImage) so
  TCC attributes to WoWGrok and creates a Settings row — a non-null window list
  alone is NOT treated as granted. Info.plist must include
  NSScreenCaptureUsageDescription. SavedVariables `/reload` fallback still works
  when capture is blocked.

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


def _load_cg_cf() -> tuple[object, object]:
    """Load CoreGraphics + CoreFoundation CDLLs."""
    import ctypes
    import ctypes.util

    cg_path = ctypes.util.find_library("CoreGraphics") or (
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    )
    cf_path = ctypes.util.find_library("CoreFoundation") or (
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )
    return ctypes.CDLL(cg_path), ctypes.CDLL(cf_path)


def _cg_window_list_copy() -> object | None:
    """In-process ``CGWindowListCopyWindowInfo`` via ctypes (no pyobjc).

    NOTE: a non-null window list is **not** proof of Screen Recording on modern
    macOS — use :func:`_cg_capture_1x1` / :func:`probe_screen_recording` instead.
    Kept for diagnostics / tests. Caller must ``release()`` a non-null return.
    """
    import ctypes

    cg, cf = _load_cg_cf()
    cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
    cg.CGWindowListCopyWindowInfo.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None
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


def _cg_capture_1x1() -> str:
    """Attempt a tiny in-process screen capture (triggers TCC for this process).

    Uses ``CGWindowListCreateImage`` of a 1×1 rect. Returns:
      - ``granted`` — non-null CGImage with width/height >= 1
      - ``denied`` — NULL image (Screen Recording blocked / not determined)
      - ``unsure`` — ctypes / framework load failure

    A non-null ``CGWindowListCopyWindowInfo`` alone must never be treated as granted.
    """
    import ctypes

    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    class CGSize(ctypes.Structure):
        _fields_ = [("width", ctypes.c_double), ("height", ctypes.c_double)]

    class CGRect(ctypes.Structure):
        _fields_ = [("origin", CGPoint), ("size", CGSize)]

    try:
        cg, cf = _load_cg_cf()
    except Exception:  # noqa: BLE001
        return "unsure"

    # kCGWindowImageDefault = 0; capture on-screen windows including desktop
    kCGWindowImageDefault = 0
    cg.CGWindowListCreateImage.argtypes = [
        CGRect,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_uint32,
    ]
    cg.CGWindowListCreateImage.restype = ctypes.c_void_p
    cg.CGImageGetWidth.argtypes = [ctypes.c_void_p]
    cg.CGImageGetWidth.restype = ctypes.c_size_t
    cg.CGImageGetHeight.argtypes = [ctypes.c_void_p]
    cg.CGImageGetHeight.restype = ctypes.c_size_t
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None

    rect = CGRect(CGPoint(0.0, 0.0), CGSize(1.0, 1.0))
    try:
        img = cg.CGWindowListCreateImage(
            rect,
            _kCGWindowListOptionOnScreenOnly,
            _kCGNullWindowID,
            kCGWindowImageDefault,
        )
    except Exception:  # noqa: BLE001
        return "unsure"
    if not img:
        return "denied"
    try:
        w = int(cg.CGImageGetWidth(img))
        h = int(cg.CGImageGetHeight(img))
    except Exception:  # noqa: BLE001
        try:
            cf.CFRelease(img)
        except Exception:  # noqa: BLE001
            pass
        return "unsure"
    try:
        cf.CFRelease(img)
    except Exception:  # noqa: BLE001
        pass
    if w >= 1 and h >= 1:
        return "granted"
    return "denied"


def _screencapture_1x1_probe() -> str:
    """Fallback: ``screencapture -x -R`` of 1×1 must produce a non-empty PNG."""
    import tempfile

    dest = Path(tempfile.gettempdir()) / "wow-grok-tcc-probe.png"
    try:
        if dest.exists():
            dest.unlink()
    except OSError:
        pass
    try:
        r = subprocess.run(
            ["screencapture", "-x", "-t", "png", "-R", "0,0,1,1", str(dest)],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return "unsure"
    if r.returncode != 0:
        return "denied"
    try:
        if dest.is_file() and dest.stat().st_size >= 50:
            return "granted"
    except OSError:
        return "unsure"
    return "denied"


def probe_screen_recording() -> str:
    """Real in-process capture probe for *this* app's Screen Recording TCC.

    Returns:
      - ``granted`` — tiny ``CGWindowListCreateImage`` (or screencapture fallback)
        produced a real image
      - ``denied`` — capture returned NULL / empty (blocked or not determined)
      - ``unsure`` — framework load / tool failure

    **Never** treat a non-null ``CGWindowListCopyWindowInfo`` alone as granted —
    modern macOS often returns a window list without Screen Recording, which
    previously skipped the first-run sheet and never created a Settings row.

    Never call in a tight loop — each real capture can re-trigger the TCC sheet.
    """
    if sys.platform != "darwin":
        return "unsure"
    try:
        status = _cg_capture_1x1()
    except Exception:  # noqa: BLE001
        status = "unsure"
    if status != "unsure":
        return status
    try:
        return _screencapture_1x1_probe()
    except Exception:  # noqa: BLE001
        return "unsure"


def request_screen_recording() -> str:
    """Real in-process capture so macOS creates a Screen Recording row for WoWGrok.

    Calls the same 1×1 ``CGWindowListCreateImage`` path as the probe (with
    screencapture fallback). May surface the system TCC prompt once when
    ``NSScreenCaptureUsageDescription`` is present in Info.plist. Returns
    ``granted`` / ``denied`` / ``unsure``. Do not call in a tight loop.
    """
    return probe_screen_recording()


def is_capture_permission_failure(msg: str) -> bool:
    """True when *msg* indicates Screen Recording / TCC / screencapture denial.

    Used by :func:`live_loop` to exit permanently (code 42) instead of
    sleep-and-retry, which re-triggers macOS "Open System Settings" spam —
    especially after an unsigned app replace that thrash-resets TCC.

    Exact match class (immediate exit): ``could not create image from rect``.
    Also empty capture, permission denied, window-list blocked, etc.
    """
    low = (msg or "").lower()
    if not low.strip():
        return False
    needles = (
        "could not create image from rect",
        "screen recording",
        "null_list",
        "blocked window list",
        "produced no image",
        "permission denied",
        "not authorized to capture",
        "not permitted to capture",
        "capture permission",
        "screencapture failed",
        "failed to capture",
        "unable to capture",
        "cannot capture",
    )
    return any(n in low for n in needles)


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
    # Consecutive strip-capture failures of the TCC/permission class (non-exact).
    # Exact "could not create image from rect" exits immediately (count unused).
    perm_fail_streak = 0
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
            perm_fail_streak = 0
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
            # Screen Recording / TCC / screencapture denial: stop permanently
            # (bridge will not restart). Do not sleep-and-retry — that re-triggers
            # the system "Open System Settings / Deny" sheet (unsigned-replace TCC thrash).
            low = m.lower()
            exact_rect = "could not create image from rect" in low
            if exact_rect or is_capture_permission_failure(m):
                perm_fail_streak += 1
                # Prefer immediate exit on the known screencapture TCC string;
                # other permission-class failures exit after 1–2 consecutive hits.
                if exact_rect or perm_fail_streak >= 2 or (
                    perm_fail_streak >= 1
                    and any(
                        n in low
                        for n in (
                            "screen recording",
                            "null_list",
                            "blocked window list",
                            "produced no image",
                            "permission denied",
                            "not authorized to capture",
                            "not permitted to capture",
                        )
                    )
                ):
                    return _permission_error(
                        m
                        + " Enable WoWGrok under Screen Recording, then Quit and reopen WoWGrok."
                    )
                now = time.time()
                if now - last_warn > 5:
                    last_warn = now
                    emit({"error": m + " (permission-class; one more will stop capture)"})
                time.sleep(1)
                continue
            perm_fail_streak = 0
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
