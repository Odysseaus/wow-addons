# WoWGrok 0.1.23 (Mac product pin)

- **Product 0.1.23** = AddOn **0.1.23** (ambient GameContext + version + shift-click links) + **capture from 0.1.19** (same as 0.1.22 — CG strip / screencapture -l). **Not** the broken 0.1.20/0.1.21 rect-capture apps.
- GameContext: zone/instance/quest/party-ish, cap ~650; always SV outbox; strip attaches ctx only if it fits; hello has **no** ctx; never drops user text.
- Codec/Inbox/SetScale/pixel Send unchanged from **0.1.22**. Capture md5 `b7539598…` (tag `wow-grok-mac-v0.1.19`).
- Versions: pyproject, `__init__`, toc, `build_mac.spec`, CHANGELOG, Info.plist inject → **0.1.23**.
- Branch base: `wow-grok-mac-v0.1.22` / 0.1.19 capture lineage. Supersedes Mac 0.1.20 / 0.1.21 apps.
