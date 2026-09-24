# Configuration reference

Everything the bridge reads: `bridge/config.json`, command-line flags, environment variables, and the files it writes next to itself. `node setup.js` writes a working `config.json` from `bridge/config.example.json`; this page explains each key so you can tune it by hand.

The bridge reads `config.json` once at start. Restart it after editing. `allowedTools` is ignored (Grok API chat has no local tool allowlist).

Windows example paths are in `config.example.json`. On macOS they look like `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns`.

## Paths

| Key | Default (from `config.example.json`) | Meaning |
|---|---|---|
| `addonDir` | `…\World of Warcraft\_classic_beta_\Interface\AddOns` | The game's AddOns folder. The bridge writes the slot addons, `Inbox.lua` and every signal file under it. `setup.js` fills this in from the client it finds. |
| `inboxFile` | `<addonDir>\WoWGrok\Inbox.lua` | The file the game reads on `/reload` (fallback path). Normally derived from `addonDir`; only change it if you moved the addon. |
| `savedVariablesFile` | `…\WTF\Account\<account>\SavedVariables\WoWGrok.lua` | The addon's saved data. The bridge polls it for the reload-path outbox. `setup.js` picks the first account under `WTF\Account`; pass `--account <name>` to choose another. |
| `defaultCwd` | `C:\path\to\your\project` | Folder for chats that have not chosen one with `/wow-grok cd`, when the bridge is started from inside this repo (`npm start`). See [Which folder a chat uses](#which-folder-a-chat-uses). |

## xAI Grok API

| Key | Default | Meaning |
|---|---|---|
| `apiKey` | `""` | xAI API key. Prefer the `XAI_API_KEY` environment variable so the key never sits in a file. Never commit a real key (`bridge/config.json` is gitignored). |
| `model` | `"grok-4-latest"` | Model id sent to `POST /v1/responses`. `grok-4`, `grok-4-latest`, `grok-4.6` and other xAI chat model ids are valid. |
| `apiBase` | `"https://api.x.ai/v1"` | API origin. The bridge posts to `{apiBase}/responses`. |
| `maxParallel` | `3` | How many chats may call Grok at the same time. Further messages queue per chat. |
| `timeoutMs` | `1800000` (30 min) | A request longer than this is aborted and reported as an error in game. |
| `progressWriteMs` | `3000` | Minimum gap between progress writes to the slot files. Final replies are written immediately. |
| `pollMs` | `750` | How often the bridge checks the SavedVariables file for a reload-path message. |
| `allowedTools` | `[]` | Ignored. Left as an empty array so older configs still parse. The in-game Allow button is a no-op. |

Auth is `process.env.XAI_API_KEY || cfg.apiKey`. The key is never logged; the banner only prints the source (`env XAI_API_KEY` vs `config.json`).

Multi-turn uses `previous_response_id` from `state.sessions`. If the server rejects that id, the bridge retries once with the local `state.history` turns instead.

## Screen capture

Keys under `capture`:

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Run `capture.ps1` on Windows or experimental `capture-mac.js` on macOS. With `false` only the reload path works (`/wow-grok mode reload` in game). |
| `processName` | `"WowB"` | Windows: game executable without `.exe`. macOS: app / process name (`World of Warcraft` or `WowB`). `setup.js` sets it from the client it finds. |
| `cellPx` | `4` | Pixel size of one strip cell. Must match `CELL` in `addon/WoWGrok/Codec.lua`. On Retina Macs, capture samples at `cellPx * backingScaleFactor`. |
| `cellsPerRow` | `200` | Cells per strip row. Must match the addon. |
| `maxRows` | `48` | Maximum strip rows captured. Must match the addon. |
| `intervalMs` | `250` | Capture period. Lower is more responsive and costs a little more CPU. |

The capture region is `cellsPerRow × cellPx` by `maxRows × cellPx` points (800 × 192 by default) at the top-left of the game window.

## Slot pool and signal files

These sizes are baked into the files `install-slots.js` creates, and the addon has matching constants at the top of `addon/WoWGrok/WoWGrok.lua` (`SLOT_COUNT`, `ACT_MAX`, `PRESENCE_MAX`). Change all three places together, re-run `node bridge/install-slots.js`, and restart the game.

| Key | Default | Meaning |
|---|---|---|
| `slots` | `200` | Reply-slot addons `WoWGrok_S001` … `WoWGrok_S200`. Each slot can be loaded once per UI session; `/reload` frees them all. |
| `actMax` | `60` | Heartbeat files per message (`act/NNN/01..60.wav`). One flips per progress beat. |
| `presenceMax` | `2000` | Presence files (`presence/0001..2000.wav`). One flips per `presenceIntervalMs`. |
| `presenceIntervalMs` | `30000` | How often the bridge flips a presence file so the in-game light stays green. |
| `tocInterface` | `"16001"` | `## Interface:` version written into every slot addon's `.toc`. Bump it when the client's TOC version changes. |

## Command line

`wow-grok` (after `npm link`) and `node bridge/bridge.js` take the same flags. `npm start` runs `bridge/supervisor.js`, which restarts the bridge on crash and passes flags through.

| Flag | Meaning |
|---|---|
| `--project <dir>` | Default working folder for this run. Overrides everything else. |
| `--once` | Handle one pending reload-path message and exit. |
| `--inject "<text>"` | Pretend the strip said this, call Grok, publish the result, exit. Handy for checking a setup without the game. Needs `XAI_API_KEY`. |
| `--help`, `-h` | Print usage. |

Exit codes: `0` normal, `1` the injected or one-shot job failed, `2` config missing or unreadable. The supervisor only restarts on codes other than `0` and `2`.

## Environment

| Variable | Meaning |
|---|---|
| `XAI_API_KEY` | xAI API key. Wins over `config.json` `apiKey`. |
| `WOW_GROK_PROJECT` | Default working folder, below `--project` and above the start folder in precedence. |

## Which folder a chat uses

Each chat can pick its own folder with `/wow-grok cd` or **Folder...** in the menu that opens when you right-click the chat in the left panel. Chats that have not are given the bridge's default folder, chosen in this order:

1. `--project <dir>`
2. `WOW_GROK_PROJECT`
3. The folder the bridge was started from, unless that is inside this repo
4. `defaultCwd` in `config.json`
5. The current folder

A relative `/wow-grok cd` path is resolved against that default. `~` expands to your home folder. Changing folder starts a fresh Grok conversation (`previous_response_id` is cleared). The Grok API cannot read that folder; the path is a label shown in game and mentioned in the system prompt.

## Files the bridge writes next to itself

All of these are gitignored.

| File | Contents |
|---|---|
| `bridge/config.json` | Your configuration. May contain `apiKey` — never commit it. |
| `bridge/state.json` | xAI response ids per chat, local history fallback, the folder each conversation ran in, handled message ids per addon session token, and the presence counter. Delete it to forget all conversations. |
| `bridge/transcripts.json` | The last 200 messages of every chat, so the addon can recover its chats after the client wipes saved data. |
| `bridge/bridge.log` | Everything printed to the console, with timestamps. Grows without bound; delete it whenever you like. |

## `setup.js` flags

| Flag | Meaning |
|---|---|
| `--wow "<client folder>"` | The flavor folder containing `Interface/` (and `Wow*.exe` on Windows, or a WoW `.app` on Mac), when auto-detection fails. |
| `--project "<dir>"` | Written to `defaultCwd`. Defaults to the folder you ran setup from. |
| `--account <name>` | Which `WTF/Account/<name>` to use when there are several. |

Re-running `setup.js` re-copies the addon (except `Inbox.lua`, which the bridge owns once running), keeps an existing `config.json`, and only creates slot and signal files that are missing.
