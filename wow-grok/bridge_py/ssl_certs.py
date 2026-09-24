"""Bundle CA store for frozen apps (PyInstaller Mac SSL gap).

urllib / ssl need a CA file; frozen Mac builds often ship without one.
Call configure() before any HTTPS. Safe to call multiple times.
"""
from __future__ import annotations

import os
import ssl
from typing import Optional

_configured = False
_ca_path: Optional[str] = None


def ca_bundle_path() -> str:
    """Return path to certifi's cacert.pem (works when collected into a freeze)."""
    import certifi

    return certifi.where()


def configure() -> str:
    """Set SSL env vars (if unset) and patch default HTTPS context to use certifi.

    Returns the CA bundle path in use.
    """
    global _configured, _ca_path
    path = ca_bundle_path()
    _ca_path = path

    if not os.environ.get("SSL_CERT_FILE"):
        os.environ["SSL_CERT_FILE"] = path
    if not os.environ.get("REQUESTS_CA_BUNDLE"):
        os.environ["REQUESTS_CA_BUNDLE"] = path

    # urllib may ignore env; force default context to load our bundle.
    ssl._create_default_https_context = lambda: ssl.create_default_context(cafile=path)  # type: ignore[assignment]

    _configured = True
    return path


def is_configured() -> bool:
    return _configured


def last_ca_path() -> Optional[str]:
    return _ca_path
