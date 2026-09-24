"""Create WoWGrok_S001–S200 slot addons and signal WAV stubs (ported from install-slots.js)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import config as cfgmod
from .protocol import SILENT_WAV, pad3


class InstallError(Exception):
    """Raised when reply slots cannot be installed (library callers)."""


def install_slots(cfg: dict | None = None) -> tuple[int, int]:
    """Create slot addons + signal wav stubs under ``cfg['addonDir']``.

    Returns ``(made, kept)``. Raises :class:`InstallError` instead of
    ``sys.exit`` so library callers (first-run install) can handle errors.
    """
    if cfg is None:
        cfg = cfgmod.load_config()
    if not cfg:
        raise InstallError("No config.json — run the bridge once to create it.")
    addons = Path(cfg["addonDir"])
    n = int(cfg.get("slots") or 200)
    act = int(cfg.get("actMax") or 60)
    presence = int(cfg.get("presenceMax") or 2000)
    iface = str(cfg.get("tocInterface") or "16001")

    if not (addons / "WoWGrok" / "WoWGrok.toc").exists():
        raise InstallError(f"WoWGrok addon not found under {addons}")

    made = 0
    kept = 0

    def ensure(file: Path, content: bytes | str) -> None:
        nonlocal made, kept
        if file.exists():
            kept += 1
            return
        file.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            file.write_bytes(content)
        else:
            file.write_text(content, encoding="utf-8")
        made += 1

    for i in range(1, n + 1):
        name = f"WoWGrok_S{pad3(i)}"
        d = addons / name
        toc = (
            f"## Interface: {iface}\n"
            f"## Title: WoW Grok slot {pad3(i)}\n"
            "## Notes: Reply slot for WoW Grok. Load-on-demand; leave it enabled.\n"
            "## LoadOnDemand: 1\n"
            "## Dependencies: WoWGrok\n"
            "\n"
            "Inbox.lua\n"
            "\n"
        )
        ensure(d / f"{name}.toc", toc)
        ensure(d / "Inbox.lua", "WoWGrok_SlotData = nil\n")
        ensure(addons / "WoWGrok" / "sig" / f"{pad3(i)}.wav", b"")
        ensure(addons / "WoWGrok" / "ack" / f"{pad3(i)}.wav", b"")
        for k in range(1, act + 1):
            ensure(
                addons / "WoWGrok" / "act" / pad3(i) / f"{str(k).zfill(2)}.wav",
                b"",
            )

    for k in range(1, presence + 1):
        ensure(addons / "WoWGrok" / "presence" / f"{str(k).zfill(4)}.wav", b"")

    ensure(addons / "WoWGrok" / "ctl" / "empty.wav", b"")
    ensure(addons / "WoWGrok" / "ctl" / "valid.wav", SILENT_WAV)

    print(f"slots: {n}  files created: {made}  already present: {kept}")
    if made > 0:
        print("Now fully quit and relaunch WoW so it sees the new files.")
    return made, kept


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Install WoWGrok reply-slot addons")
    ap.parse_args(argv)
    try:
        install_slots()
    except InstallError as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
