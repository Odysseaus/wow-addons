# wow-grok — CoS summary

**Repo:** `/home/box/agent-data/workspaces/wow-grok`  
(symlink of `/home/box/sand-data/workspaces/wow-grok`)

Fork of MIT [wow-claude](https://github.com/chelinho139/wow-claude) by chelinho139. Rebranded to **WoWGrok** / `wow-grok` and switched the companion from the Claude Code CLI to the **xAI Grok API**. Windows capture preserved; experimental macOS capture added.

This is **Grok API model chat**, not Grok Bot, and not Claude.

## Done

| Area | What |
|------|------|
| Addon | `addon/WoWGrok/` — globals `WoWGrok*` / `WoWGrokDB` (no collision with WoWClaude). Slash `/wow-grok`, `/grok`, `/ai`, `/ask`. |
| Backend | `bridge/xai.js` → `POST https://api.x.ai/v1/responses`. Auth `XAI_API_KEY` or `config.apiKey` (never committed). Default model `grok-4-latest`. Multi-turn via `previous_response_id` + local history fallback. |
| Bridge | `bridge/bridge.js` calls `xai.chat` (no `claude` spawn). Allow-rules UI stubbed as no-op. Slot/publish/signal path unchanged. |
| Windows capture | `bridge/capture.ps1` kept. |
| macOS capture | `bridge/capture-mac.js` (experimental): AppleScript bounds + `screencapture`, Retina scale handled in sampling. |
| Setup | `setup.js` discovers Forever/classic_beta AddOns on Win and Mac; `--wow <path>` override. |
| Docs | README (Win+Mac), `docs/INSTALL-WINDOWS.md`, `docs/INSTALL-MAC.md`, `docs/CONFIGURATION.md`, `docs/ARCHITECTURE.md`. Attribution + MIT preserved. |
| Tests | `npm test` — 30/30 unit + codec round-trip PASS on this box (no live API/game). |

## How to run setup

**Windows (PowerShell):**
```powershell
cd path\to\wow-grok
$env:XAI_API_KEY = "xai-..."
node setup.js --project "C:\path\to\project"
# optional: --wow "C:\Program Files (x86)\World of Warcraft\_classic_beta_"
npm start
```

**macOS:**
```bash
cd path/to/wow-grok
export XAI_API_KEY="xai-..."
node setup.js --project "$HOME/path/to/project"
# optional: --wow "$HOME/Applications/World of Warcraft/_classic_beta_"
npm start
```

Then fully quit/relaunch WoW, enable **WoW Grok**, `/wow-grok` in game.

## Left (manual / live)

1. Live Forever test on Odysseaus’s Mac and/or Windows (pixel strip decode, slot replies, presence).
2. Real `XAI_API_KEY` for `npm run test:live` / in-game chat.
3. macOS Screen Recording permission + Retina windowed/borderless at 100% UI scale validation.
4. Confirm Forever TOC (`## Interface: 16001` in toc) matches the installed client; bump if Blizzard moved on.
5. Confirm capture `processName` (`WowB` vs `World of Warcraft` / Forever app name) on the machine in use.

## Blockers

- **No API key in this environment** — cannot call api.x.ai here.
- **No WoW client on the box** — capture and end-to-end untested live.
- **macOS capture experimental** — scale math implemented, not proven in-game.
- **Forever TOC / install layout** may differ from defaults; use `--wow`.

## Python rewrite scaffold (2026-09-24)

Milestone: `bridge_py/` package alongside Node bridge. First-run tkinter API key + AddOns picker, protocol/xai ports, supervisor, capture stubs, INSTALL-USERS + packaging docs, unit tests (16). No `gh` publish yet — ready for scrub then public repo **wow-grok** under Odysseaus’s GitHub. Node README kept until cutover (`README.python.md` + `docs/INSTALL-USERS.md`).

