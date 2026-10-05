"""AI provider key health: missing / invalid-expired detection for the wizard gate.

Definitions (used by :func:`first_run.onboard_wizard_gate`):

* **missing** — the configured provider (``xai`` / ``claude``) has no key in env,
  ``config.json`` or the OS secret store (:func:`config.has_provider_api_key`).
* **invalid / expired** — either
    - ``config.json`` ``providerKeyInvalid[<provider>]`` is set (written when a
      live chat or the startup probe got an auth rejection), or
    - the startup probe (``GET <apiBase>/models``) returns an auth rejection.
  Auth rejection = xAI HTTP 401/403, or HTTP 400 whose message says the API key
  is incorrect/invalid/expired/revoked/blocked (real xAI bad-key response is
  ``400 "Incorrect API key provided"``); Anthropic HTTP 401 or
  ``authentication_error``. Network errors, timeouts, 429, 5xx → **unknown**,
  never invalid (offline must not reopen the wizard).

The flag clears when a new key is saved in the wizard, a probe succeeds, or a
chat succeeds. Keys are never logged or stored in the flag.
"""
from __future__ import annotations

import time
import urllib.error
import urllib.request
from typing import Any, Callable

from . import config as cfgmod

INVALID_FLAG_KEY = "providerKeyInvalid"
PROBE_ON_STARTUP_KEY = "keyProbeOnStartup"

XAI_DEFAULT_BASE = "https://api.x.ai/v1"
CLAUDE_DEFAULT_BASE = "https://api.anthropic.com/v1"
ANTHROPIC_VERSION = "2023-06-01"

_XAI_KEY_WORDS = ("invalid", "incorrect", "expired", "revoked", "blocked", "disabled")


def is_auth_failure(provider: str, status: int | None, message: str | None) -> bool:
    """True when an API error means the key itself was rejected."""
    msg = (message or "").lower()
    prov = (provider or "xai").strip().lower()
    if prov == "claude":
        return status == 401 or "authentication_error" in msg
    if status in (401, 403):
        return True
    if status == 400 and "api key" in msg and any(w in msg for w in _XAI_KEY_WORDS):
        return True
    return False


def _provider(cfg: dict[str, Any] | None, provider: str | None) -> str:
    return (provider or cfgmod.resolve_provider(cfg)).strip().lower()


def mark_key_invalid(
    cfg: dict[str, Any], provider: str, status: int | None, reason: str = ""
) -> dict[str, Any]:
    flags = cfg.get(INVALID_FLAG_KEY)
    if not isinstance(flags, dict):
        flags = {}
    flags[provider] = {
        "status": status,
        "reason": (reason or "")[:120],
        "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    cfg[INVALID_FLAG_KEY] = flags
    return cfg


def clear_key_invalid(cfg: dict[str, Any], provider: str | None = None) -> bool:
    """Drop the invalid flag for ``provider`` (all providers when None)."""
    flags = cfg.get(INVALID_FLAG_KEY)
    if not flags:
        if INVALID_FLAG_KEY in cfg:
            del cfg[INVALID_FLAG_KEY]
            return True
        return False
    if provider is None or not isinstance(flags, dict):
        del cfg[INVALID_FLAG_KEY]
        return True
    if provider not in flags:
        return False
    del flags[provider]
    if not flags:
        del cfg[INVALID_FLAG_KEY]
    return True


def is_key_flagged_invalid(cfg: dict[str, Any] | None, provider: str | None = None) -> bool:
    flags = (cfg or {}).get(INVALID_FLAG_KEY)
    if not isinstance(flags, dict):
        return False
    return bool(flags.get(_provider(cfg, provider)))


def probe_enabled(cfg: dict[str, Any] | None) -> bool:
    return (cfg or {}).get(PROBE_ON_STARTUP_KEY, True) is not False


def probe_provider_key(
    cfg: dict[str, Any] | None,
    *,
    timeout: float = 4.0,
    opener: Callable[..., Any] | None = None,
) -> str:
    """Quick key check: ``valid`` | ``invalid`` | ``unknown`` (never raises)."""
    opener = opener or urllib.request.urlopen
    prov = cfgmod.resolve_provider(cfg)
    if prov == "claude":
        key = cfgmod.resolve_claude_api_key(cfg)
        base = str((cfg or {}).get("claudeApiBase") or CLAUDE_DEFAULT_BASE).rstrip("/")
        headers = {"x-api-key": key, "anthropic-version": ANTHROPIC_VERSION}
    else:
        key = cfgmod.resolve_api_key(cfg)
        base = str((cfg or {}).get("apiBase") or XAI_DEFAULT_BASE).rstrip("/")
        headers = {"Authorization": f"Bearer {key}"}
    if not key:
        return "unknown"
    try:
        from . import ssl_certs

        ssl_certs.configure()
    except Exception:  # noqa: BLE001
        pass
    req = urllib.request.Request(f"{base}/models", headers=headers, method="GET")
    try:
        with opener(req, timeout=timeout) as resp:
            status = getattr(resp, "status", 200) or 200
            return "valid" if 200 <= int(status) < 300 else "unknown"
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode("utf-8", "replace")
        except Exception:  # noqa: BLE001
            body = ""
        return "invalid" if is_auth_failure(prov, e.code, body) else "unknown"
    except Exception:  # noqa: BLE001 — offline / TLS / timeout → unknown
        return "unknown"


def provider_token_state(
    cfg: dict[str, Any] | None,
    *,
    probe: Callable[[dict[str, Any] | None], str] | None = None,
) -> str:
    """``missing`` | ``invalid`` | ``ok`` for the configured provider.

    When ``probe`` returns ``invalid`` the flag is persisted on ``cfg`` (caller
    saves); ``valid`` clears a stale flag; ``unknown`` counts as ok.
    """
    if not cfgmod.has_provider_api_key(cfg):
        return "missing"
    if is_key_flagged_invalid(cfg):
        return "invalid"
    if probe is not None:
        result = probe(cfg)
        prov = cfgmod.resolve_provider(cfg)
        if result == "invalid":
            if cfg is not None:
                mark_key_invalid(cfg, prov, None, "startup probe rejected key")
            return "invalid"
        if result == "valid" and cfg is not None:
            clear_key_invalid(cfg, prov)
    return "ok"
