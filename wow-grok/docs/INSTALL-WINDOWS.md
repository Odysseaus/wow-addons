# WoW Grok on Windows: set up in 2 to 3 minutes

One download, no Node.js, npm, Python, or terminal. **WoWGrok.exe** is the desktop app *and* the addon installer. It writes the WoW Grok addon into your WoW folder for you, so there is no separate addon zip to unzip.

You need **Windows 10 or 11**, **World of Warcraft: Forever** (or another local WoW client) installed on the **same PC**, and an **API key** from xAI (the default) or Anthropic (Claude, optional).

> **Not supported:** GeForce Now, Shadow, or any cloud or streaming WoW. The app has to run on the same PC as a normal local WoW install.

---

## 1. Download the app (it installs the addon)

1. Download **`WoWGrok.exe`** from the [Releases page](https://github.com/Odysseaus/wow-addons/releases). Pick the newest **`wow-grok-win-v…`** release. Mac builds are separate (`wow-grok-mac-v…`).
2. Optional: move `WoWGrok.exe` into a folder you'll keep, such as `Documents\WoWGrok`. Its settings file sits next to it.
3. Double-click `WoWGrok.exe`. If Windows says **"Windows protected your PC"**, click **More info**, then **Run anyway**. You'll see this because the exe is **unsigned** (see [Fair questions](#fair-questions)).
4. Confirm your WoW **Interface\AddOns** folder. WoWGrok looks for it automatically and shows a folder picker if it finds none or several.

## 2. Connect your AI: paste an API key

1. Choose **xAI (Grok)** or **Claude**. Pressing Enter (the default button) keeps **xAI**.
2. Paste the key for that provider:
   - xAI: create one at [console.x.ai](https://console.x.ai/) (keys start with `xai-`).
   - Claude: create one at [console.anthropic.com](https://console.anthropic.com/).
   - API keys are billed per use by the provider. A Grok, ChatGPT, or Claude **chat subscription is not an API key**.
3. Wait for **Done**. In about a minute WoWGrok writes the `WoWGrok` addon and its reply slots (`WoWGrok_S001` to `WoWGrok_S200`) into your AddOns folder. Don't copy any folders yourself.

## 3. Log in and play

1. **Leave WoWGrok running.** It sits in the **system tray** (the notification area by the clock; you may need the **^** arrow to see it). Right-click it and the menu should say **Running**. It's the live bridge between WoW and your AI, not a one-time installer.
2. Set WoW to **Windowed** or **Windowed (Fullscreen)** display mode. Exclusive **Fullscreen** blocks the screen read.
3. If WoW was already open, **fully quit and relaunch** it. `/reload` doesn't pick up new AddOns.
4. At character select, open **AddOns**, enable **WoW Grok**, and leave the `WoW Grok slot ###` entries enabled.
5. Log in and type **`/wow-grok`** or **`/grok`** in chat.

**Stopping later:** right-click the tray icon and choose **Quit**. Quit is only for when you want to stop. You don't need it to open or use WoW Grok, and in-game replies stop until you open WoWGrok.exe again.

---

## Fair questions

**Windows says the app is unrecognized. Is that OK?**
WoWGrok.exe is **not code-signed** right now, so SmartScreen may show "Windows protected your PC" the first time. Click **More info**, then **Run anyway**, but only for an exe you downloaded from this project's Releases page. Releases built by GitHub Actions list the commit they were built from.

**Why a desktop app? Can I use just the addon?**
WoW addons can't go online. The addon shows your message in game, the app reads it and asks your AI, then writes the answer back into AddOn files the game loads. Without the app running, the addon can't get replies. Play in **Windowed** or **Windowed (Fullscreen)** so the app can see the game window.

**What's the pixelated bar at the top left of WoW?**
That's how your question gets from WoW to the app. When you send a message, the addon briefly draws it as a strip of colored squares in the top-left corner. WoWGrok reads that small area, sends your question to your AI, and the strip goes away once the message is received. Nothing is injected into the game, nothing reads game memory, and no key presses or clicks are faked.

**Does it read my screen?**
Only the top-left area of the WoW window where the addon draws the strip. Windows captures what's on screen there, so a window covering that corner gets read too. Keep the corner clear.

**Where is my API key stored?**
- **Newer Windows builds** (the first release after 0.1.27 that includes this change): the key goes in **Windows Credential Manager**, under Control Panel → Credential Manager → Windows Credentials. Look for entries named `WoWGrok/apiKey` or `WoWGrok/claudeApiKey`. If you're upgrading and your key was in `config.json`, WoWGrok moves it into Credential Manager on the next launch and blanks it in the file. If Credential Manager can't be written, the key stays in `config.json` so you aren't locked out.
- **0.1.27 and earlier:** the key is in plain text in `config.json` next to `WoWGrok.exe`.
- Either way, the key stays on your PC. It's sent only to the AI provider you chose, never to the WoW addon or Lua, and never committed to git. The `XAI_API_KEY` or `ANTHROPIC_API_KEY` environment variables override any stored key.
- **To change or remove a key:** delete the `WoWGrok/…` entry in Credential Manager (and clear `apiKey` / `claudeApiKey` in `config.json` if set), then reopen WoWGrok.exe and it will ask again. You can also paste a new key into `config.json`; WoWGrok uses it and moves it into Credential Manager on the next launch.

**Does it work with GeForce Now or cloud WoW?**
No. WoWGrok must run on the same PC as a local WoW install.

**Is the game-context feature here?**
Not yet. This trunk doesn't include the in-game game-context area (`/wow-grok context`, location / money / XP). See the changelog note under 0.1.21.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| SmartScreen blocks the exe | **More info → Run anyway** (unsigned build). |
| No tray icon / no replies | Reopen `WoWGrok.exe` and check that the tray icon's menu says **Running**. Check the display mode is Windowed / Windowed (Fullscreen), WoW was fully restarted, and WoW Grok and its slots are enabled. |
| "Missing API key" | Reopen `WoWGrok.exe` and paste the key, or set `XAI_API_KEY` / `ANTHROPIC_API_KEY`. |
| Addon or slots missing | Reopen `WoWGrok.exe` so it reinstalls into AddOns, then fully quit and relaunch WoW. |
| Wrong key / want to switch | See "To change or remove a key" above. |

Everyone, both platforms: [INSTALL-USERS.md](INSTALL-USERS.md). Developers / from source: [DEV.md](DEV.md). Build notes: [bridge_py/packaging.md](../bridge_py/packaging.md).
