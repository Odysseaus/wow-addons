# Changelog

All notable changes to this project are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Bridge talks to the xAI Grok API (`POST /v1/responses`, default model `grok-4-latest`) instead of spawning the Claude Code CLI. Conversations use `previous_response_id` with a local history fallback.
- macOS support: `setup.js` finds the client under `/Applications` and `~/Applications`; experimental `bridge/capture-mac.js` captures the pixel strip (Screen Recording, Retina).
- `claudePath` / `permissionMode` removed. `allowedTools` is an ignored empty array. The in-game Allow button is a no-op (Grok API chat has no local tool allowlist).
- Requires Node 20+ (`fetch`). Auth is `XAI_API_KEY` or `config.json` `apiKey`.
- Rename and Folder moved off the bottom row into a small menu that opens when you right-click a chat in the left panel.
- Each chat row has a trash can that deletes the chat after an OK/Cancel confirm; `/wow-grok delete` still deletes without asking.
- Send sits at the right end of the input box instead of at the left of the bottom row.
- The bridge no longer exits when the addon folder is missing from `Interface\AddOns`; it logs one warning and the banner shows `addon : NOT INSTALLED`.

### Fixed

- Deleting a chat in game now tells the bridge to forget its transcript and Grok conversation (a `d` strip record), so a later restore no longer brings the chat back. Deletions made while the bridge was away are resent with the next hello.
- On clients where the sound-file self-test fails (an empty `.wav` reports as playable), the addon can't hear the bridge's 30-second presence beats, and the status light went yellow 90 s after every reply, so each new message needed a Reconnect click and burned a slot. In that mode the light now allows for the 10-minute idle slot poll (green up to 12 min without news, "down" after 22), so it stays green while the bridge is running.
- A message sent while the light is not green is now sent automatically once the bridge answers the reconnect, instead of waiting for a second click on Send.

## [0.1.22] - 2026-09-24

### Product pin (Mac)

- **Product 0.1.22** = **AddOn 0.1.22** (version title/footer + shift-click TakeLink/ExpandLinks) + **app/bridge capture stack from wow-grok-mac-v0.1.19** (CG strip / `screencapture -l` / permissionPaused resume).
- **NOT** the broken **0.1.20 / 0.1.21** Mac app builds. Reinstalling this DMG does **not** bring back 0.1.21 rect-capture.

### Added

- Panel title + footer show AddOn version via `GetAddOnMetadata` / `C_AddOns.GetAddOnMetadata` (e.g. `WoW Grok v0.1.22`).
- Shift-click **TakeLink** / **ExpandLinks**: InsertLink hooks (frame shown) + debounce; on Send, links become `[Name]` plus a "Linked from the game" tooltip block.

### Changed

- Branch cut from **wow-grok-mac-v0.1.19** (known-good capture). AddOn replaced with live-patched 0.1.22 (pure 0.1.13 strip/Send/Codec/`SetScale(768/physH)` + version + links).
- Bridge `__init__` / pyproject / `build_mac.spec` CFBundle / workflow Info.plist inject → **0.1.22** so the DMG is clearly 0.1.22 while capture code remains the 0.1.19 stack.
- **Supersedes** broken Mac apps **0.1.20** and **0.1.21**.

### Notes

- Keeps 0.1.13 pixel Send path, 7-field RecordFor (no ctx), and strip `SetScale(768 / physH)`.
- **Not included:** `GameContext` / `ContextToSend` / RecordFor ctx / hello ctx / `/wow-grok context` / SafeReload-on-Send / loadfile Inbox / SetScale(1) / capturePaused chat UX from 0.1.14–0.1.21.

## [0.1.19] - 2026-09-24

