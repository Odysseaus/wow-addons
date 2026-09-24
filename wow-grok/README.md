# WoW Grok

Chat with [xAI Grok](https://docs.x.ai/) from inside **World of Warcraft: Forever**. Send a task, keep questing, get pinged in-game when the answer lands.

> **Screenshot:** coming after live testing. See [docs/screenshot-placeholder.md](docs/screenshot-placeholder.md).

This is **not** Grok Bot and **not** Claude Code. A packaged companion app on your Mac or Windows PC talks to `https://api.x.ai/v1/responses` with **your** API key. Default model: `grok-4-latest`.

Based on MIT [wow-claude](https://github.com/chelinho139/wow-claude) by chelinho139. **We rewrote the companion bridge in Python** (not a Node.js port of that project). Players use the executable only — no Python, pip, or Node required.

## What you get

- In-game window via `/wow-grok` or `/grok` (also `/ai`, `/ask`)
- Multiple chats with persistent Grok conversations
- Status light, progress, and reply recovery if the beta client wipes addon data
- No code injection, no memory reading, no fake input — documented addon APIs + screen strip + files only

## Not supported

**GeForce Now, Shadow, and any cloud / streaming WoW.** The bridge must run on the same computer as a normal WoW install so it can read the on-screen pixel strip and write AddOn files.

## Requirements

- Windows or macOS
- World of Warcraft: Forever (or a matching classic / beta flavor folder), **windowed or borderless** (exclusive fullscreen blocks capture)
- An xAI API key from [console.x.ai](https://console.x.ai/) (Grok **API**, not a Grok Bot token)
- **Bridge:** `WoWGrok.exe` (Windows) or `WoWGrok.app` (Mac) from Releases — **separate downloads**, not one shared installer

Mac needs **Screen Recording** permission for the app (System Settings → Privacy & Security → Screen Recording).

## Simple install

Full walkthrough: [docs/INSTALL-USERS.md](docs/INSTALL-USERS.md).

### 1. Download the app

Get **either** `WoWGrok.exe` (Windows) **or** `WoWGrok.app` (Mac) from this project’s **Releases**. Mac and Windows are separate builds.

### 2. Run it once

Double-click the app. On first launch it will:

1. Ask for your **xAI API key** — stored only in a local `config.json` next to the app (never uploaded, never written into Lua).
2. Auto-detect or let you pick your WoW `Interface/AddOns` folder.
3. **Install** the `WoWGrok` addon and reply slots `WoWGrok_S001`–`WoWGrok_S200` as top-level siblings in that folder (can take about a minute).
4. Start the bridge.

You never need to copy files by hand, and you never need Python / pip / npm.

### 3. Mac: Screen Recording

Grant **Screen Recording** to `WoWGrok.app` under System Settings → Privacy & Security → Screen Recording.

### 4. In game

1. Fully quit and relaunch WoW (a `/reload` is not enough for new AddOns).
2. At character select, enable **WoW Grok** (leave the slot entries enabled).
3. Type `/wow-grok` or `/grok`.

### 5. Cloud / GeForce Now

**Unsupported.** Use a local WoW install on the same PC as the app.

## How it works (short)

WoW addons cannot open the network. **Out:** the addon draws your message as a strip of colored pixels; the bridge captures that corner and decodes it. **In:** the bridge writes replies into the slot AddOns and the game loads a fresh one. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Developers / from source

Building from source, running tests, and packaging: [docs/DEV.md](docs/DEV.md).

## License

MIT. Attribution to upstream wow-claude preserved in [LICENSE](LICENSE).
