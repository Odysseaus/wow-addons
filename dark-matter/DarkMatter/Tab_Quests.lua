-- Quests tab: the player's quest log (C_QuestLog) grouped by zone header, with a WoW-style detail panel.
-- 0.4.5: toolbar row at the top of the quest column (All, Track Quest, search), a watch checkbox per quest kept in sync
-- with the game's watch list, live search over title/zone/objectives/quest text/reward names, and the detail panel
-- (objectives, description, rewards with real item tooltips). Data comes from NS.QL (QuestLog.lua); nothing is invented.
local _, NS = ...
local UI = NS.UI
local QL = NS.QL

local ROW_H
local tab, list, detail, empty, rowPool = nil, nil, nil, nil, {}
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
local function OnWatchClick(self)
  local r = self.row
  local q = r and r.quest
  if not q then return end
  QL.SetWatched(q, not QL.IsWatched(q))
  NS.tabs.quests.Refresh()
end

local function GetRow(i)
  local r = rowPool[i]
  if r then return r end
  local m = NS.theme.m
  r = CreateFrame("Button", nil, list.content)
  r:SetSize(list.cw, ROW_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.sel:SetAllPoints(r)
  r.hover = UI.Hover(r)
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
      NS.tabs.quests.Refresh()
    elseif self.quest then
      selectedId = self.quest.questID or self.quest.title
      NS.tabs.quests.Refresh()
    end
  end)
  rowPool[i] = r
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
local function DK(key)
  if detail and detail.panel and detail.panel.parch then return PARCH_KEY[key] or key end
  return key
end

local function DText(i, size, colorKey)
  colorKey = DK(colorKey)
  local d = detail
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

local function DItem(i)
  local d = detail
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
    if self.entry and selQuest then QL.ShowRewardTooltip(self, selQuest, self.entry) end
  end, function(self) QL.HideRewardTooltip(self) end)
  b.hoverInk = "listInk"
  -- 0.5.1.2: no name plate on the parchment; hover there is a faint warm tint only (UI.Hover hoverSoft)
  b.hoverSoft = function() return d.panel and d.panel.parch end
  d.items[i] = b
  return b
end

local debugged = {} -- quests whose empty detail panel was already explained in chat (0.4.6)

