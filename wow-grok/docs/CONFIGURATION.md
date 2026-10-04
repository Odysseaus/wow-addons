# Configuration (Python bridge)

Runtime settings live in a local **`config.json`** (gitignored). The menu-bar app only quits, so change provider and keys in this file.

- Dev (`python -m bridge_py`): `bridge_py/config.json`
- Frozen macOS app: `~/Library/Application Support/WoWGrok/config.json`
- Windows exe: `config.json` next to the `.exe`

Mac and Windows share `bridge_py`, so both read the same keys. The file is created on first run. Prefer environment variables over putting keys in the file.

**xAI (Grok) is the default provider.** Set `"provider": "claude"` to use Anthropic Claude behind the same inbox/outbox. The in-game addon keeps the same protocol.

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

First-run GUI writes paths and, for the default xAI provider, asks for the xAI key, then installs `WoWGrok` + `WoWGrok_S001`–`S200`. For Claude, set `provider` to `claude` and provide `ANTHROPIC_API_KEY` or `claudeApiKey` (a short prompt appears if that key is missing and a GUI is available). See [INSTALL-USERS.md](INSTALL-USERS.md) and [DEV.md](DEV.md).
