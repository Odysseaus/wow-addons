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
-- 0.5.2b.7.1: laid out like the stock map's QuestBlob pin. The game draws the areas in the frame's own units at the
-- size the frame has when DrawBlob runs, so the frame keeps one fixed size (the zone picture's art size, like the stock
-- map canvas) and only its SetScale and anchor change with zoom and pan. The game makes the drawing for the scale the
-- frame has when DrawBlob runs (panning moves it with the frame; a new scale needs a new drawing, which is why the stock
-- pin redraws on every OnCanvasScaleChanged); 0.5.2b.7.3 draws it in the same frame, after the move (X.BlobDrawNow).
-- (0.5.2b.7 resized the frame in screen pixels and drew in the same frame, at the old size: the areas slid around.)
X.BLOB_W, X.BLOB_H = 1002, 668
-- 0.5.2b.7.3: how the areas are drawn again after a scale change (/dm blobdraw, DarkMatterDB.map.blobDraw):
--  same (default): in the SAME frame, right after this frame's layout has placed the area frame on its zone picture
--    (scale and anchor final, the rect resolved with GetRect), before anything is rendered: the stock pin's "wait until
--    the end of the frame" (QuestBlobPin OnCanvasScaleChanged -> MarkDirty -> its OnUpdate after the canvas moved).
--  next: 0.5.2b.7.2, at the start of the next frame, BEFORE that frame's layout: the areas were drawn for the previous
--    frame's scale, then the frame was rescaled, so every rendered zoom frame showed them one frame behind (the bounce).
--  once: never while zooming or gliding; drawn when the quests or the zone change and once the zoom stops.
X.BLOB_MODES = { same = true, next = true, once = true }
function X.BlobMode()
  local db = NS.db and NS.db.map
  local m = db and db.blobDraw
  return X.BLOB_MODES[m] and m or "same"
end
local function DrawState(f, st)
  if f.GetRect then pcall(f.GetRect, f) end -- resolve this frame's new scale and anchor before the game draws in it
  st.dirty = nil
  DrawBlobs(f, X.blobQuests or {}, f.key)
  st.drawn = st.scale
  st.drawnKey = st.key
  st.drawnTick = X.tickN or 0
  if M.Gliding and M.Gliding() then
    X.gl.redraws = X.gl.redraws + 1
    if st.drawnScaleOnly then X.gl.zoomRedraws = X.gl.zoomRedraws + 1 end
  end
end
-- draw the marked areas now: called at the end of every layout (after the zone pictures and the area frames are placed)
function X.BlobDrawNow()
  local mode = X.BlobMode()
  if mode == "next" then return end
  local gliding = M.Gliding and M.Gliding()
  for id, f in pairs(X.blobs) do
    local st = X.bst[id]
    if f and st and st.f == f and st.dirty and f.rect then
      -- once: a change of scale alone waits for the zoom to stop; a new quest set or a new frame is drawn at once
      local scaleOnly = st.drawnKey == st.key and st.drawnCW == st.cw
      if not (mode == "once" and gliding and scaleOnly) then
        st.drawnScaleOnly = scaleOnly
        DrawState(f, st)
        st.drawnCW = st.cw
      end
    end
  end
end

-- per-zone layout state kept off the frame (a frame answers unknown keys with its methods)
X.bst = {}
function X.BlobState(id, f)
  local st = X.bst[id]
  if not st or st.f ~= f then st = { f = f } X.bst[id] = st end
  return st
end
function X.BlobCanvas(id)
  local L = M.layers and M.layers[id]
  local a = L and L.art
  if a and (a.w or 0) > 0 and (a.h or 0) > 0 then return a.w, a.h end
  return X.BLOB_W, X.BLOB_H
end
function X.LayoutBlobs()
  local used = {}
  local quests = M.layersOn.quests ~= false and X.BlobQuests() or {}
  X.blobQuests = quests
  X.blobWant = {}
  if #quests > 0 and M.over then
    local key = table.concat(quests, ",")
    local vw, vh = M.over:GetWidth() or 0, M.over:GetHeight() or 0
    for _, c in ipairs(M.ContList and M.ContList() or {}) do
      if M.ContAlpha(c.id) > 0.5 then
        for _, z in ipairs(MD.Zones(c.id) or {}) do
          -- 0.5.2b.7.2: the areas go with their zone picture: shown (at its strength) for as long as the picture is
          -- drawn, so zooming out no longer drops them while the zone is still painted (0.5.2b.7.1 cut them at
          -- ZoneAlpha 0.6, mid-zoom); a zone whose picture is not drawn keeps the old rule
          local L = M.layers and M.layers[z.id]
          local la = (L and L.shown and (L.alpha or 0) > 0.01) and L.alpha or 0
          local ba = math.max(M.ZoneAlpha(z) > 0.6 and 1 or 0, math.min(1, la))
          if ba > 0 then
            local x1, x2, y1, y2 = M.WorldRect(z.id)
            local l, t = M.ToScreen(x1, y1)
            local r, b = M.ToScreen(x2, y2)
            if r > 0 and b > 0 and l < vw and t < vh and r - l > 8 then
              local f = BlobFrame(z.id)
              if f then
                used[z.id] = true
                X.blobWant[z.id] = true
                local st = X.BlobState(z.id, f)
                local tk = X.tickN or 0
                st.first = st.first or tk
                local cw, ch = X.BlobCanvas(z.id)
                local s = math.max((r - l) / cw, 0.0001)
                -- a change marks the frame for a redraw at the start of the NEXT frame (stock MarkDirty -> OnUpdate).
                -- 0.5.2b.7.2: the mark keeps its first frame (0.5.2b.7.1 moved it on every frame of a glide, so the
                -- redraw waited until the zoom stopped and the areas were blank meanwhile)
                if st.cw ~= cw or st.ch ~= ch then f:SetSize(cw, ch) st.cw, st.ch = cw, ch st.dirty = st.dirty or tk end
                if st.scale ~= s then f:SetScale(s) st.scale = s st.dirty = st.dirty or tk end
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", M.over, "TOPLEFT", l / s, -t / s)
                f:SetFrameLevel(M.over:GetFrameLevel())
                if st.key ~= key then st.key = key f.key = key st.dirty = st.dirty or tk end
                if st.alpha ~= ba then f:SetAlpha(ba) st.alpha = ba end
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
  X.BlobDrawNow()
