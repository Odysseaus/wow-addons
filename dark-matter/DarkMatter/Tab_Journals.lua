-- Journals tab: Fishing panel with waters list + catch statistics (per-character).
-- Adventure Guide (0.3.4): dungeon dropdown, LFG dungeons/raids only + our Forever-validated drop seed + loot learning.
-- Achievements (0.4.0): Journal_Achievements.lua (game Legacy Challenges when the API has data + Dark Matter's own set).
local _, NS = ...
local UI = NS.UI

local SECTIONS = {
  { id = "adventure", name = "Adventure Guide" }, -- 0.4.4: Adventure Guide first and the default
  { id = "fishing", name = "Fishing" },
  { id = "achievements", name = "Achievements" },
}

local tab, pills, badgeText
local fishPage, stubPage, stub
local skillBar, skillTitle, skillSub
local viewWaters, watersRoot, fishRoot, statsRoot, statsScroll
local zoneScroll, detailPanel, detailTitle, detailMeta, detailStatus, detailBody, catchHeader, catchRows, emptyFish
local fvCatches, fvStats, modeZone, modeFish
local fishScroll, fishRowPool, emptyCatchFish
local hoverRow -- the one row that owns the fishing tooltip (never more than one)
local searchBox, showAllBox, filterBar, catalogNote
local rowPool, selectedZone, selectedFish, fishRank, fishMax = {}, nil, nil, nil, nil
local ev, pending = nil, false
local ROW_H, FISH_ROW_H
local statCards = {}
local searchText = ""

local function ZoneStatus(z, rank)
  if not rank then return "unknown", "listSoft" end
  if rank < z.minSkill then return "Locked", "low" end
  return "Ready", "good"
end

local function BestZoneIndex(rank)
  if not rank then return 1 end
  local best, bi = -1, 1
  for i, z in ipairs(NS.FishingZones or {}) do
    if rank >= z.minSkill and z.minSkill >= best then best, bi = z.minSkill, i end
  end
  return bi
end

local function ReadSkill()
  fishRank, fishMax = select(2, NS.ReadFishingSkill())
end

---------------------------------------------------------------------------
-- waters list
---------------------------------------------------------------------------
local function GetRow(i)
  local r = rowPool[i]
  if r then return r end
  local m = NS.theme.m
  r = CreateFrame("Button", nil, zoneScroll.content)
  r:SetSize(zoneScroll.w - m.sbWidth, ROW_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.text = r:CreateFontString(nil, "OVERLAY")
  NS.SetFont(r.text, m.rowSize, "")
  r.text:SetPoint("LEFT", r, "LEFT", m.rowPad, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -56, 0)
  r.text:SetJustifyH("LEFT")
  r.small = r:CreateFontString(nil, "OVERLAY")
  NS.SetFont(r.small, m.rowSize - 1, "")
  r.small:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
  r.small:SetJustifyH("RIGHT")
  r:SetScript("OnClick", function(self)
    selectedZone = self.index
    if NS.db then NS.db.fishingZone = selectedZone end
    if tab and tab.RefreshFish then tab.RefreshFish() end
  end)
  rowPool[i] = r
  return r
end

local function EnsureCatchRow(i, parent)
  catchRows = catchRows or {}
  local r = catchRows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, parent)
  r:SetHeight(22)
  r.name = UI.Text(r, "OVERLAY", 13, "listInk", "LEFT")
  r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
  r.name:SetWidth(150)
  r.count = UI.Text(r, "OVERLAY", 12, "listInk", "RIGHT")
  r.count:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
  r.count:SetWidth(36)
  r.bar = UI.Bar(r, 160, 12, true)
  r.bar:SetPoint("LEFT", r.count, "RIGHT", 8, 0)
  r.bar:SetPoint("RIGHT", r, "RIGHT", 0, 0)
  catchRows[i] = r
  return r
end

local function ShowDetail(z)
  if not detailTitle then return end
  catchRows = catchRows or {}
  if not z then
    detailTitle:SetText("No waters listed")
    detailMeta:SetText("")
    detailStatus:SetText("")
    detailBody:SetText("Fishing waters will show here.")
    if catchHeader then catchHeader:Hide() end
    for _, r in ipairs(catchRows) do r:Hide() end
    return
  end
  local st, col = ZoneStatus(z, fishRank)
  local catches, items = NS.FishingZoneStats(z.name)
  detailTitle:SetText(z.name)
  detailMeta:SetText(string.format("Level %s · %d catches", z.levels, catches))
  local status = NS.ColorCode(col) .. st .. "|r"
  detailStatus:SetText(status)

  local lines = {
    "Minimum fishing skill: " .. tostring(z.minSkill),
  }
  if fishRank then
    if fishRank < z.minSkill then
      lines[#lines + 1] = string.format("You need %d more skill to fish here reliably.", z.minSkill - fishRank)
    else
      lines[#lines + 1] = "Your skill is high enough for these waters."
    end
  else
    lines[#lines + 1] = "Learn Fishing to see which waters you can use."
  end
  detailBody:SetText(table.concat(lines, "\n"))

  local parent = detailPanel
  if not parent then return end
  if not catchHeader then
    catchHeader = UI.Text(parent, "OVERLAY", 11, "listHead", "LEFT")
    catchHeader:SetPoint("TOPLEFT", detailBody, "BOTTOMLEFT", 0, -12)
  end
  if catches == 0 then
    catchHeader:SetText("No catches logged here yet.")
    catchHeader:Show()
    for _, r in ipairs(catchRows) do r:Hide() end
  else
    catchHeader:SetText("Catch · Count · % of zone catches")
    catchHeader:Show()
    local y = 0
    for i, it in ipairs(items) do
      local r = EnsureCatchRow(i, parent)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", catchHeader, "BOTTOMLEFT", 0, -6 - y)
      r:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
      local pct = catches > 0 and (100 * it.count / catches) or 0
      local label = it.name
      if it.junk then label = label .. " (junk)" end
      r.name:SetText(label)
      r.name:SetTextColor(NS.Color(it.junk and "listSoft" or "listInk"))
      r.count:SetText(tostring(it.count))
      r.bar:SetProgress(it.count, catches, string.format("%.0f%%", pct), it.junk and "low" or "gold")
      r:Show()
      y = y + 24
    end
    for i = #items + 1, #catchRows do catchRows[i]:Hide() end
  end
end

---------------------------------------------------------------------------
-- statistics cards
---------------------------------------------------------------------------
local function EnsureStatCard(i)
  local c = statCards[i]
  if c then return c end
  local parent = statsScroll.content
  c = CreateFrame("Frame", nil, parent)
  c:SetSize(statsScroll.w - 24, 72)
  UI.Slate(c, "listShade", "BACKGROUND", 0)
  c.border = UI.NineSlice(c, "pane", 5, "BORDER", 1)
  c.head = UI.Text(c, "OVERLAY", 11, "listHead", "LEFT")
  c.head:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -8)
  c.big = UI.Text(c, "OVERLAY", 18, "goldOn", "LEFT")
  c.big:SetPoint("TOPLEFT", c.head, "BOTTOMLEFT", 0, -4)
  c.sub = UI.Text(c, "OVERLAY", 11, "listInk", "LEFT")
  c.sub:SetPoint("TOPLEFT", c.big, "BOTTOMLEFT", 0, -2)
  c.sub:SetPoint("RIGHT", c, "RIGHT", -12, 0)
  statCards[i] = c
  return c
end

local function RefreshStats()
  if not statsScroll then return end
  local f = NS.GetFishingDB and NS.GetFishingDB() or {}
  local casts = f.casts or 0
  local catches = f.catches or 0
  local junk = f.junk or 0
  local good = f.good or 0
  local gotAway = f.gotAway or 0
  local rate = casts > 0 and (catches / casts) or 0
  local awayPct = casts > 0 and (100 * gotAway / casts) or 0
  local favZone, favN, favLure, favL = NS.FishingFavoriteZoneAndLure()
  local totalCatches = catches > 0 and catches or 1
  local favPct = favZone and favN and (100 * favN / totalCatches) or 0
  local hist = f.skillHistory or {}
  local histLine = "No skill gains recorded yet."
  if #hist > 0 then
    local parts = {}
    local from, to = 1, #hist
    if to - from > 5 then from = to - 5 end
    for i = from, to do
      parts[#parts + 1] = string.format("%s: %d", hist[i].t or "?", hist[i].skill or 0)
    end
    histLine = table.concat(parts, "  ·  ")
  end
  local best = f.bestGold
  local bestLine = "—"
  if type(best) == "table" and best.name then
    bestLine = string.format("best single: %s (%s)", best.name, NS.FishingFormatGold(best.copper or 0))
  end

  local cards = {
    { "1 · Total fish caught", tostring(catches), "overall logged catches" },
    { "2 · Catch rate", string.format("%.2f", rate), string.format("catches per cast (%d / %d casts)", catches, casts) },
    { "3 · Junk vs good", string.format("%d junk · %d good", junk, good), catches > 0 and string.format("%.0f%% good", 100 * good / catches) or "no catches yet" },
    { "4 · Rare / special catches", tostring(#(f.rares or {})), (function()
        local r = f.rares or {}
        if #r == 0 then return "quality rare+ first catches appear here" end
        local lines = {}
        for i = math.max(1, #r - 2), #r do
          lines[#lines + 1] = string.format("%s · %s · %s", r[i].name or "?", r[i].zone or "?", r[i].when or "?")
        end
        return table.concat(lines, " | ")
      end)() },
    { "5 · Time spent fishing", NS.FishingFormatTime(f.timeSec or 0), casts > 0 and string.format("~%d s per cast", math.floor((f.timeSec or 0) / casts + 0.5)) or "channel time while fishing" },
    { "6 · Best streak without junk", tostring(f.bestStreak or 0), string.format("current streak %d", f.streak or 0) },
    { "7 · Gold value of catches", NS.FishingFormatGold(f.goldCopper or 0), bestLine },
    { "8 · Casts that got away", tostring(gotAway), string.format("%.0f%% of all casts", awayPct) },
    { "9 · Favorite zone and lure", favZone or "—", favZone and string.format("%.0f%% of catches · lure: %s (%d casts)", favPct, favLure or "None", favL or 0) or "fish to build favorites" },
    { "10 · Fishing skill over time", fishRank and tostring(fishRank) or "—", histLine },
  }

  local y, gap = 0, 8
  for i, row in ipairs(cards) do
    local c = EnsureStatCard(i)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", statsScroll.content, "TOPLEFT", 8, -y)
    c:SetWidth(statsScroll.w - 24)
    c.head:SetText(row[1])
    c.big:SetText(row[2])
    c.sub:SetText(row[3])
    c:Show()
    y = y + 72 + gap
  end
  for i = #cards + 1, #statCards do
    if statCards[i] then statCards[i]:Hide() end
  end
  statsScroll:SetContentHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------------
local function GetUI()
  return NS.FishingUIPrefs and NS.FishingUIPrefs() or { catchMode = "zone", panel = "catches", showAll = false }
end

-- Apply Show/Hide + pill active state from CharDB (no write). Keeps mode toggles from being clobbered by Refresh.
local function ApplyFishView()
  local ui = GetUI()
  local panel = ui.panel == "stats" and "stats" or "catches"
  local mode = ui.catchMode == "fish" and "fish" or "zone"
  if fvCatches then fvCatches:SetActive(panel == "catches") end
  if fvStats then fvStats:SetActive(panel == "stats") end
  if modeZone then modeZone:SetActive(mode == "zone") end
  if modeFish then modeFish:SetActive(mode == "fish") end
  if watersRoot then
    if panel == "catches" and mode == "zone" then watersRoot:Show() else watersRoot:Hide() end
  end
  if fishRoot then
    if panel == "catches" and mode == "fish" then fishRoot:Show() else fishRoot:Hide() end
  end
  if statsRoot then
    if panel == "stats" then statsRoot:Show() else statsRoot:Hide() end
  end
  if filterBar then
    if panel == "catches" then filterBar:Show() else filterBar:Hide() end
  end
  if NS.db then
    NS.db.fishingView = (panel == "stats") and "stats" or ((mode == "fish") and "fish" or "waters")
  end
end

local function SetFishView(id)
  -- id: "catches" | "stats" | "zone" | "fish"
  if id == "stats" then
    NS.FishingSetUIPref("panel", "stats")
  elseif id == "catches" then
    NS.FishingSetUIPref("panel", "catches")
  elseif id == "fish" or id == "zone" then
    NS.FishingSetUIPref("panel", "catches")
    NS.FishingSetUIPref("catchMode", id)
  end
  ApplyFishView()
end

local function MatchesSearch(name)
  if not searchText or searchText == "" then return true end
  name = tostring(name or ""):lower()
  return name:find(searchText, 1, true) and true or false
end

local function GetFishRow(i)
  fishRowPool = fishRowPool or {}
  local r = fishRowPool[i]
  if r then return r end
  local parent = fishScroll and fishScroll.content
  r = CreateFrame("Button", nil, parent)
  r:SetHeight(FISH_ROW_H or 36)
  r.icon = UI.RoundIcon(r, 28)
  r.icon:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.text = UI.Text(r, "OVERLAY", 13, "listInk", "LEFT")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 4)
  r.text:SetPoint("RIGHT", r, "RIGHT", -56, 4)
  r.small = UI.Text(r, "OVERLAY", 12, "gold", "RIGHT")
  r.small:SetPoint("RIGHT", r, "RIGHT", -10, 0)
  r.sub = UI.Text(r, "OVERLAY", 11, "listSoft", "LEFT")
  r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -1)
  r.sub:SetPoint("RIGHT", r, "RIGHT", -56, 0)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r:SetScript("OnClick", function(self)
    selectedFish = self.catchName
    if tab and tab.RefreshFish then tab.RefreshFish() end
  end)
  -- item tooltip + our lines (caught count, last zone/coords or waters/skill)
  r:SetScript("OnEnter", function(self)
    hoverRow = self
    if self.entry then NS.FishingShowCatchTooltip(self, self.entry, self.total) end
  end)
  r:SetScript("OnLeave", function(self)
    if hoverRow == self then hoverRow = nil end
    NS.FishingHideCatchTooltip(self)
  end)
  r:SetScript("OnHide", function(self)
    if hoverRow == self then hoverRow = nil NS.FishingHideCatchTooltip(self) end
  end)
  fishRowPool[i] = r
  return r
end

local function RefreshFishList()
  if not fishScroll then return end
  local ui = GetUI()
  local list, total, stats = NS.FishingCatchTypes(ui.showAll, searchText)
  local n = #list
  if catalogNote then
    stats = stats or {}
    if ui.showAll then
      catalogNote:SetText(string.format("Catalog: %d items, %d caught", stats.catalog or n, stats.caught or 0))
    else
      catalogNote:SetText(string.format("%d caught · Show all for the full catalog", stats.caught or n))
    end
  end
  for i = 1, math.max(n, #(fishRowPool or {})) do
    local r = fishRowPool and fishRowPool[i]
    local e = list[i]
    if e then
      r = GetFishRow(i)
      r.catchName = e.name
      r.entry, r.total = e, total
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", fishScroll.content, "TOPLEFT", 0, -(i - 1) * (FISH_ROW_H or 36))
      r:SetPoint("RIGHT", fishScroll.content, "RIGHT", 0, 0)
      -- show the client's item name when cached so row text and tooltip always agree
      local clientName = NS.FishingClientItemName and NS.FishingClientItemName(e.itemId)
      if clientName and clientName ~= e.name then NS.FishingNoteNameMismatch(e.itemId, e.name, clientName) end
      r.text:SetText(clientName or e.name)
      local caught = e.caught and (e.count or 0) > 0
      -- caught and account-learned items stand out; the rest of the catalog is soft
      local lit = caught or e.learned
      r.text:SetTextColor(NS.Color(selectedFish == e.name and "liOn" or (lit and "listInk" or "listSoft")))
      if caught then
        r.small:SetText(tostring(e.count))
        r.small:SetTextColor(NS.Color("gold"))
      else
        r.small:SetText("—")
        r.small:SetTextColor(NS.Color("listSoft"))
      end
      local loc = e.lastZone or ""
      local coords = NS.FishingFormatCoords and NS.FishingFormatCoords(e.lastX, e.lastY)
      if coords then loc = (loc ~= "" and (loc .. " · ") or "") .. coords end
      if caught then
        local pct = total > 0 and (100 * e.count / total) or 0
        r.sub:SetText(string.format("%.0f%% · %s%s", pct, e.junk and "junk · " or "", loc ~= "" and loc or "location unknown"))
      elseif e.learned then
        local where = e.firstZone and ("first seen in " .. e.firstZone) or "seen on this account"
        r.sub:SetText("Learned · " .. where .. (e.firstSeen and (" · " .. e.firstSeen) or ""))
      else
        local bits = { e.junk and "Not caught yet · junk" or "Not caught yet" }
        if e.waters then bits[#bits + 1] = e.waters end
        if e.skill then bits[#bits + 1] = "skill " .. e.skill end
        r.sub:SetText(table.concat(bits, " · "))
      end
      r.sub:SetTextColor(NS.Color(caught and "listSoft" or "listSoft"))
      r.icon:SetItem(e.itemId, NS.FishingItemQuality and NS.FishingItemQuality(e.itemId, e.quality) or e.quality, e.icon)
      if selectedFish == e.name then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      r:Show()
      -- item data arrived (list refresh) while hovering: rebuild the tooltip with the real item
      if r == hoverRow then
        local okM, over = pcall(r.IsMouseOver, r)
        if not (okM and over == false) then NS.FishingShowCatchTooltip(r, e, total) end
      end
    elseif r then
      r:Hide()
      r.entry = nil
    end
  end
  fishScroll:SetContentHeight(math.max(1, n * (FISH_ROW_H or 36)))
  if emptyCatchFish then
    if n == 0 then
      emptyCatchFish:SetText(ui.showAll and "Catalog empty (unexpected)." or "No catches logged yet. Enable Show all to browse the fishing catalog.")
      emptyCatchFish:Show()
    else
      emptyCatchFish:Hide()
    end
  end
end

local function RefreshFish()
  if not fishPage then return end
  ReadSkill()
  if skillBar then
    if fishRank and fishMax then
      skillTitle:SetText("Fishing skill")
      skillTitle:SetTextColor(NS.Color("inkHead"))
      skillBar:SetProgress(fishRank, fishMax, fishRank .. " / " .. fishMax, "gold")
      skillSub:SetText("Live skill · per character")
      skillSub:SetTextColor(NS.Color("inkSoft"))
    else
      skillTitle:SetText("Fishing skill")
      skillTitle:SetTextColor(NS.Color("inkHead"))
      skillBar:SetProgress(0, 1, "Not learned", "listSoft")
      skillSub:SetText("Fishing not learned")
      skillSub:SetTextColor(NS.Color("inkSoft"))
    end
    skillBar:Show()
  end

  local ui = GetUI()
  if showAllBox then showAllBox:SetChecked(ui.showAll) end

  local zones = NS.FishingZones or {}
  if not selectedZone or not zones[selectedZone] then
    selectedZone = BestZoneIndex(fishRank)
  end

  local visible = {}
  for i, z in ipairs(zones) do
    if MatchesSearch(z.name) then visible[#visible + 1] = i end
  end
  local nVis = #visible
  for i = 1, math.max(nVis, #rowPool) do
    local r = rowPool[i]
    local zi = visible[i]
    local z = zi and zones[zi]
    if z then
      r = GetRow(i)
      r.index = zi
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", zoneScroll.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
      local _, col = ZoneStatus(z, fishRank)
      local isSel = (zi == selectedZone)
      local catches = select(1, NS.FishingZoneStats(z.name))
      r.text:SetText(z.name)
      r.text:SetTextColor(NS.Color(isSel and "liOn" or "listInk"))
      if catches > 0 then
        r.small:SetText(tostring(catches))
        r.small:SetTextColor(NS.Color("gold"))
      else
        r.small:SetText(tostring(z.minSkill))
        r.small:SetTextColor(NS.Color(col))
      end
      if isSel then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      r:Show()
    elseif r then
      r:Hide()
    end
  end
  if zoneScroll then zoneScroll:SetContentHeight(nVis * ROW_H) end
  if emptyFish then
    if nVis == 0 then emptyFish:Show() else emptyFish:Hide() end
  end
  ShowDetail(zones[selectedZone])
  RefreshFishList()
  RefreshStats()

  ApplyFishView()

  local fdb = NS.GetFishingDB and NS.GetFishingDB() or {}
  if badgeText and NS.db and NS.db.section == "fishing" then
    local c = fdb.catches or 0
    if c > 0 then badgeText:SetText("Catches: " .. c) else badgeText:SetText("Zones: " .. #zones) end
  end
  if NS.SetStatus and fishRank and fishMax then
    NS.SetStatus(string.format("Dark Matter %s · Fishing %d / %d · %d catches", NS.version, fishRank, fishMax, fdb.catches or 0))
  end
end

local function ScheduleFish()
  if pending then return end
  pending = true
  C_Timer.After(0.25, function()
    pending = false
    RefreshFish()
  end)
end

local function EnsureFishEvents(on)
  if on then
    if not ev then
      ev = CreateFrame("Frame")
      ev:SetScript("OnEvent", function() ScheduleFish() end)
    end
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(function() ev:RegisterEvent("SKILL_LINES_CHANGED") end)
    pcall(function() ev:RegisterEvent("CHAT_MSG_SKILL") end)
    pcall(function() ev:RegisterEvent("LOOT_CLOSED") end)
  elseif ev then
    ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
    pcall(function() ev:UnregisterEvent("SKILL_LINES_CHANGED") end)
    pcall(function() ev:UnregisterEvent("CHAT_MSG_SKILL") end)
    pcall(function() ev:UnregisterEvent("LOOT_CLOSED") end)
  end
end

local function BuildFish(page)
  local m = NS.theme.m
  ROW_H = m.rowH
  FISH_ROW_H = 36
  fishPage = CreateFrame("Frame", nil, page)
  fishPage:SetAllPoints(page)

  local pad = m.pagePad
  local innerW = m.pageW - pad * 2

  viewWaters = CreateFrame("Frame", nil, fishPage)
  viewWaters:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -pad)
  viewWaters:SetSize(innerW, 28)
  fvCatches = UI.Pill(viewWaters, "Catches")
  fvCatches:SetPoint("TOPLEFT", viewWaters, "TOPLEFT", 0, 0)
  fvCatches:SetScript("OnClick", function() SetFishView("catches") RefreshFish() end)
  fvStats = UI.Pill(viewWaters, "Statistics")
  fvStats:SetPoint("TOPLEFT", fvCatches, "TOPRIGHT", m.pillGap, 0)
  fvStats:SetScript("OnClick", function() SetFishView("stats") RefreshFish() end)

  local skillH = 40
  local skillPanel = UI.PaperPanel(fishPage, innerW, skillH)
  skillPanel:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -(pad + 32))
  skillTitle = UI.Text(skillPanel, "OVERLAY", 14, "inkHead", "LEFT")
  skillTitle:SetPoint("LEFT", skillPanel, "LEFT", 12, 0)
  skillTitle:SetText("Fishing skill")
  skillTitle:SetWidth(100)
  skillSub = UI.Text(skillPanel, "OVERLAY", 12, "inkSoft", "RIGHT")
  skillSub:SetPoint("RIGHT", skillPanel, "RIGHT", -12, 0)
  skillSub:SetWidth(150)
  skillBar = UI.Bar(skillPanel, 200, 20)
  skillBar:SetPoint("LEFT", skillTitle, "RIGHT", 12, 0)
  skillBar:SetPoint("RIGHT", skillSub, "LEFT", -12, 0)
  skillBar:SetHeight(20)

  local filterH = m.pillsH or 32
  filterBar = CreateFrame("Frame", nil, fishPage)
  filterBar:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -(pad + 32 + skillH + 8))
  filterBar:SetSize(innerW, filterH)
  -- Above watersRoot/fishRoot (created later) so mode pills stay clickable both ways.
  if filterBar.SetFrameLevel then filterBar:SetFrameLevel((fishPage.GetFrameLevel and fishPage:GetFrameLevel() or 1) + 20) end
  if filterBar.EnableMouse then filterBar:EnableMouse(true) end
  modeZone = UI.Pill(filterBar, "by zone")
  modeZone:SetPoint("LEFT", filterBar, "LEFT", 0, 0)
  if modeZone.RegisterForClicks then modeZone:RegisterForClicks("LeftButtonUp") end
  modeZone:SetScript("OnClick", function() SetFishView("zone") RefreshFish() end)
  modeFish = UI.Pill(filterBar, "by fish")
  modeFish:SetPoint("LEFT", modeZone, "RIGHT", m.pillGap, 0)
  if modeFish.RegisterForClicks then modeFish:RegisterForClicks("LeftButtonUp") end
  modeFish:SetScript("OnClick", function() SetFishView("fish") RefreshFish() end)
  searchBox = UI.SearchBox(filterBar, math.max(120, innerW - 360), 24)
  searchBox:SetPoint("LEFT", modeFish, "RIGHT", 12, 0)
  searchBox.onChange = function(t)
    searchText = (t or ""):lower()
    if tab and tab.RefreshFish then tab.RefreshFish() end
  end
  showAllBox = UI.Checkbox(filterBar, "Show all", 18, "ink")  -- 0.4.4: it sits on the page: paper ink
  showAllBox:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
  showAllBox:EnableMouse(true)
  showAllBox.onToggle = function(_, on)
    if NS.FishingSetUIPref then NS.FishingSetUIPref("showAll", on and true or false) end
    if tab and tab.RefreshFish then tab.RefreshFish() end
  end

  local splitY = pad + 32 + skillH + 8 + filterH + 8
  local splitH = m.sectionPageH - splitY - pad

  watersRoot = CreateFrame("Frame", nil, fishPage)
  if watersRoot.EnableMouse then watersRoot:EnableMouse(false) end
  watersRoot:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -splitY)
  watersRoot:SetSize(innerW, splitH)

  local leftW = 240
  local rightW = innerW - leftW - 10
  local left = UI.Panel(watersRoot, leftW, splitH)
  left:SetPoint("TOPLEFT", watersRoot, "TOPLEFT", 0, 0)
  local lh = UI.Text(left, "OVERLAY", 12, "listHead", "LEFT")
  lh:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -8)
  lh:SetText("Zones")
  zoneScroll = UI.Scroll(left, leftW - 8, splitH - 28)
  zoneScroll.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 4, -26)
  emptyFish = UI.Text(left, "OVERLAY", 12, "listSoft", "CENTER")
  emptyFish:SetPoint("CENTER", left, "CENTER", 0, 0)
  emptyFish:SetText("No waters listed.")
  emptyFish:Hide()

  local right = UI.Panel(watersRoot, rightW, splitH)
  right:SetPoint("TOPLEFT", watersRoot, "TOPLEFT", leftW + 10, 0)
  detailPanel = right
  detailTitle = UI.Text(right, "OVERLAY", 18, "gold", "LEFT")
  detailTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -12)
  detailTitle:SetPoint("TOPRIGHT", right, "TOPRIGHT", -14, -12)
  detailMeta = UI.Text(right, "OVERLAY", 12, "listSoft", "LEFT")
  detailMeta:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -4)
  detailStatus = UI.Text(right, "OVERLAY", 13, "good", "LEFT")
  detailStatus:SetPoint("TOPLEFT", detailMeta, "BOTTOMLEFT", 0, -6)
  detailBody = UI.Text(right, "OVERLAY", 12, "listInk", "LEFT")
  detailBody:SetPoint("TOPLEFT", detailStatus, "BOTTOMLEFT", 0, -10)
  detailBody:SetPoint("RIGHT", right, "RIGHT", -14, 0)
  detailBody:SetJustifyV("TOP")

  fishRoot = CreateFrame("Frame", nil, fishPage)
  if fishRoot.EnableMouse then fishRoot:EnableMouse(false) end
  fishRoot:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -splitY)
  fishRoot:SetSize(innerW, splitH)
  local fishPanel = UI.Panel(fishRoot, innerW, splitH)
  fishPanel:SetPoint("TOPLEFT", fishRoot, "TOPLEFT", 0, 0)
  local fh = UI.Text(fishPanel, "OVERLAY", 12, "listHead", "LEFT")
  fh:SetPoint("TOPLEFT", fishPanel, "TOPLEFT", 10, -8)
  fh:SetText("Catch types")
  catalogNote = UI.Text(fishPanel, "OVERLAY", 11, "listSoft", "RIGHT")
  catalogNote:SetPoint("TOPRIGHT", fishPanel, "TOPRIGHT", -12, -8)
  catalogNote:SetText("")
  fishScroll = UI.Scroll(fishPanel, innerW - 8, splitH - 28)
  fishScroll.frame:SetPoint("TOPLEFT", fishPanel, "TOPLEFT", 4, -26)
  emptyCatchFish = UI.Text(fishPanel, "OVERLAY", 12, "listSoft", "CENTER")
  emptyCatchFish:SetPoint("CENTER", fishPanel, "CENTER", 0, 0)
  emptyCatchFish:Hide()
  fishRoot:Hide()

  statsRoot = CreateFrame("Frame", nil, fishPage)
  if statsRoot.EnableMouse then statsRoot:EnableMouse(false) end
  statsRoot:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -splitY)
  statsRoot:SetSize(innerW, splitH)
  statsScroll = UI.Scroll(statsRoot, innerW, splitH)
  statsScroll.frame:SetPoint("TOPLEFT", statsRoot, "TOPLEFT", 0, 0)
  statsRoot:Hide()

  tab.RefreshFish = RefreshFish
  ApplyFishView()
