"""First-run UI: provider choice + API key + AddOns folder picker (tkinter).

Shared by the Mac app (DMG) and Windows exe. On **macOS** or **Windows** with a
display, :func:`ensure_first_run_config` auto-opens the two-pane
:mod:`onboard_wizard` (Download → Connect your AI → Say hi in game) **once per
app version bump** (``lastSeenAppVersion`` vs ``__version__``). Same version
never auto-shows the wizard; incomplete setup then uses the sequential tiny
dialogs (or menu bar **Setup…** for the wizard on demand). Headless / no-GUI
fallback still uses the provider + key prompts below. Screen Recording
onboarding stays **Mac-only**. ``provider: claude`` without a key asks for an
Anthropic key (or fails headless with a config/env message).
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path
from typing import Any

from . import config as cfgmod
from . import setup_detect
from . import tk_util

# Persist the app package version that last showed the NQA onboard wizard.
# Auto-show only when bridge_py.__version__ differs from this value (missing =
# new → show once). Same app version never auto-shows, even if setup is incomplete
# (menu bar + Setup… / sequential prompts instead). Legacy ``onboardWizardVersion``
# from PR #45 is deleted only — never invent a fake lastSeenAppVersion.
LAST_SEEN_APP_VERSION_KEY = "lastSeenAppVersion"
_LEGACY_ONBOARD_WIZARD_VERSION_KEY = "onboardWizardVersion"


def current_app_version() -> str:
    """Package version string used for the once-per-build wizard gate."""
    from . import __version__

    return str(__version__)


def migrate_legacy_onboard_wizard_version(cfg: dict[str, Any]) -> bool:
    """Drop PR #45 ``onboardWizardVersion`` without inventing ``lastSeenAppVersion``.

    Setting lastSeen to the *current* build previously skipped the version-bump
    wizard for users who only had the legacy key (e.g. first launch of 0.1.29).
    Preferred behavior: delete the legacy key only and leave lastSeen missing so
    this build still auto-shows once per the product rule. Mutates ``cfg``; does
    not save. Returns True when a migration write is needed.
    """
    if _LEGACY_ONBOARD_WIZARD_VERSION_KEY not in (cfg or {}):
        return False
    del cfg[_LEGACY_ONBOARD_WIZARD_VERSION_KEY]
    return True


def app_version_wizard_due(cfg: dict[str, Any] | None) -> bool:
    """True when ``lastSeenAppVersion`` is missing or differs from the running app.

    Call after :func:`migrate_legacy_onboard_wizard_version` so the legacy key
    alone cannot suppress the gate (it is deleted, not converted to lastSeen).
    """
    seen = str((cfg or {}).get(LAST_SEEN_APP_VERSION_KEY) or "")
    return seen != current_app_version()


def should_show_onboard_wizard(
    cfg: dict[str, Any] | None,
    *,
    use_wizard: bool,
) -> bool:
    """Pure gate: auto-show the NQA wizard only on an app version bump (GUI path).

    Incomplete setup on the *same* version does **not** open the wizard; use
    Setup… or the sequential first-run prompts instead.
    """
    if not use_wizard:
        return False
    return app_version_wizard_due(cfg)


def mark_onboard_wizard_seen(cfg: dict[str, Any]) -> dict[str, Any]:
    """Record that the version-bump wizard was shown/closed (mutates + returns ``cfg``)."""
    cfg[LAST_SEEN_APP_VERSION_KEY] = current_app_version()
    return cfg


def format_startup_path_log(
    *,
    app_version: str,
    executable: str,
    frozen: bool,
    applications: bool,
) -> str:
    """One bridge.log line: which binary is running (before the onboard gate)."""
    return (
        f"[startup] app_version={app_version} executable={executable} "
        f"frozen={'true' if frozen else 'false'} "
        f"applications={'true' if applications else 'false'}"
    )


def should_warn_not_under_applications(*, frozen: bool, applications: bool) -> bool:
    """Soft nudge: frozen Mac binary outside /Applications or ~/Applications."""
    return bool(frozen) and not bool(applications)


def _setup_incomplete(cfg: dict[str, Any]) -> bool:
    return (
        not cfg.get("addonDir")
        or not Path(str(cfg.get("addonDir") or "")).is_dir()
        or not cfgmod.has_provider_api_key(cfg)
    )


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
    store = cfgmod.secure_store_label()
    if store:
        where = (
            f"Your key is stored in {store} on this PC (local config.json is "
            "only a fallback if that fails)."
        )
        short = f"(Stored locally in {store} — not uploaded, not in the addon.)"
    else:
        where = (
            "Your key is stored ONLY in a local config.json on this computer "
            "(next to the bridge)."
        )
        short = "(Stored locally only in config.json — not uploaded, not in the addon.)"
    tk_util.show_info_dialog(
        "WoW Grok — API key",
        "WoW Grok needs an xAI API key to chat with Grok.\n\n"
        f"{where} It is never uploaded, never sent to the WoW "
        "addon, and never written into Lua.\n\n"
        "Get a key at https://console.x.ai/",
    )
    key = tk_util.ask_string_dialog(
        "WoW Grok — xAI API key",
        "Paste your xAI API key (starts with xai-…):\n"
        f"{short}",
        show="*",
    )
    if key is None:
        return None
    key = key.strip()
    return key or None


def prompt_claude_api_key(parent=None) -> str | None:
    """Ask for an Anthropic API key. Returns the key or None if cancelled.

    Reuses the same string dialog as the xAI prompt. Never logs the value.
    """
    _ = parent
    store = cfgmod.secure_store_label()
    if store:
        where = f"It is stored in {store} on this PC "
    else:
        where = "It is stored ONLY in local config.json as claudeApiKey "
    key = tk_util.ask_string_dialog(
        "WoW Grok — Anthropic API key",
        "You chose Claude (Anthropic).\n\n"
        f"Paste your Anthropic API key. {where}"
        "(not uploaded, not sent to the WoW addon, not written into Lua).\n\n"
        "Get a key at https://console.anthropic.com/ — or set ANTHROPIC_API_KEY and restart.",
        show="*",
    )
    if key is None:
        return None
    key = key.strip()
    return key or None


def prompt_provider(parent=None) -> str:
    """Ask xAI (default) vs Claude. Same dialog on Mac and Windows.

    Returns ``"xai"`` or ``"claude"``. Enter / Escape / close window → xAI.
    """
    _ = parent
    return tk_util.ask_provider_dialog()


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

    If capture.permissionPaused is set (persisted after exit 42), skip the CG
    probe/request entirely — do not clear that flag on probe=granted.
    """
    if sys.platform != "darwin":
        return
    if not _gui_available():
        _append_bridge_log("[screen-recording] skip: no GUI available")
        return

    cap = (cfg or {}).get("capture") or {}
    if cap.get("permissionPaused"):
        _append_bridge_log(
            "[screen-recording] skip probe/request: capture.permissionPaused "
            "(presence/Connect-only). Clear the flag in config.json after "
            "enabling Screen Recording, then Quit+reopen."
        )
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


