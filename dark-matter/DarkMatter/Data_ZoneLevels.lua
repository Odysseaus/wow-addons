-- 0.5.0 zone level badges for the Map tab. PUBLIC DATA, not read from the game: the client returns no level ranges
-- (/dm mapprobe 0.4.7: "map 8: levels: not provided").
-- Sources (October 2026): Wowhead WoW Forever guides for the new Forever zones (Zephras Isle 1-12, Riverglades 35-45,
-- Mount Hyjal 60; Shen'Dralas has no published range, so it gets no badge). Wowhead's per-zone Forever pages could not
-- be read from here, so the Classic zones use Warcraft Wiki "Zones by level (Classic)". Forever may retune these.
-- Keys are zone names in lower case without a leading "the ".
local _, NS = ...
NS.ZoneLevels = {
  source = "public data: Wowhead WoW Forever (new zones), Warcraft Wiki Classic table",
  short = "Levels: public data",
  zones = {
    ["dun morogh"] = { 1, 10 }, ["durotar"] = { 1, 10 }, ["elwynn forest"] = { 1, 10 }, ["mulgore"] = { 1, 10 },
    ["teldrassil"] = { 1, 10 }, ["tirisfal glades"] = { 1, 10 },
    ["darkshore"] = { 10, 20 }, ["loch modan"] = { 10, 20 }, ["silverpine forest"] = { 10, 20 }, ["westfall"] = { 10, 20 },
    ["barrens"] = { 10, 25 }, ["redridge mountains"] = { 15, 25 }, ["stonetalon mountains"] = { 15, 27 },
    ["ashenvale"] = { 18, 30 }, ["duskwood"] = { 18, 30 }, ["wetlands"] = { 20, 30 }, ["hillsbrad foothills"] = { 20, 35 },
    ["thousand needles"] = { 25, 35 }, ["alterac mountains"] = { 30, 40 }, ["arathi highlands"] = { 30, 40 },
    ["desolace"] = { 30, 40 }, ["stranglethorn vale"] = { 30, 45 }, ["dustwallow marsh"] = { 35, 45 },
    ["badlands"] = { 35, 45 }, ["swamp of sorrows"] = { 35, 45 }, ["feralas"] = { 40, 50 }, ["hinterlands"] = { 40, 50 },
    ["tanaris"] = { 40, 50 }, ["searing gorge"] = { 45, 50 }, ["azshara"] = { 45, 55 }, ["blasted lands"] = { 45, 55 },
    ["un'goro crater"] = { 48, 55 }, ["felwood"] = { 48, 55 }, ["burning steppes"] = { 50, 58 },
    ["western plaguelands"] = { 51, 58 }, ["eastern plaguelands"] = { 53, 60 }, ["winterspring"] = { 53, 60 },
    ["deadwind pass"] = { 55, 60 }, ["moonglade"] = { 55, 60 }, ["silithus"] = { 55, 60 },
    -- WoW Forever (Wowhead)
    ["zephras isle"] = { 1, 12 }, ["riverglades"] = { 35, 45 }, ["mount hyjal"] = { 60, 60 },
  },
}

function NS.ZoneLevelText(name)
  if type(name) ~= "string" then return nil end
  local k = name:lower():gsub("^the ", "")
  local r = NS.ZoneLevels.zones[k]
  if not r then return nil end
  if r[1] == r[2] then return tostring(r[1]) end
  return r[1] .. "-" .. r[2]
end
