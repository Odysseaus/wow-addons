-- Journals tab: Fishing panel with waters list + catch statistics (per-character).
-- Adventure Guide and Achievements stay placeholders.
local _, NS = ...
local UI = NS.UI

local SECTIONS = {
  { id = "fishing", name = "Fishing" },
  { id = "adventure", name = "Adventure Guide",
    sub = "Dungeons, raids, bosses and their drops come in a later phase." },
  { id = "achievements", name = "Achievements",
    sub = "A themed achievement browser comes in a later phase." },
}

local tab, pills, badgeText
local fishPage, stubPage, stub
local skillBar, skillTitle, skillSub
local viewWaters, watersRoot, statsRoot, statsScroll
local zoneScroll, detailTitle, detailMeta, detailStatus, detailBody, emptyFish
local fvWaters, fvStats
local rowPool, selectedZone, fishRank, fishMax, fishName = {}, nil, nil, nil, nil
local ev, pending = nil, false
local ROW_H
local statCards = {}

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
  fishName, fishRank, fishMax = NS.ReadFishingSkill()
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

local function ShowDetail(z)
  if not detailTitle then return end
  if not z then
    detailTitle:SetText("No waters listed")
    detailMeta:SetText("")
    detailStatus:SetText("")
    detailBody:SetText("Fishing waters will show here.")
    return
  end
  local st, col = ZoneStatus(z, fishRank)
  local catches, items = NS.FishingZoneStats(z.name)
  detailTitle:SetText(z.name)
  detailMeta:SetText(string.format("Levels %s  ·  %s", z.levels, z.continent))
  local status = NS.ColorCode(col) .. st .. "|r"
  if catches > 0 then
    status = status .. "  ·  " .. catches .. " catches logged"
  end
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
  lines[#lines + 1] = ""
  if catches == 0 then
    lines[#lines + 1] = "No catches logged here yet. Fish in this zone and Dark Matter will record them."
  else
    lines[#lines + 1] = "Catches in this zone (share of zone total):"
    for _, it in ipairs(items) do
      local pct = catches > 0 and (100 * it.count / catches) or 0
      local tag = it.junk and "  (junk)" or ""
      lines[#lines + 1] = string.format("  %s — %d (%.0f%%)%s", it.name, it.count, pct, tag)
    end
  end
  detailBody:SetText(table.concat(lines, "\n"))
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
  c.head = UI.Text(c, "OVERLAY", 12, "listHead", "LEFT")
  c.head:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -8)
  c.big = UI.Text(c, "OVERLAY", 22, "gold", "LEFT")
  c.big:SetPoint("TOPLEFT", c.head, "BOTTOMLEFT", 0, -4)
  c.sub = UI.Text(c, "OVERLAY", 11, "listSoft", "LEFT")
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
local function SetFishView(id)
  if NS.db then NS.db.fishingView = id end
  if fvWaters then fvWaters:SetActive(id == "waters") end
  if fvStats then fvStats:SetActive(id == "stats") end
  if watersRoot then if id == "waters" then watersRoot:Show() else watersRoot:Hide() end end
  if statsRoot then if id == "stats" then statsRoot:Show() else statsRoot:Hide() end end
end

local function RefreshFish()
  if not fishPage then return end
  ReadSkill()
  if skillBar then
    if fishRank and fishMax then
      skillTitle:SetText(fishName or "Fishing skill")
      skillBar:SetProgress(fishRank, fishMax, fishRank .. " / " .. fishMax, "gold")
      skillSub:SetText("Live skill · catches saved per character from first cast.")
    else
      skillTitle:SetText("Fishing skill")
      skillBar:SetProgress(0, 1, "Not learned", "listSoft")
      skillSub:SetText("No fishing profession on this character.")
    end
    skillBar:Show()
  end

  local zones = NS.FishingZones or {}
  if not selectedZone or not zones[selectedZone] then
    selectedZone = BestZoneIndex(fishRank)
  end
  local n = #zones
  for i = 1, math.max(n, #rowPool) do
    local r = rowPool[i]
    local z = zones[i]
    if z then
      r = GetRow(i)
      r.index = i
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", zoneScroll.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
      local _, col = ZoneStatus(z, fishRank)
      local isSel = (i == selectedZone)
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
  if zoneScroll then zoneScroll:SetContentHeight(n * ROW_H) end
  if emptyFish then
    if n == 0 then emptyFish:Show() else emptyFish:Hide() end
  end
  ShowDetail(zones[selectedZone])
  RefreshStats()

  local fdb = NS.GetFishingDB and NS.GetFishingDB() or {}
  if badgeText and NS.db and NS.db.section == "fishing" then
    local c = fdb.catches or 0
    if c > 0 then badgeText:SetText("Catches: " .. c) else badgeText:SetText("Zones: " .. n) end
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
  -- UI refresh only; catch recording runs always via Fishing.lua.
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
  fishPage = CreateFrame("Frame", nil, page)
  fishPage:SetAllPoints(page)

  local pad = m.pagePad
  local innerW = m.pageW - pad * 2

  -- view pills
  viewWaters = CreateFrame("Frame", nil, fishPage)
  viewWaters:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -pad)
  viewWaters:SetSize(innerW, 28)
  fvWaters = UI.Pill(viewWaters, "Waters")
  fvWaters:SetPoint("TOPLEFT", viewWaters, "TOPLEFT", 0, 0)
  fvWaters:SetScript("OnClick", function() SetFishView("waters") RefreshFish() end)
  fvStats = UI.Pill(viewWaters, "Statistics")
  fvStats:SetPoint("TOPLEFT", fvWaters, "TOPRIGHT", m.pillGap, 0)
  fvStats:SetScript("OnClick", function() SetFishView("stats") RefreshFish() end)

  local skillH = 52
  local skillPanel = UI.Panel(fishPage, innerW, skillH)
  skillPanel:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -(pad + 32))
  skillTitle = UI.Text(skillPanel, "OVERLAY", 14, "listHead", "LEFT")
  skillTitle:SetPoint("TOPLEFT", skillPanel, "TOPLEFT", 12, -8)
  skillBar = UI.Bar(skillPanel, innerW - 24, 18)
  skillBar:SetPoint("TOPLEFT", skillPanel, "TOPLEFT", 12, -26)
  skillSub = UI.Text(skillPanel, "OVERLAY", 10, "listSoft", "LEFT")
  skillSub:SetPoint("TOPLEFT", skillBar, "BOTTOMLEFT", 0, -2)

  local splitY = pad + 32 + skillH + 10
  local splitH = m.sectionPageH - splitY - pad

  watersRoot = CreateFrame("Frame", nil, fishPage)
  watersRoot:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -splitY)
  watersRoot:SetSize(innerW, splitH)

  local leftW = 240
  local rightW = innerW - leftW - 10
  local left = UI.Panel(watersRoot, leftW, splitH)
  left:SetPoint("TOPLEFT", watersRoot, "TOPLEFT", 0, 0)
  local lh = UI.Text(left, "OVERLAY", 12, "listHead", "LEFT")
  lh:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -8)
  lh:SetText("Waters")
  zoneScroll = UI.Scroll(left, leftW - 8, splitH - 28)
  zoneScroll.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 4, -26)
  emptyFish = UI.Text(left, "OVERLAY", 12, "listSoft", "CENTER")
  emptyFish:SetPoint("CENTER", left, "CENTER", 0, 0)
  emptyFish:SetText("No waters listed.")
  emptyFish:Hide()

  local right = UI.Panel(watersRoot, rightW, splitH)
  right:SetPoint("TOPLEFT", watersRoot, "TOPLEFT", leftW + 10, 0)
  detailTitle = UI.Text(right, "OVERLAY", 18, "gold", "LEFT")
  detailTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -12)
  detailTitle:SetPoint("TOPRIGHT", right, "TOPRIGHT", -14, -12)
  detailMeta = UI.Text(right, "OVERLAY", 12, "listSoft", "LEFT")
  detailMeta:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -4)
  detailStatus = UI.Text(right, "OVERLAY", 13, "good", "LEFT")
  detailStatus:SetPoint("TOPLEFT", detailMeta, "BOTTOMLEFT", 0, -6)
  detailBody = UI.Text(right, "OVERLAY", 12, "listInk", "LEFT")
  detailBody:SetPoint("TOPLEFT", detailStatus, "BOTTOMLEFT", 0, -10)
  detailBody:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -14, 14)

  statsRoot = CreateFrame("Frame", nil, fishPage)
  statsRoot:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -splitY)
  statsRoot:SetSize(innerW, splitH)
  statsScroll = UI.Scroll(statsRoot, innerW, splitH)
  statsScroll.frame:SetPoint("TOPLEFT", statsRoot, "TOPLEFT", 0, 0)
  statsRoot:Hide()

  tab.RefreshFish = RefreshFish
  SetFishView(NS.db and NS.db.fishingView or "waters")