### Fixed
- **Lua forward-decl:** `UseReloadTransport` declared before `ArmAutoRefresh` (nil@245 / classic local-before-def).
- **Product lock — Send never ReloadUI:** Send always queues SV outbox + pixel outbound/RefreshStrip; status hints Reload when capture paused. `ArmAutoRefresh` / keyCatcher no longer auto-`ReloadUI`. Reload button, `/wow-grok reload`, and combat-deferred reload remain.
- **SayHello under capturePaused:** still paints pixel hello for restore (does not early-return solely on `UseReloadTransport` when only paused).
- **No loadfile/loadstring:** `PullInboxFromDisk` is a no-op (Forever has no `loadfile` — calling it nil-crashed Tick). Mid-session replies = `TryLoadSlot` only.
- **Connect + grey light while capturePaused:** Connect sets `wantConnectSlot`; Tick polls slots every 2s when paused and `bridgeSeen` is nil; `IsConnected` requires `bridgeSeen` when paused so Connect stays clickable.
- **Connect + grey light while capturePaused:** Connect still sets `wantConnectSlot` (does not early-return without a slot poll); Tick polls slots every 2s when paused and `bridgeSeen` is nil so presence/Inbox/slots mark the bridge without ReloadUI.
- **Inbox without ReloadUI:** `PullInboxFromDisk` in `ProcessInbox`; Tick re-pulls every 2s while pending so capture-paused replies land without thrashing Reload.
- **Reload button:** shown only in explicit reload mode (hidden in pixel / capturePaused). Send status no longer nags "press Reload".
- **Visible addon version:** panel title + cwd line show `GetAddOnMetadata` Version.
- **Mac capture strategies:** CG strip → CG full-window + Pillow crop → **`screencapture -l` window id + crop** (preferred for fullscreen/ultrawide) → `screencapture -R` last. Soften exit 42 until strategies exhausted with permission-class failures. Resume smoke returns/logs failure reason; bridge logs it each attempt.
- **Window match:** owner exact `Wow` (id from JXA) recognized.

### Carry-forward
- NoteCaptureResumed / permissionPaused persist / Connect presence from 0.1.16–0.1.18.

## [0.1.18] - 2026-09-24

### Fixed
- **Pixel Send restored (no ReloadUI on healthy path):** live mac capture prefers in-process `CGWindowListCreateImage` for the WoW window strip (by `kCGWindowNumber`); `screencapture -R` is fallback only. Exit 42 only when both CG and CLI fail permission-class errors — CLI `could not create image from rect` alone no longer permanent-pauses when CG was not tried or CG works.
- **Resume smoke matches live path:** `resume_smoke_ok` CG-captures ≥64×64 of the WoW window (not desktop screencapture). Bridge slow resume watcher (~45s) clears `permissionPaused`, republishes without `capturePaused`, and spawns capture once smoke passes. Probe=granted still never clears pause alone.
- **Addon:** `NoteCaptureResumed` clears `run.capturePaused` when Inbox/slot data omits `capturePaused`, so Send returns to the pixel strip without ReloadUI/Reload button.

### Carry-forward
- 0.1.17 reload-transport UX while truly paused; Connect/presence without capture; TCC pause persist.

## [0.1.17] - 2026-09-24

### Fixed
- **Auto reload/SV when capture paused:** bridge advertises `capturePaused` in Inbox/slots; addon uses reload transport for Send without a manual mode flip. Capture does not spawn while `permissionPaused`; resume requires a real capture smoke (probe=granted alone never clears pause).
- **Stuck pending after successful bridge job:** ApplyReplies recovers `pendingId` from outbox/`pendingBackup`; already-handled outbox jobs re-publish the transcript reply to Inbox; login re-queues outbox when `pendingId` disagrees with outbox id.
- **Reload-mode Send no longer feels like bare /reload:** on Send while pending, ProcessInbox first (clears when Inbox already done); new typed text cancels stuck pending and sends. Connect in reload/capture-paused marks presence (does not only SafeReload).
- **UX:** clearer status after send-reload; shorter auto-refresh interval (max 8s) on reload transport so the second Refresh is prompt.

### Carry-forward
- Connect/presence from 0.1.16; TCC exit 42 + permissionPaused persist from 0.1.15/0.1.16.

