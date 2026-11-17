"""macOS pixel-strip capture (port of bridge/capture-mac.js).

Strategy: in-process CoreGraphics (ctypes ``CGWindowListCopyWindowInfo``) locates
the Forever / World of Warcraft window (including kCGWindowNumber); since 0.1.36
no ``osascript`` runs per tick (JXA is only a startup fallback when CoreGraphics
cannot be loaded in-process). Live strip capture prefers in-process
``CGWindowListCreateImage`` keyed by that window id; ``screencapture -l``
(window id + Pillow crop) is preferred alongside CG for fullscreen/ultrawide;
``screencapture -R`` is last resort. Retina: macOS reports window bounds in points; the PNG may be in
pixels. If backingScaleFactor is 2 (or the PNG is 2× the requested point size),
cells are sampled at cellPx * scale via Pillow (see strip_codec).

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
_kCGWindowListOptionIncludingWindow = 1 << 3  # 8
_kCGNullWindowID = 0
_kCGWindowImageDefault = 0
# Ignore window framing/shadow so fullscreen/ultrawide bounds align with content.
_kCGWindowImageBoundsIgnoreFraming = 1 << 0  # 1


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




def resume_smoke(process_name: str = "WowB") -> tuple[bool, str]:
    """Try capture strategies for a ≥32×32 smoke of the WoW window.

    Returns ``(ok, reason)``. Reason is logged by the bridge on failure.
    Order: CG strip → CG full+crop → screencapture -l + crop → screencapture -R.
    No WoW window / no id → False with reason. Non-darwin → (True, "non-darwin").
    Does not call request_screen_recording (stays quiet).
    """
    if sys.platform != "darwin":
        return True, "non-darwin"
    try:
        win = find_wow_window(process_name)
    except Exception as e:  # noqa: BLE001
        return False, f"find_wow_window error: {e}"
    if not win:
        return False, "no WoW window"
    wid = win.get("id")
    if not wid:
        return False, f"no window id (name={win.get('name')!r})"
    dest = Path(tempfile.gettempdir()) / "wow-grok-resume-smoke.png"
    try:
        if dest.exists():
            dest.unlink()
    except OSError:
        pass
    errors: list[str] = []
    for name, fn in (
        ("cg-strip", lambda: capture_strip_cg(int(wid), float(win["x"]), float(win["y"]), 64.0, 64.0, dest)),
        ("cg-full-crop", lambda: capture_window_cg_crop(int(wid), 64.0, 64.0, dest)),
        ("screencapture-l", lambda: capture_window_cli_crop(int(wid), 64.0, 64.0, dest)),
        ("screencapture-R", lambda: capture_region(float(win["x"]), float(win["y"]), 64.0, 64.0, dest)),
    ):
        try:
            if dest.exists():
                try:
                    dest.unlink()
                except OSError:
                    pass
            fn()
            if not dest.is_file() or dest.stat().st_size < 50:
                errors.append(f"{name}: empty file")
                continue
            from PIL import Image

            with Image.open(dest) as im:
                w, h = im.size
            if w >= 32 and h >= 32:
                return True, f"ok via {name} {w}x{h}"
            errors.append(f"{name}: size {w}x{h}")
        except Exception as e:  # noqa: BLE001
            errors.append(f"{name}: {e}")
    return False, "; ".join(errors) if errors else "all strategies failed"


def resume_smoke_ok(process_name: str = "WowB") -> bool:
    """True when :func:`resume_smoke` succeeds (compat wrapper)."""
    ok, _reason = resume_smoke(process_name)
    return ok


# Last failure reason from resume_smoke (bridge may also call resume_smoke directly).
_last_resume_smoke_reason: str = ""


def is_capture_permission_failure(msg: str) -> bool:
    """True when *msg* indicates Screen Recording / TCC / screencapture denial.

    Used by :func:`live_loop` to exit permanently (code 42) instead of
    sleep-and-retry, which re-triggers macOS "Open System Settings" spam —
    especially after an unsigned app replace that thrash-resets TCC.

    Includes ``could not create image from rect`` (screencapture) and CG null /
    empty capture strings. ``live_loop`` only exits 42 when *both* CG strip and
    CLI fail this class (CLI rect alone is not permanent if CG was not tried).
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
        "cgwindowlistcreateimage returned null",
        "window capture",
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


# --- 0.1.36: in-process CoreGraphics for the per-tick work (no osascript) -------
#
# Before 0.1.36 the live loop spawned ``osascript`` (JXA) twice per tick: once to
# find the WoW window and once to read the screen's backingScaleFactor. That is
# ~8 short-lived processes a second, each attaching to WindowServer. Both are now
# read in-process through ctypes; JXA window finding is kept only as a startup
# fallback for a Mac where CoreGraphics cannot be loaded in-process.

