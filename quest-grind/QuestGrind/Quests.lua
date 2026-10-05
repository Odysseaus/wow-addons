local _, NS = ...

-- P1: live quest log enumerate + prioritize + MockRoute-compatible live route.
-- Prefer Classic/Forever APIs; guard C_QuestLog vs legacy GetQuestLog* with pcall.

NS.questList = NS.questList or {}
NS.selectedQuestIndex = NS.selectedQuestIndex or 1
NS.liveRoute = NS.liveRoute or nil
NS.forceMock = NS.forceMock or false

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f
end

local function ZoneName()
  local z = SafeCall(GetRealZoneText) or SafeCall(GetZoneText) or SafeCall(GetMinimapZoneText)
  if type(z) == "string" and z ~= "" then return z end
  return "?"
end

function NS.GetPlayerMapPosition()
  -- Prefer world coords (yards) when available.
  if type(UnitPosition) == "function" then
    local y, x, _, mapID = SafeCall(UnitPosition, "player")
    -- UnitPosition returns y, x in yards (Classic); treat as world coords.
    if x and y then
      return x, y, mapID, "world"
    end
  end
  -- Normalized map position fallback.
  local mapID
  if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
    mapID = SafeCall(C_Map.GetBestMapForUnit, "player")
  end
  if mapID and C_Map and type(C_Map.GetPlayerMapPosition) == "function" then
    local pos = SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
    if pos then
      local ok, x, y = pcall(function()
        if pos.GetXY then return pos:GetXY() end
        return pos.x, pos.y
      end)
      if ok and x and y then
        return x, y, mapID, "map"
      end
    end
  end
  if type(GetPlayerMapPosition) == "function" then
    local x, y = SafeCall(GetPlayerMapPosition, "player")
    if x and y and x > 0 and y > 0 then
      return x, y, mapID, "map"
    end
  end
  return nil, nil, nil, nil
end

local function HasCQuestLog()
  return type(C_QuestLog) == "table"
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

local function TryQuestPOI(questID)
  -- Best-effort: quest POI / world map position APIs vary widely on Forever.
  if HasCQuestLog() and type(C_QuestLog.GetNextWaypoint) == "function" then
    local mapID, x, y = SafeCall(C_QuestLog.GetNextWaypoint, questID)
    if x and y then return x, y, mapID end
  end
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestObjectives) == "function" then
    -- no reliable coords from objectives alone
  end
  if type(QuestPOIGetIconInfo) == "function" then
    local _, posX, posY = SafeCall(QuestPOIGetIconInfo, questID)
    if posX and posY and posX > 0 then
      return posX, posY, nil
    end
  end
  if type(GetQuestLogSpecialItemInfo) == "function" then
    -- item link only; no coords
  end
  return nil, nil, nil
end

local function EnumerateModern()
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
      local objs = questID and GetObjectivesModern(questID) or {}
      local tx, ty, tmap = TryQuestPOI(questID)
      list[#list + 1] = {
        logIndex = i,
        questID = questID,
        title = title,
        complete = complete,
        objectives = objs,
        level = info.level,
        suggestedGroup = info.suggestedGroup,
        targetX = tx,
        targetY = ty,
        targetMapID = tmap,
      }
    elseif type(info) ~= "table" then
      -- GetInfo missing: stop modern path
      return nil
    end
  end
  return list
end

local function EnumerateLegacy()
  local list = {}
  local n = GetNumEntries()
  local i
  for i = 1, n do
    local title, level, suggestedGroup, isHeader, _, isComplete, frequency, questID =
      SafeCall(GetQuestLogTitle, i)
    -- Classic returns many fields; tolerate partial.
    if not title then
      -- alternate: SelectQuestLogEntry then GetQuestLogTitle
      if type(SelectQuestLogEntry) == "function" then
        SafeCall(SelectQuestLogEntry, i)
        title, level, suggestedGroup, isHeader, _, isComplete, frequency, questID =
          SafeCall(GetQuestLogTitle, i)
      end
    end
    if title and not isHeader then
      local objs = GetObjectivesLegacy(i)
      local complete = false
      if isComplete == 1 or isComplete == true then
        complete = true
      end
      local tx, ty, tmap = TryQuestPOI(questID)
      list[#list + 1] = {
        logIndex = i,
        questID = questID,
        title = title,
        complete = complete,
        objectives = objs,
        level = level,
        suggestedGroup = suggestedGroup,
        targetX = tx,
        targetY = ty,
        targetMapID = tmap,
      }
    end
  end
  return list
end

local function Prioritize(list)
  table.sort(list, function(a, b)
    local ac = a.complete and 1 or 0
    local bc = b.complete and 1 or 0
    if ac ~= bc then return ac < bc end
    local ao = #(a.objectives or {})
    local bo = #(b.objectives or {})
    if (ao == 0) ~= (bo == 0) then return ao > 0 end
    local ah = (a.targetX and a.targetY) and 1 or 0
    local bh = (b.targetX and b.targetY) and 1 or 0
    if ah ~= bh then return ah > bh end
    return (a.logIndex or 0) < (b.logIndex or 0)
  end)
  return list
end

