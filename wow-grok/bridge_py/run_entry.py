"""PyInstaller entrypoint — imports package so relative imports in __main__ work."""
from __future__ import annotations

from bridge_py.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
