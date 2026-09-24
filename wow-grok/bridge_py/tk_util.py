"""Shared tkinter helpers (dialog placement on multi-monitor Macs)."""
from __future__ import annotations

import subprocess
import sys
from typing import Any, Callable

# Keep the full window at least this many pixels inside the work area.
DIALOG_MARGIN = 24


def cocoa_visible_to_tk(
    main_frame: tuple[float, float, float, float],
    vis_frame: tuple[float, float, float, float],
) -> tuple[int, int, int, int]:
    """Map a Cocoa ``visibleFrame`` into Tk coords relative to mainScreen.

    Cocoa: origin bottom-left, y up. Tk on Aqua: ``+0+0`` is the **top-left of
    NSScreen.mainScreen**, y down. For Odysseaus's layout (ultrawide main
    ``(0,0,3440,1440)`` + laptop at cocoa x=3440), a dialog on the main screen
    stays in ``[0..3440)``; on the laptop it lands at tk x ≈ 3440.
    """
    mox, moy, _mw, mh = main_frame
    vox, voy, vw, vh = vis_frame
    main_top = moy + mh
    vis_top = voy + vh
    tk_x = int(round(vox - mox))
    tk_y = int(round(main_top - vis_top))
    tk_w = int(round(vw))
    tk_h = int(round(vh))
    return tk_x, tk_y, tk_w, tk_h