def _apply_addon_dir(cfg: dict[str, Any], addon_dir: Path) -> dict[str, Any]:
    """Fill addonDir / inbox / SavedVariables / capture process from AddOns path."""
    cfg = cfgmod.derive_paths_from_addon_dir(cfg, str(addon_dir))
    client = addon_dir.parent.parent
    accounts = setup_detect.find_accounts(client)
    if accounts:
        cfg = cfgmod.derive_paths_from_addon_dir(cfg, str(addon_dir), accounts[0])
    cap = cfg.setdefault("capture", {})
    cap["processName"] = setup_detect.detect_process_name(client)
    return cfg


def _run_onboard_wizard(cfg: dict[str, Any]) -> dict[str, Any]:
    """Two-pane wizard (Mac + Windows). Mutates and returns ``cfg``.

    Always records ``lastSeenAppVersion`` afterwards (done / finish later /
    cancelled) so the same app build is not auto-shown again.
    """
    from . import onboard_wizard

    existing = setup_detect.find_existing_addons()

    def _pick() -> Path | None:
        return prompt_addons_dir(existing)

    result = onboard_wizard.run_onboard_wizard(
        cfg=cfg,
        initial_addon_dir=cfg.get("addonDir") or None,
        pick_addons_dir=_pick,
        secure_store_label=cfgmod.secure_store_label(),
        provider_key_present=cfgmod.has_provider_api_key(cfg),
    )
    onboard_wizard.apply_wizard_result(cfg, result)
    if result.addon_dir:
        cfg = _apply_addon_dir(cfg, Path(result.addon_dir))
    _append_bridge_log(
        f"[onboard-wizard] status={result.status} provider={result.provider!r} "
        f"connected={result.connected_label!r}"
    )
    mark_onboard_wizard_seen(cfg)
    try:
        cfgmod.save_config(cfg)
    except Exception as e:  # noqa: BLE001
        _append_bridge_log(f"[onboard-wizard] failed to save config: {e}")
    return cfg


