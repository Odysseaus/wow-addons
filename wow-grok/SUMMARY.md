# WoWGrok 0.1.26 (Mac + Windows product pin)

- **Product 0.1.26** = app/bridge **0.1.26** + AddOn **0.1.26**; capture unchanged (md5 `b75395986a768269a8f4ae5594709159`).
- **Stuck pending / multi-chat Inbox:** hello + already-handled re-serve recent transcript replies for all chats; `live_put` LRU so one chat cannot push another out of the published set; ApplyReplies accepts done/error by chat when id drifted.
- **Windows 0.1.26** ship: same multi-chat fix as Mac; tray (`tray_win` / Running + Quit) + GHA `WoWGrok.exe` (`wow-grok-win-v0.1.26`); SSL/`--ssl-smoke`.
- Default `timeoutMs`: **300000** (5m). Tools: `webSearch: true`, `xSearch: false`.
- Branch base: `mac/v0.1.26-stuck-pending-inbox` (5b49255).
