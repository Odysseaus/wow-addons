"""Entry: first-run UI (via bridge) under supervisor by default."""
from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(
        prog="python -m bridge_py",
        description="WoW Grok Python bridge (supervisor + first-run UI)",
        add_help=False,
    )
    ap.add_argument("-h", "--help", action="store_true")
    ap.add_argument("--no-supervisor", action="store_true")
    ap.add_argument("--install-slots", action="store_true")
    # Forward unknown to bridge
    known, rest = ap.parse_known_args(argv)

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
        from .install_slots import main as slots_main

        return slots_main([])

    # Strip our flags from rest for bridge
    bridge_argv = [a for a in argv if a not in ("--no-supervisor", "--install-slots", "-h", "--help")]

    if known.no_supervisor:
        from .bridge import main as bridge_main

        return bridge_main(bridge_argv)

    from .supervisor import run_supervised

    return run_supervised(bridge_argv)


if __name__ == "__main__":
    raise SystemExit(main())
