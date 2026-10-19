-- Journals tab: section pills (Fishing, Adventure Guide, Achievements) with placeholder pages for now.
local _, NS = ...

local SECTIONS = {
  { id = "fishing", name = "Fishing", sub = "Fishing skill, catches by zone and statistics come in a later phase." },
  { id = "adventure", name = "Adventure Guide", sub = "Dungeons, raids, bosses and their drops come in a later phase." },
  { id = "achievements", name = "Achievements", sub = "A themed achievement browser comes in a later phase." },
}

local tab, stub, pills, badgeText

local function ShowSection(id)
  local sec
  for _, s in ipairs(SECTIONS) do if s.id == id then sec = s end end
  if not sec then sec = SECTIONS[1] id = sec.id end
  if NS.db then NS.db.section = id end
  for _, p in ipairs(pills) do p:SetActive(p.sectionId == id) end
  stub:SetContent(NS.theme.glyphs.journals, sec.name, sec.sub)
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
      local p = NS.UI.Pill(tab, s.name)
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
    -- "Coming soon" badge on the right (the mockup has count / example-data badges here)
    local badge = CreateFrame("Frame", nil, tab)
    badge:SetSize(100, 24)
    badge:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -8, -4)
    NS.UI.ThreeSlice(badge, "badge", 24, "ARTWORK")
    badgeText = NS.UI.Text(badge, "OVERLAY", 11, "badge", "CENTER")
    badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badgeText:SetText("Coming soon")

    local page = NS.UI.Page(tab, m.pageW, m.sectionPageH)
    page:SetPoint("TOPLEFT", tab, "TOPLEFT", m.pageX, -m.sectionPageY)
    stub = NS.UI.Stub(page, NS.theme.glyphs.journals, "", "")
    ShowSection(NS.db and NS.db.section or "fishing")
    return tab
  end,
})
