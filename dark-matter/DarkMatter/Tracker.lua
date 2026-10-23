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
-- Ready to Turn In (0.5.2b.2, option C): our OWN frame, a child of UIParent, placed just below the visible bottom of the
-- whole objective tracker. The tracker is only READ (positions, sizes, IsVisible): never a parent, never an anchor
-- target, no hook, nothing inserted. The header copies the tracker's module headers (the Professions header): the same
-- header atlas, header font and collapse/expand button. Starts collapsed; DarkMatterDB.readyCollapsed keeps the choice.
---------------------------------------------------------------------------
Tr.READY_POLL = 0.1  -- the section re-reads the tracker's bottom 10 times a second
Tr.HEADER_H = 26     -- ObjectiveTrackerModuleHeaderTemplate: 260 x 26
Tr.HEADER_GAP = 10   -- the module's fromHeaderOffsetY (header -> first block)
Tr.READY_ATLAS = {
  bg = "UI-QuestTracker-Secondary-Objective-Header",
  collapse = "ui-questtrackerbutton-secondary-collapse", collapsePressed = "ui-questtrackerbutton-secondary-collapse-pressed",
  expand = "ui-questtrackerbutton-secondary-expand", expandPressed = "ui-questtrackerbutton-secondary-expand-pressed",
  highlight = "ui-questtrackerbutton-yellow-highlight",
}
local ready
-- a game atlas, or nothing (no substitute) where this client lacks it
local function Atlas(t, name)
  local CT = C_Texture
  if type(CT) == "table" and type(CT.GetAtlasInfo) == "function" then
    local ok, info = pcall(CT.GetAtlasInfo, name)
    if ok and not info then t:Hide() return false end
  end
  t:SetAtlas(name, true)
  t:Show()
  return true
end
function Tr.ReadyCollapsed()
  local db = DB()
  return not (db and db.readyCollapsed == false)
end
local function PaintToggle()
  local A, b = Tr.READY_ATLAS, ready.toggle
  local c = Tr.ReadyCollapsed()
  local name = c and (rawget(b, "down") and A.expandPressed or A.expand) or (rawget(b, "down") and A.collapsePressed or A.collapse)
  Atlas(b.icon, name)
  b.atlas = name
  if ready.header and not ready.header.bg:IsShown() then Atlas(ready.header.bg, A.bg) end -- (atlas data can arrive late)
  if not b.hl:IsShown() and Atlas(b.hl, A.highlight) then b.hl:SetBlendMode("ADD") end
end
function Tr.SetReadyCollapsed(on)
  local db = DB()
  if db then db.readyCollapsed = on and true or false end
  if ready then PaintToggle() end
  Tr.FillReady()
  Tr.PlaceReady()
