# Configuration (Python bridge)

Runtime settings live in a local **`config.json`** (gitignored). First-run on Mac and Windows asks **xAI or Claude** (Enter keeps xAI). After that, the menu-bar app only quits — change provider/keys later in this file.

- Dev (`python -m bridge_py`): `bridge_py/config.json`
- Frozen macOS app: `~/Library/Application Support/WoWGrok/config.json`
- Windows exe: `config.json` next to the `.exe`

**Windows API keys:** `apiKey` / `claudeApiKey` go to **Windows Credential Manager** (`WoWGrok/apiKey`, `WoWGrok/claudeApiKey`), and `config.json` keeps an empty string. A key you type into `config.json` by hand is used right away and moved into Credential Manager on the next save or launch. If Credential Manager can't be written, the key stays in `config.json`. Lookup order: env var, then `config.json`, then Credential Manager. macOS keeps keys in `config.json`.

Mac and Windows share `bridge_py`, so both read the same keys. The file is created on first run. Prefer environment variables over putting keys in the file.

**xAI (Grok) is the default provider.** First-run offers Claude as well; or set `"provider": "claude"` in config later. Same inbox/outbox; the in-game addon protocol is unchanged.

Template: `bridge_py/config.example.json`.

Common keys:

| Key | Purpose |
|-----|---------|
| `addonDir` | WoW `Interface/AddOns` folder |
| `provider` | `xai` (default) or `claude` |
| `apiKey` / `XAI_API_KEY` | xAI API key when `provider` is `xai` (never commit). Env wins. |
| `model` | xAI model. Default `grok-4-latest` |
| `apiBase` | xAI base URL. Default `https://api.x.ai/v1` |
| `claudeApiKey` / `ANTHROPIC_API_KEY` | Anthropic key when `provider` is `claude` (never commit). Env wins. |
| `claudeModel` | Claude model. Default `claude-sonnet-4-5` |
| `claudeApiBase` | Anthropic base URL. Default `https://api.anthropic.com` |
| `slots` | Reply slot count (default 200) |
| `capture.processName` | Game process (`WowB` for Forever, etc.) |

First-run GUI (shared `first_run.py` for Mac DMG/app and Windows exe) writes paths, asks **xAI vs Claude** (Enter / default button = xAI), then asks for that provider's API key, then installs `WoWGrok` + `WoWGrok_S001`–`S200`. Choosing Claude with no key prompts for `claudeApiKey` (or use `ANTHROPIC_API_KEY`). The existing xAI key prompt is unchanged when xAI is selected. See [INSTALL-USERS.md](INSTALL-USERS.md) and [DEV.md](DEV.md).
