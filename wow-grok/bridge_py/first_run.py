"""First-run UI: xAI API key popup + AddOns folder picker (tkinter)."""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path
from typing import Any

from . import config as cfgmod
from . import setup_detect
from . import tk_util


def _tk():
    """Lazy import so headless / servers without tkinter still load the package."""
    import tkinter as tk
    from tkinter import filedialog

    return tk, filedialog


def _ensure_root():
    tk, _ = _tk()
    root = tk.Tk()
    return tk_util.prepare_dialog_root(root)


def _gui_available() -> bool:
    if sys.platform in ("darwin", "win32"):
        return True
    return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def _append_bridge_log(line: str) -> None:
    """Append one line to Application Support / package bridge.log."""
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    text = f"{stamp} {line}\n"
    try:
        path = cfgmod.log_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(text)
    except Exception as e:  # noqa: BLE001 — still surface on stderr
        print(f"[bridge.log write failed] {e}: {line}", file=sys.stderr)


def prompt_api_key(parent=None) -> str | None:
    """Ask for xAI API key. Returns key or None if cancelled. Never logs the value."""
    # parent kept for API compat; custom dialogs own their roots
    _ = parent
    tk_util.show_info_dialog(
        "WoW Grok — API key",
        "WoW Grok needs an xAI API key to chat with Grok.\n\n"
        "Your key is stored ONLY in a local config.json on this computer "
        "(next to the bridge). It is never uploaded, never sent to the WoW "
        "addon, and never written into Lua.\n\n"
        "Get a key at https://console.x.ai/",
    )
    key = tk_util.ask_string_dialog(
        "WoW Grok — xAI API key",
        "Paste your xAI API key (starts with xai-…):\n"
        "(Stored locally only in config.json — not uploaded, not in the addon.)",
        show="*",
    )
    if key is None:
        return None
    key = key.strip()
    return key or None


def prompt_addons_dir(
    candidates: list[Path] | None = None,
    parent=None,
) -> Path | None:
    """Pick Interface/AddOns (or WoW root). Returns normalized AddOns path."""
    tk, filedialog = _tk()
    own = parent is None
    root = parent or _ensure_root()
    try:
        candidates = candidates if candidates is not None else setup_detect.find_existing_addons()
        if len(candidates) == 1:
            if tk_util.ask_yes_no(
                "WoW Grok — AddOns folder",
                f"Found World of Warcraft AddOns at:\n\n{candidates[0]}\n\nUse this folder?",
            ):
                return candidates[0]
        elif len(candidates) > 1:
            listing = "\n".join(f"  {i+1}. {c}" for i, c in enumerate(candidates[:12]))
            tk_util.show_info_dialog(
                "WoW Grok — multiple AddOns folders",
                "Several World of Warcraft AddOns folders were found:\n\n"
                f"{listing}\n\n"
                "Next you will pick the correct Interface/AddOns folder "
                "(or the WoW client / flavor folder).",
            )
        else:
            tk_util.show_info_dialog(
                "WoW Grok — locate AddOns",
                "Could not auto-find World of Warcraft.\n\n"
                "Select your Interface/AddOns folder, or the WoW client folder "
                "(e.g. …/World of Warcraft/_classic_beta_).\n\n"
                "GeForce Now / cloud WoW is NOT supported — the bridge must run "
                "on the same PC as a local WoW install.",
            )

        # Native folder dialog — parent root already centered via prepare_dialog_root
        try:
            root.update_idletasks()
        except Exception:
            pass
        chosen = filedialog.askdirectory(
            parent=root,
            title="Select WoW Interface/AddOns (or WoW client folder)",
            mustexist=True,
        )
        if not chosen:
            return None
        normalized = setup_detect.normalize_addons_selection(chosen)
        if not normalized:
            tk_util.show_info_dialog(
                "WoW Grok",
                "That path does not look like Interface/AddOns or a WoW client folder.\n"
                "Expected …/Interface/AddOns or …/_classic_beta_ (etc).",
            )
            return None
        return normalized
    finally:
        if own:
            try:
                root.destroy()
            except Exception:
                pass


def _mark_screen_recording_onboarded(cfg: dict[str, Any] | None) -> None:
    if cfg is None:
        return
    try:
        cfg["screenRecordingOnboarded"] = True
        cfgmod.save_config(cfg)
    except Exception as e:  # noqa: BLE001
        _append_bridge_log(f"[screen-recording] failed to save onboarded flag: {e}")