end

---------------------------------------------------------------------------
-- Adventure Guide (0.3.1): top bar = dungeon dropdown (own frames, no UIDropDownMenu) + search + level pills;
-- dungeon header; bosses in the left column; drops in the wide right panel. Every text is one line with a
-- fixed height, so nothing wraps into its neighbour.
---------------------------------------------------------------------------
local agPage, agSearch, agLvlAll, agLvlMine = nil, nil, nil, nil
local agDrop, agMenu, agMenuScroll, agMenuHead
local agDropTextW = 157
local AG_MENU_INDENT = 12  -- entries sit 12px in from their group header (headers stay flush left)
local agMenuTextW = 172    -- entry text width in a dropdown row (set from the menu width in BuildAG)
local agBossScroll, agDropScroll, agTitle, agMeta, agBossHead, agDropHead, agDropNote, agEmptyBoss, agEmptyDrops
local agMenuRows, agBossRows, agDropRows = {}, {}, {}
local agHover
local agText, agEv, agPending = "", nil, false
local AG_MENU_H, AG_BOSS_H, AG_DROP_H = 22, 34, 40
local AG_MENU_MAX = 14

local function AGPrefs()
  local db = NS.db or {}
  return db
end

-- one line, fixed height: no wrapping into the next row
-- "Scarlet Monastery: Graveyard" -> "SM: Graveyard" (dropdown label only)
local function CompactName(n)
  local pre, rest = n:match("^(.-):%s*(.+)$")
  if not pre then return n end
  local ini = pre:gsub("(%a)[%a']*%s*", "%1")
  return ini .. ": " .. rest
