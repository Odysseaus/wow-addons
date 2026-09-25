"""Entry: first-run UI (via bridge) under supervisor by default."""
from __future__ import annotations

import argparse
import importlib
import sys

# CA bundle for frozen/non-frozen HTTPS (urllib + children).
try:
    from . import ssl_certs as _ssl_certs

    _ssl_certs.configure()
except Exception:
    pass

# Freeze anchors: importlib lazy loads are invisible to PyInstaller analysis.
from . import bridge as _freeze_bridge  # noqa: F401
from . import supervisor as _freeze_supervisor  # noqa: F401
from . import first_run as _freeze_first_run  # noqa: F401
from . import install_addon as _freeze_install_addon  # noqa: F401
from . import install_slots as _freeze_install_slots  # noqa: F401
from . import setup_detect as _freeze_setup_detect  # noqa: F401
from . import capture_mac as _freeze_capture_mac  # noqa: F401
from . import tk_util as _freeze_tk_util  # noqa: F401
from . import menubar as _freeze_menubar  # noqa: F401


def _load(name: str):
    """Import bridge_py.<name> whether we were started via -m or a frozen script."""
    if __package__:
        return importlib.import_module(f".{name}", __package__)
    return importlib.import_module(f"bridge_py.{name}")


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    # Frozen one-file re-entry: bridge spawns this exe with --run-capture-*
    if argv and argv[0] == "--run-capture-mac":
        return _load("capture_mac").main(argv[1:])
    if argv and argv[0] == "--run-capture-win":
        return _load("capture_win").main(argv[1:])

    ap = argparse.ArgumentParser(
        prog="python -m bridge_py",
        description="WoW Grok Python bridge (supervisor + first-run UI)",
        add_help=False,
    )
    ap.add_argument("-h", "--help", action="store_true")
    ap.add_argument("--no-supervisor", action="store_true")
    ap.add_argument("--install-slots", action="store_true")
    known, _rest = ap.parse_known_args(argv)

    if known.help:
        print(
            "usage: python -m bridge_py [--project DIR] [--wow PATH] [--once] "
            "[--inject TEXT] [--headless] [--no-supervisor] [--install-slots]\n\n"
            "WoW Grok bridge (Python). On first launch, asks for an xAI API key and\n"
            "your WoW Interface/AddOns folder (values stay in local config.json only).\n\n"
            "  --project DIR     default chat folder\n"
            "  --wow PATH        WoW client or AddOns path\n"
            "  --once            one SavedVariables job then exit\n"
            "  --inject TEXT     inject a prompt (test) then exit\n"
            "  --headless        no GUI; require config / env\n"
            "  --no-supervisor   run bridge without restart loop\n"
            "  --install-slots   create WoWGrok_S001–S200 slot addons and exit\n"
        )
        return 0

    if known.install_slots:
        return _load("install_slots").main([])

    bridge_argv = [
        a for a in argv if a not in ("--no-supervisor", "--install-slots", "-h", "--help")
    ]

    if known.no_supervisor:
        return _load("bridge").main(bridge_argv)

    return _load("supervisor").run_supervised(bridge_argv)


if __name__ == "__main__":
    raise SystemExit(main())
