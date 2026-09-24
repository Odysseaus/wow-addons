"""macOS menu bar status item — quiet companion after first-run.

On darwin with rumps available, the bridge main thread runs a status item
instead of a blank wait loop. First-run / install still use Tk beforehand.

Windows system tray: see tray_win.py (Running + Quit).
"""
from __future__ import annotations

import sys
from typing import Any


def available() -> bool:
    """True when we can run a menu bar status item (darwin + rumps)."""
    if sys.platform != "darwin":
        return False
    try:
        import rumps  # noqa: F401
    except ImportError:
        return False
    return True


def _screen_recording_body(msg: str) -> str:
    return (
        "Screen capture is paused so macOS stops asking repeatedly.\n\n"
        f"{msg}\n\n"
        "1. System Settings → Privacy & Security → Screen Recording "
        "(or Screen & System Audio Recording)\n"
        "2. Turn WoWGrok ON\n"
        "3. Choose Quit WoWGrok, then reopen from /Applications\n\n"
        "SavedVariables /reload still works without capture."
    )


def _alert_screen_recording(msg: str) -> str:
    """AppKit alert via rumps. Returns ``quit`` or ``continue``."""
    import rumps

    body = _screen_recording_body(msg)
    # ok → 1, cancel → 0
    choice = rumps.alert(
        title="WoW Grok — Screen Recording",
        message=body,
        ok="Continue",
        cancel="Quit WoWGrok",
    )
    return "continue" if choice == 1 else "quit"


def run_status_item(
    *,
    stop_event: Any,
    screen_ui: dict[str, Any],
    on_quit: Any | None = None,
) -> int:
    """Block on the main thread with a menu bar item until Quit / stop_event.

    Must be called from the process main thread (AppKit requirement).
    Returns 0 so the supervisor treats a clean Quit as exit success.

    If ``on_quit`` is provided, Quit / screen-recording quit call it (expected
    to set ``stop_event`` and tear down capture) before ``rumps.quit_application``.
    """
    if not available():
        raise RuntimeError("menubar.run_status_item requires darwin + rumps")

    import rumps

    def _do_quit() -> None:
        if on_quit is not None:
            on_quit()
        else:
            stop_event.set()
        rumps.quit_application()

    class WoWGrokStatusApp(rumps.App):
        def __init__(self) -> None:
            super().__init__(
                "WoWGrok",
                title="WoWGrok",
                quit_button=None,
            )
            self._status = rumps.MenuItem("Running")
            self.menu = [
                self._status,
                None,
                rumps.MenuItem("Quit WoWGrok", callback=self._quit),
            ]

        def _quit(self, _sender: Any = None) -> None:
            _do_quit()

        @rumps.timer(0.2)
        def _tick(self, _sender: Any) -> None:
            if stop_event.is_set():
                rumps.quit_application()
                return
            if not screen_ui.get("pending"):
                return
            screen_ui["pending"] = False
            try:
                result = _alert_screen_recording(str(screen_ui.get("msg") or ""))
            except Exception:
                result = "continue"
            screen_ui["result"] = result
            if result == "quit":
                _do_quit()
            screen_ui["event"].set()

    WoWGrokStatusApp().run()
    return 0
