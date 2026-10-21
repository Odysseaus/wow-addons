-- Map and Dungeons tabs: "coming in a later phase" pages (same stub look as the mockup).
local _, NS = ...

local function Stub(id, name, glyph, text)
  NS.RegisterTab({
    id = id, name = name, glyph = glyph,
    Build = function(body)
      local m = NS.theme.m
      local tab = CreateFrame("Frame", nil, body)
      tab:SetAllPoints(body)
      local page = NS.UI.Page(tab, m.pageW, m.pageH)
      page:SetPoint("TOPLEFT", tab, "TOPLEFT", m.pageX, 0)
      NS.UI.Stub(page, NS.theme.glyphs[id], "Coming soon", text)
      return tab
    end,
  })
end

Stub("map", "Map", "map", "The Map tab is being built. Type /dm mapprobe and send a screenshot of the results.")
Stub("dungeons", "Dungeons", "dungeons", "The Dungeons tab comes in a later phase: lockouts and run tracking.")
