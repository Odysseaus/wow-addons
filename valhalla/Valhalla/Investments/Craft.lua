--------------------------------------------------------------------------------
-- AH Market > Craft (v0.4.1): Top 10 profitable crafts per profession. Registered in the TOC with v0.4.0
-- (the one restart), so v0.4.1 installs with a /reload. Empty until then.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("invest")
local I = mod and mod.I
if I then I.Craft = I.Craft or { ready = false } end
