"""Local config paths and load/save. Never logs apiKey or claudeApiKey.

Windows: API keys live in Windows Credential Manager (:mod:`secret_store`).
``save_config`` moves any non-empty ``apiKey`` / ``claudeApiKey`` into the
store, verifies the read-back, and only then blanks it in ``config.json``.
If the store is unavailable or the write fails, the key stays in
``config.json`` (pre-0.1.28 behaviour). Existing installs migrate on the next
launch. macOS / Linux are unchanged (``config.json``).
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

PACKAGE_DIR = Path(__file__).resolve().parent
EXAMPLE_NAME = "config.example.json"
CONFIG_NAME = "config.json"
STATE_NAME = "state.json"
TRANSCRIPTS_NAME = "transcripts.json"
LOG_NAME = "bridge.log"

# Fields that go to the OS secret store on Windows (never to logs).
SECRET_FIELDS = ("apiKey", "claudeApiKey")


def runtime_dir() -> Path:
    """Directory for config/state.

    - Dev: package dir (``bridge_py/``)
    - Frozen Windows one-file: next to the ``.exe``
    - Frozen macOS ``.app``: ``~/Library/Application Support/WoWGrok``
      (``Contents/MacOS`` is not writable / wrong place for user data)
    """
    if getattr(sys, "frozen", False):
        exe = Path(sys.executable).resolve()
        # …/WoWGrok.app/Contents/MacOS/WoWGrok
        if sys.platform == "darwin" and exe.parent.name == "MacOS":
            support = Path.home() / "Library" / "Application Support" / "WoWGrok"
            support.mkdir(parents=True, exist_ok=True)
            return support
        return exe.parent
    return PACKAGE_DIR


def config_path() -> Path:
    return runtime_dir() / CONFIG_NAME


def example_path() -> Path:
    return PACKAGE_DIR / EXAMPLE_NAME


def state_path() -> Path:
    return runtime_dir() / STATE_NAME


def transcripts_path() -> Path:
    return runtime_dir() / TRANSCRIPTS_NAME


def log_path() -> Path:
    return runtime_dir() / LOG_NAME


def load_example() -> dict[str, Any]:
    p = example_path()
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return default_config()


def default_config() -> dict[str, Any]:
    return {
        "addonDir": "",
        "savedVariablesFile": "",
        "inboxFile": "",
        "defaultCwd": "",
        "tocInterface": "16001",
        "slots": 200,
        "actMax": 60,
        "presenceMax": 2000,
        "presenceIntervalMs": 30000,
        "maxParallel": 3,
        "capture": {
            "enabled": True,
            "processName": "WowB",
            "cellPx": 4,
            "cellsPerRow": 200,
            "maxRows": 48,
            "intervalMs": 250,
            "permissionPaused": False,
        },
        "apiKey": "",
        "model": "grok-4-latest",
        "apiBase": "https://api.x.ai/v1",
        "provider": "xai",
        "claudeApiKey": "",
        "claudeModel": "claude-sonnet-4-5",
        "claudeApiBase": "https://api.anthropic.com",
        "allowedTools": [],
        "pollMs": 750,
        "progressWriteMs": 3000,
        "timeoutMs": 1800000,
    }


def load_config() -> dict[str, Any] | None:
    p = config_path()
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def _secret_store():
    """``secret_store`` module when the OS store is usable, else ``None``."""
    try:
        from . import secret_store

        return secret_store if secret_store.available() else None
    except Exception:  # noqa: BLE001
        return None


def secure_store_label() -> str | None:
    """Human name of the active OS secret store, or ``None`` (config.json only)."""
    store = _secret_store()
    return store.STORE_LABEL if store is not None else None


def _stored_secret(field: str) -> str:
    store = _secret_store()
    if store is None:
        return ""
    return store.get(field)


def _append_log(line: str) -> None:
    """Best-effort bridge.log line. Callers must never pass a secret value."""
    try:
        import time

        path = log_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {line}\n")
    except Exception:  # noqa: BLE001
        pass


def secrets_for_disk(cfg: dict[str, Any]) -> dict[str, Any]:
    """Copy of ``cfg`` safe to write to config.json.

    On Windows each non-empty secret field is written to Credential Manager
    and verified; on success the on-disk copy gets ``""``. On failure (or on
    Mac / Linux) the value is kept so the player is never left without a key.
    The caller's in-memory ``cfg`` is not modified.
    """
    store = _secret_store()
    if store is None:
        return cfg
    out = dict(cfg)
    for field in SECRET_FIELDS:
        val = str(out.get(field) or "").strip()
        if not val:
            continue
        if store.put(field, val):
            out[field] = ""
            _append_log(f"[secrets] {field} stored in {store.STORE_LABEL}")
        else:
            _append_log(
                f"[secrets] {field}: {store.STORE_LABEL} write failed — "
                "kept in local config.json"
            )
    return out


def save_config(cfg: dict[str, Any]) -> Path:
    p = config_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    data = secrets_for_disk(cfg)
    tmp = p.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(p)
    return p


def forget_stored_keys() -> list[str]:
    """Delete WoWGrok keys from the OS secret store. Returns deleted fields."""
    store = _secret_store()
    if store is None:
        return []
    return [f for f in SECRET_FIELDS if store.delete(f)]


def resolve_api_key(cfg: dict | None = None) -> str:
    env = os.environ.get("XAI_API_KEY") or ""
    if env:
        return env
    if cfg and cfg.get("apiKey"):
        return str(cfg["apiKey"])
    return _stored_secret("apiKey")


def has_api_key(cfg: dict | None = None) -> bool:
    """xAI key only. Claude uses :func:`has_claude_api_key`."""
    return bool(resolve_api_key(cfg))


def api_key_source(cfg: dict | None = None) -> str:
    if os.environ.get("XAI_API_KEY"):
        return "env XAI_API_KEY"
    if cfg and cfg.get("apiKey"):
        return "config.json"
    if _stored_secret("apiKey"):
        return secure_store_label() or "secret store"
    return "MISSING — set XAI_API_KEY or config apiKey"


def resolve_provider(cfg: dict | None = None) -> str:
    """``xai`` or ``claude``. Missing or unknown values stay on xAI."""
    raw = ""
    if cfg is not None:
        raw = str(cfg.get("provider") or "").strip().lower()
    if raw in ("xai", "claude"):
        return raw
    return "xai"


def resolve_claude_api_key(cfg: dict | None = None) -> str:
    env = os.environ.get("ANTHROPIC_API_KEY") or ""
    if env:
        return env
    if cfg and cfg.get("claudeApiKey"):
        return str(cfg["claudeApiKey"])
    return _stored_secret("claudeApiKey")


def has_claude_api_key(cfg: dict | None = None) -> bool:
    return bool(resolve_claude_api_key(cfg))


def claude_api_key_source(cfg: dict | None = None) -> str:
    if os.environ.get("ANTHROPIC_API_KEY"):
        return "env ANTHROPIC_API_KEY"
    if cfg and cfg.get("claudeApiKey"):
        return "config.json"
    if _stored_secret("claudeApiKey"):
        return secure_store_label() or "secret store"
    return "MISSING — set ANTHROPIC_API_KEY or config claudeApiKey"


def has_provider_api_key(cfg: dict | None = None) -> bool:
    """True when the active provider's key is available (env or config)."""
    if resolve_provider(cfg) == "claude":
        return has_claude_api_key(cfg)
    return has_api_key(cfg)


def derive_paths_from_addon_dir(cfg: dict, addon_dir: str, account: str | None = None) -> dict:
    """Fill inboxFile / savedVariablesFile from AddOns dir (and optional account)."""
    cfg = dict(cfg)
    addon_dir = str(Path(addon_dir).resolve())
    cfg["addonDir"] = addon_dir
    cfg["inboxFile"] = str(Path(addon_dir) / "WoWGrok" / "Inbox.lua")
    client = str(Path(addon_dir).parent.parent)  # .../Interface/AddOns -> client root
    if account:
        cfg["savedVariablesFile"] = str(
            Path(client) / "WTF" / "Account" / account / "SavedVariables" / "WoWGrok.lua"
        )
    elif not cfg.get("savedVariablesFile"):
        # placeholder until account is known
        cfg["savedVariablesFile"] = str(
            Path(client) / "WTF" / "Account" / "YOUR_ACCOUNT" / "SavedVariables" / "WoWGrok.lua"
        )
    return cfg
