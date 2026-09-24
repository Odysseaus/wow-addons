# Configuration (Python bridge)

Runtime config lives in **`bridge_py/config.json`** (gitignored), created on first run of the app / `python -m bridge_py`. Prefer the env var **`XAI_API_KEY`** over putting `apiKey` in the file.

Template: `bridge_py/config.example.json`.

Common keys:

| Key | Purpose |
|-----|---------|
| `addonDir` | WoW `Interface/AddOns` folder |
| `apiKey` / `XAI_API_KEY` | xAI Grok API key (never commit) |
| `model` | Default `grok-4-latest` |
| `slots` | Reply slot count (default 200) |
| `capture.processName` | Game process (`WowB` for Forever, etc.) |
| `gameContext` | `true` — inject character/zone context from the addon into Grok’s instructions. `false` ignores it. In-game: `/wow-grok context [on|off]` |

First-run GUI writes paths and installs `WoWGrok` + `WoWGrok_S001`–`S200`. See [INSTALL-USERS.md](INSTALL-USERS.md) and [DEV.md](DEV.md).
