#!/usr/bin/env bash
# Linux one-file smoke: prove entrypoint freezes and --help works.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
PY="${ROOT}/.venv/bin/python"
PIP="${ROOT}/.venv/bin/pip"
if [[ ! -x "$PY" ]]; then
  python3 -m venv .venv
  PY="${ROOT}/.venv/bin/python"
  PIP="${ROOT}/.venv/bin/pip"
fi
"$PIP" install -q -U pip
"$PIP" install -q pillow pyinstaller
OUT="$ROOT/bridge_py/dist-linux-smoke"
rm -rf "$OUT" "$ROOT/bridge_py/build-linux-smoke"
mkdir -p "$OUT"
cd "$ROOT"
"$PY" -m PyInstaller \
  --noconfirm \
  --clean \
  --onefile \
  --console \
  --name WoWGrokLinuxSmoke \
  --distpath "$OUT" \
  --workpath "$ROOT/bridge_py/build-linux-smoke" \
  --specpath "$ROOT/bridge_py/build-linux-smoke" \
  --paths "$ROOT" \
  --collect-submodules bridge_py \
  --hidden-import bridge_py.capture_mac \
  --hidden-import bridge_py.strip_codec \
  "$ROOT/bridge_py/run_entry.py"
BIN="$OUT/WoWGrokLinuxSmoke"
"$BIN" --help | head -20
echo "SMOKE_OK: $BIN --help"
