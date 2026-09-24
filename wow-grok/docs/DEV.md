# Developer / from-source notes

Players should use the packaged `WoWGrok.exe` / `WoWGrok.app` — see [INSTALL-USERS.md](INSTALL-USERS.md). This page is for contributors and anyone building or debugging from source.

## Quick start

```bash
cd wow-grok
python3 -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install pillow
python -m bridge_py --help
python -m unittest discover -s bridge_py/tests -v
```

First real GUI run opens a local popup for your xAI API key and AddOns folder; values go only into `bridge_py/config.json` on your machine. The app then copies `addon/WoWGrok` into AddOns and creates `WoWGrok_S001`–`WoWGrok_S200` as top-level siblings.

Headless / CI (no tk):

```bash
export XAI_API_KEY=xai-...
python -m bridge_py --headless --wow "/path/to/Interface/AddOns"
# or install slots only (dev):
python -m bridge_py --install-slots
```

## Layout

```
bridge_py/          Python package (supervisor, protocol, xAI, capture, first-run install)
addon/WoWGrok/      Lua addon (bundled into the frozen app)
bridge/             Node bridge (legacy until cutover)
docs/INSTALL-USERS.md   Player path (executable only)
docs/DEV.md             This file
bridge_py/packaging.md  PyInstaller
```

## Packaging

Separate Windows `.exe` and Mac `.app`/`.dmg` — see `bridge_py/packaging.md`.

Both `build_mac.spec` and `build_win.spec` bundle `addon/WoWGrok` so first-run can copy it from `sys._MEIPASS` without a source checkout.

## Related

- [README.python.md](../README.python.md) — short Python-bridge pointer
- Platform-specific legacy notes: [INSTALL-MAC.md](INSTALL-MAC.md), [INSTALL-WINDOWS.md](INSTALL-WINDOWS.md)

## History

An earlier Node.js companion (`bridge/`, `setup.js`, `npm`) was removed; the shipped bridge is **Python-only** (`bridge_py/`). Upstream inspiration remains MIT [wow-claude](https://github.com/chelinho139/wow-claude).

