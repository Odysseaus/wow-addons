"""Install main WoWGrok addon (+ reply slots) into Interface/AddOns."""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from . import install_slots as slots_mod

# Bundle files to copy. Inbox.lua is owned by the bridge at runtime — never
# overwrite an existing one.
MAIN_COPY_NAMES = ("WoWGrok.toc", "WoWGrok.lua", "Codec.lua", "Inbox.lua")


class InstallError(Exception):
    """Raised when the main addon or reply slots cannot be installed."""


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def addon_bundle_dir() -> Path:
    """Resolve ``addon/WoWGrok`` from the repo root or PyInstaller ``sys._MEIPASS``."""
    candidates: list[Path] = []
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        candidates.append(Path(meipass) / "addon" / "WoWGrok")
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        candidates.append(exe_dir / "addon" / "WoWGrok")
        # onedir / .app: datas may sit one level up from MacOS
        candidates.append(exe_dir.parent / "Resources" / "addon" / "WoWGrok")
        candidates.append(exe_dir.parent / "Frameworks" / "addon" / "WoWGrok")
    candidates.append(repo_root() / "addon" / "WoWGrok")
    for p in candidates:
        if (p / "WoWGrok.toc").is_file():
            return p
    raise InstallError(
        "addon bundle not found (expected addon/WoWGrok with WoWGrok.toc "
        "under the repo root or the frozen app datas)"
    )


def install_main_addon(addons: Path) -> int:
    """Copy toc/lua into ``addons/WoWGrok``.

    Skips overwriting ``Inbox.lua`` when it already exists (bridge owns it).
    Returns the number of files written.
    """
    src = addon_bundle_dir()
    dest = Path(addons) / "WoWGrok"
    dest.mkdir(parents=True, exist_ok=True)
    written = 0
    for name in MAIN_COPY_NAMES:
        s = src / name
        if not s.is_file():
            continue
        d = dest / name
        if name == "Inbox.lua" and d.exists():
            continue
        shutil.copy2(s, d)
        written += 1
    if not (dest / "WoWGrok.toc").is_file():
        raise InstallError(f"failed to install WoWGrok.toc into {dest}")
    return written


def ensure_game_files(cfg: dict, *, gui: bool = False) -> tuple[int, int, int]:
    """Install main addon + reply slots into ``cfg['addonDir']``.

    Returns ``(main_written, slots_made, slots_kept)``.
    Does not call ``sys.exit`` — raises :class:`InstallError` on failure.
    When ``gui`` is True and install work is needed, shows brief tk dialogs.
    """
    addons_raw = cfg.get("addonDir") or ""
    if not addons_raw:
        raise InstallError("config missing addonDir")
    addons = Path(addons_raw)
    if not addons.is_dir():
        raise InstallError(f"addonDir is not a directory: {addons}")

    need_main = not (addons / "WoWGrok" / "WoWGrok.toc").is_file()
    need_slots = not (addons / "WoWGrok_S001" / "Inbox.lua").is_file()
    show_ui = bool(gui) and (need_main or need_slots)

    root = None
    messagebox = None
    if show_ui:
        try:
            import tkinter as tk
            from tkinter import messagebox as mb

            messagebox = mb
            root = tk.Tk()
            root.withdraw()
            try:
                root.attributes("-topmost", True)
            except Exception:
                pass
            messagebox.showinfo(
                "WoW Grok — installing",
                "Installing the WoW Grok addon and reply slots into your "
                "AddOns folder.\n\nThis can take about a minute — please wait.",
                parent=root,
            )
            root.update()
        except Exception:
            show_ui = False
            if root is not None:
                try:
                    root.destroy()
                except Exception:
                    pass
                root = None
            messagebox = None

    main_written = made = kept = 0
    ok = False
    try:
        main_written = install_main_addon(addons)
        made, kept = slots_mod.install_slots(cfg)
        ok = True
    except slots_mod.InstallError as e:
        raise InstallError(str(e)) from e
    except Exception as e:
        raise InstallError(str(e)) from e
    finally:
        if show_ui and root is not None:
            if ok and messagebox is not None:
                try:
                    messagebox.showinfo(
                        "WoW Grok — install done",
                        "Addon and reply slots are installed.\n\n"
                        "Fully quit World of Warcraft (not just /reload) and "
                        "relaunch it, then enable WoW Grok at character select.",
                        parent=root,
                    )
                except Exception:
                    pass
            try:
                root.destroy()
            except Exception:
                pass

    return main_written, made, kept
