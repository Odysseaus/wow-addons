"""macOS menu bar status item — quiet companion after first-run.

On darwin with rumps available, the bridge main thread runs a status item
instead of a blank wait loop. First-run / install still use Tk beforehand.
Menu: a disabled **WoWGrok <version>** row (so a wrong binary is obvious),
**Setup…** re-opens the onboard wizard (Connect your AI) on demand;
**Quit WoWGrok**.

Windows system tray: not in this release (optional future stub).
"""
from __future__ import annotations

import subprocess
import sys
from typing import Any

SETUP_MENU_TITLE = "Setup…"
# Matches supervisor.RESTART_EXIT_CODE (kept literal: no import cycle / AppKit-free).
RESTART_EXIT_CODE = 75
# first_run.run_setup_wizard_on_demand exit codes
_SETUP_APPLIED = 0


def menu_version_label(version: str | None = None) -> str:
    """Disabled menu-row title showing the running package version.

    Pure helper (no rumps): ``WoWGrok 0.1.31`` from ``bridge_py.__version__`` so a
    wrong-binary launch (e.g. an old ``~/wowgrok-build-*`` copy) is obvious in the
    menu bar dropdown.
    """
    if version is None:
        from . import __version__ as pkg_version

        version = str(pkg_version)
    return f"WoWGrok {version}"


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


def setup_wizard_command() -> list[str]:
    """argv that re-opens the onboard wizard in a separate process.

    Frozen app: re-invoke the bundle binary (``exe -m`` does not work there).
    Source run: ``python -m bridge_py --onboard-setup``.
    """
    if getattr(sys, "frozen", False):
        return [sys.executable, "--onboard-setup"]
    return [sys.executable, "-m", "bridge_py", "--onboard-setup"]


def setup_result_action(returncode: int | None) -> str:
    """Map the Setup… child exit code to ``restart`` | ``none``.

    ``0`` means provider / key / AddOns changed and were saved, so the running
    bridge must restart to pick them up. Anything else (unchanged, cancelled,
    crash) leaves the running bridge alone.
    """
    return "restart" if returncode == _SETUP_APPLIED else "none"


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

    **Setup…** re-opens the onboard wizard (Connect your AI) in a child process
    (``--onboard-setup``) so Tk never runs inside the rumps/AppKit run loop. The
    menu stays live meanwhile. If the wizard changed provider / key / AddOns the
    status item exits with :data:`RESTART_EXIT_CODE` and the supervisor
    relaunches the bridge with the new config (menu bar icon blinks once);
    otherwise nothing restarts.
    """
    if not available():
        raise RuntimeError("menubar.run_status_item requires darwin + rumps")

    import rumps

    state: dict[str, Any] = {"rc": 0, "setup_proc": None}

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
            # Disabled row: package version (wrong-binary launches are obvious).
            version_row = rumps.MenuItem(menu_version_label())
            version_row.set_callback(None)
            self.menu = [
                version_row,
                self._status,
                None,
                rumps.MenuItem(SETUP_MENU_TITLE, callback=self._setup),
                None,
                rumps.MenuItem("Quit WoWGrok", callback=self._quit),
            ]

        def _quit(self, _sender: Any = None) -> None:
            _do_quit()

        def _setup(self, _sender: Any = None) -> None:
            proc = state.get("setup_proc")
            if proc is not None and proc.poll() is None:
                return  # wizard already open
            try:
                state["setup_proc"] = subprocess.Popen(setup_wizard_command())
                self._status.title = "Setup open…"
            except Exception as e:  # noqa: BLE001
                state["setup_proc"] = None
                rumps.alert(
                    title="WoW Grok — Setup",
                    message=f"Could not open Setup: {e}",
                )

        def _poll_setup(self) -> None:
            proc = state.get("setup_proc")
            if proc is None:
                return
            code = proc.poll()
            if code is None:
                return
            state["setup_proc"] = None
            self._status.title = "Running"
            if setup_result_action(code) == "restart":
                state["rc"] = RESTART_EXIT_CODE
                _do_quit()

        @rumps.timer(0.2)
        def _tick(self, _sender: Any) -> None:
            if stop_event.is_set():
                rumps.quit_application()
                return
            self._poll_setup()
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
    return int(state["rc"])
