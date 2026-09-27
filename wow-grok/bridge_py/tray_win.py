"""Windows system tray companion — Running + Quit (Mac menubar parity).

Uses pystray + Pillow. Steady-state UI is tray-only (no console when frozen
with console=False). Quit tears down capture via the same on_quit callback
Mac menubar uses.
"""
from __future__ import annotations

import sys
import threading
from typing import Any


def available() -> bool:
    """True when we can run a Windows tray icon (win32 + pystray + Pillow)."""
    if sys.platform != "win32":
        return False
    try:
        import pystray  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        return False
    return True


def _default_icon():
    """Small solid icon so we do not need a .ico asset in the freeze."""
    from PIL import Image, ImageDraw

    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((4, 4, 60, 60), fill=(32, 120, 220, 255))
    draw.ellipse((20, 20, 44, 44), fill=(240, 248, 255, 255))
    return img


def run_status_item(
    *,
    stop_event: Any,
    screen_ui: dict[str, Any] | None = None,
    on_quit: Any | None = None,
) -> int:
    """Block with a tray icon until Quit / stop_event.

    ``screen_ui`` is accepted for Mac API parity; Windows has no Screen
    Recording sheet, so it is unused here.

    Returns 0 so the supervisor treats a clean Quit as exit success.
    """
    if not available():
        raise RuntimeError("tray_win.run_status_item requires win32 + pystray + Pillow")

    import pystray
    from pystray import MenuItem as Item

    # silence unused (Mac parity kwarg)
    _ = screen_ui

    state: dict[str, Any] = {"icon": None}

    def _do_quit(icon: Any | None = None, _item: Any | None = None) -> None:
        if on_quit is not None:
            on_quit()
        else:
            stop_event.set()
        ic = icon or state.get("icon")
        if ic is not None:
            ic.stop()

    def _watch_stop() -> None:
        while not stop_event.wait(0.25):
            pass
        ic = state.get("icon")
        if ic is not None:
            try:
                ic.stop()
            except Exception:
                pass

    menu = pystray.Menu(
        Item("Running", None, enabled=False),
        Item("Quit", _do_quit),
    )
    icon = pystray.Icon("WoWGrok", _default_icon(), "WoWGrok", menu)
    state["icon"] = icon
    watcher = threading.Thread(target=_watch_stop, name="wowgrok-tray-stop", daemon=True)
    watcher.start()
    icon.run()
    return 0