_SCALE_RECHECK_S = 30.0
_JXA_RETRY_S = 10.0
_kCFStringEncodingUTF8 = 0x08000100
_kCFNumberSInt64Type = 4


class _CGUnavailable(RuntimeError):
    """CoreGraphics could not be used in-process (library or symbol missing)."""


_cg_cache: dict[str, Any] = {}


def _cg_api() -> tuple[Any, Any, dict[str, int]]:
    """CoreGraphics + CoreFoundation with the window-list / display prototypes set.

    Cached for the process. Raises :class:`_CGUnavailable` when the frameworks or
    a symbol cannot be loaded (never spawns a process).
    """
    if "api" in _cg_cache:
        return _cg_cache["api"]
    import ctypes

    try:
        cg, cf = _load_cg_cf()
        CGPoint, _CGSize, CGRect = _cg_rect_types()
        vp = ctypes.c_void_p
        cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
        cg.CGWindowListCopyWindowInfo.restype = vp
        cg.CGRectMakeWithDictionaryRepresentation.argtypes = [vp, ctypes.POINTER(CGRect)]
        cg.CGRectMakeWithDictionaryRepresentation.restype = ctypes.c_bool
        cg.CGGetDisplaysWithPoint.argtypes = [
            CGPoint,
            ctypes.c_uint32,
            ctypes.POINTER(ctypes.c_uint32),
            ctypes.POINTER(ctypes.c_uint32),
        ]
        cg.CGGetDisplaysWithPoint.restype = ctypes.c_int32
        cg.CGMainDisplayID.argtypes = []
        cg.CGMainDisplayID.restype = ctypes.c_uint32
        cg.CGDisplayCopyDisplayMode.argtypes = [ctypes.c_uint32]
        cg.CGDisplayCopyDisplayMode.restype = vp
        cg.CGDisplayModeGetWidth.argtypes = [vp]
        cg.CGDisplayModeGetWidth.restype = ctypes.c_size_t
        cg.CGDisplayModeGetPixelWidth.argtypes = [vp]
        cg.CGDisplayModeGetPixelWidth.restype = ctypes.c_size_t
        cg.CGDisplayModeRelease.argtypes = [vp]
        cg.CGDisplayModeRelease.restype = None
        cf.CFArrayGetCount.argtypes = [vp]
        cf.CFArrayGetCount.restype = ctypes.c_long
        cf.CFArrayGetValueAtIndex.argtypes = [vp, ctypes.c_long]
        cf.CFArrayGetValueAtIndex.restype = vp
        cf.CFDictionaryGetValue.argtypes = [vp, vp]
        cf.CFDictionaryGetValue.restype = vp
        cf.CFGetTypeID.argtypes = [vp]
        cf.CFGetTypeID.restype = ctypes.c_ulong
        cf.CFStringGetTypeID.argtypes = []
        cf.CFStringGetTypeID.restype = ctypes.c_ulong
        cf.CFNumberGetTypeID.argtypes = []
        cf.CFNumberGetTypeID.restype = ctypes.c_ulong
        cf.CFDictionaryGetTypeID.argtypes = []
        cf.CFDictionaryGetTypeID.restype = ctypes.c_ulong
        cf.CFStringGetLength.argtypes = [vp]
        cf.CFStringGetLength.restype = ctypes.c_long
        cf.CFStringGetMaximumSizeForEncoding.argtypes = [ctypes.c_long, ctypes.c_uint32]
        cf.CFStringGetMaximumSizeForEncoding.restype = ctypes.c_long
        cf.CFStringGetCString.argtypes = [vp, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
        cf.CFStringGetCString.restype = ctypes.c_bool
        cf.CFNumberGetValue.argtypes = [vp, ctypes.c_long, vp]
        cf.CFNumberGetValue.restype = ctypes.c_bool
        cf.CFRelease.argtypes = [vp]
        cf.CFRelease.restype = None
        keys = {
            name: vp.in_dll(cg, name).value
            for name in (
                "kCGWindowOwnerName",
                "kCGWindowLayer",
                "kCGWindowBounds",
                "kCGWindowNumber",
            )
        }
        types = {
            "str": int(cf.CFStringGetTypeID()),
            "num": int(cf.CFNumberGetTypeID()),
            "dict": int(cf.CFDictionaryGetTypeID()),
        }
    except Exception as e:  # noqa: BLE001
        raise _CGUnavailable(f"CoreGraphics unavailable in-process: {e}") from e
    api = (cg, cf, {**keys, **{"type_" + k: v for k, v in types.items()}})
    _cg_cache["api"] = api
    return api


def _cg_window_rows() -> list[dict[str, Any]]:
    """On-screen windows (front to back) from ``CGWindowListCopyWindowInfo``.

    Each row: ``owner`` (str or None), ``layer`` (int or None), ``bounds``
    (``(x, y, w, h)`` floats or None), ``number`` (int or None) — the same four
    fields the JXA finder read. A NULL list raises the Screen Recording message
    the bridge has always treated as a hard permission failure.
    """
    import ctypes

    cg, cf, k = _cg_api()
    _CGPoint, _CGSize, CGRect = _cg_rect_types()
    arr = cg.CGWindowListCopyWindowInfo(_kCGWindowListOptionOnScreenOnly, _kCGNullWindowID)
    if not arr:
        raise RuntimeError(
            "Screen Recording blocked window list — System Settings → Privacy & Security "
            "→ Screen Recording → enable WoWGrok.app, then Quit and reopen WoWGrok"
        )

    def typed(ref: Any, kind: str) -> Any:
        if ref and int(cf.CFGetTypeID(ref)) == k["type_" + kind]:
            return ref
        return None

    def as_int(ref: Any) -> int | None:
        if not typed(ref, "num"):
            return None
        out = ctypes.c_int64(0)
        if not cf.CFNumberGetValue(ref, _kCFNumberSInt64Type, ctypes.byref(out)):
            return None
        return int(out.value)

    def as_str(ref: Any) -> str | None:
        if not typed(ref, "str"):
            return None
        size = int(cf.CFStringGetMaximumSizeForEncoding(cf.CFStringGetLength(ref), _kCFStringEncodingUTF8)) + 1
        buf = ctypes.create_string_buffer(max(size, 1))
        if not cf.CFStringGetCString(ref, buf, len(buf), _kCFStringEncodingUTF8):
            return None
        return buf.value.decode("utf-8", "replace")

    rows: list[dict[str, Any]] = []
    try:
        for i in range(int(cf.CFArrayGetCount(arr))):
            d = cf.CFArrayGetValueAtIndex(arr, i)
            if not typed(d, "dict"):
                continue
            bounds = None
            bref = typed(cf.CFDictionaryGetValue(d, k["kCGWindowBounds"]), "dict")
            if bref:
                r = CGRect()
                if cg.CGRectMakeWithDictionaryRepresentation(bref, ctypes.byref(r)):
                    bounds = (r.origin.x, r.origin.y, r.size.width, r.size.height)
            rows.append(
                {
                    "owner": as_str(cf.CFDictionaryGetValue(d, k["kCGWindowOwnerName"])),
                    "layer": as_int(cf.CFDictionaryGetValue(d, k["kCGWindowLayer"])),
                    "bounds": bounds,
                    "number": as_int(cf.CFDictionaryGetValue(d, k["kCGWindowNumber"])),
                }
            )
    finally:
        cf.CFRelease(arr)
    return rows


def _wow_window_wants(process_name: str) -> list[str]:
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
    add("Wow")  # exact owner often "Wow"; wowgrok is skipped before matching
    return want


def _js_int(v: Any) -> int:
    """JavaScript ``v|0`` for the numbers the JXA finder saw (truncate toward 0)."""
    try:
        f = float(v)
    except (TypeError, ValueError):
        return 0
    if f != f or f in (float("inf"), float("-inf")):
        return 0
    n = int(f) & 0xFFFFFFFF
    return n - 0x100000000 if n >= 0x80000000 else n


def pick_wow_window(rows: list[dict[str, Any]], process_name: str) -> dict[str, Any] | None:
    """First window in *rows* the JXA finder would have picked (identical rules).

    Rules (unchanged from <=0.1.35): normal layer (0) only; skip owners containing
    ``wowgrok``; owner must match a wanted name (equal / contains / contained-in)
    or be ``wow`` / contain ``warcraft`` / ``wowb``; bounds wider and taller than
    100 points. Front-most match wins. Coordinates truncate like JS ``|0``.
    """
    want = _wow_window_wants(process_name)
    for row in rows:
        owner = row.get("owner") or ""
        if (row.get("layer") or 0) != 0:
            continue
        low = str(owner).lower()
        if "wowgrok" in low:
            continue
        ok = any(low == w or w in low or low in w for w in want)
        if not ok and low != "wow" and "warcraft" not in low and "wowb" not in low:
            continue
        b = row.get("bounds")
        if not b:
            continue
        x, y, w, h = b
        if not (w > 100 and h > 100):
            continue
        return {
            "name": str(owner),
            "x": _js_int(x),
            "y": _js_int(y),
            "w": _js_int(w),
            "h": _js_int(h),
            "id": _js_int(row.get("number") or 0),
        }
    return None


_jxa_fallback: dict[str, Any] = {"announced": False, "hit": None, "last_try": None}


def _reset_window_finder() -> None:
    """Forget the JXA fallback state (tests)."""
    _jxa_fallback.update({"announced": False, "hit": None, "last_try": None})


def find_wow_window(process_name: str) -> dict[str, Any] | None:
    """Locate the on-screen WoW / Forever window (needs Screen Recording).

    In-process ``CGWindowListCopyWindowInfo`` every call — no subprocess. Only if
    CoreGraphics cannot be loaded in-process does it fall back to the old JXA
    finder: logged once, retried at most every 10 s until the window is found,
    and then that window is reused for the rest of the run (so the fallback never
    spawns ``osascript`` per tick).
    """
    try:
        rows = _cg_window_rows()
    except _CGUnavailable as e:
        return _find_wow_window_fallback(process_name, str(e))
    return pick_wow_window(rows, process_name)


def _find_wow_window_fallback(process_name: str, why: str) -> dict[str, Any] | None:
    st = _jxa_fallback
    if st["hit"] is not None:
        return st["hit"]
    if not st["announced"]:
        st["announced"] = True
        emit(
            {
                "info": (
                    f"{why}; using one-time osascript window lookup "
                    "(window position is fixed until WoWGrok restarts)"
                )
            }
        )
    now = time.monotonic()
    if st["last_try"] is not None and now - st["last_try"] < _JXA_RETRY_S:
        return None
    st["last_try"] = now
    hit = _find_wow_window_jxa(process_name)
    if hit:
        st["hit"] = hit
    return hit


def _cg_main_display() -> int | None:
    try:
        cg, _cf, _k = _cg_api()
        return int(cg.CGMainDisplayID()) or None
    except Exception:  # noqa: BLE001
        return None


def _cg_display_for_window(win: dict[str, Any] | None) -> int | None:
    """CGDirectDisplayID under the window centre (global top-left points)."""
    if not win:
        return _cg_main_display()
    import ctypes

    try:
        cx = float(win["x"]) + float(win["w"]) / 2.0
        cy = float(win["y"]) + float(win["h"]) / 2.0
        cg, _cf, _k = _cg_api()
        CGPoint, _CGSize, _CGRect = _cg_rect_types()
        disp = ctypes.c_uint32(0)
        count = ctypes.c_uint32(0)
        err = cg.CGGetDisplaysWithPoint(CGPoint(cx, cy), 1, ctypes.byref(disp), ctypes.byref(count))
        if err == 0 and count.value >= 1 and disp.value:
            return int(disp.value)
    except Exception:  # noqa: BLE001
        pass
    return _cg_main_display()


def _cg_display_scale(display_id: int | None) -> float | None:
    """Backing scale of *display_id*: mode pixel width / point width (Retina = 2)."""
    if not display_id:
        return None
    try:
        cg, _cf, _k = _cg_api()
        mode = cg.CGDisplayCopyDisplayMode(int(display_id))
        if not mode:
            return None
        try:
            pts = int(cg.CGDisplayModeGetWidth(mode))
            px = int(cg.CGDisplayModeGetPixelWidth(mode))
        finally:
            cg.CGDisplayModeRelease(mode)
        if pts <= 0 or px <= 0:
            return None
        return round(px / pts, 3)
    except Exception:  # noqa: BLE001
        return None


def backing_scale_factor() -> float:
    """Main display backing scale, in-process (1.0 when unknown). No subprocess."""
    return _cg_display_scale(_cg_main_display()) or 1.0


def backing_scale_for_window(bounds: dict[str, Any] | None) -> float:
    """Backing scale of the display under the window centre; else the main display."""
    return _cg_display_scale(_cg_display_for_window(bounds)) or backing_scale_factor()


class ScaleCache:
    """Display scale for the capture window, read once and cached.

    Re-read only when the display under the window changes, the window size
    changes, or :data:`_SCALE_RECHECK_S` (30 s) has passed. A failed read keeps
    the last good value. All reads are in-process CoreGraphics calls.
    """

    def __init__(self, recheck_s: float = _SCALE_RECHECK_S) -> None:
        self.recheck_s = recheck_s
        self.value: float | None = None
        self._key: tuple[Any, ...] | None = None
        self._read_at = 0.0
        self.reads = 0

    def get(self, win: dict[str, Any] | None, now: float | None = None) -> float | None:
        now = time.monotonic() if now is None else now
        size = (int((win or {}).get("w") or 0), int((win or {}).get("h") or 0))
        key = (_cg_display_for_window(win), size)
        if self.value is not None and key == self._key and now - self._read_at < self.recheck_s:
            return self.value
        self.reads += 1
        v = _cg_display_scale(key[0])
        if v and v > 0:
            self.value = v
        self._key = key
        self._read_at = now
        return self.value


def parse_wow_window_hit(line: str) -> dict[str, Any] | None:
    """Parse a tab-separated JXA hit: name, x, y, w, h[, id]."""
    parts = (line or "").split("\t")
    if len(parts) < 5:
        return None
    try:
        out: dict[str, Any] = {
            "name": parts[0],
            "x": int(parts[1]),
            "y": int(parts[2]),
            "w": int(parts[3]),
            "h": int(parts[4]),
        }
        if len(parts) >= 6 and str(parts[5]).strip() != "":
            out["id"] = int(parts[5])
        return out
    except (TypeError, ValueError):
        return None


def _find_wow_window_jxa(process_name: str) -> dict[str, Any] | None:
    """Pre-0.1.36 finder: JXA + CoreGraphics in a spawned ``osascript``.

    Only used by :func:`find_wow_window` when CoreGraphics cannot be loaded
    in-process. Same matching rules as :func:`pick_wow_window`.
    """
    want_json = json.dumps(_wow_window_wants(process_name))
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
      if (low !== 'wow' && low.indexOf('warcraft') < 0 && low.indexOf('wowb') < 0) continue;
    }}
    var b = w.kCGWindowBounds || {{}};
    if (!(b.Width > 100 && b.Height > 100)) continue;
    var wid = w.kCGWindowNumber || 0;
    hits.push([owner, b.X|0, b.Y|0, b.Width|0, b.Height|0, wid|0].join('\\t'));
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
    return parse_wow_window_hit(out)



