-- Dark Matter 0.5.2a.1: the docked quest panel. While the Map tab is showing, the quest log sits as its own panel
-- docked to the right of the Dark Matter window, like the game's map + quest log: locked in place (it is a child of the
-- window, so it moves and scales with it), themed in every theme, open or closed as saved in DarkMatterDB.questPanel.
-- Top: the stock quest log's search bar (the game's SearchBoxTemplate and its "Quests: n/max" box, built from the game's
-- own template and atlases where this client has them). Below: the same quest list as the Quests tab (Tab_Quests views,
-- shared QuestState). A row click opens that quest's detail (the Quests tab's detail code) with a Back button.
-- Our own frames only: nothing of the game's is hooked or changed.
local _, NS = ...
local UI = NS.UI

local P = { w = 336, gap = 6, open = false }
NS.QuestPanel = P

local frame, view, det, lp, dp, sbar, count
local function T() return NS.tabs and NS.tabs.quests end

function P.Wanted() return not (NS.db and NS.db.questPanel == false) end

-- the panel's offset to the right of the window: past the theme's border art
local function RightReach()
  local MW = NS.MapWindow
  if MW and MW.ThemeBorder then
    local ok, _, _, r = pcall(MW.ThemeBorder, NS.theme, NS.theme.m)
    if ok and NS.Num(r) then return r end
  end
  return 0
end
function P.Extent() return RightReach() + P.gap + P.w end

local function Place()
  if not frame then return end
  local win = frame:GetParent()
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", win, "TOPRIGHT", RightReach() + P.gap, 0)
  frame:SetHeight(NS.theme.m.h)
end

-- live quest count and the log's maximum, from the game's API (nil when this client gives none)
function P.QuestCount()
  local CQ = C_QuestLog
  local n
  if CQ and CQ.GetNumQuestLogEntries then
    local ok, _, nq = pcall(CQ.GetNumQuestLogEntries)
    if ok then n = NS.Num(nq) end
  end
  if not n and T() and T().Count then n = T().Count() end
  local max
  if CQ and CQ.GetMaxNumQuestsCanAccept then
    local ok, v = pcall(CQ.GetMaxNumQuestsCanAccept)
    if ok then max = NS.Num(v) end
  end
  local K = _G.Constants and _G.Constants.QuestLogConsts
  max = max or (K and NS.Num(K.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT)) or NS.Num(_G.MAX_QUESTLOG_QUESTS)
  return n or 0, max
end
function P.CountText()
  local n, max = P.QuestCount()
  if not max then return "Quests: |cffffffff" .. n .. "|r" end
  local fmt = type(_G.QUEST_LOG_COUNT_TEMPLATE) == "string" and _G.QUEST_LOG_COUNT_TEMPLATE or "Quests: %s%d|r/%d"
  local ok, s = pcall(string.format, fmt, n > max and "|cffff2020" or "|cffffffff", n, max)
  return ok and s or ("Quests: " .. n .. "/" .. max)
end
local function UpdateCount() if count then count.text:SetText(P.CountText()) end end

local function AtlasOK(a)
  local f = C_Texture and C_Texture.GetAtlasInfo
  if type(f) ~= "function" then return false end
  local ok, info = pcall(f, a)
  return ok and type(info) == "table"
end

