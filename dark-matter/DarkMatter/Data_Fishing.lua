-- Original Dark Matter fishing waters table for Classic Forever.
-- This client has no fishing-zone / catch APIs (forever_api + probe: only GetProfessions /
-- GetProfessionInfo and IsFishingLoot). Zone names and minimum skill floors are authored
-- here for the addon (Classic-style open-water floors), not copied from another addon.
local _, NS = ...

-- minSkill: approximate skill needed to fish the zone's open water without constant escapes.
-- levels: the zone's character level band (context only).
NS.FishingZones = {
  { name = "Elwynn Forest",           continent = "Eastern Kingdoms", levels = "1-10",  minSkill = 1 },
  { name = "Dun Morogh",              continent = "Eastern Kingdoms", levels = "1-10",  minSkill = 1 },
  { name = "Tirisfal Glades",         continent = "Eastern Kingdoms", levels = "1-10",  minSkill = 1 },
  { name = "Durotar",                 continent = "Kalimdor",         levels = "1-10",  minSkill = 1 },
  { name = "Mulgore",                 continent = "Kalimdor",         levels = "1-10",  minSkill = 1 },
  { name = "Teldrassil",              continent = "Kalimdor",         levels = "1-10",  minSkill = 1 },
  { name = "Westfall",                continent = "Eastern Kingdoms", levels = "10-20", minSkill = 1 },
  { name = "Loch Modan",              continent = "Eastern Kingdoms", levels = "10-20", minSkill = 1 },
  { name = "Darkshore",               continent = "Kalimdor",         levels = "10-20", minSkill = 1 },
  { name = "Silverpine Forest",       continent = "Eastern Kingdoms", levels = "10-20", minSkill = 1 },
  { name = "The Barrens",             continent = "Kalimdor",         levels = "10-25", minSkill = 1 },
  { name = "Redridge Mountains",      continent = "Eastern Kingdoms", levels = "15-25", minSkill = 55 },
  { name = "Wetlands",                continent = "Eastern Kingdoms", levels = "20-30", minSkill = 55 },
  { name = "Ashenvale",               continent = "Kalimdor",         levels = "18-30", minSkill = 55 },
  { name = "Stonetalon Mountains",    continent = "Kalimdor",         levels = "15-27", minSkill = 55 },
  { name = "Hillsbrad Foothills",     continent = "Eastern Kingdoms", levels = "20-30", minSkill = 55 },
  { name = "Thousand Needles",        continent = "Kalimdor",         levels = "25-35", minSkill = 55 },
  { name = "Stranglethorn Vale",      continent = "Eastern Kingdoms", levels = "30-45", minSkill = 130 },
  { name = "Dustwallow Marsh",        continent = "Kalimdor",         levels = "35-45", minSkill = 130 },
  { name = "Desolace",                continent = "Kalimdor",         levels = "30-40", minSkill = 130 },
  { name = "Arathi Highlands",        continent = "Eastern Kingdoms", levels = "30-40", minSkill = 130 },
  { name = "Swamp of Sorrows",        continent = "Eastern Kingdoms", levels = "35-45", minSkill = 130 },
  { name = "Badlands",                continent = "Eastern Kingdoms", levels = "35-45", minSkill = 130 },
  { name = "Tanaris",                 continent = "Kalimdor",         levels = "40-50", minSkill = 175 },
  { name = "Feralas",                 continent = "Kalimdor",         levels = "40-50", minSkill = 175 },
  { name = "The Hinterlands",         continent = "Eastern Kingdoms", levels = "40-50", minSkill = 175 },
  { name = "Searing Gorge",           continent = "Eastern Kingdoms", levels = "45-50", minSkill = 175 },
  { name = "Azshara",                 continent = "Kalimdor",         levels = "45-55", minSkill = 175 },
  { name = "Un'Goro Crater",          continent = "Kalimdor",         levels = "48-55", minSkill = 205 },
  { name = "Felwood",                 continent = "Kalimdor",         levels = "48-55", minSkill = 205 },
  { name = "Winterspring",            continent = "Kalimdor",         levels = "53-60", minSkill = 205 },
  { name = "Western Plaguelands",     continent = "Eastern Kingdoms", levels = "50-58", minSkill = 205 },
  { name = "Eastern Plaguelands",     continent = "Eastern Kingdoms", levels = "53-60", minSkill = 205 },
  { name = "Burning Steppes",         continent = "Eastern Kingdoms", levels = "50-58", minSkill = 205 },
  { name = "Deadwind Pass",           continent = "Eastern Kingdoms", levels = "55-60", minSkill = 225 },
  { name = "Moonglade",               continent = "Kalimdor",         levels = "1-60",  minSkill = 225 },
}

--- Read fishing skill from the profession API the probe confirmed.
-- Returns name, rank, max (or nils). Never loads Blizzard UI.
function NS.ReadFishingSkill()
  if not (GetProfessions and GetProfessionInfo) then return end
  local ok, _, _, _, fish = pcall(GetProfessions)
  fish = ok and NS.Num(fish) or nil
  if not fish then return end
  local ok2, name, _, rank, maxRank = pcall(GetProfessionInfo, fish)
  if not ok2 then return end
  name = NS.Str(name)
  rank = NS.Num(rank)
  maxRank = NS.Num(maxRank)
  if name and rank and maxRank then return name, rank, maxRank end
end
