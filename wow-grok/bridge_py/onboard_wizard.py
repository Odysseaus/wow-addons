"""First-run onboarding wizard (NQA-style two-pane layout, WoWGrok branding).

Shared by Mac and Windows. Pure helpers are display-free so unit tests can
cover step state and provider mapping without a GUI. The tkinter UI is built
only when :func:`run_onboard_wizard` is called. Platform-specific copy
(Applications vs exe, menu bar vs tray) is parameterized — Screen Recording
stays Mac-only in :mod:`first_run`.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

# --- Pure logic (no tkinter) -------------------------------------------------

STEP_DOWNLOAD = "download"
STEP_CONNECT = "connect"
STEP_SAY_HI = "say_hi"

STEPS: tuple[str, ...] = (STEP_DOWNLOAD, STEP_CONNECT, STEP_SAY_HI)

STEP_LABELS = {
    STEP_DOWNLOAD: "Download",
    STEP_CONNECT: "Connect your AI",
    STEP_SAY_HI: "Say hi in game",
}

# UI label → config provider id. Only live providers return a non-None id.
PROVIDER_ROWS: tuple[dict[str, Any], ...] = (
    {
        "id": "grok",
        "label": "xAI (Grok)",
        "hint": "xAI API · billed by xAI",
        "live": True,
        "config_provider": "xai",
        "key_field": "apiKey",
        "key_url": "https://console.x.ai/",
        "key_prefix_hint": "xai-…",
    },
    {
        "id": "claude",
        "label": "Claude",
        "hint": "API key · billed by Anthropic",
        "live": True,
        "config_provider": "claude",
        "key_field": "claudeApiKey",
        "key_url": "https://console.anthropic.com/",
        "key_prefix_hint": "Anthropic key",
    },
)


def ui_label_to_provider(label: str) -> str | None:
    """Map a picker label (``\"Grok\"``, ``\"Claude\"``, …) to ``xai`` / ``claude``.

    Returns ``None`` for unknown labels (only xAI (Grok) and Claude exist).
    """
    needle = (label or "").strip().lower()
    for row in PROVIDER_ROWS:
        if row["label"].lower() == needle:
            return row["config_provider"]
    # aliases
    if needle in ("xai", "x.ai", "grok"):
        return "xai"
    if needle in ("anthropic",):
        return "claude"
    return None


def provider_row_by_id(row_id: str) -> dict[str, Any] | None:
    for row in PROVIDER_ROWS:
        if row["id"] == row_id:
            return row
    return None


def provider_row_for_config(provider: str) -> dict[str, Any] | None:
    """Return the picker row whose ``config_provider`` matches ``provider``."""
    want = (provider or "").strip().lower()
    for row in PROVIDER_ROWS:
        if row["config_provider"] == want:
            return row
    return None


def live_provider_ids() -> tuple[str, ...]:
    return tuple(r["id"] for r in PROVIDER_ROWS if r["live"])


def is_running_frozen() -> bool:
    """True when running as a frozen app (PyInstaller exe / .app)."""
    return bool(getattr(sys, "frozen", False))


def is_running_from_applications() -> bool:
    """True when the frozen Mac app lives under ``/Applications`` (or ~/Applications)."""
    if sys.platform != "darwin":
        return False
    try:
        exe = Path(sys.executable).resolve()
    except Exception:
        return False
    parts = exe.parts
    # …/Applications/WoWGrok.app/Contents/MacOS/WoWGrok
    if "Applications" in parts:
        return True
    # Dev / non-frozen: treat as not Applications
    if not is_running_frozen():
        return False
    return False


def download_step_complete(
    *,
    addon_dir: str | Path | None = None,
    running_from_applications: bool | None = None,
    running_frozen: bool | None = None,
) -> bool:
    """Download is done when AddOns is known, or the platform install signal is met.

    Mac: AddOns dir **or** running from ``/Applications`` (unchanged).
    Windows: AddOns dir **or** the frozen ``WoWGrok.exe`` is already running
    (player downloaded and launched the app — no Applications folder).
    """
    if addon_dir and Path(addon_dir).is_dir():
        return True
    if sys.platform == "win32":
        if running_frozen is None:
            running_frozen = is_running_frozen()
        return bool(running_frozen)
    # darwin (and other): Applications check; non-Mac non-Win → False unless dir set
    if running_from_applications is None:
        running_from_applications = is_running_from_applications()
    return bool(running_from_applications)


@dataclass
class WizardState:
    """In-memory wizard progress (display-free)."""

    active_step: str = STEP_DOWNLOAD
    completed_steps: set[str] = field(default_factory=set)
    selected_row_id: str = "grok"  # default highlight = Grok / xAI
    connected_row_id: str | None = None
    connected_label: str | None = None
    provider: str | None = None  # config: xai | claude
    api_key: str | None = None
    key_field: str | None = None
    addon_dir: str | None = None
    finished_later: bool = False
    completed: bool = False
    # Row whose key is already stored (config / keychain / env) — set when the
    # wizard re-opens on a configured install (upgrade gate or menu Setup…).
    existing_key_row_id: str | None = None

    def mark_download_done(self) -> None:
        self.completed_steps.add(STEP_DOWNLOAD)
        if self.active_step == STEP_DOWNLOAD:
            self.active_step = STEP_CONNECT

    def mark_connected(self, row: dict[str, Any], api_key: str) -> None:
        self.connected_row_id = row["id"]
        self.connected_label = row["label"]
        self.provider = row["config_provider"]
        self.key_field = row["key_field"]
        self.api_key = api_key
        self.completed_steps.add(STEP_CONNECT)
        self.active_step = STEP_SAY_HI

    def mark_existing_key(self, row: dict[str, Any]) -> None:
        """Show ``row`` as connected using the key already on file (no new key).

        Connect counts as done, but the active step is left alone so the user
        can still paste a new key or switch provider.
        """
        self.connected_row_id = row["id"]
        self.connected_label = row["label"]
        self.provider = row["config_provider"]
        self.key_field = row["key_field"]
        self.existing_key_row_id = row["id"]
        self.completed_steps.add(STEP_CONNECT)

    def can_continue_with(self, row_id: str) -> bool:
        """True when Continue on Connect may advance without pasting a key."""
        if self.connected_row_id != row_id:
            return False
        return bool(self.api_key) or self.existing_key_row_id == row_id

    def mark_say_hi_done(self) -> None:
        self.completed_steps.add(STEP_SAY_HI)
        self.completed = True

    def step_status(self, step: str) -> str:
        """``done`` | ``active`` | ``pending``."""
        if step in self.completed_steps:
            return "done"
        if step == self.active_step:
            return "active"
        return "pending"


@dataclass
class WizardResult:
    """Outcome handed back to :func:`first_run.ensure_first_run_config`."""

    status: str  # "done" | "finish_later" | "cancelled"
    provider: str | None = None
    api_key: str | None = None
    key_field: str | None = None
    addon_dir: str | None = None
    connected_label: str | None = None


def apply_wizard_result(cfg: dict[str, Any], result: WizardResult) -> dict[str, Any]:
    """Merge a successful / partial wizard result into ``cfg`` (returns same dict)."""
    if result.addon_dir:
        cfg["addonDir"] = result.addon_dir
    if result.provider:
        cfg["provider"] = result.provider
    if result.api_key and result.key_field:
        cfg[result.key_field] = result.api_key
        # New key pasted → drop any invalid/expired flag for that provider.
        from . import key_health

        key_health.clear_key_invalid(cfg, result.provider or cfg.get("provider") or "xai")
    return cfg


# --- Colors (dark palette; not NQA skull branding) --------------------------

_BG = "#1a1a1c"
_BG_SIDE = "#141416"
_BG_CARD = "#242428"
_BG_ROW = "#2a2a2e"
_BG_ROW_SEL = "#333338"
_FG = "#f2f2f2"
_FG_MUTED = "#9a9aa0"
_ACCENT = "#e8a317"  # warm gold / orange (Continue)
_ACCENT_FG = "#1a1a1c"
_OK = "#3dcc7a"
_BORDER = "#3a3a40"


def _ui_font(size: int, weight: str = "normal") -> tuple:
    """Prefer Segoe UI on Windows; Helvetica elsewhere (tk maps fine on Mac)."""
    family = "Segoe UI" if sys.platform == "win32" else "Helvetica"
    if weight == "bold":
        return (family, size, "bold")
    return (family, size)


def _platform_machine_phrase() -> str:
    if sys.platform == "win32":
        return "this PC"
    if sys.platform == "darwin":
        return "this Mac"
    return "this computer"


def _download_blurb() -> str:
    if sys.platform == "win32":
        return (
            "Download WoWGrok.exe and run it (if SmartScreen appears: "
            "More info → Run anyway). Confirm your WoW Interface\\AddOns "
            "folder so the app can install the addon and reply slots."
        )
    return (
        "Drag WoWGrok into Applications, then launch from there "
        "(not from the DMG). Confirm your WoW Interface/AddOns folder "
        "so the app can install the addon and reply slots."
    )


def _say_hi_body(*, connected_label: str | None) -> str:
    if sys.platform == "win32":
        body = (
            "You're almost questing.\n\n"
            "1. Set WoW to Windowed or Windowed (Fullscreen).\n"
            "2. Fully quit and relaunch WoW if it was already open.\n"
            "3. At character select, enable WoW Grok (and leave the slot addons on).\n"
            "4. Log in and type /wow-grok or /grok in chat.\n\n"
            "Leave WoWGrok running in the system tray (notification area by the "
            "clock — use the ^ arrow if needed). Right-click it; the menu should "
            "say Running. It's the live bridge, not a one-time installer.\n\n"
            "When you send a message, a brief pixel bar appears at the top-left "
            "of WoW so the app can read your question."
        )
    else:
        body = (
            "You're almost questing.\n\n"
            "1. Set WoW to Windowed or Windowed (Fullscreen) / borderless.\n"
            "2. Fully quit and relaunch WoW if it was already open.\n"
            "3. At character select, enable WoW Grok (and leave the slot addons on).\n"
            "4. Log in and type /wow-grok or /grok in chat.\n\n"
            "Leave WoWGrok running in the menu bar — it's the live bridge, "
            "not a one-time installer."
        )
    if connected_label:
        body = f"{connected_label} is connected.\n\n" + body
    return body


def run_onboard_wizard(
    *,
    cfg: dict[str, Any] | None = None,
    initial_addon_dir: str | Path | None = None,
    pick_addons_dir: Callable[[], Path | None] | None = None,
    secure_store_label: str | None = None,
    provider_key_present: bool = False,
) -> WizardResult:
    """Show the two-pane onboarding wizard (Mac + Windows). Blocks until closed.

    ``pick_addons_dir`` is injected so first_run can reuse
    :func:`first_run.prompt_addons_dir` without a circular import at module load.

    ``provider_key_present``: the configured provider already has a key, so
    Connect starts as "<provider> is connected" (paste a new key to replace it).
    """
    import tkinter as tk

    from . import tk_util

    cfg = dict(cfg or {})
    state = WizardState()
    if initial_addon_dir and Path(initial_addon_dir).is_dir():
        state.addon_dir = str(Path(initial_addon_dir))
    elif cfg.get("addonDir") and Path(str(cfg["addonDir"])).is_dir():
        state.addon_dir = str(cfg["addonDir"])

    # Prefer an already-configured live provider as the selection.
    existing = (cfg.get("provider") or "xai").strip().lower()
    row = provider_row_for_config(existing) or provider_row_by_id("grok")
    if row:
        state.selected_row_id = row["id"]
        if provider_key_present and row.get("live"):
            state.mark_existing_key(row)

    if download_step_complete(addon_dir=state.addon_dir):
        state.mark_download_done()
    else:
        state.active_step = STEP_DOWNLOAD

    result_box: dict[str, WizardResult] = {
        "v": WizardResult(status="cancelled"),
    }

    root = tk.Tk()
    root.title("WoW Grok — Setup")
    root.configure(bg=_BG)
    try:
        root.attributes("-topmost", True)
    except Exception:
        pass
    root.minsize(720, 480)

    # Layout: sidebar | main
    shell = tk.Frame(root, bg=_BG)
    shell.pack(fill="both", expand=True)

    sidebar = tk.Frame(shell, bg=_BG_SIDE, width=220)
    sidebar.pack(side="left", fill="y")
    sidebar.pack_propagate(False)

    main = tk.Frame(shell, bg=_BG)
    main.pack(side="left", fill="both", expand=True)

    # Sidebar brand
    brand = tk.Frame(sidebar, bg=_BG_SIDE)
    brand.pack(fill="x", padx=20, pady=(28, 18))
    logo = tk.Canvas(brand, width=48, height=48, bg=_BG_SIDE, highlightthickness=0)
    logo.pack(anchor="w")
    # Simple WoWGrok mark: rounded square + "WG" — no skull
    logo.create_oval(2, 2, 46, 46, fill="#2c2c32", outline=_ACCENT, width=2)
    logo.create_text(24, 24, text="WG", fill=_ACCENT, font=_ui_font(14, "bold"))
    tk.Label(
        brand,
        text="WoW Grok",
        bg=_BG_SIDE,
        fg=_FG,
        font=_ui_font(13, "bold"),
        anchor="w",
    ).pack(anchor="w", pady=(10, 0))

    step_frames: dict[str, dict[str, Any]] = {}
    steps_box = tk.Frame(sidebar, bg=_BG_SIDE)
    steps_box.pack(fill="x", padx=16, pady=(8, 0))

    def _refresh_sidebar() -> None:
        for step in STEPS:
            widgets = step_frames[step]
            status = state.step_status(step)
            if status == "done":
                widgets["dot"].configure(text="✓", fg=_ACCENT)
                widgets["label"].configure(fg=_FG)
            elif status == "active":
                widgets["dot"].configure(text="◆", fg=_ACCENT)
                widgets["label"].configure(fg=_FG)
            else:
                widgets["dot"].configure(text="◇", fg=_FG_MUTED)
                widgets["label"].configure(fg=_FG_MUTED)

    for step in STEPS:
        row_f = tk.Frame(steps_box, bg=_BG_SIDE)
        row_f.pack(fill="x", pady=6)
        dot = tk.Label(row_f, text="◇", bg=_BG_SIDE, fg=_FG_MUTED, font=_ui_font(12))
        dot.pack(side="left", padx=(4, 8))
        lab = tk.Label(
            row_f,
            text=STEP_LABELS[step],
            bg=_BG_SIDE,
            fg=_FG_MUTED,
            font=_ui_font(11),
            anchor="w",
        )
        lab.pack(side="left", fill="x", expand=True)

        def _goto(s: str = step) -> None:
            # Allow revisiting completed / current steps only
            idx = STEPS.index(s)
            active_idx = STEPS.index(state.active_step)
            if s in state.completed_steps or idx <= active_idx:
                state.active_step = s
                _show_step()
                _refresh_sidebar()

        lab.bind("<Button-1>", lambda _e, s=step: _goto(s))
        dot.bind("<Button-1>", lambda _e, s=step: _goto(s))
        step_frames[step] = {"dot": dot, "label": lab, "frame": row_f}

    footer = tk.Frame(sidebar, bg=_BG_SIDE)
    footer.pack(side="bottom", fill="x", padx=16, pady=20)

    def _finish_later() -> None:
        state.finished_later = True
        result_box["v"] = WizardResult(
            status="finish_later",
            provider=state.provider,
            api_key=state.api_key,
            key_field=state.key_field,
            addon_dir=state.addon_dir,
            connected_label=state.connected_label,
        )
        try:
            root.destroy()
        except Exception:
            pass

    fl = tk.Label(
        footer,
        text="Finish later",
        bg=_BG_SIDE,
        fg=_FG_MUTED,
        font=_ui_font(10),
        cursor="hand2",
    )
    fl.pack(anchor="e")
    fl.bind("<Button-1>", lambda _e: _finish_later())

    # Main content host
    content = tk.Frame(main, bg=_BG)
    content.pack(fill="both", expand=True, padx=36, pady=28)

    # Shared mutable UI refs for connect pane
    ui: dict[str, Any] = {}

    def _clear_content() -> None:
        for child in content.winfo_children():
            child.destroy()

    def _show_download() -> None:
        _clear_content()
        tk.Label(
            content,
            text="Download",
            bg=_BG,
            fg=_FG,
            font=_ui_font(22, "bold"),
            anchor="w",
        ).pack(anchor="w")
        tk.Label(
            content,
            text=_download_blurb(),
            bg=_BG,
            fg=_FG_MUTED,
            font=_ui_font(11),
            wraplength=440,
            justify="left",
            anchor="w",
        ).pack(anchor="w", pady=(10, 18))

        path_var = tk.StringVar(value=state.addon_dir or "(not set yet)")
        path_lbl = tk.Label(
            content,
            textvariable=path_var,
            bg=_BG_CARD,
            fg=_FG,
            font=_ui_font(10),
            wraplength=420,
            justify="left",
            anchor="w",
            padx=12,
            pady=10,
        )
        path_lbl.pack(fill="x")

        btns = tk.Frame(content, bg=_BG)
        btns.pack(fill="x", pady=(16, 0))

        def _pick() -> None:
            picked = None
            if pick_addons_dir is not None:
                picked = pick_addons_dir()
            if picked:
                state.addon_dir = str(picked)
                path_var.set(state.addon_dir)
                state.mark_download_done()
                _refresh_sidebar()
                _show_step()

        def _continue_download() -> None:
            if state.addon_dir and Path(state.addon_dir).is_dir():
                state.mark_download_done()
                _refresh_sidebar()
                _show_step()
                return
            _pick()

        tk.Button(
            btns,
            text="Choose AddOns folder…",
            command=_pick,
            bg=_BG_ROW,
            fg=_FG,
            activebackground=_BG_ROW_SEL,
            activeforeground=_FG,
            relief="flat",
            padx=14,
            pady=8,
        ).pack(side="left")
        cont = tk.Button(
            btns,
            text="Continue",
            command=_continue_download,
            bg=_ACCENT,
            fg=_ACCENT_FG,
            activebackground="#f0b430",
            activeforeground=_ACCENT_FG,
            relief="flat",
            padx=22,
            pady=8,
            font=_ui_font(11, "bold"),
        )
        cont.pack(side="right")

    def _show_connect() -> None:
        _clear_content()
        title_row = tk.Frame(content, bg=_BG)
        title_row.pack(fill="x")
        tk.Label(
            title_row,
            text="Connect your AI",
            bg=_BG,
            fg=_FG,
            font=_ui_font(22, "bold"),
            anchor="w",
        ).pack(side="left")
        tk.Label(
            title_row,
            text="ⓘ",
            bg=_BG,
            fg=_FG_MUTED,
            font=_ui_font(12),
        ).pack(side="right")

        tk.Label(
            content,
            text=(
                "Choose xAI (Grok) or Claude and paste an API key."
            ),
            bg=_BG,
            fg=_FG_MUTED,
            font=_ui_font(11),
            wraplength=440,
            justify="left",
            anchor="w",
        ).pack(anchor="w", pady=(8, 14))

        card = tk.Frame(content, bg=_BG_CARD, highlightbackground=_BORDER, highlightthickness=1)
        card.pack(fill="x")

        row_widgets: dict[str, dict[str, Any]] = {}

        def _select(row_id: str) -> None:
            row = provider_row_by_id(row_id)
            if row is None:
                return
            if not row["live"]:
                return
            state.selected_row_id = row_id
            for rid, w in row_widgets.items():
                r = provider_row_by_id(rid)
                live = bool(r and r["live"])
                selected = rid == state.selected_row_id
                bg = _BG_ROW_SEL if selected else _BG_CARD
                fg = _FG if live else _FG_MUTED
                w["frame"].configure(bg=bg)
                w["name"].configure(bg=bg, fg=fg)
                w["hint"].configure(bg=bg, fg=_FG_MUTED)
                mark = ""
                if state.connected_row_id == rid:
                    mark = "✓"
                elif selected and live:
                    mark = "●"
                w["mark"].configure(bg=bg, fg=_ACCENT if mark else _FG_MUTED, text=mark)

        for prow in PROVIDER_ROWS:
            rf = tk.Frame(card, bg=_BG_CARD)
            rf.pack(fill="x", padx=2, pady=1)
            name = tk.Label(
                rf,
                text=prow["label"],
                bg=_BG_CARD,
                fg=_FG if prow["live"] else _FG_MUTED,
                font=_ui_font(12),
                anchor="w",
            )
            name.pack(side="left", padx=(14, 8), pady=10)
            hint = tk.Label(
                rf,
                text=prow["hint"],
                bg=_BG_CARD,
                fg=_FG_MUTED,
                font=_ui_font(10),
                anchor="e",
            )
            hint.pack(side="left", fill="x", expand=True)
            mark = tk.Label(rf, text="", bg=_BG_CARD, fg=_ACCENT, font=_ui_font(12), width=2)
            mark.pack(side="right", padx=(4, 10))

            row_widgets[prow["id"]] = {
                "frame": rf,
                "name": name,
                "hint": hint,
                "mark": mark,
            }
            if prow["live"]:
                for w in (rf, name, hint, mark):
                    w.bind("<Button-1>", lambda _e, rid=prow["id"]: _select(rid))
                    try:
                        w.configure(cursor="hand2")
                    except Exception:
                        pass

        ui["row_widgets"] = row_widgets
        _select(state.selected_row_id)

        # Key entry area (hidden until Continue on a live provider needing a key)
        key_area = tk.Frame(content, bg=_BG)
        key_area.pack(fill="x", pady=(14, 0))
        ui["key_area"] = key_area

        status_var = tk.StringVar(value="")
        status_row = tk.Frame(content, bg=_BG)
        status_row.pack(fill="x", pady=(12, 0))
        status_mark = tk.Label(status_row, text="", bg=_BG, fg=_OK, font=_ui_font(12))
        status_mark.pack(side="left", padx=(0, 6))
        status_lbl = tk.Label(
            status_row,
            textvariable=status_var,
            bg=_BG,
            fg=_OK,
            font=_ui_font(11),
            anchor="w",
        )
        status_lbl.pack(side="left")
        ui["status_var"] = status_var
        ui["status_mark"] = status_mark

        if state.connected_label:
            status_var.set(f"{state.connected_label} is connected.")
            status_mark.configure(text="✓")

        btn_row = tk.Frame(content, bg=_BG)
        btn_row.pack(fill="x", pady=(18, 0))

        def _clear_key_area() -> None:
            for child in key_area.winfo_children():
                child.destroy()

        def _save_key(row: dict[str, Any], entry: Any) -> None:
            raw = (entry.get() or "").strip()
            if not raw:
                status_var.set("Paste an API key to continue.")
                status_mark.configure(text="", fg=_FG_MUTED)
                status_lbl.configure(fg=_FG_MUTED)
                return
            state.mark_connected(row, raw)
            status_var.set(f"{row['label']} is connected.")
            status_mark.configure(text="✓", fg=_OK)
            status_lbl.configure(fg=_OK)
            _clear_key_area()
            _select(row["id"])
            _refresh_sidebar()
            # Brief beat then advance
            try:
                root.after(450, _show_step)
            except Exception:
                _show_step()

        def _on_continue() -> None:
            row = provider_row_by_id(state.selected_row_id)
            if row is None or not row["live"]:
                status_var.set("Pick xAI (Grok) or Claude.")
                status_mark.configure(text="", fg=_FG_MUTED)
                status_lbl.configure(fg=_FG_MUTED)
                return
            # Already connected to this row (new or existing key) → advance
            if state.can_continue_with(row["id"]):
                state.completed_steps.add(STEP_CONNECT)
                state.active_step = STEP_SAY_HI
                _refresh_sidebar()
                _show_step()
                return
            _clear_key_area()
            store = secure_store_label
            machine = _platform_machine_phrase()
            where = (
                f"Stored in {store} on {machine}."
                if store
                else f"Stored only in local config.json on {machine}."
            )
            tk.Label(
                key_area,
                text=(
                    f"Paste your {row['label']} API key "
                    f"({row['key_prefix_hint']}). {where}\n"
                    f"Get a key at {row['key_url']}"
                ),
                bg=_BG,
                fg=_FG_MUTED,
                font=_ui_font(10),
                wraplength=440,
                justify="left",
                anchor="w",
            ).pack(anchor="w", pady=(0, 8))
            entry = tk.Entry(key_area, show="*", width=48, bg=_BG_ROW, fg=_FG, insertbackground=_FG)
            entry.pack(fill="x", ipady=6)
            try:
                entry.focus_set()
            except Exception:
                pass
            save_row = tk.Frame(key_area, bg=_BG)
            save_row.pack(fill="x", pady=(10, 0))
            tk.Button(
                save_row,
                text=f"Save {row['label']} key",
                command=lambda: _save_key(row, entry),
                bg=_ACCENT,
                fg=_ACCENT_FG,
                relief="flat",
                padx=16,
                pady=6,
                font=_ui_font(10, "bold"),
            ).pack(side="right")
            try:
                entry.bind("<Return>", lambda _e: _save_key(row, entry))
            except Exception:
                pass

        tk.Button(
            btn_row,
            text="Continue",
            command=_on_continue,
            bg=_ACCENT,
            fg=_ACCENT_FG,
            activebackground="#f0b430",
            activeforeground=_ACCENT_FG,
            relief="flat",
            padx=28,
            pady=10,
            font=_ui_font(12, "bold"),
        ).pack(side="left")

    def _show_say_hi() -> None:
        _clear_content()
        tk.Label(
            content,
            text="Say hi in game",
            bg=_BG,
            fg=_FG,
            font=_ui_font(22, "bold"),
            anchor="w",
        ).pack(anchor="w")
        body = _say_hi_body(connected_label=state.connected_label)
        tk.Label(
            content,
            text=body,
            bg=_BG,
            fg=_FG_MUTED,
            font=_ui_font(11),
            wraplength=460,
            justify="left",
            anchor="w",
        ).pack(anchor="w", pady=(12, 20))

        def _done() -> None:
            state.mark_say_hi_done()
            result_box["v"] = WizardResult(
                status="done",
                provider=state.provider,
                api_key=state.api_key,
                key_field=state.key_field,
                addon_dir=state.addon_dir,
                connected_label=state.connected_label,
            )
            try:
                root.destroy()
            except Exception:
                pass

        tk.Button(
            content,
            text="Done — start questing",
            command=_done,
            bg=_ACCENT,
            fg=_ACCENT_FG,
            activebackground="#f0b430",
            activeforeground=_ACCENT_FG,
            relief="flat",
            padx=22,
            pady=10,
            font=_ui_font(12, "bold"),
        ).pack(anchor="w")

    def _show_step() -> None:
        if state.active_step == STEP_DOWNLOAD:
            _show_download()
        elif state.active_step == STEP_CONNECT:
            _show_connect()
        else:
            _show_say_hi()

    def _on_close() -> None:
        # Window close ≈ finish later (keep any partial key/provider)
        if state.completed:
            return
        _finish_later()

    root.protocol("WM_DELETE_WINDOW", _on_close)
    _refresh_sidebar()
    _show_step()

    root.update_idletasks()
    tw, th = 780, 520
    try:
        tk_util.center_on_work_area(root, width=tw, height=th)
    except Exception:
        try:
            root.geometry(f"{tw}x{th}")
        except Exception:
            pass
    try:
        root.lift()
        root.focus_force()
    except Exception:
        pass
    root.mainloop()
    return result_box["v"]


def should_use_wizard(*, headless: bool, gui_available: bool) -> bool:
    """Mac and Windows GUI first-run use the wizard; headless keeps the old path."""
    if headless or not gui_available:
        return False
    return sys.platform in ("darwin", "win32")
