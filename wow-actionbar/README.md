# WoW Action Bar

Forever addon in `wow-actionbar/WoWActionBar`. It fills **empty** Blizzard action-bar slots once, grouped by category. It does not replace the bar UI and does not move spells you already placed. Drag stays the normal action-bar drag.

Not part of WoWGrok.

## What it places

1. Healing spells
2. Other instants
3. Cast-time spells
4. Food and drink (items in your bags, plus Conjure Food / Conjure Water)

One empty slot is left between groups (changeable, 0–3). The two side bars stay off unless you turn them on. After the first pass it locks so it will not reshuffle.

## Settings

A **WA** button sits at the right of the main bar. `/wa` opens the same panel. You can change group order, the gap, which bars it may touch, and the lock. Unlock, then **Organize now** or `/wa organize`. It still only fills empty slots.

## Install

Copy `wow-actionbar/WoWActionBar` to:

`Interface/AddOns/WoWActionBar`

Then `/reload`. Built for Interface `16001`.
