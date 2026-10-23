-- 0.5.0 map data for the Map tab: everything is read from the game at runtime (C_Map / C_MapExplorationInfo), per
-- mapID, for every continent and zone. Nothing here draws or changes the game: no hooks, no waypoints, no WorldMapFrame.
-- Coordinates:
--   map coords   0..1 on one map's own art (what the game's map shows as 0..100)
--   world coords 0..1 on the world map's art; a continent sits on it at its "placement" (see MD.Placement)
local _, NS = ...
local MD = {}
NS.MapData = MD

local function Fn(t, k) t = _G[t] if type(t) == "table" and type(t[k]) == "function" then return t[k] end end
local function Call(t, k, ...)
  local f = Fn(t, k)
  if not f then return end
  local r = { pcall(f, ...) }
  if r[1] then return select(2, unpack(r)) end
end
local function N(v) if type(v) == "number" and v == v then return v end end

local TYPE_NUM = { cosmic = 0, world = 1, continent = 2, zone = 3, dungeon = 4, micro = 5, orphan = 6 }
function MD.TypeNum(word)
  local E = type(Enum) == "table" and Enum.UIMapType
  if type(E) == "table" then
    for k, v in pairs(E) do if type(k) == "string" and k:lower() == word then return v end end
  end
  return TYPE_NUM[word]
end

local C = {} -- caches, keyed by mapID (cleared by MD.Forget)
local function Cache(name) C[name] = C[name] or {} return C[name] end
function MD.Forget(which)
  if which then C[which] = nil else C = {} end
end

function MD.Info(id)
  id = N(id)
  if not id then return nil end
  local c = Cache("info")
  if c[id] == nil then
    local i = Call("C_Map", "GetMapInfo", id)
    c[id] = type(i) == "table" and i or false
  end
  return c[id] or nil
end
function MD.Name(id) local i = MD.Info(id) return i and NS.Str(i.name) or nil end
-- 0.5.2b.6: the six capitals (Stormwind, Ironforge, Undercity, Orgrimmar, Thunder Bluff, Darnassus). Their land is drawn by
-- the zone around them (Elwynn, Dun Morogh, ...); their own picture only when the city itself is the focus.
MD.CITY_IDS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
function MD.IsCityID(id) return MD.CITY_IDS[id] == true end
function MD.Is(id, word) local i = MD.Info(id) return i ~= nil and i.mapType == MD.TypeNum(word) end

-- Art for ONE mapID: layer 1 of C_Map.GetMapArtLayers(mapID) + C_Map.GetMapArtLayerTextures(mapID, 1).
-- (0.4.7 probe: every Classic map, world/continent/zone, is 1002x668 in 4x3 tiles of 256; the file IDs differ.)
function MD.Art(id)
  id = N(id)
  if not id then return nil end
  local c = Cache("art")
  if c[id] == nil then
    c[id] = false
    local layers = Call("C_Map", "GetMapArtLayers", id)
    local L = type(layers) == "table" and layers[1]
    local tex = Call("C_Map", "GetMapArtLayerTextures", id, 1)
    if type(L) == "table" and type(tex) == "table" and #tex > 0 then
      local w, h = N(L.layerWidth) or 1002, N(L.layerHeight) or 668
      local tw, th = N(L.tileWidth) or 256, N(L.tileHeight) or 256
      local cols = math.ceil(w / tw)
      c[id] = { mapID = id, w = w, h = h, tw = tw, th = th, cols = cols, rows = math.ceil(h / th), tex = tex }
    end
  end
  return c[id] or nil
end