function NS.EnumerateQuests()
  local list
  if HasCQuestLog() then
    list = EnumerateModern()
  end
  if not list then
    list = EnumerateLegacy()
  end
  list = Prioritize(list or {})
  NS.questList = list
  -- Keep selected index stable by questID when possible.
  local sel = NS.selectedQuestIndex or 1
  local wantID = NS.selectedQuestID
  if wantID then
    local i
    for i = 1, #list do
      if list[i].questID == wantID then
        sel = i
        break
      end
    end
  end
  if sel < 1 then sel = 1 end
  if #list == 0 then
    sel = 1
  elseif sel > #list then
    sel = #list
  end
  NS.selectedQuestIndex = sel
  if list[sel] then
    NS.selectedQuestID = list[sel].questID
  end
  return list
end

function NS.SelectQuest(index)
  local list = NS.questList or {}
  if type(index) ~= "number" then return end
  if index < 1 or index > #list then return end
  NS.selectedQuestIndex = index
  NS.selectedQuestID = list[index].questID
  if NS.Refresh then NS.Refresh() end
end

function NS.NextQuest()
  local list = NS.questList or {}
  if #list == 0 then return end
  local i = (NS.selectedQuestIndex or 1) + 1
  if i > #list then i = 1 end
  NS.SelectQuest(i)
end

function NS.PrevQuest()
  local list = NS.questList or {}
  if #list == 0 then return end
  local i = (NS.selectedQuestIndex or 1) - 1
  if i < 1 then i = #list end
  NS.SelectQuest(i)
end

local function CopyMock()
  local m = NS.MockRoute or {}
  local out = {
    name = m.name or "Barrens Loop",
    index = m.index or 1,
    total = m.total or 7,
    segments = m.segments or 5,
    filled = m.filled or 1,
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
      xp = (m.status and m.status.xp) or "+1240 XP",
    },
    askPlaceholder = m.askPlaceholder or "Where do I turn in Smart Drinks?",
    targetX = nil,
    targetY = nil,
    targetMapID = nil,
    bearingDeg = 0,
    distanceYards = nil,
    hasCoords = false,
    questID = nil,
    source = "mock",
  }
  return out
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
  if not facing then
    return Cardinal(targetDeg)
  end
  -- GetPlayerFacing: radians, 0 = north, increases counter-clockwise in many clients.
  local facingDeg = math.deg(facing)
  local delta = (targetDeg - facingDeg + 180) % 360 - 180
  local ad = math.abs(delta)
  if ad < 25 then return "ahead"
  elseif ad > 155 then return "behind"
  elseif delta > 0 then return "left"
  else return "right"
  end
end

local function ComputeNav(quest)
  local px, py, pmap, kind = NS.GetPlayerMapPosition()
  local tx, ty, tmap = quest.targetX, quest.targetY, quest.targetMapID
  if not (tx and ty and px and py) then
    return {
      hasCoords = false,
      distanceYards = nil,
      bearingDeg = nil,
      distance = "?",
      bearing = "unknown",
      approx = "no coords",
      zone = ZoneName(),
    }
  end
  local dx = tx - px
  local dy = ty - py
  local dist
  if kind == "world" then
    dist = math.sqrt(dx * dx + dy * dy)
  else
    -- Normalized map units → rough yards (heuristic ~1000 yd per map axis).
    dist = math.sqrt(dx * dx + dy * dy) * 1000
  end
  -- Bearing: 0 = north (+y in map space often inverted). Use atan2(dx, -dy) for N-up maps.
  local bearingDeg = math.deg(math.atan2(dx, -dy))
  if bearingDeg < 0 then bearingDeg = bearingDeg + 360 end
  return {
    hasCoords = true,
    distanceYards = dist,
    bearingDeg = bearingDeg,
    distance = FormatDistance(dist),
    bearing = RelativeBearing(bearingDeg),
    approx = "approx.",
    zone = ZoneName(),
    targetX = tx,
    targetY = ty,
    targetMapID = tmap or pmap,
  }
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
    -- Strip trailing "x/y" from label for cleaner display when we show count separately.
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
    return m
  end

  local idx = NS.selectedQuestIndex or 1
  if idx < 1 then idx = 1 end
  if idx > #list then idx = #list end
  local q = list[idx]
  local nav = ComputeNav(q)
  local tracker = TrackerFromQuest(q)
  local filled = 0
  local segs = math.min(5, math.max(1, #list))
  local i
  for i = 1, #list do
    if list[i].complete then filled = filled + 1 end
  end
  -- Progress bar: selected position among incomplete-first list.
  local barFilled = math.min(segs, math.max(1, idx))

  local state = "In progress"
  if q.complete then state = "Ready to turn in" end

  local out = {
    name = "Quest Log",
    index = idx,
    total = #list,
    segments = segs,
    filled = barFilled,
    step = {
      title = q.title,
      distance = nav.distance,
      bearing = nav.bearing,
      approx = nav.approx,
      zone = nav.zone,
    },
    tracker = tracker,
    status = {
      state = state,
      last = "live",
      xp = string.format("%d quest%s", #list, #list == 1 and "" or "s"),
    },
    askPlaceholder = "Help with: " .. tostring(q.title),
    targetX = nav.targetX or q.targetX,
    targetY = nav.targetY or q.targetY,
    targetMapID = nav.targetMapID or q.targetMapID,
    bearingDeg = nav.bearingDeg,
    distanceYards = nav.distanceYards,
    hasCoords = nav.hasCoords and true or false,
    questID = q.questID,
    source = "live",
  }
  NS.liveRoute = out
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
