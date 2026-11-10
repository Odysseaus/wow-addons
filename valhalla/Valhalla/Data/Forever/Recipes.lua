--------------------------------------------------------------------------------
-- WoW Forever recipes (v0.4.1): bundled recipe IDs for the professions none of your characters has opened.
-- Only IDs: the output, its quantity and the reagents are always read from the game
-- (C_TradeSkillUI.GetRecipeSchematic), so this list can be incomplete but never wrong about costs. An ID
-- the game doesn't know is dropped (counted as "unknown to this client"). A profession's window, once
-- opened on any character, replaces its bundled list with the game's own (Investments/Craft.lua).
--
-- Format (for a data drop):
--   ns.Recipes.professions[<skill line ID>] = { name = "<English profession name>", ids = "<recipe ID>,<recipe ID>,..." }
--   skill lines: Alchemy 171, Blacksmithing 164, Enchanting 333, Engineering 202, Herbalism 182,
--   Leatherworking 165, Mining 186, Skinning 393, Tailoring 197, Cooking 185, First Aid 129, Fishing 356,
--   Jewelcrafting 755, Inscription 773. Recipe ID = the recipe's spell ID (Wowhead's /forever/spell=<ID>).
--
-- v0.4.1 ships only the IDs the game itself answered for (the AH check's recipe probe, 2026-11-10, profession
-- window closed: GetRecipeSchematic read each one). 2330 isn't here: the game returned it empty.
--------------------------------------------------------------------------------

local _, ns = ...
ns.Recipes = {
	source = "Valhalla AH check recipe probe, 2026-11-10 (read in game)",
	professions = {
		[197] = { name = "Tailoring", ids = "2963" },        -- Bolt of Linen Cloth
		[129] = { name = "First Aid", ids = "3275" },        -- Linen Bandage
		[186] = { name = "Mining", ids = "2657" },           -- Smelt Copper
		[164] = { name = "Blacksmithing", ids = "2660" },    -- Rough Sharpening Stone
		[165] = { name = "Leatherworking", ids = "2149" },   -- Handstitched Leather Boots
		[185] = { name = "Cooking", ids = "2538" },          -- Charred Wolf Meat
	},
}
