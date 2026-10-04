# Install on Windows (players)

Use the packaged **`WoWGrok.exe`** — no Node.js, npm, or Python required.

1. Download `WoWGrok.exe` from the GitHub Release (tag like `wow-grok-win-v0.1.27`).
2. SmartScreen may warn on the first unsigned drop — choose **More info → Run anyway** if you trust the release.
3. Double-click and finish setup. The first-run prompt asks **xAI or Claude**; Enter / the default button keeps **xAI**. Then enter that provider's API key and confirm your WoW **Interface/AddOns** folder.
4. Leave **WoWGrok.exe** running while you play. A **system tray** (notification area) icon shows **Running**.
5. After Forever is running with **WoW Grok** enabled, type `/wow-grok` or `/grok` in game chat.
6. When you are done and want to stop the bridge, open that tray icon and choose **Quit** — Quit closes the app; it is not part of opening or using the AddOn.

This 0.1.27 trunk does **not** include the in-game game-context area (`/wow-grok context`, location / money / XP). See the changelog note under 0.1.21.

Full player steps: [INSTALL-USERS.md](INSTALL-USERS.md).

Developers / from source: [DEV.md](DEV.md). Build notes: [bridge_py/packaging.md](../bridge_py/packaging.md).
