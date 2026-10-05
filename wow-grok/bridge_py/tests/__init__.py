"""Test package: never hit the network for the startup key probe.

``key_health.probe_provider_key`` is replaced with a stub returning
``"unknown"`` (offline → treated as ok) for every test. Probe tests use
:data:`ORIGINAL_PROBE` with a fake opener.
"""
from bridge_py import key_health as _key_health

ORIGINAL_PROBE = _key_health.probe_provider_key


def _offline_probe(cfg, **_kw):  # noqa: ANN001
    return "unknown"


_key_health.probe_provider_key = _offline_probe