end

local function OneLine(fs, h)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetHeight(h)
  return fs
end

-- relabel a pill and keep its width fitted to the text
local function PillLabel(p, label)
  if not (p and p.text) or p._label == label then return end
  p._label = label
  p.text:SetText(label)
  local m = NS.theme.m
  local tw = NS.Num(p.text:GetStringWidth()) or 60
  p:SetSize(math.floor(tw + m.pillPad * 2 + 0.5), m.pillsH)
end

local function PlayerLevel()
  if not UnitLevel then return nil end
  local ok, l = pcall(UnitLevel, "player")
  if ok and type(l) == "number" then return l end
  return nil
end

local function LevelText(d)
  if d.minLevel and d.maxLevel then
    if d.minLevel == d.maxLevel then return tostring(d.minLevel) end
    return d.minLevel .. "–" .. d.maxLevel
  end
  if d.minLevel then return tostring(d.minLevel) end
  return "?"
end

local function AGLines(row)
  return function(tt)
    local d, b, it = row.dungeon, row.boss, row.entry
    tt:AddLine(" ")
    tt:AddLine("Dark Matter", 1, 0.82, 0)
    tt:AddDoubleLine("Drops from", b and b.name or "?", 0.9, 0.9, 0.9, 1, 1, 1)
    tt:AddDoubleLine("Dungeon", d and d.name or "?", 0.9, 0.9, 0.9, 1, 1, 1)
    if it.pct then tt:AddDoubleLine("Drop chance", string.format("%.1f%% (Wowhead)", it.pct), 0.9, 0.9, 0.9, 1, 1, 1) end
    local n = row.seen or 0
    tt:AddDoubleLine("Seen by you", n > 0 and (n .. "×") or "not yet", 0.9, 0.9, 0.9, 1, 1, 1)
  end
