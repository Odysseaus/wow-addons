# WoW Grok

Chat with [xAI Grok](https://docs.x.ai/) from inside **World of Warcraft: Forever**. Send a task, keep questing, get pinged in-game when the answer lands.

> **Screenshot:** coming after live testing. See [docs/screenshot-placeholder.md](docs/screenshot-placeholder.md).

This is **not** Grok Bot and **not** Claude Code. A packaged companion app on your Mac or Windows PC talks to `https://api.x.ai/v1/responses` with **your** API key. Default model: `grok-4-latest`.

Based on MIT [wow-claude](https://github.com/chelinho139/wow-claude) by chelinho139. **We rewrote the companion bridge in Python** (not a Node.js port of that project). Players use the **executable only** — you never copy AddOn folders by hand, and you never run Python, pip, or npm.

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

**Mac Gatekeeper:** the Release build is unsigned. Hold **Control** and click `WoWGrok.app` → **Open**, then use **System Settings → Privacy & Security → Open Anyway** if shown. A plain double-click often only shows **Done** and will not launch. Also grant **Screen Recording** (same Privacy & Security pane).

## Simple install

Full walkthrough: [docs/INSTALL-USERS.md](docs/INSTALL-USERS.md).

1. **Download** the Mac or Windows executable from this project’s **Releases** (`WoWGrok.app` / `.dmg`, or `WoWGrok.exe` — separate builds).
2. **Run** it:
   - **Windows:** double-click `WoWGrok.exe`.
   - **Mac (unsigned):** do **not** rely on a plain double-click — that often only shows **Done** and never launches. Instead:
     1. Hold **Control** and click `WoWGrok.app` → click **Open**.
     2. If macOS still blocks it, open **System Settings → Privacy & Security**, then click **Open Anyway** (if shown).
3. **Enter your xAI API key** when asked — stored only in a local `config.json` (never uploaded, never written into Lua).
4. **Pick or confirm** your WoW `Interface/AddOns` folder (auto-detect, or a folder picker).
5. Wait while the **app creates** the main `WoWGrok` addon and reply slots `WoWGrok_S001`–`WoWGrok_S200` as top-level siblings in that folder (can take about a minute). Do **not** copy 200 folders yourself.
6. **Mac only:** grant **Screen Recording** to `WoWGrok.app` under System Settings → Privacy & Security → Screen Recording.
7. **Start Forever** (fully quit and relaunch WoW if it was already open — a `/reload` is not enough for new AddOns). At character select, enable **WoW Grok** and leave the slot entries enabled.
8. **Type `/wow-grok` or `/grok` in game chat.**

You never need Python, pip, npm, or a terminal for this path.

### Cloud / GeForce Now

**Unsupported.** Use a local Forever / WoW install on the same PC as the app.

## How it works (short)

WoW addons cannot open the network. **Out:** the addon draws your message as a strip of colored pixels; the bridge captures that corner and decodes it. **In:** the bridge writes replies into the slot AddOns and the game loads a fresh one. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Developers only

Building from source, running tests, packaging, and any `python` / `pip` steps: [docs/DEV.md](docs/DEV.md). Players should ignore this section.

## License

MIT. Attribution to upstream wow-claude preserved in [LICENSE](LICENSE).