end

---------------------------------------------------------------------------
-- section switching
---------------------------------------------------------------------------
local function ShowSection(id)
  local sec
  for _, s in ipairs(SECTIONS) do if s.id == id then sec = s end end
  if not sec then sec = SECTIONS[1] id = sec.id end
  if NS.db then NS.db.section = id end
  for _, p in ipairs(pills) do p:SetActive(p.sectionId == id) end

  if id == "fishing" then
    if fishPage then fishPage:Show() end
    if stubPage then stubPage:Hide() end
    RefreshFish()
    EnsureFishEvents(tab and tab:IsShown())
  else
    EnsureFishEvents(false)
    if fishPage then fishPage:Hide() end
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
    stubPage = CreateFrame("Frame", nil, page)
    stubPage:SetAllPoints(page)
    stub = UI.Stub(stubPage, NS.theme.glyphs.journals, "", "")

    selectedZone = NS.db and NS.db.fishingZone or nil
    ShowSection(NS.db and NS.db.section or "fishing")
    return tab
  end,
  OnShow = function()
    if NS.db and NS.db.section == "fishing" then
      EnsureFishEvents(true)
      RefreshFish()
    end
  end,
  OnHide = function()
    EnsureFishEvents(false)
  end,
  Refresh = function()
    if NS.db and NS.db.section == "fishing" then RefreshFish() end
  end,
})