def _cg_rect_types():
    """CGPoint / CGSize / CGRect ctypes structures (shared by capture helpers).

    Built once: ctypes prototypes cached in :func:`_cg_api` only accept the very
    same structure classes.
    """
    if "rect_types" in _cg_cache:
        return _cg_cache["rect_types"]
    import ctypes

    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    class CGSize(ctypes.Structure):
        _fields_ = [("width", ctypes.c_double), ("height", ctypes.c_double)]

    class CGRect(ctypes.Structure):
        _fields_ = [("origin", CGPoint), ("size", CGSize)]

    _cg_cache["rect_types"] = (CGPoint, CGSize, CGRect)
    return CGPoint, CGSize, CGRect


def _cg_image_to_png(cg: object, cf: object, img: int, dest: Path) -> None:
    """Write a CGImageRef to PNG via ImageIO, else raw bytes + Pillow."""
    import ctypes
    import ctypes.util

    dest = Path(dest)
    # --- ImageIO path ---
    try:
        io_path = ctypes.util.find_library("ImageIO") or (
            "/System/Library/Frameworks/ImageIO.framework/ImageIO"
        )
        imageio = ctypes.CDLL(io_path)
        # CFURL from file path
        cf.CFURLCreateFromFileSystemRepresentation.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_long,
            ctypes.c_bool,
        ]
        cf.CFURLCreateFromFileSystemRepresentation.restype = ctypes.c_void_p
        cf.CFStringCreateWithCString.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_uint32,
        ]
        cf.CFStringCreateWithCString.restype = ctypes.c_void_p
        imageio.CGImageDestinationCreateWithURL.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_void_p,
        ]
        imageio.CGImageDestinationCreateWithURL.restype = ctypes.c_void_p
        imageio.CGImageDestinationAddImage.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_void_p,
        ]
        imageio.CGImageDestinationAddImage.restype = None
        imageio.CGImageDestinationFinalize.argtypes = [ctypes.c_void_p]
        imageio.CGImageDestinationFinalize.restype = ctypes.c_bool
        cf.CFRelease.argtypes = [ctypes.c_void_p]
        cf.CFRelease.restype = None

        path_bytes = str(dest).encode("utf-8")
        url = cf.CFURLCreateFromFileSystemRepresentation(
            None, path_bytes, len(path_bytes), False
        )
        if not url:
            raise RuntimeError("CFURLCreateFromFileSystemRepresentation failed")
        # kUTTypePNG / public.png
        uti = cf.CFStringCreateWithCString(None, b"public.png", 0x08000100)  # UTF-8
        if not uti:
            cf.CFRelease(url)
            raise RuntimeError("CFStringCreateWithCString failed")
        dest_ref = imageio.CGImageDestinationCreateWithURL(url, uti, 1, None)
        cf.CFRelease(uti)
        cf.CFRelease(url)
        if not dest_ref:
            raise RuntimeError("CGImageDestinationCreateWithURL failed")
        imageio.CGImageDestinationAddImage(dest_ref, img, None)
        ok = bool(imageio.CGImageDestinationFinalize(dest_ref))
        cf.CFRelease(dest_ref)
        if ok and dest.is_file() and dest.stat().st_size >= 50:
            return
        raise RuntimeError("CGImageDestinationFinalize failed")
    except Exception:
        pass  # fall through to Pillow

    # --- Pillow from CGDataProvider raw bytes ---
    from PIL import Image

    cg.CGImageGetWidth.argtypes = [ctypes.c_void_p]
    cg.CGImageGetWidth.restype = ctypes.c_size_t
    cg.CGImageGetHeight.argtypes = [ctypes.c_void_p]
    cg.CGImageGetHeight.restype = ctypes.c_size_t
    cg.CGImageGetBytesPerRow.argtypes = [ctypes.c_void_p]
    cg.CGImageGetBytesPerRow.restype = ctypes.c_size_t
    cg.CGImageGetBitsPerPixel.argtypes = [ctypes.c_void_p]
    cg.CGImageGetBitsPerPixel.restype = ctypes.c_size_t
    cg.CGImageGetDataProvider.argtypes = [ctypes.c_void_p]
    cg.CGImageGetDataProvider.restype = ctypes.c_void_p
    cg.CGDataProviderCopyData.argtypes = [ctypes.c_void_p]
    cg.CGDataProviderCopyData.restype = ctypes.c_void_p
    cf.CFDataGetLength.argtypes = [ctypes.c_void_p]
    cf.CFDataGetLength.restype = ctypes.c_long
    cf.CFDataGetBytePtr.argtypes = [ctypes.c_void_p]
    cf.CFDataGetBytePtr.restype = ctypes.POINTER(ctypes.c_ubyte)
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None

    width = int(cg.CGImageGetWidth(img))
    height = int(cg.CGImageGetHeight(img))
    bpr = int(cg.CGImageGetBytesPerRow(img))
    bpp = int(cg.CGImageGetBitsPerPixel(img))
    if width < 1 or height < 1:
        raise RuntimeError("CGImage has empty dimensions")
    provider = cg.CGImageGetDataProvider(img)
    if not provider:
        raise RuntimeError("CGImageGetDataProvider returned null")
    data_ref = cg.CGDataProviderCopyData(provider)
    if not data_ref:
        raise RuntimeError("CGDataProviderCopyData returned null")
    try:
        length = int(cf.CFDataGetLength(data_ref))
        ptr = cf.CFDataGetBytePtr(data_ref)
        raw = ctypes.string_at(ptr, length)
    finally:
        cf.CFRelease(data_ref)

    # Most window captures are 32-bit BGRA; fall back to RGBA.
    if bpp >= 32:
        mode = "BGRA"
        pil = Image.frombuffer("RGBA", (width, height), raw, "raw", mode, bpr, 1)
        pil = pil.convert("RGB")
    elif bpp == 24:
        pil = Image.frombuffer("RGB", (width, height), raw, "raw", "RGB", bpr, 1)
    else:
        raise RuntimeError(f"unsupported CGImage bitsPerPixel={bpp}")
    pil.save(dest, format="PNG")
    if not dest.is_file() or dest.stat().st_size < 50:
        raise RuntimeError("Pillow PNG write produced no image")