end
-- 0.5.2b.7.3: each row is drawn like one of the tracker's own quest blocks (Blizzard_ObjectiveTrackerBlock.xml):
--  * the icon is the game's own POI button for a completed quest (ObjectiveTrackerPOIButtonTemplate with
--    POIButtonUtil.Style.QuestComplete: "UI-QuestIcon-TurnIn-Normal" on the "UI-QuestPoi-QuestNumber" face,
--    "-SuperTracked" face when the quest is super tracked), placed like the tracker places it
--    (TOPRIGHT of the button on the title's TOPLEFT, -7, 5). Where the template is missing: the same two atlases.
--  * title and second line use ObjectiveTrackerLineFont (the font of the block's HeaderText and of its lines);
--    colours are OBJECTIVE_TRACKER_COLOR: title "Header", hover "HeaderHighlight" (or the quest difficulty colour
--    when showQuestDifficultyColor is on, as ObjectiveTrackerBlockMixin:UpdateHighlight does); line "Normal",
--    hover "NormalHighlight". No backdrop and no highlight plate, like the tracker.
Tr.READY_ICON = { style = "QuestComplete", template = "ObjectiveTrackerPOIButtonTemplate",
  atlas = "UI-QuestIcon-TurnIn-Normal", face = "UI-QuestPoi-QuestNumber", faceSel = "UI-QuestPoi-QuestNumber-SuperTracked" }
Tr.READY_FALLBACK_COLOR = {
  Header = { r = 0.75, g = 0.61, b = 0 }, HeaderHighlight = { r = 1, g = 0.82, b = 0 },
  Normal = { r = 0.8, g = 0.8, b = 0.8 }, NormalHighlight = { r = 1, g = 1, b = 1 },
}
function Tr.TrackerColor(key)
  local T = rawget(_G, "OBJECTIVE_TRACKER_COLOR")
  local c = type(T) == "table" and T[key]
  if type(c) == "table" and N(c.r) and N(c.g) and N(c.b) then return c.r, c.g, c.b, "OBJECTIVE_TRACKER_COLOR" end
  local g
  if key == "Header" then g = rawget(_G, "OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR")
  elseif key == "HeaderHighlight" then g = rawget(_G, "NORMAL_FONT_COLOR")
  elseif key == "NormalHighlight" then g = rawget(_G, "HIGHLIGHT_FONT_COLOR") end
  if type(g) == "table" and N(g.r) and N(g.g) and N(g.b) then return g.r, g.g, g.b, "global" end
  c = Tr.READY_FALLBACK_COLOR[key]
  return c.r, c.g, c.b, "fallback"
end
-- the title colour exactly as ObjectiveTrackerBlockMixin:UpdateHighlight picks it
local function DifficultyOn()
  local CV = rawget(_G, "C_CVar")
  if type(CV) == "table" and type(CV.GetCVarBool) == "function" then
    local ok, v = pcall(CV.GetCVarBool, "showQuestDifficultyColor")
    if ok then return v == true end
  end
  if type(GetCVarBool) == "function" then
    local ok, v = pcall(GetCVarBool, "showQuestDifficultyColor")
    if ok then return v == true end
  end
  return false
end
function Tr.ReadyTitleColor(q, hot)
  if q and DifficultyOn() and type(GetDifficultyColor) == "function" then
    local PI = rawget(_G, "C_PlayerInfo")
    if type(PI) == "table" and type(PI.GetContentDifficultyQuestForPlayer) == "function" then
      local ok, d = pcall(PI.GetContentDifficultyQuestForPlayer, q)
      if ok and d ~= nil then
        local ok2, c, ch = pcall(GetDifficultyColor, d)
        local x = hot and ch or c
        if ok2 and type(x) == "table" and N(x.r) then return x.r, x.g, x.b, "difficulty" end
      end
    end
  end
  return Tr.TrackerColor(hot and "HeaderHighlight" or "Header")
end
local function PaintReadyText(r)
  local hot = rawget(r, "hot") and true or false
  local a, b, c = Tr.ReadyTitleColor(r.q, hot)
  r.title:SetTextColor(a, b, c)
  a, b, c = Tr.TrackerColor(hot and "NormalHighlight" or "Normal")
  r.zone:SetTextColor(a, b, c)
end
Tr.PaintReadyText = PaintReadyText
local function LineFont(fs)
  local f = rawget(_G, "ObjectiveTrackerLineFont")
  if type(f) == "table" and pcall(fs.SetFontObject, fs, f) then return "ObjectiveTrackerLineFont" end
  pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  return "FRIZQT 12 (ObjectiveTrackerLineFont missing)"
end
local function SuperTracked(q)
  local ST = rawget(_G, "C_SuperTrack")
  if q and type(ST) == "table" and type(ST.GetSuperTrackedQuestID) == "function" then
    local ok, id = pcall(ST.GetSuperTrackedQuestID)
    return ok and id == q
  end
  return false
end
-- the game's POI button: built from its template (no art of ours); nil when this client can't
local function GamePOI(r)
  local U = rawget(_G, "POIButtonUtil")
  local style = type(U) == "table" and type(U.Style) == "table" and U.Style[Tr.READY_ICON.style]
  if not style then return nil end
  for _, tmpl in ipairs({ Tr.READY_ICON.template, "POIButtonTemplate" }) do
    local ok, b = pcall(CreateFrame, "Button", nil, r, tmpl)
    if ok and type(b) == "table" and M(b, "SetStyle") and M(b, "UpdateButtonStyle") and M(b, "SetQuestID") then
      pcall(b.EnableMouse, b, false) -- the row takes the clicks and the hover, as the tracker's header button does
      b.style, b.template = style, tmpl
      return b
    elseif ok and type(b) == "table" then
      pcall(b.Hide, b)
    end
  end
  return nil
end
function Tr.PaintReadyIcon(r)
  local sel = SuperTracked(r.q)
  local b = rawget(r, "poi")
  if b then
    local ok = pcall(function()
      b:SetQuestID(r.q)
      b:SetStyle(b.style)
      if M(b, "SetSelected") then b:SetSelected(sel) end
      b:UpdateButtonStyle()
      b:Show()
    end)
    if ok then r.ficon:Hide() r.face:Hide() r.iconHow = b.template return true end
    pcall(b.Hide, b)
    r.poi = nil
  end
  local A = Tr.READY_ICON
  local okFace = Atlas(r.face, sel and A.faceSel or A.face)
  local okIcon = Atlas(r.ficon, A.atlas)
  r.iconHow = (okFace and okIcon) and "atlas" or (okIcon and "atlas (no face)" or "none")
  return okIcon
end
local function ReadyRow(i)
  local r = ready.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, ready)
  r:SetHeight(30)
  r.title = r:CreateFontString(nil, "ARTWORK")
  r.font = LineFont(r.title)
  r.title:SetJustifyH("LEFT")
  r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 28, -2)
  r.title:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  r.zone = r:CreateFontString(nil, "ARTWORK")
  LineFont(r.zone)
  r.zone:SetJustifyH("LEFT")
  r.zone:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
  r.zone:SetPoint("RIGHT", r, "RIGHT", -4, 0)
  -- the icon: the tracker's POI button, 20 x 20, TOPRIGHT on the title's TOPLEFT (-7, 5)
  r.iconBox = CreateFrame("Frame", nil, r)
  r.iconBox:SetSize(20, 20)
  r.iconBox:SetPoint("TOPRIGHT", r.title, "TOPLEFT", -7, 5)
  r.face = r.iconBox:CreateTexture(nil, "BORDER")
  r.face:SetPoint("CENTER", r.iconBox, "CENTER", 0, 0)
  r.ficon = r.iconBox:CreateTexture(nil, "ARTWORK")
  r.ficon:SetPoint("CENTER", r.iconBox, "CENTER", 0, 0)
  r.icon = r.ficon
  r.poi = GamePOI(r)
  if r.poi then
    pcall(function() r.poi:ClearAllPoints() r.poi:SetPoint("TOPRIGHT", r.title, "TOPLEFT", -7, 5) end)
  end
  r:RegisterForClicks("LeftButtonUp")
  r:SetScript("OnClick", function(self) Tr.ReadyClick(self.q) end)
  r:SetScript("OnEnter", function(self)
    self.hot = true
    PaintReadyText(self)
    self.tipTitle = self.titleText
    self.tipText = "Ready to turn in. Click: the game's arrow points to it, and Dark Matter shows it."
    Tip(self)
  end)
  r:SetScript("OnLeave", function(self)
    self.hot = nil
    PaintReadyText(self)
    Untip()
  end)
  ready.rows[i] = r
  return r
