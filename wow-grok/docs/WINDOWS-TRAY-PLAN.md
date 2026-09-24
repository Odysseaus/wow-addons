# Windows packaging plan — system tray + SSL (post Mac feature green)

**Status:** skip-ahead / ship path (Odysseaus GO via CoS) — tray + SSL smoke + GHA Win release in progress.  
**Locked requirement (2026-09-24):** first public `WoWGrok.exe` **must** include a system tray companion (Running + Quit), mirroring Mac menubar (`rumps` / LSUIElement). Not deferred.

## Goals for Windows Helper / first Win release
1. **Tray companion** — steady-state UI is tray only (no console window): status **Running**, action **Quit** (full process-tree teardown like Mac 0.1.10: stop capture + supervisor kill).
2. **certifi / SSL** — same as Mac 0.1.13: bundle `certifi`, set `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE`, patch default HTTPS context via `bridge_py/ssl_certs.py` at frozen start. Smoke: frozen exe HTTPS to `https://api.x.ai/v1/...` must get auth error (401), not `CERTIFICATE_VERIFY_FAILED`.
3. **PyInstaller** — extend `bridge_py/build_win.spec`: hiddenimports for tray lib + certifi `collect_data_files`; `console=False`.
4. **Parity** — first-run API key / AddOns / addon install already in Python; Win need not reimplement Mac Screen Recording TCC.

## Recommended tray stack
- Prefer **`pystray`** + **Pillow** (icon) — pure-Python, works with PyInstaller, common on Windows.
- Alternative: `infi.systray` if pystray packaging fights; avoid pulling all of Qt/wx just for tray.
- Mirror Mac `menubar.py` surface: label/title “WoWGrok”, menu items Running (disabled/info), Quit → same quit path as Mac (`stop_capture` + supervisor teardown).
- Entry: reuse `run_entry.py` / `__main__`; on `win32` start tray thread instead of `rumps`. Factor shared “status + quit” callbacks so Mac/Win stay thin wrappers.

## Files to touch (when kicked)
| Area | Files |
|------|--------|
| Tray | New `bridge_py/tray_win.py` (or extend menubar abstraction) |
| Entry | `bridge_py/bridge.py` / `__main__.py` — platform branch |
| Spec | `bridge_py/build_win.spec` + CI workflow for Windows release artifact |
| Deps | `requirements` / Actions: `pystray`, `Pillow`, `certifi` |
| Docs | `README.md`, `docs/INSTALL-USERS.md` — tray Quit, unsigned SmartScreen notes |
| Verify | Frozen SSL smoke script; manual tray Quit kills capture child |

## Non-goals until green
- Starting Win Actions / `.exe` upload before Mac feature retest green.
- GeForce Now / cloud.
- Code signing (document SmartScreen; unsigned OK for first drop unless Odysseaus asks).

## Handoff
Macbook Helper owns Mac path. When CoS kicks **Windows Helper** after feature green, point them at this plan + `bridge_py/menubar.py` (Mac behavior to mirror) + `bridge_py/ssl_certs.py`.
