# WoW Grok

Chat with [xAI Grok](https://docs.x.ai/) from inside **World of Warcraft: Forever**. Send a task, keep questing, get pinged in-game when the answer lands.

> **Screenshot:** coming after live testing. See [docs/screenshot-placeholder.md](docs/screenshot-placeholder.md).

This is **not** Grok Bot and **not** Claude Code. A packaged companion app on your Mac or Windows PC talks to `https://api.x.ai/v1/responses` with **your** API key. Default model: `grok-4-latest`.

Based on MIT [wow-claude](https://github.com/chelinho139/wow-claude) by chelinho139. **We rewrote the companion bridge in Python** (not a Node.js port of that project). Players use the **executable only** — you never copy AddOn folders by hand, and you never run Python, pip, or npm.

## What you get

- In-game window via `/wow-grok` or `/grok` (also `/ai`, `/ask`)
- **Shift-click links** — with the WoWGrok input focused, shift-click items/spells/quests to insert links; tooltips expand on send
- Multiple chats with persistent Grok conversations
- Status light, progress, and reply recovery if the beta client wipes addon data
- No code injection, no memory reading, no fake input — documented addon APIs + screen strip + files only

## Not supported

**GeForce Now, Shadow, and any cloud / streaming WoW.** The bridge must run on the same computer as a normal WoW install so it can read the on-screen pixel strip and write AddOn files.

## Requirements

- Windows 10/11 or macOS
- World of Warcraft: Forever (or a matching classic / beta flavor folder) in **Windowed** or **Windowed (Fullscreen)** / borderless mode (exclusive fullscreen blocks capture)
- An xAI API key from [console.x.ai](https://console.x.ai/) (Grok **API**, not a Grok Bot token). Claude (Anthropic key) is optional at first run.
- **Bridge:** `WoWGrok.exe` (Windows) or `WoWGrok.app` (Mac) from Releases — **separate downloads**, not one shared installer

**Windows:** one download. `WoWGrok.exe` is the app and installs the addon for you. It's unsigned, so SmartScreen may say "Windows protected your PC": click **More info → Run anyway**. Leave the **tray** icon running while you play; **Quit** is only for stopping later. Three steps: [docs/INSTALL-WINDOWS.md](docs/INSTALL-WINDOWS.md).

**Mac:** one download. The DMG shows **WoWGrok.app** plus an **Applications** shortcut — drag the app into Applications, then launch from there. The Release build is unsigned: hold **Control** and click → **Open**, then **Open Anyway** in Privacy & Security if shown. Grant **Screen Recording**, Quit/reopen once if offered, then leave the **menu bar** companion running while you play. Three steps: [docs/INSTALL-MAC.md](docs/INSTALL-MAC.md).

## Simple install

Full walkthrough: [docs/INSTALL-USERS.md](docs/INSTALL-USERS.md). Mac and Windows are **separate downloads** from this project’s **Releases**.

### Windows: set up in 2 to 3 minutes

Details and fair questions: [docs/INSTALL-WINDOWS.md](docs/INSTALL-WINDOWS.md).

1. **Download the app. It installs the addon.** Get `WoWGrok.exe` from the newest `wow-grok-win-v…` release and double-click it. SmartScreen (unsigned build): **More info → Run anyway**. Confirm your WoW `Interface\AddOns` folder.
2. **Connect your AI: paste an API key.** Choose **xAI** (Enter = default) or **Claude**, paste that key, and wait for **Done** while the app writes the `WoWGrok` addon and reply slots. Newer Windows builds keep the key in **Windows Credential Manager**; 0.1.27 and earlier use local `config.json`.
3. **Log in and play.** Leave the **tray** icon **Running**. Use **Windowed** or **Windowed (Fullscreen)**, fully restart WoW, enable **WoW Grok** at character select, and type **`/wow-grok`** or **`/grok`**. Tray → **Quit** only when you want to stop later.

### Mac: set up in 2 to 3 minutes

Details and fair questions: [docs/INSTALL-MAC.md](docs/INSTALL-MAC.md).

1. **Download the app and addon.** Get the newest `wow-grok-mac-v…` `.dmg` from Releases, drag **WoWGrok.app** into Applications, then launch from there. Gatekeeper (unsigned): **Control-click → Open**, then **Open Anyway** if shown. Confirm your WoW `Interface/AddOns` folder — the app creates the addon and reply slots.
2. **Connect your AI.** First launch opens the in-app setup wizard — pick **Claude** or **Grok** (xAI), paste that API key, then continue to **Say hi in game**. Grant **Screen Recording**, Quit/reopen once if offered, then leave the **menu bar** companion running. The key stays in local `config.json` under Application Support.
3. **Start questing.** Use **Windowed** or **Windowed (Fullscreen)** / borderless, fully restart Forever, enable **WoW Grok** at character select, and type **`/wow-grok`** or **`/grok`**. Menu bar → **Quit WoWGrok** only when you want to stop later.

You never need Python, pip, npm, or a terminal for this path.

### Cloud / GeForce Now

**Unsupported.** Use a local Forever / WoW install on the same PC as the app.

## How it works (short)

WoW addons cannot open the network. **Out:** the addon draws your message as a strip of colored pixels; the bridge captures that corner and decodes it. **In:** the bridge writes replies into the slot AddOns and the game loads a fresh one. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Developers only

Building from source, running tests, packaging, and any `python` / `pip` steps: [docs/DEV.md](docs/DEV.md). Players should ignore this section.

## License

MIT. Attribution to upstream wow-claude preserved in [LICENSE](LICENSE).