end
local function BuildReady()
  if ready then return ready end
  local A = Tr.READY_ATLAS
  ready = CreateFrame("Frame", "DarkMatterReadyFrame", UIParent)
  ready:SetSize(260, Tr.HEADER_H)
  ready:SetFrameStrata("LOW")
  -- the header: a copy of the tracker's module header (Professions, Quests), built from the same game atlases and font
  local h = CreateFrame("Frame", nil, ready)
  h:SetPoint("TOPLEFT", ready, "TOPLEFT", 0, 0)
  h:SetPoint("TOPRIGHT", ready, "TOPRIGHT", 0, 0)
  h:SetHeight(Tr.HEADER_H)
  h.bg = h:CreateTexture(nil, "BACKGROUND")
  h.bg:SetPoint("CENTER", h, "CENTER", 0, 0)
  Atlas(h.bg, A.bg)
  h.text = h:CreateFontString(nil, "ARTWORK")
  local font = _G.ObjectiveTrackerHeaderFont
  if type(font) == "table" and pcall(h.text.SetFontObject, h.text, font) then
    h.font = "ObjectiveTrackerHeaderFont"
  elseif (_G.GameFontNormalMed2 or _G.GameFontNormal) and pcall(h.text.SetFontObject, h.text, _G.GameFontNormalMed2 or _G.GameFontNormal) then
    h.font = "GameFontNormal"
  else
    pcall(h.text.SetFont, h.text, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "")
  end
  -- the live module header's colour, read only (whichever module header exists)
  for _, name in ipairs({ "ProfessionsRecipeTracker", "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }) do
    local m = _G[name]
    local src = type(m) == "table" and type(m.Header) == "table" and m.Header.Text or nil
    local ok, r2, g2, b2 = false, nil, nil, nil
    if M(src, "GetTextColor") then ok, r2, g2, b2 = pcall(src.GetTextColor, src) end
    if ok and N(r2) and N(g2) and N(b2) then h.text:SetTextColor(r2, g2, b2) h.color = name break end
  end
  h.text:SetJustifyH("LEFT")
  h.text:SetWidth(200)
  h.text:SetPoint("LEFT", h, "LEFT", 7, 0)
  h.text:SetText("Ready to Turn In")
  -- the collapse/expand button (ObjectiveTrackerModuleMinimizeButtonTemplate: 16 x 16, RIGHT x=1)
  local b = CreateFrame("Button", nil, h)
  b:SetSize(16, 16)
  b:SetPoint("RIGHT", h, "RIGHT", 1, 0)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.hl = b:CreateTexture(nil, "HIGHLIGHT")
  b.hl:SetPoint("CENTER", b, "CENTER", 0, 0)
  if Atlas(b.hl, A.highlight) then b.hl:SetBlendMode("ADD") end
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnMouseDown", function(self) self.down = true PaintToggle() end)
  b:SetScript("OnMouseUp", function(self) self.down = nil PaintToggle() end)
  b:SetScript("OnClick", function()
    if NS.ClickSound then NS.ClickSound() end
    Tr.SetReadyCollapsed(not Tr.ReadyCollapsed())
  end)
  b:SetScript("OnEnter", function(self)
    self.tipTitle = "Ready to Turn In"
    self.tipText = Tr.ReadyCollapsed() and "Expand: list the quests ready to turn in." or "Collapse: show only this header."
    Tip(self)
  end)
  b:SetScript("OnLeave", Untip)
  h.button = b
  ready.header, ready.toggle = h, b
  ready.head = h.text
  -- 0.5.2b.7.3: no backdrop behind the rows (transparent, like the tracker's own blocks)
  ready.rows = {}
  ready:Hide()
  PaintToggle()
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
  local collapsed = Tr.ReadyCollapsed()
  local n = collapsed and 0 or math.min(#list, Tr.READY_MAX)
  for i = 1, n do
    local e, r = list[i], ReadyRow(i)
    r.q, r.titleText = e.id, e.title
    r.title:SetText(e.title)
    r.zone:SetText(e.zone or "")
    Tr.PaintReadyIcon(r)
    PaintReadyText(r)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", ready, "TOPLEFT", 6, -Tr.HEADER_H - Tr.HEADER_GAP - (i - 1) * 32)
    r:SetPoint("RIGHT", ready, "RIGHT", -6, 0)
    r:Show()
  end
  for i = n + 1, #ready.rows do ready.rows[i]:Hide() end
  if n > 0 then
    ready:SetHeight(Tr.HEADER_H + Tr.HEADER_GAP + n * 32)
  else
    ready:SetHeight(Tr.HEADER_H)
  end
  ready.n = n
  ready.collapsed = collapsed
  PaintToggle()
end
-- The tracker's real visible bottom, read only, in screen pixels: the lowest of its visible header, visible modules
-- (Quests, Professions, ...; a collapsed, hidden or empty module is hidden or only its header) and visible quest blocks.
-- Returns left, top for our section (one module spacing below that bottom, never above the tracker's background), and
-- how it was found. A hidden tracker: where it would be (its own top left).
local function Px(f, v)
  if not v then return nil end
  return v * (N(Try(f, "GetEffectiveScale")) or 1)
end
function Tr.ReadyTarget(blocks)
  local T = Tr.TrackerFrame()
  if not T then return nil end
  local left, top = Px(T, N(Try(T, "GetLeft"))), Px(T, N(Try(T, "GetTop")))
  if not (left and top) then return nil end
  if not Visible(T) then return left, top, "hidden" end
  local low
  local function Take(f)
    if not Visible(f) then return end
    local b = Px(f, N(Try(f, "GetBottom")))
    if b and (not low or b < low) then low = b end
  end
  Take(rawget(T, "Header"))
  local mods = rawget(T, "modules")
  if type(mods) == "table" then for _, m in ipairs(mods) do Take(m) end end
  for _, name in ipairs(MODULES) do Take(_G[name]) end
  Take(_G.ProfessionsRecipeTracker)
  for _, it in ipairs(blocks or {}) do Take(it.b) end
  if not low then return left, top, "empty" end
  local sp = (N(rawget(T, "moduleSpacing")) or 10) * (N(Try(T, "GetEffectiveScale")) or 1)
  local y = low - sp
  local ns = rawget(T, "NineSlice")
  if Visible(ns) then
    local nb = Px(ns, N(Try(ns, "GetBottom")))
    if nb and nb < y then y = nb end
  end
  return left, y, "below"
end
function Tr.PlaceReady(blocks)
  if not ready or not rawget(ready, "n") or (Tr.readyCount or 0) == 0 or (DB() and DB().readySection == false) then if ready then ready:Hide() end return end
  local T = Tr.TrackerFrame()
  local left, top, how = Tr.ReadyTarget(blocks or ((T and Visible(T)) and Tr.Blocks()) or nil)
  if not left then ready:Hide() return end
  -- the tracker's scale, so the header matches its module headers exactly
  local us = N(Try(UIParent, "GetEffectiveScale")) or 1
  local ts = N(Try(T, "GetEffectiveScale")) or us
  local sc = (us > 0 and ts > 0) and ts / us or 1
  if math.abs((rawget(ready, "sc") or 1) - sc) > 1e-4 then ready:SetScale(sc) ready.sc = sc end
  local eff = us * sc
  local x, y = left / eff, top / eff
  local w = (N(Try(T, "GetWidth")) or 260)
  if rawget(ready, "w") ~= w then ready:SetWidth(w) ready.w = w end
  if rawget(ready, "x") ~= x or rawget(ready, "y") ~= y then
    ready:ClearAllPoints()
    ready:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    ready.x, ready.y = x, y
  end
  ready.how = how
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
-- 0.5.2b.1 / 0.5.2b.2: the tracker in quest-log order (zone groups, lowest level first, as the log shows them).
-- The game's tracker (Blizzard_QuestObjectiveTracker.lua, BuildQuestWatchInfos + CompareQuestWatchInfos) lists the
-- quests in WATCH order: index 1..C_QuestLog.GetNumQuestWatches() from GetQuestIDForQuestWatchIndex, sorted only to put
-- callings and quests that override the sort order first; there is no sort setting. The game re-sorts the watch list
-- on zone changes (C_QuestLog.SortQuestWatches on ZONE_CHANGED_NEW_AREA and on ZONE_CHANGED to a new map).
-- 0.5.2b.1 re-tracked the out-of-place quests in log order assuming a new watch goes to the END of the list. On 1.60.1 a
-- new watch goes to the FRONT (index 1), so that came out exactly reversed (Wetlands 35, 34, 32, 31, ..., 30).
-- 0.5.2b.2: which end a new watch goes to is learned from the result (the watch list after a re-order is compared with
-- both predictions, at once and again after the next settle in case the change arrives later) and saved in
-- DarkMatterDB.watchInsert ("front" / "end"). Front: the quests before the longest correct tail are re-tracked in
-- REVERSE log order, so the first one in the log ends at index 1. End: the tail from the first out-of-place one is
-- re-tracked in log order. Only the public watch API is used; no tracker code or frame is touched. Out of combat, not
-- in flight, about a second after the game's sort and after auto-track. If the order is still wrong for any other
-- reason (or a watch did not come back) it stops until the next zone change.
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
-- which end of the watch list a new watch goes to: "front" or "end" (learned; "end" until then)
function Tr.WatchSide()
  local db = DB()
  return (db and db.watchInsert == "front") and "front" or "end"
end
-- the quests to track again, in the order to track them (empty when the order is already right)
function Tr.OrderFix(order, log, side)
  side = side or Tr.WatchSide()
  local have = {}
  for _, id in ipairs(order) do if log[id] then have[#have + 1] = id end end
  local want = {}
  for i, id in ipairs(have) do want[i] = id end
  table.sort(want, function(a, b) return log[a].idx < log[b].idx end)
  local fix = {}
  if side == "front" then
    local n, k = #have, 0
    while k < n and have[n - k] == want[n - k] do k = k + 1 end
    for i = n - k, 1, -1 do fix[#fix + 1] = want[i] end
  else
    local k = 0
    while k < #have and have[k + 1] == want[k + 1] do k = k + 1 end
    for i = k + 1, #want do fix[#fix + 1] = want[i] end
  end
  return fix
end
-- the watch list after untracking and tracking `fix` again, when a new watch goes to `side`
function Tr.PredictOrder(order, fix, side)
  local drop = {}
  for _, id in ipairs(fix) do drop[id] = true end
  local out = {}
  for _, id in ipairs(order) do if not drop[id] then out[#out + 1] = id end end
  for _, id in ipairs(fix) do
    if side == "front" then table.insert(out, 1, id) else out[#out + 1] = id end
  end
  return out
end
local function Same(a, b)
  if not (a and b) or #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
-- did the watch list come out as the OTHER end predicts? Then learn that end (saved).
local function LearnSide(v, now)
  if Tr.orderLearnTried then return false end -- once per zone change, so an odd client can never flip back and forth
  local other = v.side == "front" and "end" or "front"
  if Same(now, Tr.PredictOrder(v.order, v.fix, other)) and not Same(now, Tr.PredictOrder(v.order, v.fix, v.side)) then
    if DB() then DB().watchInsert = other end
    Tr.orderLearned = other
    Tr.orderLearnTried = true
    return true
  end
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
  Tr.orderDirty = nil
  local v, learned = Tr.orderVerify, false
  Tr.orderVerify = nil
  if v then learned = LearnSide(v, order) end
  local side = Tr.WatchSide()
  local fix = Tr.OrderFix(order, log, side)
  if #fix == 0 then
    Tr.orderNote = v and ("re-ordered " .. #v.fix .. " to log order (new watches go to the " .. side .. ")") or "in log order"
    return
  end
  if v and not learned then
    Tr.orderGaveUp = true
    Tr.orderNote = "the game kept its own order: stopped until the next zone change"
    return
  end
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
  local vNow = { order = order, fix = fix, side = side }
  if lost > 0 then
    Tr.orderGaveUp = true
    Tr.orderNote = lost .. " watch(es) did not come back: stopped until the next zone change"
  elseif again and #Tr.OrderFix(again, log, side) == 0 then
    Tr.orderNote = "re-ordered " .. #fix .. " to log order (new watches go to the " .. side .. ")"
  elseif again and LearnSide(vNow, again) then
    -- new watches went to the other end: learned; put it right on the next tick
    Tr.orderNote = "learned: new watches go to the " .. Tr.WatchSide() .. "; re-ordering again"
    Tr.orderDirty = Now() - Tr.ORDER_SETTLE
  else
    -- not visible yet (the change may arrive a moment later): look again after the next settle
    Tr.orderVerify = vNow
    Tr.orderDirty = Now()
    Tr.orderNote = "re-ordered " .. #fix .. "; checking the result"
  end
end

---------------------------------------------------------------------------
-- events and the tick (our own private frame; the tracker itself is never touched)
---------------------------------------------------------------------------
Tr.EVENTS = { "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
  "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_CONTROL_GAINED", "ZONE_CHANGED",
  "SUPER_TRACKING_CHANGED" }
function Tr.OnEvent(event, a1)
  if event == "SUPER_TRACKING_CHANGED" then Tr.readyDirty = true return end -- 0.5.2b.7.3: the ready icons' super-tracked face
  if event == "QUEST_WATCH_LIST_CHANGED" or event == "QUEST_ACCEPTED" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA"
    or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_CONTROL_GAINED" then
    Tr.orderDirty = Now() -- 0.5.2b.1: keep the tracker in log order (after the game's own re-sort)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then Tr.orderGaveUp, Tr.orderVerify, Tr.orderLearnTried = nil, nil, nil end
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
  local acc, racc = 0, 0
  f:SetScript("OnUpdate", function(_, dt)
    acc, racc = acc + (dt or 0), racc + (dt or 0)
    if racc >= Tr.READY_POLL then racc = 0 if ready and rawget(ready, "n") then Tr.PlaceReady() end end -- 0.5.2b.2: follow the tracker's bottom
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
  if ready then
    lines[#lines + 1] = string.format("ready section: %s, %s, placed %s at %s, %s (own frame on UIParent; the tracker is only read)",
      ready:IsShown() and "shown" or "hidden", Tr.ReadyCollapsed() and "collapsed" or "expanded", tostring(rawget(ready, "how")), tostring(rawget(ready, "x")), tostring(rawget(ready, "y")))
    local r1 = ready.rows and ready.rows[1]
    local A = Tr.READY_ICON
    local hr, hg, hb, hs = Tr.TrackerColor("Header")
    local lr, lg, lb = Tr.TrackerColor("Normal")
    lines[#lines + 1] = string.format("ready rows: icon %s (POIButtonUtil.Style.%s: %s on %s); font %s; title Header %.2f %.2f %.2f (%s), hover HeaderHighlight; line Normal %.2f %.2f %.2f, hover NormalHighlight; backdrop none",
      r1 and tostring(rawget(r1, "iconHow")) or "not built yet", A.style, A.atlas, A.face,
      r1 and tostring(rawget(r1, "font")) or "ObjectiveTrackerLineFont", hr, hg, hb, hs, lr, lg, lb)
  end
  lines[#lines + 1] = string.format("tracker in log order: %s; watch-order API %s; re-orders %d; %s", Tr.OrderWanted() and "on" or "off",
    Tr.WatchOrder() and "ok" or "missing", Tr.orderFixed or 0, Tr.orderNote or "not checked yet")
  -- 0.5.2b.2: the quest log's order against the watch list and the tracker's blocks (top to bottom)
  local db = DB()
  lines[#lines + 1] = string.format("new watches go to the: %s (%s)", Tr.WatchSide(),
    Tr.orderLearned and "learned this session" or ((db and db.watchInsert) and "saved" or "not learned yet; assumed"))
  local log = ReadLog()
  local wo = Tr.WatchOrder() or {}
  local watched = {}
  for _, id in ipairs(wo) do watched[id] = true end
  local logList = {}
  for id, e in pairs(log) do if watched[id] then logList[#logList + 1] = e end end
  table.sort(logList, function(a, b) return a.idx < b.idx end)
  local function Name(id)
    if not id then return "none" end
    local e = log[id]
    return id .. " " .. (e and e.title or "?")
  end
  local parts = {}
  for i, e in ipairs(logList) do parts[i] = Name(e.id) end
  lines[#lines + 1] = "log order (tracked quests): " .. (#parts > 0 and table.concat(parts, " | ") or "none")
  parts = {}
  for i, id in ipairs(wo) do parts[i] = Name(id) end
  lines[#lines + 1] = "watch order (index 1 first): " .. (#parts > 0 and table.concat(parts, " | ") or "none")
  parts = {}
  local blockIds = {}
  for i, it in ipairs((T and Visible(T)) and Tr.Blocks() or {}) do parts[i] = Name(it.q) blockIds[i] = it.q end
  lines[#lines + 1] = "tracker blocks (top to bottom): " .. (#parts > 0 and table.concat(parts, " | ") or "none visible")
  local seen, k = {}, 0
  for _, id in ipairs(blockIds) do if log[id] then k = k + 1 seen[k] = id end end
  local sub = {}
  for i, id in ipairs(seen) do sub[i] = id end
  table.sort(sub, function(a, b) return log[a].idx < log[b].idx end)
  local diff
  for i = 1, #seen do if seen[i] ~= sub[i] then diff = i break end end
  if #blockIds == 0 then
    lines[#lines + 1] = "tracker vs log: no visible blocks to compare"
  else
    lines[#lines + 1] = diff and ("tracker vs log: DIFFERENT from position " .. diff .. " (" .. Name(seen[diff]) .. " where the log has " .. Name(sub[diff]) .. ")")
      or "tracker vs log: SAME order"
  end
  return lines
end
