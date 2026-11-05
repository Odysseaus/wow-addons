"""Install main WoWGrok addon (+ reply slots) into Interface/AddOns."""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from . import install_slots as slots_mod
from . import tk_util

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


# Files the startup sync may replace. Never Inbox.lua (the bridge writes it at
# runtime) and never the runtime folders (ack/act/ctl/presence/sig) or WTF.
SYNC_COPY_NAMES = ("Codec.lua", "WoWGrok.lua", "WoWGrok.toc")


def toc_version(toc: Path) -> tuple[int, ...] | None:
    """``## Version: 0.1.34`` -> (0, 1, 34); None when missing/unreadable."""
    try:
        text = Path(toc).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        line = line.strip()
        if line.lower().startswith("## version:"):
            raw = line.split(":", 1)[1].strip()
            parts = []
            for piece in raw.split("."):
                digits = "".join(ch for ch in piece if ch.isdigit())
                if not digits:
                    break
                parts.append(int(digits))
            return tuple(parts) or None
    return None


def sync_addon_if_older(
    addons_dir: str | Path | None,
    backup_root: str | Path,
    *,
    src: Path | None = None,
    log=print,
) -> str | None:
    """Update ``addons/WoWGrok`` from the bundled addon when it is older.

    Copies only Codec.lua, WoWGrok.lua and WoWGrok.toc after backing up the
    installed .lua/.toc files to ``backup_root/<timestamp>``. Same or newer
    installed versions are left alone. Returns the new version string when it
    updated, else None. Never raises.
    """
    import time

    try:
        if not addons_dir or not Path(addons_dir).is_dir():
            log(f"addon sync: addonDir missing ({addons_dir!r}); skipped")
            return None
        src = Path(src) if src else addon_bundle_dir()
        new_v = toc_version(src / "WoWGrok.toc")
        if not new_v:
            log("addon sync: bundled WoWGrok.toc has no version; skipped")
            return None
        dest = Path(addons_dir) / "WoWGrok"
        old_v = toc_version(dest / "WoWGrok.toc")
        if old_v is not None and old_v >= new_v:
            return None
        if dest.is_dir():
            stamp = time.strftime("%Y%m%d-%H%M%S")
            bdir = Path(backup_root) / f"addon-backup-{stamp}"
            n = 1
            while bdir.exists():
                n += 1
                bdir = Path(backup_root) / f"addon-backup-{stamp}-{n}"
            bdir.mkdir(parents=True)
            for f in dest.iterdir():
                if f.is_file() and f.suffix.lower() in (".lua", ".toc"):
                    shutil.copy2(f, bdir / f.name)
        dest.mkdir(parents=True, exist_ok=True)
        for name in SYNC_COPY_NAMES:
            if (src / name).is_file():
                shutil.copy2(src / name, dest / name)
        ver = ".".join(str(x) for x in new_v)
        old = ".".join(str(x) for x in old_v) if old_v else "none"
        log(f"Add-on updated to {ver} (was {old}), /reload in game")
        return ver
    except Exception as e:  # never block bridge startup
        log(f"addon sync: failed: {e}")
        return None


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

    root.update_idletasks()
    w, h = 460, 160
    try:
        root.geometry(f"{w}x{h}")
    except Exception:
        pass
    tk_util.center_on_pointer(root, width=w, height=h)

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
