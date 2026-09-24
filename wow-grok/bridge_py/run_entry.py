"""PyInstaller entrypoint — imports package so relative imports in __main__ work."""
from __future__ import annotations

import sys
import traceback
from pathlib import Path


def _crash_log_path() -> Path:
    try:
        from bridge_py import config as cfgmod

        return cfgmod.runtime_dir() / "crash.log"
    except Exception:
        if sys.platform == "darwin":
            return Path.home() / "Library" / "Application Support" / "WoWGrok" / "crash.log"
        return Path.home() / "WoWGrok-crash.log"


def _install_excepthook() -> None:
    def _hook(exc_type, exc, tb) -> None:
        text = "".join(traceback.format_exception(exc_type, exc, tb))
        try:
            path = _crash_log_path()
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        except Exception:
            path = None
        try:
            import tkinter as tk
            from tkinter import messagebox

            from bridge_py import tk_util

            root = tk.Tk()
            tk_util.prepare_dialog_root(root)
            msg = "WoW Grok hit an unexpected error and must close.\n\n" + text[-1500:]
            if path is not None:
                msg += f"\n\nDetails saved to:\n{path}"
            messagebox.showerror("WoW Grok — error", msg, parent=root)
            root.destroy()
        except Exception:
            sys.stderr.write(text)
        sys.__excepthook__(exc_type, exc, tb)

    sys.excepthook = _hook


_install_excepthook()

# Frozen Mac apps lack a system CA store; configure before any HTTPS.
try:
    from bridge_py import ssl_certs as _ssl_certs

    _ssl_certs.configure()
except Exception:
    pass

from bridge_py.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