local function Detail(q)
  local d = detail
  selQuest = q
  d.title:SetTextColor(NS.Color(DK("gold")))
  d.meta:SetTextColor(NS.Color(DK("listSoft")))
  d.status:SetTextColor(NS.Color(DK("mid")))
  local sh = (d.panel and d.panel.parch) and 0 or 0.9
  d.title:SetShadowColor(0, 0, 0, sh)
  d.meta:SetShadowColor(0, 0, 0, sh)
  d.status:SetShadowColor(0, 0, 0, sh)
  local nt, ni, y = 0, 0, -4
  local function line(text, size, key, gapAbove)
    nt = nt + 1
    local fs = DText(nt, size, key)
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
      local b = DItem(ni)
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
        b.name:SetTextColor(NS.Color(DK("listSoft")))
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
    d.title:SetText(query ~= "" and "No matching quests" or (total == 0 and "No quests" or ""))
    d.meta:SetText("")
    d.status:SetText("")
    if total == 0 then line("Your quest log is empty. Accept a quest and it shows up here.", 13, "listSoft") end
    if query ~= "" and total > 0 then line("Nothing in your log matches \"" .. query .. "\".", 13, "listSoft") end
  else
    d.title:SetText(q.title)
    local meta = {}
    if q.level then meta[#meta + 1] = "Level " .. q.level end
    if q.group then meta[#meta + 1] = q.group end
    if q.frequency == 1 then meta[#meta + 1] = "Daily" elseif q.frequency == 2 then meta[#meta + 1] = "Weekly" end
    if q.questID then meta[#meta + 1] = "Quest " .. q.questID end
    d.meta:SetText(table.concat(meta, "  \194\183  "))
    if q.failed then
      d.status:SetText(NS.ColorCode(DK("low")) .. "Failed|r")
    elseif q.complete then
      d.status:SetText(NS.ColorCode(DK("good")) .. "Ready to turn in|r")
    else
      d.status:SetText(NS.ColorCode(DK("mid")) .. "In progress|r")
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
local function Refresh()
  if not list then return end
  local m = NS.theme.m
  ReadLog()
  local collapsed = Collapsed()
  local words = {}
  for w in QL.Norm(query):gmatch("%S+") do words[#words + 1] = w end
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
  if not sel then
    sel = firstVisible
    selectedId = sel and (sel.questID or sel.title) or (searching and selectedId or nil)
  end
  local canWatch = QL.CanWatch()
  local nrows = #rows
  for i = 1, math.max(nrows, #rowPool) do
    local r = rowPool[i]
    local data = rows[i]
    if data then
      r = GetRow(i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
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
      r:Show()
    elseif r then
      r:Hide()
    end
  end
  list:SetContentHeight(math.max(1, nrows * ROW_H))
  if empty then
    if searching and matched == 0 and total > 0 then
      empty:SetText("No matching quests")
      empty:Show()
    elseif total == 0 then
      empty:SetText("No quests in your log.")
      empty:Show()
    else
      empty:Hide()
    end
  end
  if searching and matched == 0 then sel = nil end
  Detail(sel)
  -- toolbar: All icon, Track Quest box follows the selected quest
  local expanded = false
  for _, g in ipairs(groups) do if not collapsed[g.title] then expanded = true end end
  if bar.allIcon then NS.SetPiece(bar.allIcon, expanded and "coin_minus" or "coin_plus") end
  if bar.trk then
    local w = sel and canWatch and QL.IsWatched(sel)
    bar.trk:SetChecked(w and true or false)
    if sel and canWatch then bar.trk:Enable() else bar.trk:Disable() end
  end
  local s = string.format("Dark Matter %s  \194\183  %d %s in your log", NS.version, total, total == 1 and "quest" or "quests")
  if searching then s = s .. string.format("  \194\183  %d matching", matched) end
  NS.SetStatus(s)
end

local function Schedule()
  if pending then return end
  pending = true
  C_Timer.After(0.25, function()
    pending = false
    if tab and tab:IsShown() then Refresh() end
  end)
end

local function Events(on)
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
  for _, e in ipairs(QL.WATCH_EVENTS) do
    if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
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
  if bar.clear then if query ~= "" then bar.clear:Show() else bar.clear:Hide() end end
  Refresh()
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

    list = UI.Scroll(lp, lw - G - 2 * b, ph - 2 * b - tbH - 8, lp)
    list.frame:SetPoint("TOPLEFT", lp, "TOPLEFT", b, -(b + tbH + 8))
    list.step = ROW_H * 3
    empty = UI.Text(lp, "OVERLAY", 13, "listSoft", "CENTER")
    empty:SetPoint("CENTER", lp, "CENTER", 0, -tbH / 2)
    empty:SetWidth(lw - G - 40)
    empty:SetText("No quests in your log.")
    empty:Hide()

    local dp = UI.Panel(page, dw - G, ph, "detailShade")
    dp:SetPoint("TOPLEFT", page, "TOPLEFT", pad + lw + gap, -pad)
    detail = { texts = {}, items = {}, panel = dp }
    detail.title = UI.Text(dp, "OVERLAY", 17, "gold", "LEFT")
    detail.title:SetPoint("TOPLEFT", dp, "TOPLEFT", 14, -14)
    detail.title:SetWidth(dw - G - 28)
    detail.title:SetWordWrap(false)
    detail.meta = UI.Text(dp, "OVERLAY", 12, "listSoft", "LEFT")
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -6)
    detail.meta:SetWidth(dw - G - 28)
    detail.status = UI.Text(dp, "OVERLAY", 13, "mid", "LEFT")
    detail.status:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -8)
    detail.status:SetWidth(dw - G - 28)
    local headH = 82
    detail.scroll = UI.Scroll(dp, dw - G - 2 * b, ph - 2 * b - headH, dp)
    detail.scroll.frame:SetPoint("TOPLEFT", dp, "TOPLEFT", b, -(b + headH))
    detail.scroll.step = 60
    detail.cw = dw - G - 2 * b - 20
    detail.iw = math.floor((detail.cw - 8) / 2)
    -- 0.5.1: redraw after a theme change so the detail ink follows the panel (parchment or dark)
    NS.OnSkin(function() if detail then Refresh() end end)
    Refresh()
    return tab
  end,
  OnShow = function()
    Events(true)
    Refresh()
  end,
  OnHide = function() Events(false) end,
  Refresh = Refresh,
  ToggleAll = ToggleAll,
  SetSearch = function(t) if bar.search then bar.search:SetText(t or "") end SetQuery(t or "") end,
  Selected = function() return selQuest end,
  Parts = function() return bar, detail, list end,
})
