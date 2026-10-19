-- Journals tab: Fishing is a real panel (skill + zone waters). Adventure Guide and Achievements stay placeholders.
local _, NS = ...
local UI = NS.UI

local SECTIONS = {
  { id = "fishing", name = "Fishing" },
  { id = "adventure", name = "Adventure Guide",
    sub = "Dungeons, raids, bosses and their drops come in a later phase." },
  { id = "achievements", name = "Achievements",
    sub = "A themed achievement browser comes in a later phase." },
}

local tab, pills, badge, badgeText
local fishPage, stubPage, stub
local skillBar, skillTitle, skillSub, zoneScroll, detailTitle, detailMeta, detailStatus, detailBody, emptyFish
local rowPool, selectedZone, fishRank, fishMax, fishName = {}, nil, nil, nil, nil
local ev, pending = nil, false
local ROW_H

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

---------------------------------------------------------------------------
-- skill + list
---------------------------------------------------------------------------
local function ReadSkill()
  fishName, fishRank, fishMax = NS.ReadFishingSkill()
end

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
  detailTitle:SetText(z.name)
  detailMeta:SetText(string.format("Levels %s  ·  %s", z.levels, z.continent))
  detailStatus:SetText(NS.ColorCode(col) .. st .. "|r")
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
  lines[#lines + 1] = "Catch counts and statistics come in a later phase (this client has no fishing-zone API)."
  detailBody:SetText(table.concat(lines, "\n"))
end

local function RefreshFish()
  if not fishPage then return end
  ReadSkill()
  if skillBar then
    if fishRank and fishMax then
      skillTitle:SetText(fishName or "Fishing skill")
      skillBar:SetProgress(fishRank, fishMax, fishRank .. " / " .. fishMax, "gold")
      skillSub:SetText("Read from GetProfessionInfo (probe-confirmed).")
      skillBar:Show()
    else
      skillTitle:SetText("Fishing skill")
      skillBar:SetProgress(0, 1, "Not learned", "listSoft")
      skillSub:SetText("No fishing profession on this character.")
      skillBar:Show()
    end
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
      r.text:SetText(z.name)
      r.text:SetTextColor(NS.Color(isSel and "liOn" or "listInk"))
      r.small:SetText(tostring(z.minSkill))
      r.small:SetTextColor(NS.Color(col))
      if isSel then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      r:Show()
    elseif r then
      r:Hide()
    end
  end
  zoneScroll:SetContentHeight(n * ROW_H)
  if emptyFish then
    if n == 0 then emptyFish:Show() else emptyFish:Hide() end
  end
  ShowDetail(zones[selectedZone])
  if badgeText and NS.db and NS.db.section == "fishing" then
    badgeText:SetText("Zones: " .. n)
  end
  if NS.SetStatus and fishRank and fishMax then
    NS.SetStatus(string.format("Dark Matter %s · Fishing %d / %d", NS.version, fishRank, fishMax))
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
    -- skill updates (present on this client family; pcall via RegisterEvent is fine)
    pcall(function() ev:RegisterEvent("SKILL_LINES_CHANGED") end)
    pcall(function() ev:RegisterEvent("CHAT_MSG_SKILL") end)
  elseif ev then
    ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
    pcall(function() ev:UnregisterEvent("SKILL_LINES_CHANGED") end)
    pcall(function() ev:UnregisterEvent("CHAT_MSG_SKILL") end)
  end
end

local function BuildFish(page)
  local m = NS.theme.m
  ROW_H = m.rowH
  fishPage = CreateFrame("Frame", nil, page)
  fishPage:SetAllPoints(page)

  local pad = m.pagePad
  local innerW = m.pageW - pad * 2
  local skillH = 52
  local skillPanel = UI.Panel(fishPage, innerW, skillH)
  skillPanel:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -pad)
  skillTitle = UI.Text(skillPanel, "OVERLAY", 14, "listHead", "LEFT")
  skillTitle:SetPoint("TOPLEFT", skillPanel, "TOPLEFT", 12, -8)
  skillBar = UI.Bar(skillPanel, innerW - 24, 18)
  skillBar:SetPoint("TOPLEFT", skillPanel, "TOPLEFT", 12, -26)
  skillSub = UI.Text(skillPanel, "OVERLAY", 10, "listSoft", "LEFT")
  skillSub:SetPoint("TOPLEFT", skillBar, "BOTTOMLEFT", 0, -2)

  local splitY = pad + skillH + 10
  local splitH = m.sectionPageH - splitY - pad
  local leftW = 240
  local rightW = innerW - leftW - 10

  local left = UI.Panel(fishPage, leftW, splitH)
  left:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad, -splitY)
  local lh = UI.Text(left, "OVERLAY", 12, "listHead", "LEFT")
  lh:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -8)
  lh:SetText("Waters")
  zoneScroll = UI.Scroll(left, leftW - 8, splitH - 28)
  zoneScroll.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 4, -26)
  emptyFish = UI.Text(left, "OVERLAY", 12, "listSoft", "CENTER")
  emptyFish:SetPoint("CENTER", left, "CENTER", 0, 0)
  emptyFish:SetText("No waters listed.")
  emptyFish:Hide()

  local right = UI.Panel(fishPage, rightW, splitH)
  right:SetPoint("TOPLEFT", fishPage, "TOPLEFT", pad + leftW + 10, -splitY)
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

  tab.RefreshFish = RefreshFish
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
    if badgeText then badgeText:SetText("Zones: " .. #(NS.FishingZones or {})) end
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

    badge = CreateFrame("Frame", nil, tab)
    badge:SetSize(100, 24)
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