end
-- the start of every frame: the frame counter, and (blobdraw next, the 0.5.2b.7.2 way) the areas marked in an earlier
-- frame are drawn before this frame's layout
function X.BlobFlush()
  X.tickN = (X.tickN or 0) + 1
  if X.BlobMode() ~= "next" then return end
  for id, f in pairs(X.blobs) do
    local st = X.bst[id]
    if st and st.f ~= f then st = nil end
    if f and st and st.dirty and f.rect and X.tickN > st.dirty then
      st.drawnScaleOnly = st.drawnKey == st.key
      DrawState(f, st)
    end
  end
end
-- /dm mapprobe 10e counters, at the END of every frame of a zoom or glide (after the layout, what will be rendered):
--  hidden: an area frame its zone needs is hidden or still blank (a new area gets one frame)
--  late: an area still waits for its redraw; stale: an area shows a drawing made at another scale (it would be off its
--  zone by "drawn vs shown" px); offset: the area frame against its zone picture, in screen pixels (the game's rects)
X.gl = { frames = 0, hidden = 0, late = 0, redraws = 0, zoomRedraws = 0, stale = 0, staleMax = 0, offMax = 0 }
function X.GlideCount()
  if not (M.Gliding and M.Gliding()) then return end
  local g = X.gl
  g.frames = g.frames + 1
  local hid, late, stale = false, false, false
  local es = M.over and M.over.GetEffectiveScale and Try(M.over.GetEffectiveScale, M.over) or 1
  for id in pairs(X.blobWant or {}) do
    local f, st = X.blobs[id], X.bst[id]
    if not (f and f:IsShown() and st) or (not st.drawnKey and (st.first or 0) < (X.tickN or 0) - 1) then hid = true end
    if st and st.dirty and st.dirty < (X.tickN or 0) then late = true end
    if st and st.drawn and st.scale and st.drawn ~= st.scale then
      stale = true
      local d = math.max(st.cw or 0, st.ch or 0) * math.abs(st.scale - st.drawn) * es
      if d > g.staleMax then g.staleMax = d end
    end
    local d = X.PicOffset(id)
    if d and d > g.offMax then g.offMax = d end
  end
  if hid then g.hidden = g.hidden + 1 end
  if late then g.late = g.late + 1 end
  if stale then g.stale = g.stale + 1 end
end
-- /dm mapprobe 10e: each area frame against its zone picture, in screen pixels (the game's own rects)
local function SRect(fr)
  if not (fr and fr.GetLeft and fr.GetEffectiveScale) then return nil end
  local ok, l, t, r, b, e = pcall(function() return fr:GetLeft(), fr:GetTop(), fr:GetRight(), fr:GetBottom(), fr:GetEffectiveScale() end)
  if ok and type(l) == "number" and type(t) == "number" and type(r) == "number" and type(b) == "number" and type(e) == "number" then
    return l * e, t * e, r * e, b * e
  end
end
-- 0.5.2b.7.3: one area frame against its zone picture, in screen pixels (nil when either is not on screen)
function X.PicOffset(id)
  local f = X.blobs[id]
  local L = M.layers and M.layers[id]
  if not (f and f.rect and f:IsShown() and L and L.shown) then return nil end
  local a1, a2, a3, a4 = SRect(f)
  local b1, b2, b3, b4 = SRect(L.frame)
  if not (a1 and b1) then return nil end
  return math.max(math.abs(a1 - b1), math.abs(a2 - b2), math.abs(a3 - b3), math.abs(a4 - b4))
end
-- 0.5.2b.7.3: what the area frames hold that could scale or snap on their own: child frames, regions (textures that
-- snap to the pixel grid), and the effective scale against the map's times the frame's own scale (0 = only ours)
function X.BlobFrameCheck()
  local kids, regs, snap, ed, n = 0, 0, 0, 0, 0
  local es = M.over and Try(M.over.GetEffectiveScale, M.over)
  for id, f in pairs(X.blobs) do
    local st = X.bst[id]
    if f and f:IsShown() and st and st.scale then
      n = n + 1
      kids = kids + (tonumber((Try(f.GetNumChildren, f))) or 0)
      local rs = { Try(f.GetRegions, f) }
      regs = regs + #rs
      for _, r in ipairs(rs) do if type(r) == "table" and Try(r.IsSnappingToPixelGrid, r) then snap = snap + 1 end end
      local fe = Try(f.GetEffectiveScale, f)
      if type(fe) == "number" and type(es) == "number" then ed = math.max(ed, math.abs(fe - es * st.scale) / math.max(fe, 1e-6)) end
    end
  end
  return n, kids, regs, snap, ed
end
function X.BlobCheck()
  local n, worst, wname, pend, nopic = 0, 0, nil, 0, 0
  for id, f in pairs(X.blobs) do
    if f and f.rect and f:IsShown() then
      n = n + 1
      local st = X.bst[id] or {}
      if st.dirty or st.drawn ~= st.scale then pend = pend + 1 end
      local L = M.layers and M.layers[id]
      local a1, a2, a3, a4 = SRect(f)
      local b1, b2, b3, b4 = SRect(L and L.shown and L.frame)
      if a1 and b1 then
        local d = math.max(math.abs(a1 - b1), math.abs(a2 - b2), math.abs(a3 - b3), math.abs(a4 - b4))
        if d > worst or not wname then worst, wname = d, MD.Name(id) or tostring(id) end
      else
        nopic = nopic + 1
      end
    end
  end
  return n, worst, wname, pend, nopic
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
function M.ExtrasPreTick()
  if not M.over then return end
  X.BlobFlush()
end
function M.ExtrasTick(dt)
  if not M.over then return end
  X.BlobDrawNow() -- blobdraw once: the redraw when the zoom has stopped
  X.GlideCount()
  X.tg = (X.tg or 0) + dt
  if X.tg >= X.GROUP_EVERY then X.tg = 0 X.LayoutGroup() end
  X.tc = (X.tc or 0) + dt
  if X.tc >= X.CORPSE_EVERY then X.tc = 0 X.LayoutCorpse() end
  X.th = (X.th or 0) + dt
  if X.th >= X.HOVER_EVERY then X.th = 0 BlobHover() end
end
-- 0.5.2b.7.3: /dm blobdraw [same|next|once]: when the quest areas are drawn again after a scale change (X.BlobMode);
-- saved in DarkMatterDB.map.blobDraw; the 10e zoom counters start again
function M.BlobDrawSlash(arg)
  arg = arg and arg:lower():match("^%s*(%S*)") or ""
  local say = "same (default: in the frame of the move), next (0.5.2b.7.2), once (only when the zoom stops)"
  if arg ~= "" then
    if not X.BLOB_MODES[arg] and arg ~= "default" then return "blobdraw: " .. say end
    if not NS.db then return "blobdraw: saved settings not loaded yet" end
    NS.db.map = NS.db.map or {}
    NS.db.map.blobDraw = (arg ~= "same" and arg ~= "default") and arg or nil
    for k in pairs(X.gl) do X.gl[k] = 0 end
    for _, st in pairs(X.bst) do st.dirty = st.dirty or (X.tickN or 0) end
    M.dirty = true
  end
  return "blobdraw: " .. X.BlobMode() .. " - " .. say .. "; /dm mapprobe 10e counts each zoom"
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
  do
    local n, worst, wname, pend, nopic = X.BlobCheck()
    out[#out + 1] = n == 0 and "map 10e: quest areas vs zone picture: none on screen (select a quest, look again)"
      or string.format("map 10e: areas vs zone picture: %d, worst %.1f px (%s) -> %s", n, worst, tostring(wname):sub(1, 18),
        (nopic > 0 and "no picture") or (worst <= 1.5 and "OK") or "OFF")
    if n > 0 then out[#out + 1] = string.format("map 10e: redraw pending %d, no picture %d, canvas %dx%d", pend, nopic, X.BLOB_W, X.BLOB_H) end
    local g = X.gl
    out[#out + 1] = string.format("map 10e: hidden during zoom: %d frames; late %d; zoom frames %d; redraws %d",
      g.hidden, g.late, g.frames, g.redraws)
    out[#out + 1] = string.format("map 10e: zoom: redraws %d (scale only %d); stale %d frames, drawn vs shown %.1f px",
      g.redraws, g.zoomRedraws, g.stale, g.staleMax)
    out[#out + 1] = string.format("map 10e: zoom offset: area vs zone picture max %.1f px; draw %s (/dm blobdraw)", g.offMax, X.BlobMode())
    local fn, kids, regs, snap, ed = X.BlobFrameCheck()
    if fn > 0 then
      out[#out + 1] = string.format("map 10e: area frames %d: children %d, regions %d, pixel-snapped %d, scale %s", fn, kids, regs, snap,
        ed < 1e-4 and "ours only" or string.format("OFF by %.4f", ed))
    end
  end
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
