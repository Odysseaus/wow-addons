-- WoW default theme (data only). Numbers are the approved previewer mockup's CSS pixels (window 880x680).
-- The art is the mockup's generated raster art, converted by tools/make_wow_textures.py (see Atlas_WoW.lua).
local _, NS = ...

NS.RegisterTheme({
  id = "wow",
  name = "WoW",
  title = "Dark Matter",
  atlas = "wow",
  media = {
    parchment = "Interface\\AddOns\\DarkMatter\\Media\\wow-parchment",
    slate = "Interface\\AddOns\\DarkMatter\\Media\\wow-slate",
  },
  colors = {
    ink = "#2b1d0e", inkSoft = "#4a3820", inkHead = "#2b1608", inkFaint = "#6a5434",
    gold = "#f0cf4a", goldOn = "#fff0b0", greyBtn = "#7c7a72",
    title = "#e9e6dc", listInk = "#e4e0d2", listSoft = "#a8a496", listHead = "#b9b6ab", liOn = "#ffffff",
    good = "#4cc43a", mid = "#ecd83c", low = "#e8442e", row = "#ecd83c",
    status = "#6d6b64", lheadAll = "#fff0b0", lheadInk = "#d8d4c6", badge = "#f2d63a",
    popBg = "#1a1a18", popBorder = "#f2d63a", popInk = "#e4e0d2",
  },
  m = {
    -- window
    w = 880, h = 680, pad = 9, frameCorner = 16, maxScreenFraction = 0.92,
    slateShade = 0.88, footerTint = 0.2,
    -- title plate, medal, close button
    titleX = 81, titleY = 9, titleW = 746, titleH = 28, titleSize = 15,
    medalX = -24, medalY = -24, medalSize = 78,
    closeSize = 28, closeRight = 3, closeTop = 3,
    -- shell: rail, body, footer
    shellTop = 37, footerTop = 630, footerH = 41,
    railX = 15, railY = 77, railW = 176, railH = 547, railBorder = 9, railShade = 0.45,
    tabX = 34, tabY = 100, tabH = 48, tabW = 132, tabWOn = 146, tabGap = 8, tabIcon = 20, tabSize = 13,
    bodyX = 203, bodyY = 37, bodyW = 668, bodyH = 593,
    pageX = 4, pageW = 656, pageH = 587, pageBorder = 9, pagePad = 23,
    pillsH = 32, pillGap = 6, pillPad = 16, pillSize = 13, sectionPageY = 40, sectionPageH = 547,
    listBorder = 5, listShade = 0.38, sbWidth = 20,
    rowH = 26, rowSize = 13, rowPad = 7,
    -- footer
    fbtnW = 104, fbtnH = 30, fbtnY = 635, fbtnSize = 13, fbtnLeft = 17,
    statusX = 131, statusY = 637, statusW = 504, statusH = 26, statusSize = 11,
    shareX = 645, exitX = 759,
    -- quest-log style head row above the rail
    lheadAllX = 19, lheadAllY = 51, lheadAllW = 54, lheadAllH = 24, lheadTrkX = 89, lheadTrkY = 56, lheadSize = 13,
    -- settings popover
    popX = 23, popBottom = 56, popW = 300, popH = 132,
  },
  -- tab glyphs: atlas piece keys
  glyphs = { quests = "glyph_quests", journals = "glyph_journals", map = "glyph_map", dungeons = "glyph_dungeons" },
})