## [0.1.16] - 2026-09-24

### Fixed

- **Persist capture pause:** on capture exit 42, save `capture.permissionPaused=true` so the next launch never spawns capture (stops the system Screen Recording sheet when Forever appears). Clear the flag in `config.json` after enabling Screen Recording, then Quit and reopen. First-run skips the CG probe/request while paused (does not clear on probe=granted).
- **Connect hardening:** SelfTest falls back to `presence/0001` when ctl files are not sound-indexed; Connect sets `wantConnectSlot` so Tick polls a reply slot even when presence sound-index fails or pixel Hello is dead.

### Changed

- Still includes 0.1.15 TCC exit-42 treatment and presence-without-capture.

## [0.1.15] - 2026-09-24

### Fixed

- **Capture TCC spam:** `screencapture` failures such as `could not create image from rect`, empty capture, and permission-denied strings now exit capture with code 42 (permanent Screen Recording failure) instead of sleep-and-retry. The bridge still does not restart capture on 42, which stops macOS "Open System Settings / Deny" loops after an unsigned app replace.
- **First-run probe:** when `screenRecordingOnboarded` is set, probe at most once and do not call `request_screen_recording` again every launch.
- **Connect without capture:** presence beats keep running when capture is paused (exit 42), so Connect works via SavedVariables without the pixel path.
- **Mac Info.plist version:** release workflow injects `CFBundleShortVersionString` / `CFBundleVersion` from the tag (0.1.14 zips still said 0.1.13).

### Changed

- Capture flap restart backoff doubles up to 60s for non-permission exits.

## [0.1.14] - 2026-09-24

### Added

- **Game context:** the addon sends plain-text lines (Game / Character / Location / Position / Money / XP / Talents / Professions) with hello and again when the text changes. The bridge stores them in `state.json` and injects them into xAI `instructions` on every turn (including multi-turn). `/wow-grok context [on|off]` (alias `ctx`); config `gameContext` (default `true`).
- **Shift-click link expansion:** with the WoWGrok input focused, shift-click inserts item/spell/quest links (`ChatFrameUtil.InsertLink`, fallback `ChatEdit_InsertLink`). On send (panel or `/ai`/`/grok`), links become `[Name]` plus a "Linked from the game" tooltip block.

### Fixed

- xAI multi-turn: `instructions` (game context) are now sent together with `previous_response_id`, so context no longer drops after the first reply.

## [0.3.0] - 2026-09-22

First public release.

### Added

- In-game chat window (`/wow-grok`) with multiple chats, each backed by its own persistent Claude Code session, running in parallel up to `maxParallel`.
- Outbound transport: messages drawn as a pixel strip in the top-left corner and decoded by a PowerShell screen capture.
- Inbound transport: a pool of 200 load-on-demand slot addons the bridge writes replies into, plus `Inbox.lua` for the `/reload` fallback.
- Empty-wav signal files for acknowledgements, reply readiness, per-action heartbeats, and a 30-second presence beat that drives the status light.
- Live progress in the working bubble: action count, elapsed time, and the files and commands Claude is touching.
- Replies echoed into the game chat; `/r` replies to Claude when it was the last to message you; `/ai <text>` sends from the chat box.
- **Allow & retry** button when Claude is denied a tool, which appends the rule to `allowedTools` and resumes.
- Per-chat working folder (`/wow-grok cd`, **Folder** button) resolved against the bridge's default folder.
- Bridge-side transcripts and automatic restore of chats after the client wipes addon saved data.
- `wow-grok` command (`npm link`) that uses the folder it is started from as the default project.
- `setup.js` installer: finds the client, copies the addon, writes `config.json`, builds the slot pool.
- Test suite: addon in a Lua VM with a stub client, protocol unit tests, slot-file round trip, codec-to-decoder round trip, and a live inject test.

[Unreleased]: https://github.com/chelinho139/wow-grok/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/chelinho139/wow-grok/releases/tag/v0.3.0
