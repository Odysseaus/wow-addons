# WoW Grok — summary

Public path: `Odysseaus/wow-addons` → `wow-grok/`.

Companion bridge is **Python** (`bridge_py/`). Lua addon under `addon/WoWGrok/`. Node.js bridge retired.

- First-run GUI: API key → AddOns picker → installs `WoWGrok` + `WoWGrok_S001`–`S200`
- Packaging: Mac `.app` / Windows `.exe` (separate builds); see `bridge_py/packaging.md`
- Player docs: executable-only (`README.md`, `docs/INSTALL-USERS.md`)
- Tests: `python -m unittest discover -s bridge_py/tests -v`
- Mac test build: GitHub release `wow-grok-mac-v0.1.21`
