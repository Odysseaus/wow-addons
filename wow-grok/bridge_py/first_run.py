"""First-run UI: xAI API key popup + AddOns folder picker (tkinter)."""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any

from . import config as cfgmod
from . import setup_detect


def _tk():
    """Lazy import so headless / servers without tkinter still load the package."""
    import tkinter as tk
    from tkinter import filedialog, messagebox, simpledialog
    return tk, filedialog, messagebox, simpledialog


def _ensure_root():
    tk, _, _, _ = _tk()
    root = tk.Tk()
    root.withdraw()
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass
    return root


def _gui_available() -> bool:
    if sys.platform in ("darwin", "win32"):
        return True
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def prompt_api_key(parent=None) -> str | None:
    """Ask for xAI API key. Returns key or None if cancelled. Never logs the value."""
    tk, _, messagebox, simpledialog = _tk()
    own = parent is None
    root = parent or _ensure_root()
    try:
        messagebox.showinfo(
            "WoW Grok — API key",
            "WoW Grok needs an xAI API key to chat with Grok.\n\n"
            "Your key is stored ONLY in a local config.json on this computer "
            "(next to the bridge). It is never uploaded, never sent to the WoW "
            "addon, and never written into Lua.\n\n"
            "Get a key at https://console.x.ai/",
            parent=root,
        )
        key = simpledialog.askstring(
            "WoW Grok — xAI API key",
            "Paste your xAI API key (starts with xai-…):\n"
            "(Stored locally only in config.json — not uploaded, not in the addon.)",
            parent=root,
            show="*",
        )
        if key is None:
            return None
        key = key.strip()
        return key or None
    finally:
        if own:
            root.destroy()


def prompt_addons_dir(
    candidates: list[Path] | None = None,
    parent=None,
) -> Path | None:
    """Pick Interface/AddOns (or WoW root). Returns normalized AddOns path."""
    tk, filedialog, messagebox, _ = _tk()
    own = parent is None
    root = parent or _ensure_root()
    try:
        candidates = candidates if candidates is not None else setup_detect.find_existing_addons()
        if len(candidates) == 1:
            if messagebox.askyesno(
                "WoW Grok — AddOns folder",
                f"Found World of Warcraft AddOns at:\n\n{candidates[0]}\n\nUse this folder?",
                parent=root,
            ):
                return candidates[0]
        elif len(candidates) > 1:
            # Simple chooser via numbered message + folder dialog fallback
            listing = "\n".join(f"  {i+1}. {c}" for i, c in enumerate(candidates[:12]))
            messagebox.showinfo(
                "WoW Grok — multiple AddOns folders",
                "Several World of Warcraft AddOns folders were found:\n\n"
                f"{listing}\n\n"
                "Next you will pick the correct Interface/AddOns folder "
                "(or the WoW client / flavor folder).",
                parent=root,
            )
        else:
            messagebox.showinfo(
                "WoW Grok — locate AddOns",
                "Could not auto-find World of Warcraft.\n\n"
                "Select your Interface/AddOns folder, or the WoW client folder "
                "(e.g. …/World of Warcraft/_classic_beta_).\n\n"
                "GeForce Now / cloud WoW is NOT supported — the bridge must run "
                "on the same PC as a local WoW install.",
                parent=root,
            )

        chosen = filedialog.askdirectory(
            parent=root,
            title="Select WoW Interface/AddOns (or WoW client folder)",
            mustexist=True,
        )
        if not chosen:
            return None
        normalized = setup_detect.normalize_addons_selection(chosen)
        if not normalized:
            messagebox.showerror(
                "WoW Grok",
                "That path does not look like Interface/AddOns or a WoW client folder.\n"
                "Expected …/Interface/AddOns or …/_classic_beta_ (etc).",
                parent=root,
            )
            return None
        return normalized
    finally:
        if own:
            root.destroy()


def ensure_first_run_config(
    *,
    headless: bool = False,
    wow: str | None = None,
) -> dict[str, Any]:
    """Load or create config; prompt for API key + AddOns if needed.

    After addonDir + apiKey are set and config is saved, installs the main
    addon and reply slots into Interface/AddOns (GUI shows progress dialogs).

    headless: skip UI (CLI --wow / env only); exit 2 if incomplete.
    """
    cfg = cfgmod.load_config()
    if cfg is None:
        cfg = cfgmod.load_example()

    # AddOns path
    if wow:
        norm = setup_detect.normalize_addons_selection(wow)
        if not norm:
            print(f'--wow "{wow}" is not a WoW AddOns/client folder', file=sys.stderr)
            sys.exit(2)
        cfg = cfgmod.derive_paths_from_addon_dir(cfg, str(norm))
        client = Path(norm).parent.parent
        accounts = setup_detect.find_accounts(client)
        if accounts:
            cfg = cfgmod.derive_paths_from_addon_dir(cfg, str(norm), accounts[0])
        cap = cfg.setdefault("capture", {})
        cap["processName"] = setup_detect.detect_process_name(client)
    elif not cfg.get("addonDir") or not Path(cfg["addonDir"]).is_dir():
        existing = setup_detect.find_existing_addons()
        if headless:
            if len(existing) == 1:
                cfg = cfgmod.derive_paths_from_addon_dir(cfg, str(existing[0]))
            else:
                print(
                    "No addonDir in config. Pass --wow <path> or run without --headless "
                    "for the folder picker.",
                    file=sys.stderr,
                )
                sys.exit(2)
        else:
            picked = prompt_addons_dir(existing)
            if not picked:
                print("AddOns folder required.", file=sys.stderr)
                sys.exit(2)
            cfg = cfgmod.derive_paths_from_addon_dir(cfg, str(picked))
            client = picked.parent.parent
            accounts = setup_detect.find_accounts(client)
            if accounts:
                cfg = cfgmod.derive_paths_from_addon_dir(cfg, str(picked), accounts[0])
            cap = cfg.setdefault("capture", {})
            cap["processName"] = setup_detect.detect_process_name(client)

    if not cfg.get("defaultCwd"):
        cfg["defaultCwd"] = os.getcwd()

    # API key
    if not cfgmod.has_api_key(cfg):
        if headless:
            print(
                "Missing xAI API key. Set XAI_API_KEY or apiKey in config.json.",
                file=sys.stderr,
            )
            sys.exit(2)
        if os.environ.get("DISPLAY") is None and sys.platform.startswith("linux"):
            # No display: cannot show tk popup
            print(
                "Missing xAI API key and no display for first-run UI. "
                "Set XAI_API_KEY or write apiKey into bridge_py/config.json.",
                file=sys.stderr,
            )
            sys.exit(2)
        key = prompt_api_key()
        if not key:
            print("API key required.", file=sys.stderr)
            sys.exit(2)
        cfg["apiKey"] = key

    cfgmod.save_config(cfg)

    # Copy main addon + create WoWGrok_S001–S200 next to it (idempotent).
    from .install_addon import InstallError, ensure_game_files

    use_gui = (not headless) and _gui_available()
    try:
        ensure_game_files(cfg, gui=use_gui)
    except InstallError as e:
        print(f"Could not install addon/slots: {e}", file=sys.stderr)
        if headless:
            sys.exit(2)
        # GUI path: warn but still return config so bridge can start;
        # bridge banner will remind the user to re-run the app.
        print(
            "Re-run the WoWGrok app after fixing the AddOns path.",
            file=sys.stderr,
        )

    return cfg