def capture_strip_cg(
    window_id: int,
    x: float,
    y: float,
    w: float,
    h: float,
    dest: str | Path,
) -> None:
    """In-process ``CGWindowListCreateImage`` strip for *window_id* → PNG at *dest*.

    Uses ``kCGWindowListOptionIncludingWindow`` with a global-points rect for the
    top-left strip. Raises RuntimeError on null image / write failure.
    """
    import ctypes

    if not window_id:
        raise RuntimeError("capture_strip_cg requires a non-zero window id")
    CGPoint, CGSize, CGRect = _cg_rect_types()
    try:
        cg, cf = _load_cg_cf()
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(f"CoreGraphics load failed: {e}") from e

    cg.CGWindowListCreateImage.argtypes = [
        CGRect,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_uint32,
    ]
    cg.CGWindowListCreateImage.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None

    rect = CGRect(
        CGPoint(float(x), float(y)),
        CGSize(float(w), float(h)),
    )
    img = cg.CGWindowListCreateImage(
        rect,
        _kCGWindowListOptionIncludingWindow,
        ctypes.c_uint32(int(window_id)),
        _kCGWindowImageDefault,
    )
    if not img:
        # Retry with BoundsIgnoreFraming (helps some fullscreen / borderless windows).
        img = cg.CGWindowListCreateImage(
            rect,
            _kCGWindowListOptionIncludingWindow,
            ctypes.c_uint32(int(window_id)),
            _kCGWindowImageBoundsIgnoreFraming,
        )
    if not img:
        raise RuntimeError(
            "CGWindowListCreateImage returned null (Screen Recording / window capture)"
        )
    try:
        cg.CGImageGetWidth.argtypes = [ctypes.c_void_p]
        cg.CGImageGetWidth.restype = ctypes.c_size_t
        cg.CGImageGetHeight.argtypes = [ctypes.c_void_p]
        cg.CGImageGetHeight.restype = ctypes.c_size_t
        iw = int(cg.CGImageGetWidth(img))
        ih = int(cg.CGImageGetHeight(img))
        if iw < 1 or ih < 1:
            raise RuntimeError(
                "CGWindowListCreateImage produced no image (Screen Recording denied)"
            )
        _cg_image_to_png(cg, cf, img, Path(dest))
    finally:
        try:
            cf.CFRelease(img)
        except Exception:  # noqa: BLE001
            pass


