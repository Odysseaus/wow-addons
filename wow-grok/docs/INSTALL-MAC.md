# WoW Grok on Mac: set up in 2 to 3 minutes

One download, no Node.js, npm, Python, or terminal. **WoWGrok.app** is the desktop companion *and* the addon installer. First launch shows an in-app setup wizard (Connect your AI, then Say hi in game). It writes the WoW Grok addon into your WoW folder for you, so there is no separate addon zip to unzip.

You need **macOS**, **World of Warcraft: Forever** (or another local WoW client) installed on the **same Mac**, and an **API key** from xAI (the default) or Anthropic (Claude, optional).

> **Not supported:** GeForce Now, Shadow, or any cloud or streaming WoW. The app has to run on the same Mac as a normal local WoW install.

---

## 1. Download the app and addon

1. Download the Mac build from the [Releases page](https://github.com/Odysseaus/wow-addons/releases). Pick the newest **`wow-grok-mac-v…`** release (`.dmg`, or the `.app` zip). Windows builds are separate (`wow-grok-win-v…`).
2. Open the **`.dmg`**. Finder shows **WoWGrok.app** and an **Applications** shortcut.
3. **Drag `WoWGrok.app` onto the Applications shortcut** (or into `/Applications`). Eject the DMG. Always launch from **Applications** (`/Applications/WoWGrok.app` or `~/Applications/WoWGrok.app`), not from the DMG, Downloads, or an old build folder. Leftover copies under `~/wowgrok-build-*` (or other non-Applications paths) can steal Dock / Spotlight launches so you keep running an older binary even after installing a newer DMG.
4. First open (unsigned build) — a plain double-click often only shows **Done** and does **not** launch:
   - Hold **Control** and click `WoWGrok.app` → click **Open**.
   - If macOS still blocks it, open **System Settings → Privacy & Security** and click **Open Anyway** (if shown).
5. Confirm your WoW **Interface/AddOns** folder. WoWGrok looks for it automatically and shows a folder picker if it finds none or several. The app creates the `WoWGrok` addon and reply slots (`WoWGrok_S001`–`WoWGrok_S200`) for you — don't copy any folders yourself.

## 2. Connect your AI

1. On first launch, WoWGrok opens an **in-app setup wizard** (two-pane: Download → Connect your AI → Say hi in game). You can click **Finish later** and reopen the app to finish — or use menu bar → **Setup…** any time.
2. Under **Connect your AI**, pick a provider: **xAI (Grok)** (default) or **Claude**. Those are the only two providers.
3. Click **Continue**, paste the API key for that provider, and wait for the green **"{Provider} is connected."** status:
   - Grok / xAI: create a key at [console.x.ai](https://console.x.ai/) (keys start with `xai-`).
   - Claude: create a key at [console.anthropic.com](https://console.anthropic.com/).
   - API keys are billed per use by the provider. A Grok or Claude **chat subscription is not an API key**.
4. Advance to **Say hi in game**, then **Done**. In about a minute WoWGrok writes the addon and slots into your AddOns folder.
5. **Screen Recording** (needed so the app can read the top-left pixel strip):
   - On first launch WoWGrok may show an in-app sheet and request access so a **WoWGrok** row appears under **System Settings → Privacy & Security → Screen Recording** (or Screen & System Audio Recording). Turn **WoWGrok** ON.
   - If the app offers **Quit WoWGrok**, click it so the permission sticks, then reopen from Applications.
6. **Leave WoWGrok running.** After first-run it sits in the **menu bar** (quiet companion; no Dock icon). The menu shows a disabled **WoWGrok <version>** row (for example `WoWGrok 0.1.31`) so you can confirm which binary is live — if that version does not match the DMG you just installed, Quit and reopen from `/Applications`. It's the live bridge between WoW and your AI, not a one-time installer.

## 3. Start questing

1. Set WoW to **Windowed** or **Windowed (Fullscreen)** / borderless. Exclusive **Fullscreen** blocks the screen read.
2. If Forever / WoW was already open, **fully quit and relaunch** it. `/reload` doesn't pick up new AddOns.
3. At character select, open **AddOns**, enable **WoW Grok**, and leave the `WoW Grok slot ###` entries enabled.
4. Log in and type **`/wow-grok`** or **`/grok`** in chat.

**Changing your AI later:** menu bar → **Setup…** re-opens the setup wizard without quitting. Paste a new key or pick another provider; if anything changed, WoWGrok restarts its bridge in the background (the menu bar icon blinks once) so the new key takes effect.

**Stopping later:** menu bar → **Quit WoWGrok**. Quit exits the menu bar, bridge, and capture together so you can replace `/Applications/WoWGrok.app`. You don't need Quit to open or use WoW Grok, and in-game replies stop until you reopen the app.

---

## Fair questions

**macOS says the app is damaged / can't be opened / only shows Done. Is that OK?**
The Release build is **not notarized / code-signed** right now, so Gatekeeper may block a plain double-click. Hold **Control**, click `WoWGrok.app` → **Open**, then **Open Anyway** in Privacy & Security if shown — but only for an app you downloaded from this project's Releases page. Releases built by GitHub Actions list the commit they were built from.

**Why a desktop app? Can I use just the addon?**
WoW addons can't go online. The addon shows your message in game, the app reads it and asks your AI, then writes the answer back into AddOn files the game loads. Without the app running, the addon can't get replies. Play in **Windowed** or **Windowed (Fullscreen)** / borderless so the app can see the game window.

**What's the pixelated bar at the top left of WoW?**
That's how your question gets from WoW to the app. When you send a message, the addon briefly draws it as a strip of colored squares in the top-left corner. WoWGrok reads that small area, sends your question to your AI, and the strip goes away once the message is received. Nothing is injected into the game, nothing reads game memory, and no key presses or clicks are faked.

**Does it read my screen?**
Only the top-left area of the WoW window where the addon draws the strip. On Mac that needs **Screen Recording** permission for WoWGrok. A window covering that corner gets read too — keep the corner clear.

**Where is my API key stored?**
On Mac the key stays in local **`config.json`** under `~/Library/Application Support/WoWGrok/`. It stays on your Mac. It's sent only to the AI provider you chose, never to the WoW addon or Lua, and never committed to git. The `XAI_API_KEY` or `ANTHROPIC_API_KEY` environment variables override any stored key. To change or remove a key, clear `apiKey` / `claudeApiKey` in that file (or delete the file), then reopen WoWGrok.app and it will ask again. Easier: menu bar → **Setup…** and paste the new key.

**I installed a new DMG but the menu still shows an old version / Setup never appears.**
macOS Dock or Spotlight may still be launching an older binary (often from a leftover `~/wowgrok-build-*` folder) instead of `/Applications/WoWGrok.app`. Open the menu bar dropdown and check the disabled **WoWGrok <version>** row. If it is wrong, **Quit WoWGrok**, confirm `/Applications/WoWGrok.app` exists, remove or ignore old build folders, and reopen from Applications (or Spotlight after Quitting so it reindexes). You can also check `~/Library/Application Support/WoWGrok/bridge.log` for a `[startup] app_version=… executable=…` line that names the path that actually ran.

**When does the setup wizard show? I already had WoWGrok set up and only got the menu bar.**
The Connect-your-AI wizard is the **only** setup UI (the old one-at-a-time provider / key / AddOns popups are gone). It auto-opens when **any** of these is true:

- **New app version** — `lastSeenAppVersion` in `config.json` is missing or differs from the running app.
- **No AI key** — the selected provider (xAI or Claude) has no key in env, `config.json`, or the keychain.
- **Key rejected (invalid / expired)** — a quick startup check (`GET …/models`) or a real chat got an auth rejection: xAI HTTP 400 "Incorrect API key" / 401 / 403, Anthropic HTTP 401 `authentication_error`. WoWGrok remembers this as `providerKeyInvalid` in `config.json` until you paste a new key (or the key works again). Being offline, timeouts, rate limits, and 5xx **never** count as invalid.
- **AddOns folder missing** — so the wizard (not an old popup) asks for it.

Same app version + a working key stays **menu-bar only**. Closing the wizard (Done, Finish later, or the close button) records the current app version. Use menu bar → **Setup…** any time to reopen it. To skip the startup key check, set `"keyProbeOnStartup": false` in `config.json`. To **re-force the wizard** without renaming the whole file, Quit WoWGrok, open `~/Library/Application Support/WoWGrok/config.json`, delete the `lastSeenAppVersion` key (and any leftover `onboardWizardVersion`), save, and reopen — or just use menu bar → **Setup…**. To start completely fresh, Quit WoWGrok, rename that `config.json` (for example to `config.old.json`), and reopen the app.

**Does it work with GeForce Now or cloud WoW?**
No. WoWGrok must run on the same Mac as a local WoW install.

**Is the game-context feature here?**
Not yet. This trunk doesn't include the in-game game-context area (`/wow-grok context`, location / money / XP). See the changelog note under 0.1.21.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| App won't launch / only shows Done | Hold **Control** → click `WoWGrok.app` → **Open**; then **System Settings → Privacy & Security → Open Anyway** if shown. |
| No menu bar icon / no replies | Reopen from Applications and leave the menu bar companion running. Check Windowed / borderless, full WoW restart, and WoW Grok + slots enabled. |
| Menu shows wrong version after upgrade | Quit WoWGrok; launch `/Applications/WoWGrok.app` (not DMG / Downloads / `~/wowgrok-build-*`). Confirm the disabled version row and `bridge.log` `[startup]` line. Use **Setup…** to reopen the wizard. |
| "Missing API key" | Reopen WoWGrok.app and paste the key, or set `XAI_API_KEY` / `ANTHROPIC_API_KEY`. |
| Addon or slots missing | Reopen WoWGrok.app so it reinstalls into AddOns, then fully quit and relaunch WoW. |
| Capture / Screen Recording loops | Enable **WoWGrok** under Screen Recording, then **Quit and reopen** (toggle alone is not enough). |
| xAI SSL / CERTIFICATE_VERIFY_FAILED | Use **v0.1.13+** (bundles certifi CA store). Quit old WoWGrok, replace the app, reopen. |
| Post-install dialog stuck (spinning) | Force Quit WoWGrok (install is already done), reopen; use v0.1.3+ which uses a dismissible Done / OK window. |

Everyone, both platforms: [INSTALL-USERS.md](INSTALL-USERS.md). Windows: [INSTALL-WINDOWS.md](INSTALL-WINDOWS.md). Developers / from source: [DEV.md](DEV.md). Build notes: [bridge_py/packaging.md](../bridge_py/packaging.md).
