-- Dark Matter 0.5.2b: the game's objective tracker, READ ONLY. Beside each quest row: our own keep-tracked pin button;
-- over each quest title: our own transparent click area that opens the quest in Dark Matter; under the tracker: our own
-- "Ready to Turn In" section; and zone auto-track (on by default since 0.5.2b.1).
-- Taint rules: every frame here is Dark Matter's own, parented to UIParent and only POSITIONED by the tracker's blocks
-- (read-only anchors). Nothing is inserted into the tracker, no tracker frame gets a script, a hook or a new parent, and
-- watch-list changes happen only out of combat (queued until it ends).
local _, NS = ...
local UI = NS.UI

local Tr = { pins = {}, rows = {}, own = {}, ownAt = {}, queue = {}, log = {} }
NS.Tracker = Tr

local MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
Tr.TICK = 0.2       -- the overlays follow the tracker 5 times a second
Tr.BATCH = 5        -- auto-track: changes per batch
Tr.BATCH_GAP = 1    -- auto-track: seconds between batches
Tr.ZONE_GUARD = 3   -- a pinned quest the game untracks this soon after a zone change is tracked again
Tr.READY_MAX = 8
Tr.PIN_SIZE = 17   -- 0.5.2b.1: keep pins about 20% larger (were 14)
Tr.OWN_TTL = 5     -- our own watch changes are recognised for this long

local function N(v) return NS.Num(v) end
local function Now() return (type(GetTime) == "function" and GetTime()) or 0 end
local function InCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end
local function M(o, k) return type(o) == "table" and type(o[k]) == "function" end
local function Try(o, k, ...)
  if not M(o, k) then return nil end
  local ok, a, b = pcall(o[k], o, ...)
  if ok then return a, b end
end
local function DB() return NS.db end
local function Pins()
  local db = DB()
  if not db then return {} end
  if type(db.keepTracked) ~= "table" then db.keepTracked = {} end
  return db.keepTracked
end
Tr.Pins = Pins
function Tr.IsPinned(q) return q ~= nil and Pins()[q] == true end

---------------------------------------------------------------------------
-- the quest log (read only): { [questID] = { id, idx, title, zone } } and the watched set
---------------------------------------------------------------------------
local function ReadLog()
  local CQ = C_QuestLog
  local out, n = {}, 0
  if not (CQ and type(CQ.GetNumQuestLogEntries) == "function" and type(CQ.GetInfo) == "function") then return out, 0 end
  local ok, cnt = pcall(CQ.GetNumQuestLogEntries)
  cnt = ok and N(cnt) or 0
  local zone
  for i = 1, cnt do
    local ok2, info = pcall(CQ.GetInfo, i)
    if ok2 and type(info) == "table" then
      if info.isHeader == true then zone = NS.Str(info.title)
      elseif N(info.questID) and info.isHidden ~= true then
        local id = N(info.questID)
        out[id] = { id = id, idx = i, title = NS.Str(info.title) or ("Quest " .. id), zone = zone, questID = id, logIndex = i }
        n = n + 1
      end
    end
  end
  return out, n
end
Tr.ReadLog = ReadLog
local function Watched(log)
  local w = {}
  if not (NS.QL and NS.QL.CanWatch()) then return w end
  for id, e in pairs(log) do if NS.QL.IsWatched(e) then w[id] = true end end
  return w
end
Tr.Watched = Watched

-- change a watch, remembering it is ours (the snapshot diff then does not take it as yours)
local function SetWatch(e, want)
  if not NS.QL then return "noapi" end
  local id = N(e.id or e.questID)
  if id then Tr.own[id] = want and "add" or "remove" Tr.ownAt[id] = Now() end
  local r = NS.QL.SetWatched(e, want)
  if id and r ~= "ok" and r ~= "queued" then Tr.own[id] = nil Tr.ownAt[id] = nil end
  return r
end
Tr.SetWatch = SetWatch
local function Own(id, kind, now)
  if Tr.own[id] ~= kind then return false end
  local at = Tr.ownAt[id]
  Tr.own[id], Tr.ownAt[id] = nil, nil
  return at == nil or now - at <= Tr.OWN_TTL or InCombat()
end

