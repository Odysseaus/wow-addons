-- 0.5.2b.20: hand-tuned crest size / vertical seat for class themes.
-- Theme_Classes.lua is GENERATED (tools/themes/make_class_textures.py) — do not put lasting crest tweaks there.
-- This file is the documented override table: { size, x, y }. x is ignored by Window.lua (crest is centred);
-- only size and y are applied. Adjust here, then /reload. Illusionist re-export comes later if art is still off.
-- Apply() runs BEFORE SetTheme's skins. A wrap that paints first and then writes the table leaves the frame
-- on the generated seat until the next switch (0.5.2b.19 did that).
local _, NS = ...

-- before 0.5.2b.19 (from Theme_Classes.lua):
--   hunter  crest = { 104, 0, -48 }
--   paladin crest = { 92, -168, -12 }
-- 0.5.2b.19 was { 96, 0, -30 } and { 90, 0, -28 } — only a few pixels, easy to miss.
-- 0.5.2b.20: clearly smaller, and up toward warrior's seat (warrior crest y is -26).
NS.CrestOverrides = {
  hunter  = { 88, 0, -22 },
  paladin = { 84, 0, -22 },
}

local function Apply()
  for id, crest in pairs(NS.CrestOverrides) do
    local def = NS.themes and NS.themes[id]
    if def and def.classArt and type(crest) == "table" and crest[1] then
      def.classArt.crest = { crest[1], crest[2] or 0, crest[3] or 0 }
    end
  end
end
Apply()
-- if a theme is registered later, re-apply when SetTheme runs — before the skins read classArt.crest
local prev = NS.SetTheme
if type(prev) == "function" then
  function NS.SetTheme(id)
    Apply()
    return prev(id)
  end
end