-- Explored overlays (fog of war): C_MapExplorationInfo.GetExploredMapTextures(mapID). Overlays shown only on mouse-over
-- in the game's map are skipped. nil when the client has no API; {} when nothing is explored / not used for this map.
function MD.Explored(id)
  id = N(id)
  if not id or not Fn("C_MapExplorationInfo", "GetExploredMapTextures") then return nil end
  local c = Cache("explored")
  if c[id] == nil then
    local list = Call("C_MapExplorationInfo", "GetExploredMapTextures", id)
    local out = {}
    if type(list) == "table" then
      for _, e in ipairs(list) do
        if type(e) == "table" and not e.isShownByMouseOver and type(e.fileDataIDs) == "table" then out[#out + 1] = e end
      end
    end
    c[id] = out
  end
  return c[id]
end

-- 0.5.2b.6: a short fingerprint of a map's explored areas, read fresh from the game (not the cache), and whether the
-- cached list (what the map draws) is out of date: a new discovery adds an entry or grows one
local function Sig(list)
  local n, parts = 0, {}
  for _, e in ipairs(type(list) == "table" and list or {}) do
    if type(e) == "table" and not e.isShownByMouseOver and type(e.fileDataIDs) == "table" then
      n = n + 1
      parts[#parts + 1] = string.format("%s,%s,%s,%s", tostring(e.offsetX), tostring(e.offsetY), tostring(e.textureWidth), tostring(e.textureHeight))
    end
  end
  table.sort(parts)
  return n .. ":" .. table.concat(parts, ";")
end
function MD.ExploredSig(id)
  id = N(id)
  if not id or not Fn("C_MapExplorationInfo", "GetExploredMapTextures") then return nil end
  return Sig(Call("C_MapExplorationInfo", "GetExploredMapTextures", id))
end
function MD.ExploredChanged(id)
  id = N(id)
  local c = id and C.explored
  if not (c and c[id]) then return false end
  local now = MD.ExploredSig(id)
  return now ~= nil and now ~= Sig(c[id])
end

-- Where map `child` sits on map `parent` (0..1 of the parent's art): minX, maxX, minY, maxY or nil.
function MD.Rect(child, parent)
  child, parent = N(child), N(parent)
  if not child or not parent then return nil end
  local c = Cache("rect")
  local k = child .. ":" .. parent
  if c[k] == nil then
    local x1, x2, y1, y2 = Call("C_Map", "GetMapRectOnMap", child, parent)
    x1, x2, y1, y2 = N(x1), N(x2), N(y1), N(y2)
    if x1 and x2 and y1 and y2 and x2 > x1 and y2 > y1 then c[k] = { x1, x2, y1, y2 } else c[k] = false end
  end
  local r = c[k]
  if r then return r[1], r[2], r[3], r[4] end
end

local function Children(id, word)
  local c = Cache("kids")
  local k = tostring(id) .. ":" .. word
  if c[k] == nil then
    local out = {}
    local list = Call("C_Map", "GetMapChildrenInfo", id, MD.TypeNum(word))
    local seen = {}
    if type(list) == "table" then
      for _, i in ipairs(list) do
        local cid = type(i) == "table" and N(i.mapID)
        if cid and not seen[cid] and cid ~= id and (i.mapType == nil or i.mapType == MD.TypeNum(word)) then
          seen[cid] = true
          out[#out + 1] = { id = cid, name = NS.Str(i.name) or MD.Name(cid) or ("map " .. cid) }
        end
      end
    end
    c[k] = out
  end
  return c[k]
end

-- The parent chain of a map, nearest first (guarded against loops).
function MD.Chain(id)
  local out, seen = {}, {}
  id = N(id)
  while id and id ~= 0 and not seen[id] and #out < 12 do
    seen[id] = true
    local i = MD.Info(id)
    if not i then break end
    out[#out + 1] = id
    id = N(i.parentMapID)
  end
  return out
end
function MD.ContinentOf(id)
  for _, m in ipairs(MD.Chain(id)) do if MD.Is(m, "continent") then return m end end
end
-- The zone a map belongs to (itself for a zone; the zone above a micro/dungeon map).
function MD.ZoneOf(id)
  for _, m in ipairs(MD.Chain(id)) do if MD.Is(m, "zone") then return m end end
end

function MD.PlayerMap() return N(Call("C_Map", "GetBestMapForUnit", "player")) end

-- The world map above the continents: from the player's map chain, else the game's fallback world map.
function MD.World()
  local c = Cache("world")
  if c.id == nil then
    c.id = false
    for _, m in ipairs(MD.Chain(MD.PlayerMap())) do if MD.Is(m, "world") then c.id = m end end
    if not c.id then
      local fb = N(Call("C_Map", "GetFallbackWorldMapID"))
      if fb and MD.Is(fb, "world") then c.id = fb end
    end
    if not c.id and MD.Is(947, "world") then c.id = 947 end
  end
  return c.id or nil
end

-- Continents with art. Under the world map when there is one; else the player's own continent.
function MD.Continents()
  local c = Cache("conts")
  if not c.list then
    local list = {}
    local w = MD.World()
    if w then
      for _, k in ipairs(Children(w, "continent")) do if MD.Art(k.id) then list[#list + 1] = k end end
    end
    if #list == 0 then
      local pc = MD.ContinentOf(MD.PlayerMap())
      if pc and MD.Art(pc) then list[1] = { id = pc, name = MD.Name(pc) or "Continent" } end
    end
    c.list = list
  end
  return c.list
end

-- Zones of a continent that have art and a rect on it; big ones first (cities draw last, on top).
function MD.Zones(cont)
  local c = Cache("zones")
  if not c[cont] then
    local out = {}
    for _, z in ipairs(Children(cont, "zone")) do
      local x1, x2, y1, y2 = MD.Rect(z.id, cont)
      if x1 and MD.Art(z.id) then
        out[#out + 1] = { id = z.id, name = z.name, cont = cont, r = { x1, x2, y1, y2 }, area = (x2 - x1) * (y2 - y1) }
      end
    end
    table.sort(out, function(a, b) if a.area ~= b.area then return a.area > b.area end return a.id < b.id end)
    c[cont] = out
  end
  return c[cont]
end
function MD.ZoneEntry(id)
  for _, ct in ipairs(MD.Continents()) do
    for _, z in ipairs(MD.Zones(ct.id)) do if z.id == id then return z end end
  end
end

-- The land on a continent's art: the union of its zone rects.
function MD.Land(cont)
  local x1, x2, y1, y2
  for _, z in ipairs(MD.Zones(cont)) do
    local r = z.r
    x1 = math.min(x1 or r[1], r[1]) x2 = math.max(x2 or r[2], r[2])
    y1 = math.min(y1 or r[3], r[3]) y2 = math.max(y2 or r[4], r[4])
  end
  if x1 then return { x1, x2, y1, y2 } end
end

-- Last resort only: where each continent's LAND sits on the Classic world picture, by eye (0..1 of the world art).
MD.APPROX_LAND = {
  ["kalimdor"] = { 0.09, 0.36, 0.20, 0.92 },
  ["eastern kingdoms"] = { 0.66, 0.89, 0.12, 0.89 },
}

local function Sane(r) return r and r[1] >= -0.05 and r[2] <= 1.05 and r[3] >= -0.05 and r[4] <= 1.05 and (r[2] - r[1]) > 0.04 end

-- Land box of a continent on the world art, sampled with C_Map.GetMapInfoAtPosition(world, x, y) (read-only).
local function SampleLand(w, cont)
  if not Fn("C_Map", "GetMapInfoAtPosition") then return nil end
  local NX, NY = 64, 43
  local x1, x2, y1, y2, hits = nil, nil, nil, nil, 0
  for i = 0, NX do
    for j = 0, NY do
      local x, y = i / NX, j / NY
      local info = Call("C_Map", "GetMapInfoAtPosition", w, x, y)
      local id = type(info) == "table" and N(info.mapID)
      if id and id ~= w and (id == cont or MD.ContinentOf(id) == cont) then
        hits = hits + 1
        x1 = math.min(x1 or x, x) x2 = math.max(x2 or x, x) y1 = math.min(y1 or y, y) y2 = math.max(y2 or y, y)
      end
    end
  end
  if hits >= 6 and x2 - x1 > 0.04 and y2 - y1 > 0.04 then
    local hx, hy = 0.5 / NX, 0.5 / NY
    return { x1 - hx, x2 + hx, y1 - hy, y2 + hy }
  end
end

-- Placement of a continent's ART on the world art: { x1, x2, y1, y2 } (0..1 of the world art) and its source:
--   "rect"    C_Map.GetMapRectOnMap(continent, world), when it fits on the world picture
--   "sampled" the continent's land found on the world picture (GetMapInfoAtPosition), matched to its zone rects
--   "approx"  a built-in estimate of where the land is (last resort; only affects the world <-> continent crossfade)
-- Zones are always placed on their continent with GetMapRectOnMap, so zone stitching never depends on this.
function MD.Placement(cont)
  local w = MD.World()
  if not w then return { 0, 1, 0, 1 }, "none" end
  local c = Cache("place")
  if c[cont] then return c[cont][1], c[cont][2] end
  local p, src
  local x1, x2, y1, y2 = MD.Rect(cont, w)
  if x1 and Sane({ x1, x2, y1, y2 }) then p, src = { x1, x2, y1, y2 }, "rect" end
  local land = not p and MD.Land(cont)
  if land then
    local saved = NS.db and NS.db.map and NS.db.map.place and NS.db.map.place[cont]
    local target
    if type(saved) == "table" and saved.v == 1 and type(saved.land) == "table" then target, src = saved.land, "sampled"
    else
      target = SampleLand(w, cont)
      if target then
        src = "sampled"
        if NS.db then NS.db.map = NS.db.map or {} NS.db.map.place = NS.db.map.place or {} NS.db.map.place[cont] = { v = 1, land = target } end
      end
    end
    if not target then
      local nm = (MD.Name(cont) or ""):lower()
      target = MD.APPROX_LAND[nm]
      if target then src = "approx" end
    end
    if target then
      -- one scale for both axes (continent and world art have the same shape), centred on the land
      local sx = (target[2] - target[1]) / (land[2] - land[1])
      local sy = (target[4] - target[3]) / (land[4] - land[3])
      local sc = (sx + sy) / 2
      local px = (target[1] + target[2]) / 2 - (land[1] + land[2]) / 2 * sc
      local py = (target[3] + target[4]) / 2 - (land[3] + land[4]) / 2 * sc
      p = { px, px + sc, py, py + sc }
    end
  end
  if not p then p, src = { 0.25, 0.75, 0.25, 0.75 }, "guess" end
  c[cont] = { p, src }
  return p, src
end

-- map coords on `id` -> world coords (via zone rect on its continent and the continent placement); nil if unplaceable
function MD.ToWorld(id, x, y)
  if not (N(x) and N(y)) then return nil end
  local cont
  if MD.Is(id, "continent") then cont = id
  elseif MD.Is(id, "world") then return x, y
  else
    local z = MD.ZoneEntry(id)
    if not z then return nil end
    x = z.r[1] + x * (z.r[2] - z.r[1])
    y = z.r[3] + y * (z.r[4] - z.r[3])
    cont = z.cont
  end
  local p = MD.Placement(cont)
  return p[1] + x * (p[2] - p[1]), p[3] + y * (p[4] - p[3]), cont
end

-- world coords -> map coords on a continent
function MD.WorldToCont(cont, wx, wy)
  local p = MD.Placement(cont)
  return (wx - p[1]) / (p[2] - p[1]), (wy - p[3]) / (p[4] - p[3])
end

-- The zone at continent coords (x, y): the game's own answer (GetMapInfoAtPosition) when it names a zone of this
-- continent, else the smallest zone rect containing the point. Returns the zone entry and its map coords.
function MD.ZoneAt(cont, x, y)
  local info = Call("C_Map", "GetMapInfoAtPosition", cont, x, y)
  local id = type(info) == "table" and N(info.mapID)
  local best
  if id then
    local zid = MD.ZoneOf(id) or id
    for _, z in ipairs(MD.Zones(cont)) do if z.id == zid then best = z end end
  end
  if not best then
    for _, z in ipairs(MD.Zones(cont)) do
      local r = z.r
      if x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4] and (not best or z.area < best.area) then best = z end
    end
  end
  if best then
    local r = best.r
    return best, (x - r[1]) / (r[2] - r[1]), (y - r[3]) / (r[4] - r[3])
  end
end

-- Player position on a map (0..1) or nil (instances, no API).
-- 0.5.2b.7: any unit (party / raid members); MD.PlayerPos is the player
function MD.Vec(pos)
  if type(pos) ~= "table" then return nil end
  local x, y
  if type(pos.GetXY) == "function" then local ok, a, b = pcall(pos.GetXY, pos) if ok then x, y = a, b end end
  x, y = N(x or pos.x), N(y or pos.y)
  if x and y and (x ~= 0 or y ~= 0) then return x, y end
end
function MD.UnitPos(id, unit) return MD.Vec(N(id) and Call("C_Map", "GetPlayerMapPosition", id, unit or "player")) end
function MD.UnitMap(unit) return N(Call("C_Map", "GetBestMapForUnit", unit)) end
function MD.PlayerPos(id)
  local pos = N(id) and Call("C_Map", "GetPlayerMapPosition", id, "player")
  if type(pos) ~= "table" then return nil end
  local x, y
  if type(pos.GetXY) == "function" then local ok, a, b = pcall(pos.GetXY, pos) if ok then x, y = a, b end end
  x, y = N(x or pos.x), N(y or pos.y)
  if x and y and (x ~= 0 or y ~= 0) then return x, y end
end

-- The player in world coords: on the continent's own map when the game answers there, else through the zone rect.
function MD.PlayerWorld()
  local m = MD.PlayerMap()
  if not m then return nil end
  local cont = MD.ContinentOf(m)
  if cont then
    local x, y = MD.PlayerPos(cont)
    if x then
      local p = MD.Placement(cont)
      return p[1] + x * (p[2] - p[1]), p[3] + y * (p[4] - p[3]), cont, m
    end
  end
  local z = MD.ZoneOf(m) or m
  local x, y = MD.PlayerPos(z)
  if x then
    local wx, wy, c2 = MD.ToWorld(z, x, y)
    if wx then return wx, wy, c2, m end
  end
end

-- Quest objective spots on a zone: C_QuestLog.GetQuestsOnMap(mapID) -> { {questID, x, y}, ... } (cached per map).
function MD.Quests(id)
  if not Fn("C_QuestLog", "GetQuestsOnMap") then return nil end
  local c = Cache("quests")
  if c[id] == nil then
    local out = {}
    local list = Call("C_QuestLog", "GetQuestsOnMap", id)
    if type(list) == "table" then
      for _, q in ipairs(list) do
        if type(q) == "table" and N(q.x) and N(q.y) and N(q.questID) then out[#out + 1] = { id = q.questID, x = q.x, y = q.y } end
      end
    end
    c[id] = out
  end
  return c[id]
end
function MD.QuestTitle(qid)
  local t = Call("C_QuestLog", "GetTitleForQuestID", qid)
  if NS.Str(t) then return t end
  if NS.QL and NS.QL.TitleOf then local ok, s = pcall(NS.QL.TitleOf, qid) if ok and NS.Str(s) then return s end end
  return "Quest " .. tostring(qid)
end

-- Zone / continent search by name (plain, case-insensitive), at most `max` results, continents first.
function MD.Search(q, max)
  q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local out = {}
  if q == "" then return out end
  max = max or 8
  for _, ct in ipairs(MD.Continents()) do
    if ct.name:lower():find(q, 1, true) and #out < max then out[#out + 1] = { id = ct.id, name = ct.name, sub = "Continent" } end
  end
  local starts, contains = {}, {}
  for _, ct in ipairs(MD.Continents()) do
    for _, z in ipairs(MD.Zones(ct.id)) do
      local n = z.name:lower()
      local at = n:find(q, 1, true)
      if at then table.insert(at == 1 and starts or contains, { id = z.id, name = z.name, sub = ct.name }) end
    end
  end
  local function byName(a, b) return a.name < b.name end
  table.sort(starts, byName) table.sort(contains, byName)
  for _, list in ipairs({ starts, contains }) do
    for _, r in ipairs(list) do if #out < max then out[#out + 1] = r end end
  end
  return out
end