def ensure_first_run_config(
    *,
    headless: bool = False,
    wow: str | None = None,
) -> dict[str, Any]:
    """Load or create config; prompt for provider + API key + AddOns if needed.

    After addonDir and the active provider's API key are set and config is saved,
    installs the main addon and reply slots into Interface/AddOns (GUI shows
    progress dialogs). On macOS / Windows GUI launches, the :mod:`onboard_wizard`
    (Download → Connect your AI → Say hi) auto-opens **only** when the running
    app ``__version__`` differs from ``lastSeenAppVersion`` in config.json
    (missing counts as new → show once). Closing it records the current version.
    Same app version never auto-shows the wizard — even when setup is incomplete;
    incomplete same-version GUI launches use the sequential provider/key/AddOns
    prompts instead. Menu bar **Setup…** still opens the wizard on demand.
    Headless / no-GUI fallback still asks xAI vs Claude (Enter = xAI default),
    then the matching key prompt. Claude requires ANTHROPIC_API_KEY or
    claudeApiKey. Screen Recording sheet remains macOS-only after a successful
    install.

    headless: skip UI (CLI --wow / env only); exit 2 if incomplete.
    """
    from . import onboard_wizard

    cfg = cfgmod.load_config()
    if cfg is None:
        cfg = cfgmod.load_example()

    # Always log which binary is running *before* the version-bump gate so a
    # wrong-path launch (e.g. ~/wowgrok-build-0.1.27) is diagnosable even when
    # the gate never fires.
    frozen = onboard_wizard.is_running_frozen()
    applications = onboard_wizard.is_running_from_applications()
    _append_bridge_log(
        format_startup_path_log(
            app_version=current_app_version(),
            executable=str(sys.executable),
            frozen=frozen,
            applications=applications,
        )
    )
    if should_warn_not_under_applications(frozen=frozen, applications=applications):
        _append_bridge_log(
            "[startup] warning: frozen app is not under /Applications or "
            "~/Applications; old ~/wowgrok-build-* copies can steal Dock/"
            "Spotlight launches — prefer /Applications/WoWGrok.app"
        )

    # PR #45 left onboardWizardVersion; drop it only — never invent lastSeen.
    legacy_key_present = _LEGACY_ONBOARD_WIZARD_VERSION_KEY in (cfg or {})
    if migrate_legacy_onboard_wizard_version(cfg):
        try:
            cfgmod.save_config(cfg)
        except Exception as e:  # noqa: BLE001
            _append_bridge_log(f"[onboard-wizard] failed to save legacy-key cleanup: {e}")

    use_wizard = onboard_wizard.should_use_wizard(
        headless=headless, gui_available=_gui_available()
    )
    show_wizard = should_show_onboard_wizard(cfg, use_wizard=use_wizard)
    _append_bridge_log(
        f"[onboard-wizard] gate "
        f"seen={cfg.get(LAST_SEEN_APP_VERSION_KEY)!r} "
        f"current={current_app_version()!r} "
        f"show={'true' if show_wizard else 'false'} "
        f"legacy_key={'true' if legacy_key_present else 'false'}"
    )

    # CLI --wow always wins for AddOns path (headless and GUI).
    if wow:
        norm = setup_detect.normalize_addons_selection(wow)
        if not norm:
            print(f'--wow "{wow}" is not a WoW AddOns/client folder', file=sys.stderr)
            sys.exit(2)
        cfg = _apply_addon_dir(cfg, Path(norm))
    elif (not cfg.get("addonDir") or not Path(str(cfg["addonDir"])).is_dir()) and not show_wizard:
        # Non-wizard path: pick AddOns now. Version-bump wizard collects AddOns
        # inside the Download step when it is about to show.
        existing = setup_detect.find_existing_addons()
        if headless:
            if len(existing) == 1:
                cfg = _apply_addon_dir(cfg, existing[0])
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
            cfg = _apply_addon_dir(cfg, picked)

    showed_wizard = False
    if show_wizard:
        # Once per app version bump only (not every needs_setup launch).
        # Gate decision already logged above (seen/current/show/legacy_key).
        cfg = _run_onboard_wizard(cfg)
        showed_wizard = True

    if not cfg.get("defaultCwd"):
        cfg["defaultCwd"] = os.getcwd()

    # Sequential provider/key prompts when the NQA wizard was not auto-shown
    # (same-version incomplete, headless-off GUI without version bump, etc.).
    if (
        not showed_wizard
        and not headless
        and _gui_available()
        and not cfgmod.has_provider_api_key(cfg)
    ):
        if os.environ.get("DISPLAY") is None and sys.platform.startswith("linux"):
            # No display: leave provider as-is (default xai); key checks below exit.
            pass
        else:
            cfg["provider"] = prompt_provider()

    # API key. Required key depends on provider; xAI stays the default path.
    # Skip prompts when the wizard already stored a key for the active provider.
    if cfgmod.resolve_provider(cfg) == "claude":
        if not cfgmod.has_claude_api_key(cfg):
            if headless or showed_wizard:
                print(
                    "Missing Anthropic API key. Set ANTHROPIC_API_KEY or claudeApiKey in config.json.",
                    file=sys.stderr,
                )
                sys.exit(2)
            if os.environ.get("DISPLAY") is None and sys.platform.startswith("linux"):
                print(
                    "Missing Anthropic API key and no display for first-run UI. "
                    "Set ANTHROPIC_API_KEY or write claudeApiKey into config.json.",
                    file=sys.stderr,
                )
                sys.exit(2)
            key = prompt_claude_api_key()
            if not key:
                print(
                    "Anthropic API key required. Set ANTHROPIC_API_KEY or claudeApiKey in config.json.",
                    file=sys.stderr,
                )
                sys.exit(2)
            cfg["claudeApiKey"] = key
    elif not cfgmod.has_api_key(cfg):
        if headless or showed_wizard:
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

    # AddonDir still required after wizard finish-later
    if not cfg.get("addonDir") or not Path(str(cfg["addonDir"])).is_dir():
        print("AddOns folder required.", file=sys.stderr)
        sys.exit(2)

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


