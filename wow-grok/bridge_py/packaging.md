# Packaging WoW Grok (Python bridge)

Build **separate** binaries per OS. There is **no** single shared installer that covers Mac and Windows.

| Platform | Artifact | Build machine |
|----------|----------|---------------|
| Windows  | `WoWGrok.exe` (one-file) | **Windows Helper / OMEN** or **GitHub Actions `windows-latest`** (required for a real Win binary) |
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
pip install pillow certifi pyinstaller rumps  # Win: add pystray; skip rumps
# or: pip install -e ".[dev]"
# rumps is macOS-only (menu bar status item); skip on Windows/Linux
```

Do **not** bake an API key into the binary. First-run UI writes `config.json` next to the exe (see `bridge_py/config.runtime_dir()`).

Frozen capture re-entry: the bridge spawns `WoWGrok --run-capture-mac …` / `--run-capture-win …` (see `bridge_py/run_entry.py`).

## Windows (run on Windows Helper / OMEN)

```powershell
cd path\to\wow-grok
.\.venv\Scripts\Activate.ps1
pip install pillow certifi pyinstaller pystray
pyinstaller --noconfirm bridge_py\build_win.spec
# Output: dist\WoWGrok.exe
```

Helper: `bridge_py\scripts\build_win.ps1`

Notes:

- Spec embeds `bridge_py/capture.ps1` (`capture_win` looks under `_MEIPASS/bridge/` and next to the exe).
- The frozen app installs the Lua addon and **WoWGrok_S001–S200** on first run; `capture.ps1` is baked from `bridge_py/capture.ps1`.
- Spec uses `console=False` + `pystray` tray (Running + Quit) and certifi CA data.
- Real Windows builds need Helper / OMEN **or** `.github/workflows/wow-grok-win-release.yml` — this Linux box only runs a Linux freeze smoke.

Optional onedir:

```powershell
pyinstaller --name WoWGrok --onedir --console --collect-submodules bridge_py bridge_py\__main__.py
```

## macOS (run on a Mac)

```bash
cd /path/to/wow-grok
source .venv/bin/activate
pip install pillow certifi pyinstaller rumps  # Win: add pystray; skip rumps
pyinstaller --noconfirm bridge_py/build_mac.spec
# Output: dist/WoWGrok.app (LSUIElement menu-bar agent; no Dock icon)
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

First launch requests access **in-process** (CoreGraphics via ctypes) so a **WoWGrok** row appears in Settings; enable it, then Quit and reopen. Without it, `capture_mac.py` fails with a clear error; SavedVariables `/reload` fallback may still work.

### DMG (drag to Applications)

Prefer **create-dmg** so the volume shows `WoWGrok.app` plus an Applications shortcut:

```bash
brew install create-dmg
STAGE=dist/dmg-stage
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R dist/WoWGrok.app "$STAGE/"
rm -f dist/WoWGrok.dmg
create-dmg \
  --volname "WoWGrok" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "WoWGrok.app" 150 185 \
  --hide-extension "WoWGrok.app" \
  --app-drop-link 450 185 \
  dist/WoWGrok.dmg \
  "$STAGE/"
```

Fallback (app only, no Applications link):

```bash
hdiutil create -volname WoWGrok -srcfolder dist/WoWGrok.app -ov -format UDZO dist/WoWGrok.dmg
```

Code signing / notarization are out of scope for this milestone.

### Menu bar companion

Frozen Mac builds set `LSUIElement=true` and run a **rumps** status item after first-run (title "WoWGrok", status "Running", **Quit WoWGrok**). No spinning desktop window in steady state.

## Linux freeze smoke (this box / CI)

On Debian/Ubuntu install the shared library first: `sudo apt-get install -y libpython3.13`.

```bash
bridge_py/scripts/build_linux_smoke.sh
# → bridge_py/dist-linux-smoke/WoWGrokLinuxSmoke --help
```

Not a supported runtime for live WoW capture.

## What not to do

- Do not produce one cross-platform "universal install" blob.
- Do not commit `config.json`, `.env`, or binaries with embedded keys.
- Do not put the API key in the Lua addon.
- Do not expect Mac `.app` / Win `.exe` builds from this Linux box (smoke only).
