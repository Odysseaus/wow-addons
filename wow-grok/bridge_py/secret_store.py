"""OS secret store for API keys (Windows Credential Manager).

Windows only. Uses the documented advapi32 ``CredWriteW`` / ``CredReadW`` /
``CredDeleteW`` calls through ``ctypes`` (no extra dependency, nothing new for
PyInstaller to miss). Each key is a *Generic* credential named
``WoWGrok/<field>`` (``WoWGrok/apiKey``, ``WoWGrok/claudeApiKey``) with
``CRED_PERSIST_LOCAL_MACHINE`` — the same place NeverQuestAlone and most
Windows apps keep secrets. Players can see / remove them in
Control Panel → Credential Manager → Windows Credentials.

macOS and Linux report :func:`available` ``False`` here; they keep using
``config.json`` (Mac Keychain is out of scope for the Windows track).

Never logs or raises with a secret value in the message.
"""
from __future__ import annotations

import sys
from typing import Any

TARGET_PREFIX = "WoWGrok/"
USER_NAME = "WoWGrok"
STORE_LABEL = "Windows Credential Manager"

# Windows constants (wincred.h / winerror.h)
CRED_TYPE_GENERIC = 1
CRED_PERSIST_LOCAL_MACHINE = 2
CRED_MAX_CREDENTIAL_BLOB_SIZE = 5 * 512
ERROR_NOT_FOUND = 1168

# Tests may install a fake backend (object with read/write/delete). None = real.
_backend_override: Any | None = None
_win_backend_cache: Any | None = None


class SecretStoreError(Exception):
    """Credential Manager call failed. Message never contains the secret."""


def target_name(field: str) -> str:
    return f"{TARGET_PREFIX}{field}"


class _WinCredBackend:
    """Thin ctypes wrapper over advapi32 Cred* (UTF-16LE blob, like keyring)."""

    def __init__(self) -> None:
        import ctypes
        from ctypes import wintypes

        self._ctypes = ctypes

        class FILETIME(ctypes.Structure):
            _fields_ = [
                ("dwLowDateTime", wintypes.DWORD),
                ("dwHighDateTime", wintypes.DWORD),
            ]

        class CREDENTIALW(ctypes.Structure):
            _fields_ = [
                ("Flags", wintypes.DWORD),
                ("Type", wintypes.DWORD),
                ("TargetName", wintypes.LPWSTR),
                ("Comment", wintypes.LPWSTR),
                ("LastWritten", FILETIME),
                ("CredentialBlobSize", wintypes.DWORD),
                ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
                ("Persist", wintypes.DWORD),
                ("AttributeCount", wintypes.DWORD),
                ("Attributes", ctypes.c_void_p),
                ("TargetAlias", wintypes.LPWSTR),
                ("UserName", wintypes.LPWSTR),
            ]

        self._CREDENTIALW = CREDENTIALW
        pcred = ctypes.POINTER(CREDENTIALW)
        self._PCREDENTIALW = pcred

        advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)  # type: ignore[attr-defined]

        self._CredReadW = advapi32.CredReadW
        self._CredReadW.argtypes = [
            wintypes.LPCWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
            ctypes.POINTER(pcred),
        ]
        self._CredReadW.restype = wintypes.BOOL

        self._CredWriteW = advapi32.CredWriteW
        self._CredWriteW.argtypes = [pcred, wintypes.DWORD]
        self._CredWriteW.restype = wintypes.BOOL

        self._CredDeleteW = advapi32.CredDeleteW
        self._CredDeleteW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD]
        self._CredDeleteW.restype = wintypes.BOOL

        self._CredFree = advapi32.CredFree
        self._CredFree.argtypes = [ctypes.c_void_p]
        self._CredFree.restype = None

    def read(self, target: str) -> str | None:
        ctypes = self._ctypes
        p = self._PCREDENTIALW()
        if not self._CredReadW(target, CRED_TYPE_GENERIC, 0, ctypes.byref(p)):
            err = ctypes.get_last_error()  # type: ignore[attr-defined]
            if err == ERROR_NOT_FOUND:
                return None
            raise SecretStoreError(f"CredReadW failed (winerror {err})")
        try:
            size = int(p.contents.CredentialBlobSize)
            if size <= 0 or not p.contents.CredentialBlob:
                return ""
            raw = ctypes.string_at(p.contents.CredentialBlob, size)
        finally:
            self._CredFree(p)
        try:
            return raw.decode("utf-16-le")
        except UnicodeDecodeError:
            return raw.decode("utf-8", errors="replace")

    def write(self, target: str, value: str) -> None:
        ctypes = self._ctypes
        blob = value.encode("utf-16-le")
        if len(blob) > CRED_MAX_CREDENTIAL_BLOB_SIZE:
            raise SecretStoreError("secret too large for Credential Manager")
        buf = (ctypes.c_ubyte * max(len(blob), 1)).from_buffer_copy(blob or b"\0")
        cred = self._CREDENTIALW()
        cred.Flags = 0
        cred.Type = CRED_TYPE_GENERIC
        cred.TargetName = target
        cred.Comment = "WoW Grok API key (local only)"
        cred.CredentialBlobSize = len(blob)
        cred.CredentialBlob = ctypes.cast(buf, ctypes.POINTER(ctypes.c_ubyte))
        cred.Persist = CRED_PERSIST_LOCAL_MACHINE
        cred.AttributeCount = 0
        cred.Attributes = None
        cred.TargetAlias = None
        cred.UserName = USER_NAME
        if not self._CredWriteW(ctypes.byref(cred), 0):
            err = ctypes.get_last_error()  # type: ignore[attr-defined]
            raise SecretStoreError(f"CredWriteW failed (winerror {err})")

    def delete(self, target: str) -> bool:
        ctypes = self._ctypes
        if self._CredDeleteW(target, CRED_TYPE_GENERIC, 0):
            return True
        err = ctypes.get_last_error()  # type: ignore[attr-defined]
        if err == ERROR_NOT_FOUND:
            return False
        raise SecretStoreError(f"CredDeleteW failed (winerror {err})")


def _backend() -> Any | None:
    global _win_backend_cache
    if _backend_override is not None:
        return _backend_override
    if sys.platform != "win32":
        return None
    if _win_backend_cache is None:
        try:
            _win_backend_cache = _WinCredBackend()
        except Exception:  # noqa: BLE001 — no advapi32 / ctypes: config.json fallback
            return None
    return _win_backend_cache


def available() -> bool:
    """True on Windows when Credential Manager can be called."""
    return _backend() is not None


def get(field: str) -> str:
    """Stored secret for ``field`` or ``""`` (missing / unavailable / error)."""
    b = _backend()
    if b is None:
        return ""
    try:
        return b.read(target_name(field)) or ""
    except Exception:  # noqa: BLE001
        return ""


def put(field: str, value: str) -> bool:
    """Store ``value`` and verify by reading it back. False on any failure."""
    b = _backend()
    if b is None or not value:
        return False
    try:
        b.write(target_name(field), value)
        return b.read(target_name(field)) == value
    except Exception:  # noqa: BLE001
        return False


def delete(field: str) -> bool:
    """Remove the stored secret. True if something was deleted."""
    b = _backend()
    if b is None:
        return False
    try:
        return bool(b.delete(target_name(field)))
    except Exception:  # noqa: BLE001
        return False