-- the stock quest log's search bar: the game's search box (magnifier, grey "Search Quest Log") and its count box
local function BuildSearchBar(parent, w)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetSize(w, 30)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetColorTexture(0.02, 0.02, 0.02, 0.9)
  bar.border = UI.NineSlice(bar, "pane", 4, "BORDER", 1)
  local cw = 96
  -- count box: the game's input-box border pieces (common-search-border-*) with the yellow small font, as QuestLogCount
  local c = CreateFrame("Frame", nil, bar)
  c:SetSize(cw, 20)
  c:SetPoint("RIGHT", bar, "RIGHT", -7, 0)
  if AtlasOK("common-search-border-middle") then
    local l = c:CreateTexture(nil, "BACKGROUND") l:SetAtlas("common-search-border-left") l:SetSize(8, 20) l:SetPoint("LEFT", c, "LEFT", -5, 0)
    local r = c:CreateTexture(nil, "BACKGROUND") r:SetAtlas("common-search-border-right") r:SetSize(8, 20) r:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    local m = c:CreateTexture(nil, "BACKGROUND") m:SetAtlas("common-search-border-middle")
    m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0) m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
    c.stock = true
  else
    UI.NineSlice(c, "pane", 4, "BORDER", 1)
  end
  c.text = c:CreateFontString(nil, "ARTWORK")
  if _G.GameFontNormalSmall and c.text.SetFontObject and pcall(c.text.SetFontObject, c.text, _G.GameFontNormalSmall) then
    c.stockFont = true
  else
    NS.SetFont(c.text, 11, "")
    c.text:SetTextColor(1, 0.82, 0, 1)
  end
  c.text:SetPoint("RIGHT", c, "RIGHT", -6, 0)
  count = c
  -- search: the game's SearchBoxTemplate when the client has it, else Dark Matter's own box
  local sw = w - cw - 7 - 7 - 10 - 6
  local placeholder = type(_G.SEARCH_QUEST_LOG) == "string" and _G.SEARCH_QUEST_LOG or "Search Quest Log"
  local sb = NS.Stock.FromTemplate("EditBox", bar, "SearchBoxTemplate")
  if sb then
    sb:SetSize(sw, 20)
    sb:SetPoint("LEFT", bar, "LEFT", 12, 0)
    if sb.SetAutoFocus then sb:SetAutoFocus(false) end
    if type(sb.Instructions) == "table" and sb.Instructions.SetText then sb.Instructions:SetText(placeholder) end
    sb:SetScript("OnTextChanged", function(self, user)
      if type(_G.SearchBoxTemplate_OnTextChanged) == "function" then pcall(_G.SearchBoxTemplate_OnTextChanged, self, user) end
      if view then view.SetQuery(self:GetText() or "") end
    end)
    bar.stock = true
    bar.edit = sb
    function bar.SetText(_, t) sb:SetText(t or "") end
  else
    local s = UI.SearchBox(bar, sw, 22)
    s:SetPoint("LEFT", bar, "LEFT", 8, 0)
    s.placeholder:SetText(placeholder)
    s.onChange = function(t) if view then view.SetQuery(t) end end
    bar.edit = s.edit
    function bar.SetText(_, t) s:SetText(t or "") end
  end
  return bar
end

local function ShowList()
  if dp then dp:Hide() end
  if lp then lp:Show() end
  if view then view.Refresh() end -- the scroll position and the search text are kept (the list was only hidden)
end
local function ShowDetail(q)
  if not (dp and det and T()) then return end
  lp:Hide()
  dp:Show()
  T().ShowDetail(q, det)
  if det.scroll and det.scroll.SetScroll then pcall(det.scroll.SetScroll, det.scroll, 0) end
end
P.ShowList, P.ShowDetail = ShowList, ShowDetail

