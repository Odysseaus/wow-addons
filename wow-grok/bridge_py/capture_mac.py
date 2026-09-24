"""macOS pixel-strip capture (port of bridge/capture-mac.js).

Strategy: osascript (JXA + CoreGraphics) locates the Forever / World of Warcraft
window (including kCGWindowNumber). Live strip capture prefers in-process
``CGWindowListCreateImage`` keyed by that window id; ``screencapture -R`` is a
fallback only. Retina: macOS reports window bounds in points; the PNG may be in
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




def resume_smoke_ok(process_name: str = "WowB") -> bool:
    """True when a CG strip of the WoW window captures successfully.

    Aligns with the live path (in-process window-id capture), not a desktop
    ``screencapture`` corner. Used before clearing permissionPaused / spawning.
    No WoW window → False (do not flap). Non-darwin → True for tests.
    Does not call request_screen_recording (stays quiet).
    """
    if sys.platform != "darwin":
        return True
    try:
        win = find_wow_window(process_name)
    except Exception:  # noqa: BLE001
        return False
    if not win or not win.get("id"):
        return False
    dest = Path(tempfile.gettempdir()) / "wow-grok-resume-smoke.png"
    try:
        if dest.exists():
            dest.unlink()
    except OSError:
        pass
    try:
        capture_strip_cg(
            int(win["id"]),
            float(win["x"]),
            float(win["y"]),
            64.0,
            64.0,
            dest,
        )
    except Exception:  # noqa: BLE001
        return False
    try:
        if not dest.is_file() or dest.stat().st_size < 50:
            return False
        from PIL import Image

        with Image.open(dest) as im:
            w, h = im.size
        return w >= 32 and h >= 32
    except Exception:  # noqa: BLE001
        return False


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


def backing_scale_for_window(bounds: dict[str, Any] | None) -> float:
    """Backing scale of the NSScreen containing the window center; else mainScreen."""
    if not bounds:
        return backing_scale_factor()
    try:
        cx = float(bounds["x"]) + float(bounds["w"]) / 2.0
        cy = float(bounds["y"]) + float(bounds["h"]) / 2.0
    except (KeyError, TypeError, ValueError):
        return backing_scale_factor()
    jxa = f"""
ObjC.import('AppKit');
var screens = $.NSScreen.screens;
var n = screens.count;
var best = $.NSScreen.mainScreen.backingScaleFactor;
for (var i = 0; i < n; i++) {{
  var s = screens.objectAtIndex(i);
  var f = s.frame;
  var x = f.origin.x;
  var y = f.origin.y;
  var w = f.size.width;
  var h = f.size.height;
  if ({cx} >= x && {cx} < x + w && {cy} >= y && {cy} < y + h) {{
    best = s.backingScaleFactor;
    break;
  }}
}}
best;
"""
    try:
        out = _run_osascript(["-l", "JavaScript", "-e", jxa], timeout_ms=2000)
        n = float(out)
        return n if n > 0 else 1.0
    except (RuntimeError, ValueError, subprocess.TimeoutExpired, FileNotFoundError):
        return backing_scale_factor()


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
    """CGPoint / CGSize / CGRect ctypes structures (shared by capture helpers)."""
    import ctypes

    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    class CGSize(ctypes.Structure):
        _fields_ = [("width", ctypes.c_double), ("height", ctypes.c_double)]

    class CGRect(ctypes.Structure):
        _fields_ = [("origin", CGPoint), ("size", CGSize)]

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
                f"experimental mac capture; CG window strip first, screencapture fallback; "
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

            # Prefer in-process CG window strip; screencapture -R is fallback only.
            cg_tried = False
            cg_err: Exception | None = None
            cli_err: Exception | None = None
            captured = False
            wid = win.get("id")
            if wid:
                cg_tried = True
                try:
                    capture_strip_cg(
                        int(wid),
                        float(win["x"]),
                        float(win["y"]),
                        float(cap_w),
                        float(cap_h),
                        dest,
                    )
                    captured = True
                except Exception as e:  # noqa: BLE001
                    cg_err = e

            if not captured:
                try:
                    capture_region(win["x"], win["y"], cap_w, cap_h, dest)
                    captured = True
                except Exception as e:  # noqa: BLE001
                    cli_err = e

            if not captured:
                # Exit 42 only when BOTH CG (if tried) and CLI fail permission-class.
                # screencapture "could not create image from rect" alone is NOT exit 42
                # when CG was not tried or when CG has not also failed that class.
                msgs = []
                if cg_err is not None:
                    msgs.append(f"cg: {cg_err}")
                if cli_err is not None:
                    msgs.append(f"cli: {cli_err}")
                combined = " | ".join(msgs) if msgs else "strip capture failed"
                cg_perm = cg_tried and cg_err is not None and is_capture_permission_failure(
                    str(cg_err)
                )
                cli_perm = cli_err is not None and is_capture_permission_failure(str(cli_err))
                # NULL_LIST / blocked window list from find is raised earlier; here:
                if cg_tried and cg_perm and cli_perm:
                    return _permission_error(
                        combined
                        + " Enable WoWGrok under Screen Recording, then Quit and reopen WoWGrok."
                    )
                # Window-list / true TCC strings without a usable CG path still exit.
                hard = False
                for err in (cg_err, cli_err):
                    if err is None:
                        continue
                    low = str(err).lower()
                    if any(
                        n in low
                        for n in (
                            "null_list",
                            "blocked window list",
                            "not authorized to capture",
                            "not permitted to capture",
                            "screen recording blocked",
                        )
                    ):
                        hard = True
                        break
                if hard and (cli_perm or cg_perm):
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
                            + (
                                " (CG+CLI permission-class; will stop if both keep failing)"
                                if cg_tried
                                else " (CLI fallback; CG not tried — not treating as permanent TCC yet)"
                            )
                        }
                    )
                # Soft retry — do not exit 42 on CLI rect alone when CG was not tried.
                time.sleep(2 if not cg_tried else 1)
                continue

            perm_fail_streak = 0
            scale_hint = backing_scale_for_window(win) or declared_scale
            got = _decode_captured(dest, args.cell, args.cells, args.max_rows, scale_hint)
            if not told_scale:
                told_scale = True
                via = "cg-window" if (cg_tried and cg_err is None) else "screencapture"
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
