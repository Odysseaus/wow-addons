# WoWGrok 0.1.18 (box tree)

## What changed
- **capture_mac:** `find_wow_window` returns `id` (kCGWindowNumber). Live strip uses in-process `CGWindowListCreateImage` (IncludingWindow) first; `screencapture -R` is fallback. Exit 42 only when both CG and CLI fail permission-class. `resume_smoke_ok` smokes a CG ≥64×64 of the WoW window (not desktop CLI). Optional per-window backing scale.
- **bridge:** slow ~45s resume watcher clears `permissionPaused` after smoke, republishes without `capturePaused`, spawns capture once. Probe=granted still never clears pause alone.
- **addon:** `NoteCaptureResumed` clears `run.capturePaused` when Inbox/slots omit the flag. Send stays pixel (no ReloadUI) when capture is healthy.
- Versions: pyproject, `__init__`, toc, `build_mac.spec`, CHANGELOG → **0.1.18**.

## Verify
```bash
cd /home/box/agent-data/workspaces/wow-grok
python -m unittest discover -s bridge_py/tests -v
```
Do not push/release from this tree; Macbook Helper ships after PR-ready review.
