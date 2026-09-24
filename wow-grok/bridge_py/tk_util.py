"""Shared tkinter helpers (dialog placement on multi-monitor Macs)."""
from __future__ import annotations

import subprocess
import sys
from typing import Any


def primary_work_area() -> tuple[int, int, int, int]:
    """Return ``(x, y, w, h)`` of the primary display's visible work area in Tk coords.

    Tk/Aqua uses ``+0+0`` as the **top-left of the primary (menu-bar) display**,
    with a secondary monitor to the left at negative ``x``. Centering with
    ``winfo_screenwidth()`` (full virtual desktop) or the mouse pointer can place
    dialogs off the left edge. Prefer ``NSScreen.mainScreen.visibleFrame``.
    """
    if sys.platform != "darwin":
        return (0, 0, 1280, 800)
    jxa = r"""
ObjC.import('AppKit');
var s = $.NSScreen.mainScreen;
if (!s) { '0,0,1280,800'; }
else {
  var mf = s.frame;
  var vf = s.visibleFrame;
  // Cocoa: origin bottom-left, y up. Tk: origin top-left of primary, y down.
  // Map visible-frame top-left into Tk primary-relative coordinates.
  var mainTop = mf.origin.y + mf.size.height;
  var visTop = vf.origin.y + vf.size.height;
  var tkX = Math.round(vf.origin.x - mf.origin.x);
  var tkY = Math.round(mainTop - visTop);
  var tkW = Math.round(vf.size.width);
  var tkH = Math.round(vf.size.height);
  [tkX, tkY, tkW, tkH].join(',');
}
"""
    try:
        r = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", jxa],
            capture_output=True,
            text=True,
            timeout=2.5,
        )
        if r.returncode != 0:
            raise RuntimeError(r.stderr or "osascript failed")
        parts = [int(float(x)) for x in (r.stdout or "").strip().split(",")]
        if len(parts) != 4 or parts[2] < 200 or parts[3] < 200:
            raise RuntimeError(f"bad frame: {parts}")
        return parts[0], parts[1], parts[2], parts[3]
    except Exception:
        return 0, 22, 1280, 720


def center_on_primary(win: Any, width: int | None = None, height: int | None = None) -> None:
    """Place ``win`` centered on the primary display work area; fully on-screen."""
    try:
        win.update_idletasks()
    except Exception:
        pass
    try:
        w = int(width if width is not None else win.winfo_reqwidth() or 440)
        h = int(height if height is not None else win.winfo_reqheight() or 220)
    except Exception:
        w, h = 440, 220
    w = max(200, w)
    h = max(120, h)
    px, py, pw, ph = primary_work_area()
    # Ensure window fits; shrink slightly if needed
    w = min(w, max(200, pw - 48))
    h = min(h, max(120, ph - 48))
    x = px + max(0, (pw - w) // 2)
    y = py + max(0, (ph - h) // 3)
    x = min(max(x, px + 12), px + pw - w - 12)
    y = min(max(y, py + 12), py + ph - h - 12)
    try:
        win.geometry(f"{w}x{h}+{int(x)}+{int(y)}")
    except Exception:
        try:
            win.geometry(f"+{int(x)}+{int(y)}")
        except Exception:
            pass


# Back-compat alias (callers may still import the old name)
def center_on_pointer(win: Any, width: int | None = None, height: int | None = None) -> None:
    center_on_primary(win, width=width, height=height)


def prepare_dialog_root(root: Any) -> Any:
    """Withdrawn root positioned on the primary display for child messageboxes."""
    try:
        root.withdraw()
    except Exception:
        pass
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass
    # Visible 1×1 anchor on primary so native messageboxes inherit a good position
    try:
        root.geometry("1x1")
        center_on_primary(root, width=1, height=1)
        root.deiconify()
        root.update_idletasks()
        root.withdraw()
    except Exception:
        center_on_primary(root, width=10, height=10)
    return root


def show_screen_recording_dialog(body: str, *, title: str = "WoW Grok — Screen Recording") -> str:
    """Primary-centered dialog with Quit / Continue.

    Returns ``\"quit\"`` or ``\"continue\"``.
    """
    import tkinter as tk

    result = {"v": "continue"}
    root = tk.Tk()
    root.title(title)
    root.resizable(True, True)
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass

    frm = tk.Frame(root, padx=18, pady=14)
    frm.pack(fill="both", expand=True)
    lbl = tk.Label(frm, text=body, justify="left", wraplength=420, anchor="w")
    lbl.pack(fill="both", expand=True)

    btns = tk.Frame(frm)
    btns.pack(fill="x", pady=(14, 0))

    def finish(choice: str) -> None:
        result["v"] = choice
        try:
            root.destroy()
        except Exception:
            pass

    tk.Button(btns, text="Continue", width=14, command=lambda: finish("continue")).pack(
        side="left"
    )
    tk.Button(btns, text="Quit WoWGrok", width=14, command=lambda: finish("quit")).pack(side="right")

    root.protocol("WM_DELETE_WINDOW", lambda: finish("continue"))
    root.update_idletasks()
    # Size from content, then force onto primary
    req_w = max(460, int(root.winfo_reqwidth()) + 8)
    req_h = max(240, int(root.winfo_reqheight()) + 8)
    center_on_primary(root, width=req_w, height=req_h)
    try:
        root.lift()
        root.focus_force()
    except Exception:
        pass

    root.mainloop()
    return result["v"]
