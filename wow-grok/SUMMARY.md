# WoWGrok 0.1.25 (Mac + Windows product pin)

- **Product 0.1.25** = app/bridge **0.1.25** with xAI `web_search` on by default and `x_search` off by default; AddOn content unchanged from 0.1.24 except toc Version **0.1.25**; capture unchanged.
- **Windows 0.1.25** ship: tray (`tray_win` / Running + Quit) + GHA `WoWGrok.exe` (`wow-grok-win-v0.1.25`); same tool defaults (`web_search` on / `x_search` off); Game context currently **location, money, and XP only**.
- Default tools: `webSearch: true`, `xSearch: false` → `tools: web_search`.
- Existing **0.1.24** Mac users: set `"xSearch": false` in `~/Library/Application Support/WoWGrok/config.json`, then restart WoWGrok.
- Capture md5 `b75395986a768269a8f4ae5594709159`.
- Versions: pyproject, `__init__`, toc, `build_mac.spec`, CHANGELOG → **0.1.25**.
- Branch base: `mac/v0.1.24-xai-tools` (bbdedb9).
