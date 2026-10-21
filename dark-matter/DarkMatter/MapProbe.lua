-- 0.4.7 /dm mapprobe: READ-ONLY check of the map APIs the Map tab plan needs (dark-matter-map-plan.md, section 8).
-- It only asks the game questions: it never sets or clears a waypoint, never touches WorldMapFrame (type checks only),
-- registers nothing and hooks nothing. Every call is feature-detected and pcall'd.
-- Output: short numbered lines ("map 1" .. "map 14") so a chat screenshot is easy to read, plus a SavedVariables copy
-- in DarkMatterDB.mapprobe (last run + the last 6 runs, so a zone run and a city/dungeon run are both kept).
local _, NS = ...
local MP = {}
NS.MapProbe = MP

-- dotted name -> function or table in _G (nil when missing)
local function Get(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end
local function Fn(path) local f = Get(path) if type(f) == "function" then return f end end
local function Call(path, ...) local f = Fn(path) if not f then return end local r = { pcall(f, ...) } if r[1] then return select(2, unpack(r)) end end
local function YN(v) return v and "yes" or "no" end
local function Pct(v) return v and string.format("%.1f", v * 100) or "?" end
local function R2(v) return type(v) == "number" and string.format("%.2f", v) or "?" end

MP.API = {
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo", "C_Map.GetMapChildrenInfo",
  "C_Map.GetMapArtLayers", "C_Map.GetMapArtLayerTextures", "C_Map.GetMapRectOnMap", "C_Map.GetWorldPosFromMapPos",
  "C_Map.GetMapPosFromWorldPos", "C_Map.GetMapLevels", "C_Map.GetFallbackWorldMapID", "C_MapExplorationInfo.GetExploredMapTextures",
  "C_Map.CanSetUserWaypointOnMap", "C_Map.SetUserWaypoint", "C_Map.ClearUserWaypoint", "C_Map.HasUserWaypoint", "C_Map.GetUserWaypoint",
  "C_SuperTrack.SetSuperTrackedUserWaypoint", "C_SuperTrack.IsSuperTrackingUserWaypoint", "C_Navigation.GetDistance", "C_Navigation.GetFrame",
  "C_QuestLog.GetQuestsOnMap", "QuestPOIGetIconInfo", "C_TaxiMap.GetAllTaxiNodes",
  "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "SendChatMessage", "CreateVector2D", "UiMapPoint.CreateFromCoordinates",
}

-- map type number -> word (Enum.UIMapType when present, else the usual numbers)
local TYPES = { [0] = "cosmic", [1] = "world", [2] = "continent", [3] = "zone", [4] = "dungeon", [5] = "micro", [6] = "orphan" }
local function TypeName(t)
  local E = type(Enum) == "table" and Enum.UIMapType
  if type(E) == "table" then for k, v in pairs(E) do if v == t then return k:lower() end end end
  return TYPES[t] or tostring(t)
end
local function T(name, fallback)
  local E = type(Enum) == "table" and Enum.UIMapType
  return type(E) == "table" and type(E[name]) == "number" and E[name] or fallback
end

local function Info(id)
  local i = id and Call("C_Map.GetMapInfo", id)
  return type(i) == "table" and i or nil
end
local function Label(id) local i = Info(id) return i and string.format("%s (%s)", tostring(i.name), tostring(id)) or ("? (" .. tostring(id) .. ")") end

-- list -> several short lines ("present: a, b, c"), each at most ~72 characters
local function Chunk(lines, tag, list)
  if #list == 0 then lines[#lines + 1] = tag .. "none" return end
  local cur = ""
  for _, item in ipairs(list) do
    if cur ~= "" and #tag + #cur + 2 + #item > 72 then lines[#lines + 1] = tag .. cur cur = "" end
    cur = cur == "" and item or (cur .. ", " .. item)
  end
  if cur ~= "" then lines[#lines + 1] = tag .. cur end
end

local function ArtLine(id)
  local layers = Call("C_Map.GetMapArtLayers", id)
  if type(layers) ~= "table" or #layers == 0 then return "no art layers" end
  local L = layers[1]
  local tw, th = tonumber(L.tileWidth) or 256, tonumber(L.tileHeight) or 256
  local lw, lh = tonumber(L.layerWidth), tonumber(L.layerHeight)
  local cols = lw and math.ceil(lw / tw) or "?"
  local rows = lh and math.ceil(lh / th) or "?"
  local tex = Call("C_Map.GetMapArtLayerTextures", id, 1)
  return string.format("%d layer(s); %sx%s tiles of %s, %s textures, %sx%s px", #layers, tostring(cols), tostring(rows), tostring(tw),
    type(tex) == "table" and #tex or "?", tostring(lw), tostring(lh))
end

local function Run()
  local lines, have, miss, data = {}, {}, {}, {}
  for _, a in ipairs(MP.API) do if Fn(a) then have[#have + 1] = a else miss[#miss + 1] = a end end
  data.have, data.missing = have, miss
  lines[#lines + 1] = "mapprobe 0.4.7 (read-only)"
  lines[#lines + 1] = string.format("map 1: %d of %d map APIs present", #have, #MP.API)
  -- chat shows only what is MISSING, grouped by namespace (the full present list is in DarkMatterDB.mapprobe)
  local groups, order = {}, {}
  for _, a in ipairs(miss) do
    local ns, short = a:match("^(.*)%.([^%.]+)$")
    ns, short = ns or "global", short or a
    if not groups[ns] then groups[ns] = {} order[#order + 1] = ns end
    table.insert(groups[ns], short)
  end
  if #order == 0 then lines[#lines + 1] = "map 1 missing: none" end
  for _, ns in ipairs(order) do Chunk(lines, "map 1 missing " .. ns .. ": ", groups[ns]) end

  -- 2: where am I
  local here = Call("C_Map.GetBestMapForUnit", "player")
  local hi = Info(here)
  local pos = here and Call("C_Map.GetPlayerMapPosition", here, "player")
  local px, py
  if type(pos) == "table" then
    if type(pos.GetXY) == "function" then local ok, a, b = pcall(pos.GetXY, pos) if ok then px, py = a, b end end
    px, py = px or pos.x, py or pos.y
  end
  data.mapID, data.x, data.y = here, px, py
  data.mapName, data.mapType = hi and hi.name, hi and hi.mapType
  lines[#lines + 1] = string.format("map 2: you: map %s \"%s\" (%s)", tostring(here), tostring(hi and hi.name), hi and TypeName(hi.mapType) or "?")
  lines[#lines + 1] = px and string.format("map 2 pos: %s, %s", Pct(px), Pct(py)) or "map 2 pos: not available here (instance or no API)"

  -- 3: the tree up to the top
  local chain, id, guard = {}, here, 0
  local world, continent
  while id and id ~= 0 and guard < 10 do
    local i = Info(id)
    if not i then break end
    chain[#chain + 1] = string.format("%s (%s, %s)", tostring(i.name), tostring(id), TypeName(i.mapType))
    if i.mapType == T("Continent", 2) and not continent then continent = id end
    if i.mapType == T("World", 1) or i.mapType == T("Cosmic", 0) then world = world or id end
    id, guard = i.parentMapID, guard + 1
  end
  data.chain, data.continent, data.world = chain, continent, world
  if #chain == 0 then lines[#lines + 1] = "map 3: tree: not available"
  else
    for i, c in ipairs(chain) do lines[#lines + 1] = (i == 1 and "map 3: tree: " or "map 3   > ") .. c end
  end
  if not world then
    local fb = Call("C_Map.GetFallbackWorldMapID")
    if fb then world = fb data.world = fb lines[#lines + 1] = "map 3 world (fallback): " .. Label(fb) end
  end

  -- 4: continents under the world, with zone counts
  local conts = {}
  if world then
    local kids = Call("C_Map.GetMapChildrenInfo", world, T("Continent", 2))
    if type(kids) == "table" then
      for _, k in ipairs(kids) do
        if type(k) == "table" and (k.mapType == nil or k.mapType == T("Continent", 2)) then
          local zones = Call("C_Map.GetMapChildrenInfo", k.mapID, T("Zone", 3))
          conts[#conts + 1] = string.format("%s (%s, %s zones)", tostring(k.name), tostring(k.mapID), type(zones) == "table" and #zones or "?")
        end
      end
    end
  end
  data.continents = conts
  if #conts == 0 then lines[#lines + 1] = "map 4: continents: none found under the world map"
  else for i, c in ipairs(conts) do lines[#lines + 1] = (i == 1 and "map 4: continents: " or "map 4   ") .. c end end

  -- 5: map art at each level, explored overlays here
  data.art = {}
  if here then data.art.zone = ArtLine(here) lines[#lines + 1] = "map 5: art here: " .. data.art.zone end
  if continent then data.art.continent = ArtLine(continent) lines[#lines + 1] = "map 5: art continent: " .. data.art.continent end
  if world then data.art.world = ArtLine(world) lines[#lines + 1] = "map 5: art world: " .. data.art.world end
  local ex = here and Call("C_MapExplorationInfo.GetExploredMapTextures", here)
  data.explored = type(ex) == "table" and #ex or nil
  lines[#lines + 1] = "map 5: explored overlays here: " .. (type(ex) == "table" and #ex or "n/a")

  -- 6: where this map sits on its continent / the world (the seamless-stitch test)
  local function RectLine(a, b)
    local x1, x2, y1, y2 = Call("C_Map.GetMapRectOnMap", a, b)
    if type(x1) ~= "number" then return "not available" end
    return string.format("x %s-%s, y %s-%s", R2(x1), R2(x2), R2(y1), R2(y2))
  end
  if here and continent and here ~= continent then data.rectOnContinent = RectLine(here, continent) lines[#lines + 1] = "map 6: rect here on continent: " .. data.rectOnContinent end
  if continent and world then data.rectOnWorld = RectLine(continent, world) lines[#lines + 1] = "map 6: rect continent on world: " .. data.rectOnWorld end
  if not (here and continent) then lines[#lines + 1] = "map 6: rect: no continent above this map" end

  -- 7: world positions (yards) -> distances; the size of this map in yards
  local function World(mapID, x, y)
    local V = Fn("CreateVector2D")
    local v
    if V then local ok, r = pcall(V, x, y) if ok and type(r) == "table" then v = r end end
    v = v or { x = x, y = y }
    local cont, wp = Call("C_Map.GetWorldPosFromMapPos", mapID, v)
    if type(wp) ~= "table" then return end
    local wx, wy = wp.x, wp.y
    if type(wp.GetXY) == "function" then local ok, a, b = pcall(wp.GetXY, wp) if ok then wx, wy = a, b end end
    return cont, wx, wy
  end
  local c0, ax, ay, bx, by
  if here then c0, ax, ay = World(here, 0, 0) local _ _, bx, by = World(here, 1, 1) end
  if type(ax) == "number" and type(bx) == "number" then
    data.yardsW, data.yardsH = math.abs(bx - ax), math.abs(by - ay)
    lines[#lines + 1] = string.format("map 7: world pos: yes (instance %s); this map is %d x %d yd", tostring(c0), math.floor(data.yardsW + 0.5), math.floor(data.yardsH + 0.5))
  else
    lines[#lines + 1] = "map 7: world pos: not available"
  end

  -- 8: level range
  local l1, l2
  if here then l1, l2 = Call("C_Map.GetMapLevels", here) end
  data.levels = l1 and { l1, l2 } or nil
  lines[#lines + 1] = "map 8: levels: " .. ((type(l1) == "number" and l1 > 0) and (l1 .. "-" .. tostring(l2)) or "not provided")

  -- 9: waypoint / minimap pointing (queries only; nothing is set or cleared)
  local can = here and Call("C_Map.CanSetUserWaypointOnMap", here)
  data.waypoint = { set = Fn("C_Map.SetUserWaypoint") ~= nil, canHere = can == true, has = Call("C_Map.HasUserWaypoint") == true,
    superTrack = Fn("C_SuperTrack.SetSuperTrackedUserWaypoint") ~= nil, nav = Fn("C_Navigation.GetDistance") ~= nil }
  lines[#lines + 1] = string.format("map 9: waypoint API %s; allowed here %s; one set now %s",
    YN(data.waypoint.set), Fn("C_Map.CanSetUserWaypointOnMap") and YN(data.waypoint.canHere) or "?", YN(data.waypoint.has))
  lines[#lines + 1] = string.format("map 9: super-track %s; navigation %s", YN(data.waypoint.superTrack), YN(data.waypoint.nav))

  -- 10: quest markers
  local qs = here and Call("C_QuestLog.GetQuestsOnMap", here)
  data.questsOnMap = type(qs) == "table" and #qs or nil
  lines[#lines + 1] = "map 10: quests on this map: " .. (type(qs) == "table" and (#qs .. " (GetQuestsOnMap)") or "no quest-POI list")
    .. "; QuestPOIGetIconInfo " .. YN(Fn("QuestPOIGetIconInfo"))

  -- 11: drawing support (method checks on a frame that already exists; nothing is created)
  local P = UIParent
  data.createLine = type(P) == "table" and type(P.CreateLine) == "function"
  lines[#lines + 1] = "map 11: drawing: CreateLine " .. YN(data.createLine) .. "; CreateTexture " .. YN(type(P) == "table" and type(P.CreateTexture) == "function")

  -- 12: sharing
  lines[#lines + 1] = string.format("map 12: share: addon messages %s; chat %s", YN(Fn("C_ChatInfo.SendAddonMessage")), YN(Fn("SendChatMessage")))

  -- 13: other map addons that are loaded
  local maps = {}
  local n = Call("C_AddOns.GetNumAddOns") or Call("GetNumAddOns") or 0
  for i = 1, tonumber(n) or 0 do
    local name = Call("C_AddOns.GetAddOnInfo", i) or Call("GetAddOnInfo", i)
    if type(name) == "string" then
      local low = name:lower()
      if low:find("map") or low == "tomtom" or low:find("questie") or low == "magnify" then
        local loaded = Call("C_AddOns.IsAddOnLoaded", name)
        if loaded == nil then loaded = Call("IsAddOnLoaded", name) end
        if loaded then maps[#maps + 1] = name end
      end
    end
  end
  data.mapAddons = maps
  Chunk(lines, "map 13: map addons loaded: ", maps)

  -- 14: the game's map window (type checks only; never opened or changed)
  local W = _G.WorldMapFrame
  lines[#lines + 1] = string.format("map 14: WorldMapFrame %s; ScrollContainer %s; MapCanvasMixin %s", YN(type(W) == "table"),
    YN(type(W) == "table" and type(W.ScrollContainer) == "table"), YN(type(_G.MapCanvasMixin) == "table"))
  return lines, data
end

function MP.Report()
  local ok, lines, data = pcall(Run)
  if not ok then lines, data = { "mapprobe failed: " .. tostring(lines) }, {} end
  local when = (type(date) == "function" and select(2, pcall(date, "%Y-%m-%d %H:%M"))) or "?"
  lines[#lines + 1] = "mapprobe saved to DarkMatterDB.mapprobe (written on /reload or logout)"
  if NS.db then
    local db = NS.db.mapprobe or {}
    local run = { when = when, version = NS.version, lines = lines, data = data }
    db.last = run
    db.runs = db.runs or {}
    table.insert(db.runs, 1, run)
    while #db.runs > 6 do table.remove(db.runs) end
    NS.db.mapprobe = db
  end
  return lines, data
end
