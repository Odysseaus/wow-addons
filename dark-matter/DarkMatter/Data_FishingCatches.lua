-- Static catalog of Classic / Forever fishing-catchable items (open-water loot + common junk).
-- Authored for Dark Matter Show-all: ids/names from Classic fishing loot tables (not another addon).
-- When Show all is on, uncaught catalog entries appear below caught ones (caught highlighted, sorted top).
local _, NS = ...

-- { itemId, name, junk? }  junk ≈ non-fish clutter / quality-0 style pool trash
NS.FishingCatchCatalog = {
  { itemId = 6291,  name = "Raw Brilliant Smallfish" },
  { itemId = 6303,  name = "Raw Slitherskin Mackerel" },
  { itemId = 6289,  name = "Raw Longjaw Mud Snapper" },
  { itemId = 6317,  name = "Raw Loch Frenzy" },
  { itemId = 6361,  name = "Raw Rainbow Fin Albacore" },
  { itemId = 6308,  name = "Raw Bristle Whisker Catfish" },
  { itemId = 6362,  name = "Raw Rockscale Cod" },
  { itemId = 21071, name = "Raw Sagefish" },
  { itemId = 21153, name = "Raw Greater Sagefish" },
  { itemId = 6358,  name = "Oily Blackmouth" },
  { itemId = 6359,  name = "Firefin Snapper" },
  { itemId = 13422, name = "Stonescale Eel" },
  { itemId = 4603,  name = "Raw Spotted Yellowtail" },
  { itemId = 8365,  name = "Raw Mithril Head Trout" },
  { itemId = 13754, name = "Raw Glossy Mightfish" },
  { itemId = 13756, name = "Raw Summer Bass" },
  { itemId = 13758, name = "Raw Redgill" },
  { itemId = 13760, name = "Raw Sunscale Salmon" },
  { itemId = 13888, name = "Darkshore Grouper" },
  { itemId = 13889, name = "Raw Whitescale Salmon" },
  { itemId = 13893, name = "Large Raw Mightfish" },
  { itemId = 13876, name = "40 Pound Grouper" },
  { itemId = 13877, name = "47 Pound Grouper" },
  { itemId = 13878, name = "53 Pound Grouper" },
  { itemId = 13879, name = "59 Pound Grouper" },
  { itemId = 13880, name = "68 Pound Grouper" },
  { itemId = 6360,  name = "Steelscale Crushfish" },
  { itemId = 8959,  name = "Raw Spinefin Halibut" },
  { itemId = 19808, name = "Rockhide Strongfish" },
  { itemId = 6292,  name = "10 Pound Mud Snapper" },
  { itemId = 6294,  name = "12 Pound Mud Snapper" },
  { itemId = 6295,  name = "15 Pound Mud Snapper" },
  { itemId = 6299,  name = "Sickly Looking Fish", junk = true },
  { itemId = 6307,  name = "Message in a Bottle", junk = true },
  { itemId = 6651,  name = "Broken Wine Bottle", junk = true },
  { itemId = 5523,  name = "Small Barnacled Clam", junk = true },
  { itemId = 5524,  name = "Thick-shelled Clam", junk = true },
  { itemId = 7973,  name = "Big-mouth Clam", junk = true },
  { itemId = 20768, name = "Oozing Bag", junk = true },
  { itemId = 4510,  name = "Ruined Pelt", junk = true },
  { itemId = 6304,  name = "Damp Diary Page", junk = true },
  { itemId = 18235, name = "Schematic: Field Repair Bot 74A", junk = true },
  { itemId = 11099, name = "Dark Iron Ore", junk = true },
  { itemId = 12808, name = "Essence of Undeath", junk = true },
}

function NS.FishingCatalogById()
  local t = {}
  for _, e in ipairs(NS.FishingCatchCatalog or {}) do
    if e.itemId then t[e.itemId] = e end
  end
  return t
end

function NS.FishingCatalogByName()
  local t = {}
  for _, e in ipairs(NS.FishingCatchCatalog or {}) do
    if e.name then t[e.name] = e end
  end
  return t
end
