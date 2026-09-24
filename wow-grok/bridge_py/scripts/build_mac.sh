#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source .venv/bin/activate 2>/dev/null || true
pip install -q pillow pyinstaller rumps
pyinstaller --noconfirm bridge_py/build_mac.spec
echo "Built: $ROOT/dist/WoWGrok.app"

# Optional drag-to-Applications DMG (create-dmg; brew install create-dmg)
if command -v create-dmg >/dev/null 2>&1; then
  STAGE="$ROOT/dist/dmg-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -R "$ROOT/dist/WoWGrok.app" "$STAGE/"
  rm -f "$ROOT/dist/WoWGrok.dmg"
  create-dmg \
    --volname "WoWGrok" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "WoWGrok.app" 150 185 \
    --hide-extension "WoWGrok.app" \
    --app-drop-link 450 185 \
    "$ROOT/dist/WoWGrok.dmg" \
    "$STAGE/" || true
  if [[ -f "$ROOT/dist/WoWGrok.dmg" ]]; then
    echo "DMG: $ROOT/dist/WoWGrok.dmg (app + Applications shortcut)"
  else
    echo "create-dmg did not produce a DMG; falling back to bare hdiutil"
    hdiutil create -volname WoWGrok -srcfolder dist/WoWGrok.app -ov -format UDZO dist/WoWGrok.dmg
  fi
else
  echo "Optional DMG: brew install create-dmg, then re-run; or:"
  echo "  hdiutil create -volname WoWGrok -srcfolder dist/WoWGrok.app -ov -format UDZO dist/WoWGrok.dmg"
fi
echo "Grant Screen Recording to WoWGrok.app before live capture."
echo "Steady state: menu bar icon (LSUIElement); Quit from the menu."
