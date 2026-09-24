"""Shared tkinter helpers (dialog placement on multi-monitor Macs)."""
from __future__ import annotations

from typing import Any


def center_on_pointer(win: Any, width: int | None = None, height: int | None = None) -> None:
    """Place ``win`` near the mouse, clamped to the virtual desktop.

    Default Tk + withdrawn parents often open messageboxes at the far left of a
    multi-monitor layout (clipped off-screen). Anchoring to the pointer keeps
    dialogs on the display the user is actually using.
    """
    try:
        win.update_idletasks()
    except Exception:
        return
    try:
        w = int(width if width is not None else win.winfo_reqwidth() or 400)
        h = int(height if height is not None else win.winfo_reqheight() or 200)
    except Exception:
        w, h = 400, 200
    try:
        px, py = win.winfo_pointerxy()
    except Exception:
        try:
            px = win.winfo_screenwidth() // 2
            py = win.winfo_screenheight() // 3
        except Exception:
            px, py = 200, 200
    x = int(px - w // 2)
    y = int(py - h // 3)
    try:
        vx = int(win.winfo_vrootx())
        vy = int(win.winfo_vrooty())
        vw = int(win.winfo_vrootwidth() or win.winfo_screenwidth())
        vh = int(win.winfo_vrootheight() or win.winfo_screenheight())
        x = min(max(x, vx + 24), max(vx + 24, vx + vw - w - 24))
        y = min(max(y, vy + 24), max(vy + 24, vy + vh - h - 24))
    except Exception:
        x = max(24, x)
        y = max(24, y)
    try:
        win.geometry(f"+{x}+{y}")
    except Exception:
        pass


def prepare_dialog_root(root: Any) -> Any:
    """Withdrawn root positioned so child messageboxes appear on-screen."""
    try:
        root.withdraw()
    except Exception:
        pass
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass
    center_on_pointer(root, width=10, height=10)
    try:
        root.update_idletasks()
    except Exception:
        pass
    return root
