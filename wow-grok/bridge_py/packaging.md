# Packaging WoW Grok (Python bridge)

Build **separate** binaries per OS. There is **no** single shared installer that covers Mac and Windows.

| Platform | Artifact | Build machine |
|----------|----------|---------------|
| Windows  | `WoWGrok.exe` (one-file) | **Windows Helper / OMEN** (required for a real Win binary) |
| macOS    | `WoWGrok.app` and/or `.dmg` | a Mac |
| Linux    | smoke-only one-file (CI / this box) | any Linux — proves freeze; **not** a ship target |

GeForce Now / cloud WoW is **not supported** — the bridge must run on the same computer as a local WoW install (screen capture + AddOns folder).

## Prerequisites (both)

```bash
cd /path/to/wow-grok
python -m venv .venv
# Windows: .venv\Scripts\activate
source .venv/bin/activate
pip install -U pip
pip install pillow pyinstaller
# or: pip install -e ".[dev]"
```

Do **not** bake an API key into the binary. First-run UI writes `config.json` next to the exe (see `bridge_py/config.runtime_dir()`).

Frozen capture re-entry: the bridge spawns `WoWGrok --run-capture-mac …` / `--run-capture-win …` (see `bridge_py/run_entry.py`).

## Windows (run on Windows Helper / OMEN)

```powershell
cd path\to\wow-grok
.\.venv\Scripts\Activate.ps1
pip install pillow pyinstaller
pyinstaller --noconfirm bridge_py\build_win.spec
# Output: dist\WoWGrok.exe
```

Helper: `bridge_py\scripts\build_win.ps1`

Notes:

- Spec embeds `bridge/capture.ps1` (`capture_win` looks under `_MEIPASS/bridge/` and next to the exe).
- Users still need the Lua addon under `Interface/AddOns/WoWGrok` (`--install-slots` creates **WoWGrok_S001–S200** top-level siblings).
- Real Windows builds need the Helper / OMEN machine — this Linux box only runs a Linux freeze smoke.

Optional onedir:

```powershell
pyinstaller --name WoWGrok --onedir --console --collect-submodules bridge_py bridge_py\__main__.py
```

## macOS (run on a Mac)

```bash
cd /path/to/wow-grok
source .venv/bin/activate
pip install pillow pyinstaller
pyinstaller --noconfirm bridge_py/build_mac.spec
# Output: dist/WoWGrok.app
```

Helper: `bridge_py/scripts/build_mac.sh`

Console one-file (logs in Terminal):

```bash
pyinstaller --name WoWGrok --onefile --console --collect-submodules bridge_py \
  --osx-bundle-identifier com.wowgrok.bridge \
  --add-data "bridge_py/config.example.json:bridge_py" \
  --add-data "addon/WoWGrok:addon/WoWGrok" \
  bridge_py/run_entry.py
```

### Screen Recording

Grant **Screen Recording** to the frozen app (or Terminal if running from source):

System Settings → Privacy & Security → Screen Recording

Without it, `capture_mac.py` fails with a clear error; SavedVariables `/reload` fallback may still work.

### DMG (optional)

```bash
hdiutil create -volname WoWGrok -srcfolder dist/WoWGrok.app -ov -format UDZO dist/WoWGrok.dmg
```

Code signing / notarization are out of scope for this milestone.

## Linux freeze smoke (this box / CI)

On Debian/Ubuntu install the shared library first: `sudo apt-get install -y libpython3.13`.

```bash
bridge_py/scripts/build_linux_smoke.sh
# → bridge_py/dist-linux-smoke/WoWGrokLinuxSmoke --help
```

Not a supported runtime for live WoW capture.

## What not to do

- Do not produce one cross-platform “universal install” blob.
- Do not commit `config.json`, `.env`, or binaries with embedded keys.
- Do not put the API key in the Lua addon.
- Do not expect Mac `.app` / Win `.exe` builds from this Linux box (smoke only).