---------------------------------------------------------------------------
-- keep-tracked pins (0.5.2b.1: a sticky flag, changed ONLY by a click on the pin). A pinned quest stays tracked in every
-- zone; an unpinned one follows zone auto-track (or the game, with auto-track off). Abandoning a quest drops its pin. Saved in DarkMatterDB.keepTracked = { [questID] = true }.
---------------------------------------------------------------------------
function Tr.SetPinned(q, on)
  q = N(q)
  if not q then return end
  Pins()[q] = on and true or nil
  if on then
    local e = Tr.log[q]
    if e and Tr.watch and not Tr.watch[q] then SetWatch(e, true) end
  end
  Tr.layoutDirty = true
  Tr.NotifyPins()
  if NS.SetStatus then NS.SetStatus(on and "Kept tracked: it stays in the objective tracker when you change zone." or "No longer kept tracked.") end
end

-- tell the Quests tab and the Quest Log panel to redraw
function Tr.NotifyPins()
  Tr.layoutDirty = true
  local t = NS.tabs and NS.tabs.quests
  if t and type(t.Refresh) == "function" then pcall(t.Refresh) end
end

-- 0.5.2b.1: the Track checkboxes are plain tracking (the pin is only the tracker's keep button). Returns checked, partly
-- (always false now), or nil when the client has no watch API.
function Tr.CheckState(q)
  local w = NS.QL and NS.QL.CanWatch() and type(q) == "table" and NS.QL.IsWatched(q)
  if w == nil then return nil end
  return w and true or false, false
end
-- a click on a Track box: track or untrack, nothing else (the pin is not touched; zone auto-track may change an
-- unpinned quest again on the next zone change)
function Tr.UserToggle(q)
  if type(q) ~= "table" or not NS.QL then return end
  local watched = NS.QL.IsWatched(q)
  local r = SetWatch(q, not watched) -- marked as ours: a deliberate untrack of a pinned quest is not taken for a zone drop
  Tr.diffDirty = true
  Tr.NotifyPins()
  return r
end

function Tr.Diff()
  local log, n = ReadLog()
  local w = Watched(log)
  if n == 0 and not Tr.watch then return end -- the log is not loaded yet: look again later
  local pins, now = Pins(), Now()
  local changed = false
  if Tr.watch then
    -- 0.5.2b.1: a pin changes only when you click it. Tracking and untracking (our boxes, the game's log, the game's
    -- auto-watch, zone auto-track) never pin or unpin; only a quest leaving the log drops its pin.
    for id in pairs(w) do if not Tr.watch[id] then Own(id, "add", now) end end -- consume our own marks
    for id in pairs(Tr.watch) do
      if not w[id] then
        local ours = Own(id, "remove", now)
        if not log[id] then if pins[id] then changed = true end pins[id] = nil -- abandoned or turned in
        elseif not ours and pins[id] and Tr.zoneAt and now - Tr.zoneAt <= Tr.ZONE_GUARD then
          SetWatch(log[id], true) -- the game dropped a pinned quest on a zone change: keep it
        end
      end
    end
  end
  -- a pin whose quest left the log goes (only when the log reads non-empty: it can read empty while loading)
  if n > 0 then for id in pairs(pins) do if not log[id] then pins[id] = nil end end end
  Tr.log, Tr.watch = log, w
  Tr.layoutDirty, Tr.readyDirty = true, true
  for id in pairs(Tr.own) do if Tr.ownAt[id] and now - Tr.ownAt[id] > Tr.OWN_TTL and not InCombat() then Tr.own[id], Tr.ownAt[id] = nil, nil end end
  if changed then Tr.NotifyPins() end
end

---------------------------------------------------------------------------
-- the keep icon: three game-icon styles; the first this client has unless you chose one (/dm keepicon). A chosen style
-- the client lacks draws nothing (no substitute).
---------------------------------------------------------------------------
Tr.KEEP_STYLES = {
  { key = "pin", on = "keepPin", off = "keepPinOff", what = "map pin (atlas Waypoint-MapPin-Tracked / -Untracked)" },
  { key = "lock", on = "keepLock", off = "keepLockOff", what = "lock (Interface\\Buttons\\LockButton-Locked-Up / -Unlocked-Up)" },
  { key = "star", on = "keepStar", off = "keepStar", what = "star (atlas PetJournal-FavoritesIcon, dimmed when not pinned)" },
}
function Tr.KeepStyle()
  local QS = NS.QS
  if not QS then return nil end
  local want = DB() and DB().keepIcon
  for _, s in ipairs(Tr.KEEP_STYLES) do
    if want and s.key == want then return QS.Icon(s.on) and s or nil end
  end
  for _, s in ipairs(Tr.KEEP_STYLES) do if QS.Icon(s.on) then return s end end
end

-- /dm keepicon [pin|lock|star|auto]: choose the style (auto = the first this client has). Returns ok, message.
function Tr.SetKeepIcon(key)
  local db = DB()
  if not db then return false, "not ready" end
  key = key or ""
  if key == "auto" then db.keepIcon = nil
  elseif key ~= "" then
    local found
    for _, s in ipairs(Tr.KEEP_STYLES) do if s.key == key then found = s end end
    if not found then return false, "keep icon: pin, lock, star or auto" end
    db.keepIcon = key
  end
  Tr.layoutDirty = true
  local s = Tr.KeepStyle()
  return true, "keep icon: " .. (db.keepIcon or "auto") .. " -> " .. (s and s.what or "MISSING on this client (nothing drawn)")
end

---------------------------------------------------------------------------
-- the tracker's quest rows (read only)
---------------------------------------------------------------------------
function Tr.TrackerFrame()
  local T = _G.ObjectiveTrackerFrame
  return type(T) == "table" and T or nil
end
function Tr.Blocks()
  local out = {}
  for _, name in ipairs(MODULES) do
    local m = _G[name]
    if type(m) == "table" and type(m.usedBlocks) == "table" then
      for _, set in pairs(m.usedBlocks) do
        if type(set) == "table" then
          for id, b in pairs(set) do
            local q = N(id) or (type(b) == "table" and N(b.id))
            if q and type(b) == "table" and Try(b, "IsVisible") == true then out[#out + 1] = { q = q, b = b } end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b2) return (Try(a.b, "GetTop") or 0) > (Try(b2.b, "GetTop") or 0) end)
  return out
end

local function Tip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(self.tipTitle or "", 1, 0.82, 0)
  if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end
  GameTooltip:Show()
end
local function Untip() if GameTooltip then GameTooltip:Hide() end end

local function MakeRow()
  local r = {}
  local pin = CreateFrame("Button", nil, UIParent)
  pin:SetSize(Tr.PIN_SIZE, Tr.PIN_SIZE)
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetAllPoints(pin)
  pin:RegisterForClicks("LeftButtonUp")
  pin:SetScript("OnClick", function(self) Tr.SetPinned(self.q, not Tr.IsPinned(self.q)) end)
  pin:SetScript("OnEnter", function(self)
    self.tipTitle = Tr.IsPinned(self.q) and "Kept tracked (Dark Matter)" or "Keep tracked (Dark Matter)"
    self.tipText = Tr.IsPinned(self.q) and "Pinned: it stays in the tracker in every zone. Click to unpin (it then follows zone auto-track from the next zone change)."
      or "Click to pin: this quest then stays in the tracker in every zone. Only this button pins or unpins."
    Tip(self)
  end)
  pin:SetScript("OnLeave", Untip)
  pin:Hide()
  local click = CreateFrame("Button", nil, UIParent)
  click:RegisterForClicks("LeftButtonUp")
  click:SetScript("OnClick", function(self) Tr.OpenQuest(self.q) end)
  click:SetScript("OnEnter", function(self)
    self.tipTitle = NS.QS and NS.QS.Title(self.q) or "Quest"
    self.tipText = "Click: show it in Dark Matter (map and quest log)"
    Tip(self)
  end)
  click:SetScript("OnLeave", Untip)
  click:Hide()
  r.pin, r.click = pin, click
  return r
end

local function Visible(f) return type(f) == "table" and Try(f, "IsVisible") == true end

-- place one row's pin and click area on block b (re-anchored only when the block or quest changes)
local function PlaceRow(r, b, q, style)
  local strata = Try(b, "GetFrameStrata") or "MEDIUM"
  local level = (N(Try(b, "GetFrameLevel")) or 1) + 5
  local head = type(b.HeaderText) == "table" and b.HeaderText or nil
  local poi = Visible(b.poiButton) and b.poiButton or nil
  local key = tostring(b) .. ":" .. q .. ":" .. tostring(poi ~= nil)
  local pin, click = r.pin, r.click
  if r.key ~= key then
    r.key = key
    pin:ClearAllPoints()
    if poi then pin:SetPoint("RIGHT", poi, "LEFT", -2, 0)
    else pin:SetPoint("RIGHT", head or b, "LEFT", -2, 0) end
    click:ClearAllPoints()
    if head then
      click:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
      click:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
    end
  end
  pin.q, click.q = q, q
  pin:SetFrameStrata(strata) pin:SetFrameLevel(level)
  click:SetFrameStrata(strata) click:SetFrameLevel(level)
  local on = Tr.IsPinned(q)
  local QS = NS.QS
  local look = style and (style.key .. (on and "+" or "-"))
  if look and pin.look == look then
    pin:Show()
  elseif style and QS and QS.PaintIcon(pin.icon, on and style.on or style.off) then
    pin.look = look
    if pin.icon.SetDesaturated then pin.icon:SetDesaturated(not on and style.on == style.off) end
    pin.icon:SetAlpha(on and 1 or 0.55)
    pin:Show()
  else
    pin.look = nil
    pin:Hide()
  end
  -- the title area stops short of the item button (and the quest's map button), so they stay uncovered
  if head then
    local item = b.ItemButton or b.itemButton
    local hl, hr = N(Try(head, "GetLeft")), N(Try(head, "GetRight"))
    local cut
    for _, o in ipairs({ item, poi }) do
      if Visible(o) then
        local ol, or2 = N(Try(o, "GetLeft")), N(Try(o, "GetRight"))
        if hl and hr and ol and or2 and ol < hr and or2 > hl and ol > hl then cut = math.min(cut or hr, ol) end
      end
    end
    if cut then
      click:ClearAllPoints()
      click:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
      click:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
      click:SetWidth(math.max(1, cut - hl - 2))
      r.key = nil
    end
    click.cut = cut
    click:Show()
  else
    click:Hide()
  end
end

function Tr.Layout()
  Tr.layoutDirty = false
  local T = Tr.TrackerFrame()
  local blocks = (T and Visible(T)) and Tr.Blocks() or {}
  local style = Tr.KeepStyle()
  local n = 0
  for _, it in ipairs(blocks) do
    n = n + 1
    local r = Tr.rows[n] or MakeRow()
    Tr.rows[n] = r
    PlaceRow(r, it.b, it.q, style)
  end
  for i = n + 1, #Tr.rows do Tr.rows[i].pin:Hide() Tr.rows[i].click:Hide() Tr.rows[i].key = nil end
  Tr.shown = n
  Tr.PlaceReady(blocks)
end

---------------------------------------------------------------------------
-- open a quest in Dark Matter: the Map tab, the docked Quest Log panel on its detail, a glide to it
---------------------------------------------------------------------------
function NS.OpenOnMap(q, keepPanel)
  if NS.ToggleWindow then NS.ToggleWindow(true) end
  local f = _G.DarkMatterFrame
  if not (f and f:IsShown()) then return false end
  if NS.ShowTab and not (NS.db and NS.db.tab == "map" and NS.tabs.map and NS.tabs.map.frame and NS.tabs.map.frame:IsShown()) then NS.ShowTab("map") end
  local P = NS.QuestPanel
  if P and not P.Wanted() then P.SetOpen(true) end
  if q then
    if NS.MapTab and NS.MapTab.ShowQuest then NS.MapTab.ShowQuest(q) end
    if P then P.OpenQuest(q) end
  elseif P and P.ShowList and not keepPanel then
    P.ShowList()
  end
  return true
end
function Tr.OpenQuest(q)
  q = N(q)
  if not q then return false end
  return NS.OpenOnMap(q)
end

---------------------------------------------------------------------------
-- Ready to Turn In: our own themed section under the tracker (placed by reading its bottom; never anchored into it)
---------------------------------------------------------------------------
local ready
local function ReadyRow(i)
  local r = ready.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, ready)
  r:SetHeight(30)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -2)
  r.title = UI.Text(r, "OVERLAY", 12, "gold", "LEFT")
  r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 20, -2)
  r.title:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.zone = UI.Text(r, "OVERLAY", 10, "listSoft", "LEFT")
  r.zone:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -1)
  r.zone:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints(r)
  r.hl:SetColorTexture(1, 0.82, 0.25, 0.12)
  r:RegisterForClicks("LeftButtonUp")
  r:SetScript("OnClick", function(self) Tr.ReadyClick(self.q) end)
  r:SetScript("OnEnter", function(self)
    self.tipTitle = self.titleText
    self.tipText = "Ready to turn in. Click: the game's arrow points to it, and Dark Matter shows it."
    Tip(self)
  end)
  r:SetScript("OnLeave", Untip)
  ready.rows[i] = r
  return r
