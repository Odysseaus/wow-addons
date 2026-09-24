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


def _install_progress_ui():
    """Non-modal progress window with an always-clickable OK when done.

    Avoids ``messagebox.showinfo`` after a long install: on macOS that pattern
    often freezes (spinning beachball) when Screen Recording / other sheets
    appear, leaving the user unable to dismiss the dialog.
    """
    import tkinter as tk

    root = tk.Tk()
    root.title("WoW Grok")
    root.resizable(False, False)
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass

    status = tk.StringVar(
        value=(
            "Installing the WoW Grok addon and reply slots into your "
            "AddOns folder.\n\nThis can take about a minute — please wait."
        )
    )
    lbl = tk.Label(
        root,
        textvariable=status,
        justify="left",
        wraplength=420,
        padx=16,
        pady=12,
    )
    lbl.pack(fill="both", expand=True)

    btn = tk.Button(root, text="OK", width=10, state="disabled")
    btn.pack(pady=(0, 12))

    closed = {"done": False}

    def close() -> None:
        closed["done"] = True
        try:
            root.destroy()
        except Exception:
            pass

    btn.configure(command=close)
    root.protocol("WM_DELETE_WINDOW", close)

    # Center roughly
    root.update_idletasks()
    w, h = 460, 160
    try:
        sw = root.winfo_screenwidth()
        sh = root.winfo_screenheight()
        root.geometry(f"{w}x{h}+{(sw - w) // 2}+{(sh - h) // 3}")
    except Exception:
        root.geometry(f"{w}x{h}")

    def pump() -> None:
        try:
            root.update_idletasks()
            root.update()
        except Exception:
            pass

    def set_done(msg: str) -> None:
        status.set(msg)
        btn.configure(state="normal")
        try:
            btn.focus_set()
        except Exception:
            pass
        pump()

    def wait_ok() -> None:
        """Block until OK / window close, while keeping the UI alive."""
        import time

        while not closed["done"]:
            try:
                root.update()
            except tk.TclError:
                break
            time.sleep(0.05)

    return root, pump, set_done, wait_ok, close


def ensure_game_files(cfg: dict, *, gui: bool = False) -> tuple[int, int, int]:
    """Install main addon + reply slots into ``cfg['addonDir']``.

    Returns ``(main_written, slots_made, slots_kept)``.
    Does not call ``sys.exit`` — raises :class:`InstallError` on failure.
    When ``gui`` is True and install work is needed, shows a dismissible progress window.
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

    ui = None
    if show_ui:
        try:
            ui = _install_progress_ui()
            ui[1]()  # pump once so the window appears before the long copy
        except Exception:
            show_ui = False
            ui = None

    main_written = made = kept = 0
    err: Exception | None = None
    try:
        main_written = install_main_addon(addons)
        if ui is not None:
            ui[1]()
        made, kept = slots_mod.install_slots(cfg)
        if ui is not None:
            ui[1]()
    except slots_mod.InstallError as e:
        err = InstallError(str(e))
    except Exception as e:
        err = InstallError(str(e))

    if ui is not None:
        _root, pump, set_done, wait_ok, close = ui
        try:
            if err is None:
                set_done(
                    "Addon and reply slots are installed.\n\n"
                    "Fully quit World of Warcraft (not just /reload) and "
                    "relaunch it, then enable WoW Grok at character select.\n\n"
                    "Click OK to continue."
                )
            else:
                set_done(
                    f"Install failed:\n\n{err}\n\n"
                    "Click OK, fix the AddOns path if needed, and re-run WoWGrok."
                )
            wait_ok()
        except Exception:
            try:
                close()
            except Exception:
                pass

    if err is not None:
        raise err
    return main_written, made, kept