end

-- 0.3.3: an open dropdown closes on any click outside it, on Esc and when the window hides; the button still
-- toggles it. Stock frames only, no hooks: a full-screen invisible catcher (our own UIParent child, one frame
-- level under the list) takes the outside mouse-down and closes the list (it passes nothing on); a private
-- frame's GLOBAL_MOUSE_DOWN covers clicks on frames above the catcher (checked with IsMouseOver on the list
-- and the button); Esc goes through Blizzard's UISpecialFrames list, where the named catcher is listed only
-- while the list is open (the main window comes off the list meanwhile, as with the Settings popup).
local agCatch, agMouseEv
local SetMenuOpen
local function EnsureCatcher()
  if agCatch then return agCatch end
  agCatch = CreateFrame("Frame", "DarkMatterAGMenuCatcher", UIParent)
  agCatch:SetAllPoints(UIParent)
  agCatch:EnableMouse(true)
  agCatch:Hide()
  agCatch:SetScript("OnMouseDown", function() SetMenuOpen(false) end)
  agCatch:SetScript("OnHide", function() if agMenu and agMenu:IsShown() then SetMenuOpen(false) end end)
  agMouseEv = CreateFrame("Frame")
  agMouseEv:SetScript("OnEvent", function()
    if not (agMenu and agMenu:IsShown()) then return end
    local okM, overM = pcall(agMenu.IsMouseOver, agMenu)
    local okD, overD = pcall(agDrop.IsMouseOver, agDrop)
    if okM and okD and overM == false and overD == false then SetMenuOpen(false) end
  end)
  return agCatch
