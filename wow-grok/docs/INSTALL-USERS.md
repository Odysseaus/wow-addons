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
| Mac | `WoWGrok.app` (or `.dmg`) |

### 2. Run the app

Double-click `WoWGrok.exe` or open `WoWGrok.app`.

On **first launch** the app will:

1. Ask for your **xAI API key**. It is saved only in a local `config.json` next to the app (not uploaded, not put in the Lua addon).
2. Auto-find your `Interface/AddOns` folder, or show a folder picker if none / several are found.
3. **Copy** the main `WoWGrok` addon into that folder and **create** reply slots `WoWGrok_S001` … `WoWGrok_S200` as **top-level siblings** next to it (plus signal wav stubs). This can take about a minute — wait for the “done” dialog.
4. Start the bridge.

### 3. Mac only — Screen Recording

System Settings → Privacy & Security → Screen Recording → enable **WoWGrok**.

### 4. In game

1. **Fully quit** World of Warcraft and relaunch it (`/reload` is not enough for new AddOns).
2. At character select, enable **WoW Grok** (leave the `WoW Grok slot ###` entries enabled).
3. **Type `/wow-grok` or `/grok` in game chat.**

### 5. Cloud / GeForce Now

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
| No replies in game | Confirm AddOns path, WoW fully restarted, addon + slots enabled, windowed/borderless. |
| Capture errors on Mac | Screen Recording permission for the app; use windowed/borderless (not exclusive fullscreen). |
| Cloud / GeForce Now | Unsupported — use a local install. |

More detail: [ARCHITECTURE.md](ARCHITECTURE.md), [CONFIGURATION.md](CONFIGURATION.md). Developers: [DEV.md](DEV.md).
