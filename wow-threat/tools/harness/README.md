# WoWThreat stub harness (box only)

Lua 5.1 stubs of the WoW API, run with lupa. Not shipped in the addon.

    python run.py h140.lua ../../WoWThreat            # main checks (MODE=proxy default; MODE=old also supported)
    MODE=canvas python run.py hcanvas.lua ../../WoWThreat   # the canvas Options panel's Theme cycler

`h140.lua` is the 1.3.0 harness plus the 1.4.0 section (WoW theme, migration, /wtm artprobe, fallback).