end
local function BuildReady()
  if ready then return ready end
  ready = CreateFrame("Frame", "DarkMatterReadyFrame", UIParent)
  ready:SetSize(240, 40)
  ready:SetFrameStrata("LOW")
  ready.bg = ready:CreateTexture(nil, "BACKGROUND")
  ready.bg:SetAllPoints(ready)
  ready.bg:SetColorTexture(0.03, 0.03, 0.03, 0.78)
  UI.NineSlice(ready, "pane", 4, "BORDER", 1)
  ready.head = UI.Text(ready, "OVERLAY", 13, "gold", "LEFT")
  ready.head:SetPoint("TOPLEFT", ready, "TOPLEFT", 8, -6)
  ready.head:SetText("Ready to Turn In")
  ready.rows = {}
  ready:Hide()
  Tr.ready = ready
  return ready
end
function Tr.ReadyList()
  local out = {}
  local QS = NS.QS
  local list = {}
  for _, e in pairs(Tr.log) do list[#list + 1] = e end
  table.sort(list, function(a, b) return a.idx < b.idx end)
  for _, e in ipairs(list) do
    if QS and QS.Status(e.id) == "ready" then out[#out + 1] = e end
  end
  return out
end
function Tr.FillReady()
  Tr.readyDirty = false
  if DB() and DB().readySection == false then if ready then ready:Hide() end return end
  local list = Tr.ReadyList()
  Tr.readyCount = #list
  if #list == 0 then if ready then ready:Hide() end return end
  BuildReady()
  local n = math.min(#list, Tr.READY_MAX)
  for i = 1, n do
    local e, r = list[i], ReadyRow(i)
    r.q, r.titleText = e.id, e.title
    r.title:SetText(e.title)
    r.zone:SetText(e.zone or "")
    if not (NS.QS and NS.QS.PaintIcon(r.icon, "ready")) then r.icon:Hide() else r.icon:Show() end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", ready, "TOPLEFT", 6, -24 - (i - 1) * 32)
    r:SetPoint("RIGHT", ready, "RIGHT", -6, 0)
    r:Show()
  end
  for i = n + 1, #ready.rows do ready.rows[i]:Hide() end
  ready:SetHeight(30 + n * 32)
  ready.n = n
end
-- below the lowest visible quest row (or the tracker's header), converted to UIParent units; hidden without a tracker
function Tr.PlaceReady(blocks)
  if not ready or not ready.n or (Tr.readyCount or 0) == 0 or (DB() and DB().readySection == false) then if ready then ready:Hide() end return end
  local T = Tr.TrackerFrame()
  if not (T and Visible(T)) then ready:Hide() return end
  local us = N(Try(UIParent, "GetEffectiveScale")) or 1
  local function Y(f, v) return v and v * (N(Try(f, "GetEffectiveScale")) or us) / us end
  local left = Y(T, N(Try(T, "GetLeft")))
  local bottom
  for _, it in ipairs(blocks or {}) do
    local b = Y(it.b, N(Try(it.b, "GetBottom")))
    if b and (not bottom or b < bottom) then bottom = b end
  end
  if not bottom and type(T.Header) == "table" then bottom = Y(T.Header, N(Try(T.Header, "GetBottom"))) end
  if not bottom then bottom = Y(T, N(Try(T, "GetTop"))) end
  if not (left and bottom) then ready:Hide() return end
  local w = Y(T, N(Try(T, "GetWidth"))) or 240
  ready:SetWidth(math.max(180, math.min(w, 280)))
  if ready.x ~= left or ready.y ~= bottom then
    ready:ClearAllPoints()
    ready:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, bottom - 6)
    ready.x, ready.y = left, bottom
  end
  ready:Show()
end
function Tr.ReadyClick(q)
  q = N(q)
  if not q then return end
  local QS = NS.QS
  if QS and not QS.TrackQuest(q) then
    local loc = QS.Locate(q)
    if loc and not loc.zoneOnly then QS.SetWaypoint(loc.map, loc.x, loc.y, q) end
  end
  Tr.OpenQuest(q)
end

---------------------------------------------------------------------------
-- zone auto-track (on by default since 0.5.2b.1): this zone's quests plus pinned ones tracked, the rest untracked. Waits for a
-- flight to land, then switches once; changes go out in batches about a second apart, and never in combat.
---------------------------------------------------------------------------
function Tr.ZoneSet(log)
  local want = {}
  local zone = (type(GetZoneText) == "function" and GetZoneText()) or nil
  local real = (type(GetRealZoneText) == "function" and GetRealZoneText()) or nil
  for id, e in pairs(log) do
    if e.zone and (e.zone == zone or e.zone == real) then want[id] = true end
  end
  local MD = NS.MapData
  local here = MD and MD.PlayerMap()
  local z = here and (MD.ZoneOf(here) or here)
  if z and MD.Quests then
    for _, q in ipairs(MD.Quests(z) or {}) do if log[q.id] then want[q.id] = true end end
  end
  for id in pairs(Pins()) do if log[id] then want[id] = true end end
  return want
end
function Tr.Plan()
  local log = ReadLog()
  local w = Watched(log)
  local want = Tr.ZoneSet(log)
  local q = {}
  for id in pairs(w) do if not want[id] then q[#q + 1] = { e = log[id], want = false } end end
  local adds = {}
  for id in pairs(want) do if not w[id] then adds[#adds + 1] = { e = log[id], want = true } end end
  table.sort(q, function(a, b) return a.e.idx < b.e.idx end)
  table.sort(adds, function(a, b) return a.e.idx < b.e.idx end)
  for _, a in ipairs(adds) do q[#q + 1] = a end
  return q
end
function Tr.AutoWanted() return DB() and DB().autoTrack == true end
function Tr.SetAuto(on)
  if DB() then DB().autoTrack = on and true or false end
  Tr.queue = {}
  if on then Tr.zonePending = Now() end
end
local function OnTaxi() return type(_G.UnitOnTaxi) == "function" and _G.UnitOnTaxi("player") == true end
function Tr.AutoStep(now)
  if not Tr.AutoWanted() then
    -- auto-track off: the game's own tracking, except that pinned quests are tracked again after a zone change
    Tr.queue = {}
    if Tr.zonePending then
      if OnTaxi() then Tr.waitingTaxi = true return end
      if InCombat() then return end
      Tr.waitingTaxi, Tr.zonePending = nil, nil
      local log = ReadLog()
      local w = Watched(log)
      local ids = {}
      for id in pairs(Pins()) do if log[id] and not w[id] then ids[#ids + 1] = id end end
      table.sort(ids, function(a, b) return log[a].idx < log[b].idx end)
      for _, id in ipairs(ids) do if SetWatch(log[id], true) == "cap" then break end end
    end
    return
  end
  if Tr.zonePending then
    if OnTaxi() then Tr.waitingTaxi = true return end -- a flight: wait for the landing
    if InCombat() then return end
    Tr.waitingTaxi = nil
    Tr.zonePending = nil
    Tr.queue = Tr.Plan()
    Tr.nextBatch = now
  end
  if #Tr.queue == 0 or InCombat() or OnTaxi() or now < (Tr.nextBatch or 0) then return end
  local done = 0
  while done < Tr.BATCH and #Tr.queue > 0 do
    local it = table.remove(Tr.queue, 1)
    local r = SetWatch(it.e, it.want)
    done = done + 1
    if r == "cap" then -- the game's limit: the rest of the adds cannot go in
      local keep = {}
      for _, x in ipairs(Tr.queue) do if not x.want then keep[#keep + 1] = x end end
      Tr.queue = keep
    end
  end
  Tr.nextBatch = now + Tr.BATCH_GAP
  Tr.batches = (Tr.batches or 0) + 1
end

---------------------------------------------------------------------------
-- 0.5.2b.1: the tracker in quest-log order (zone groups, lowest level first, as the log shows them). The game's tracker
-- lists quests in WATCH order (C_QuestLog.GetQuestIDForQuestWatchIndex) and the game itself re-sorts that order on zone
-- changes (C_QuestLog.SortQuestWatches). So, out of combat and not in flight, about a second after the game's sort and
-- after auto-track: the quests from the first one out of place on are untracked and tracked again in log order (a new
-- watch goes to the end of the list). Only the public watch API is used; no tracker code or frame is touched. If the
-- order is still wrong afterwards (or a watch did not come back) it stops until the next zone change.
---------------------------------------------------------------------------
Tr.ORDER_SETTLE = 1  -- seconds after the last watch / zone event
Tr.ORDER_MAX = 10    -- re-orders a minute at most
function Tr.OrderWanted() return DB() ~= nil and DB().trackOrder ~= false end
function Tr.WatchOrder()
  local CQ = C_QuestLog
  if not (CQ and type(CQ.GetNumQuestWatches) == "function" and type(CQ.GetQuestIDForQuestWatchIndex) == "function") then return nil end
  local ok, n = pcall(CQ.GetNumQuestWatches)
  n = ok and N(n) or 0
  local out = {}
  for i = 1, n do
    local ok2, id = pcall(CQ.GetQuestIDForQuestWatchIndex, i)
    id = ok2 and N(id)
    if id then out[#out + 1] = id end
  end
  return out
end
-- the quests to track again, in log order (empty when the order is already right)
function Tr.OrderFix(order, log)
  local have = {}
  for _, id in ipairs(order) do if log[id] then have[#have + 1] = id end end
  local want = {}
  for i, id in ipairs(have) do want[i] = id end
  table.sort(want, function(a, b) return log[a].idx < log[b].idx end)
  local k = 0
  while k < #have and have[k + 1] == want[k + 1] do k = k + 1 end
  local fix = {}
  for i = k + 1, #want do fix[#fix + 1] = want[i] end
  return fix
end
function Tr.SetOrder(on)
  if DB() then DB().trackOrder = on and true or false end
  Tr.orderGaveUp = nil
  if on then Tr.orderDirty = Now() - Tr.ORDER_SETTLE end
end
function Tr.OrderStep(now)
  if not Tr.orderDirty or not Tr.OrderWanted() or Tr.orderGaveUp then return end
  if now < Tr.orderDirty + Tr.ORDER_SETTLE or InCombat() or OnTaxi() or Tr.zonePending or #Tr.queue > 0 then return end
  local order = Tr.WatchOrder()
  if not order then Tr.orderDirty = nil Tr.orderNote = "no watch-order API: the game's order stays" return end
  local log = ReadLog()
  local fix = Tr.OrderFix(order, log)
  Tr.orderDirty = nil
  if #fix == 0 then Tr.orderNote = "in log order" return end
  Tr.orderRuns = Tr.orderRuns or {}
  local recent = 0
  for _, t in ipairs(Tr.orderRuns) do if now - t < 60 then recent = recent + 1 end end
  if recent >= Tr.ORDER_MAX then Tr.orderGaveUp = true Tr.orderNote = "stopped: re-ordered too often this minute" return end
  Tr.orderRuns[#Tr.orderRuns + 1] = now
  while #Tr.orderRuns > Tr.ORDER_MAX do table.remove(Tr.orderRuns, 1) end
  -- all in this one tick, so the snapshot diff never sees a quest half way (it is tracked before and after: not yours)
  for _, id in ipairs(fix) do SetWatch(log[id], false) end
  local lost = 0
  for _, id in ipairs(fix) do if SetWatch(log[id], true) ~= "ok" then lost = lost + 1 end end
  for _, id in ipairs(fix) do Tr.own[id], Tr.ownAt[id] = nil, nil end
  Tr.orderFixed = (Tr.orderFixed or 0) + 1
  local again = Tr.WatchOrder()
  if lost > 0 or (again and #Tr.OrderFix(again, log) > 0) then
    Tr.orderGaveUp = true
    Tr.orderNote = lost > 0 and (lost .. " watch(es) did not come back: stopped until the next zone change")
      or "the game kept its own order: stopped until the next zone change"
  else
    Tr.orderNote = "re-ordered " .. #fix .. " to log order"
  end
end

---------------------------------------------------------------------------
-- events and the tick (our own private frame; the tracker itself is never touched)
---------------------------------------------------------------------------
Tr.EVENTS = { "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
  "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_CONTROL_GAINED", "ZONE_CHANGED" }
function Tr.OnEvent(event, a1)
  if event == "QUEST_WATCH_LIST_CHANGED" or event == "QUEST_ACCEPTED" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA"
    or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_CONTROL_GAINED" then
    Tr.orderDirty = Now() -- 0.5.2b.1: keep the tracker in log order (after the game's own re-sort)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then Tr.orderGaveUp = nil end
  end
  if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
    Tr.zoneAt = Now()
    Tr.zonePending = Now() -- auto-track re-plans; with it off, pinned quests are still tracked again
  elseif event == "PLAYER_CONTROL_GAINED" then -- 0.5.2b.1: landing after a flight (also after a stun or a cinematic)
    if Tr.waitingTaxi or Tr.zonePending then Tr.zonePending = Now() end
  elseif event == "QUEST_ACCEPTED" then
    if Tr.AutoWanted() then Tr.zonePending = Now() end
  elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
    local q = N(a1)
    if q then Pins()[q] = nil end
  end
  Tr.diffDirty = true
end
function Tr.Tick(now)
  now = now or Now()
  if Tr.diffDirty then Tr.diffDirty = false Tr.Diff() end
  Tr.AutoStep(now)
  Tr.OrderStep(now)
  if Tr.readyDirty then Tr.FillReady() end
  Tr.Layout()
end
function Tr.Start()
  if Tr.frame then return end
  local f = CreateFrame("Frame") -- private
  for _, e in ipairs(Tr.EVENTS) do pcall(f.RegisterEvent, f, e) end
  f:SetScript("OnEvent", function(_, e, a1) Tr.OnEvent(e, a1) end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < Tr.TICK then return end
    acc = 0
    Tr.Tick()
  end)
  Tr.frame = f
  Tr.zoneAt = Now()
  Tr.zonePending = Now()
  Tr.Diff()
  Tr.FillReady()
  Tr.orderDirty = Now()
end

-- /dm trackerprobe: what the overlays found (read only)
function Tr.Report()
  local T = Tr.TrackerFrame()
  local lines = { "trackerprobe " .. NS.version .. " (read-only)" }
  if not T then
    lines[#lines + 1] = "tracker: ObjectiveTrackerFrame not present: no pins, title clicks or ready section here (the Quests tab still works)"
  else
    lines[#lines + 1] = string.format("tracker: shown %s; quest rows visible %d; our pins/title areas %d", tostring(Visible(T)), #Tr.Blocks(), Tr.shown or 0)
  end
  local s = Tr.KeepStyle()
  lines[#lines + 1] = "keep icon: " .. (s and (s.key .. " = " .. s.what) or "NONE (the chosen style is missing on this client: nothing drawn)")
  for _, st in ipairs(Tr.KEEP_STYLES) do
    lines[#lines + 1] = string.format("  style %s: %s -> %s", st.key, st.what, (NS.QS and NS.QS.Icon(st.on)) and "ok" or "MISSING")
  end
  local np = 0
  for _ in pairs(Pins()) do np = np + 1 end
  lines[#lines + 1] = string.format("kept tracked: %d; ready to turn in: %d; zone auto-track %s; queued changes %d%s",
    np, Tr.readyCount or 0, Tr.AutoWanted() and "on" or "off", #Tr.queue, Tr.waitingTaxi and " (waiting for the flight to land)" or "")
  lines[#lines + 1] = string.format("tracker in log order: %s; watch-order API %s; re-orders %d; %s", Tr.OrderWanted() and "on" or "off",
    Tr.WatchOrder() and "ok" or "missing", Tr.orderFixed or 0, Tr.orderNote or "not checked yet")
  return lines
end
