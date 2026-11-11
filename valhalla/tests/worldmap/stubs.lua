-- WoW API stubs for Valhalla's world map fly-to (Map/FlyPath.lua, Map/WorldMap.lua, Map/QuestFly.lua): box tests only.
-- Blizzard's map is modelled as far as the fly-to needs: SetMapID puts a map up (its zoom levels made, its view
-- reset: ResetZoom), QuestMapFrame_ShowQuestDetails / OpenToQuestDetails / ReturnFromQuestDetails as Blizzard's do.
local W = { clock = 100, frames = {}, timers = {}, errors = {}, pings = {}, printed = {}, combat = false, cursor = { 500, 400 } }
_G.W = W
function GetTime() return W.clock end
function debugprofilestop() return W.clock * 1000 end
function InCombatLockdown() return W.combat end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCursorPosition() return W.cursor[1], W.cursor[2] end
function geterrorhandler() return function(e) W.errors[#W.errors + 1] = tostring(e) .. (W.trace and debug.traceback() or "") end end
function Clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
unpack = unpack or table.unpack
function collectgarbage() return 0 end
Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE, MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL = 0, 1
InputUtil = { IsGamepadUIEnabled = function() return false end }

-- frames: any method they don't have does nothing
local Frame = {}
local function NewFrame(kind)
  local f = { _kind = kind, _scripts = {}, _hooks = {}, _shown = true, _w = 0, _h = 0 }
  return setmetatable(f, Frame)
end
Frame.__index = function(t, k)
  local m = rawget(Frame, k)
  if m then return m end
  return function() return nil end
end
function Frame.SetScript(self, k, fn) self._scripts[k] = fn end
function Frame.GetScript(self, k) return self._scripts[k] end
function Frame.HookScript(self, k, fn) self._hooks[k] = self._hooks[k] or {} table.insert(self._hooks[k], fn) end
function Frame.Show(self) self._shown = true end
function Frame.Hide(self) self._shown = false end
function Frame.IsShown(self) return self._shown end
function Frame.IsVisible(self) return self._shown end
function Frame.SetShown(self, v) self._shown = v and true or false end
function Frame.SetSize(self, w, h) self._w, self._h = w, h end
function Frame.GetWidth(self) return self._w end
function Frame.GetHeight(self) return self._h end
function Frame.CreateTexture(self) return NewFrame("Texture") end
function Frame.CreateFontString(self) local f = NewFrame("FontString") f._text = "" return f end
function Frame.SetText(self, s) self._text = s end
function Frame.GetText(self) return self._text end
function Frame.GetFrameLevel() return 10 end
function Frame.GetEffectiveScale() return 1 end
function Frame.RegisterEvent() end
function CreateFrame(kind, name, parent)
  local f = NewFrame(kind or "Frame")
  if kind == "Frame" or kind == nil then f._shown = true end
  W.frames[#W.frames + 1] = f
  if name then _G[name] = f end
  return f
end
function W.Run(f, script, ...)
  local fn = f._scripts[script]
  if fn then fn(f, ...) end
  for _, h in ipairs(f._hooks[script] or {}) do h(f, ...) end
end

C_Timer = { After = function(t, fn) table.insert(W.timers, { at = W.clock + t, fn = fn }) end }
local function RunTimers()
  local due = {}
  for i = #W.timers, 1, -1 do if W.timers[i].at <= W.clock + 1e-9 then table.insert(due, 1, table.remove(W.timers, i)) end end
  for _, t in ipairs(due) do t.fn() end
end

-- hooksecurefunc: a global by name, or a table's method
function hooksecurefunc(a, b, c)
  local t, name, fn = _G, a, b
  if type(a) == "table" then t, name, fn = a, b, c end
  local orig = t[name]
  t[name] = function(...) local r1, r2 = orig(...) fn(...) return r1, r2 end
end

EventRegistry = { TriggerEvent = function(_, event, q) if event == "MapCanvas.PingQuestID" then table.insert(W.pings, { q = q, at = W.clock }) end end,
  RegisterCallback = function() end }
function CreateFromMixins(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
MapCanvasDataProviderMixin = {}

-- the maps: normalized rects on Azeroth's map (947); [mapID] = { l, r, t, b, type, parent }
W.maps = {
  [947] = { 0, 1, 0, 1, 1, 0, "Azeroth" },
  [1414] = { -0.18589, 0.63409, 0.06768, 0.88774, 2, 947, "Kalimdor" },
  [1415] = { 0.37148, 1.15916, 0.08150, 0.86910, 2, 947, "Eastern Kingdoms" },
  [1429] = { 0.69516, 0.77283, 0.59857, 0.67626, 3, 1415, "Elwynn Forest" },
  [1436] = { 0.66201, 0.74033, 0.64759, 0.72590, 3, 1415, "Westfall" },
  [1434] = { 0.67982, 0.82261, 0.70695, 0.84973, 3, 1415, "Stranglethorn Vale" },
  [1439] = { 0.12884, 0.27479, 0.21698, 0.36294, 3, 1414, "Darkshore" },
  [1453] = { 0.69096, 0.72984, 0.60046, 0.63934, 3, 1429, "Stormwind City" },
  [9999] = { nil, nil, nil, nil, 4, 1436, "The Deadmines" },        -- a dungeon's map (not stitched)
  [8888] = { nil, nil, nil, nil, 4, 1415, "An arena" },             -- another unstitched map, no entrance
}
C_Map = {}
function C_Map.GetMapInfo(id)
  local m = W.maps[id]
  if not m then return nil end
  return { mapID = id, mapType = m[5], parentMapID = m[6], name = m[7] }
end
W.player = { map = 1429, x = 0.42, y = 0.65 }
function C_Map.GetBestMapForUnit() return W.player.map end
function C_Map.GetPlayerMapPosition(id, unit)
  if id ~= W.player.map then return nil end
  return { x = W.player.x, y = W.player.y }
end

-- the stitched map (Stitch.lua's S), as far as WorldMap.lua and QuestFly.lua use it
local S = { WORLD = 947, stats = { zones = 0, tiles = 0, overlays = 0, pins = 0 } }
W.S = S
function S.Size() return 10000, 6667 end
function S.Rect(id) local m = W.maps[id] if m and m[1] then return m[1], m[2], m[3], m[4] end end
function S.ArtSize(id) if S.Rect(id) then return 1002, 668 end end
function S.Stitched() return true end
function S.IsBuilt() return true end
function S.Layout() return true end
function S.ChainAt(u, v)
  local chain = { 947 }
  for _, id in ipairs({ 1414, 1415, 1429, 1436, 1434, 1439, 1453 }) do
    local l, r, t, b = S.Rect(id)
    if u >= l and u <= r and v >= t and v <= b then chain[#chain + 1] = id end
  end
  return chain
end
for _, n in ipairs({ "SetShown", "SetPlayer", "RaiseArrow", "Recull", "SetZoom", "SetView", "RefreshExplored", "RefreshCities",
  "SetPinSetOn", "SetPlayerHidden", "SetPlacesFrom", "SetFoundOnly", "SetIconScale", "SetGapFillsShown", "ApplyGrade", "Build" }) do
  S[n] = function() end
end
function S.GetPinSet() end

-- Blizzard's world map: its frame, its scroll container (the canvas), its data providers
local map = CreateFrame("Frame", "WorldMapFrame")
map._shown = false
map.mapID = 1429
map.detailLayerPool = false
local sc = CreateFrame("ScrollFrame")
map.ScrollContainer = sc
sc:SetSize(1002, 668)
sc.Child = CreateFrame("Frame")
sc.mouseButtonInfo = { LeftButton = { down = false } }
sc.currentScale, sc.targetScale, sc.currentScrollX, sc.currentScrollY, sc.targetScrollX, sc.targetScrollY = 1, 1, 0.5, 0.5, 0.5, 0.5
sc.zoomLevels = {}
sc.gamepadZoom, sc.gamepadZoomSpeed = 0, 1
function sc:GetLeft() return 0 end
function sc:GetTop() return 668 end
function sc:GetCurrentScrollX() return self.currentScrollX end
function sc:GetCurrentScrollY() return self.currentScrollY end
function sc:GetCanvasScale() return self.currentScale end
function sc:NormalizeHorizontalSize(size) local aw = S.ArtSize(map.mapID) or 1002 return size / aw end
function sc:NormalizeVerticalSize(size) local _, ah = S.ArtSize(map.mapID) return size / (ah or 668) end
function sc:CalculateScrollExtentsAtScale(scale) return -10, 10, -10, 10 end
function sc:CalculateScrollExtents()
  self.scrollXExtentsMin, self.scrollXExtentsMax, self.scrollYExtentsMin, self.scrollYExtentsMax = self:CalculateScrollExtentsAtScale(self.currentScale)
end
function sc:CreateZoomLevels() end
function sc:ResetZoom() W.blizzardResets = (W.blizzardResets or 0) + 1 end
function sc:OnCanvasSizeChanged() self.mapID = map.mapID self:CreateZoomLevels() self:ResetZoom() end
function sc:IsMouseOver() return true end
function sc:SetNormalizedHorizontalScroll() if W.dp and W.dp.OnCanvasPanChanged then W.dp.OnCanvasPanChanged() end end
local fl = {}
function fl:InsertFrameLevelAbove() return true end
local LEVELS = { PIN_FRAME_LEVEL_MAP_EXPLORATION = 100, PIN_FRAME_LEVEL_VALHALLA_STITCH = 110, PIN_FRAME_LEVEL_VALHALLA_ICONS = 200 }
function fl:GetValidFrameLevel(name) return LEVELS[name] or 50 end
function map:GetPinFrameLevelsManager() return fl end
function map:GetMapID() return rawget(self, "mapID") end
function map:OnCanvasScaleChanged() if W.dp and W.dp.OnCanvasScaleChanged then W.dp.OnCanvasScaleChanged() end end
function map:GetCanvas() return sc.Child end
function map:EnumeratePinsByTemplate() return function() end end
map.dataProviders = {}
function map:AddDataProvider(dp) self.dataProviders[dp] = true W.dp = dp end
function map:SetMapID(id)
  assert(type(id) == "number", "SetMapID: not a map id")
  if self.mapID == id then return end
  self.mapID = id
  W.mapChanges = (W.mapChanges or 0) + 1
  sc:OnCanvasSizeChanged()                     -- (Blizzard: the new map's zoom levels, its view reset)
  if W.dp and W.dp.OnMapChanged then W.dp.OnMapChanged() end
end
function W.OpenMap()
  if map._shown then return end
  map._shown = true
  map.mapID = 0
  map:SetMapID(W.player.map)                   -- (Blizzard opens on where you are)
  if W.dp then W.dp.OnShow() end
end
function W.CloseMap()
  map._shown = false
  if W.dp then W.dp.OnHide() end
end

-- the quest log (Blizzard's QuestMapFrame functions, as the fly-to sees them)
W.quests = {}                                  -- [q] = { map = uiMapID, x, y (its marker), waypoint = { map, x, y } }
C_QuestLog = {}
function C_QuestLog.GetQuestsOnMap(id)
  local out = {}
  for q, info in pairs(W.quests) do
    if info.map == id and info.x then out[#out + 1] = { questID = q, x = info.x, y = info.y } end
  end
  return out
end
function C_QuestLog.GetNextWaypoint(q) local w = W.quests[q] and W.quests[q].waypoint return w and w[1] or nil end
function C_QuestLog.GetNextWaypointForMap(q, id)
  local w = W.quests[q] and W.quests[q].waypoint
  if w and w[1] == id then return w[2], w[3] end
end
function GetQuestUiMapID(q, ignoreWaypoints)
  local info = W.quests[q]
  if not info then return 0 end
  if info.waypoint and not ignoreWaypoints then return info.waypoint[1] end
  return info.map or 0
end
local details = CreateFrame("Frame")
details._shown = false
details.WaypointMapButton = CreateFrame("Button")
details.WaypointMapButton._shown = false
QuestMapFrame = { DetailsFrame = details }
W.ignoreWaypoints = {}
function QuestMapFrame_ShowQuestDetails(q)
  details.questID = q
  details:Show()
  details.returnMapID = rawget(details, "returnMapID") or rawget(map, "mapID")
  local ignore = W.ignoreWaypoints[q] and true or false
  details.WaypointMapButton:SetShown(ignore and C_QuestLog.GetNextWaypoint(q) ~= nil)
  local id = GetQuestUiMapID(q, ignore)
  details.questMapID = id
  if id ~= 0 then
    map:SetMapID(id)
    EventRegistry:TriggerEvent("MapCanvas.PingQuestID", q)
  end
end
function QuestMapFrame_OpenToQuestDetails(q)
  W.OpenMap()
  QuestMapFrame_ShowQuestDetails(q)
end
function QuestMapFrame_ReturnFromQuestDetails()
  if rawget(details, "returnMapID") then map:SetMapID(details.returnMapID) end
  details:Hide()
  details.questID, details.returnMapID = nil, nil
end
function QuestMapFrame_GetDetailQuestID() return rawget(details, "questID") end

-- one frame: the clock on, timers, every shown frame's OnUpdate, then the canvas's (Animate is hooked on it)
function W.Tick(dt)
  dt = dt or 1 / 60
  W.clock = W.clock + dt
  RunTimers()
  for _, f in ipairs(W.frames) do
    if f ~= sc and f._shown and (f._scripts.OnUpdate or f._hooks.OnUpdate) then W.Run(f, "OnUpdate", dt) end
  end
  if map._shown then W.Run(sc, "OnUpdate", dt) end
end
function W.Ticks(n, dt) for _ = 1, n do W.Tick(dt) end end
return S
