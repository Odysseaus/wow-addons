-- Static catalog of Classic / Forever fishing-catchable items (open-water loot + common junk).
-- Authored for Dark Matter Show-all: ids/names from Classic fishing loot tables (not another addon).
-- When Show all is on, uncaught catalog entries appear below caught ones (caught highlighted, sorted top).
local _, NS = ...

-- { itemId, name, junk? }  junk ≈ non-fish clutter / quality-0 style pool trash
NS.FishingCatchCatalog = {
  { itemId = 6291,  name = "Raw Brilliant Smallfish" , icon = "Interface\\Icons\\INV_Misc_Fish_07"},
  { itemId = 6303,  name = "Raw Slitherskin Mackerel" , icon = "Interface\\Icons\\INV_Misc_Fish_24"},
  { itemId = 6289,  name = "Raw Longjaw Mud Snapper" , icon = "Interface\\Icons\\INV_Misc_Fish_32"},
  { itemId = 6317,  name = "Raw Loch Frenzy" , icon = "Interface\\Icons\\INV_Misc_Fish_03"},
  { itemId = 6361,  name = "Raw Rainbow Fin Albacore" , icon = "Interface\\Icons\\INV_Misc_Fish_25"},
  { itemId = 6308,  name = "Raw Bristle Whisker Catfish" , icon = "Interface\\Icons\\INV_Misc_Fish_30"},
  { itemId = 6362,  name = "Raw Rockscale Cod" , icon = "Interface\\Icons\\INV_Misc_Fish_04"},
  { itemId = 21071, name = "Raw Sagefish" , icon = "Interface\\Icons\\INV_Misc_Fish_11"},
  { itemId = 21153, name = "Raw Greater Sagefish" , icon = "Interface\\Icons\\INV_Misc_Fish_20"},
  { itemId = 6358,  name = "Oily Blackmouth" , icon = "Interface\\Icons\\INV_Misc_MonsterHead_04"},
  { itemId = 6359,  name = "Firefin Snapper" , icon = "Interface\\Icons\\INV_Misc_MonsterHead_01"},
  { itemId = 13422, name = "Stonescale Eel" , icon = "Interface\\Icons\\INV_Misc_Fish_11"},
  { itemId = 4603,  name = "Raw Spotted Yellowtail" , icon = "Interface\\Icons\\INV_Misc_Fish_01"},
  { itemId = 8365,  name = "Raw Mithril Head Trout" , icon = "Interface\\Icons\\INV_Misc_Fish_02"},
  { itemId = 13754, name = "Raw Glossy Mightfish" , icon = "Interface\\Icons\\INV_Misc_Fish_06"},
  { itemId = 13756, name = "Raw Summer Bass" , icon = "Interface\\Icons\\INV_Misc_Fish_03"},
  { itemId = 13758, name = "Raw Redgill" , icon = "Interface\\Icons\\INV_Misc_Fish_06"},
  { itemId = 13760, name = "Raw Sunscale Salmon" , icon = "Interface\\Icons\\INV_Misc_Fish_22"},
  { itemId = 13888, name = "Darkshore Grouper" , icon = "Interface\\Icons\\INV_Misc_Fish_02"},
  { itemId = 13889, name = "Raw Whitescale Salmon" , icon = "Interface\\Icons\\INV_Misc_Fish_22"},
  { itemId = 13893, name = "Large Raw Mightfish" , icon = "Interface\\Icons\\INV_Misc_Fish_06"},
  { itemId = 13876, name = "40 Pound Grouper" , icon = "Interface\\Icons\\INV_Misc_Fish_02"},
  { itemId = 13877, name = "47 Pound Grouper" , icon = "Interface\\Icons\\INV_Misc_Fish_02"},
  { itemId = 13878, name = "53 Pound Grouper" , icon = "Interface\\Icons\\INV_Misc_Fish_02"},
  { itemId = 13879, name = "59 Pound Grouper" , icon = "Interface\\Icons\\INV_Misc_Fish_02"},
  { itemId = 13880, name = "68 Pound Grouper" , icon = "Interface\\Icons\\INV_Misc_Fish_02"},
  { itemId = 6360,  name = "Steelscale Crushfish" , icon = "Interface\\Icons\\INV_Misc_Fish_04"},
  { itemId = 8959,  name = "Raw Spinefin Halibut" , icon = "Interface\\Icons\\INV_Misc_Fish_08"},
  { itemId = 19808, name = "Rockhide Strongfish" , icon = "Interface\\Icons\\INV_Misc_Fish_08"},
  { itemId = 6292,  name = "10 Pound Mud Snapper" , icon = "Interface\\Icons\\INV_Misc_Fish_32"},
  { itemId = 6294,  name = "12 Pound Mud Snapper" , icon = "Interface\\Icons\\INV_Misc_Fish_32"},
  { itemId = 6295,  name = "15 Pound Mud Snapper" , icon = "Interface\\Icons\\INV_Misc_Fish_32"},
  { itemId = 6299,  name = "Sickly Looking Fish", junk = true , icon = "Interface\\Icons\\INV_Misc_Fish_08"},
  { itemId = 6307,  name = "Message in a Bottle", junk = true , icon = "Interface\\Icons\\INV_Misc_Note_06"},
  { itemId = 6651,  name = "Broken Wine Bottle", junk = true , icon = "Interface\\Icons\\INV_Drink_10"},
  { itemId = 5523,  name = "Small Barnacled Clam", junk = true , icon = "Interface\\Icons\\INV_Misc_Shell_01"},
  { itemId = 5524,  name = "Thick-shelled Clam", junk = true , icon = "Interface\\Icons\\INV_Misc_Shell_02"},
  { itemId = 7973,  name = "Big-mouth Clam", junk = true , icon = "Interface\\Icons\\INV_Misc_Shell_01"},
  { itemId = 20768, name = "Oozing Bag", junk = true , icon = "Interface\\Icons\\INV_Misc_Bag_13"},
  { itemId = 4510,  name = "Ruined Pelt", junk = true , icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_Ruin_01"},
  { itemId = 6304,  name = "Damp Diary Page", junk = true , icon = "Interface\\Icons\\INV_Misc_Note_06"},
  { itemId = 18235, name = "Schematic: Field Repair Bot 74A", junk = true , icon = "Interface\\Icons\\INV_Scroll_05"},
  { itemId = 11099, name = "Dark Iron Ore", junk = true , icon = "Interface\\Icons\\INV_Ore_Mithril_01"},
  { itemId = 12808, name = "Essence of Undeath", junk = true , icon = "Interface\\Icons\\Spell_Shadow_Teleport"},
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
