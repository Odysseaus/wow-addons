-- WoW API stubs for Valhalla's Objectives module (box tests only)
local W = {}
_G.W = W
W.clock = 100
function GetTime() return W.clock end
-- generic frame
local Frame = {}
local function NewFrame(kind, name)
  local f = { _kind = kind, _scripts = {}, _shown = kind ~= "Frame-hidden", _points = {} }
  return setmetatable(f, Frame)
end
Frame.__index = function(t, k)
  local m = rawget(Frame, k)
  if m then return m end
  return function() return nil end
end
function Frame.SetScript(self, k, fn) self._scripts[k] = fn end
function Frame.GetScript(self, k) return self._scripts[k] end
function Frame.Show(self) self._shown = true end
function Frame.Hide(self) self._shown = false end
function Frame.IsShown(self) return self._shown end
function Frame.IsVisible(self) return self._shown end
function Frame.SetShown(self, v) self._shown = v and true or false end
function Frame.CreateTexture(self) return NewFrame("Texture") end
function Frame.CreateFontString(self) local f = NewFrame("FontString") f._text = "" return f end
function Frame.SetText(self, s) self._text = s end
function Frame.GetText(self) return self._text end
function Frame.GetEffectiveScale() return 1 end
function Frame.GetWidth() return 260 end
function Frame.GetLeft() return 1000 end
function Frame.GetTop() return 700 end
function Frame.GetBottom(self) return rawget(self, "_bottom") or 500 end
function Frame.SetAtlas(self, a) self._atlas = a end
function Frame.SetTexture(self, t) self._tex = t end
function Frame.RegisterEvent(self, e) local t = rawget(self, "_events") or {} self._events = t t[e] = true end
function Frame.UnregisterAllEvents(self) self._events = {} end
function Frame.UnregisterEvent(self, e) local t = rawget(self, "_events") if t then t[e] = nil end end
-- the game's date() and time() (v0.4.2.2's sync log)
W.epoch = 1000000
date = os.date
time = function() return W.epoch end
function Frame.SetPoint(self, ...) self._points[#self._points + 1] = { ... } end
function Frame.ClearAllPoints(self) self._points = {} end
function Frame.GetFrameStrata() return "LOW" end
function Frame.SetSize(self, w, h) self._w, self._h = w, h end
function Frame.GetSize(self) return rawget(self, "_w"), rawget(self, "_h") end
function Frame.GetFrameLevel() return 5 end
W.NewFrame = NewFrame
W.frames = {}
-- the game's templates the module asks for (v0.2.1): a quest POI button, the tracker header's minimize button
W.templates = {}
W.templates.ObjectiveTrackerPOIButtonTemplate = function(f)
  f._w, f._h = 20, 20
  f.SetQuestID = function(self, q) self._q = q end
  f.GetQuestID = function(self) return self._q end
  f.SetStyle = function(self, st) self._style = st end
  f.SetSelected = function(self, v) self._selected = v and true or false end
  f.IsSelected = function(self) return self._selected end
  f.UpdateButtonStyle = function(self) self._styled = (self._styled or 0) + 1 end
end
W.templates.ObjectiveTrackerModuleMinimizeButtonTemplate = function(f)
  f._w, f._h = 16, 16
  f._normal, f._pushed = NewFrame("Texture"), NewFrame("Texture")
  f.GetNormalTexture = function(self) return self._normal end
  f.GetPushedTexture = function(self) return self._pushed end
end
function CreateFrame(kind, name, parent, template)
  local f = NewFrame(kind, name)
  f._parent = parent
  if template and not W.noTemplates and W.templates[template] then W.templates[template](f) f._template = template end
  W.frames[#W.frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = NewFrame("Frame")
GameTooltip = NewFrame("GameTooltip")
GameFontNormal = {}
C_Texture = { GetAtlasInfo = function() return {} end }
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
C_Timer = { NewTicker = function(_, fn) W.ticker = { fn = fn, Cancel = function(self) self.cancelled = true end } return W.ticker end,
  After = function() end }
function InCombatLockdown() return W.combat end
function UnitOnTaxi() return W.taxi end

-- maps (Forever uiMapIDs)
W.MAPS = {
  [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 13 },
  [1453] = { name = "Stormwind City", mapType = 3, parentMapID = 1415 },
  [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
  [1436] = { name = "Westfall", mapType = 3, parentMapID = 1415 },
  [1431] = { name = "Duskwood", mapType = 3, parentMapID = 1415 },
  [1426] = { name = "Dun Morogh", mapType = 3, parentMapID = 1415 },
  [1455] = { name = "Ironforge", mapType = 3, parentMapID = 1415 },
  [9001] = { name = "Goldshire Inn", mapType = 5, parentMapID = 1429 },
  [1437] = { name = "Wetlands", mapType = 3, parentMapID = 1415 },
  [1432] = { name = "Loch Modan", mapType = 3, parentMapID = 1415 },
  [1424] = { name = "Hillsbrad Foothills", mapType = 3, parentMapID = 1415 },
  [9100] = { name = "Gnomeregan", mapType = 4, parentMapID = 1426 },
  [9101] = { name = "The Deadmines", mapType = 4, parentMapID = 1436 },
  [9102] = { name = "Excavation Site: Wetlands", mapType = 4, parentMapID = 1437 },
}
W.map = 1453
W.onMap = {}   -- [mapID] = { questID, ... }
C_Map = {
  GetBestMapForUnit = function() return W.map end,
  GetMapInfo = function(id) local m = W.MAPS[id] if m then return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID } end end,
  GetMapChildrenInfo = function(root, mapType, all)
    local out = {}
    local function Under(id) local m = W.MAPS[id] for _ = 1, 8 do if not m then return false end if m.parentMapID == root then return true end if not all then return false end m = W.MAPS[m.parentMapID] end return false end
    for id, m in pairs(W.MAPS) do
      if Under(id) and (mapType == nil or m.mapType == mapType) then out[#out + 1] = { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID } end
    end
    return out
  end,
}
-- instances: W.inst = { name, kind } while inside one
function IsInInstance() if W.inst then return true, W.inst.kind or "party" end return false, "none" end
function GetInstanceInfo() if W.inst then return W.inst.name, W.inst.kind or "party" end return GetZoneText(), "none" end
function GetZoneText() if W.inst then return W.inst.name end local m = W.MAPS[W.map] return m and m.name or "" end
function GetRealZoneText() return GetZoneText() end

-- the quest log: W.quests = { [id] = { header, title, level, ready } }; headers in log order of first appearance
W.quests = {}
W.order = {}   -- quest ids in log order
W.watches = {} -- watch list (ids)
W.side = "front"
W.autoWatch = true
W.calls = { add = 0, remove = 0 }
local function Entries()
  local list, seen = {}, {}
  local byHeader, headers = {}, {}
  for _, id in ipairs(W.order) do
    local q = W.quests[id]
    if q then
      if not byHeader[q.header] then byHeader[q.header] = {} headers[#headers + 1] = q.header end
      table.insert(byHeader[q.header], id)
    end
  end
  for _, h in ipairs(headers) do
    list[#list + 1] = { isHeader = true, title = h }
    for _, id in ipairs(byHeader[h]) do
      local q = W.quests[id]
      list[#list + 1] = { questID = id, title = q.title, level = q.level, difficultyLevel = q.level, isHeader = false, isHidden = false, isTask = false, isBounty = false }
    end
  end
  return list
end
local function WatchIndex(id) for i, w in ipairs(W.watches) do if w == id then return i end end end
C_QuestLog = {
  GetNumQuestLogEntries = function() return #Entries() end,
  GetInfo = function(i) return Entries()[i] end,
  -- (v0.4.2.2: q.rft / q.ic answer for one of the two on their own; q.obj = { { have, need }, ... })
  ReadyForTurnIn = function(id) local q = W.quests[id] if q and q.rft ~= nil then return q.rft end return q and q.ready or false end,
  IsComplete = function(id) local q = W.quests[id] if q and q.ic ~= nil then return q.ic end return q and q.ready or false end,
  GetQuestObjectives = function(id)
    local q = W.quests[id]
    if not q then return nil end
    local out = {}
    for i, o in ipairs(q.obj or {}) do out[i] = { text = "Item: " .. o[1] .. "/" .. o[2], type = "item", numFulfilled = o[1], numRequired = o[2], finished = o[1] >= o[2] } end
    return out
  end,
  GetNumQuestWatches = function() return #W.watches end,
  GetQuestIDForQuestWatchIndex = function(i) return W.watches[i] end,
  AddQuestWatch = function(id)
    W.calls.add = W.calls.add + 1
    if W.combat then W.combatChanges = (W.combatChanges or 0) + 1 end
    if WatchIndex(id) or #W.watches >= 25 or not W.quests[id] then return false end
    if W.side == "front" then table.insert(W.watches, 1, id) else W.watches[#W.watches + 1] = id end
    return true
  end,
  RemoveQuestWatch = function(id)
    W.calls.remove = W.calls.remove + 1
    if W.combat then W.combatChanges = (W.combatChanges or 0) + 1 end
    local i = WatchIndex(id) if i then table.remove(W.watches, i) end
  end,
  -- W.onMap[mapID] = { questID | { questID, mapID, isMapIndicatorQuest }, ... }; W.waypoints["q:map"] = true
  GetQuestsOnMap = function(m)
    local out = {}
    for _, it in ipairs(W.onMap[m] or {}) do
      if type(it) == "table" then
        out[#out + 1] = { questID = it.questID, mapID = it.mapID or m, x = 0.4, y = 0.6, isMapIndicatorQuest = it.isMapIndicatorQuest or false }
      else
        out[#out + 1] = { questID = it, x = 0.5, y = 0.5, isMapIndicatorQuest = false }
      end
    end
    return out
  end,
  GetNextWaypointForMap = function(q, m) if W.waypoints[q .. ":" .. m] then return 0.9, 0.1 end end,
  -- v0.2.2: W.next[q] = the map of its next waypoint; W.noLocal[q] = the game says no local POI
  GetNextWaypoint = function(q) local m = W.next[q] if m then return m, 0.5, 0.5 end end,
  IsOnMap = function(q) return true, not W.noLocal[q] end,
  GetQuestTagInfo = function(q) local x = W.quests[q] if x and x.tag then return { tagID = x.tag, tagName = "Dungeon" } end end,
}
W.super = 0
C_SuperTrack = { GetSuperTrackedQuestID = function() return W.super end, SetSuperTrackedQuestID = function(id) W.super = id end,
  ClearAllSuperTracked = function() W.super = 0 W.cleared = (W.cleared or 0) + 1 end }
POIButtonUtil = { Style = { QuestInProgress = 2, QuestComplete = 3 } }
W.waypoints = {}
W.next, W.noLocal = {}, {}
-- frames: the mouse setters combat blocks (counted: the module must never call them)
W.blockedSetters = 0
function Frame.SetPassThroughButtons() W.blockedSetters = W.blockedSetters + 1 end
function Frame.SetPropagateMouseClicks() W.blockedSetters = W.blockedSetters + 1 end
function Frame.GetFrameLevel(self) return rawget(self, "_level") or 5 end
function Frame.SetFrameLevel(self, l) self._level = l end
-- hooksecurefunc: a post-hook
function hooksecurefunc(t, name, fn)
  if type(t) == "string" then t, name, fn = _G, t, name end
  local orig = t[name]
  t[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
end

function W.AddQuest(id, header, title, level, ready, watched, tag)
  W.quests[id] = { header = header, title = title, level = level, ready = ready or false, tag = tag }
  W.order[#W.order + 1] = id
  if watched then W.watches[#W.watches + 1] = id end
end
function W.Drop(id)
  W.quests[id] = nil
  for i, x in ipairs(W.order) do if x == id then table.remove(W.order, i) break end end
  local i = WatchIndex(id) if i then table.remove(W.watches, i) end
end
function W.Reset()
  W.quests, W.order, W.watches, W.onMap, W.waypoints, W.inst = {}, {}, {}, {}, {}, nil
  W.next, W.noLocal = {}, {}
  W.combat, W.taxi, W.super, W.combatChanges = false, false, 0, 0
  W.side = "front"
  W.calls = { add = 0, remove = 0 }
end

--------------------------------------------------------------------------------
-- the game's quest log (Blizzard_UIPanels_Game QuestMapFrame.lua, as far as the quest-log pins read it):
-- a pool of title rows (QuestLogTitleTemplate: Text at TOPLEFT 31, -8), a pool of headers, the quest
-- icons (POI buttons) found by quest, and QuestLogQuests_Update laying them out as the game does
--------------------------------------------------------------------------------
W.ROW_W = 290
local function TextLeft(t)
  local x = 31
  for _, pt in ipairs(t._points) do if pt[1] == "TOPLEFT" then x = (type(pt[2]) == "table") and pt[4] or pt[2] end end
  return x
end
W.TextLeft = TextLeft
local function Pool(make)
  local P = { active = {}, free = {}, made = 0 }
  function P:Acquire()
    local f = table.remove(self.free)
    if not f then f = make() self.made = self.made + 1 end
    self.active[f] = true
    f:Show()
    return f
  end
  function P:ReleaseAll()
    for f in pairs(self.active) do f:Hide() f._points = {} rawset(f, "questID", nil) rawset(f, "info", nil) self.free[#self.free + 1] = f end
    self.active = {}
  end
  function P:EnumerateActive() return next, self.active end
  function P:GetNumActive() local n = 0 for _ in pairs(self.active) do n = n + 1 end return n end
  return P
end
function W.NewQuestLog()
  local contents = NewFrame("Frame")
  local function Row()
    local r = NewFrame("Button")
    r._kind = "QuestLogTitle"
    r.Text = NewFrame("FontString") r.Text._text = ""
    r.Text:SetPoint("TOPLEFT", 31, -8)
    r.Text:SetPoint("TOP", 0, -8)
    r.Checkbox = NewFrame("Frame")   -- (QuestLogTitleTemplate's Track tick, TOPRIGHT y -8: 1.1.0's chain view hides it)
    r.Checkbox.CheckMark = NewFrame("Texture")
    r.Text.GetHeight = function(self)   -- (wraps: about 6 px a letter, 12 px a line, in the width it has)
      local width = W.ROW_W - TextLeft(self) - 50
      local lines = math.max(1, math.ceil(#(self._text or "") * 6 / width))
      return lines * 12
    end
    return r
  end
  local SF = { Contents = contents }
  SF.titleFramePool = Pool(Row)
  SF.headerFramePool = Pool(function() local h = NewFrame("Button") h._kind = "QuestLogHeader" return h end)
  local poiPool = Pool(function()
    local b = NewFrame("Button")
    b.GetQuestID = function(self) return self._q end
    return b
  end)
  SF.poiPool = poiPool
  function contents:FindButtonByQuestID(q) for b in poiPool:EnumerateActive() do if b._q == q then return b end end end
  _G.QuestScrollFrame = SF
  W.log = { measured = {} }
  -- the game's update: every row and header released and taken again, in log order
  _G.QuestLogQuests_Update = function()
    SF.titleFramePool:ReleaseAll() SF.headerFramePool:ReleaseAll() poiPool:ReleaseAll()
    W.log.rows, W.log.headers = {}, {}
    local last
    for _, id in ipairs(W.order) do
      local q = W.quests[id]
      if q and q.header ~= last then
        last = q.header
        local h = SF.headerFramePool:Acquire()
        h._title = q.header
        W.log.headers[#W.log.headers + 1] = h
      end
      if q then
        local row = SF.titleFramePool:Acquire()
        row.questID = id
        row.info = { questID = id }
        row.Text:SetText(q.title)
        local height = 8 + row.Text:GetHeight() + 6
        row:SetHeight(height)
        row._height = height
        W.log.measured[id] = TextLeft(row.Text)   -- (where the title was when the game measured it)
        if not W.noPOI or not W.noPOI[id] then
          local poi = poiPool:Acquire()
          poi._q = id
          poi.parent = row
          poi:SetPoint("TOPLEFT", row, 6, -4)
        end
        W.log.rows[#W.log.rows + 1] = row
      end
    end
  end
  return SF
end
function Frame.SetHeight(self, h) self._height = h end
function Frame.SetParent(self, p) self._parent = p end

return W
