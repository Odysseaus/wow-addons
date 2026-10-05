# Install WoW Grok (players — executable only)

Chat with **xAI Grok** from inside **World of Warcraft: Forever** using the packaged companion app.

> **Not supported:** GeForce Now, Shadow, or any cloud/streaming WoW. The bridge must run on the **same Mac or Windows PC** that has a normal WoW install (it reads your screen strip and writes AddOn files).

You do **not** need Python, pip, npm, or a terminal. Download the app, run it, play.

Building from source is documented separately in [DEV.md](DEV.md).

> **Windows players:** use **[INSTALL-WINDOWS.md](INSTALL-WINDOWS.md)**. It's three steps (download the app, paste an API key, log in and play) plus fair questions about SmartScreen, the pixel bar, windowed mode, and where your key is stored. The rest of this page covers both platforms, with Mac detail.

---

## What you need

1. A local Forever / WoW install (Retail, Classic, Classic Era, Beta / Forever flavor folders are fine).
2. An **xAI API key** from [https://console.x.ai/](https://console.x.ai/) (kept only on your machine). First run can use **Claude** instead (Anthropic key); xAI is the default.
3. **`WoWGrok.exe` (Windows) or `WoWGrok.app` (Mac)** from Releases — **separate** downloads; there is no single shared installer.

---

## Install steps

### 1. Download

Get the build for your OS from the project **Releases** page:

| OS | File |
|----|------|
| Windows | `WoWGrok.exe` |
| Mac | `.dmg` (app + Applications shortcut) or `WoWGrok.app` zip |

### 2. Install and run the app

**Windows:** double-click `WoWGrok.exe`. If SmartScreen says "Windows protected your PC", click **More info → Run anyway** (unsigned build). Full Windows steps: [INSTALL-WINDOWS.md](INSTALL-WINDOWS.md).

**Mac:**

1. Open the `.dmg` (Finder shows **WoWGrok.app** and an **Applications** shortcut) — or unzip the release.
2. **Drag `WoWGrok.app` onto the Applications shortcut** (or into `/Applications`).
3. Eject the DMG. Always launch from **Applications**, not from the DMG or Downloads.
4. First open (unsigned build) — a plain double-click often only shows **Done** and does **not** launch:
   - Hold **Control** and click `WoWGrok.app` → click **Open**.
   - If macOS still blocks it, open **System Settings → Privacy & Security** and click **Open Anyway** (if shown).

On **first launch** the app will:

1. Ask **xAI or Claude** (Enter keeps xAI), then for that **API key**. It stays on this computer (not uploaded, not put in the Lua addon). Mac: local `config.json`. Windows: see [where the key is stored](INSTALL-WINDOWS.md#fair-questions).
2. Auto-find your `Interface/AddOns` folder, or show a folder picker if none / several are found.
3. **Copy** the main `WoWGrok` addon into that folder and **create** reply slots `WoWGrok_S001` … `WoWGrok_S200` as **top-level siblings** next to it (plus signal wav stubs). This can take about a minute — wait for the “done” dialog.
4. Keep running as the **live bridge** (not a one-shot installer). After Done / OK, leave WoWGrok running while you play. **Windows:** the **system tray** icon (menu shows **Running**). **Mac:** look for the **WoWGrok** icon in the **menu bar** (quiet companion; no Dock icon). Quit from the menu bar when finished. Quit exits the menu bar, bridge, and capture together so `/Applications/WoWGrok.app` can be replaced.

### 3. Mac only — Gatekeeper + Screen Recording

Keep the app in **`/Applications`** (drag from the DMG). The Release build is **unsigned**.

1. Hold **Control** and click `WoWGrok.app` in Applications → **Open** (plain double-click often only shows **Done** and will not launch).
2. If still blocked: **System Settings → Privacy & Security** → **Open Anyway** (if shown).
3. **Screen Recording:** On first launch WoWGrok may show an in-app sheet and request access so a **WoWGrok** row appears under System Settings → Privacy & Security → Screen Recording (or Screen & System Audio Recording). Turn **WoWGrok** ON.
4. When the app offers **Quit WoWGrok**, click it so Screen Recording can stick, then reopen from Applications (Force Quit should not be needed). After that reopen, **leave WoWGrok running** for the whole Forever session.

### 4. Keep the bridge running

**WoWGrok.app / WoWGrok.exe stays running while you play.** It is the live companion bridge, not an installer that exits after setup. On **Mac**, after first-run look for the **WoWGrok** icon in the **menu bar** and leave it there while you play; use **Quit WoWGrok** from that menu when you are done. On **Windows**, leave the **system tray** icon running; tray → **Quit** is only for stopping later, not part of opening or using the AddOn. If you quit, in-game capture and replies stop until you launch it again.

### 5. In game

1. **Fully quit** World of Warcraft and relaunch it (`/reload` is not enough for new AddOns). Use **Windowed** or **Windowed (Fullscreen)** / borderless (exclusive fullscreen blocks the screen read).
2. At character select, enable **WoW Grok** (leave the `WoW Grok slot ###` entries enabled).
3. **Type `/wow-grok` or `/grok` in game chat.**

### 6. Cloud / GeForce Now

**Unsupported.** The app must share a machine with a normal local WoW install.

---

## Privacy of your API key

- **Mac:** stored in local `config.json` (`~/Library/Application Support/WoWGrok/`).
- **Windows:** newer builds (after 0.1.27) store it in **Windows Credential Manager** (`WoWGrok/apiKey`, `WoWGrok/claudeApiKey`) and move any old `config.json` key there on the next launch. 0.1.27 and earlier use `config.json` next to `WoWGrok.exe`. Details: [INSTALL-WINDOWS.md](INSTALL-WINDOWS.md#fair-questions).
- **Never** sent to the WoW addon / Lua.
- **Never** committed to git.
- You can instead set environment variable `XAI_API_KEY` (or `ANTHROPIC_API_KEY` for Claude); the environment overrides any stored key.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| Windows: “Windows protected your PC” | **More info → Run anyway** (unsigned build). |
| “Missing API key” | Re-run the app and paste the key, or set `XAI_API_KEY`. |
| Addon / slots missing | Re-run the **WoWGrok** app so it reinstalls into AddOns; then fully quit/relaunch WoW. |
| No replies in game | Confirm **WoWGrok is still running** (Mac: menu bar icon; Windows: tray icon; it must stay up while you play), AddOns path, WoW fully restarted, addon + slots enabled, windowed/borderless. |
| Mac app won’t launch / only shows Done | Hold **Control** → click `WoWGrok.app` → **Open**; then **System Settings → Privacy & Security → Open Anyway** if shown. Plain double-click is unreliable for this unsigned build. |
| xAI SSL / CERTIFICATE_VERIFY_FAILED on Mac | Use **v0.1.13+** (bundles certifi CA store in the frozen .app). Quit old WoWGrok, replace the app, reopen. |
| Capture errors on Mac / screen-record prompt loops | Enable **WoWGrok** under Screen Recording, then **Quit and reopen** WoWGrok (toggle alone is not enough). First launch may prompt Screen Recording and must create a WoWGrok row in System Settings; the in-app sheet shows unless a real capture probe says granted (v0.1.12+; window-list alone is not enough). Use windowed/borderless. |
| Post-install dialog stuck (spinning) | Force Quit WoWGrok (install is already done), reopen; use v0.1.3+ which uses a dismissible Done / OK window. |
| Cloud / GeForce Now | Unsupported — use a local install. |

More detail: [ARCHITECTURE.md](ARCHITECTURE.md), [CONFIGURATION.md](CONFIGURATION.md). Developers: [DEV.md](DEV.md).