def capture_window_cg_crop(
    window_id: int,
    strip_w: float,
    strip_h: float,
    dest: str | Path,
) -> None:
    """CG full-window capture (CGRectNull) then Pillow-crop top-left strip → *dest*."""
    import ctypes

    if not window_id:
        raise RuntimeError("capture_window_cg_crop requires a non-zero window id")
    CGPoint, CGSize, CGRect = _cg_rect_types()
    try:
        cg, cf = _load_cg_cf()
    except Exception as e:  # noqa: BLE001
        raise RuntimeError(f"CoreGraphics load failed: {e}") from e

    cg.CGWindowListCreateImage.argtypes = [
        CGRect,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_uint32,
    ]
    cg.CGWindowListCreateImage.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    cf.CFRelease.restype = None

    # CGRectNull = infinite rect → capture whole window
    null_rect = CGRect(CGPoint(0.0, 0.0), CGSize(0.0, 0.0))
    # On Apple platforms CGRectNull has origin ±inf; use a large bounds via IncludingWindow
    # with null-like size 0,0 often still works; prefer explicit null constants when present.
    try:
        # CGRectNull is {{+inf,+inf},{-inf,-inf}} — approximate via c_double inf
        inf = float("inf")
        null_rect = CGRect(CGPoint(inf, inf), CGSize(-inf, -inf))
    except Exception:  # noqa: BLE001
        pass

    img = None
    for image_opts in (_kCGWindowImageDefault, _kCGWindowImageBoundsIgnoreFraming):
        img = cg.CGWindowListCreateImage(
            null_rect,
            _kCGWindowListOptionIncludingWindow,
            ctypes.c_uint32(int(window_id)),
            image_opts,
        )
        if img:
            break
    if not img:
        raise RuntimeError(
            "CGWindowListCreateImage(full) returned null (Screen Recording / window capture)"
        )
    tmp = Path(dest).with_suffix(".full.png")
    try:
        _cg_image_to_png(cg, cf, img, tmp)
    finally:
        try:
            cf.CFRelease(img)
        except Exception:  # noqa: BLE001
            pass
    _pillow_crop_top_left(tmp, float(strip_w), float(strip_h), Path(dest))
    try:
        tmp.unlink()
    except OSError:
        pass


