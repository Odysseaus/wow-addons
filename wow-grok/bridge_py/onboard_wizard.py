"""Mac first-run onboarding wizard (NQA-style two-pane layout, WoWGrok branding).

Pure helpers in this module are display-free so unit tests can cover step state
and provider mapping without a GUI. The tkinter UI is built only when
:func:`run_onboard_wizard` is called.
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
        "id": "claude",
        "label": "Claude",
        "hint": "API key · billed by Anthropic",
        "live": True,
        "config_provider": "claude",
        "key_field": "claudeApiKey",
        "key_url": "https://console.anthropic.com/",
        "key_prefix_hint": "Anthropic key",
    },
    {
        "id": "chatgpt",
        "label": "ChatGPT",
        "hint": "Coming soon",
        "live": False,
        "config_provider": None,
        "key_field": None,
        "key_url": None,
        "key_prefix_hint": None,
    },
    {
        "id": "grok",
        "label": "Grok",
        "hint": "xAI API · billed by xAI",
        "live": True,
        "config_provider": "xai",
        "key_field": "apiKey",
        "key_url": "https://console.x.ai/",
        "key_prefix_hint": "xai-…",
    },
    {
        "id": "gemini",
        "label": "Gemini",
        "hint": "Coming soon",
        "live": False,
        "config_provider": None,
        "key_field": None,
        "key_url": None,
        "key_prefix_hint": None,
    },
    {
        "id": "other",
        "label": "Other",
        "hint": "Coming soon",
        "live": False,
        "config_provider": None,
        "key_field": None,
        "key_url": None,
        "key_prefix_hint": None,
    },
)


def ui_label_to_provider(label: str) -> str | None:
    """Map a picker label (``\"Grok\"``, ``\"Claude\"``, …) to ``xai`` / ``claude``.

    Returns ``None`` for Coming soon / unknown labels.
    """
    needle = (label or "").strip().lower()
    for row in PROVIDER_ROWS:
        if row["label"].lower() == needle:
            return row["config_provider"]
    # aliases
    if needle in ("xai", "x.ai"):
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


def download_step_complete(
    *,
    addon_dir: str | Path | None = None,
    running_from_applications: bool | None = None,
) -> bool:
    """Download is done when AddOns is known, or the app is under /Applications."""
    if addon_dir and Path(addon_dir).is_dir():
        return True
    if running_from_applications is None:
        running_from_applications = is_running_from_applications()
    return bool(running_from_applications)


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
    if not getattr(sys, "frozen", False):
        return False
    return False


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
    return cfg


# --- Colors (dark Mac-like palette; not NQA skull branding) -----------------

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


def run_onboard_wizard(
    *,
    cfg: dict[str, Any] | None = None,
    initial_addon_dir: str | Path | None = None,
    pick_addons_dir: Callable[[], Path | None] | None = None,
    secure_store_label: str | None = None,
) -> WizardResult:
    """Show the two-pane Mac onboarding wizard. Blocks until closed.

    ``pick_addons_dir`` is injected so first_run can reuse
    :func:`first_run.prompt_addons_dir` without a circular import at module load.
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
    logo.create_text(24, 24, text="WG", fill=_ACCENT, font=("Helvetica", 14, "bold"))
    tk.Label(
        brand,
        text="WoW Grok",
        bg=_BG_SIDE,
        fg=_FG,
        font=("Helvetica", 13, "bold"),
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
        dot = tk.Label(row_f, text="◇", bg=_BG_SIDE, fg=_FG_MUTED, font=("Helvetica", 12))
        dot.pack(side="left", padx=(4, 8))
        lab = tk.Label(
            row_f,
            text=STEP_LABELS[step],
            bg=_BG_SIDE,
            fg=_FG_MUTED,
            font=("Helvetica", 11),
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
        font=("Helvetica", 10),
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
            font=("Helvetica", 22, "bold"),
            anchor="w",
        ).pack(anchor="w")
        tk.Label(
            content,
            text=(
                "Drag WoWGrok into Applications, then launch from there "
                "(not from the DMG). Confirm your WoW Interface/AddOns folder "
                "so the app can install the addon and reply slots."
            ),
            bg=_BG,
            fg=_FG_MUTED,
            font=("Helvetica", 11),
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
            font=("Helvetica", 10),
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
            font=("Helvetica", 11, "bold"),
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
            font=("Helvetica", 22, "bold"),
            anchor="w",
        ).pack(side="left")
        tk.Label(
            title_row,
            text="ⓘ",
            bg=_BG,
            fg=_FG_MUTED,
            font=("Helvetica", 12),
        ).pack(side="right")

        tk.Label(
            content,
            text=(
                "Choose a provider and paste an API key. "
                "ChatGPT, Gemini, and Other are listed for later — "
                "Claude and Grok (xAI) work now."
            ),
            bg=_BG,
            fg=_FG_MUTED,
            font=("Helvetica", 11),
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
                font=("Helvetica", 12),
                anchor="w",
            )
            name.pack(side="left", padx=(14, 8), pady=10)
            hint = tk.Label(
                rf,
                text=prow["hint"],
                bg=_BG_CARD,
                fg=_FG_MUTED,
                font=("Helvetica", 10),
                anchor="e",
            )
            hint.pack(side="left", fill="x", expand=True)
            mark = tk.Label(rf, text="", bg=_BG_CARD, fg=_ACCENT, font=("Helvetica", 12), width=2)
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
        status_mark = tk.Label(status_row, text="", bg=_BG, fg=_OK, font=("Helvetica", 12))
        status_mark.pack(side="left", padx=(0, 6))
        status_lbl = tk.Label(
            status_row,
            textvariable=status_var,
            bg=_BG,
            fg=_OK,
            font=("Helvetica", 11),
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
                status_var.set("That provider is coming soon — pick Claude or Grok.")
                status_mark.configure(text="", fg=_FG_MUTED)
                status_lbl.configure(fg=_FG_MUTED)
                return
            # Already connected to this row with a key → advance
            if state.connected_row_id == row["id"] and state.api_key:
                state.completed_steps.add(STEP_CONNECT)
                state.active_step = STEP_SAY_HI
                _refresh_sidebar()
                _show_step()
                return
            _clear_key_area()
            store = secure_store_label
            where = (
                f"Stored in {store} on this Mac."
                if store
                else "Stored only in local config.json on this Mac."
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
                font=("Helvetica", 10),
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
                font=("Helvetica", 10, "bold"),
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
            font=("Helvetica", 12, "bold"),
        ).pack(side="left")

    def _show_say_hi() -> None:
        _clear_content()
        tk.Label(
            content,
            text="Say hi in game",
            bg=_BG,
            fg=_FG,
            font=("Helvetica", 22, "bold"),
            anchor="w",
        ).pack(anchor="w")
        body = (
            "You're almost questing.\n\n"
            "1. Set WoW to Windowed or Windowed (Fullscreen) / borderless.\n"
            "2. Fully quit and relaunch WoW if it was already open.\n"
            "3. At character select, enable WoW Grok (and leave the slot addons on).\n"
            "4. Log in and type /wow-grok or /grok in chat.\n\n"
            "Leave WoWGrok running in the menu bar — it's the live bridge, "
            "not a one-time installer."
        )
        if state.connected_label:
            body = f"{state.connected_label} is connected.\n\n" + body
        tk.Label(
            content,
            text=body,
            bg=_BG,
            fg=_FG_MUTED,
            font=("Helvetica", 11),
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
            font=("Helvetica", 12, "bold"),
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
    """Mac GUI first-run uses the wizard; headless / non-Mac keep the old path."""
    if headless or not gui_available:
        return False
    return sys.platform == "darwin"