function P.Build(win)
  if frame then return frame end
  local t = T()
  if not (win and t and t.NewView) then return nil end
  local m = NS.theme.m
  local f = CreateFrame("Frame", nil, win)
  f:SetSize(P.w, m.h)
  f:SetFrameLevel(win:GetFrameLevel() + 2)
  f:EnableMouse(true) -- locked: it does not move by itself, it follows the window
  f:Hide()
  frame = f
  P.frame = f
  Place()
  UI.Slate(f, "slateShade", "BACKGROUND", 0)
  f.border = UI.NineSlice(f, "frame", m.frameCorner, "BORDER", 2)
  -- head: title + close (the game's close button in the WoW theme, our own elsewhere)
  local title = UI.Text(f, "OVERLAY", 14, "gold", "CENTER")
  title:SetPoint("TOP", f, "TOP", 0, -14)
  title:SetText("Quest Log")
  f.title = title
  local close = NS.Stock.FromTemplate("Button", f, "UIPanelCloseButton")
  if not close then
    close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    local ct = close:CreateTexture(nil, "ARTWORK")
    ct:SetAllPoints(close)
    NS.OnSkin(function() NS.SetPiece(ct, "xbtn") end)
  end
  if (NS.Num(close:GetWidth()) or 0) <= 0 then close:SetSize(28, 28) end
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() P.SetOpen(false) end)
  f.close = close
  local pad = 14
  local cw = P.w - 2 * pad
  sbar = BuildSearchBar(f, cw)
  sbar:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -38)
  f.search = sbar
  local G = UI.Gutter()
  local b = m.listBorder
  local top = 38 + 30 + 8
  local h = m.h - top - pad
  -- the list (same rows, watch boxes and selection as the Quests tab)
  lp = UI.Panel(f, cw - G, h)
  lp:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -top)
  view = t.NewView(lp, cw - G - 2 * b, h - 2 * b, b, -b, {
    onPick = function(q) ShowDetail(q) end,
    after = function() UpdateCount() if dp and dp:IsShown() and det and det.quest then T().ShowDetail(det.quest.questID or det.quest.title, det) end end,
  })
  -- the detail (the Quests tab's detail code) with Back at its top
  dp = UI.Panel(f, cw - G, h, "detailShade")
  dp:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -top)
  dp:Hide()
  local back = UI.Button(dp, "Back", 72, 22, "red", 11)
  back:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -10)
  back:SetScript("OnClick", ShowList)
  det = t.NewDetail(dp, cw - G, h, 28)
  det.back = back
  P.view, P.detail, P.list, P.detailPanel, P.back = view, det, lp, dp, back
  NS.OnSkin(function() Place() UpdateCount() end)
  return f
end

-- 0.5.2a.2: a map pin click opens THAT quest's detail here (opening the panel if it was closed; from the list or
-- another quest's detail). A quest not in the log shows the list. Returns true when the detail is shown.
function P.OpenQuest(q)
  if q == nil then return false end
  if not P.Wanted() then P.SetOpen(true) elseif not (frame and frame:IsShown()) then P.Sync() end
  if not (frame and frame:IsShown() and T()) then return false end
  local found = T().FindQuest and T().FindQuest(q)
  if not found then ShowList() return false end
  ShowDetail(found)
  return true
end

-- shown while the Map tab is showing and the panel is wanted
function P.Sync(mapShown)
  if mapShown ~= nil then P.mapShown = mapShown end
  local want = P.mapShown and P.Wanted()
  if want and not frame then P.Build(_G.DarkMatterFrame) end
  if not frame then return end
  if want then
    Place()
    frame:Show()
    if T() and T().Events then T().Events(true, "panel") end
    if view then view.Refresh() end
    UpdateCount()
  else
    frame:Hide()
    if T() and T().Events then T().Events(false, "panel") end
  end
  if NS.WindowClampExtra then NS.WindowClampExtra(want and P.Extent() or 0) end
  if NS.MapTab and NS.MapTab.SetPanelIcon then NS.MapTab.SetPanelIcon() end
end
function P.SetOpen(on)
  if NS.db then NS.db.questPanel = on and true or false end
  P.Sync()
end
function P.Toggle() P.SetOpen(not P.Wanted()) end
function P.IsShown() return frame ~= nil and frame:IsShown() end
-- the window is being built again: the panel hung off the old one
function P.Drop()
  if frame then frame:Hide() end
  frame, view, det, lp, dp, sbar, count = nil, nil, nil, nil, nil, nil, nil
  P.frame, P.view, P.detail, P.list, P.detailPanel, P.back = nil, nil, nil, nil, nil, nil
  if NS.WindowClampExtra then NS.WindowClampExtra(0) end
end
