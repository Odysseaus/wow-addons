# Install WoW Grok (players — executable only)

Chat with **xAI Grok** from inside **World of Warcraft: Forever** using the packaged companion app.

> **Not supported:** GeForce Now, Shadow, or any cloud/streaming WoW. The bridge must run on the **same Mac or Windows PC** that has a normal WoW install (it reads your screen strip and writes AddOn files).

You do **not** need Python, pip, npm, or a terminal. Download the app, run it, play.

Building from source is documented separately in [DEV.md](DEV.md).

---

## What you need

1. A local Forever / WoW install (Retail, Classic, Classic Era, Beta / Forever flavor folders are fine).
2. An **xAI API key** from [https://console.x.ai/](https://console.x.ai/) (kept only on your machine).
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

**Windows:** double-click `WoWGrok.exe`.

**Mac:**

1. Open the `.dmg` (Finder shows **WoWGrok.app** and an **Applications** shortcut) — or unzip the release.
2. **Drag `WoWGrok.app` onto the Applications shortcut** (or into `/Applications`).
3. Eject the DMG. Always launch from **Applications**, not from the DMG or Downloads.
4. First open (unsigned build) — a plain double-click often only shows **Done** and does **not** launch:
   - Hold **Control** and click `WoWGrok.app` → click **Open**.
   - If macOS still blocks it, open **System Settings → Privacy & Security** and click **Open Anyway** (if shown).

On **first launch** the app will:

1. Ask for your **xAI API key**. It is saved only in a local `config.json` next to the app (not uploaded, not put in the Lua addon).
2. Auto-find your `Interface/AddOns` folder, or show a folder picker if none / several are found.
3. **Copy** the main `WoWGrok` addon into that folder and **create** reply slots `WoWGrok_S001` … `WoWGrok_S200` as **top-level siblings** next to it (plus signal wav stubs). This can take about a minute — wait for the “done” dialog.
4. Keep running as the **live bridge** (not a one-shot installer). After Done / OK, leave WoWGrok running while you play — look for the **WoWGrok** icon in the **menu bar** (quiet companion; no Dock icon). Quit from the menu bar when finished. Quit exits the menu bar, bridge, and capture together so `/Applications/WoWGrok.app` can be replaced.

### 3. Mac only — Gatekeeper + Screen Recording

Keep the app in **`/Applications`** (drag from the DMG). The Release build is **unsigned**.

1. Hold **Control** and click `WoWGrok.app` in Applications → **Open** (plain double-click often only shows **Done** and will not launch).
2. If still blocked: **System Settings → Privacy & Security** → **Open Anyway** (if shown).
3. **Screen Recording:** On first launch WoWGrok may show an in-app sheet and request access so a **WoWGrok** row appears under System Settings → Privacy & Security → Screen Recording (or Screen & System Audio Recording). Turn **WoWGrok** ON.
4. When the app offers **Quit WoWGrok**, click it so Screen Recording can stick, then reopen from Applications (Force Quit should not be needed). After that reopen, **leave WoWGrok running** for the whole Forever session.

### 4. Keep the bridge running

**WoWGrok.app / WoWGrok.exe stays running while you play.** It is the live companion bridge, not an installer that exits after setup. On **Mac**, after first-run look for the **WoWGrok** icon in the **menu bar** and leave it there while you play; use **Quit WoWGrok** from that menu when you are done. If you quit, in-game capture and replies stop until you launch it again.

### 5. In game

1. **Fully quit** World of Warcraft and relaunch it (`/reload` is not enough for new AddOns).
2. At character select, enable **WoW Grok** (leave the `WoW Grok slot ###` entries enabled).
3. **Type `/wow-grok` or `/grok` in game chat.**

### 6. Cloud / GeForce Now

**Unsupported.** The app must share a machine with a normal local WoW install.

---

## Privacy of your API key

- Stored in **local** `config.json` next to the app (or next to the frozen exe).
- **Never** sent to the WoW addon / Lua.
- **Never** committed to git.
- You can instead set environment variable `XAI_API_KEY` and leave `apiKey` empty in config.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| “Missing API key” | Re-run the app and paste the key, or set `XAI_API_KEY`. |
| Addon / slots missing | Re-run the **WoWGrok** app so it reinstalls into AddOns; then fully quit/relaunch WoW. |
| No replies in game | Confirm **WoWGrok is still running** (Mac: menu bar icon; it must stay up while you play), AddOns path, WoW fully restarted, addon + slots enabled, windowed/borderless. |
| Mac app won’t launch / only shows Done | Hold **Control** → click `WoWGrok.app` → **Open**; then **System Settings → Privacy & Security → Open Anyway** if shown. Plain double-click is unreliable for this unsigned build. |
| xAI SSL / CERTIFICATE_VERIFY_FAILED on Mac | Use **v0.1.13+** (bundles certifi CA store in the frozen .app). Quit old WoWGrok, replace the app, reopen. |
| Capture errors on Mac / screen-record prompt loops | Enable **WoWGrok** under Screen Recording, then **Quit and reopen** WoWGrok (toggle alone is not enough). v0.1.15+ stops the Settings spam loop when screencapture fails after an unsigned upgrade (capture exits; Connect/presence still work). v0.1.16+ also persists `capture.permissionPaused` so capture never re-spawns (no system Screen Recording sheet on Forever launch). **v0.1.18+** clears pause automatically after a CG window-strip resume smoke (or clear the flag in Application Support config.json). Probe=granted alone never clears pause. First launch may prompt Screen Recording and must create a WoWGrok row in System Settings; the in-app sheet shows unless a real capture probe says granted (v0.1.12+; window-list alone is not enough). Use windowed/borderless (not exclusive fullscreen). |
| Post-install dialog stuck (spinning) | Force Quit WoWGrok (install is already done), reopen; use v0.1.3+ which uses a dismissible Done / OK window. |
| Cloud / GeForce Now | Unsupported — use a local install. |

More detail: [ARCHITECTURE.md](ARCHITECTURE.md), [CONFIGURATION.md](CONFIGURATION.md). Developers: [DEV.md](DEV.md).
