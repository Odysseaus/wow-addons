local _, NS = ...

-- P1 live quest log. 0.2.7: ChainData.lua GPL fallback (QuestieDB Forever),
-- no fake 1/1 (show — + objective %), closest-checked focus (recomputed on move),
-- GetQuestUiMapID for quest area. C_QuestLine still tried first.
-- 0.2.6: chain step index + chain progress (C_QuestLine), checked-chain focus.
-- 0.2.5: status.count is the quest total (rewards stay on rewardsText).
-- 0.2.4: item reward IDs for tooltips; 0.2.3 focus/rewards/type
-- Prefer Classic/Forever APIs; every Blizzard call is type-checked and pcalled.

NS.questList = NS.questList or {}
NS.selectedQuestIndex = NS.selectedQuestIndex or 1
NS.liveRoute = NS.liveRoute or nil
NS.forceMock = NS.forceMock or false
NS.focusCandidates = NS.focusCandidates or {}

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, k, l, m = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g, h, i, j, k, l, m
end

local function ZoneName()
  local z = SafeCall(GetRealZoneText) or SafeCall(GetZoneText) or SafeCall(GetMinimapZoneText)
  if type(z) == "string" and z ~= "" then return z end
  return "?"
end

local function HasCQuestLog()
  return type(C_QuestLog) == "table"
end

-- Known instance tag ids (Enum.QuestTag). String fallback is "dungeon" only;
-- outdoor group size (suggestedGroup) is NOT enough to call a quest a Dungeon.
local DUNGEON_TAG_IDS = {
  [81] = true, -- Dungeon
  [62] = true, -- Raid
  [88] = true, -- Raid10
  [89] = true, -- Raid25
}

local function AbsorbEnumTags()
  if type(Enum) ~= "table" or type(Enum.QuestTag) ~= "table" then return end
  local names = { "Dungeon", "Raid", "Raid10", "Raid25" }
  local i
  for i = 1, #names do
    local v = Enum.QuestTag[names[i]]
    if type(v) == "number" then DUNGEON_TAG_IDS[v] = true end
  end
end

local function TagIsDungeon(tag)
  if type(tag) == "number" then
    return DUNGEON_TAG_IDS[tag] == true
  end
  if type(tag) == "string" then
    if string.find(string.lower(tag), "dungeon", 1, true) then return true end
    local n = tonumber(tag)
    if n and DUNGEON_TAG_IDS[n] then return true end
  end
  return false
end

local function TagFromInfoTable(t)
  if type(t) ~= "table" then return false end
  if TagIsDungeon(t.tagName) or TagIsDungeon(t.tagID) or TagIsDungeon(t.tag) then
    return true
  end
  if TagIsDungeon(t.questTag) or TagIsDungeon(t.questType) or TagIsDungeon(t.name) or TagIsDungeon(t.type) then
    return true
  end
  return false
end

-- 0..1 (and not both zero) = normalized map. Anything larger is world yards.
local function ClassifyXY(x, y)
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  if x == 0 and y == 0 then return nil end
  if math.abs(x) <= 1 and math.abs(y) <= 1 then return "map", x, y end
  return "world", x, y
end

local function VecXY(pos)
  if type(pos) ~= "table" then return nil, nil end
  if type(pos.GetXY) == "function" then
    local ok, x, y = pcall(pos.GetXY, pos)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
  end
  if type(pos.x) == "number" and type(pos.y) == "number" then
    return pos.x, pos.y
  end
  return nil, nil
end