def clamp_window_in_work_area(
    win_w: int,
    win_h: int,
    work: tuple[int, int, int, int],
    *,
    margin: int = DIALOG_MARGIN,
) -> tuple[int, int, int, int]:
    """Return ``(w, h, x, y)`` so the window stays fully inside ``work``.

    Shrinks if needed, centers horizontally, places roughly one-third down
    vertically, then clamps so every side keeps ``margin`` pixels of work area
    (when the work area is large enough).
    """
    px, py, pw, ph = work
    margin = max(0, int(margin))
    inner_w = max(1, pw - 2 * margin)
    inner_h = max(1, ph - 2 * margin)
    w = max(1, min(int(win_w), inner_w))
    h = max(1, min(int(win_h), inner_h))
    # Prefer a usable minimum when the work area allows it
    if inner_w >= 200:
        w = max(200, w) if win_w >= 200 else w
        w = min(w, inner_w)
    if inner_h >= 120:
        h = max(120, h) if win_h >= 120 else h
        h = min(h, inner_h)
    x = px + max(0, (pw - w) // 2)
    y = py + max(0, (ph - h) // 3)
    max_x = px + pw - w - margin
    max_y = py + ph - h - margin
    min_x = px + margin
    min_y = py + margin
    if max_x < min_x:
        x = px + max(0, (pw - w) // 2)
    else:
        x = min(max(x, min_x), max_x)
    if max_y < min_y:
        y = py + max(0, (ph - h) // 3)
    else:
        y = min(max(y, min_y), max_y)
    return int(w), int(h), int(x), int(y)


def _parse_frame_csv(raw: str) -> tuple[int, int, int, int] | None:
    parts = [int(float(x)) for x in (raw or "").strip().split(",") if x.strip() != ""]
    if len(parts) != 4 or parts[2] < 200 or parts[3] < 200:
        return None
    return parts[0], parts[1], parts[2], parts[3]


def _darwin_work_area_jxa(*, prefer_pointer: bool) -> tuple[int, int, int, int]:
    """Ask AppKit for the visible work area of the pointer screen (or main)."""
    # Prefer the screen containing the mouse; fall back to mainScreen.
    # Map that screen's visibleFrame into Tk coords relative to mainScreen.
    prefer = "true" if prefer_pointer else "false"
    jxa = rf"""
ObjC.import('AppKit');
var preferPointer = {prefer};
var main = $.NSScreen.mainScreen;
if (!main) {{ '0,0,1280,800'; }}
else {{
  var chosen = main;
  if (preferPointer) {{
    var mouse = $.NSEvent.mouseLocation;
    var screens = $.NSScreen.screens;
    for (var i = 0; i < screens.count; i++) {{
      var s = screens.objectAtIndex(i);
      var f = s.frame;
      if (mouse.x >= f.origin.x && mouse.x < f.origin.x + f.size.width &&
          mouse.y >= f.origin.y && mouse.y < f.origin.y + f.size.height) {{
        chosen = s;
        break;
      }}
    }}
  }}
  var mf = main.frame;
  var vf = chosen.visibleFrame;
  var mainTop = mf.origin.y + mf.size.height;
  var visTop = vf.origin.y + vf.size.height;
  var tkX = Math.round(vf.origin.x - mf.origin.x);
  var tkY = Math.round(mainTop - visTop);
  var tkW = Math.round(vf.size.width);
  var tkH = Math.round(vf.size.height);
  [tkX, tkY, tkW, tkH].join(',');
}}
"""
    r = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", jxa],
        capture_output=True,
        text=True,
        timeout=2.5,
    )
    if r.returncode != 0:
        raise RuntimeError(r.stderr or "osascript failed")
    parsed = _parse_frame_csv(r.stdout or "")
    if parsed is None:
        raise RuntimeError(f"bad frame: {(r.stdout or '').strip()!r}")
    return parsed


def work_area_for_dialog() -> tuple[int, int, int, int]:
    """Return ``(x, y, w, h)`` work area in Tk coords for dialog placement.

    Prefers the screen containing the **mouse pointer**; falls back to
    ``NSScreen.mainScreen``. Tk ``+0+0`` is the top-left of mainScreen.
    """
    if sys.platform != "darwin":
        return (0, 0, 1280, 800)
    try:
        return _darwin_work_area_jxa(prefer_pointer=True)
    except Exception:
        try:
            return _darwin_work_area_jxa(prefer_pointer=False)
        except Exception:
            return 0, 22, 1280, 720


def primary_work_area() -> tuple[int, int, int, int]:
    """Return ``(x, y, w, h)`` of mainScreen's visible work area in Tk coords.

    Kept for callers that specifically want the menu-bar display. Dialog
    centering should use :func:`work_area_for_dialog` instead.
    """
    if sys.platform != "darwin":
        return (0, 0, 1280, 800)
    try:
        return _darwin_work_area_jxa(prefer_pointer=False)
    except Exception:
        return 0, 22, 1280, 720


def _apply_geometry(win: Any, w: int, h: int, x: int, y: int) -> None:
    try:
        win.geometry(f"{w}x{h}+{int(x)}+{int(y)}")
    except Exception:
        try:
            win.geometry(f"+{int(x)}+{int(y)}")
        except Exception:
            pass


def center_on_work_area(
    win: Any,
    width: int | None = None,
    height: int | None = None,
    *,
    work: tuple[int, int, int, int] | None = None,
    rebind_map: bool = True,
) -> None:
    """Place ``win`` inside the dialog work area; re-apply after ``<Map>``.

    Clamps so the full window stays at least :data:`DIALOG_MARGIN` px inside
    the work area on all sides. Binding ``<Map>`` + ``update_idletasks``
    catches reqwidth growth that would otherwise leave buttons off-screen.
    """

    def place(_event: Any = None) -> None:
        try:
            win.update_idletasks()
        except Exception:
            pass
        try:
            w = int(width if width is not None else win.winfo_reqwidth() or 440)
            h = int(height if height is not None else win.winfo_reqheight() or 220)
        except Exception:
            w, h = 440, 220
        area = work if work is not None else work_area_for_dialog()
        cw, ch, x, y = clamp_window_in_work_area(w, h, area)
        _apply_geometry(win, cw, ch, x, y)

    place()
    if rebind_map:
        try:
            # Avoid stacking duplicate handlers on repeated calls
            if not getattr(win, "_wowgrok_center_bound", False):
                win.bind("<Map>", place, add="+")
                win._wowgrok_center_bound = True  # type: ignore[attr-defined]
        except Exception:
            pass
        try:
            win.after_idle(place)
        except Exception:
            pass


def center_on_primary(win: Any, width: int | None = None, height: int | None = None) -> None:
    """Place ``win`` on the pointer/primary dialog work area (fully on-screen)."""
    center_on_work_area(win, width=width, height=height)


def center_on_pointer(win: Any, width: int | None = None, height: int | None = None) -> None:
    """Alias for :func:`center_on_primary` (pointer-preferring work area)."""
    center_on_work_area(win, width=width, height=height)


def prepare_dialog_root(root: Any) -> Any:
    """Withdrawn root centered for remaining native dialogs (e.g. filedialog)."""
    try:
        root.withdraw()
    except Exception:
        pass
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass
    # Small visible anchor so native sheets inherit a good screen
    try:
        root.geometry("1x1")
        center_on_work_area(root, width=1, height=1, rebind_map=False)
        root.deiconify()
        root.update_idletasks()
        root.withdraw()
    except Exception:
        center_on_work_area(root, width=10, height=10, rebind_map=False)
    return root


def _run_modal_dialog(
    *,
    title: str,
    build: Callable[[Any, Any], None],
    default: Any,
    min_w: int = 420,
    min_h: int = 160,
) -> Any:
    """Create a centered Tk root, let ``build`` fill it, run mainloop, return result."""
    import tkinter as tk

    result = {"v": default}
    root = tk.Tk()
    root.title(title)
    root.resizable(True, True)
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass

    def finish(value: Any) -> None:
        result["v"] = value
        try:
            root.destroy()
        except Exception:
            pass

    frm = tk.Frame(root, padx=18, pady=14)
    frm.pack(fill="both", expand=True)
    build(frm, finish)

    root.protocol("WM_DELETE_WINDOW", lambda: finish(default))
    root.update_idletasks()
    req_w = max(min_w, int(root.winfo_reqwidth()) + 8)
    req_h = max(min_h, int(root.winfo_reqheight()) + 8)
    center_on_work_area(root, width=req_w, height=req_h)
    try:
        root.lift()
        root.focus_force()
    except Exception:
        pass
    root.mainloop()
    return result["v"]


def show_info_dialog(title: str, body: str) -> None:
    """Custom OK info dialog, centered on the pointer/primary work area."""
    import tkinter as tk

    def build(frm: Any, finish: Callable[[Any], None]) -> None:
        tk.Label(frm, text=body, justify="left", wraplength=420, anchor="w").pack(
            fill="both", expand=True
        )
        btns = tk.Frame(frm)
        btns.pack(fill="x", pady=(14, 0))
        ok = tk.Button(btns, text="OK", width=12, command=lambda: finish(None))
        ok.pack(side="right")
        try:
            ok.focus_set()
        except Exception:
            pass

    _run_modal_dialog(title=title, build=build, default=None, min_w=440, min_h=160)


def ask_yes_no(title: str, body: str) -> bool:
    """Custom Yes/No dialog. Returns True for Yes."""
    import tkinter as tk

    def build(frm: Any, finish: Callable[[Any], None]) -> None:
        tk.Label(frm, text=body, justify="left", wraplength=420, anchor="w").pack(
            fill="both", expand=True
        )
        btns = tk.Frame(frm)
        btns.pack(fill="x", pady=(14, 0))
        tk.Button(btns, text="Yes", width=12, command=lambda: finish(True)).pack(side="left")
        tk.Button(btns, text="No", width=12, command=lambda: finish(False)).pack(side="right")

    return bool(_run_modal_dialog(title=title, build=build, default=False, min_w=440, min_h=160))


def ask_string_dialog(title: str, prompt: str, *, show: str | None = None) -> str | None:
    """Custom string prompt with OK/Cancel; OK stays fully on-screen.

    Returns the entered string, or None if cancelled / empty after strip is
    left to the caller (raw value returned; empty string possible).
    """
    import tkinter as tk

    entry_holder: dict[str, Any] = {}

    def build(frm: Any, finish: Callable[[Any], None]) -> None:
        tk.Label(frm, text=prompt, justify="left", wraplength=420, anchor="w").pack(
            fill="both", expand=True
        )
        entry = tk.Entry(frm, width=48, show=show if show else "")
        entry.pack(fill="x", pady=(12, 0))
        entry_holder["e"] = entry
        try:
            entry.focus_set()
        except Exception:
            pass

        def on_ok() -> None:
            finish(entry.get())

        def on_cancel() -> None:
            finish(None)

        btns = tk.Frame(frm)
        btns.pack(fill="x", pady=(14, 0))
        # OK on the right so growth/clamp cannot clip it off the left edge
        tk.Button(btns, text="Cancel", width=12, command=on_cancel).pack(side="left")
        ok = tk.Button(btns, text="OK", width=12, command=on_ok)
        ok.pack(side="right")
        try:
            entry.bind("<Return>", lambda _e: on_ok())
            entry.bind("<Escape>", lambda _e: on_cancel())
        except Exception:
            pass

    return _run_modal_dialog(title=title, build=build, default=None, min_w=460, min_h=180)


def show_screen_recording_dialog(body: str, *, title: str = "WoW Grok — Screen Recording") -> str:
    """Centered dialog with Quit / Continue (same work-area helper).

    Returns ``\"quit\"`` or ``\"continue\"``.
    """
    import tkinter as tk

    def build(frm: Any, finish: Callable[[Any], None]) -> None:
        tk.Label(frm, text=body, justify="left", wraplength=420, anchor="w").pack(
            fill="both", expand=True
        )
        btns = tk.Frame(frm)
        btns.pack(fill="x", pady=(14, 0))
        tk.Button(btns, text="Continue", width=14, command=lambda: finish("continue")).pack(
            side="left"
        )
        tk.Button(btns, text="Quit WoWGrok", width=14, command=lambda: finish("quit")).pack(
            side="right"
        )

    return str(
        _run_modal_dialog(
            title=title, build=build, default="continue", min_w=460, min_h=240
        )
    )
