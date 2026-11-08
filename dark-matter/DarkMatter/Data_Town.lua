-- Town pins. Coordinates are from Wowhead WoW Forever, fetched 2026-11-08. A page that only names a category is not a location.
-- Map ids are this addon's own: Ironforge is uiMapID 1455 (the map tests' game table names it Ironforge). Tanaris is 1446 and
-- Riverglades is 2548 (Data_ZoneMasks.lua, sampled from the client 2026-10-23; Compat_Era.lua names 2548 riverglades).
-- Wowhead zone 1537 is the zone id on tooltip records whose place line says Ironforge. Coordinates are 0-1 on that map.
-- A tooltip cluster is the center of points within 1.5 map-percent of each other. A second cluster is not averaged in.
-- Not drawn, and why:
--   Stormwind (Wowhead zone 1519). These tooltips list two clusters for the same NPC, and neither is marked current:
--   Dungar Longdrink (flight), Innkeeper Allison, Edna Mullby and Thurman Mullby and Maria Lumere and Alexandra Bolero
--   and Billibub Cogspinner and Catherine Leland (vendors), Auctioneer Fitch, Chilton and Jaxon, Olivia, Newton and John
--   Burnside (bankers). Weapon and armor merchants in that same fetch (Marda Weller, Lina Stover, Gerik Koen, Agustus
--   Moulaine) have no matching tracking icon and the same two-cluster problem.
--   Orgrimmar, Thunder Bluff, Undercity and Darnassus tooltips name the city, and this file does not pair those names
--   with uiMapIDs 1454, 1456, 1457 or 1458.
--   Docks have verified destinations below. This addon has no dock texture, so the Docks row stays hidden until one loads.
local _, NS = ...

NS.TownPins = {
  fetched = "2026-11-08",
  cats = {
    { id = "flight", label = "Flight masters", role = "flight", default = true },
    { id = "inn", label = "Innkeepers", role = "inn", default = true },
    { id = "vendor", label = "Vendors", role = "reagents", default = true },
    { id = "bank", label = "Bankers", role = "bank", default = true },
    { id = "auction", label = "Auctioneers", role = "auction", default = true },
    { id = "dock", label = "Docks", role = "dock", default = true },
  },
  pins = {
    { cat = "flight", name = "Gryth Thurden", detail = "Gryphon Master", map = 1455, x = 0.5568, y = 0.4796,
      src = "https://nether.wowhead.com/forever/tooltip/npc/1573", whZone = 1537 },
    { cat = "inn", name = "Innkeeper Firebrew", detail = "Innkeeper", map = 1455, x = 0.1850, y = 0.5150,
      src = "https://nether.wowhead.com/forever/tooltip/npc/5111", whZone = 1537 },
    { cat = "vendor", name = "Fillius Fizzlespinner", detail = "Trade Supplier", map = 1455, x = 0.3850, y = 0.7393,
      src = "https://nether.wowhead.com/forever/tooltip/npc/5100", whZone = 1537 },
    { cat = "vendor", name = "Golnir Bouldertoe", detail = "Mining Supplier", map = 1455, x = 0.5135, y = 0.2610,
      src = "https://nether.wowhead.com/forever/tooltip/npc/4256", whZone = 1537 },
    { cat = "vendor", name = "Poranna Snowbraid", detail = "Tailoring Supplies", map = 1455, x = 0.4350, y = 0.2900,
      src = "https://nether.wowhead.com/forever/tooltip/npc/5154", whZone = 1537 },
    { cat = "bank", name = "Barnum Stonemantle", detail = "Banker", map = 1455, x = 0.3460, y = 0.5924,
      src = "https://nether.wowhead.com/forever/tooltip/npc/2460", whZone = 1537 },
    { cat = "bank", name = "Bailey Stonemantle", detail = "Banker", map = 1455, x = 0.3550, y = 0.6050,
      src = "https://nether.wowhead.com/forever/tooltip/npc/2461", whZone = 1537 },
    { cat = "auction", name = "Auctioneer Redmuse", detail = "Auctioneer", map = 1455, x = 0.2460, y = 0.7412,
      src = "https://nether.wowhead.com/forever/tooltip/npc/8720", whZone = 1537 },
    { cat = "flight", name = "Gretchen Mayberry", detail = "Gryphon Master", map = 2548, x = 0.6060, y = 0.8150,
      src = "https://nether.wowhead.com/forever/tooltip/npc/257087", whZone = 16591 },
    { cat = "flight", name = "Grakna", detail = "Wind Rider Master", map = 2548, x = 0.5950, y = 0.4500,
      src = "https://nether.wowhead.com/forever/tooltip/npc/255993", whZone = 16591 },
    -- The Riverglades guide (dateModified 2026-11-07) names each pier and where that boat goes.
    -- Tanaris is uiMapID 1446. Riverglades is uiMapID 2548.
    { cat = "dock", name = "Steamwheedle Port", detail = "Tanaris", dest = "Powderfuse Port, Riverglades", map = 1446, x = 0.6860, y = 0.2300,
      src = "https://www.wowhead.com/forever/guide/riverglades-zone-overview" },
    { cat = "dock", name = "Powderfuse Port", detail = "Riverglades", dest = "Steamwheedle Port, Tanaris", map = 2548, x = 0.8060, y = 0.5460,
      src = "https://www.wowhead.com/forever/guide/riverglades-zone-overview" },
  },
}
