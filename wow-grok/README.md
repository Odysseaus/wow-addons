# WoW Grok

Chat with [xAI Grok](https://docs.x.ai/) from inside **World of Warcraft: Forever**. Send a task, keep questing, get pinged in-game when the answer lands.

> **Screenshot:** coming after live testing. See [docs/screenshot-placeholder.md](docs/screenshot-placeholder.md).

This is **not** Grok Bot and **not** Claude Code. A small **Python** companion on your Mac or Windows PC talks to `https://api.x.ai/v1/responses` with **your** API key. Default model: `grok-4-latest`.

Based on MIT [wow-claude](https://github.com/chelinho139/wow-claude) by chelinho139.

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
- **Bridge:** packaged `WoWGrok.exe` (Windows) or `WoWGrok.app` (Mac) when Releases ship — until then, Python 3.10+ from source (below). **You do not need Node.js.**

Mac needs **Screen Recording** permission for the bridge (System Settings → Privacy & Security → Screen Recording).

## Simple install

Full walkthrough: [docs/INSTALL-USERS.md](docs/INSTALL-USERS.md).

### 1. Get the project

Clone or download this folder from the repo:

`https://github.com/Odysseaus/wow-addons/tree/main/wow-grok`

### 2. Install the addon + reply slots

Copy into your client’s `Interface/AddOns` (examples — adjust the flavor folder if needed):

| Platform | Typical AddOns folder |
|---|---|
| Mac | `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns` |
| Windows | `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns` |

- Copy `addon/WoWGrok` → `…/AddOns/WoWGrok`
- Reply slots `WoWGrok_S001` … `WoWGrok_S200` must sit as **top-level** siblings next to `WoWGrok` (WoW will not load nested AddOns). Create them with:

```bash
python -m bridge_py --install-slots
```

(First bridge launch can also auto-detect `Interface/AddOns`, or show a folder picker if it finds none / several.)

### 3. Run the bridge

**When binaries ship (Releases):** run `WoWGrok.exe` or open `WoWGrok.app`. Mac and Windows are **separate** downloads — not one shared installer.

**From source (interim):**

```bash
cd wow-grok
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
pip install pillow
python -m bridge_py
```

On first launch:

1. Enter your **xAI API key** — stored only in local `bridge_py/config.json` on that machine (never uploaded, never written into Lua, never committed).
2. Confirm or pick the WoW `Interface/AddOns` folder if asked.

### 4. In game

1. Fully quit and relaunch WoW (a `/reload` is not enough for new AddOns).
2. At character select, enable **WoW Grok** (leave the slot entries enabled).
3. Type `/wow-grok` or `/grok`.

## How it works (short)

WoW addons cannot open the network. **Out:** the addon draws your message as a strip of colored pixels; the bridge captures that corner and decodes it. **In:** the bridge writes replies into the slot AddOns and the game loads a fresh one. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Packaging

Separate Windows `.exe` and Mac `.app` / `.dmg` builds — see [bridge_py/packaging.md](bridge_py/packaging.md).

## License

MIT. Attribution to upstream wow-claude preserved in [LICENSE](LICENSE).