def prompt_mac_screen_recording(cfg: dict[str, Any] | None = None) -> None:
    """Show the Screen Recording sheet unless permission is clearly granted.

    Probes via a real in-process 1×1 capture (not window-list alone). Always
    logs probe/request/status/choice to bridge.log. If not clearly granted after
    request, always shows the in-app sheet (do not skip on unsure). On first
    launch after a wipe (no screenRecordingOnboarded), always performs a real
    request so macOS can create a Screen Recording row for WoWGrok.

    Once screenRecordingOnboarded is set, probe at most once per launch and
    never call request_screen_recording again (avoids TCC spam after unsigned
    app replace). Capture still exits 42 on permission failure.
    """
    if sys.platform != "darwin":
        return
    if not _gui_available():
        _append_bridge_log("[screen-recording] skip: no GUI available")
        return

    onboarded = bool(cfg.get("screenRecordingOnboarded")) if cfg else False
    status = "unsure"
    request = None
    probe = None
    try:
        from .capture_mac import probe_screen_recording, request_screen_recording

        request = request_screen_recording
        probe = probe_screen_recording
        status = probe()
        _append_bridge_log(f"[screen-recording] probe={status} onboarded={onboarded}")
    except Exception as e:  # noqa: BLE001
        status = "unsure"
        _append_bridge_log(f"[screen-recording] probe import/error: {e!r} → unsure")

    # After wipe / first launch only: request once so macOS can create a Settings
    # row (even if probe looked granted — old window-list probe false-positived).
    # When already onboarded: probe at most once for logging; never call
    # request_screen_recording again (unsigned-replace TCC thrash / sheet spam).
    if request is not None and not onboarded:
        try:
            req_status = request()
            _append_bridge_log(f"[screen-recording] request={req_status}")
            status = req_status
            if probe is not None:
                try:
                    status = probe()
                    _append_bridge_log(f"[screen-recording] probe_after_request={status}")
                except Exception as e:  # noqa: BLE001
                    _append_bridge_log(f"[screen-recording] probe_after_request error: {e!r}")
        except Exception as e:  # noqa: BLE001
            status = "unsure"
            _append_bridge_log(f"[screen-recording] request error: {e!r} → unsure")
    elif onboarded:
        _append_bridge_log(
            f"[screen-recording] onboarded — skip request (probe={status})"
        )

    if status == "granted":
        _append_bridge_log("[screen-recording] granted — skip sheet")
        _mark_screen_recording_onboarded(cfg)
        return

    # User previously chose Continue (or was marked onboarded) — do not re-nag
    # every launch. Capture exit 42 still shows the guided dialog from the bridge.
    if onboarded and status != "granted":
        _append_bridge_log(
            f"[screen-recording] not granted ({status}) but onboarded — skip sheet"
        )
        return

    try:
        choice = tk_util.show_screen_recording_dialog(
            "Mac capture needs Screen Recording permission for WoWGrok.\n\n"
            "1. Open System Settings → Privacy & Security → Screen Recording "
            "(or Screen & System Audio Recording).\n"
            "2. Turn WoWGrok ON (it should appear after this first launch — "
            "WoWGrok requests access in-process so a Settings row is created).\n"
            "3. Click Quit WoWGrok below, then reopen it from Applications "
            "so the permission sticks.\n\n"
            "Or choose Continue — SavedVariables /reload still works without capture.\n"
            "Launch WoWGrok from /Applications (not from the DMG)."
        )
        _append_bridge_log(f"[screen-recording] sheet_choice={choice} status={status}")
        if choice == "quit":
            sys.exit(0)
        # Continue: remember so we do not re-sheet every launch
        _mark_screen_recording_onboarded(cfg)
    except Exception as e:  # noqa: BLE001
        _append_bridge_log(f"[screen-recording] sheet error: {e!r}")
        raise


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

    from .install_addon import InstallError, ensure_game_files

    use_gui = (not headless) and _gui_available()
    install_ok = True
    try:
        ensure_game_files(cfg, gui=use_gui)
    except InstallError as e:
        install_ok = False
        print(f"Could not install addon/slots: {e}", file=sys.stderr)
        if headless:
            sys.exit(2)
        print(
            "Re-run the WoWGrok app after fixing the AddOns path.",
            file=sys.stderr,
        )

    if install_ok and use_gui and sys.platform == "darwin":
        prompt_mac_screen_recording(cfg)

    return cfg
