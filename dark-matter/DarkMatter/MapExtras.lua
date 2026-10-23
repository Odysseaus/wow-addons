-- 0.5.2b.7 Map tab extras, drawn over the map pictures like the stock map's own pins:
--  * quest objective areas: the game's QuestPOIFrame (the stock map's QuestBlob pin: SetFillTexture / DrawBlob) for the
--    tracked quests and the selected one, one frame per zone on screen; hovering an area names the quest and its objectives
--  * party and raid members: the stock map's party dot (Interface\WorldMap\WorldMapPartyIcon), class-coloured in a raid,
--    dimmed when the member is in another zone or out of range; a tooltip with name, level, class and zone
--  * your corpse while dead or a ghost: the stock map's tombstone (CorpsePinTemplate: Interface\Minimap\POIIcons),
--    placed by C_DeathInfo.GetCorpseMapPosition; tooltip "Your corpse"
-- Game art only (QuestState.lua roles groupDot / corpse); a client without one draws nothing (/dm mapprobe says so).
-- Plain frames and textures, no hooks or protected calls.
local _, NS = ...
local M, MD = NS.MapTab, NS.MapData
if not (M and MD) then return end

local X = { blobs = {}, group = {}, stats = {} }
M.X = X
X.GROUP_EVERY = 0.2   -- group dots move 5 times a second
X.CORPSE_EVERY = 0.5
X.HOVER_EVERY = 0.1
X.DIM = 0.4
X.BLOB_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
X.BLOB_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"

local function G(name) return _G[name] end
local function Try(f, ...) if type(f) ~= "function" then return nil end local r = { pcall(f, ...) } if r[1] then return select(2, unpack(r)) end end

