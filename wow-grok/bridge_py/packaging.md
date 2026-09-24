# Packaging WoW Grok (Python bridge)

Build **separate** binaries per OS. There is **no** single shared installer that covers Mac and Windows.

| Platform | Artifact | Build machine |
|----------|----------|---------------|
| Windows  | `WoWGrok.exe` (one-file or onedir) | Windows Helper / OMEN |
| macOS    | `WoWGrok.app` and/or `.dmg` | a Mac |

GeForce Now / cloud WoW is **not supported** — the bridge must run on the same computer as a local WoW install (Screen capture + AddOns folder).

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

Do **not** bake an API key into the binary. First-run UI writes `config.json` next to the exe (or inside the `.app` Contents when frozen — see `bridge_py/config.runtime_dir()`).

## Windows (run on Windows Helper / OMEN)

From an elevated-or-normal PowerShell in the repo:

```powershell
cd path\to\wow-grok
.\.venv\Scripts\Activate.ps1
pip install pillow pyinstaller

pyinstaller `
  --name WoWGrok `
  --onefile `
  --console `
  --collect-all bridge_py `
  --add-data "bridge_py\config.example.json;bridge_py" `
  --add-data "bridge\capture.ps1;bridge" `
  --add-data "addon\WoWGrok;addon\WoWGrok" `
  -m bridge_py

# Output: dist\WoWGrok.exe
```

Notes:

- Ship `capture.ps1` beside the exe **or** inside the bundle via `--add-data` (capture_win looks for `bridge/capture.ps1`).
- Users still need the Lua addon under `Interface/AddOns/WoWGrok` (first-run / install-slots can create slot siblings).
- Test on the same machine that runs Forever before distributing.

Optional onedir (easier debugging):

```powershell
pyinstaller --name WoWGrok --onedir --console --collect-all bridge_py -m bridge_py
```

## macOS (run on a Mac)

```bash
cd /path/to/wow-grok
source .venv/bin/activate
pip install pillow pyinstaller

pyinstaller \
  --name WoWGrok \
  --windowed \
  --osx-bundle-identifier com.wowgrok.bridge \
  --collect-all bridge_py \
  --add-data "bridge_py/config.example.json:bridge_py" \
  --add-data "addon/WoWGrok:addon/WoWGrok" \
  -m bridge_py

# Output: dist/WoWGrok.app
```

Console build (see logs in Terminal):

```bash
pyinstaller --name WoWGrok --console --collect-all bridge_py -m bridge_py
```

### Screen Recording

The frozen app (or Terminal, if you run from source) must be granted **Screen Recording** in:

System Settings → Privacy & Security → Screen Recording

Without it, pixel-strip capture fails; SavedVariables `/reload` fallback may still work.

### DMG (optional)

```bash
hdiutil create -volname WoWGrok -srcfolder dist/WoWGrok.app -ov -format UDZO dist/WoWGrok.dmg
```

Code signing / notarization are out of scope for this milestone; add Apple Developer signing before public Gatekeeper-friendly distribution.

## What not to do

- Do not produce one cross-platform “universal install” blob.
- Do not commit `config.json`, `.env`, or binaries with embedded keys.
- Do not put the API key in the Lua addon.