local function WorldToNorm(wx, wy, mapID)
  if type(wx) ~= "number" or type(wy) ~= "number" then return nil, nil, nil end
  if type(C_Map) ~= "table" or type(C_Map.GetMapPosFromWorldPos) ~= "function" then
    return nil, nil, nil
  end
  local ids = {}
  local function add(id)
    if type(id) ~= "number" or id == 0 then return end
    local i
    for i = 1, #ids do
      if ids[i] == id then return end
    end
    ids[#ids + 1] = id
  end
  add(mapID)
  if type(C_Map.GetBestMapForUnit) == "function" then
    add(SafeCall(C_Map.GetBestMapForUnit, "player"))
  end
  if type(C_Map.GetFallbackWorldMapID) == "function" then
    add(SafeCall(C_Map.GetFallbackWorldMapID))
  end

  local function accept(pos, ui)
    local x, y = VecXY(pos)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    if x < 0 or y < 0 or x > 1 or y > 1 then return nil end
    if x == 0 and y == 0 then return nil end
    return x, y, ui
  end

  local function attempt(id, x, y)
    local vec = { x = x, y = y }
    if type(CreateVector2D) == "function" then
      local created = SafeCall(CreateVector2D, x, y)
      if type(created) == "table" then vec = created end
    end
    local ok, a, b = pcall(C_Map.GetMapPosFromWorldPos, id, vec)
    if not ok then return nil end
    if type(b) == "table" then
      local nx, ny, mid = accept(b, type(a) == "number" and a or id)
      if nx then return nx, ny, mid end
    end
    if type(a) == "table" then
      local nx, ny = accept(a, id)
      if nx then return nx, ny, id end
    end
    return nil
  end

  local i
  for i = 1, #ids do
    local nx, ny, mid = attempt(ids[i], wx, wy)
    if nx then return nx, ny, mid end
  end
  local ok, a = pcall(C_Map.GetMapPosFromWorldPos, { x = wx, y = wy })
  if ok and type(a) == "table" then
    local nx, ny = accept(a, mapID)
    if nx then return nx, ny, mapID end
  end
  return nil, nil, nil
end

NS.WorldToMapNorm = function(wx, wy, mapID)
  return WorldToNorm(wx, wy, mapID)
end

function NS.GetPlayerPositions()
  local pos = {
    worldX = nil,
    worldY = nil,
    worldMapID = nil,
    mapX = nil,
    mapY = nil,
    mapID = nil,
  }
  if type(UnitPosition) == "function" then
    local y, x, _, mapID = SafeCall(UnitPosition, "player")
    if type(x) == "number" and type(y) == "number" then
      pos.worldX, pos.worldY, pos.worldMapID = x, y, mapID
    end
  end
  local mapID
  if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
    mapID = SafeCall(C_Map.GetBestMapForUnit, "player")
    if type(mapID) == "number" then pos.mapID = mapID end
  end
  if pos.mapID and type(C_Map) == "table" and type(C_Map.GetPlayerMapPosition) == "function" then
    local p = SafeCall(C_Map.GetPlayerMapPosition, pos.mapID, "player")
    local x, y = VecXY(p)
    if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then
      pos.mapX, pos.mapY = x, y
    end
  end
  if not pos.mapX and type(GetPlayerMapPosition) == "function" then
    local x, y = SafeCall(GetPlayerMapPosition, "player")
    if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
      pos.mapX, pos.mapY = x, y
    end
  end
  -- Player yards → normalized so a map-space POI still has a distance.
  if not pos.mapX and pos.worldX then
    local mx, my, mid = WorldToNorm(pos.worldX, pos.worldY, pos.mapID or pos.worldMapID)
    if mx then
      pos.mapX, pos.mapY = mx, my
      if type(mid) == "number" then pos.mapID = mid end
    end
  end
  return pos
end

function NS.GetPlayerMapPosition()
  local pos = NS.GetPlayerPositions()
  if pos.worldX and pos.worldY then
    return pos.worldX, pos.worldY, pos.worldMapID, "world"
  end
  if pos.mapX and pos.mapY then
    return pos.mapX, pos.mapY, pos.mapID, "map"
  end
  return nil, nil, nil, nil
end

local function GetNumEntries()
  if HasCQuestLog() and type(C_QuestLog.GetNumQuestLogEntries) == "function" then
    local n = SafeCall(C_QuestLog.GetNumQuestLogEntries)
    if type(n) == "number" then return n end
  end
  local n = SafeCall(GetNumQuestLogEntries)
  return type(n) == "number" and n or 0
end

local function GetObjectivesModern(questID)
  local objs = {}
  if HasCQuestLog() and type(C_QuestLog.GetQuestObjectives) == "function" then
    local list = SafeCall(C_QuestLog.GetQuestObjectives, questID)
    if type(list) == "table" then
      local i
      for i = 1, #list do
        local o = list[i]
        if type(o) == "table" then
          objs[#objs + 1] = {
            text = o.text or "",
            finished = o.finished and true or false,
            numFulfilled = o.numFulfilled or 0,
            numRequired = o.numRequired or 0,
          }
        end
      end
    end
  end
  return objs
end

local function GetObjectivesLegacy(logIndex)
  local objs = {}
  local n = SafeCall(GetNumQuestLeaderBoards, logIndex) or 0
  if type(n) ~= "number" then n = 0 end
  local i
  for i = 1, n do
    local text, objectiveType, finished = SafeCall(GetQuestLogLeaderBoard, i, logIndex)
    if text then
      local fulfilled, required = 0, 0
      local a, b = string.match(text, "(%d+)%s*/%s*(%d+)")
      if a and b then
        fulfilled = tonumber(a) or 0
        required = tonumber(b) or 0
      end
      objs[#objs + 1] = {
        text = text,
        finished = finished and true or false,
        numFulfilled = fulfilled,
        numRequired = required,
        objectiveType = objectiveType,
      }
    end
  end
  return objs
end

local function PlayerMapID()
  if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
    local id = SafeCall(C_Map.GetBestMapForUnit, "player")
    if type(id) == "number" then return id end
  end
  return nil
end

local function MakePOI(x, y, mapID)
  local kind, nx, ny = ClassifyXY(x, y)
  if not kind then return nil end
  local poi = { mapID = mapID }
  if kind == "world" then
    poi.worldX, poi.worldY = nx, ny
    poi.worldMapID = mapID
    local mx, my, mid = WorldToNorm(nx, ny, mapID)
    if mx then
      poi.mapX, poi.mapY = mx, my
      poi.mapID = mid or mapID
    end
  else
    poi.mapX, poi.mapY = nx, ny
  end
  return poi
end

local function IsMapID(v)
  return type(v) == "number" and v >= 1 and v == math.floor(v)
end

local function NormPair(x, y)
  return type(x) == "number" and type(y) == "number"
    and math.abs(x) <= 1 and math.abs(y) <= 1
    and not (x == 0 and y == 0)
end

-- GetNextWaypoint is mapID, x, y. QuestPOI is often (completed, x, y), (x, y),
-- or (x, y, mapID) when x,y are already normalized.
local function POIFromWaypoint(a, b, c)
  if (a == nil or type(a) == "boolean") and type(b) == "number" and type(c) == "number" then
    return MakePOI(b, c, nil)
  end
  if type(a) ~= "number" or type(b) ~= "number" then return nil end
  if type(c) ~= "number" then
    return MakePOI(a, b, nil)
  end
  if NormPair(a, b) then
    return MakePOI(a, b, IsMapID(c) and c or nil)
  end
  if NormPair(b, c) or math.abs(b) > 1 or math.abs(c) > 1 then
    return MakePOI(b, c, IsMapID(a) and a or nil)
  end
  return MakePOI(a, b, IsMapID(c) and c or nil)
end

local function QuestAreaID(questID, logIndex)
  local area
  -- Forever: GetQuestUiMapID(questID) is the modern map id for a quest.
  if type(questID) == "number" and type(GetQuestUiMapID) == "function" then
    local a = SafeCall(GetQuestUiMapID, questID)
    if type(a) == "number" and a > 0 then area = a end
  end
  if type(questID) == "number" and type(GetQuestWorldMapAreaID) == "function" then
    local a = SafeCall(GetQuestWorldMapAreaID, questID)
    if type(a) == "number" and a > 0 then area = a end
  end
  if type(GetQuestLogWorldMapAreaID) == "function" then
    local a
    if type(questID) == "number" then a = SafeCall(GetQuestLogWorldMapAreaID, questID) end
    if type(a) ~= "number" and type(logIndex) == "number" then
      a = SafeCall(GetQuestLogWorldMapAreaID, logIndex)
    end
    if type(a) == "number" and a > 0 then area = a end
  end
  return area
end

-- 0.2.7 quest chains. Try C_QuestLine first (live Forever API). On miss, fall
-- back to shipped ChainData.lua (QuestieDB Forever, GPL-3.0). Hits are cached;
-- API misses retry after CHAIN_RETRY seconds (or on QUESTLINE_UPDATE).
local CHAIN_RETRY = 15
local chainCache = {}
local chainRequested = {}
local completedSet = nil
local completedSetAt = 0

local function NowSec()
  local t = SafeCall(GetTime)
  if type(t) == "number" then return t end
  return 0
end

local function HasQuestLineAPI()
  return type(C_QuestLine) == "table" and type(C_QuestLine.GetQuestLineInfo) == "function"
    and type(C_QuestLine.GetQuestLineQuests) == "function"
end

local function ReadQuestLine(questID, mapID)
  local info = SafeCall(C_QuestLine.GetQuestLineInfo, questID, mapID)
  if type(info) ~= "table" or type(info.questLineID) ~= "number" or info.questLineID <= 0 then
    return nil
  end
  local ids = SafeCall(C_QuestLine.GetQuestLineQuests, info.questLineID)
  if type(ids) ~= "table" or #ids < 1 then return nil end
  local quests, pos = {}, nil
  local i
  for i = 1, #ids do
    local id = ids[i]
    if type(id) == "number" then
      quests[#quests + 1] = id
      if id == questID then pos = #quests end
    end
  end
  if #quests < 1 then return nil end
  return {
    lineID = info.questLineID,
    name = type(info.questLineName) == "string" and info.questLineName or nil,
    quests = quests,
    pos = pos,
    source = "api",
  }
end

local function ReadChainData(questID)
  if type(questID) ~= "number" or type(NS.ChainByQuest) ~= "table" then return nil end
  local meta = NS.ChainByQuest[questID]
  if type(meta) ~= "table" or type(meta.chainId) ~= "number" then return nil end
  local list = NS.ChainLists and NS.ChainLists[meta.chainId]
  if type(list) ~= "table" or #list < 1 then return nil end
  return {
    lineID = meta.chainId,
    name = nil,
    quests = list,
    pos = meta.step,
    source = "chaindata",
  }
end

function NS.GetQuestChain(questID, mapHint)
  if type(questID) ~= "number" then return nil end
  local now = NowSec()
  local c = chainCache[questID]
  if c then
    if c.lineID then return c end
    -- Miss cache: allow ChainData immediately; retry C_QuestLine after CHAIN_RETRY.
    local fallback = ReadChainData(questID)
    if fallback then
      chainCache[questID] = fallback
      return fallback
    end
    if (now - (c.at or 0)) < CHAIN_RETRY then return nil end
  end

  if HasQuestLineAPI() then
    local maps = {}
    local function add(id)
      if type(id) ~= "number" or id <= 0 then return end
      local i
      for i = 1, #maps do if maps[i] == id then return end end
      maps[#maps + 1] = id
    end
    add(mapHint)
    add(PlayerMapID())
    add(QuestAreaID(questID, nil))
    local found = ReadQuestLine(questID, nil)
    local i
    for i = 1, #maps do
      if found then break end
      found = ReadQuestLine(questID, maps[i])
    end
    if found then
      chainCache[questID] = found
      return found
    end
    if type(C_QuestLine.RequestQuestLinesForMap) == "function" then
      for i = 1, #maps do
        if not chainRequested[maps[i]] then
          chainRequested[maps[i]] = true
          SafeCall(C_QuestLine.RequestQuestLinesForMap, maps[i])
        end
      end
    end
  end

  local fallback = ReadChainData(questID)
  if fallback then
    chainCache[questID] = fallback
    return fallback
  end
  chainCache[questID] = { at = now }
  return nil
end

local function ClearChainMisses()
  local k, v
  for k, v in pairs(chainCache) do
    if not v.lineID then chainCache[k] = nil end
  end
end
NS.ClearChainMisses = ClearChainMisses

local function RefreshCompletedSet(force)
  local now = NowSec()
  if completedSet and not force and (now - completedSetAt) < 30 then
    return completedSet
  end
  local set = {}
  if HasCQuestLog() and type(C_QuestLog.GetAllCompletedQuestIDs) == "function" then
    local ids = SafeCall(C_QuestLog.GetAllCompletedQuestIDs)
    if type(ids) == "table" then
      local i, id
      for i, id in ipairs(ids) do
        if type(id) == "number" then set[id] = true end
      end
      if not next(set) then
        for i, id in pairs(ids) do
          if type(i) == "number" and type(id) == "number" then set[id] = true
          elseif type(id) == "boolean" and id and type(i) == "number" then set[i] = true end
        end
      end
    end
  end
  completedSet = set
  completedSetAt = now
  return set
end

local function FlaggedComplete(questID)
  if type(questID) ~= "number" then return false end
  local set = RefreshCompletedSet(false)
  if set[questID] then return true end
  if HasCQuestLog() and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" then
    local v = SafeCall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if v == true then
      set[questID] = true
      return true
    end
  end
  if type(IsQuestFlaggedCompleted) == "function" then
    local v = SafeCall(IsQuestFlaggedCompleted, questID)
    if v == true or v == 1 then
      set[questID] = true
      return true
    end
  end
  return false
end

local function ObjectiveFrac(quest)
  if type(quest) ~= "table" then return 0 end
  local objs = quest.objectives
  if type(objs) ~= "table" or #objs < 1 then
    return quest.complete and 1 or 0
  end
  local got, need = 0, 0
  local i
  for i = 1, #objs do
    local o = objs[i]
    local req = tonumber(o.numRequired) or 0
    if req < 1 then req = 1 end
    local ful = tonumber(o.numFulfilled) or 0
    if o.finished then ful = req end
    if ful > req then ful = req end
    got = got + ful
    need = need + req
  end
  if need < 1 then return quest.complete and 1 or 0 end
  local f = got / need
  if f < 0 then f = 0 end
  if f > 1 then f = 1 end
  return f
end

-- Step index / total / steps done for the focused quest. No chain data → noChain
-- (UI shows "—"); progress bar uses objective progress instead of a fake 1/1.
function NS.ChainProgress(quest)
  local out = { index = nil, total = nil, done = 0, frac = 0, name = nil, lineID = nil, noChain = true }
  if type(quest) ~= "table" then return out end
  local c = NS.GetQuestChain(quest.questID, quest.targetMapID)
  if not c or type(c.quests) ~= "table" or #c.quests < 1 then
    out.frac = ObjectiveFrac(quest)
    out.done = quest.complete and 1 or 0
    return out
  end
  local total = #c.quests
  local done = 0
  local i
  for i = 1, total do
    local id = c.quests[i]
    if id == quest.questID then
      if quest.complete or FlaggedComplete(id) then done = done + 1 end
    elseif FlaggedComplete(id) then
      done = done + 1
    end
  end
  if done > total then done = total end
  out.noChain = false
  out.total = total
  out.index = c.pos or 1
  out.done = done
  out.frac = total > 0 and (done / total) or 0
  out.name = c.name
  out.lineID = c.lineID
  return out
end

local function TrySuperTrack(questID)
  if type(questID) ~= "number" then return nil end
  local st
  if type(C_SuperTrack) == "table" and type(C_SuperTrack.GetSuperTrackedQuestID) == "function" then
    st = SafeCall(C_SuperTrack.GetSuperTrackedQuestID)
  end
  if type(st) ~= "number" and type(GetSuperTrackedQuestID) == "function" then
    st = SafeCall(GetSuperTrackedQuestID)
  end
  if st ~= questID then return nil end
  if type(C_SuperTrack) == "table" and type(C_SuperTrack.GetSuperTrackedPosition) == "function" then
    local a, b, c = SafeCall(C_SuperTrack.GetSuperTrackedPosition)
    local poi = POIFromWaypoint(a, b, c)
    if poi then return poi end
  end
  return nil
end

local function TryTaskInfo(questID)
  if type(questID) ~= "number" or type(QuestMapGetTaskInfo) ~= "function" then return nil end
  local a, b, c, d = SafeCall(QuestMapGetTaskInfo, questID)
  return POIFromWaypoint(a, b, c) or POIFromWaypoint(b, c, d) or POIFromWaypoint(a, b, d)
end

-- Best-effort objective position. Forever often has no POI; callers must tolerate nil.
function NS.TryQuestPOI(questID, logIndex)
  local area = QuestAreaID(questID, logIndex)
  local playerMap = PlayerMapID()

  if type(questID) == "number" and HasCQuestLog() and type(C_QuestLog.GetNextWaypoint) == "function" then
    local mapID, x, y = SafeCall(C_QuestLog.GetNextWaypoint, questID)
    local poi = POIFromWaypoint(mapID, x, y)
    if poi then
      if not poi.mapID and area then poi.mapID = area end
      return poi
    end
  end

  if type(questID) == "number" and HasCQuestLog() and type(C_QuestLog.GetNextWaypointForMap) == "function" then
    local maps = { playerMap, area }
    local i
    for i = 1, #maps do
      if type(maps[i]) == "number" then
        local x, y = SafeCall(C_QuestLog.GetNextWaypointForMap, questID, maps[i])
        local poi = MakePOI(x, y, maps[i])
        if poi then return poi end
      end
    end
  end

  if type(questID) == "number" and HasCQuestLog() and type(C_QuestLog.GetQuestsOnMap) == "function" then
    local maps = { playerMap, area }
    local mi
    for mi = 1, #maps do
      if type(maps[mi]) == "number" then
        local list = SafeCall(C_QuestLog.GetQuestsOnMap, maps[mi])
        if type(list) == "table" then
          local i
          for i = 1, #list do
            local e = list[i]
            if type(e) == "table" and e.questID == questID then
              local poi = MakePOI(e.x, e.y, maps[mi])
              if poi then return poi end
            end
          end
        end
      end
    end
  end

  if type(questID) == "number" and type(C_TaskQuest) == "table" and type(C_TaskQuest.GetQuestLocation) == "function" then
    local maps = { playerMap, area }
    local i
    for i = 1, #maps do
      if type(maps[i]) == "number" then
        local x, y = SafeCall(C_TaskQuest.GetQuestLocation, questID, maps[i])
        local poi = MakePOI(x, y, maps[i])
        if poi then return poi end
      end
    end
  end

  if type(questID) == "number" and type(QuestPOIGetIconInfo) == "function" then
    local a, b, c = SafeCall(QuestPOIGetIconInfo, questID)
    local poi = POIFromWaypoint(a, b, c) or POIFromWaypoint(b, c, a)
    if poi then return poi end
  end

  local taskPOI = TryTaskInfo(questID)
  if taskPOI then return taskPOI end

  local st = TrySuperTrack(questID)
  if st then return st end

  -- Area id alone cannot place a pin; keep it so a later waypoint call has a map.
  if area then
    return { mapID = area }
  end
  return nil
end

local function ApplyPOI(quest, poi)
  quest.mapX, quest.mapY = nil, nil
  quest.worldX, quest.worldY = nil, nil
  quest.targetX, quest.targetY = nil, nil
  quest.targetCoordKind = nil
  if type(poi) ~= "table" then
    quest.targetMapID = quest.targetMapID
    return
  end
  if type(poi.mapID) == "number" then quest.targetMapID = poi.mapID end
  if type(poi.mapX) == "number" and type(poi.mapY) == "number" then
    quest.mapX, quest.mapY = poi.mapX, poi.mapY
  end
  if type(poi.worldX) == "number" and type(poi.worldY) == "number" then
    quest.worldX, quest.worldY = poi.worldX, poi.worldY
  end
  if quest.worldX then
    quest.targetX, quest.targetY = quest.worldX, quest.worldY
    quest.targetCoordKind = "world"
    quest.targetMapID = poi.worldMapID or quest.targetMapID
  elseif quest.mapX then
    quest.targetX, quest.targetY = quest.mapX, quest.mapY
    quest.targetCoordKind = "map"
  end
end

local function FormatDistance(yards)
  if not yards then return "?" end
  if yards >= 1000 then
    return string.format("%.1fk yd", yards / 1000)
  end
  return string.format("%d yd", math.floor(yards + 0.5))
end

local function Cardinal(deg)
  if not deg then return "unknown" end
  local d = deg % 360
  if d < 0 then d = d + 360 end
  local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
  local idx = math.floor((d + 22.5) / 45) % 8 + 1
  return dirs[idx]
end

local function RelativeBearing(targetDeg)
  if not targetDeg then return "unknown" end
  local facing
  if type(GetPlayerFacing) == "function" then
    facing = SafeCall(GetPlayerFacing)
  end
  if type(facing) ~= "number" then
    return Cardinal(targetDeg)
  end
  local facingDeg = math.deg(facing)
  -- CCW delta (positive = left): bearing is CW, facing is CCW from north.
  local delta = (-targetDeg - facingDeg + 180) % 360 - 180
  local ad = math.abs(delta)
  if ad < 25 then return "ahead"
  elseif ad > 155 then return "behind"
  elseif delta > 0 then return "left"
  else return "right"
  end
end

local function ComputeNav(quest, pos)
  pos = pos or NS.GetPlayerPositions()
  local worldX, worldY = quest.worldX, quest.worldY
  local mapX, mapY = quest.mapX, quest.mapY
  if not worldX and quest.targetCoordKind == "world" then
    worldX, worldY = quest.targetX, quest.targetY
  end
  if not mapX and quest.targetCoordKind == "map" then
    mapX, mapY = quest.targetX, quest.targetY
  end
  if not worldX and not mapX and quest.targetX and quest.targetY then
    local kind, x, y = ClassifyXY(quest.targetX, quest.targetY)
    if kind == "world" then
      worldX, worldY = x, y
    elseif kind == "map" then
      mapX, mapY = x, y
    end
  end
  if worldX and not mapX then
    local mx, my, mid = WorldToNorm(worldX, worldY, quest.targetMapID or pos.mapID or pos.worldMapID)
    if mx then
      mapX, mapY = mx, my
      quest.mapX, quest.mapY = mx, my
      if type(mid) == "number" and not quest.targetMapID then quest.targetMapID = mid end
    end
  end

  local px, py, tx, ty, kind
  if worldX and pos.worldX then
    px, py, tx, ty, kind = pos.worldX, pos.worldY, worldX, worldY, "world"
  elseif mapX and pos.mapX then
    px, py, tx, ty, kind = pos.mapX, pos.mapY, mapX, mapY, "map"
  end

  local zone = ZoneName()
  if not (px and py and tx and ty) then
    return {
      hasCoords = false,
      distanceYards = nil,
      bearingDeg = nil,
      distance = "?",
      bearing = "unknown",
      approx = "no coords",
      zone = zone,
      mapX = mapX,
      mapY = mapY,
      targetX = nil,
      targetY = nil,
      targetCoordKind = nil,
      targetMapID = quest.targetMapID or pos.mapID,
    }
  end

  local dx = tx - px
  local dy = ty - py
  local dist
  if kind == "world" then
    dist = math.sqrt(dx * dx + dy * dy)
  else
    dist = math.sqrt(dx * dx + dy * dy) * 1000
  end
  -- Compass bearing, CW from north (see Route.lua NS.BearingFromDelta).
  -- world: worldX grows north, worldY grows west; map: x east, y south.
  local bearingDeg
  if kind == "world" then
    bearingDeg = math.deg(math.atan2(-dy, dx))
  else
    bearingDeg = math.deg(math.atan2(dx, -dy))
  end
  if bearingDeg < 0 then bearingDeg = bearingDeg + 360 end
  return {
    hasCoords = true,
    distanceYards = dist,
    bearingDeg = bearingDeg,
    distance = FormatDistance(dist),
    bearing = RelativeBearing(bearingDeg),
    approx = "approx.",
    zone = zone,
    targetX = tx,
    targetY = ty,
    targetCoordKind = kind,
    targetMapID = quest.targetMapID or pos.mapID or pos.worldMapID,
    mapX = mapX,
    mapY = mapY,
  }
end

function NS.NormalizeQuestPin(route)
  if type(route) ~= "table" then return nil, nil end
  if type(route.mapX) == "number" and type(route.mapY) == "number" then
    local kind = ClassifyXY(route.mapX, route.mapY)
    if kind == "map" then return route.mapX, route.mapY end
  end
  local wx, wy = route.worldX, route.worldY
  if type(wx) ~= "number" and route.targetCoordKind == "world" then
    wx, wy = route.targetX, route.targetY
  end
  if type(wx) == "number" and type(wy) == "number" then
    local x, y, id = WorldToNorm(wx, wy, route.targetMapID)
    if x then
      route.mapX, route.mapY = x, y
      if type(id) == "number" then route.targetMapID = route.targetMapID or id end
      return x, y
    end
  end
  if route.targetCoordKind ~= "world" and type(route.targetX) == "number" and type(route.targetY) == "number" then
    local kind, x, y = ClassifyXY(route.targetX, route.targetY)
    if kind == "map" then return x, y end
  end
  return nil, nil
end

local function LookupQuestType(quest, info)
  AbsorbEnumTags()
  if TagIsDungeon(quest.questTag) or TagIsDungeon(quest.tagName) or TagIsDungeon(quest.tagID) then
    return "Dungeon"
  end
  if TagFromInfoTable(info) then return "Dungeon" end
  if type(info) == "table" and TagFromInfoTable(info.questTagInfo) then return "Dungeon" end

  local qid = quest.questID
  if type(qid) ~= "number" then return "World" end

  if type(GetQuestTagInfo) == "function" then
    local tagID, tagName = SafeCall(GetQuestTagInfo, qid)
    if type(tagID) == "table" then
      if TagFromInfoTable(tagID) then return "Dungeon" end
    elseif TagIsDungeon(tagID) or TagIsDungeon(tagName) then
      return "Dungeon"
    end
  end
  if HasCQuestLog() and type(C_QuestLog.GetQuestTagInfo) == "function" then
    local tagID, tagName = SafeCall(C_QuestLog.GetQuestTagInfo, qid)
    if type(tagID) == "table" then
      if TagFromInfoTable(tagID) then return "Dungeon" end
    elseif TagIsDungeon(tagID) or TagIsDungeon(tagName) then
      return "Dungeon"
    end
  end
  if HasCQuestLog() and type(C_QuestLog.GetQuestType) == "function" then
    local qt = SafeCall(C_QuestLog.GetQuestType, qid)
    if type(qt) == "table" then
      if TagFromInfoTable(qt) then return "Dungeon" end
    elseif TagIsDungeon(qt) then
      return "Dungeon"
    end
  end
  return "World"
end

local function PushRefresh()
  if NS.PushRefresh then
    NS.PushRefresh()
  else
    NS._refreshing = true
  end
end

local function PopRefresh()
  if NS.PopRefresh then
    NS.PopRefresh()
  else
    NS._refreshing = false
  end
end

-- SelectQuestLogEntry fires QUEST_LOG_UPDATE on some clients. Hold the refresh
-- guard across the select so that event cannot re-enter Refresh.
local function WithLogSelected(logIndex, reader)
  local prev
  if type(GetQuestLogSelection) == "function" then
    prev = SafeCall(GetQuestLogSelection)
  end
  PushRefresh()
  if type(logIndex) == "number" and type(SelectQuestLogEntry) == "function" then
    SafeCall(SelectQuestLogEntry, logIndex)
  end
  local ret = { pcall(reader) }
  if type(prev) == "number" and type(SelectQuestLogEntry) == "function" then
    SafeCall(SelectQuestLogEntry, prev)
  end
  PopRefresh()
  if not ret[1] then return nil end
  return ret[2], ret[3], ret[4], ret[5], ret[6], ret[7], ret[8], ret[9]
end

local function AsQuestID(v)
  if type(v) == "number" and v > 0 then return v end
  return nil
end

local function TitleFields(logIndex)
  local title, level, tagOrGroup, isHeader, isCollapsed, isComplete, frequency, questID =
    SafeCall(GetQuestLogTitle, logIndex)
  local questTag, suggestedGroup, tagID
  if type(tagOrGroup) == "string" then
    -- Vanilla-style: 3rd return is "Dungeon" / "Elite" / "Raid".
    questTag = tagOrGroup
  elseif type(tagOrGroup) == "number" then
    if DUNGEON_TAG_IDS[tagOrGroup] then
      tagID = tagOrGroup
    else
      suggestedGroup = tagOrGroup
    end
  end
  questID = AsQuestID(questID)
  if not questID and HasCQuestLog() and type(C_QuestLog.GetQuestIDForLogIndex) == "function" then
    questID = AsQuestID(SafeCall(C_QuestLog.GetQuestIDForLogIndex, logIndex))
  end
  if not title and type(SelectQuestLogEntry) == "function" then
    local t2, lv2, tag2, header2, _, complete2, freq2, id2 = WithLogSelected(logIndex, function()
      return SafeCall(GetQuestLogTitle, logIndex)
    end)
    if t2 then
      title, level, isHeader, isComplete, frequency = t2, lv2, header2, complete2, freq2
      if type(tag2) == "string" then
        questTag = tag2
      elseif type(tag2) == "number" and not suggestedGroup then
        if DUNGEON_TAG_IDS[tag2] then tagID = tag2 else suggestedGroup = tag2 end
      end
      questID = questID or AsQuestID(id2)
    end
  end
  if not questID and type(SelectQuestLogEntry) == "function" then
    local qid = WithLogSelected(logIndex, function()
      local id
      if type(GetQuestID) == "function" then id = AsQuestID(SafeCall(GetQuestID)) end
      if not id and type(GetQuestLogQuestID) == "function" then
        id = AsQuestID(SafeCall(GetQuestLogQuestID))
      end
      return id
    end)
    questID = questID or qid
  end
  return title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, questTag, tagID
end

local function WatchMaps()
  local byIndex, byID = {}, {}
  if type(GetNumQuestWatches) == "function" and type(GetQuestIndexForWatch) == "function" then
    local n = SafeCall(GetNumQuestWatches) or 0
    if type(n) == "number" then
      local i
      for i = 1, n do
        local idx = SafeCall(GetQuestIndexForWatch, i)
        if type(idx) == "number" then byIndex[idx] = true end
      end
    end
  end
  if HasCQuestLog() and type(C_QuestLog.GetNumQuestWatches) == "function" then
    local getter = C_QuestLog.GetQuestIDForQuestWatchIndex
    if type(getter) ~= "function" then getter = C_QuestLog.GetQuestIDForWatch end
    local n = SafeCall(C_QuestLog.GetNumQuestWatches) or 0
    if type(n) == "number" and type(getter) == "function" then
      local i
      for i = 1, n do
        local id = SafeCall(getter, i)
        if type(id) == "number" then byID[id] = true end
      end
    end
  end
  return byIndex, byID
end

local function EntryWatched(logIndex, questID, byIndex, byID)
  local watched = false
  if type(logIndex) == "number" and byIndex[logIndex] then watched = true end
  if type(questID) == "number" and byID[questID] then watched = true end
  if not watched and type(logIndex) == "number" and type(IsQuestWatched) == "function" then
    local w = SafeCall(IsQuestWatched, logIndex)
    if w == true or w == 1 then watched = true end
  end
  if not watched and type(questID) == "number" and HasCQuestLog() and type(C_QuestLog.GetQuestWatchType) == "function" then
    local wt = SafeCall(C_QuestLog.GetQuestWatchType, questID)
    -- nil = not watched. 0 is a real watch type (Automatic) and must count.
    if wt ~= nil then watched = true end
  end
  return watched
end

-- IsPushableQuest / GetQuestLogPushable is share-state, not the objective tracker.
-- Probed so Forever builds that expose it are tolerated; it does not set `watched`.
local function NotePushable(quest)
  local qid = quest.questID
  local pushable
  if type(qid) == "number" and HasCQuestLog() and type(C_QuestLog.IsPushableQuest) == "function" then
    pushable = SafeCall(C_QuestLog.IsPushableQuest, qid)
  elseif type(qid) == "number" and type(IsPushableQuest) == "function" then
    pushable = SafeCall(IsPushableQuest, qid)
  end
  quest.pushable = (pushable == true or pushable == 1) or false
end

local function NewEntry(fields)
  local poi = NS.TryQuestPOI(fields.questID, fields.logIndex)
  local entry = {
    logIndex = fields.logIndex,
    questID = fields.questID,
    title = fields.title,
    complete = fields.complete and true or false,
    objectives = fields.objectives or {},
    level = fields.level,
    suggestedGroup = fields.suggestedGroup,
    questTag = fields.questTag,
    tagID = fields.tagID,
    tagName = fields.tagName,
    watched = fields.watched and true or false,
    pushable = false,
  }
  ApplyPOI(entry, poi)
  local chain = NS.GetQuestChain(entry.questID, entry.targetMapID)
  entry.chainID = chain and chain.lineID or nil
  entry.questType = LookupQuestType(entry, fields.info)
  entry.questTypeLabel = entry.questType
  NotePushable(entry)
  return entry
end

local function EnumerateModern(byIndex, byID)
  local list = {}
  local n = GetNumEntries()
  local i
  for i = 1, n do
    local info
    if type(C_QuestLog.GetInfo) == "function" then
      info = SafeCall(C_QuestLog.GetInfo, i)
    end
    if type(info) == "table" and not info.isHeader then
      local questID = info.questID
      local title = info.title or ("Quest " .. tostring(questID or i))
      local complete = info.isComplete and true or false
      if type(C_QuestLog.IsComplete) == "function" and questID then
        local c = SafeCall(C_QuestLog.IsComplete, questID)
        if c ~= nil then complete = c and true or false end
      end
      local tag = info.questTag or info.tag or info.tagName
      local tagID = info.tagID
      if type(info.questTagInfo) == "table" then
        tag = tag or info.questTagInfo.tagName
        tagID = tagID or info.questTagInfo.tagID
      end
      list[#list + 1] = NewEntry({
        logIndex = info.questLogIndex or i,
        questID = questID,
        title = title,
        complete = complete,
        objectives = questID and GetObjectivesModern(questID) or {},
        level = info.level,
        suggestedGroup = info.suggestedGroup,
        questTag = tag,
        tagID = tagID,
        tagName = type(tag) == "string" and tag or nil,
        watched = EntryWatched(info.questLogIndex or i, questID, byIndex, byID),
        info = info,
      })
    elseif type(info) ~= "table" then
      return nil
    end
  end
  return list
end

local function EnumerateLegacy(byIndex, byID)
  local list = {}
  local n = GetNumEntries()
  local i
  for i = 1, n do
    local title, level, suggestedGroup, isHeader, _, isComplete, _, questID, questTag, tagID = TitleFields(i)
    if title and not isHeader then
      local complete = (isComplete == 1 or isComplete == true)
      list[#list + 1] = NewEntry({
        logIndex = i,
        questID = questID,
        title = title,
        complete = complete,
        objectives = GetObjectivesLegacy(i),
        level = level,
        suggestedGroup = suggestedGroup,
        questTag = questTag,
        tagID = tagID,
        tagName = questTag,
        watched = EntryWatched(i, questID, byIndex, byID),
        info = nil,
      })
    end
  end
  return list
end

local function CollectQuests()
  local byIndex, byID = WatchMaps()
  local list
  if HasCQuestLog() then
    list = EnumerateModern(byIndex, byID)
  end
  if not list then
    list = EnumerateLegacy(byIndex, byID)
  end
  return list or {}
end

local function FocusKey(q)
  if not q then return nil end
  if type(q.questID) == "number" then return "id:" .. tostring(q.questID) end
  if type(q.logIndex) == "number" then return "log:" .. tostring(q.logIndex) end
  return nil
end

local function ByDistThenIndex(a, b)
  local da = a._dist or math.huge
  local db = b._dist or math.huge
  if da ~= db then return da < db end
  local ia = a.logIndex or 0
  local ib = b.logIndex or 0
  if ia ~= ib then return ia < ib end
  return false
end

function NS.QuestDistance(quest, pos)
  local nav = ComputeNav(quest, pos)
  if nav.hasCoords and type(nav.distanceYards) == "number" then
    return nav.distanceYards
  end
  return math.huge
end

-- 0.2.7 focus scope.
-- Any checked (watched) quests → candidates are ONLY those checked; always the
-- closest by distance (recomputed each EnumerateQuests / ~1s). Newly checked no
-- longer pins forever. Chain / adopted-successor rules apply only when NOTHING
-- is checked (or the successor itself is checked — already in the checked set).
-- /qg next|prev sets manualFocusID as a temporary override until the watch set
-- changes or /qg refresh clears it. No-coords sort after coords, then log order.
NS._adopted = NS._adopted or {}
NS._stickyChainID = NS._stickyChainID or nil
NS._scopeIDs = NS._scopeIDs or {}

local function InScope(q, anyChecked)
  if q.watched then return true end
  -- Chain / adoption only when nothing is checked.
  if anyChecked then return false end
  if type(q.questID) == "number" and NS._adopted[q.questID] then return true end
  if NS._stickyChainID and q.chainID == NS._stickyChainID then return true end
  return false
end

local function CountChecked(list)
  local n, i = 0, nil
  for i = 1, #list do
    if list[i].watched then n = n + 1 end
  end
  return n
end

-- Checked quests win (closest). Only when NO quest is checked do adoption /
-- sticky-chain / incomplete fallbacks apply. No usable coords → +inf so
-- coord-bearing quests sort first; logIndex breaks ties.
function NS.GetFocusCandidates(list)
  list = list or NS.questList or {}
  local pos = NS.GetPlayerPositions()
  local checked, incomplete, scoped = {}, {}, {}
  local anyChecked = false
  local i
  for i = 1, #list do
    local q = list[i]
    q._dist = NS.QuestDistance(q, pos)
    if q.watched then
      checked[#checked + 1] = q
      anyChecked = true
    end
    if not q.complete then
      incomplete[#incomplete + 1] = q
    end
  end
  local candidates
  if anyChecked then
    candidates = checked
  else
    for i = 1, #list do
      if InScope(list[i], false) then
        scoped[#scoped + 1] = list[i]
      end
    end
    if #scoped > 0 then
      candidates = scoped
    elseif #incomplete > 0 then
      candidates = incomplete
    else
      candidates = {}
      for i = 1, #list do candidates[i] = list[i] end
    end
  end
  table.sort(candidates, ByDistThenIndex)
  return candidates
end

-- ===== 0.2.8 main-map route stops (up to 7) =====
-- Best completion order = focus-candidate order (closest checked / scoped),
-- then upcoming untriggered chain steps for those quests (ChainData / C_QuestLine)
-- inserted after their predecessor when Forever exposes a POI. Cap = 7.
NS.MAX_MAP_ROUTE_STOPS = 7

local function StopMapCoords(questID, logIndex, existing)
  if type(existing) == "table" then
    if type(existing.mapX) == "number" and type(existing.mapY) == "number" then
      local kind = ClassifyXY(existing.mapX, existing.mapY)
      if kind == "map" and not (existing.mapX == 0 and existing.mapY == 0) then
        return existing.mapX, existing.mapY, existing.targetMapID
      end
    end
    if type(existing.worldX) == "number" and type(existing.worldY) == "number" then
      local mx, my, mid = WorldToNorm(existing.worldX, existing.worldY, existing.targetMapID)
      if mx then return mx, my, mid or existing.targetMapID end
    end
  end
  local poi = NS.TryQuestPOI(questID, logIndex)
  if type(poi) ~= "table" then return nil, nil, nil end
  if type(poi.mapX) == "number" and type(poi.mapY) == "number" then
    local kind = ClassifyXY(poi.mapX, poi.mapY)
    if kind == "map" and not (poi.mapX == 0 and poi.mapY == 0) then
      return poi.mapX, poi.mapY, poi.mapID
    end
  end
  if type(poi.worldX) == "number" and type(poi.worldY) == "number" then
    local mx, my, mid = WorldToNorm(poi.worldX, poi.worldY, poi.mapID)
    if mx then return mx, my, mid or poi.mapID end
  end
  return nil, nil, poi.mapID
end

local function InLogByID(list)
  local set, i = {}, nil
  for i = 1, #(list or {}) do
    local id = list[i].questID
    if type(id) == "number" then set[id] = list[i] end
  end
  return set
end

-- Returns ordered stops for the world-map route overlay.
-- Each: { n, questID, title, mapX, mapY, mapID, inLog, untriggered, chainID, chainStep }
function NS.GetMapRouteStops(maxStops)
  maxStops = tonumber(maxStops) or NS.MAX_MAP_ROUTE_STOPS or 7
  if maxStops < 1 then maxStops = 1 end
  if maxStops > 7 then maxStops = 7 end

  local list = NS.questList
  if type(list) ~= "table" or #list == 0 then
    list = CollectQuests()
    if type(list) == "table" and #list > 0 then
      ApplyFocus(list)
    end
  end
  list = list or {}
  local inLog = InLogByID(list)
  local candidates = NS.focusCandidates
  if type(candidates) ~= "table" or #candidates == 0 then
    candidates = NS.GetFocusCandidates(list)
  end

  local stops, seen = {}, {}
  local function addStop(questID, title, mapX, mapY, mapID, inLogFlag, chainID, chainStep)
    if #stops >= maxStops then return false end
    if type(questID) == "number" and seen[questID] then return false end
    if type(mapX) ~= "number" or type(mapY) ~= "number" then return false end
    if mapX < 0 or mapY < 0 or mapX > 1 or mapY > 1 then return false end
    if mapX == 0 and mapY == 0 then return false end
    local n = #stops + 1
    stops[n] = {
      n = n,
      questID = questID,
      title = title or ("Quest " .. tostring(questID or "?")),
      mapX = mapX,
      mapY = mapY,
      mapID = mapID,
      inLog = inLogFlag and true or false,
      untriggered = not inLogFlag,
      chainID = chainID,
      chainStep = chainStep,
    }
    if type(questID) == "number" then seen[questID] = true end
    return true
  end

  local i
  for i = 1, #candidates do
    if #stops >= maxStops then break end
    local q = candidates[i]
    if type(q) == "table" then
      local mx, my, mid = StopMapCoords(q.questID, q.logIndex, q)
      if mx then
        addStop(q.questID, q.title, mx, my, mid or q.targetMapID, true, q.chainID, q.chainStep or q.chainPos)
      end
    end
  end

  -- Insert upcoming untriggered chain steps after each accepted stop (best order:
  -- finish the chain you are on before leaping to unrelated pins).
  local grown = {}
  for i = 1, #stops do
    grown[#grown + 1] = stops[i]
    if #grown >= maxStops then break end
    local s = stops[i]
    if type(s.questID) ~= "number" then
      -- continue
    else
      local chain = NS.GetQuestChain(s.questID, s.mapID)
      if chain and type(chain.quests) == "table" then
        local startPos = chain.pos or 1
        local qi
        for qi = startPos + 1, #chain.quests do
          if #grown >= maxStops then break end
          local nid = chain.quests[qi]
          if type(nid) == "number" and not seen[nid] and not FlaggedComplete(nid) and not inLog[nid] then
            local mx, my, mid = StopMapCoords(nid, nil, nil)
            if mx then
              grown[#grown + 1] = {
                n = #grown + 1,
                questID = nid,
                title = "Chain step " .. tostring(qi),
                mapX = mx,
                mapY = my,
                mapID = mid or s.mapID,
                inLog = false,
                untriggered = true,
                chainID = chain.lineID,
                chainStep = qi,
              }
              seen[nid] = true
            end
          end
        end
      end
    end
  end

  -- Renumber after chain inserts.
  for i = 1, #grown do
    grown[i].n = i
  end
  if #grown > maxStops then
    while #grown > maxStops do grown[#grown] = nil end
  end
  NS.mapRouteStops = grown
  return grown
end

local function WatchKey(list)
  local ids = {}
  local i
  for i = 1, #list do
    if list[i].watched then
      ids[#ids + 1] = FocusKey(list[i]) or ""
    end
  end
  table.sort(ids)
  return table.concat(ids, ",")
end

-- Tracks uncheck transitions: drop adoption / sticky / manual for unchecked.
-- Newly checked does NOT pin focus (closest checked always wins).
local function NoteWatchTransitions(list)
  local now, inLog = {}, {}
  local i
  for i = 1, #list do
    local q = list[i]
    local k = FocusKey(q)
    if k then
      inLog[k] = q
      if q.watched then now[k] = true end
    end
  end
  local prev = NS._prevWatched
  if prev then
    local k
    for k in pairs(prev) do
      local q = inLog[k]
      if q and not now[k] then
        if type(q.questID) == "number" then NS._adopted[q.questID] = nil end
        if NS._stickyChainID and q.chainID == NS._stickyChainID then NS._stickyChainID = nil end
        if NS.manualFocusID == k then NS.manualFocusID = nil end
      end
    end
  end
  NS._prevWatched = now
  local id
  for id in pairs(NS._adopted) do
    if not inLog["id:" .. tostring(id)] then NS._adopted[id] = nil end
  end
end

local function ApplyFocus(list)
  local key = WatchKey(list)
  -- Tracker membership changed → drop manual cycle and use the auto rules.
  if NS._watchKey ~= nil and NS._watchKey ~= key then
    NS.manualFocusID = nil
  end
  NS._watchKey = key

  NoteWatchTransitions(list)
  if NS._pendingFocusID then
    -- Only honor pending adopt when nothing else is checked, or the pending
    -- quest itself is checked.
    local anyChecked = CountChecked(list) > 0
    local i
    for i = 1, #list do
      if list[i].questID == NS._pendingFocusID then
        if (not anyChecked) or list[i].watched then
          NS.manualFocusID = FocusKey(list[i])
        end
        NS._pendingFocusID = nil
        break
      end
    end
  end

  local candidates = NS.GetFocusCandidates(list)
  NS.focusCandidates = candidates
  NS.questList = list

  local anyChecked = CountChecked(list) > 0
  local scopeIDs = {}
  local i
  for i = 1, #list do
    if type(list[i].questID) == "number" and InScope(list[i], anyChecked) then
      scopeIDs[list[i].questID] = true
    end
  end
  NS._scopeIDs = scopeIDs

  local chosen
  if NS.manualFocusID then
    for i = 1, #candidates do
      if FocusKey(candidates[i]) == NS.manualFocusID then
        chosen = candidates[i]
        break
      end
    end
    if not chosen then NS.manualFocusID = nil end
  end
  if not chosen then
    chosen = candidates[1]
  end

  if chosen then
    if chosen.watched then
      NS._stickyChainID = chosen.chainID
    elseif (not anyChecked) and type(chosen.questID) == "number" and NS._adopted[chosen.questID] then
      NS._stickyChainID = chosen.chainID or NS._stickyChainID
    end
    NS.selectedQuestID = chosen.questID
    NS.selectedLogIndex = chosen.logIndex
    local sel = 1
    for i = 1, #list do
      if list[i] == chosen then sel = i break end
    end
    NS.selectedQuestIndex = sel
  else
    NS.selectedQuestID = nil
    NS.selectedLogIndex = nil
    NS.selectedQuestIndex = 1
  end
  return chosen
end

-- Turn-in of an in-scope quest opens a short window; the next quest accepted
-- in it is adopted as the chain's next step and takes focus.
local ADOPT_WINDOW = 20
local turnInAt
local chainEv = CreateFrame("Frame")
pcall(chainEv.RegisterEvent, chainEv, "QUEST_TURNED_IN")
pcall(chainEv.RegisterEvent, chainEv, "QUEST_ACCEPTED")
pcall(chainEv.RegisterEvent, chainEv, "QUESTLINE_UPDATE")
chainEv:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "QUESTLINE_UPDATE" then
    ClearChainMisses()
  elseif event == "QUEST_TURNED_IN" then
    RefreshCompletedSet(true)
    if type(a1) == "number" and NS._scopeIDs and NS._scopeIDs[a1] then
      turnInAt = NowSec()
      local c = NS.GetQuestChain(a1)
      if c and c.lineID then NS._stickyChainID = c.lineID end
    end
  elseif event == "QUEST_ACCEPTED" then
    local qid = (type(a2) == "number" and a2 > 0) and a2 or a1
    if turnInAt and type(qid) == "number" and (NowSec() - turnInAt) <= ADOPT_WINDOW then
      -- Known chain that is not the one just advanced -> not its next step.
      local c = NS.GetQuestChain(qid)
      if not (NS._stickyChainID and c and c.lineID and c.lineID ~= NS._stickyChainID) then
        NS._adopted[qid] = true
        NS._pendingFocusID = qid
        turnInAt = nil
        if NS.uiReady and not NS._refreshing and NS.Refresh then NS.Refresh() end
      end
    end
  end
end)

function NS.EnumerateQuests()
  local list = CollectQuests()
  ApplyFocus(list)
  return list
end

function NS.SelectQuest(index)
  local list = NS.questList or {}
  if type(index) ~= "number" then return end
  if index < 1 or index > #list then return end
  NS.manualFocusID = FocusKey(list[index])
  NS.selectedQuestIndex = index
  NS.selectedQuestID = list[index].questID
  NS.selectedLogIndex = list[index].logIndex
  if NS.Refresh then NS.Refresh() end
end

function NS.CycleFocus(delta)
  delta = tonumber(delta) or 1
  local list = CollectQuests()
  NS.questList = list
  local candidates = NS.GetFocusCandidates(list)
  NS.focusCandidates = candidates
  if #candidates == 0 then
    if NS.Refresh then NS.Refresh() end
    return
  end
  local curKey = NS.manualFocusID
  if not curKey and type(NS.selectedQuestID) == "number" then
    curKey = "id:" .. tostring(NS.selectedQuestID)
  elseif not curKey and type(NS.selectedLogIndex) == "number" then
    curKey = "log:" .. tostring(NS.selectedLogIndex)
  end
  local cur, found = 1, false
  local i
  for i = 1, #candidates do
    if FocusKey(candidates[i]) == curKey then
      cur = i
      found = true
      break
    end
  end
  local nxt = 1
  if found then
    nxt = cur + delta
    if nxt > #candidates then nxt = 1 end
    if nxt < 1 then nxt = #candidates end
  end
  NS.manualFocusID = FocusKey(candidates[nxt])
  NS.selectedQuestID = candidates[nxt].questID
  NS.selectedLogIndex = candidates[nxt].logIndex
  if NS.Refresh then NS.Refresh() end
end

function NS.NextQuest()
  NS.CycleFocus(1)
end

function NS.PrevQuest()
  NS.CycleFocus(-1)
end

local function FormatMoney(copper)
  copper = tonumber(copper)
  if not copper or copper <= 0 then return nil end
  copper = math.floor(copper + 0.5)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = tostring(g) .. "g" end
  if s > 0 then parts[#parts + 1] = tostring(s) .. "s" end
  if c > 0 and g == 0 then parts[#parts + 1] = tostring(c) .. "c" end
  if #parts == 0 then return nil end
  return table.concat(parts, " ")
end

local function CleanItemName(name)
  if type(name) ~= "string" or name == "" then return nil end
  local plain = string.match(name, "%[(.-)%]")
  if plain and plain ~= "" then return plain end
  return name
end

local function ReadRewardItems(nFn, infoFn, dest, questID)
  if type(nFn) ~= "function" or type(infoFn) ~= "function" then return end
  local n = SafeCall(nFn, questID)
  if type(n) ~= "number" or n <= 0 then n = SafeCall(nFn) end
  if type(n) ~= "number" or n <= 0 then return end
  if n > 12 then n = 12 end
  local i
  for i = 1, n do
    -- Classic: name, texture, count, quality, isUsable [, itemID]
    local name, texture, count, quality, _, itemID = SafeCall(infoFn, i, questID)
    if type(name) ~= "string" or name == "" then
      name, texture, count, quality, _, itemID = SafeCall(infoFn, i)
    end
    name = CleanItemName(name)
    local link = nil
    if type(itemID) == "number" and itemID > 0 and type(GetItemInfo) == "function" then
      local iname, ilink, _, _, _, _, _, _, _, itex = SafeCall(GetItemInfo, itemID)
      if not name then name = CleanItemName(iname) end
      if type(ilink) == "string" and ilink ~= "" then link = ilink end
      if (type(texture) ~= "string" or texture == "") and type(itex) == "string" then
        texture = itex
      end
      if (type(texture) ~= "string" or texture == "") and type(GetItemIcon) == "function" then
        local ic = SafeCall(GetItemIcon, itemID)
        if type(ic) == "string" or type(ic) == "number" then texture = ic end
      end
    end
    if type(itemID) == "number" and itemID > 0 and not link then
      link = "item:" .. tostring(math.floor(itemID))
    end
    -- Keep entries that have a name OR an itemID (icons can still show).
    if name or (type(itemID) == "number" and itemID > 0) then
      local c = 1
      if type(count) == "number" and count > 0 then c = count end
      dest[#dest + 1] = {
        name = name or ("Item " .. tostring(itemID)),
        count = c,
        itemID = (type(itemID) == "number" and itemID > 0) and itemID or nil,
        texture = texture,
        link = link,
        quality = quality,
      }
    end
  end
end

local function FormatRewardsText(rewards)
  local parts = {}
  if type(rewards.xp) == "number" and rewards.xp > 0 then
    parts[#parts + 1] = "+" .. tostring(math.floor(rewards.xp + 0.5)) .. " XP"
  end
  local money = FormatMoney(rewards.money)
  if money then parts[#parts + 1] = money end
  local shown = 0
  local function add(list)
    local i
    for i = 1, #list do
      if shown >= 3 then return end
      local it = list[i]
      if it and type(it.name) == "string" and it.name ~= "" then
        local s = it.name
        if type(it.count) == "number" and it.count > 1 then
          s = s .. " x" .. tostring(math.floor(it.count))
        end
        parts[#parts + 1] = s
        shown = shown + 1
      end
    end
  end
  add(rewards.items or {})
  add(rewards.choices or {})
  if #parts == 0 then return "" end
  local text = table.concat(parts, " · ")
  if string.len(text) > 96 then
    text = string.sub(text, 1, 93) .. "..."
  end
  return text
end

local function TakePositive(v)
  if type(v) == "number" and v > 0 then return v end
  return nil
end

local function GatherRewards(quest)
  local rewards = { xp = 0, money = 0, items = {}, choices = {} }
  local qid = quest.questID

  local function readSelected()
    local xp = TakePositive(SafeCall(GetQuestLogRewardXP))
    if not xp and type(qid) == "number" then
      xp = TakePositive(SafeCall(GetQuestLogRewardXP, qid))
    end
    local money = TakePositive(SafeCall(GetQuestLogRewardMoney))
    if not money and type(qid) == "number" then
      money = TakePositive(SafeCall(GetQuestLogRewardMoney, qid))
    end
    if xp then rewards.xp = xp end
    if money then rewards.money = money end
    ReadRewardItems(GetNumQuestLogRewards, GetQuestLogRewardInfo, rewards.items, qid)
    ReadRewardItems(GetNumQuestLogChoices, GetQuestLogChoiceInfo, rewards.choices, qid)
    if HasCQuestLog() and type(qid) == "number" then
      if rewards.xp == 0 and type(C_QuestLog.GetQuestRewardXP) == "function" then
        local v = TakePositive(SafeCall(C_QuestLog.GetQuestRewardXP, qid))
        if v then rewards.xp = v end
      end
      if rewards.money == 0 and type(C_QuestLog.GetQuestRewardMoney) == "function" then
        local v = TakePositive(SafeCall(C_QuestLog.GetQuestRewardMoney, qid))
        if v then rewards.money = v end
      end
    end
  end

  if type(quest.logIndex) == "number" and type(SelectQuestLogEntry) == "function" then
    WithLogSelected(quest.logIndex, readSelected)
  else
    readSelected()
  end
  return rewards, FormatRewardsText(rewards)
end

local function QuestCountText(n)
  if type(n) ~= "number" then n = 0 end
  n = math.floor(n)
  if n < 0 then n = 0 end
  if n == 1 then return "1 quest" end
  return string.format("%d quests", n)
end

local function CopyMock()
  local m = NS.MockRoute or {}
  local out = {
    name = m.name or "Barrens Loop",
    index = m.index or 1,
    total = m.total or 7,
    progressFrac = (type(m.progressFrac) == "number") and m.progressFrac
      or ((m.total and m.total > 0) and ((m.filled or 0) / m.total) or 0),
    step = {
      title = (m.step and m.step.title) or "Smart Drinks",
      distance = (m.step and m.step.distance) or "142 yd",
      bearing = (m.step and m.step.bearing) or "ahead",
      approx = (m.step and m.step.approx) or "approx.",
      zone = (m.step and m.step.zone) or "Lushwater Oasis",
    },
    tracker = {
      label = (m.tracker and m.tracker.label) or "Smart Drinks · Wailing Essence",
      count = (m.tracker and m.tracker.count) or 0,
      total = (m.tracker and m.tracker.total) or 6,
    },
    status = {
      state = (m.status and m.status.state) or "In progress",
      last = (m.status and m.status.last) or "2m ago",
      count = (m.status and m.status.count) or QuestCountText(m.total or 7),
    },
    askPlaceholder = m.askPlaceholder or "Where do I turn in Smart Drinks?",
    targetX = nil,
    targetY = nil,
    targetMapID = nil,
    targetCoordKind = nil,
    mapX = nil,
    mapY = nil,
    worldX = nil,
    worldY = nil,
    bearingDeg = (type(m.bearingDeg) == "number") and m.bearingDeg or 0,
    distanceYards = nil,
    hasCoords = false,
    questID = nil,
    questType = nil,
    questTypeLabel = nil,
    rewards = nil,
    rewardsText = m.rewardsText or "+1240 XP",
    source = "mock",
  }
  return out
end

local function FirstIncompleteObjective(quest)
  local objs = quest.objectives or {}
  local i
  for i = 1, #objs do
    if not objs[i].finished then
      return objs[i]
    end
  end
  return objs[1]
end

local function TrackerFromQuest(quest)
  local obj = FirstIncompleteObjective(quest)
  if obj then
    local label = obj.text or quest.title
    local clean = string.gsub(label, "%s*%d+%s*/%s*%d+%s*$", "")
    return {
      label = clean ~= "" and clean or quest.title,
      count = obj.numFulfilled or 0,
      total = (obj.numRequired and obj.numRequired > 0) and obj.numRequired or 1,
    }
  end
  return {
    label = quest.title,
    count = quest.complete and 1 or 0,
    total = 1,
  }
end

-- Selecting the quest log every tick flickers Blizzard's quest frame. Re-read
-- rewards when the focused quest changes, and at most every few seconds.
local function CachedRewards(quest)
  local key = tostring(quest.questID or "x") .. ":" .. tostring(quest.logIndex or "x")
  local now = 0
  if type(GetTime) == "function" then
    local t = GetTime()
    if type(t) == "number" then now = t end
  end
  if NS._rewardCacheKey == key and type(NS._rewardCache) == "table" and (now - (NS._rewardCacheAt or 0)) < 5 then
    return NS._rewardCache, NS._rewardCacheText or ""
  end
  local rewards, text = GatherRewards(quest)
  NS._rewardCacheKey = key
  NS._rewardCache = rewards
  NS._rewardCacheText = text
  NS._rewardCacheAt = now
  return rewards, text
end

local function BuildLive(quest, list)
  local pos = NS.GetPlayerPositions()
  local nav = ComputeNav(quest, pos)
  local rewards, rewardsText = CachedRewards(quest)
  quest.rewards = rewards
  quest.rewardsText = rewardsText
  local tracker = TrackerFromQuest(quest)
  -- 0.2.7: chain step when known; no chain → noChain (UI "—") and objective %.
  local chain = NS.ChainProgress(quest)
  local state = "In progress"
  if quest.complete then state = "Ready to turn in" end
  local qtype = quest.questType or "World"
  if qtype ~= "Dungeon" then qtype = "World" end

  return {
    name = "Quest Log",
    index = chain.index,
    total = chain.total,
    noChain = chain.noChain and true or false,
    progressFrac = chain.frac,
    chainDone = chain.done,
    chainName = chain.name,
    chainID = chain.lineID,
    step = {
      title = quest.title,
      distance = nav.distance,
      bearing = nav.bearing,
      approx = nav.approx,
      zone = nav.zone,
    },
    tracker = tracker,
    status = {
      state = state,
      last = "live",
      count = QuestCountText(#list),
    },
    askPlaceholder = "Help with: " .. tostring(quest.title),
    targetX = nav.targetX or quest.targetX,
    targetY = nav.targetY or quest.targetY,
    targetMapID = nav.targetMapID or quest.targetMapID,
    targetCoordKind = nav.targetCoordKind or quest.targetCoordKind,
    mapX = nav.mapX or quest.mapX,
    mapY = nav.mapY or quest.mapY,
    worldX = quest.worldX,
    worldY = quest.worldY,
    bearingDeg = nav.bearingDeg,
    distanceYards = nav.distanceYards,
    hasCoords = nav.hasCoords and true or false,
    questID = quest.questID,
    logIndex = quest.logIndex,
    watched = quest.watched and true or false,
    questType = qtype,
    questTypeLabel = qtype,
    rewards = rewards,
    rewardsText = rewardsText or "",
    source = "live",
  }
end

function NS.RefreshFocusedNav(route)
  if not route or route.source ~= "live" then return route end
  local list = NS.questList or {}
  local q
  local i
  for i = 1, #list do
    local e = list[i]
    if route.questID and e.questID == route.questID then
      q = e
      break
    end
    if not route.questID and route.logIndex and e.logIndex == route.logIndex then
      q = e
      break
    end
  end
  if not q then return route end

  -- Re-probe POI until both a bearing and a normalized pin exist. Distance still
  -- updates every tick from whatever coords we already have.
  if not (route.hasCoords and route.mapX and route.mapY) then
    local poi = NS.TryQuestPOI(q.questID, q.logIndex)
    if poi and (poi.mapX or poi.worldX) then
      ApplyPOI(q, poi)
    elseif poi and poi.mapID and not q.targetMapID then
      q.targetMapID = poi.mapID
    end
  end

  local nav = ComputeNav(q)
  route.targetX = nav.targetX or q.targetX
  route.targetY = nav.targetY or q.targetY
  route.targetMapID = nav.targetMapID or q.targetMapID
  route.targetCoordKind = nav.targetCoordKind or q.targetCoordKind
  route.mapX = nav.mapX or q.mapX
  route.mapY = nav.mapY or q.mapY
  route.worldX = q.worldX
  route.worldY = q.worldY
  route.hasCoords = nav.hasCoords and true or false
  route.bearingDeg = nav.bearingDeg
  route.distanceYards = nav.distanceYards
  if route.step then
    route.step.distance = nav.distance
    route.step.bearing = nav.bearing
    route.step.approx = nav.approx
    route.step.zone = nav.zone
  end
  return route
end

function NS.GetLiveRoute()
  local force = NS.forceMock
  if NS.db and NS.db.forceMock then force = true end
  if force then
    local m = CopyMock()
    NS.liveRoute = m
    return m
  end

  local list = NS.EnumerateQuests()
  if not list or #list == 0 then
    local m = CopyMock()
    NS.liveRoute = m
    if NS.NoteRouteEnum then NS.NoteRouteEnum() end
    return m
  end

  local q
  local idx = NS.selectedQuestIndex or 1
  if list[idx] and (not NS.selectedQuestID or list[idx].questID == NS.selectedQuestID) then
    q = list[idx]
  end
  if not q and NS.selectedQuestID then
    local i
    for i = 1, #list do
      if list[i].questID == NS.selectedQuestID then
        q = list[i]
        break
      end
    end
  end
  if not q then
    q = (NS.focusCandidates and NS.focusCandidates[1]) or list[1]
  end
  if not q then
    local m = CopyMock()
    NS.liveRoute = m
    return m
  end

  local out = BuildLive(q, list)
  NS.liveRoute = out
  if NS.NoteRouteEnum then NS.NoteRouteEnum() end
  return out
end

function NS.RefreshLive()
  local route = NS.GetLiveRoute()
  if NS.ApplyRoute then
    NS.ApplyRoute(route)
  elseif NS.RefreshMock and route.source == "mock" then
    NS.RefreshMock()
  end
  return route
end
