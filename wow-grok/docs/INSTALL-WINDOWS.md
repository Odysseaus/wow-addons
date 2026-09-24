# Installing on Windows

A start-to-finish walkthrough for a fresh Windows machine, ending with the `wow-grok` command available in any terminal. The short version is in the [README](../README.md); this page spells out every step and what can go wrong.

## 1. Prerequisites

| Need | Check | Get it |
|---|---|---|
| Windows 10/11 on NTFS | | |
| World of Warcraft: Forever, **windowed or borderless** | Options → Graphics → Display Mode | Exclusive fullscreen blocks screen capture, so the bridge can't see your messages |
| Node.js 20 or newer | `node -v` prints `v20.x` or higher | [nodejs.org](https://nodejs.org), the LTS installer; tick "Add to PATH" (default) |
| Git | `git --version` | [git-scm.com](https://git-scm.com/download/win) |
| xAI API key | `$env:XAI_API_KEY` is set, or you will put it in `bridge/config.json` | [console.x.ai](https://console.x.ai/) — Grok **API**, not Grok Bot |

Open a new terminal after installing Node or Git so the `PATH` change is picked up. Any terminal works: Windows Terminal, PowerShell, cmd, or Git Bash.

## 2. Get the code

```powershell
cd C:\Users\<you>\Documents          # or wherever you keep projects
git clone https://github.com/chelinho139/wow-grok
cd wow-grok
npm install
$env:XAI_API_KEY = "xai-..."
```

`npm install` only pulls the test tooling; the bridge itself has no dependencies. Prefer the env var over putting the key in `config.json`. Never commit a real key.

## 3. Set up the game side

```powershell
node setup.js --project "C:\path\to\the\project\you\want\to\work\on"
```

This:

- finds the WoW: Forever client (it looks under `Program Files (x86)\World of Warcraft\_classic_beta_` and a few other common places; pass `--wow "D:\Games\World of Warcraft\_classic_beta_"` if it can't find yours),
- copies the addon into `Interface\AddOns\WoWGrok`,
- writes `bridge\config.json` with your paths, the project folder, and `capture.processName` from the `Wow*.exe` it finds,
- creates the 200 reply-slot addons and about 15,000 tiny signal files next to it. That count is normal: the client only discovers addon files when it launches, so everything the bridge might ever touch has to exist up front.

`--project` is the fallback folder for chats. Once the `wow-grok` command is installed (step 5) you'll usually pick the folder by where you start the bridge instead.

If you have several WoW accounts, setup picks the first and says so; pass `--account <name>` to choose.

Now **fully quit and relaunch World of Warcraft** (a `/reload` is not enough, the new files have to be there at launch). On the character screen, open **AddOns** and make sure *WoW Grok* is enabled. The 200 *WoW Grok slot* entries stay enabled too; leave them alone.

## 4. First run

From the `wow-grok` folder:

```powershell
npm start
```

You should see a banner like:

```
WoW Grok bridge
  folder   : C:\path\to\your\project  (config.json; chats can override with /wow-grok cd)
  addons   : C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns
  slots    : 200 installed
  capture  : on (capture.ps1, WowB, 200x48 cells of 4px)
  model    : grok-4-latest
  api key  : env XAI_API_KEY
  ...
```

In the game, type `/wow-grok`. The window opens; the light in its corner should turn green within about ten seconds. Type something in the box and press Enter. The reply arrives with the whisper sound.

If the light stays red, see [Troubleshooting](#troubleshooting).

## 5. Install the `wow-grok` command

The bridge works in the folder you start it from. To be able to type `wow-grok` from any folder, install it once from inside the repo:

```powershell
cd C:\Users\<you>\Documents\wow-grok
npm link
```

`npm link` puts a `wow-grok` launcher into npm's global folder (`%AppData%\npm`, already on your `PATH` since Node was installed) that points back at this repo. Nothing is copied: pulling a newer version of the repo updates the command, and `bridge\config.json` stays where `setup.js` wrote it.

> Don't use `npm install -g .` instead. That copies the files into npm's global folder, where there is no `config.json`, and the bridge refuses to start.

Check it:

```powershell
wow-grok --help
```

Then use it from any project:

```powershell
cd C:\path\to\realms
wow-grok
```

The banner's `folder` line now says `started here`, and every chat that hasn't chosen its own folder with `/wow-grok cd` works in `realms`. `wow-grok --project <dir>` names the folder explicitly. Only one bridge can run at a time (two would fight over the screen and the slot files), so this sets the default folder rather than running one bridge per project.

Leave the window open while you play. Ctrl+C stops it. It restarts itself if it ever crashes. `bridge\start-window.cmd` is the double-click version that opens its own window.

### Updating

```powershell
cd C:\Users\<you>\Documents\wow-grok
git pull
node setup.js        # re-copies the addon; keeps your config.json and the slot pool
```

Then `/reload` in game and restart the bridge. If `setup.js` reports that it created new files, quit and relaunch the game instead of `/reload`.

### Uninstalling

```powershell
npm unlink -g wow-grok      # removes the command
```

Delete `Interface\AddOns\WoWGrok` and the `WoWGrok_S001` … `WoWGrok_S200` folders next to it, and the `wow-grok` folder. Your chats' saved data is in `WTF\Account\<account>\SavedVariables\WoWGrok.lua`.

## Troubleshooting

**`wow-grok` is not recognized.** Open a new terminal; `npm link` needs `%AppData%\npm` on the `PATH`, which the Node installer sets up but an already-open terminal doesn't see. Check with `npm prefix -g`: that folder must be in `$env:Path`.

**PowerShell says "running scripts is disabled on this system".** npm creates three launchers (`wow-grok`, `wow-grok.cmd`, `wow-grok.ps1`) and PowerShell prefers the `.ps1` one, which a *Restricted* execution policy blocks. Either allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

or type `wow-grok.cmd` instead, which bypasses the policy.

**"Cannot read config.json … Run node setup.js".** The command is pointing at a copy of the repo that hasn't been set up (usually `npm install -g .` was used instead of `npm link`, or the repo folder was moved). Run `npm link` again from the repo folder you set up.

**The banner says `slots : NOT INSTALLED`.** `setup.js` couldn't write into the AddOns folder, or it wrote somewhere else. Check `addonDir` in `bridge\config.json`, then run `node bridge\install-slots.js` and relaunch the game.

**Missing xAI API key / banner `api key : MISSING`.** Set `$env:XAI_API_KEY = "xai-..."` in the same terminal as `npm start`, or put the key in `"apiKey"` in `bridge\config.json` (that file is gitignored). Get a key at [console.x.ai](https://console.x.ai/).

**The light stays red / "no sign of the bridge".** The bridge can't see the strip in the top-left corner of the game window. In order of likelihood: the game is in exclusive fullscreen (switch to windowed or borderless); the game window is minimized or on a monitor the bridge can't capture; `capture.processName` in the config doesn't match your game exe (`WowB` for Forever; `setup.js` sets it from the exe it finds). `bridge\bridge.log` prints `attached to '...'` when it finds the window and `strip #N` when it decodes a message.

**Windows Defender or another antivirus complains about the slot files.** They are 15,000 empty or 124-byte files; nothing runs from them. Exclude `Interface\AddOns` if the scanner slows the bridge's writes down.

**Everything else** is in the README's Troubleshooting section and in `/wow-grok diag` in game.
