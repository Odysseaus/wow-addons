# Install WoW Grok (simple — no Node.js)

Chat with **xAI Grok** from inside **World of Warcraft: Forever** using the Python bridge.

> **Not supported:** GeForce Now, Shadow, or any cloud/streaming WoW. The bridge must run on the **same Mac or Windows PC** that has a normal WoW install (it reads your screen strip and writes AddOn files).

This guide is for the **Python** package (`bridge_py/`). The older Node bridge still works if you already use it; you do **not** need Node for the Python path.

---

## What you need

1. A local Forever / WoW install (Retail, Classic, Classic Era, Beta / Forever flavor folders are fine).
2. An **xAI API key** from [https://console.x.ai/](https://console.x.ai/) (kept only on your machine).
3. Either:
   - **Easy (later):** a downloaded `WoWGrok.exe` (Windows) or `WoWGrok.app` (Mac), **or**
   - **From source now:** Python 3.10+ on your computer.

Mac and Windows use **separate** apps — there is no single shared installer file.

---

## Mac (from source)

1. Download or clone this `wow-grok` repo.
2. Open Terminal in the repo folder:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install pillow
   # optional: pip install -e .
   ```

3. Copy the addon into WoW (first run can also point at AddOns):

   ```bash
   # Example Forever / classic beta path — adjust if yours differs
   cp -R addon/WoWGrok "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/"
   ```

4. Start the bridge:

   ```bash
   python -m bridge_py
   ```

5. **First launch**
   - A popup asks for your **xAI API key**. It is saved only in `bridge_py/config.json` on this Mac (not uploaded, not put in the Lua addon).
   - If WoW isn’t auto-found, pick your `Interface/AddOns` folder (or the `_classic_beta_` / `_forever_` client folder).

6. Grant **Screen Recording** to Terminal (or `WoWGrok.app` when packaged):  
   System Settings → Privacy & Security → Screen Recording.

7. Fully quit and relaunch WoW. At character select, enable **WoW Grok** (leave the `WoW Grok slot ###` entries enabled).

8. In game: `/wow-grok` or `/grok`.

If slots were not created yet:

```bash
python -m bridge_py --install-slots
```

then restart WoW again.

---

## Windows (from source)

1. Download or clone this `wow-grok` repo.
2. In PowerShell in the repo folder:

   ```powershell
   py -3 -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install pillow
   ```

3. Copy `addon\WoWGrok` into your WoW `Interface\AddOns` folder  
   (typical Forever path under `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`).

4. Start:

   ```powershell
   python -m bridge_py
   ```

5. First launch: enter your xAI API key (stored only in local `bridge_py\config.json`) and confirm/pick AddOns if asked.

6. Fully quit and relaunch WoW; enable **WoW Grok**; use `/wow-grok` in game.

Slots:

```powershell
python -m bridge_py --install-slots
```

Capture uses the existing `bridge\capture.ps1` helper for this milestone.

---

## Packaged apps (when available)

| OS | File | Notes |
|----|------|--------|
| Windows | `WoWGrok.exe` | Double-click; keep capture.ps1 available as documented in packaging. |
| Mac | `WoWGrok.app` / `.dmg` | Grant Screen Recording to the app. |

Builders: see `bridge_py/packaging.md` (PyInstaller commands — run on Mac for Mac, on Windows for Windows).

---

## Privacy of your API key

- Stored in **local** `config.json` next to the bridge (or next to the frozen exe).
- **Never** sent to the WoW addon / Lua.
- **Never** committed to git (repo ignores `**/config.json`).
- You can instead set environment variable `XAI_API_KEY` and leave `apiKey` empty in config.

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| “Missing API key” | Re-run the bridge and paste the key, or set `XAI_API_KEY`. |
| No replies in game | Confirm AddOns path, slots installed, WoW fully restarted, addon enabled. |
| Capture errors on Mac | Screen Recording permission; use windowed/borderless (not exclusive fullscreen). |
| Cloud / GeForce Now | Unsupported — use a local install. |

More detail (Node-era docs still useful for architecture): `docs/ARCHITECTURE.md`, `docs/CONFIGURATION.md`.