SETUP_EXIT_APPLIED = 0
SETUP_EXIT_UNCHANGED = 3
SETUP_EXIT_UNAVAILABLE = 4


def _setup_fingerprint(cfg: dict[str, Any]) -> tuple:
    """What the running bridge cares about (keys compared by presence of value)."""
    return (
        cfgmod.resolve_provider(cfg),
        str(cfg.get("addonDir") or ""),
        cfgmod.resolve_api_key(cfg),
        cfgmod.resolve_claude_api_key(cfg),
    )


def run_setup_wizard_on_demand() -> int:
    """Menu bar **Setup…**: re-open the onboard wizard in its own process.

    Runs as ``WoWGrok --onboard-setup`` (frozen) / ``python -m bridge_py
    --onboard-setup`` so Tk never shares the AppKit run loop with rumps.
    Saves config (and reinstalls addon/slots when AddOns is valid).

    Exit codes: ``0`` = provider / key / AddOns changed (caller restarts the
    bridge to apply), ``3`` = nothing relevant changed, ``4`` = no GUI.
    """
    from . import onboard_wizard

    if not onboard_wizard.should_use_wizard(headless=False, gui_available=_gui_available()):
        print("Setup wizard needs a GUI (macOS / Windows).", file=sys.stderr)
        return SETUP_EXIT_UNAVAILABLE

    cfg = cfgmod.load_config()
    if cfg is None:
        cfg = cfgmod.load_example()
    before = _setup_fingerprint(cfg)
    _append_bridge_log("[onboard-wizard] on-demand Setup… from menu")
    cfg = _run_onboard_wizard(cfg)  # saves config + lastSeenAppVersion
    after = _setup_fingerprint(cfg)
    if after == before:
        return SETUP_EXIT_UNCHANGED

    addon_dir = cfg.get("addonDir")
    if addon_dir and Path(str(addon_dir)).is_dir():
        from .install_addon import InstallError, ensure_game_files

        try:
            ensure_game_files(cfg, gui=True)
        except InstallError as e:
            _append_bridge_log(f"[onboard-wizard] on-demand install failed: {e}")
    return SETUP_EXIT_APPLIED
