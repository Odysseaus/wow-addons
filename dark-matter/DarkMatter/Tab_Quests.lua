-- Quests tab: lists the player's quest log (read-only, via C_QuestLog) grouped by zone header, with a detail panel.
-- Never selects or changes anything in Blizzard's quest log; no tracking changes in this phase.
local _, NS = ...
local UI = NS.UI

local ROW_H
local tab, list, detail, empty, rowPool = nil, nil, nil, nil, {}
local groups, total = {}, 0
local selectedId
local pending = false
local ev

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
  local QL = C_QuestLog
  groups, total = {}, 0
  if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return false end
  local ok, n = pcall(QL.GetNumQuestLogEntries)
  n = ok and NS.Num(n) or 0
  local cur
  for i = 1, n do
    local ok2, raw = pcall(QL.GetInfo, i)
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
        }
        if q.questID then
          if QL.IsComplete then
            local ok3, c = pcall(QL.IsComplete, q.questID)
            q.complete = ok3 and NS.Bool(c) or false
          end
          if QL.IsFailed then
            local ok4, fl = pcall(QL.IsFailed, q.questID)
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

local function Objectives(q)
  local out = {}
  if not (q.questID and C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
  local ok, raw = pcall(C_QuestLog.GetQuestObjectives, q.questID)
  local t = ok and NS.Tbl(raw) or nil
  if not t then return out end
  for _, o in ipairs(t) do
    local ob = NS.Tbl(o)
    if ob then
      out[#out + 1] = { text = NS.Str(ob.text) or "", done = NS.Bool(ob.finished) == true }
    end
  end
  return out
end

local function Difficulty(level)
  local mine = NS.Num(UnitLevel and UnitLevel("player"))
  if not level or not mine then return "row" end
  local d = level - mine
  if d <= -3 then return "good" end
  if d >= 3 then return "low" end
  return "mid"
end

---------------------------------------------------------------------------
-- list rows
---------------------------------------------------------------------------
local function GetRow(i)
  local r = rowPool[i]
  if r then return r end
  local m = NS.theme.m
  r = CreateFrame("Button", nil, list.content)
  r:SetSize(list.w - m.sbWidth, ROW_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.sel:SetAllPoints(r)
  r.hover = r:CreateTexture(nil, "HIGHLIGHT")
  r.hover:SetAllPoints(r)
  r.hover:SetColorTexture(1, 1, 1, 0.07)
  r.line = r:CreateTexture(nil, "BORDER")
  r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
  r.line:SetHeight(1)
  r.line:SetColorTexture(1, 1, 1, 0.06)
  r.icon = r:CreateTexture(nil, "OVERLAY")
  r.icon:SetSize(14, 14)
  r.icon:SetPoint("LEFT", r, "LEFT", m.rowPad, 0)
  r.small = r:CreateFontString(nil, "OVERLAY")
  NS.SetFont(r.small, 12, "")
  r.small:SetShadowOffset(1, -1)
  r.small:SetShadowColor(0, 0, 0, 0.9)
  r.small:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
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

local function Detail(q)
  local d = detail
  if not q then
    d.title:SetText(total == 0 and "No quests" or "")
    d.meta:SetText("")
    d.status:SetText("")
    d.body:SetText(total == 0 and "Your quest log is empty. Accept a quest and it shows up here." or "")
    d.scroll:SetContentHeight(1)
    return
  end
  d.title:SetText(q.title)
  local meta = {}
  if q.level then meta[#meta + 1] = "Level " .. q.level end
  if q.group then meta[#meta + 1] = q.group end
  if q.frequency == 1 then meta[#meta + 1] = "Daily" elseif q.frequency == 2 then meta[#meta + 1] = "Weekly" end
  d.meta:SetText(table.concat(meta, "  \194\183  "))
  if q.failed then
    d.status:SetText(NS.ColorCode("low") .. "Failed|r")
  elseif q.complete then
    d.status:SetText(NS.ColorCode("good") .. "Ready to turn in|r")
  else
    d.status:SetText(NS.ColorCode("mid") .. "In progress|r")
  end
  local lines = {}
  for _, o in ipairs(Objectives(q)) do
    if o.text ~= "" then
      lines[#lines + 1] = (o.done and NS.ColorCode("good") or NS.ColorCode("listInk")) .. "- " .. o.text .. "|r"
    end
  end
  if #lines == 0 then lines[1] = NS.ColorCode("listSoft") .. "No objectives reported for this quest.|r" end
  if q.questID then lines[#lines + 1] = "\n" .. NS.ColorCode("listSoft") .. "Quest ID " .. q.questID .. "|r" end
  d.body:SetText(table.concat(lines, "\n"))
  d.scroll:SetContentHeight((NS.Num(d.body:GetStringHeight()) or 20) + 12)
end

local function Refresh()
  if not list then return end
  local m = NS.theme.m
  ReadLog()
  local collapsed = Collapsed()
  local rows = {}
  local sel
  for _, g in ipairs(groups) do
    rows[#rows + 1] = { kind = "h", group = g }
    if not collapsed[g.title] then
      for _, q in ipairs(g.quests) do rows[#rows + 1] = { kind = "q", quest = q } end
    end
    for _, q in ipairs(g.quests) do
      if (q.questID or q.title) == selectedId then sel = q end
    end
  end
  if not sel then
    -- keep the selection valid: first quest in the log
    for _, g in ipairs(groups) do
      if g.quests[1] then sel = g.quests[1] break end
    end
    selectedId = sel and (sel.questID or sel.title) or nil
  end
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
      if data.kind == "h" then
        r.icon:Show()
        NS.SetPiece(r.icon, collapsed[data.group.title] and "coin_plus" or "coin_minus")
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", r.small, "LEFT", -6, 0)
        r.text:SetText(data.group.title)
        r.text:SetTextColor(NS.Color("gold"))
        r.small:SetText(#data.group.quests)
        r.small:SetTextColor(NS.Color("listSoft"))
      else
        local q = data.quest
        isSel = ((q.questID or q.title) == selectedId)
        r.icon:Hide()
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
  list:SetContentHeight(nrows * ROW_H)
  if empty then
    if nrows == 0 then empty:Show() else empty:Hide() end
  end
  Detail(sel)
  local expanded = false
  for _, g in ipairs(groups) do if not collapsed[g.title] then expanded = true end end
  NS.SetAllIcon(expanded)
  NS.SetStatus(string.format("Dark Matter %s  \194\183  %d %s in your log", NS.version, total, total == 1 and "quest" or "quests"))
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
    ev:SetScript("OnEvent", function() Schedule() end)
  end
  for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    if on then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
  end
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
    local pad, gap, lw = m.pagePad, 12, 270
    local ph = m.pageH - 2 * pad
    local dw = m.pageW - 2 * pad - lw - gap
    local b = m.listBorder

    local lp = UI.Panel(page, lw, ph)
    lp:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -pad)
    list = UI.Scroll(lp, lw - 2 * b, ph - 2 * b)
    list.frame:SetPoint("TOPLEFT", lp, "TOPLEFT", b, -b)
    list.step = ROW_H * 3
    empty = UI.Text(lp, "OVERLAY", 13, "listSoft", "CENTER")
    empty:SetPoint("CENTER", lp, "CENTER", 0, 0)
    empty:SetWidth(lw - 40)
    empty:SetText("No quests in your log.")
    empty:Hide()

    local dp = UI.Panel(page, dw, ph)
    dp:SetPoint("TOPLEFT", page, "TOPLEFT", pad + lw + gap, -pad)
    detail = {}
    detail.title = UI.Text(dp, "OVERLAY", 17, "gold", "LEFT")
    detail.title:SetPoint("TOPLEFT", dp, "TOPLEFT", 14, -14)
    detail.title:SetWidth(dw - 28)
    detail.title:SetWordWrap(false)
    detail.meta = UI.Text(dp, "OVERLAY", 12, "listSoft", "LEFT")
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -6)
    detail.meta:SetWidth(dw - 28)
    detail.status = UI.Text(dp, "OVERLAY", 13, "mid", "LEFT")
    detail.status:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -8)
    detail.status:SetWidth(dw - 28)
    local headH = 82
    detail.scroll = UI.Scroll(dp, dw - 2 * b, ph - 2 * b - headH)
    detail.scroll.frame:SetPoint("TOPLEFT", dp, "TOPLEFT", b, -(b + headH))
    detail.body = UI.Text(detail.scroll.content, "OVERLAY", 13, "listInk", "LEFT")
    detail.body:SetPoint("TOPLEFT", detail.scroll.content, "TOPLEFT", 10, -4)
    detail.body:SetWidth(dw - 2 * b - m.sbWidth - 20)
    detail.body:SetJustifyV("TOP")
    Refresh()
    return tab
  end,
  OnShow = function()
    Events(true)
    Refresh()
  end,
  OnHide = function() Events(false) end,
  Refresh = Refresh,
  ToggleAll = function()
    local c = Collapsed()
    local anyOpen = false
    for _, g in ipairs(groups) do if not c[g.title] then anyOpen = true end end
    for _, g in ipairs(groups) do c[g.title] = anyOpen or nil end
    Refresh()
  end,
})
