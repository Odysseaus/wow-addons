# Installing on macOS

A start-to-finish walkthrough for a Mac, ending with the `wow-grok` command available in any terminal. The short version is in the [README](../README.md). Pixel capture on Mac is **experimental**.

## 1. Prerequisites

| Need | Check | Get it |
|---|---|---|
| macOS (Intel or Apple Silicon) | | |
| World of Warcraft: Forever, **windowed or borderless** | Options → Graphics → Display Mode | Exclusive fullscreen blocks screen capture |
| Node.js 20 or newer | `node -v` prints `v20.x` or higher | [nodejs.org](https://nodejs.org) LTS, or `brew install node` |
| Git | `git --version` | Xcode CLT (`xcode-select --install`) or [git-scm.com](https://git-scm.com) |
| xAI API key | `echo $XAI_API_KEY` is non-empty, or you will put it in `bridge/config.json` | [console.x.ai](https://console.x.ai/) — Grok **API**, not Grok Bot |

macOS will prompt for **Screen Recording** the first time capture runs. Allow Terminal (or iTerm, VS Code, etc. — whichever launches `node`). System Settings → Privacy & Security → Screen Recording.

On a Retina display the window is measured in points; `screencapture` writes a PNG in pixels. `capture-mac.js` reads `backingScaleFactor` and, if it is 2, samples cells at `cellPx * 2`.

## 2. Get the code

```bash
cd ~/Documents          # or wherever you keep projects
git clone https://github.com/chelinho139/wow-grok
cd wow-grok
npm install
export XAI_API_KEY="xai-..."
```

`npm install` only pulls the test tooling; the bridge itself has no dependencies. Prefer the env var over putting the key in `config.json`. Never commit a real key.

## 3. Set up the game side

```bash
node setup.js --project "$HOME/path/to/the/project/you/want/to/work/on"
```

This:

- finds the WoW client under `~/Applications/World of Warcraft/{_classic_beta_,_forever_,_retail_,_classic_era_,_classic_}` and `/Applications/World of Warcraft/...`. Pass `--wow "/Applications/World of Warcraft/_classic_beta_"` (the flavor folder that contains `Interface/`) if it can't find yours,
- copies the addon into `Interface/AddOns/WoWGrok`,
- writes `bridge/config.json` with your paths, project folder, and `capture.processName` (`World of Warcraft` or `WowB` if detectable),
- creates the 200 reply-slot addons and about 15,000 tiny signal files next to it. That count is normal: the client only discovers addon files when it launches.

`--project` is the fallback folder for chats. If you have several WoW accounts, setup picks the first and says so; pass `--account <name>` to choose.

Now **fully quit and relaunch World of Warcraft** (a `/reload` is not enough). On the character screen, open **AddOns** and make sure *WoW Grok* is enabled. The 200 *WoW Grok slot* entries stay enabled too; leave them alone.

## 4. First run

From the `wow-grok` folder:

```bash
npm start
```

You should see a banner like:

```
WoW Grok bridge
  folder   : /Users/you/path/to/your/project  (config.json; chats can override with /wow-grok cd)
  addons   : /Applications/World of Warcraft/_classic_beta_/Interface/AddOns
  slots    : 200 installed
  capture  : on (capture-mac.js, World of Warcraft, 200x48 cells of 4px)
  model    : grok-4-latest
  api key  : env XAI_API_KEY
  ...
```

Grant Screen Recording if macOS asks. In the game, type `/wow-grok`. The window opens; the light in its corner should turn green within about ten seconds. Type something in the box and press Enter.

If the light stays red, see [Troubleshooting](#troubleshooting).

## 5. Install the `wow-grok` command

```bash
cd ~/Documents/wow-grok
npm link
```

Then from any project:

```bash
cd ~/path/to/realms
wow-grok
```

Only one bridge can run at a time.

### Updating

```bash
cd ~/Documents/wow-grok
git pull
node setup.js        # re-copies the addon; keeps your config.json and the slot pool
```

Then `/reload` in game and restart the bridge. If `setup.js` reports that it created new files, quit and relaunch the game instead of `/reload`.

### Uninstalling

```bash
npm unlink -g wow-grok
```

Delete `Interface/AddOns/WoWGrok` and the `WoWGrok_S001` … `WoWGrok_S200` folders next to it, and the `wow-grok` folder. Saved chat data is in `WTF/Account/<account>/SavedVariables/WoWGrok.lua`.

## Troubleshooting

**Screen Recording denied / capture error about no image.** System Settings → Privacy & Security → Screen Recording: enable the app that runs `node` (Terminal, iTerm, Cursor, VS Code, …), then restart that app and the bridge.

**The light stays red / "waiting for … window".** Game must be windowed or borderless, not minimized, not exclusive fullscreen. `capture.processName` in `bridge/config.json` must match the process AppleScript can see (`World of Warcraft` or `WowB`; `setup.js` sets it).

**Retina / strip seen but rejected.** Capture samples at `cellPx * backingScaleFactor`. If cells mis-align, check the `capture bitmap … sample scale=` line in `bridge.log`. Stay in windowed/borderless; a title bar on a non-borderless window can shift the strip down relative to the captured origin.

**Missing xAI API key.** The banner's `api key` line must not say `MISSING`. `export XAI_API_KEY=...` in the same shell that runs `npm start`, or set `"apiKey"` in `bridge/config.json` (gitignored).

**"Cannot read config.json … Run node setup.js".** Run `node setup.js` from the repo folder, or `npm link` from the copy you set up.

**Everything else** is in the README's Troubleshooting section and in `/wow-grok diag` in game.