def capture_window_cli_crop(
    window_id: int,
    strip_w: float,
    strip_h: float,
    dest: str | Path,
) -> None:
    """``screencapture -l <windowID>`` then Pillow-crop top-left strip → *dest*.

    Preferred for fullscreen/ultrawide WoW where CG strip or ``-R`` may fail in-app
    while ``-l`` still works (Terminal verified on 3440×1440 id=7472).
    """
    if not window_id:
        raise RuntimeError("capture_window_cli_crop requires a non-zero window id")
    dest_p = Path(dest)
    full = dest_p.with_suffix(".win.png")
    try:
        if full.exists():
            full.unlink()
    except OSError:
        pass
    r = subprocess.run(
        ["screencapture", "-x", "-t", "png", "-l", str(int(window_id)), str(full)],
        capture_output=True,
        text=True,
        timeout=12,
    )
    if r.returncode != 0:
        raise RuntimeError(
            (r.stderr or r.stdout or "screencapture -l failed").strip()
            or "screencapture -l failed"
        )
    if not full.is_file() or full.stat().st_size < 50:
        raise RuntimeError(
            "screencapture -l produced no image (grant Screen Recording to WoWGrok / Terminal)"
        )
    try:
        _pillow_crop_top_left(full, float(strip_w), float(strip_h), dest_p)
    finally:
        try:
            full.unlink()
        except OSError:
            pass


