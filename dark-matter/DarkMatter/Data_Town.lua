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
    { id = "flight", label = "Flight masters", role = "flight", group = "town", default = true },
    { id = "inn", label = "Innkeepers", role = "inn", group = "town", default = true },
    -- Suppliers are not reagent vendors. The pin uses the Town Pins glyph, not the reagent icon.
    { id = "vendor", label = "Vendors", role = "town", group = "town", default = true },
    { id = "bank", label = "Bankers", role = "bank", group = "town", default = true },
    { id = "auction", label = "Auctioneers", role = "auction", group = "town", default = true },
    { id = "entrance", label = "Dungeon entrances", role = "dungeon", group = "dungeon", default = true },
    { id = "levels", label = "Level ranges", group = "dungeon", default = true,
      note = "Levels appear beside visible entrances" },
    { id = "dock", label = "Docks", group = "travel", unavailable = true, note = "Not available yet" },
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
    -- The Riverglades guide (dateModified 2026-11-07) places this door at /way 37.5 37.5 on Wowhead zone 16591,
    -- the same zone id as the Riverglades flight masters. uiMapID 2548 is Riverglades in Data_ZoneMasks.lua.
    -- The level pair is the Forever news table, not the zone's 36-44 and not a wiki page.
    { cat = "entrance", name = "Krol'dok Stronghold", detail = "Dungeon", map = 2548, x = 0.3750, y = 0.3750,
      levels = { 40, 45 }, levelSrc = "https://www.wowhead.com/forever/news/explore-the-new-dungeons-of-world-of-warcraft-forever-383506",
      src = "https://www.wowhead.com/forever/guide/riverglades-zone-overview" },
    -- The Riverglades guide (dateModified 2026-11-07) names each pier and where that boat goes.
    -- Tanaris is uiMapID 1446. Riverglades is uiMapID 2548. No dock texture, so these are not drawn.
    { cat = "dock", name = "Steamwheedle Port", detail = "Tanaris", dest = "Powderfuse Port, Riverglades", map = 1446, x = 0.6860, y = 0.2300,
      src = "https://www.wowhead.com/forever/guide/riverglades-zone-overview" },
    { cat = "dock", name = "Powderfuse Port", detail = "Riverglades", dest = "Steamwheedle Port, Tanaris", map = 2548, x = 0.8060, y = 0.5460,
      src = "https://www.wowhead.com/forever/guide/riverglades-zone-overview" },
  },
}