---------------------------------------------------------------------------
-- quest objective areas
---------------------------------------------------------------------------
-- the quests whose areas are shaded: the selected one and the tracked (watched) ones
function X.BlobQuests()
  local QS = NS.QS
  local out, seen = {}, {}
  local function add(q) if type(q) == "number" and q > 0 and not seen[q] then seen[q] = true out[#out + 1] = q end end
  if QS then
    add(QS.selected)
    if QS.IsWatched then
      for _, q in ipairs(X.LogQuestIDs()) do if QS.IsWatched(q) then add(q) end end
    end
  end
  table.sort(out)
  return out
end
-- every quest ID in the log (both APIs; headers skipped)
function X.LogQuestIDs()
  local ids = {}
  local CQ = G("C_QuestLog")
  local n = (CQ and Try(CQ.GetNumQuestLogEntries)) or Try(G("GetNumQuestLogEntries")) or 0
  for i = 1, tonumber(n) or 0 do
    local info = CQ and Try(CQ.GetInfo, i)
    if type(info) == "table" then
      if not info.isHeader and type(info.questID) == "number" then ids[#ids + 1] = info.questID end
    else
      local r = { Try(G("GetQuestLogTitle"), i) }
      if r[1] and not r[4] and type(r[8]) == "number" then ids[#ids + 1] = r[8] end
    end
  end
  return ids
end
-- the game's own quest-area frame for a zone (nil when this client cannot make one)
local function BlobFrame(id)
  local b = X.blobs[id]
  if b ~= nil then return b or nil end
  local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, M.over)
  if not ok or type(f) ~= "table" or type(f.DrawBlob) ~= "function" then
    X.blobs[id] = false
    X.blobFail = ok and "no DrawBlob" or tostring(f)
    return nil
  end
  Try(f.EnableMouse, f, false) -- the map underneath keeps the drag; hovering is read in X.Tick
  Try(f.SetFillTexture, f, X.BLOB_FILL)
  Try(f.SetBorderTexture, f, X.BLOB_BORDER)
  Try(f.SetFillAlpha, f, 128)
  Try(f.SetBorderAlpha, f, 192)
  Try(f.SetBorderScalar, f, 1.0)
  Try(f.SetMapID, f, id)
  f.mapID = id
  X.blobs[id] = f
  X.stats.blobFrames = (X.stats.blobFrames or 0) + 1
  return f
end
local function DrawBlobs(f, quests, key)
  Try(f.DrawNone, f)
  for _, q in ipairs(quests) do Try(f.DrawBlob, f, q, true) end
  f.key = key
  X.stats.blobDraws = (X.stats.blobDraws or 0) + 1
end
function X.LayoutBlobs()
  local used = {}
  local quests = M.layersOn.quests ~= false and X.BlobQuests() or {}
  X.blobQuests = quests
  if #quests > 0 and M.over then
    local key = table.concat(quests, ",")
    local vw, vh = M.over:GetWidth() or 0, M.over:GetHeight() or 0
    for _, c in ipairs(M.ContList and M.ContList() or {}) do
      if M.ContAlpha(c.id) > 0.5 then
        for _, z in ipairs(MD.Zones(c.id) or {}) do
          if M.ZoneAlpha(z) > 0.6 then
            local x1, x2, y1, y2 = M.WorldRect(z.id)
            local l, t = M.ToScreen(x1, y1)
            local r, b = M.ToScreen(x2, y2)
            -- on screen, and a quest of the set is on this zone (or the selected one, which may have no marker)
            if r > 0 and b > 0 and l < vw and t < vh and r - l > 8 then
              local f = BlobFrame(z.id)
              if f then
                used[z.id] = true
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", M.over, "TOPLEFT", l, -t)
                f:SetSize(r - l, b - t)
                f:SetFrameLevel(M.over:GetFrameLevel())
                -- the game rasterises the areas at the frame's size: drawn again when the set changes or the size jumps
                local w = r - l
                if f.key ~= key or not f.drawnW or w > f.drawnW * 1.25 or w < f.drawnW / 1.25 then
                  DrawBlobs(f, quests, key)
                  f.drawnW = w
                end
                f.rect = { l, t, r, b }
                f:Show()
              end
            end
          end
        end
      end
    end
  end
  for id, f in pairs(X.blobs) do if f and not used[id] then f:Hide() f.rect = nil end end
end
-- the quest under the cursor in a quest area: the game answers a quest ID (or a log index on old clients)
function X.BlobAt(px, py)
  for _, f in pairs(X.blobs) do
    local r = f and f.rect
    if r and f:IsShown() and px >= r[1] and px <= r[3] and py >= r[2] and py <= r[4] and type(f.UpdateMouseOverTooltip) == "function" then
      local ok, v, n = pcall(f.UpdateMouseOverTooltip, f, (px - r[1]) / (r[3] - r[1]), (py - r[2]) / (r[4] - r[2]))
      if ok and type(v) == "number" and v > 0 then
        local q
        for _, id in ipairs(X.blobQuests or {}) do if id == v then q = v end end
        if not q then
          local info = G("C_QuestLog") and Try(G("C_QuestLog").GetInfo, v)
          if type(info) == "table" and type(info.questID) == "number" then q = info.questID
          else local r8 = select(8, Try(G("GetQuestLogTitle"), v)) if type(r8) == "number" then q = r8 end end
        end
        if q then return q, f, n end
      end
    end
  end
end
local function BlobHover()
  local tip = G("GameTooltip")
  if not tip then return end
  local q, f
  if M.MouseOver() then
    local px, py = M.Cursor()
    q, f = X.BlobAt(px, py)
  end
  local owner = Try(tip.GetOwner, tip)
  if q then
    if owner ~= nil and not owner.isDMBlob then return end -- a marker or a member dot has the tooltip
    if X.tipQuest ~= q then
      f.isDMBlob = true
      tip:SetOwner(f, "ANCHOR_CURSOR")
      tip:SetText(MD.QuestTitle(q), 1, 0.82, 0)
      if (M.AddObjectiveLines and M.AddObjectiveLines(q) or 0) == 0 then tip:AddLine("Quest objective area", 0.85, 0.85, 0.85) end
      tip:Show()
      X.tipQuest = q
    end
  elseif X.tipQuest then
    X.tipQuest = nil
    if owner == nil or owner.isDMBlob then tip:Hide() end
  end
end

---------------------------------------------------------------------------
-- party and raid members
---------------------------------------------------------------------------
function X.GroupUnits()
  local units = {}
  if Try(G("IsInRaid")) then
    local n = Try(G("GetNumGroupMembers")) or 0
    for i = 1, tonumber(n) or 0 do
      local u = "raid" .. i
      if Try(G("UnitExists"), u) and not Try(G("UnitIsUnit"), u, "player") then units[#units + 1] = u end
    end
    return units, true
  end
  for i = 1, 4 do
    local u = "party" .. i
    if Try(G("UnitExists"), u) then units[#units + 1] = u end
  end
  return units, false
end
local function ClassColor(cls)
  local t = G("RAID_CLASS_COLORS")
  local c = type(t) == "table" and cls and t[cls]
  if type(c) == "table" and c.r then return c.r, c.g, c.b end
  local CC = G("C_ClassColor")
  if CC and cls then local col = Try(CC.GetClassColor, cls) if type(col) == "table" and col.r then return col.r, col.g, col.b end end
end
-- a member's place: world coords, the map they are on, and whether to dim them (another zone, or out of range)
function X.MemberPos(u)
  local m = MD.UnitMap(u)
  if not m then return nil end
  local cont = MD.ContinentOf(m)
  local wx, wy
  if cont and (M.hasWorld or cont == M.only) then
    local x, y = MD.UnitPos(cont, u)
    if x then wx, wy = M.ToW(cont, x, y)
    else
      local z = MD.ZoneOf(m) or m
      local zx, zy = MD.UnitPos(z, u)
      if zx then wx, wy = M.ToW(z, zx, zy) end
    end
  end
  if not wx then return nil end
  local mine = M.player and M.player.map
  local zone, myZone = MD.ZoneOf(m) or m, mine and (MD.ZoneOf(mine) or mine)
  local inRange, checked = Try(G("UnitInRange"), u)
  local far = (myZone ~= nil and zone ~= myZone) or (checked and not inRange) or false
  return wx, wy, m, far
end
local function MakeMember()
  local b = CreateFrame("Button", nil, M.over)
  b:SetSize(16, 16)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b:SetScript("OnEnter", function(self)
    local tip = G("GameTooltip")
    if not (tip and self.unit) then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local name = Try(G("UnitName"), self.unit) or self.unit
    local r, g, bl = ClassColor(self.cls)
    tip:SetText(name, r or 1, g or 1, bl or 1)
    local lv = Try(G("UnitLevel"), self.unit)
    local cname = Try(G("UnitClass"), self.unit)
    tip:AddLine(((type(lv) == "number" and lv > 0) and ("Level " .. lv) or "Level ??") .. (cname and (" " .. cname) or ""), 0.9, 0.9, 0.9)
    local zone = self.map and (MD.Name(MD.ZoneOf(self.map) or self.map) or MD.Name(self.map))
    if zone then tip:AddLine(zone, 0.85, 0.85, 0.85) end
    if self.far then tip:AddLine("Out of range", 0.6, 0.6, 0.6) end
    tip:Show()
  end)
  b:SetScript("OnLeave", function() local tip = G("GameTooltip") if tip then tip:Hide() end end)
  b:SetScript("OnMouseDown", function(_, btn) if M.VpDown then M.VpDown(btn) end end)
  b:SetScript("OnMouseUp", function(_, btn) if M.VpUp then M.VpUp(btn) end end)
  return b
end
function X.LayoutGroup()
  M.PoolReset("member")
  local QS = NS.QS
  local units, raid = X.GroupUnits()
  local vw, vh = M.over:GetWidth() or 0, M.over:GetHeight() or 0
  X.stats.members = 0
  if #units > 0 and QS and QS.Icon("groupDot") then
    for _, u in ipairs(units) do
      local wx, wy, m, far = X.MemberPos(u)
      if wx then
        local sx, sy = M.ToScreen(wx, wy)
        if sx >= 0 and sy >= 0 and sx <= vw and sy <= vh then
          local b = M.Pool("member", MakeMember)
          QS.PaintIcon(b.icon, "groupDot")
          local _, cls = Try(G("UnitClass"), u)
          b.unit, b.map, b.far, b.cls = u, m, far, cls
          local r, g, bl = ClassColor(cls)
          if raid and r then
            b.icon:SetDesaturated(true)
            b.icon:SetVertexColor(r, g, bl)
          else
            b.icon:SetDesaturated(false)
            b.icon:SetVertexColor(1, 1, 1)
          end
          b:SetAlpha(far and X.DIM or 1)
          b:SetFrameLevel(M.over:GetFrameLevel() + 4)
          b:ClearAllPoints()
          b:SetPoint("CENTER", M.over, "TOPLEFT", sx, -sy)
          b:Show()
          X.stats.members = X.stats.members + 1
        end
      end
    end
  end
  M.PoolHideRest("member")
end

---------------------------------------------------------------------------
-- your corpse
---------------------------------------------------------------------------
-- world coords of the corpse, or nil (alive, or the game gives no position on this map)
function X.CorpseWorld()
  if not Try(G("UnitIsDeadOrGhost"), "player") then return nil end
  local DI = G("C_DeathInfo")
  if not (DI and type(DI.GetCorpseMapPosition) == "function") then return nil end
  local m = MD.PlayerMap()
  if not m then return nil end
  local cont = MD.ContinentOf(m)
  local z = MD.ZoneOf(m) or m
  for _, id in ipairs({ cont, z }) do
    if id and (M.hasWorld or MD.ContinentOf(id) == M.only or id == M.only) then
      local x, y = MD.Vec(Try(DI.GetCorpseMapPosition, id))
      if x then
        local wx, wy = M.ToW(id, x, y)
        if wx then return wx, wy end
      end
    end
  end
end
local function MakeCorpse()
  local b = CreateFrame("Button", nil, M.over)
  b:SetSize(24, 24) -- the stock pin's size
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b:SetScript("OnEnter", function(self)
    local tip = G("GameTooltip")
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:SetText("Your corpse", 1, 0.125, 0.125) -- the stock tooltip is CORPSE_RED
    tip:Show()
  end)
  b:SetScript("OnLeave", function() local tip = G("GameTooltip") if tip then tip:Hide() end end)
  b:SetScript("OnMouseDown", function(_, btn) if M.VpDown then M.VpDown(btn) end end)
  b:SetScript("OnMouseUp", function(_, btn) if M.VpUp then M.VpUp(btn) end end)
  return b
end
function X.LayoutCorpse()
  local QS = NS.QS
  local wx, wy = X.CorpseWorld()
  X.corpse = wx and { wx, wy } or nil
  local b = X.corpseBtn
  if not wx or not (QS and QS.Icon("corpse")) then if b then b:Hide() end return end
  if not b then b = MakeCorpse() X.corpseBtn = b end
  QS.PaintIcon(b.icon, "corpse")
  local sx, sy = M.ToScreen(wx, wy)
  b:SetFrameLevel(M.over:GetFrameLevel() + 5)
  b:ClearAllPoints()
  b:SetPoint("CENTER", M.over, "TOPLEFT", sx, -sy)
  b:Show()
end

---------------------------------------------------------------------------
-- hooks from Tab_Map.lua: after every overlay layout, and every frame while the tab is shown
---------------------------------------------------------------------------
function M.DrawExtras()
  if not M.over then return end
  X.LayoutBlobs()
  X.LayoutGroup()
  X.LayoutCorpse()
end
function M.ExtrasTick(dt)
  if not M.over then return end
  X.tg = (X.tg or 0) + dt
  if X.tg >= X.GROUP_EVERY then X.tg = 0 X.LayoutGroup() end
  X.tc = (X.tc or 0) + dt
  if X.tc >= X.CORPSE_EVERY then X.tc = 0 X.LayoutCorpse() end
  X.th = (X.th or 0) + dt
  if X.th >= X.HOVER_EVERY then X.th = 0 BlobHover() end
end
-- the events that change what is drawn here (each registered only if this client has it)
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() M.dirty = true end)
X.events = {}
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "CORPSE_POSITION_UPDATE", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
  if pcall(ev.RegisterEvent, ev, e) then X.events[#X.events + 1] = e end
end

-- /dm mapprobe lines (read-only checks; nothing is drawn); each line stays under 90 characters
function X.ProbeLines()
  local QS = NS.QS
  local out = {}
  local function yn(v) return v and "yes" or "no" end
  local TOK = NS.Stock and NS.Stock.TextureOK
  local qf = next(X.blobs) == nil and "not made yet" or (X.blobFail and "NOT available" or "yes")
  out[#out + 1] = "map 10b: Map tab quest areas: QuestPOIFrame " .. qf .. "; fill " .. yn(TOK and TOK(X.BLOB_FILL))
    .. "; border " .. yn(TOK and TOK(X.BLOB_BORDER))
  if X.blobFail then out[#out + 1] = "map 10b why: " .. tostring(X.blobFail):sub(1, 70) end
  if QS then
    local function roles(list)
      local parts = {}
      for _, r in ipairs(list) do parts[#parts + 1] = r:gsub("^poi", "") .. " " .. (QS.Icon(r) and "yes" or "NO") end
      return table.concat(parts, ", ")
    end
    out[#out + 1] = "map 10c: POI icons: " .. roles({ "poiRing", "poiRingSel", "poiGlow" })
    out[#out + 1] = "map 10c: POI symbols: " .. roles({ "poiProgress", "poiProgressSel", "poiComplete" })
    out[#out + 1] = "map 10c: group dot " .. (QS.Icon("groupDot") and "yes" or "NO") .. "; corpse tombstone " .. (QS.Icon("corpse") and "yes" or "NO")
    out[#out + 1] = "map 10c: player arrow: " .. (QS.Icon("playerArrow") and ("game (" .. tostring(QS.Icon("playerArrow").file or QS.Icon("playerArrow").atlas) .. ")") or "NOT in this client (Dark Matter's)")
  end
  local DI = G("C_DeathInfo")
  out[#out + 1] = "map 10d: GetCorpseMapPosition " .. yn(DI and type(DI.GetCorpseMapPosition) == "function")
    .. "; dead " .. yn(Try(G("UnitIsDeadOrGhost"), "player")) .. "; group " .. #X.GroupUnits()
    .. "; UnitInRange " .. yn(type(G("UnitInRange")) == "function")
  return out
end
