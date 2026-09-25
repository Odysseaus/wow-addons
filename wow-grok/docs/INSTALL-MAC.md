# Install on Mac (players)

Use the packaged **`.dmg`** (drag **WoWGrok.app** to the Applications shortcut) or the `.app` zip — no Node.js, npm, or Python required.

After first-run, WoWGrok lives in the **menu bar** (quiet companion). Leave it running while you play; Quit from the menu (exits menu bar + bridge + capture).

Full player steps: [INSTALL-USERS.md](INSTALL-USERS.md).

## First install — Screen Recording

Grant **Screen Recording** to the app under System Settings → Privacy & Security → Screen Recording. First launch may prompt and must list **WoWGrok** in that Settings pane; enable it, then **Quit and reopen** from Applications.

## Upgrading / replacing WoWGrok.app (required)

macOS treats each new unsigned binary as a **different identity**. After you replace `/Applications/WoWGrok.app` from a new DMG:

1. **Quit** WoWGrok fully (menu-bar Quit).
2. Replace the app from the DMG (drag onto Applications).
3. **Screen Recording — remove and re-add** (do **not** rely on Leave Enabled alone):
   - Open **System Settings → Privacy & Security → Screen Recording** (or Screen & System Audio Recording).
   - Select **WoWGrok** → remove it (− / trash), or turn it **off** and remove the row if the UI allows.
   - Launch the new **WoWGrok.app** once so it requests access again (or use **+** to add it).
   - Turn **WoWGrok** **ON** for the new binary.
   - Quit and reopen WoWGrok from Applications so the grant sticks.
4. Only then: Forever `/reload` (if the AddOn version bumped) → Connect → smoke Send.

Skipping step 3 often leaves capture broken even though the toggle still looks enabled.

Developers / from source: [DEV.md](DEV.md).
