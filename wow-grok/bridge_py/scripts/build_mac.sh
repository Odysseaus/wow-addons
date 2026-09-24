#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source .venv/bin/activate 2>/dev/null || true
pip install -q pillow pyinstaller
pyinstaller --noconfirm bridge_py/build_mac.spec
echo "Built: $ROOT/dist/WoWGrok.app"
echo "Optional DMG: hdiutil create -volname WoWGrok -srcfolder dist/WoWGrok.app -ov -format UDZO dist/WoWGrok.dmg"
echo "Grant Screen Recording to WoWGrok.app before live capture."
