-- WoW default theme (data only). Numbers are the approved previewer mockup's CSS pixels (window 880x680).
-- 0.5.1: the window is drawn with the game's own built-in art (stock textures referenced by path, plus the
-- UIPanelCloseButton template), like a stock WoW window. Nothing from the game is copied into the addon.
-- Each stock piece is checked at runtime (Stock.lua); a piece the client lacks falls back to Dark Matter's own art
-- (the generated atlas and media below), so nothing is ever blank. /dm artprobe lists them with ok/missing.
local _, NS = ...

-- The 0.5.0 WoW colours. The class themes inherit missing colour keys from these (not from the 0.5.1 stock colours),
-- so the class themes look exactly as before.
local CLASSIC_BASE = {
  gold = "#f0cf4a", btnInk = "#f0cf4a", goldOn = "#fff0b0", greyBtn = "#a09d95",
  title = "#e9e6dc", listInk = "#e4e0d2", listSoft = "#a8a496", listHead = "#b9b6ab", hoverEdge = "#ffd14dbf",
  status = "#9a978f", listBg = "#121210", low = "#e8442e",
}

NS.RegisterTheme({
  id = "wow",
  name = "WoW",
  title = "Dark Matter",
  atlas = "wow",
  baseColors = CLASSIC_BASE, -- read by RegisterTheme for themes with base = "wow"
  -- stock pieces by atlas key: file, texcoords (4 numbers, or 8 for a flipped piece), nominal piece size in pixels
  -- (w, h: used for the three-slice cap widths), optional blend mode. Texcoords are the ones Blizzard's own XML uses.
  stock = {
    frame = { edge = true, file = "Interface\\DialogFrame\\UI-DialogBox-Border", size = 24 },
    pane = { edge = true, file = "Interface\\Tooltips\\UI-Tooltip-Border", size = 12 },
    title_l = { file = "Interface\\DialogFrame\\UI-DialogBox-Header", tc = { 0, 0.25, 0, 0.625 }, w = 64, h = 40 },
    title_m = { file = "Interface\\DialogFrame\\UI-DialogBox-Header", tc = { 0.25, 0.75, 0, 0.625 }, w = 128, h = 40 },
    title_r = { file = "Interface\\DialogFrame\\UI-DialogBox-Header", tc = { 0.75, 1, 0, 0.625 }, w = 64, h = 40 },
    medal = { file = "Interface\\QuestFrame\\UI-QuestLog-BookIcon", w = 64, h = 64 },
    xbtn = { file = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", w = 32, h = 32 },
    btn_red_l = { file = "Interface\\Buttons\\UI-Panel-Button-Up", tc = { 0, 0.09375, 0, 0.6875 }, w = 12, h = 22 },
    btn_red_m = { file = "Interface\\Buttons\\UI-Panel-Button-Up", tc = { 0.09375, 0.53125, 0, 0.6875 }, w = 56, h = 22 },
    btn_red_r = { file = "Interface\\Buttons\\UI-Panel-Button-Up", tc = { 0.53125, 0.625, 0, 0.6875 }, w = 12, h = 22 },
    btn_grey_l = { file = "Interface\\Buttons\\UI-Panel-Button-Disabled", tc = { 0, 0.09375, 0, 0.6875 }, w = 12, h = 22 },
    btn_grey_m = { file = "Interface\\Buttons\\UI-Panel-Button-Disabled", tc = { 0.09375, 0.53125, 0, 0.6875 }, w = 56, h = 22 },
    btn_grey_r = { file = "Interface\\Buttons\\UI-Panel-Button-Disabled", tc = { 0.53125, 0.625, 0, 0.6875 }, w = 12, h = 22 },
    btn_field_l = { file = "Interface\\Common\\Common-Input-Border", tc = { 0, 0.0625, 0, 0.625 }, w = 8, h = 20 },
    btn_field_m = { file = "Interface\\Common\\Common-Input-Border", tc = { 0.0625, 0.9375, 0, 0.625 }, w = 112, h = 20 },
    btn_field_r = { file = "Interface\\Common\\Common-Input-Border", tc = { 0.9375, 1, 0, 0.625 }, w = 8, h = 20 },
    -- rail tabs: the stock red panel button, pressed (Down) when active
    rtab_i_l = { file = "Interface\\Buttons\\UI-Panel-Button-Up", tc = { 0, 0.09375, 0, 0.6875 }, w = 12, h = 22 },
    rtab_i_m = { file = "Interface\\Buttons\\UI-Panel-Button-Up", tc = { 0.09375, 0.53125, 0, 0.6875 }, w = 56, h = 22 },
    rtab_i_r = { file = "Interface\\Buttons\\UI-Panel-Button-Up", tc = { 0.53125, 0.625, 0, 0.6875 }, w = 12, h = 22 },
    rtab_a_l = { file = "Interface\\Buttons\\UI-Panel-Button-Down", tc = { 0, 0.09375, 0, 0.6875 }, w = 12, h = 22 },
    rtab_a_m = { file = "Interface\\Buttons\\UI-Panel-Button-Down", tc = { 0.09375, 0.53125, 0, 0.6875 }, w = 56, h = 22 },
    rtab_a_r = { file = "Interface\\Buttons\\UI-Panel-Button-Down", tc = { 0.53125, 0.625, 0, 0.6875 }, w = 12, h = 22 },
    -- 0.5.1.2: the pressed face of the stock panel button (UIPanelButtonTemplate's PushedTexture)
    btn_down_l = { file = "Interface\\Buttons\\UI-Panel-Button-Down", tc = { 0, 0.09375, 0, 0.6875 }, w = 12, h = 22 },
    btn_down_m = { file = "Interface\\Buttons\\UI-Panel-Button-Down", tc = { 0.09375, 0.53125, 0, 0.6875 }, w = 56, h = 22 },
    btn_down_r = { file = "Interface\\Buttons\\UI-Panel-Button-Down", tc = { 0.53125, 0.625, 0, 0.6875 }, w = 12, h = 22 },
    -- section tabs (Fishing / Adventure Guide / Achievements): the character-panel tabs, flipped to open downward
    ptab_i_l = { file = "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab", tc = { 0, 1, 0, 0, 0.15625, 1, 0.15625, 0 }, w = 20, h = 32 },
    ptab_i_m = { file = "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab", tc = { 0.15625, 1, 0.15625, 0, 0.84375, 1, 0.84375, 0 }, w = 88, h = 32 },
    ptab_i_r = { file = "Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab", tc = { 0.84375, 1, 0.84375, 0, 1, 1, 1, 0 }, w = 20, h = 32 },
    ptab_a_l = { file = "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab", tc = { 0, 0.546875, 0, 0, 0.15625, 0.546875, 0.15625, 0 }, w = 20, h = 35 },
    ptab_a_m = { file = "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab", tc = { 0.15625, 0.546875, 0.15625, 0, 0.84375, 0.546875, 0.84375, 0 }, w = 88, h = 35 },
    ptab_a_r = { file = "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab", tc = { 0.84375, 0.546875, 0.84375, 0, 1, 0.546875, 1, 0 }, w = 20, h = 35 },
    -- scroll bar: UIPanelScrollUpButtonTemplate / UIPanelScrollDownButtonTemplate (16x16, the four button states) and
    -- UIPanelScrollBarTemplate's thumb (UI-ScrollBar-Knob, 18x24). 0.5.1.1: drawn at the stock size, not stretched.
    sb_up = { file = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up", tc = { 0.2, 0.8, 0.25, 0.75 }, w = 16, h = 16,
      down = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down", disabled = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled",
      highlight = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight" },
    sb_dn = { file = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up", tc = { 0.2, 0.8, 0.25, 0.75 }, w = 16, h = 16,
      down = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down", disabled = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled",
      highlight = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight" },
    sb_thumb = { file = "Interface\\Buttons\\UI-ScrollBar-Knob", tc = { 0.2, 0.8, 0.125, 0.875 }, w = 18, h = 24 },
    sb_thumb_m = { file = "Interface\\Buttons\\UI-ScrollBar-Knob", tc = { 0.2, 0.8, 0.3, 0.7 }, w = 18, h = 12 },
    sb_thumb_t = { file = "Interface\\Buttons\\UI-ScrollBar-Knob", tc = { 0.2, 0.8, 0.125, 0.3 }, w = 18, h = 6 },
    sb_thumb_b = { file = "Interface\\Buttons\\UI-ScrollBar-Knob", tc = { 0.2, 0.8, 0.7, 0.875 }, w = 18, h = 6 },
    -- 0.5.1.2: the scroll bar's groove, like the quest log's (UI-Character-ScrollBar: a 256-texel top piece and a
    -- 106-texel bottom piece; a taller bar stretches the plain middle of the top piece between them)
    sb_track_t = { file = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar", tc = { 0, 0.484375, 0, 1 }, w = 31, h = 256 },
    sb_track_m = { file = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar", tc = { 0, 0.484375, 0.25, 0.75 }, w = 31, h = 128 },
    sb_track_b = { file = "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar", tc = { 0.515625, 1, 0, 0.4140625 }, w = 31, h = 106 },
    -- quest-log style expand/collapse and the selected-row glow
    coin_minus = { file = "Interface\\Buttons\\UI-MinusButton-Up", w = 32, h = 32 },
    coin_plus = { file = "Interface\\Buttons\\UI-PlusButton-Up", w = 32, h = 32 },
    hilite = { file = "Interface\\QuestFrame\\UI-QuestTitleHighlight", blend = "ADD", vc = { 1, 0.82, 0, 0.5 }, w = 256, h = 16 },
    -- check box (UICheckButtonTemplate's textures)
    check_box = { file = "Interface\\Buttons\\UI-CheckBox-Up", w = 32, h = 32 },
    check_mark = { file = "Interface\\Buttons\\UI-CheckBox-Check", w = 32, h = 32 },
  },
  -- stock surfaces by area. Every surface is anchored to both corners of its panel (SetAllPoints) and FILLS it:
  -- tile = repeat every N pixels; shade darkens; tc = the part of the file that is drawn (stretched to the panel).
  -- 0.5.1.1: the page (the area behind the lists) is the stock rock, not parchment. QuestBG is a 512x512 file whose
  -- parchment only covers about the top-left 300x336 texels, with torn edges and transparency beyond; 0.5.1 drew the
  -- whole file, so the parchment covered the top-left ~59% x 66% of each panel with a torn edge mid-panel. Now only the
  -- clean inside of the sheet (tc below, inside the torn border) is drawn, stretched over the whole detail panel.
  -- /dm parchment l r t b adjusts that crop in game (saved; /dm parchment reset).
  -- 0.5.1.4: the window wears the frame of the game's own map window (Window.lua BuildMapChrome, NS.MapWindow)
  mapWindow = true,
  -- 0.5.1.4: the map's breadcrumb is drawn like the stock map's top-bar buttons (World / Kalimdor / Darkshore)
  crumbFaces = true,
  stockMedia = {
    -- 0.5.1.4: the map window's dark inset (InsetFrameTemplate's marble) instead of the heavy rock behind everything
    shell = { file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = 256, shade = 0.42 },
    rail = { file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = 128 },
    list = { file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = 128 },
    page = { file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = 256, shade = 0.5 },
    -- the quest-detail and boss-detail panels, like the stock quest log
    detail = { file = "Interface\\QuestFrame\\QuestBG", tc = { 0.04, 0.545, 0.04, 0.615 }, crop = true },
  },
  -- 0.5.1.1: the page is dark here, so text that sits on the page uses light ink (pageDark); the fallback is the
  -- dark slate (never Dark Matter's light parchment under light ink)
  pageDark = true,
  panelWash = { 0, 0, 0, 0.35 }, -- the Fishing skill strip on the dark page (was a cream wash over parchment)
  -- 0.5.1.2: the stock button feel (Widgets UI.StockFeel): UIPanelButtonTemplate's four files and texcoords, and the
  -- character-frame tab highlight (flipped like the tabs, which open downward)
  stockButtons = {
    up = "Interface\\Buttons\\UI-Panel-Button-Up", down = "Interface\\Buttons\\UI-Panel-Button-Down",
    disabled = "Interface\\Buttons\\UI-Panel-Button-Disabled", highlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
    tc = { 0, 0.625, 0, 0.6875 },
    tabHighlight = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", tabHighlightTC = { 0, 1, 0, 0, 1, 1, 1, 0 },
  },
  -- stock templates (each checked first): { name, frame type }. UIPanelCloseButton is created from its template; the
  -- others (0.5.1.2) are reproduced by hand and reported by /dm artprobe so the client's set is on record.
  stockTemplates = { { "UIPanelCloseButton", "Button" }, { "UIPanelButtonTemplate", "Button" },
    { "CharacterFrameTabButtonTemplate", "Button" }, { "UIPanelScrollFrameTemplate", "ScrollFrame" },
    { "UIPanelScrollBarTemplate", "Slider" } },
  -- 0.5.1.3: what /dm artprobe says stands in for a piece the client lacks. The 1.60.1 client has no
  -- CharacterFrameTabButtonTemplate (35 ok, 1 missing in game); the section tabs never used it: they are built from the
  -- UI-Character-ActiveTab / InActiveTab textures, which the client has.
  stockFallback = {
    CharacterFrameTabButtonTemplate = "tabs use UI-Character-ActiveTab/InActiveTab",
    UIPanelButtonTemplate = "buttons use the UI-Panel-Button files",
    UIPanelScrollFrameTemplate = "Dark Matter's own scroll frame",
    UIPanelScrollBarTemplate = "bars use the UI-ScrollBar files",
    UIPanelCloseButton = "Dark Matter's own close button",
    ["Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"] = "map crumbs without the arrow",
    ["Interface\\FrameGeneral\\UI-Background-Marble"] = "Dark Matter's own slate",
  },
  media = {
    parchment = "Interface\\AddOns\\DarkMatter\\Media\\wow-parchment",
    slate = "Interface\\AddOns\\DarkMatter\\Media\\wow-slate",
  },
  colors = {
    -- 0.5.1.1: page text (dungeon header, Fishing skill strip, stubs, "Show all") sits on the dark stock rock:
    -- gold headings, white/grey body. The parchment detail panels use the pInk keys (dark quest ink).
    ink = "#ffffff", inkSoft = "#d0d0d0", inkHead = "#ffd100", inkFaint = "#b8b8b8",
    pInk = "#2b1d0e", pInkSoft = "#4a3820", pInkHead = "#2b1608", pInkFaint = "#6a5434",
    -- 0.5.1: the game's own font colours: GameFontNormal gold (1, 0.82, 0) for headers and buttons,
    -- GameFontHighlight white for body text on dark panels, dark quest ink on the parchment
    fieldBg = "#050505eb", gold = "#ffd100", btnInk = "#ffd100", goldOn = "#ffffff", greyBtn = "#d8d8d8",
    title = "#ffd100", listInk = "#ffffff", listSoft = "#c8c8c8", listHead = "#ffd100", liOn = "#ffffff",
    good = "#4cc43a", mid = "#ecd83c", low = "#ff6b55", row = "#ecd83c", -- 0.5.1: low is lighter (reads on the stock dark panel)
    status = "#d0d0d0", lheadAll = "#fff0b0", lheadInk = "#d8d4c6", badge = "#f2d63a",
    popBg = "#1a1a18", popBorder = "#f2d63a", popInk = "#e4e0d2",
    barFill = "#f0cf4a", barInk = "#fff6d8", barBorder = "#4b4a44", barTrack = "#050504",
    -- 0.4.4: achievement card fills and the hover look (tint + 1px edge, drawn under the label)
    card = "#0d0d0deb", cardOn = "#1a1712eb", hoverEdge = "#ffd10033", -- 0.5.1: hover is a subtle tint
    listBg = "#2a2a2a", -- representative list surface (NS.Legible); 0.5.1: the lighter end of the stock dark panel
    barText = "#fff6d8", -- bar labels in every theme (outlined)
    -- 0.5.1: state colours on the parchment quest-detail panel (dark enough for the QuestBG parchment)
    pGood = "#0f3f08", pMid = "#4a3000", pLow = "#6e1006",
    parchBg = "#b39a6c", -- 0.5.1.2: representative QuestBG parchment (NS.ParchQuality: item names drawn on it)
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
    railX = 15, railY = 77, railW = 150, railH = 547, railBorder = 9, railShade = 0.45,
    tabX = 29, tabY = 100, tabH = 48, tabW = 120, tabWOn = 126, tabGap = 8, tabIcon = 20, tabSize = 13,
    bodyX = 177, bodyY = 37, bodyW = 694, bodyH = 593,
    pageX = 4, pageW = 682, pageH = 587, pageBorder = 9, pagePad = 23,
    pillsH = 32, pillGap = 6, pillPad = 16, pillSize = 13, sectionPageY = 40, sectionPageH = 547,
    listBorder = 5, listShade = 0.38, sbWidth = 20,
    -- 0.5.1.3: the scroll bar's own gutter to the right of its pane (bar 20 + 5 each side, the stock groove 28 wide)
    sbGutter = 30,
    rowH = 26, rowSize = 13, rowPad = 7,
    -- footer
    fbtnW = 104, fbtnH = 30, fbtnY = 635, fbtnSize = 13, fbtnLeft = 17,
    statusX = 131, statusY = 637, statusW = 504, statusH = 26, statusSize = 11,
    shareX = 645, exitX = 759,
    -- quest-log style head row above the rail
    lheadAllX = 19, lheadAllY = 51, lheadAllW = 54, lheadAllH = 24, lheadTrkX = 89, lheadTrkY = 56, lheadSize = 13,
    -- settings popover
    popX = 23, popBottom = 56, popW = 300, popH = 270,
  },
  -- tab glyphs: atlas piece keys
  glyphs = { quests = "glyph_quests", journals = "glyph_journals", map = "glyph_map", dungeons = "glyph_dungeons" },
})