end

SetMenuOpen = function(on)
  if not agMenu then return end
  if on then
    agMenu:Show()
    local c = EnsureCatcher()
    local okS, strata = pcall(agMenu.GetFrameStrata, agMenu)
    if okS and type(strata) == "string" then pcall(c.SetFrameStrata, c, strata) end
    local okL, lvl = pcall(agMenu.GetFrameLevel, agMenu)
    if okL and type(lvl) == "number" then pcall(c.SetFrameLevel, c, math.max(0, lvl - 1)) end
    c:Show()
    pcall(agMouseEv.RegisterEvent, agMouseEv, "GLOBAL_MOUSE_DOWN")
    if NS.SpecialFrame then NS.SpecialFrame("DarkMatterFrame", false) NS.SpecialFrame("DarkMatterAGMenuCatcher", true) end
  else
    agMenu:Hide()
    if agCatch then
      if agCatch:IsShown() then agCatch:Hide() end
      pcall(agMouseEv.UnregisterEvent, agMouseEv, "GLOBAL_MOUSE_DOWN")
      if NS.SpecialFrame then NS.SpecialFrame("DarkMatterAGMenuCatcher", false) end
      if NS.RestoreEscMain then NS.RestoreEscMain() end
    end
  end
  if agDrop and agDrop.arrow then NS.SetPiece(agDrop.arrow, on and "sb_up" or "sb_dn") end
end

local function GetMenuRow(i)
  local r = agMenuRows[i]
  if r then return r end
  local m = NS.theme.m
  r = CreateFrame("Button", nil, agMenuScroll.content)
  r:SetSize(agMenuScroll.w - m.sbWidth, AG_MENU_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.text = OneLine(UI.Text(r, "OVERLAY", 13, "listInk", "LEFT"), 16)
  r.small = OneLine(UI.Text(r, "OVERLAY", 12, "listSoft", "RIGHT"), 14)
  r.small:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
  r.small:SetWidth(40)
  r:SetScript("OnClick", function(self)
    if self.isHeader or type(self.dungeonKey) ~= "string" then return end -- group header: not clickable
    if NS.db then NS.db.agDungeon = self.dungeonKey NS.db.agBoss = nil end
    SetMenuOpen(false)
    if tab and tab.RefreshAG then tab.RefreshAG() end
  end)
  agMenuRows[i] = r
  return r
end

local function GetBossRow(i)
  local r = agBossRows[i]
  if r then return r end
  local m = NS.theme.m
  r = CreateFrame("Button", nil, agBossScroll.content)
  r:SetSize(agBossScroll.w - m.sbWidth, AG_BOSS_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.text = OneLine(UI.Text(r, "OVERLAY", 13, "listInk", "LEFT"), 16)
  r.text:SetPoint("TOPLEFT", r, "TOPLEFT", m.rowPad, -3)
  r.text:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
  r.sub = OneLine(UI.Text(r, "OVERLAY", 11, "listSoft", "LEFT"), 13)
  r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", m.rowPad, -19)
  r.sub:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
  r:SetScript("OnClick", function(self)
    if NS.db then NS.db.agBoss = self.bossName end
    if tab and tab.RefreshAG then tab.RefreshAG() end
  end)
  agBossRows[i] = r
  return r
end

local function GetDropRow(i)
  local r = agDropRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, agDropScroll.content)
  r:SetHeight(AG_DROP_H)
  r.icon = UI.RoundIcon(r, 28)
  r.icon:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.text = OneLine(UI.Text(r, "OVERLAY", 13, "listInk", "LEFT"), 16)
  r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 44, -4)
  r.text:SetPoint("RIGHT", r, "RIGHT", -10, 0)
  r.sub = OneLine(UI.Text(r, "OVERLAY", 11, "listSoft", "LEFT"), 13)
  r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 44, -22)
  r.sub:SetPoint("RIGHT", r, "RIGHT", -10, 0)
  -- same tooltip + placement as the fishing rows (icon TOPRIGHT, compares chained right, mirror at the edge)
  r:SetScript("OnEnter", function(self)
    agHover = self
    if self.entry then NS.ShowItemTooltip(self, self.entry, AGLines(self)) end
  end)
  r:SetScript("OnLeave", function(self)
    if agHover == self then agHover = nil end
    NS.FishingHideCatchTooltip(self)
  end)
  r:SetScript("OnHide", function(self)
    if agHover == self then agHover = nil NS.FishingHideCatchTooltip(self) end
  end)
  agDropRows[i] = r
  return r
end

local QUALITY_WORD = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
local KIND_ORDER = { Dungeon = 1, Heroic = 2, Raid = 3 }
local KIND_HEAD = { Dungeon = "Dungeons", Heroic = "Heroic dungeons", Raid = "Raids" }

