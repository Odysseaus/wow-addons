-- Quests tab: the player's quest log (C_QuestLog) grouped by zone header, with a WoW-style detail panel.
-- 0.4.5: toolbar row at the top of the quest column (All, Track Quest, search), a watch checkbox per quest kept in sync
-- with the game's watch list, live search over title/zone/objectives/quest text/reward names, and the detail panel
-- (objectives, description, rewards with real item tooltips). Data comes from NS.QL (QuestLog.lua); nothing is invented.
local _, NS = ...
local UI = NS.UI
local QL = NS.QL
local QS = NS.QS -- 0.5.2a shared quest state (selection, hover) with the Map tab

local ROW_H
-- 0.5.2a.1: the quest list is a view that can be built more than once (the Quests tab and the Map tab's docked quest
-- panel). Every view shows the same log and the same selection (QuestState); each keeps its own rows, scroll and search.
local tab, detail = nil, nil
local views = {}   -- every list view built
local main         -- the Quests tab's own view (its rows, list and empty text)
local list, empty
local groups, total = {}, 0
local selectedId, selQuest
local pending = false
local quietUntil = 0
local ev
local bar = {}
local query = ""

local function Now() return (GetTime and NS.Num(GetTime())) or 0 end

local function Collapsed()
  if NS.db then
    NS.db.questCollapsed = NS.db.questCollapsed or {}
    return NS.db.questCollapsed
  end
  return {}
end