def _pillow_crop_top_left(
    src: Path, strip_w: float, strip_h: float, dest: Path
) -> None:
    """Crop top-left *strip_w*×*strip_h* points (approx px) from *src* PNG → *dest*."""
    from PIL import Image

    with Image.open(src) as im:
        im = im.convert("RGB")
        # Retina: full window capture is often 2× points; take a generous crop then
        # let strip_codec infer scale. Prefer at least strip size in pixels.
        cw = max(int(round(strip_w)), 64)
        ch = max(int(round(strip_h)), 64)
        # If image is much larger than requested (Retina), crop 2× the point size.
        if im.width >= cw * 2 and im.height >= ch * 2:
            cw, ch = cw * 2, ch * 2
        cw = min(cw, im.width)
        ch = min(ch, im.height)
        if cw < 32 or ch < 32:
            raise RuntimeError(f"crop source too small: {im.width}x{im.height}")
        cropped = im.crop((0, 0, cw, ch))
        cropped.save(dest, format="PNG")
    if not dest.is_file() or dest.stat().st_size < 50:
        raise RuntimeError("Pillow crop produced no image")


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
    # 0.1.36: display scale is read in-process and cached (display / size change
    # or 30 s re-check), and the strategy that last worked is tried first so a
    # strategy that keeps failing is not re-spawned every tick.
    scale_cache = ScaleCache()
    last_via = ""
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
                f"experimental mac capture; CG strip / CG-full-crop / screencapture -l / -R; "
                f"backingScaleFactor={declared_scale}; "
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
                wid = win.get("id")
                emit(
                    {
                        "info": (
                            f"attached to '{win['name']}'"
                            + (f" id={wid}" if wid else "")
                            + f" at {win['x']},{win['y']} {win['w']}x{win['h']}"
                        )
                    }
                )

            # Strategies (order): CG strip → CG full+crop → screencapture -l + crop
            # → screencapture -R. Prefer -l for fullscreen/ultrawide (Terminal-proven).
            # Do NOT exit 42 on a single CLI-rect failure if other strategies remain.
            strategy_errs: list[tuple[str, Exception]] = []
            captured = False
            via = ""
            wid = win.get("id")
            strategies: list[tuple[str, object]] = []
            if wid:
                strategies.append(
                    (
                        "cg-strip",
                        lambda: capture_strip_cg(
                            int(wid),
                            float(win["x"]),
                            float(win["y"]),
                            float(cap_w),
                            float(cap_h),
                            dest,
                        ),
                    )
                )
                strategies.append(
                    (
                        "cg-full-crop",
                        lambda: capture_window_cg_crop(
                            int(wid), float(cap_w), float(cap_h), dest
                        ),
                    )
                )
                strategies.append(
                    (
                        "screencapture-l",
                        lambda: capture_window_cli_crop(
                            int(wid), float(cap_w), float(cap_h), dest
                        ),
                    )
                )
            strategies.append(
                (
                    "screencapture-R",
                    lambda: capture_region(
                        win["x"], win["y"], cap_w, cap_h, dest
                    ),
                )
            )
            if last_via:
                strategies.sort(key=lambda s: s[0] != last_via)
            for name, fn in strategies:
                try:
                    if dest.exists():
                        try:
                            dest.unlink()
                        except OSError:
                            pass
                    fn()  # type: ignore[operator]
                    if dest.is_file() and dest.stat().st_size >= 50:
                        captured = True
                        via = name
                        break
                    strategy_errs.append(
                        (name, RuntimeError("produced empty image"))
                    )
                except Exception as e:  # noqa: BLE001
                    strategy_errs.append((name, e))

            if not captured:
                msgs = [f"{n}: {e}" for n, e in strategy_errs]
                combined = " | ".join(msgs) if msgs else "strip capture failed"
                # Hard TCC only when ALL tried strategies fail permission-class,
                # or a true window-list block appears.
                perm_hits = [
                    (n, e)
                    for n, e in strategy_errs
                    if is_capture_permission_failure(str(e))
                ]
                hard = False
                for _n, e in strategy_errs:
                    low = str(e).lower()
                    if any(
                        x in low
                        for x in (
                            "null_list",
                            "blocked window list",
                            "not authorized to capture",
                            "not permitted to capture",
                            "screen recording blocked",
                        )
                    ):
                        hard = True
                        break
                all_perm = bool(strategy_errs) and len(perm_hits) == len(strategy_errs)
                # Soften: single CLI-rect alone must not permanent-pause.
                only_rect = (
                    len(strategy_errs) == 1
                    and "could not create image from rect" in str(strategy_errs[0][1]).lower()
                )
                if (hard or all_perm) and not only_rect and len(strategies) >= 2:
                    # Require exhausting multiple strategies before exit 42.
                    if all_perm and len(perm_hits) >= 2:
                        return _permission_error(
                            combined
                            + " Enable WoWGrok under Screen Recording, then Quit and reopen WoWGrok."
                        )
                    if hard and all_perm:
                        return _permission_error(
                            combined
                            + " Enable WoWGrok under Screen Recording, then Quit and reopen WoWGrok."
                        )
                perm_fail_streak += 1
                now = time.time()
                if now - last_warn > 5:
                    last_warn = now
                    emit(
                        {
                            "error": combined
                            + " (strategies exhausted this tick; soft-retry, not exit 42 yet)"
                        }
                    )
                # Soft retry — do not exit 42 on CLI rect alone.
                time.sleep(1)
                continue

            perm_fail_streak = 0
            last_via = via
            scale_hint = scale_cache.get(win) or declared_scale
            got = _decode_captured(dest, args.cell, args.cells, args.max_rows, scale_hint)
            if not told_scale:
                told_scale = True
                emit(
                    {
                        "info": (
                            f"capture bitmap {got['width']}x{got['height']} px via {via}; "
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
            # find_wow_window NULL_LIST etc. — genuine permission, exit 42.
            if is_capture_permission_failure(m):
                low = m.lower()
                if any(
                    n in low
                    for n in (
                        "null_list",
                        "blocked window list",
                        "screen recording",
                        "not authorized to capture",
                        "not permitted to capture",
                    )
                ):
                    return _permission_error(
                        m
                        + " Enable WoWGrok under Screen Recording, then Quit and reopen WoWGrok."
                    )
                perm_fail_streak += 1
                if perm_fail_streak >= 2:
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