-- dropdown entries: grouped by type (headers only when there is more than one type)
local function MenuItems(list)
  local sorted = {}
  for i, d in ipairs(list) do sorted[i] = d end
  table.sort(sorted, function(a, b)
    local ka, kb = KIND_ORDER[a.kind] or 9, KIND_ORDER[b.kind] or 9
    if ka ~= kb then return ka < kb end
    local la, lb = a.minLevel or 999, b.minLevel or 999
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  local kinds, nk = {}, 0
  for _, d in ipairs(sorted) do if not kinds[d.kind or "?"] then kinds[d.kind or "?"] = true nk = nk + 1 end end
  local out, last = {}, nil
  for _, d in ipairs(sorted) do
    if nk > 1 and d.kind ~= last then
      out[#out + 1] = { head = KIND_HEAD[d.kind] or (d.kind or "Other") }
      last = d.kind
    end
    out[#out + 1] = { d = d }
  end
  return out
end

local function RefreshMenu(list, all, sel)
  local items = MenuItems(list)
  for i = 1, math.max(#items, #agMenuRows) do
    local it = items[i]
    local r = agMenuRows[i]
    if it then
      r = GetMenuRow(i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", agMenuScroll.content, "TOPLEFT", 0, -(i - 1) * AG_MENU_H)
      local pad = NS.theme.m.rowPad
      r.text:ClearAllPoints()
      if it.head then
        -- group header: flush left, gold, not clickable (mouse off, no highlight)
        r.dungeonKey, r.fullName, r.isHeader = nil, nil, true
        r.text:SetPoint("LEFT", r, "LEFT", pad, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -pad, 0)
        r.text:SetText(it.head)
        r.text:SetTextColor(NS.Color("gold"))
        r.small:SetText("")
        r.sel:Hide()
        r:EnableMouse(false)
      else
        local d = it.d
        r.dungeonKey, r.fullName, r.isHeader = d.key, d.name, false
        r.text:SetPoint("LEFT", r, "LEFT", pad + AG_MENU_INDENT, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -(pad + 44), 0)
        r.text:SetText(d.name)
        local okW, w = pcall(r.text.GetStringWidth, r.text)
        if okW and type(w) == "number" and w > agMenuTextW then r.text:SetText(CompactName(d.name)) end
        r:EnableMouse(true)
        local on = (d == sel)
        r.text:SetTextColor(NS.Color(on and "liOn" or (d.seeded and "listInk" or "listSoft")))
        r.small:SetText(LevelText(d))
        if on then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      end
      r:Show()
    elseif r then
      r:Hide()
      r.dungeonKey = nil
    end
  end
  local rows = math.max(1, math.min(#items, AG_MENU_MAX))
  agMenuScroll:SetContentHeight(math.max(1, #items * AG_MENU_H))
  agMenu.count = #items
  agMenuHead:SetText(#list == #all and string.format("%d dungeons & raids", #all)
    or string.format("%d of %d dungeons & raids", #list, #all))
  return rows
end

local function RefreshAG()
  if not agPage or not NS.AG then return end
  local AGD = NS.AG
  local db = AGPrefs()
  local all = AGD.Dungeons()
  local lvl = db.agLevel == "mine" and "mine" or "all"
  local plevel = PlayerLevel()
  local list = AGD.Filter(all, agText, lvl, "all", plevel)
  if agLvlAll then agLvlAll:SetActive(lvl == "all") end
  if agLvlMine then
    agLvlMine:SetActive(lvl == "mine")
    PillLabel(agLvlMine, plevel and ("Near level " .. plevel) or "Near my level")
  end

  -- selected dungeon (stays selected only while it passes the filter)
  local sel
  for _, d in ipairs(list) do if d.key == db.agDungeon then sel = d end end
  sel = sel or list[1]
  if NS.db and sel then NS.db.agDungeon = sel.key end
  RefreshMenu(list, all, sel)
  agDrop.text:SetText(sel and sel.name or (#all == 0 and "No dungeons" or "No match"))
  if sel then  -- long wing names ("Scarlet Monastery: Graveyard") use initials for the prefix; the header shows the full name
    local okW, w = pcall(agDrop.text.GetStringWidth, agDrop.text)
    if #sel.name > 25 or (okW and type(w) == "number" and w > agDropTextW) then agDrop.text:SetText(CompactName(sel.name)) end
  end
  agDrop.small:SetText(sel and LevelText(sel) or "")

  -- dungeon header + bosses
  local bosses = sel and sel.bosses or {}
  local boss
  for _, b in ipairs(bosses) do if b.name == db.agBoss then boss = b end end
  boss = boss or bosses[1]
  if not sel then
    agTitle:SetText("No dungeons")
    agMeta:SetText(#all == 0 and "The game's dungeon list is empty on this client." or "No dungeons match the search or level filter.")
  else
    agTitle:SetText(sel.name)
    local bits = { "Level " .. LevelText(sel) }
    if sel.recLevel and sel.recLevel > 0 then bits[#bits + 1] = "Recommended " .. sel.recLevel end
    if sel.size and sel.size > 0 then bits[#bits + 1] = sel.size .. "-player" end
    bits[#bits + 1] = sel.kind
    if sel.forever then bits[#bits + 1] = "New in Forever" end
    if sel.zone and sel.zone ~= "" then bits[#bits + 1] = sel.zone end
    bits[#bits + 1] = #bosses .. (#bosses == 1 and " boss" or " bosses")
    agMeta:SetText(table.concat(bits, " · "))
  end
  agBossHead:SetText(string.format("Bosses (%d)", #bosses))
  local q = agText ~= "" and agText or nil
  for i = 1, math.max(#bosses, #agBossRows) do
    local b = bosses[i]
    local r = agBossRows[i]
    if b then
      r = GetBossRow(i)
      r.bossName = b.name
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", agBossScroll.content, "TOPLEFT", 0, -(i - 1) * AG_BOSS_H)
      local label = b.name
      if q and b.name:lower():find(q, 1, true) then label = "> " .. label end
      r.text:SetText(label)
      local on = (b == boss)
      r.text:SetTextColor(NS.Color(on and "liOn" or "listInk"))
      local bits = {}
      if b.rare then bits[#bits + 1] = "rare spawn" end
      if b.seeded then
        local n = #b.drops
        bits[#bits + 1] = n == 1 and "1 drop" or (n .. " drops")
      elseif b.live then
        bits[#bits + 1] = "live LFG boss · drops coming soon"
      else
        bits[#bits + 1] = "drops coming soon"
      end
      r.sub:SetText(table.concat(bits, " · "))
      r.sub:SetTextColor(NS.Color(on and "liOn" or "listSoft"))
      if on then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      r:Show()
    elseif r then
      r:Hide()
    end
  end
  agBossScroll:SetContentHeight(math.max(1, #bosses * AG_BOSS_H))
  if agEmptyBoss then if sel and #bosses == 0 then agEmptyBoss:Show() else agEmptyBoss:Hide() end end

  -- drops
  local drops = boss and boss.drops or {}
  local seenN = 0
  for i = 1, math.max(#drops, #agDropRows) do
    local it = drops[i]
    local r = agDropRows[i]
    if it then
      r = GetDropRow(i)
      r.dungeon, r.boss = sel, boss
      r.entry = { itemId = it.itemId, name = it.name, quality = it.quality, icon = it.icon, pct = it.pct }
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", agDropScroll.content, "TOPLEFT", 0, -(i - 1) * AG_DROP_H)
      r:SetPoint("RIGHT", agDropScroll.content, "RIGHT", 0, 0)
      -- client name when cached (rows and tooltip agree); our Forever name otherwise
      local cname = NS.FishingClientItemName and NS.FishingClientItemName(it.itemId)
      r.text:SetText(cname or it.name)
      local qq = NS.FishingItemQuality and NS.FishingItemQuality(it.itemId, it.quality) or it.quality
      local cr, cg, cb = 1, 1, 1
      if GetItemQualityColor then
        local okc, a1, a2, a3 = pcall(GetItemQualityColor, qq)
        if okc and type(a1) == "number" then cr, cg, cb = a1, a2, a3 end
      end
      r.text:SetTextColor(NS.Legible(cr, cg, cb))
      local n = NS.AG.SeenCount(sel.key, boss.name, it.itemId)
      r.seen = n
      if n > 0 then seenN = seenN + 1 end
      r.sub:SetText(string.format("%s · %.1f%% drop · %s", QUALITY_WORD[qq] or "Item", it.pct or 0,
        n > 0 and ("seen " .. n .. "×") or "not seen yet"))
      r.icon:SetItem(it.itemId, qq, it.icon)
      r:Show()
      if r == agHover then
        local okM, over = pcall(r.IsMouseOver, r)
        if not (okM and over == false) then NS.ShowItemTooltip(r, r.entry, AGLines(r)) end
      end
    elseif r then
      r:Hide()
      r.entry = nil
    end
  end
  agDropScroll:SetContentHeight(math.max(1, #drops * AG_DROP_H))
  agDropHead:SetText(boss and boss.name or "")
  if sel and boss and boss.seeded then
    agDropNote:SetText(string.format("%d %s · %d seen by you", #drops, #drops == 1 and "drop" or "drops", seenN))
  else
    agDropNote:SetText("")
  end
  if agEmptyDrops then
    if #drops > 0 then
      agEmptyDrops:Hide()
    else
      if not sel then
        agEmptyDrops:SetText("")
      elseif not boss then
        agEmptyDrops:SetText("Boss and drop data coming soon.\nLoot learning records what you see here.")
      elseif not boss.seeded then
        agEmptyDrops:SetText("Drop data coming soon for this boss.\nLoot learning records what you see here.")
      else
        agEmptyDrops:SetText("Wowhead WoW Forever lists no boss-specific drops here.\nLoot learning records what you see.")
      end
      agEmptyDrops:Show()
    end
  end
  if badgeText and NS.db and NS.db.section == "adventure" then badgeText:SetText("Dungeons: " .. #all) end
end

local function ScheduleAG()
  if agPending then return end
  agPending = true
  C_Timer.After(0.25, function()
    agPending = false
    if NS.db and NS.db.section == "adventure" then RefreshAG() end
  end)
end

local function EnsureAGEvents(on)
  if on then
    if not agEv then
      agEv = CreateFrame("Frame")
      agEv:SetScript("OnEvent", function() ScheduleAG() end)
    end
    pcall(function() agEv:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
    if NS.AG then NS.AG.onChange = ScheduleAG end
  elseif agEv then
    pcall(function() agEv:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end)
    if NS.AG then NS.AG.onChange = nil end
  end
  if not on then SetMenuOpen(false) end
end

local function BuildAdventure(page)
  local m = NS.theme.m
  agPage = CreateFrame("Frame", nil, page)
  agPage:SetAllPoints(page)
  local pad = m.pagePad
  local innerW = m.pageW - pad * 2
  local baseLevel = agPage.GetFrameLevel and agPage:GetFrameLevel() or 1

  local bar = CreateFrame("Frame", nil, agPage)
  bar:SetPoint("TOPLEFT", agPage, "TOPLEFT", pad, -pad)
  bar:SetSize(innerW, 28)
  if bar.SetFrameLevel then bar:SetFrameLevel(baseLevel + 20) end

  -- dungeon dropdown: a Button + our own menu frame (no UIDropDownMenu: shared Blizzard state, taint risk)
  local DROP_W = 230
  agDropTextW = DROP_W - 73
  agDrop = CreateFrame("Button", nil, bar)
  agDrop:SetSize(DROP_W, 26)
  agDrop:SetPoint("LEFT", bar, "LEFT", 0, 0)
  local dbg = agDrop:CreateTexture(nil, "BACKGROUND")
  dbg:SetAllPoints(agDrop)
  NS.OnSkin(function()  -- 0.4.4: themed (was always near-black, a dark box on the light Priest page)
    local c = NS.theme.colors.fieldBg or { 0.02, 0.02, 0.02, 0.92 }
    dbg:SetColorTexture(c[1], c[2], c[3], c[4] or 0.92)
  end)
  agDrop.border = UI.NineSlice(agDrop, "pane", 4, "BORDER", 1)
  agDrop.text = OneLine(UI.Text(agDrop, "OVERLAY", 13, "gold", "LEFT"), 16)
  agDrop.text:SetPoint("LEFT", agDrop, "LEFT", 9, 0)
  agDrop.text:SetPoint("RIGHT", agDrop, "RIGHT", -64, 0)
  agDrop.small = OneLine(UI.Text(agDrop, "OVERLAY", 11, "listSoft", "RIGHT"), 14)
  agDrop.small:SetPoint("RIGHT", agDrop, "RIGHT", -24, 0)
  agDrop.small:SetWidth(38)
  -- arrow: the scrollbar's down piece (a texture; the game fonts have no triangle glyphs)
  agDrop.arrow = agDrop:CreateTexture(nil, "OVERLAY")
  agDrop.arrow:SetSize(16, 16)
  agDrop.arrow:SetPoint("RIGHT", agDrop, "RIGHT", -5, 0)
  NS.OnSkin(function() NS.SetPiece(agDrop.arrow, "sb_dn") end)
  agDrop:SetScript("OnClick", function()
    if agMenu:IsShown() then SetMenuOpen(false) else
      SetMenuOpen(true)
      if tab and tab.RefreshAG then tab.RefreshAG() end
    end
  end)

  local MENU_W = DROP_W + 40
  agMenuTextW = (MENU_W - 8) - NS.theme.m.sbWidth - (NS.theme.m.rowPad + AG_MENU_INDENT) - (NS.theme.m.rowPad + 44)
  local MENU_H = 26 + AG_MENU_MAX * AG_MENU_H + 8
  agMenu = UI.Panel(agPage, MENU_W, MENU_H)
  agMenu:SetPoint("TOPLEFT", agDrop, "BOTTOMLEFT", 0, -2)
  if agMenu.SetFrameLevel then agMenu:SetFrameLevel(baseLevel + 60) end
  if agMenu.EnableMouse then agMenu:EnableMouse(true) end
  agMenuHead = OneLine(UI.Text(agMenu, "OVERLAY", 11, "listHead", "LEFT"), 14)
  agMenuHead:SetPoint("TOPLEFT", agMenu, "TOPLEFT", 10, -8)
  agMenuHead:SetPoint("RIGHT", agMenu, "RIGHT", -10, 0)
  agMenuScroll = UI.Scroll(agMenu, MENU_W - 8, AG_MENU_MAX * AG_MENU_H)
  agMenuScroll.frame:SetPoint("TOPLEFT", agMenu, "TOPLEFT", 4, -26)
  agMenu:Hide()
  agPage:SetScript("OnHide", function() SetMenuOpen(false) end)

  agSearch = UI.SearchBox(bar, 140, 24)
  agSearch:SetPoint("LEFT", agDrop, "RIGHT", 8, 0)
  agSearch.onChange = function(t)
    agText = (t or ""):lower()
    if tab and tab.RefreshAG then tab.RefreshAG() end
  end
  agLvlAll = UI.Pill(bar, "All levels")
  agLvlAll:SetPoint("LEFT", agSearch, "RIGHT", 10, 0)
  agLvlAll:SetScript("OnClick", function() if NS.db then NS.db.agLevel = "all" end RefreshAG() end)
  agLvlMine = UI.Pill(bar, "Near my level")
  agLvlMine:SetPoint("LEFT", agLvlAll, "RIGHT", m.pillGap, 0)
  agLvlMine:SetScript("OnClick", function() if NS.db then NS.db.agLevel = "mine" end RefreshAG() end)

  -- dungeon header: title line + meta line
  local headY = pad + 36
  agTitle = OneLine(UI.Text(agPage, "OVERLAY", 18, "inkHead", "LEFT"), 22)  -- 0.4.4: paper ink (it sits on the page)
  agTitle:SetPoint("TOPLEFT", agPage, "TOPLEFT", pad + 2, -headY)
  agTitle:SetPoint("RIGHT", agPage, "RIGHT", -pad - 2, 0)
  agMeta = OneLine(UI.Text(agPage, "OVERLAY", 12, "inkSoft", "LEFT"), 15)
  agMeta:SetPoint("TOPLEFT", agPage, "TOPLEFT", pad + 2, -(headY + 25))
  agMeta:SetPoint("RIGHT", agPage, "RIGHT", -pad - 2, 0)

  local splitY = headY + 48
  local splitH = m.sectionPageH - splitY - pad
  local bossW = 220
  local bp = UI.Panel(agPage, bossW, splitH)
  bp:SetPoint("TOPLEFT", agPage, "TOPLEFT", pad, -splitY)
  agBossHead = OneLine(UI.Text(bp, "OVERLAY", 12, "listHead", "LEFT"), 15)
  agBossHead:SetPoint("TOPLEFT", bp, "TOPLEFT", 10, -8)
  agBossHead:SetPoint("RIGHT", bp, "RIGHT", -10, 0)
  agBossScroll = UI.Scroll(bp, bossW - 8, splitH - 32)
  agBossScroll.frame:SetPoint("TOPLEFT", bp, "TOPLEFT", 4, -28)
  agEmptyBoss = UI.Text(bp, "OVERLAY", 12, "listSoft", "CENTER")
  agEmptyBoss:SetPoint("CENTER", bp, "CENTER", 0, 0)
  agEmptyBoss:SetText("Boss and drop data\ncoming soon.")
  agEmptyBoss:Hide()

  local dropW = innerW - bossW - 8
  local dp = UI.Panel(agPage, dropW, splitH)
  dp:SetPoint("TOPLEFT", agPage, "TOPLEFT", pad + bossW + 8, -splitY)
  -- header: boss name line, then the count line under it (never side by side)
  agDropHead = OneLine(UI.Text(dp, "OVERLAY", 13, "listHead", "LEFT"), 16)
  agDropHead:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -8)
  agDropHead:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  agDropNote = OneLine(UI.Text(dp, "OVERLAY", 11, "listSoft", "LEFT"), 13)
  agDropNote:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -26)
  agDropNote:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  agDropScroll = UI.Scroll(dp, dropW - 8, splitH - 48)
  agDropScroll.frame:SetPoint("TOPLEFT", dp, "TOPLEFT", 4, -44)
  agEmptyDrops = UI.Text(dp, "OVERLAY", 12, "listSoft", "CENTER")
  agEmptyDrops:SetPoint("CENTER", dp, "CENTER", 0, 0)
  agEmptyDrops:Hide()

  tab.RefreshAG = RefreshAG
  NS.AGWidgets = function()
    return { drop = agDrop, menu = agMenu, menuRows = agMenuRows, menuScroll = agMenuScroll, bossRows = agBossRows,
      dropRows = agDropRows, title = agTitle, meta = agMeta, dropHead = agDropHead, dropNote = agDropNote,
      bossHead = agBossHead, search = agSearch, emptyBoss = agEmptyBoss, emptyDrops = agEmptyDrops }
  end
  agPage:Hide()
end

---------------------------------------------------------------------------
-- section switching
---------------------------------------------------------------------------
local function AchActive(on)
  if NS.AchPage and NS.AchPage.SetActive then NS.AchPage.SetActive(on) end
end

local function ShowSection(id)
  local sec
  for _, s in ipairs(SECTIONS) do if s.id == id then sec = s end end
  if not sec then sec = SECTIONS[1] id = sec.id end
  if NS.db then NS.db.section = id end
  for _, p in ipairs(pills) do p:SetActive(p.sectionId == id) end
  if id ~= "achievements" then AchActive(false) end

  if id == "fishing" then
    EnsureAGEvents(false)
    if agPage then agPage:Hide() end
    if fishPage then fishPage:Show() end
    if stubPage then stubPage:Hide() end
    RefreshFish()
    EnsureFishEvents(tab and tab:IsShown())
  elseif id == "adventure" then
    EnsureFishEvents(false)
    if fishPage then fishPage:Hide() end
    if stubPage then stubPage:Hide() end
    if agPage then agPage:Show() end
    RefreshAG()
    EnsureAGEvents(tab and tab:IsShown())
  elseif id == "achievements" and NS.AchPage then
    EnsureFishEvents(false)
    EnsureAGEvents(false)
    if fishPage then fishPage:Hide() end
    if agPage then agPage:Hide() end
    if stubPage then stubPage:Hide() end
    AchActive(true)
  else
    EnsureFishEvents(false)
    EnsureAGEvents(false)
    if fishPage then fishPage:Hide() end
    if agPage then agPage:Hide() end
    if stubPage then stubPage:Show() end
    if stub then stub:SetContent(NS.theme.glyphs.journals, sec.name, sec.sub) end
    if badgeText then badgeText:SetText("Coming soon") end
  end
end

NS.RegisterTab({
  id = "journals", name = "Journals", glyph = "journals",
  Build = function(body)
    local m = NS.theme.m
    tab = CreateFrame("Frame", nil, body)
    tab:SetAllPoints(body)
    pills = {}
    local prev
    for _, s in ipairs(SECTIONS) do
      local p = UI.Pill(tab, s.name)
      p.sectionId = s.id
      if prev then
        p:SetPoint("TOPLEFT", prev, "TOPRIGHT", m.pillGap, 0)
      else
        p:SetPoint("TOPLEFT", tab, "TOPLEFT", m.pageX, 0)
      end
      p:SetScript("OnClick", function() ShowSection(s.id) end)
      pills[#pills + 1] = p
      prev = p
    end

    local badge = CreateFrame("Frame", nil, tab)
    badge:SetSize(110, 24)
    badge:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -8, -4)
    UI.ThreeSlice(badge, "badge", 24, "ARTWORK")
    badgeText = UI.Text(badge, "OVERLAY", 11, "badge", "CENTER")
    badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badgeText:SetText("Coming soon")

    local page = UI.Page(tab, m.pageW, m.sectionPageH)
    page:SetPoint("TOPLEFT", tab, "TOPLEFT", m.pageX, -m.sectionPageY)

    BuildFish(page)
    BuildAdventure(page)
    if NS.AchPage then
      NS.AchPage.Build(page, { badge = function(t) if badgeText then badgeText:SetText(t) end end })
    end
    stubPage = CreateFrame("Frame", nil, page)
    stubPage:SetAllPoints(page)
    stub = UI.Stub(stubPage, NS.theme.glyphs.journals, "", "")

    selectedZone = NS.db and NS.db.fishingZone or nil
    ShowSection(NS.db and NS.db.section or "adventure")
    return tab
  end,
  OnShow = function()
    if NS.db and NS.db.section == "fishing" then
      EnsureFishEvents(true)
      RefreshFish()
    elseif NS.db and NS.db.section == "adventure" then
      EnsureAGEvents(true)
      RefreshAG()
    elseif NS.db and NS.db.section == "achievements" then
      AchActive(true)
    end
  end,
  OnHide = function()
    EnsureFishEvents(false)
    EnsureAGEvents(false)
    if NS.db and NS.db.section == "achievements" then
      if NS.Ach then NS.Ach.onChange = nil end
    end
  end,
  Refresh = function()
    if NS.db and NS.db.section == "fishing" then RefreshFish()
    elseif NS.db and NS.db.section == "adventure" then RefreshAG()
    elseif NS.db and NS.db.section == "achievements" and NS.AchPage then NS.AchPage.Refresh() end
  end,
  SetSection = function(id) ShowSection(id) end,
  agWidgets = function() return NS.AGWidgets and NS.AGWidgets() end,
  achWidgets = function() return NS.AchPage and NS.AchPage.Widgets() end,
})