---------------------------------------------------------------------------
-- reading the log (pcall'd, read-only, secret-safe)
---------------------------------------------------------------------------
local function ReadLog()
  local CQ = C_QuestLog
  groups, total = {}, 0
  if not (CQ and CQ.GetNumQuestLogEntries and CQ.GetInfo) then return false end
  local ok, n = pcall(CQ.GetNumQuestLogEntries)
  n = ok and NS.Num(n) or 0
  local cur
  for i = 1, n do
    local ok2, raw = pcall(CQ.GetInfo, i)
    local info = ok2 and NS.Tbl(raw) or nil
    if info and NS.Bool(info.isHidden) ~= true then
      if NS.Bool(info.isHeader) == true then
        cur = { title = NS.Str(info.title) or "Quests", quests = {} }
        groups[#groups + 1] = cur
      else
        if not cur then
          cur = { title = "Quests", quests = {} }
          groups[#groups + 1] = cur
        end
        local q = {
          title = NS.Str(info.title) or "Quest",
          level = NS.Num(info.level),
          questID = NS.Num(info.questID),
          frequency = NS.Num(info.frequency),
          group = cur.title,
          logIndex = i,
        }
        if q.questID then
          if CQ.IsComplete then
            local ok3, c = pcall(CQ.IsComplete, q.questID)
            q.complete = ok3 and NS.Bool(c) or false
          end
          if CQ.IsFailed then
            local ok4, fl = pcall(CQ.IsFailed, q.questID)
            q.failed = ok4 and NS.Bool(fl) or false
          end
        end
        cur.quests[#cur.quests + 1] = q
        total = total + 1
      end
    end
  end
  return true
end

local function Difficulty(level)
  local mine = NS.Num(UnitLevel and UnitLevel("player"))
  if not level or not mine then return "row" end
  local d = level - mine
  if d <= -3 then return "good" end
  if d >= 3 then return "low" end
  return "mid"
end

local function Matches(q, words)
  if #words == 0 then return true end
  local hay = QL.Haystack(q)
  for _, w in ipairs(words) do
    if not hay:find(w, 1, true) then return false end
  end
  return true
end

---------------------------------------------------------------------------
-- list rows
---------------------------------------------------------------------------
local RefreshAll -- forward
local function OnWatchClick(self)
  local r = self.row
  local q = r and r.quest
  if type(q) ~= "table" then return end
  QL.SetWatched(q, not QL.IsWatched(q))
  RefreshAll()
end

local function GetRow(V, i)
  local r = V.rows[i]
  if r then return r end
  local m = NS.theme.m
  r = CreateFrame("Button", nil, V.list.content)
  r:SetSize(V.list.cw, ROW_H)
  r.view = V
  r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.sel:SetAllPoints(r)
  -- 0.5.2a: hovering a quest row lights its markers on the Map tab (shared state)
  r.hover = UI.Hover(r, function(self) if QS and type(self.quest) == "table" and self.quest.questID then QS.Hover(self.quest.questID, "list") end end,
    function() if QS then QS.Hover(nil, "list") end end)
  -- 0.5.2a: lit when this quest's marker is hovered on the map (drawn in code: a soft gold wash)
  r.link = r:CreateTexture(nil, "BACKGROUND", nil, 2)
  r.link:SetAllPoints(r)
  r.link:SetColorTexture(1, 0.82, 0.25, 0.22)
  r.link:Hide()
  r.hoverInk = "listInk"
  r.line = r:CreateTexture(nil, "BORDER")
  r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
  r.line:SetHeight(1)
  r.line:SetColorTexture(1, 1, 1, 0.06)
  r.icon = r:CreateTexture(nil, "OVERLAY")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("LEFT", r, "LEFT", m.rowPad, 0)
  -- 0.4.5: stock check button = the game's quest watch (tracker) for this quest
  r.watch = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.watch:SetSize(18, 18)
  r.watch:SetPoint("RIGHT", r, "RIGHT", -m.rowPad + 2, 0)
  r.watch:SetScript("OnClick", OnWatchClick)
  r.watch.isWatchBox = true
  r.watch.row = r
  r.small = r:CreateFontString(nil, "OVERLAY")
  NS.SetFont(r.small, 12, "")
  r.small:SetShadowOffset(1, -1)
  r.small:SetShadowColor(0, 0, 0, 0.9)
  r.text = r:CreateFontString(nil, "OVERLAY")
  NS.SetFont(r.text, m.rowSize, "")
  r.text:SetShadowOffset(1, -1)
  r.text:SetShadowColor(0, 0, 0, 0.9)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r:SetScript("OnClick", function(self)
    if self.kind == "h" then
      local c = Collapsed()
      c[self.group.title] = not c[self.group.title] or nil
      RefreshAll()
    elseif type(self.quest) == "table" then
      selectedId = self.quest.questID or self.quest.title
      if QS and self.quest.questID then QS.Select(self.quest.questID, "list") end
      if V.onPick then V.onPick(self.quest) end
      RefreshAll()
    end
  end)
  V.rows[i] = r
  return r
end

---------------------------------------------------------------------------
-- detail panel (WoW quest log layout)
---------------------------------------------------------------------------
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }
local function QualityRGB(q)
  if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
    local c = ITEM_QUALITY_COLORS[q]
    if NS.Num(c.r) then return c.r, c.g, c.b end
  end
  local c = QUALITY[q or 1] or QUALITY[1]
  return c[1], c[2], c[3]
end

-- 0.5.1: on the parchment detail panel (WoW theme, stock QuestBG found) the text uses the dark quest ink
-- (0.5.1.1: the pInk keys; the WoW theme's ink keys are now the light page ink).
local PARCH_KEY = { listInk = "pInk", listSoft = "pInkSoft", listHead = "pInkHead", gold = "pInkHead", ink = "pInk", inkSoft = "pInkSoft", inkHead = "pInkHead", good = "pGood", mid = "pMid", low = "pLow" }
local function DK(key, d)
  d = d or detail
  if d and d.panel and d.panel.parch then return PARCH_KEY[key] or key end
  return key
end

local function DText(d, i, size, colorKey)
  colorKey = DK(colorKey, d)
  local fs = d.texts[i]
  if not fs then
    fs = UI.Text(d.scroll.content, "OVERLAY", 13, "listInk", "LEFT")
    fs:SetWidth(d.cw)
    fs:SetJustifyV("TOP")
    d.texts[i] = fs
  end
  NS.SetFont(fs, size, "")
  fs:SetTextColor(NS.Color(colorKey))
  fs:SetShadowColor(0, 0, 0, (d.panel and d.panel.parch) and 0 or 0.9) -- no shadow under dark ink on parchment
  return fs
end

local function DItem(d, i)
  local b = d.items[i]
  if b then return b end
  b = CreateFrame("Button", nil, d.scroll.content)
  b:SetSize(d.iw, 40)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(36, 36)
  b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
  b.count = b:CreateFontString(nil, "OVERLAY")
  NS.SetFont(b.count, 11, "OUTLINE")
  b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 2)
  b.name = UI.Text(b, "OVERLAY", 12, "listInk", "LEFT")
  b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.name:SetWidth(d.iw - 48)
  UI.Hover(b, function(self)
    quietUntil = Now() + 0.6
    if self.entry and d.quest then QL.ShowRewardTooltip(self, d.quest, self.entry) end
  end, function(self) QL.HideRewardTooltip(self) end)
  b.hoverInk = "listInk"
  -- 0.5.1.2: no name plate on the parchment; hover there is a faint warm tint only (UI.Hover hoverSoft)
  b.hoverSoft = function() return d.panel and d.panel.parch end
  d.items[i] = b
  return b
end

local debugged = {} -- quests whose empty detail panel was already explained in chat (0.4.6)

local function Detail(q, d)
  d = d or detail
  d.quest = q
  if d == detail then selQuest = q end
  local qtext = d.query or ""
  d.title:SetTextColor(NS.Color(DK("gold", d)))
  d.meta:SetTextColor(NS.Color(DK("listSoft", d)))
  d.status:SetTextColor(NS.Color(DK("mid", d)))
  local sh = (d.panel and d.panel.parch) and 0 or 0.9
  d.title:SetShadowColor(0, 0, 0, sh)
  d.meta:SetShadowColor(0, 0, 0, sh)
  d.status:SetShadowColor(0, 0, 0, sh)
  local nt, ni, y = 0, 0, -4
  local function line(text, size, key, gapAbove)
    nt = nt + 1
    local fs = DText(d, nt, size, key)
    y = y - (gapAbove or 0)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", d.scroll.content, "TOPLEFT", 10, y)
    fs:SetText(text)
    fs:Show()
    y = y - (NS.Num(fs:GetStringHeight()) or 14) - 4
  end
  local function grid(entries)
    local col = 0
    for _, e in ipairs(entries) do
      ni = ni + 1
      local b = DItem(d, ni)
      b.entry = e
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", d.scroll.content, "TOPLEFT", 10 + col * (d.iw + 8), y)
      local ic = e.icon
      if not (NS.Str(ic) or NS.Num(ic)) then ic = "Interface\\Icons\\INV_Misc_QuestionMark" end
      b.icon:SetTexture(ic)
      b.count:SetText((e.count or 1) > 1 and tostring(e.count) or "")
      b.count:SetTextColor(NS.Color("barText"))
      -- 0.5.1.3: an item the client has not loaded yet says so; its GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT redraws
      b.name:SetText(e.name or "Loading\226\128\166")
      -- 0.5.1.2: straight on the parchment, the quality colour darkened to read on it (no name plate)
      if not e.name then
        b.name:SetTextColor(NS.Color(DK("listSoft", d)))
      elseif d.panel.parch then
        b.name:SetTextColor(NS.ParchQuality(QualityRGB(e.quality)))
        b.name:SetShadowColor(0, 0, 0, 0)
      else
        b.name:SetTextColor(NS.Legible(QualityRGB(e.quality)))
        b.name:SetShadowColor(0, 0, 0, 0.9)
      end
      b:Show()
      col = col + 1
      if col == 2 then col = 0 y = y - 44 end
    end
    if col == 1 then y = y - 44 end
  end

  if not q then
    d.title:SetText(qtext ~= "" and "No matching quests" or (total == 0 and "No quests" or ""))
    d.meta:SetText("")
    d.status:SetText("")
    if total == 0 then line("Your quest log is empty. Accept a quest and it shows up here.", 13, "listSoft") end
    if qtext ~= "" and total > 0 then line("Nothing in your log matches \"" .. qtext .. "\".", 13, "listSoft") end
  else
    d.title:SetText(q.title)
    local meta = {}
    if q.level then meta[#meta + 1] = "Level " .. q.level end
    if q.group then meta[#meta + 1] = q.group end
    if q.frequency == 1 then meta[#meta + 1] = "Daily" elseif q.frequency == 2 then meta[#meta + 1] = "Weekly" end
    if q.questID then meta[#meta + 1] = "Quest " .. q.questID end
    d.meta:SetText(table.concat(meta, "  \194\183  "))
    if q.failed then
      d.status:SetText(NS.ColorCode(DK("low", d)) .. "Failed|r")
    elseif q.complete then
      d.status:SetText(NS.ColorCode(DK("good", d)) .. "Ready to turn in|r")
    else
      d.status:SetText(NS.ColorCode(DK("mid", d)) .. "In progress|r")
    end
    local det = QL.Details(q)
    local objs = QL.Objectives(q)
    -- Objectives: the summary text, then each objective with progress
    line("Quest Objectives", 15, "listHead")
    line(det.objText or "Objectives summary: Not available from this client.", 13, det.objText and "listInk" or "listSoft")
    for _, o in ipairs(objs) do
      line((o.done and "\226\156\147 " or "- ") .. o.text, 13, o.done and "good" or "listInk")
    end
    if #objs == 0 then line("No objective progress reported for this quest.", 12, "listSoft") end
    if det.group and det.group > 1 then line("Suggested players: " .. det.group, 12, "listSoft") end
    -- Description
    line("Description", 15, "listHead", 8)
    line(det.desc or "Not available from this client.", 13, det.desc and "listInk" or "listSoft")
    -- Rewards
    local hasApi = det.src.rewards or det.src.choices or det.xp ~= nil or det.money ~= nil
    -- 0.4.6: an empty panel prints one diagnostic line per quest (index values, which selection methods were tried)
    if not det.desc and not det.objText and (det.xp or 0) <= 0 and #(det.rewards or {}) + #(det.choices or {}) == 0 then
      local dk = q.questID or q.title
      if dk and not debugged[dk] then debugged[dk] = true NS.Print(QL.DebugLine(q, det)) end
    end
    line("Rewards", 15, "listHead", 8)
    if not hasApi then
      line("Not available from this client.", 13, "listSoft")
    else
      local any = false
      if #(det.choices or {}) > 0 then
        line("You will be able to choose one of these rewards:", 13, "listInk")
        grid(det.choices)
        any = true
      end
      local also = any
      if #(det.rewards or {}) > 0 or (det.money or 0) > 0 then
        line(also and "You will also receive:" or "You will receive:", 13, "listInk")
        grid(det.rewards or {})
        if (det.money or 0) > 0 then line("Money: " .. QL.Money(det.money), 13, "listInk") end
        any = true
      end
      if det.spell then line("You will learn: " .. det.spell.name, 13, "listInk") any = true end
      if det.title then line("Title: " .. det.title, 13, "listInk") any = true end
      if (det.honor or 0) > 0 then line("Honor: " .. det.honor, 13, "listInk") any = true end
      for _, r in ipairs(det.rep or {}) do
        line(string.format("Reputation: %+d %s", r.amount, r.name), 13, "listInk")
        any = true
      end
      if (det.xp or 0) > 0 then line("Experience: " .. det.xp, 13, "listInk") any = true end
      if (det.reqMoney or 0) > 0 then line("Required money: " .. QL.Money(det.reqMoney), 13, "listSoft") end
      if not any then line("No rewards listed for this quest.", 13, "listSoft") end
    end
  end
  for i = nt + 1, #d.texts do d.texts[i]:Hide() end
  for i = ni + 1, #d.items do d.items[i]:Hide() d.items[i].entry = nil end
  d.scroll:SetContentHeight(-y + 8)
end

---------------------------------------------------------------------------
local function FindQuest(id)
  if id == nil then return nil end
  for _, g in ipairs(groups) do
    for _, q in ipairs(g.quests) do if (q.questID or q.title) == id then return q end end
  end
end

-- draw one view's rows (groups already read). Returns the quest it shows as selected, the matches, and searching.
local function FillRows(V)
  local m = NS.theme.m
  local collapsed = Collapsed()
  local words = {}
  for w in QL.Norm(V.query):gmatch("%S+") do words[#words + 1] = w end
  local searching = #words > 0
  local rows = {}
  local sel, firstVisible, matched = nil, nil, 0
  for _, g in ipairs(groups) do
    local hits = {}
    for _, q in ipairs(g.quests) do
      if not searching or Matches(q, words) then hits[#hits + 1] = q end
    end
    matched = matched + #hits
    if #hits > 0 or not searching then
      rows[#rows + 1] = { kind = "h", group = g, n = #hits }
      if searching or not collapsed[g.title] then
        for _, q in ipairs(hits) do rows[#rows + 1] = { kind = "q", quest = q } end
      end
      for _, q in ipairs(hits) do
        firstVisible = firstVisible or q
        if (q.questID or q.title) == selectedId then sel = q end
      end
    end
  end
  -- only the Quests tab picks a quest by itself (the first one shown); other views just show the selection
  if not sel and V.auto then
    sel = firstVisible
    selectedId = sel and (sel.questID or sel.title) or (searching and selectedId or nil)
  end
  if QS and sel and sel.questID and V.auto then QS.selected = sel.questID end -- the Map tab lights the selected quest's markers
  local canWatch = QL.CanWatch()
  local nrows = #rows
  for i = 1, math.max(nrows, #V.rows) do
    local r = V.rows[i]
    local data = rows[i]
    if data then
      r = GetRow(V, i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", V.list.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
      r.kind = data.kind
      r.group, r.quest = data.group, data.quest
      local isSel = false
      r.small:ClearAllPoints()
      if data.kind == "h" then
        r.icon:Show()
        r.watch:Hide()
        NS.SetPiece(r.icon, (collapsed[data.group.title] and not searching) and "coin_plus" or "coin_minus")
        r.small:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", r.small, "LEFT", -6, 0)
        r.text:SetText(data.group.title)
        r.text:SetTextColor(NS.Color("gold"))
        r.small:SetText(searching and (data.n .. "/" .. #data.group.quests) or #data.group.quests)
        r.small:SetTextColor(NS.Color("listSoft"))
      else
        local q = data.quest
        isSel = ((q.questID or q.title) == selectedId)
        r.icon:Hide()
        local watched = canWatch and QL.IsWatched(q)
        if canWatch and watched ~= nil then
          r.watch:Show()
          r.watch:SetChecked(watched and true or false)
          r.small:SetPoint("RIGHT", r.watch, "LEFT", -2, 0)
        else
          r.watch:Hide()
          r.small:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
        end
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r, "LEFT", m.rowPad + 14, 0)
        r.text:SetPoint("RIGHT", r.small, "LEFT", -6, 0)
        r.text:SetText(q.title)
        r.text:SetTextColor(NS.Color(isSel and "liOn" or Difficulty(q.level)))
        r.small:SetText(q.level and tostring(q.level) or "")
        r.small:SetTextColor(NS.Color("listSoft"))
      end
      if isSel then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      local lit = data.kind == "q" and QS and data.quest.questID ~= nil and QS.hovered == data.quest.questID and QS.hoverSrc == "map"
      if lit then r.link:Show() else r.link:Hide() end
      r:Show()
    elseif r then
      r:Hide()
    end
  end
  V.list:SetContentHeight(math.max(1, nrows * ROW_H))
  if V.empty then
    if searching and matched == 0 and total > 0 then
      V.empty:SetText("No matching quests")
      V.empty:Show()
    elseif total == 0 then
      V.empty:SetText("No quests in your log.")
      V.empty:Show()
    else
      V.empty:Hide()
    end
  end
  if searching and matched == 0 and V.auto then sel = nil end
  V.matched, V.searching = matched, searching
  if V.after then V.after(V, sel) end
  return sel, matched, searching
end

local function Live(V) return V == main or (V.host and V.host:IsVisible()) end

-- read the log once and redraw every view that is showing (the Quests tab's always, it keeps the selection)
local function Refresh()
  if not main and #views == 0 then return end
  ReadLog()
  for _, V in ipairs(views) do
    if V ~= main and Live(V) then FillRows(V) end
  end
  if not main then return end
  local sel, matched, searching = FillRows(main)
  detail.query = query
  Detail(sel)
  -- toolbar: All icon, Track Quest box follows the selected quest
  local collapsed = Collapsed()
  local canWatch = QL.CanWatch()
  local expanded = false
  for _, g in ipairs(groups) do if not collapsed[g.title] then expanded = true end end
  if bar.allIcon then NS.SetPiece(bar.allIcon, expanded and "coin_minus" or "coin_plus") end
  if bar.trk then
    local w = sel and canWatch and QL.IsWatched(sel)
    bar.trk:SetChecked(w and true or false)
    if sel and canWatch then bar.trk:Enable() else bar.trk:Disable() end
  end
  if detail and detail.showMap then
    if sel and sel.questID then detail.showMap:Enable() detail.showMap:SetAlpha(1) else detail.showMap:Disable() detail.showMap:SetAlpha(0.5) end
  end
  if not (tab and tab:IsShown() == false) then
    local s = string.format("Dark Matter %s  \194\183  %d %s in your log", NS.version, total, total == 1 and "quest" or "quests")
    if searching then s = s .. string.format("  \194\183  %d matching", matched) end
    NS.SetStatus(s)
  end
end
RefreshAll = Refresh

local function AnyLive()
  if tab and tab:IsShown() then return true end
  for _, V in ipairs(views) do if V ~= main and Live(V) then return true end end
  return false
end

local function Schedule()
  if pending then return end
  pending = true
  C_Timer.After(0.25, function()
    pending = false
    if AnyLive() then Refresh() end
  end)
end

-- the log's events, registered while any user (the Quests tab, the docked panel) is showing
local users = {}
local function Events(on, who)
  who = who or "tab"
  users[who] = on and true or nil
  local want = next(users) ~= nil
  if not ev then
    ev = CreateFrame("Frame") -- private frame, read-only handler
    ev:SetScript("OnEvent", function(_, e, a1)
      -- 0.5.1.3: a reward item we are waiting for loaded: read its quest again (other items' events are ignored)
      if e == "GET_ITEM_INFO_RECEIVED" or e == "ITEM_DATA_LOAD_RESULT" then
        if QL.ItemArrived(a1) then Schedule() end
        return
      end
      -- 0.4.6: quest data we asked for (C_QuestLog.RequestLoadQuestByID) arrived: read that quest again
      if e == "QUEST_DATA_LOAD_RESULT" then local id = NS.Num(a1) if id then QL.Forget(id) end end
      if QL.reading then return end
      -- our own brief selection (detail read, reward tooltip) fires QUEST_LOG_UPDATE: skip that echo
      if e == "QUEST_LOG_UPDATE" and (Now() < quietUntil or Now() - (QL.lastSelect or -99) < 0.5) then return end
      Schedule()
    end)
  end
  if want == ev.dmOn then return end
  ev.dmOn = want
  for _, e in ipairs(QL.WATCH_EVENTS) do
    if want then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
  end
end

local function ToggleAll()
  local c = Collapsed()
  local anyOpen = false
  for _, g in ipairs(groups) do if not c[g.title] then anyOpen = true end end
  for _, g in ipairs(groups) do c[g.title] = anyOpen or nil end
  Refresh()
end

local function SetQuery(t)
  query = t or ""
  if main then main.query = query end
  if bar.clear then if query ~= "" then bar.clear:Show() else bar.clear:Hide() end end
  Refresh()
end

-- a list view in host: a scroll list of w x h at (x, y) from host's top left, plus its empty text.
-- opts.auto: picks the first quest when none is selected (the Quests tab); opts.onPick(q): a quest row was clicked.
local function NewView(host, w, h, x, y, opts)
  opts = opts or {}
  ROW_H = ROW_H or NS.theme.m.rowH
  local V = { rows = {}, query = "", host = host, auto = opts.auto, onPick = opts.onPick, after = opts.after }
  V.list = UI.Scroll(host, w, h, host)
  V.list.frame:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
  V.list.step = ROW_H * 3
  V.empty = UI.Text(host, "OVERLAY", 13, "listSoft", "CENTER")
  V.empty:SetPoint("CENTER", V.list.frame, "CENTER", 0, 0)
  V.empty:SetWidth(w - 20)
  V.empty:SetText("No quests in your log.")
  V.empty:Hide()
  function V.SetQuery(t) V.query = t or "" if Live(V) then ReadLog() FillRows(V) end end
  function V.Refresh() if Live(V) then ReadLog() FillRows(V) end end
  views[#views + 1] = V
  return V
end

-- the quest detail (title, level/zone line, state, then objectives, description and rewards in a scroll) in panel dp
-- of w x h, the stock quest log's layout. top: room kept above the title (a Back button). Returns the detail table.
local function NewDetail(dp, w, h, top)
  local m = NS.theme.m
  local b = m.listBorder
  top = top or 0
  local d = { texts = {}, items = {}, panel = dp }
  d.title = UI.Text(dp, "OVERLAY", 17, "gold", "LEFT")
  d.title:SetPoint("TOPLEFT", dp, "TOPLEFT", 14, -14 - top)
  d.title:SetWidth(w - 28)
  d.title:SetWordWrap(false)
  d.meta = UI.Text(dp, "OVERLAY", 12, "listSoft", "LEFT")
  d.meta:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -6)
  d.meta:SetWidth(w - 28)
  d.status = UI.Text(dp, "OVERLAY", 13, "mid", "LEFT")
  d.status:SetPoint("TOPLEFT", d.meta, "BOTTOMLEFT", 0, -8)
  d.status:SetWidth(w - 28 - 124)
  -- 0.5.2a: Show on map: the Map tab flies to the quest (zoom out, pan, zoom in) and sets the game's waypoint + arrow
  local sm = UI.Button(dp, "Show on map", 116, 22, "red", 11)
  sm:SetPoint("TOPRIGHT", dp, "TOPRIGHT", -14, -50 - top)
  sm:SetScript("OnClick", function()
    local q = d.quest and d.quest.questID
    if not q or not NS.MapTab then return end
    if QS then QS.Select(q, "list") end
    if NS.ShowTab and not (NS.windowParts and NS.windowParts.current == "map") then NS.ShowTab("map") end
    NS.MapTab.ShowQuest(q, true)
  end)
  d.showMap = sm
  local headH = 82 + top
  d.scroll = UI.Scroll(dp, w - 2 * b, h - 2 * b - headH, dp)
  d.scroll.frame:SetPoint("TOPLEFT", dp, "TOPLEFT", b, -(b + headH))
  d.scroll.step = 60
  d.cw = w - 2 * b - 20
  d.iw = math.floor((d.cw - 8) / 2)
  return d
end

NS.RegisterTab({
  id = "quests", name = "Quests", glyph = "quests",
  Build = function(body)
    local m = NS.theme.m
    ROW_H = m.rowH
    tab = CreateFrame("Frame", nil, body)
    tab:SetAllPoints(body)
    local page = UI.Page(tab, m.pageW, m.pageH)
    page:SetPoint("TOPLEFT", tab, "TOPLEFT", m.pageX, 0)
    -- 0.5.1.3: each pane gives up a gutter (G) on its right for its scroll bar, like the stock quest log
    local pad, gap, lw = m.pagePad, 10, 276
    local G = UI.Gutter()
    local ph = m.pageH - 2 * pad
    local dw = m.pageW - 2 * pad - lw - gap
    local b = m.listBorder
    local tbH = 24

    local lp = UI.Panel(page, lw - G, ph)
    lp:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -pad)

    -- 0.4.5 toolbar row at the top of the quest column: All, Track Quest (selected quest), search at the far right
    local tb = CreateFrame("Frame", nil, lp)
    tb:SetPoint("TOPLEFT", lp, "TOPLEFT", b + 4, -(b + 4))
    tb:SetSize(lw - G - 2 * b - 8, tbH)
    bar.frame = tb
    local allBtn = CreateFrame("Button", nil, tb)
    allBtn:SetPoint("LEFT", tb, "LEFT", 0, 0)
    allBtn:SetSize(48, 22)
    local allSlice = UI.ThreeSlice(allBtn, "ptab_a", 22, "ARTWORK")
    UI.Hover(allBtn)
    allBtn.hoverInk = "lheadAll"
    bar.allIcon = allBtn:CreateTexture(nil, "OVERLAY")
    bar.allIcon:SetSize(13, 13)
    bar.allIcon:SetPoint("LEFT", allBtn, "LEFT", 6, 0)
    NS.OnSkin(function() NS.SetPiece(bar.allIcon, "coin_minus") end)
    local allText = UI.Text(allBtn, "OVERLAY", 12, "lheadAll", "LEFT")
    allText:SetPoint("LEFT", bar.allIcon, "RIGHT", 4, 0)
    allText:SetText("All")
    allBtn.text = allText
    allBtn.slice = allSlice
    -- 0.5.1.2 WoW theme: a stock panel button labelled "All" (no expand/collapse icon); class themes keep the icon
    UI.StockFeel(allBtn, {
      slice = allSlice,
      place = function(self, dx, dy)
        allText:ClearAllPoints()
        if self.stockOn then
          bar.allIcon:Hide()
          allText:SetPoint("CENTER", self, "CENTER", dx, 1 + dy)
        else
          bar.allIcon:Show()
          allText:SetPoint("LEFT", bar.allIcon, "RIGHT", 4, 0)
        end
      end,
      classic = function()
        allSlice:Apply("ptab_a")
        allText:SetTextColor(NS.Color("lheadAll"))
      end,
    })
    allBtn:SetScript("OnClick", ToggleAll)
    bar.all = allBtn
    local trk = CreateFrame("CheckButton", nil, tb, "UICheckButtonTemplate")
    trk:SetSize(18, 18)
    trk:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
    trk:SetScript("OnClick", function()
      if selQuest then QL.SetWatched(selQuest, not QL.IsWatched(selQuest)) end
      Refresh()
    end)
    bar.trk = trk
    local trkText = UI.Text(tb, "OVERLAY", 12, "listInk", "LEFT")
    trkText:SetPoint("LEFT", trk, "RIGHT", 3, 0)
    trkText:SetText("Track Quest")
    bar.trkText = trkText
    local sw = lw - G - 2 * b - 8 - 48 - 6 - 18 - 3 - 66 - 6
    local search = UI.SearchBox(tb, sw, 22)
    search:SetPoint("RIGHT", tb, "RIGHT", 0, 0)
    search.onChange = SetQuery
    search.edit:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() SetQuery("") end)
    search.edit:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", -18, 3)
    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    local cx = UI.Text(clear, "OVERLAY", 12, "listSoft", "CENTER")
    cx:SetPoint("CENTER", clear, "CENTER", 0, 0)
    cx:SetText("x")
    clear:SetScript("OnClick", function() search:SetText("") search.edit:ClearFocus() SetQuery("") end)
    clear:Hide()
    bar.clear, bar.search = clear, search
    local W = NS.windowParts
    if W then W.allBtn, W.trk, W.questSearch, W.questBar = allBtn, trk, search, tb end

    main = NewView(lp, lw - G - 2 * b, ph - 2 * b - tbH - 8, b, -(b + tbH + 8), { auto = true })
    main.query = query
    list, empty = main.list, main.empty
    empty:ClearAllPoints()
    empty:SetPoint("CENTER", lp, "CENTER", 0, -tbH / 2)
    empty:SetWidth(lw - G - 40)

    local dp = UI.Panel(page, dw - G, ph, "detailShade")
    dp:SetPoint("TOPLEFT", page, "TOPLEFT", pad + lw + gap, -pad)
    detail = NewDetail(dp, dw - G, ph)
    if W then W.showOnMap = detail.showMap end
    -- 0.5.1: redraw after a theme change so the detail ink follows the panel (parchment or dark)
    NS.OnSkin(function() if detail then Refresh() end end)
    Refresh()
    return tab
  end,
  OnShow = function()
    Events(true, "tab")
    Refresh()
  end,
  OnHide = function() Events(false, "tab") end,
  Refresh = Refresh,
  ToggleAll = ToggleAll,
  SetSearch = function(t) if bar.search then bar.search:SetText(t or "") end SetQuery(t or "") end,
  Selected = function() return selQuest end,
  Parts = function() return bar, detail, list end,
  -- 0.5.2a.1: the same list and detail for the Map tab's docked quest panel (QuestPanel.lua)
  NewView = NewView,
  NewDetail = NewDetail,
  ShowDetail = function(q, d) ReadLog() Detail(FindQuest(q) or q, d) end,
  FindQuest = function(id) ReadLog() return FindQuest(id) end,
  Events = Events,
  Count = function() ReadLog() return total end,
  -- the window is being built again: forget the views that hung off the old one
  Reset = function()
    views, main, tab, detail, list, empty = {}, nil, nil, nil, nil, nil
    bar = {}
    Events(false, "tab") Events(false, "panel")
  end,
})

-- 0.5.2a: the shared quest state. A marker clicked on the map selects its quest here; a marker hovered there lights
-- its row here (rows are only redrawn while a list is showing; the selection is kept for the next show).
if QS then
  QS.On(function(what, q, src)
    if what == "select" and src ~= "list" and q then
      selectedId = q
      if AnyLive() then Refresh() end
    elseif what == "hover" then
      for _, V in ipairs(views) do
        for _, r in ipairs(V.rows) do
          local lit = r.kind == "q" and type(r.quest) == "table" and q ~= nil and r.quest.questID == q and src == "map"
          if r.link then if lit then r.link:Show() else r.link:Hide() end end
        end
      end
    end
  end)
end
