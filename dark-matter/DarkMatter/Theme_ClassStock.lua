-- 0.5.1.3: the class themes draw the game's own buttons, tabs and scroll bars too (UIPanelButtonTemplate's faces, the
-- character-frame tabs, the UI-ScrollBar buttons, knob and groove), the same files the WoW theme uses, desaturated and
-- recoloured in each theme's palette (Stock.Recolor). Hand-picked here (Theme_Classes.lua is generated); the labels
-- keep each theme's own button ink (Widgets StockInk). Every other part of a class theme (frame art, crest, ornaments,
-- surfaces, hover edge, its colours) is unchanged.
--   face: Up face   down: Pushed face   disabled: Disabled face   tab / tabOn: section tab (unselected / selected)
--   hl: the hover glow (ADD)   sb: scroll bar buttons, knob and groove
local _, NS = ...

local GREY = { 0.58, 0.58, 0.58 }
local TINT = {
  warrior = { face = { 1, 0.5, 0.42 }, down = { 0.78, 0.36, 0.3 }, tab = { 0.8, 0.8, 0.86 }, tabOn = { 1, 0.86, 0.62 },
    hl = { 1, 0.78, 0.55 }, sb = { 0.85, 0.85, 0.9 } },
  paladin = { face = { 0.9, 0.76, 0.44 }, down = { 0.72, 0.6, 0.32 }, tab = { 1, 0.92, 0.74 }, tabOn = { 1, 0.95, 0.8 },
    hl = { 0.9, 0.8, 0.55 }, sb = { 1, 0.9, 0.7 } },
  -- hunter: green faces, brown tabs and bars (leather and leaf)
  hunter = { face = { 0.62, 0.86, 0.4 }, down = { 0.46, 0.66, 0.28 }, tab = { 0.9, 0.7, 0.46 }, tabOn = { 1, 0.84, 0.58 },
    hl = { 0.85, 1, 0.6 }, sb = { 0.92, 0.74, 0.5 } },
  rogue = { face = { 0.66, 0.66, 0.72 }, down = { 0.5, 0.5, 0.56 }, tab = { 0.62, 0.62, 0.68 }, tabOn = { 0.95, 0.84, 0.52 },
    hl = { 1, 0.86, 0.5 }, sb = { 0.7, 0.7, 0.76 } },
  priest = { face = { 0.86, 0.83, 0.75 }, down = { 0.72, 0.68, 0.58 }, tab = { 1, 0.98, 0.92 }, tabOn = { 1, 0.92, 0.7 },
    hl = { 0.9, 0.86, 0.7 }, sb = { 1, 0.96, 0.86 } },
  shaman = { face = { 0.34, 0.9, 0.9 }, down = { 0.24, 0.68, 0.7 }, tab = { 0.66, 0.78, 0.86 }, tabOn = { 0.6, 1, 0.96 },
    hl = { 0.6, 1, 1 }, sb = { 0.6, 0.86, 0.9 } },
  mage = { face = { 0.5, 0.7, 1 }, down = { 0.36, 0.52, 0.86 }, tab = { 0.6, 0.74, 1 }, tabOn = { 0.8, 0.9, 1 },
    hl = { 0.7, 0.85, 1 }, sb = { 0.62, 0.76, 1 } },
  warlock = { face = { 0.76, 0.5, 1 }, down = { 0.56, 0.36, 0.82 }, tab = { 0.8, 0.72, 0.6 }, tabOn = { 0.9, 0.78, 1 },
    hl = { 0.86, 0.7, 1 }, sb = { 0.78, 0.66, 0.9 } },
  -- druid: leaf-green faces, bark-brown tabs and bars
  druid = { face = { 0.6, 0.9, 0.38 }, down = { 0.44, 0.7, 0.26 }, tab = { 0.9, 0.7, 0.44 }, tabOn = { 1, 0.86, 0.56 },
    hl = { 0.85, 1, 0.6 }, sb = { 0.9, 0.72, 0.48 } },
}

for id, t in pairs(TINT) do
  local def = NS.themes[id]
  if def then
    t.disabled = t.disabled or GREY
    def.stockTint = t
  end
end
NS.CLASS_STOCK_TINT = TINT
