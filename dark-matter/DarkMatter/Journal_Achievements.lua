-- Journals > Achievements (0.4.0). Category dropdown in the Adventure Guide style (gold group headers flush left and
-- not clickable, entries indented 12px, closes on an outside click, Esc and when the window hides), achievement list
-- (icon, points, status/date, a progress bar each) and a detail pane with criteria.
-- Groups: "Legacy Challenges" = the game's own achievement API (shown only when the client returns data) and
-- "Dark Matter" = our own per-character set (Achievements.lua). Stock frames only, no Blizzard dropdown template, no hooks.
local _, NS = ...
local UI = NS.UI
local P = {}
NS.AchPage = P

local page, bar, drop, menu, menuScroll, menuHead, catch, mouseEv
local title, meta, listHead, listScroll, listEmpty
local dIcon, dName, dPts, dDesc, dStatus, dBar, critHead, critScroll, critEmpty, dNote
local fAll, fDone, fTodo
local menuRows, listRows, critRows = {}, {}, {}
local MENU_H, ROW_H, CRIT_H, MENU_MAX, MENU_INDENT = 22, 52, 20, 14, 12
local menuTextW, dropTextW = 172, 157
local hooks = {}
local pending, onShowing = false, false
local GOLD = 10000
P.GAME_HEAD, P.DM_HEAD = "Legacy Challenges", "Dark Matter"

local function OneLine(fs, h)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetHeight(h)
  return fs
end
local function CompactName(n)
  local pre, rest = n:match("^(.-):%s*(.+)$")
  if not pre then return n end
  return pre:gsub("(%a)[%a']*%s*", "%1") .. ": " .. rest
end
local function Fit(fs, text, w)
  fs:SetText(text)
  local ok, sw = pcall(fs.GetStringWidth, fs)
  if ok and type(sw) == "number" and sw > w then fs:SetText(CompactName(text)) end
end
local function Prefs() return NS.db or {} end
local function GoldText(c) return math.floor((c or 0) / GOLD) .. "g" end

---------------------------------------------------------------------------
-- data model
---------------------------------------------------------------------------
-- dropdown items: { head } or { key, name, small, game|dm, cat }
function P.Categories()
  local ACH = NS.Ach
  local mode = ACH.Mode()
  local out = {}
  if mode ~= "dm" then
    out[#out + 1] = { head = P.GAME_HEAD }
    for _, c in ipairs(ACH.ReadGame().cats) do
      out[#out + 1] = { key = c.key, name = c.name, game = true, cat = c, small = c.done .. "/" .. #c.list }
    end
  end
  if mode ~= "game" then
    out[#out + 1] = { head = P.DM_HEAD }
    local t = ACH.Totals()
    for _, name in ipairs(ACH.CATS) do
      local tc = t.cats[name] or { count = 0, earned = 0 }
      out[#out + 1] = { key = "dm:" .. name, name = name, dm = true, small = tc.earned .. "/" .. tc.count }
    end
  end
  return out, mode
end

local function GameItem(a)
  local ACH = NS.Ach
  local crit = {}
  for _, c in ipairs(ACH.GameCriteria(a.id)) do
    crit[#crit + 1] = { name = c.name, done = c.done, cur = c.cur, need = c.need,
      text = c.need > 1 and (c.text or (c.cur .. " / " .. c.need)) or nil }
  end
  local cur, need
  if #crit == 1 and (crit[1].need or 0) > 1 then cur, need = crit[1].cur, crit[1].need
  elseif #crit > 0 then
    cur, need = 0, #crit
    for _, c in ipairs(crit) do if c.done then cur = cur + 1 end end
  else cur, need = a.completed and 1 or 0, 1 end
  if a.completed then cur = need end
  local pts = (a.legacy and a.legacy > 0) and (a.legacy .. (a.legacy == 1 and " Legacy Point" or " Legacy Points"))
    or (a.points .. " pts")
  return { key = a.key, name = a.name, desc = a.desc, pts = pts, ptsShort = (a.legacy and a.legacy > 0) and (a.legacy .. " LP") or (a.points .. " pts"),
    done = a.completed, when = a.when, cur = cur, need = need, icon = a.icon, crit = crit, game = true,
    whenNote = a.completed and not a.mine and "another character" or nil,
    reward = a.reward }
end

local function DMItem(a)
  local ACH = NS.Ach
  local cur, need, crit = ACH.Progress(a)
  local e = ACH.Earned(a)
  if e then cur = need end
  local curText = a.money and (GoldText(cur) .. " / " .. GoldText(need)) or (cur .. " / " .. need)
  local out = {}
  for _, c in ipairs(crit or {}) do
    out[#out + 1] = { name = c.name, done = c.done or (e and true), cur = c.cur, need = c.need,
      text = c.count and c.count > 1 and (c.count .. "×") or nil }
  end
  return { key = a.key, name = a.name, desc = a.desc, pts = a.points .. " points", ptsShort = a.points .. " pts",
    done = e and true or false, when = e and e.when or nil, retro = e and e.retro, cur = cur, need = need,
    curText = curText, icon = a.icon, crit = out, dm = true }
end

-- achievements of one dropdown entry, filtered ("all" / "done" / "todo")
function P.Items(entry, filter)
  local out = {}
  if not entry then return out end
  local src = {}
  if entry.game then
    for _, a in ipairs(entry.cat.list) do src[#src + 1] = GameItem(a) end
  else
    for _, a in ipairs(NS.Ach.Defs()) do if a.catKey == entry.key then src[#src + 1] = DMItem(a) end end
  end
  for _, it in ipairs(src) do
    if filter == "done" and it.done or filter == "todo" and not it.done or filter ~= "done" and filter ~= "todo" then
      out[#out + 1] = it
    end
  end
  return out, #src
end

---------------------------------------------------------------------------
-- dropdown (same model as the Adventure Guide's; named catcher for Esc)
---------------------------------------------------------------------------
local SetMenuOpen
local function EnsureCatcher()
  if catch then return catch end
  catch = CreateFrame("Frame", "DarkMatterAchMenuCatcher", UIParent)
  catch:SetAllPoints(UIParent)
  catch:EnableMouse(true)
  catch:Hide()
  catch:SetScript("OnMouseDown", function() SetMenuOpen(false) end)
  catch:SetScript("OnHide", function() if menu and menu:IsShown() then SetMenuOpen(false) end end)
  mouseEv = CreateFrame("Frame")
  mouseEv:SetScript("OnEvent", function()
    if not (menu and menu:IsShown()) then return end
    local okM, overM = pcall(menu.IsMouseOver, menu)
    local okD, overD = pcall(drop.IsMouseOver, drop)
    if okM and okD and overM == false and overD == false then SetMenuOpen(false) end
  end)
  return catch
end

SetMenuOpen = function(on)
  if not menu then return end
  if on then
    menu:Show()
    local c = EnsureCatcher()
    local okS, strata = pcall(menu.GetFrameStrata, menu)
    if okS and type(strata) == "string" then pcall(c.SetFrameStrata, c, strata) end
    local okL, lvl = pcall(menu.GetFrameLevel, menu)
    if okL and type(lvl) == "number" then pcall(c.SetFrameLevel, c, math.max(0, lvl - 1)) end
    c:Show()
    pcall(mouseEv.RegisterEvent, mouseEv, "GLOBAL_MOUSE_DOWN")
    if NS.SpecialFrame then NS.SpecialFrame("DarkMatterFrame", false) NS.SpecialFrame("DarkMatterAchMenuCatcher", true) end
  else
    menu:Hide()
    if catch then
      if catch:IsShown() then catch:Hide() end
      pcall(mouseEv.UnregisterEvent, mouseEv, "GLOBAL_MOUSE_DOWN")
      if NS.SpecialFrame then NS.SpecialFrame("DarkMatterAchMenuCatcher", false) end
      if NS.RestoreEscMain then NS.RestoreEscMain() end
    end
  end
  if drop and drop.arrow then NS.SetPiece(drop.arrow, on and "sb_up" or "sb_dn") end
end
P.SetMenuOpen = function(on) SetMenuOpen(on) end

local function GetMenuRow(i)
  local r = menuRows[i]
  if r then return r end
  local m = NS.theme.m
  r = CreateFrame("Button", nil, menuScroll.content)
  r:SetSize(menuScroll.w - m.sbWidth, MENU_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.text = OneLine(UI.Text(r, "OVERLAY", 13, "listInk", "LEFT"), 16)
  r.small = OneLine(UI.Text(r, "OVERLAY", 12, "listSoft", "RIGHT"), 14)
  r.small:SetPoint("RIGHT", r, "RIGHT", -m.rowPad, 0)
  r.small:SetWidth(40)
  r:SetScript("OnClick", function(self)
    if self.isHeader or type(self.catKey) ~= "string" then return end
    if NS.db then NS.db.achCat = self.catKey NS.db.achSel = nil end
    SetMenuOpen(false)
    P.Refresh()
  end)
  menuRows[i] = r
  return r
end

local function RefreshMenu(items, sel)
  local pad = NS.theme.m.rowPad
  local ncat = 0
  for i = 1, math.max(#items, #menuRows) do
    local it, r = items[i], menuRows[i]
    if it then
      r = GetMenuRow(i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", menuScroll.content, "TOPLEFT", 0, -(i - 1) * MENU_H)
      r.text:ClearAllPoints()
      if it.head then
        r.catKey, r.fullName, r.isHeader = nil, nil, true
        r.text:SetPoint("LEFT", r, "LEFT", pad, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -pad, 0)
        r.text:SetText(it.head)
        r.text:SetTextColor(NS.Color("gold"))
        r.small:SetText("")
        r.sel:Hide()
        r:EnableMouse(false)
      else
        ncat = ncat + 1
        r.catKey, r.fullName, r.isHeader = it.key, it.name, false
        r.text:SetPoint("LEFT", r, "LEFT", pad + MENU_INDENT, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -(pad + 44), 0)
        Fit(r.text, it.name, menuTextW)
        r:EnableMouse(true)
        local on = (it == sel)
        r.text:SetTextColor(NS.Color(on and "liOn" or "listInk"))
        r.small:SetText(it.small or "")
        if on then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      end
      r:Show()
    elseif r then
      r:Hide()
      r.catKey = nil
    end
  end
  menuScroll:SetContentHeight(math.max(1, #items * MENU_H))
  menu.count = #items
  local rows = math.max(1, math.min(#items, MENU_MAX))
  menu:SetHeight(26 + rows * MENU_H + 8)
  menuHead:SetText(ncat .. (ncat == 1 and " category" or " categories"))
end

---------------------------------------------------------------------------
-- list + detail
---------------------------------------------------------------------------
local function GetListRow(i)
  local r = listRows[i]
  if r then return r end
  local w = listScroll.w - NS.theme.m.sbWidth
  r = CreateFrame("Button", nil, listScroll.content)
  r:SetSize(w, ROW_H)
  r.sel = r:CreateTexture(nil, "BACKGROUND")
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.icon = UI.RoundIcon(r, 32)
  r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -6)
  r.text = OneLine(UI.Text(r, "OVERLAY", 13, "listInk", "LEFT"), 16)
  r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 46, -4)
  r.text:SetPoint("RIGHT", r, "RIGHT", -56, 0)
  r.pts = OneLine(UI.Text(r, "OVERLAY", 11, "gold", "RIGHT"), 14)
  r.pts:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -5)
  r.pts:SetWidth(48)
  r.sub = OneLine(UI.Text(r, "OVERLAY", 11, "listSoft", "LEFT"), 13)
  r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 46, -21)
  r.sub:SetPoint("RIGHT", r, "RIGHT", -8, 0)
  r.bar = UI.Bar(r, w - 46 - 8, 9, true)
  r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 46, -37)
  r:SetScript("OnClick", function(self)
    if NS.db then NS.db.achSel = self.itemKey end
    P.Refresh()
  end)
  listRows[i] = r
  return r
end

local function GetCritRow(i)
  local r = critRows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, critScroll.content)
  r:SetSize(critScroll.w - NS.theme.m.sbWidth, CRIT_H)
  r.text = OneLine(UI.Text(r, "OVERLAY", 12, "listInk", "LEFT"), 15)
  r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -70, 0)
  r.val = OneLine(UI.Text(r, "OVERLAY", 11, "listSoft", "RIGHT"), 14)
  r.val:SetPoint("RIGHT", r, "RIGHT", -8, 0)
  r.val:SetWidth(60)
  critRows[i] = r
  return r
end

local function StatusText(it)
  if it.done then
    local s = "Earned" .. (it.when and (" " .. it.when) or "")
    if it.retro then s = s .. " · at install" end      -- level the game confirmed when Dark Matter was installed
    if it.whenNote then s = s .. " · " .. it.whenNote end
    return s, "good"
  end
  return "In progress: " .. (it.curText or (it.cur .. " / " .. it.need)), "listSoft"
end

local function SetIcon(ic, it)
  ic:SetItem(nil, it.done and 2 or 1, it.icon)
  if ic.tex and ic.tex.SetDesaturated then pcall(ic.tex.SetDesaturated, ic.tex, not it.done) end
end

local function RefreshDetail(it)
  local ACH = NS.Ach
  if not it then
    dName:SetText("No achievement selected")
    dPts:SetText("") dDesc:SetText("") dStatus:SetText("")
    dBar:SetProgress(0, 1, "")
    critHead:SetText("")
    for _, r in ipairs(critRows) do r:Hide() end
    critEmpty:Hide()
    dNote:SetText("")
    return
  end
  SetIcon(dIcon, it)
  dName:SetText(it.name)
  dPts:SetText(it.pts)
  dDesc:SetText(it.desc ~= "" and it.desc or "No description from the game.")
  local st, col = StatusText(it)
  dStatus:SetText(st)
  dStatus:SetTextColor(NS.Color(col))
  dBar:SetProgress(it.cur, it.need, it.curText or (it.cur .. " / " .. it.need))
  local crit = it.crit or {}
  critHead:SetText(#crit > 0 and string.format("Criteria (%d)", #crit) or "Criteria")
  for i = 1, math.max(#crit, #critRows) do
    local c, r = crit[i], critRows[i]
    if c then
      r = GetCritRow(i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", critScroll.content, "TOPLEFT", 0, -(i - 1) * CRIT_H)
      r.text:SetText(c.name)
      r.text:SetTextColor(NS.Color(c.done and "good" or "listInk"))
      r.val:SetText(c.text or (c.done and "done" or "not yet"))
      r.val:SetTextColor(NS.Color(c.done and "good" or "listSoft"))
      r:Show()
    elseif r then r:Hide() end
  end
  critScroll:SetContentHeight(math.max(1, #crit * CRIT_H))
  if #crit == 0 then
    critEmpty:SetText(it.need > 1 and "Progress is counted as a total (no separate criteria)." or "A single goal (no separate criteria).")
    critEmpty:Show()
  else critEmpty:Hide() end
  if it.dm then
    local db = ACH.DB()
    dNote:SetText("Dark Matter (not Blizzard) · since " .. ((db and db.since or "install"):sub(1, 10)))
  else
    dNote:SetText("Game data · Legacy Challenge · account-wide")
  end
end

function P.Refresh()
  if not page or not NS.Ach then return end
  local ACH = NS.Ach
  local db = Prefs()
  local items, mode = P.Categories()
  local sel
  for _, it in ipairs(items) do if not it.head and it.key == db.achCat then sel = it end end
  if not sel then for _, it in ipairs(items) do if not it.head and not sel then sel = it end end end
  if sel and NS.db then NS.db.achCat = sel.key end
  RefreshMenu(items, sel)
  if sel then
    Fit(drop.text, sel.name, dropTextW)
    drop.small:SetText(sel.small or "")
  else
    drop.text:SetText("No categories") drop.small:SetText("")
  end

  local filter = (db.achFilter == "done" or db.achFilter == "todo") and db.achFilter or "all"
  fAll:SetActive(filter == "all") fDone:SetActive(filter == "done") fTodo:SetActive(filter == "todo")
  local list, total = P.Items(sel, filter)

  -- header
  if not sel then
    title:SetText("Achievements")
    meta:SetText("No achievement data.")
  else
    title:SetText(sel.name)
    local bits = {}
    if sel.game then
      local c = sel.cat
      bits[#bits + 1] = "Game: Legacy Challenges"
      bits[#bits + 1] = c.done .. " of " .. #c.list .. " complete"
      bits[#bits + 1] = "account-wide"
    else
      local tc = ACH.Totals().cats[sel.name] or { earned = 0, count = 0, pointsEarned = 0, points = 0 }
      bits[#bits + 1] = "Dark Matter achievements"
      bits[#bits + 1] = tc.earned .. " of " .. tc.count .. " earned"
      bits[#bits + 1] = tc.pointsEarned .. " / " .. tc.points .. " points"
      if mode == "dm" then bits[#bits + 1] = "no game achievement API" end
    end
    meta:SetText(table.concat(bits, " · "))
  end
  listHead:SetText(filter == "all" and string.format("Achievements (%d)", total or 0)
    or string.format("Achievements (%d of %d)", #list, total or 0))

  -- list
  local cur
  for _, it in ipairs(list) do if it.key == db.achSel then cur = it end end
  cur = cur or list[1]
  if cur and NS.db then NS.db.achSel = cur.key end
  for i = 1, math.max(#list, #listRows) do
    local it, r = list[i], listRows[i]
    if it then
      r = GetListRow(i)
      r.itemKey = it.key
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", listScroll.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
      SetIcon(r.icon, it)
      r.text:SetText(it.name)
      r.text:SetTextColor(NS.Color(it == cur and "liOn" or (it.done and "listInk" or "listSoft")))
      r.pts:SetText(it.ptsShort)
      local st, col = StatusText(it)
      r.sub:SetText(it.done and ("Earned" .. (it.when and (" " .. it.when) or "")) or st)
      r.sub:SetTextColor(NS.Color(col))
      r.bar:SetProgress(it.cur, it.need, "")
      if it == cur then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      r:Show()
    elseif r then
      r:Hide() r.itemKey = nil
    end
  end
  listScroll:SetContentHeight(math.max(1, #list * ROW_H))
  if #list == 0 then
    listEmpty:SetText(filter == "done" and "Nothing earned here yet." or (filter == "todo" and "All earned." or "No achievements."))
    listEmpty:Show()
  else listEmpty:Hide() end
  RefreshDetail(cur)

  if hooks.badge then
    if sel and sel.game then
      local g = ACH.ReadGame()
      hooks.badge("Done " .. g.done .. "/" .. g.total)
    else
      local t = ACH.Totals()
      hooks.badge("Earned " .. t.earned .. "/" .. t.count)
    end
  end
  P._list, P._sel, P._cur, P._mode = list, sel, cur, mode
end

local function Schedule()
  if pending then return end
  pending = true
  C_Timer.After(0.25, function()
    pending = false
    if onShowing then P.Refresh() end
  end)
end

-- the Journals tab calls this when the section shows/hides
function P.SetActive(on)
  onShowing = on and true or false
  if NS.Ach then
    NS.Ach.onChange = on and Schedule or nil
    if on then NS.Ach.InvalidateGame() end
  end
  if page then
    if on then page:Show() P.Refresh() else SetMenuOpen(false) page:Hide() end
  end
end

---------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------
function P.Build(parent, opts)
  hooks = opts or {}
  local m = NS.theme.m
  page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints(parent)
  local pad = m.pagePad
  local innerW = m.pageW - pad * 2
  local baseLevel = page.GetFrameLevel and page:GetFrameLevel() or 1

  bar = CreateFrame("Frame", nil, page)
  bar:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -pad)
  bar:SetSize(innerW, 28)
  if bar.SetFrameLevel then bar:SetFrameLevel(baseLevel + 20) end

  local DROP_W = 230
  dropTextW = DROP_W - 73
  drop = CreateFrame("Button", nil, bar)
  drop:SetSize(DROP_W, 26)
  drop:SetPoint("LEFT", bar, "LEFT", 0, 0)
  local dbg = drop:CreateTexture(nil, "BACKGROUND")
  dbg:SetAllPoints(drop)
  dbg:SetColorTexture(0.02, 0.02, 0.02, 0.92)
  drop.border = UI.NineSlice(drop, "pane", 4, "BORDER", 1)
  drop.text = OneLine(UI.Text(drop, "OVERLAY", 13, "gold", "LEFT"), 16)
  drop.text:SetPoint("LEFT", drop, "LEFT", 9, 0)
  drop.text:SetPoint("RIGHT", drop, "RIGHT", -64, 0)
  drop.small = OneLine(UI.Text(drop, "OVERLAY", 11, "listSoft", "RIGHT"), 14)
  drop.small:SetPoint("RIGHT", drop, "RIGHT", -24, 0)
  drop.small:SetWidth(38)
  drop.arrow = drop:CreateTexture(nil, "OVERLAY")
  drop.arrow:SetSize(16, 16)
  drop.arrow:SetPoint("RIGHT", drop, "RIGHT", -5, 0)
  NS.OnSkin(function() NS.SetPiece(drop.arrow, "sb_dn") end)
  drop:SetScript("OnClick", function()
    if menu:IsShown() then SetMenuOpen(false) else SetMenuOpen(true) P.Refresh() end
  end)

  local MENU_W = DROP_W + 40
  menuTextW = (MENU_W - 8) - m.sbWidth - (m.rowPad + MENU_INDENT) - (m.rowPad + 44)
  menu = UI.Panel(page, MENU_W, 26 + MENU_MAX * MENU_H + 8)
  menu:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -2)
  if menu.SetFrameLevel then menu:SetFrameLevel(baseLevel + 60) end
  if menu.EnableMouse then menu:EnableMouse(true) end
  menuHead = OneLine(UI.Text(menu, "OVERLAY", 11, "listHead", "LEFT"), 14)
  menuHead:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -8)
  menuHead:SetPoint("RIGHT", menu, "RIGHT", -10, 0)
  menuScroll = UI.Scroll(menu, MENU_W - 8, MENU_MAX * MENU_H)
  menuScroll.frame:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -26)
  menu:Hide()
  page:SetScript("OnHide", function() SetMenuOpen(false) end)

  local function Filter(id) return function() if NS.db then NS.db.achFilter = id NS.db.achSel = nil end P.Refresh() end end
  fAll = UI.Pill(bar, "All")
  fAll:SetPoint("LEFT", drop, "RIGHT", 10, 0)
  fAll:SetScript("OnClick", Filter("all"))
  fDone = UI.Pill(bar, "Earned")
  fDone:SetPoint("LEFT", fAll, "RIGHT", m.pillGap, 0)
  fDone:SetScript("OnClick", Filter("done"))
  fTodo = UI.Pill(bar, "Not yet")
  fTodo:SetPoint("LEFT", fDone, "RIGHT", m.pillGap, 0)
  fTodo:SetScript("OnClick", Filter("todo"))

  local headY = pad + 36
  title = OneLine(UI.Text(page, "OVERLAY", 18, "gold", "LEFT"), 22)
  title:SetPoint("TOPLEFT", page, "TOPLEFT", pad + 2, -headY)
  title:SetPoint("RIGHT", page, "RIGHT", -pad - 2, 0)
  meta = OneLine(UI.Text(page, "OVERLAY", 12, "inkSoft", "LEFT"), 15)
  meta:SetPoint("TOPLEFT", page, "TOPLEFT", pad + 2, -(headY + 25))
  meta:SetPoint("RIGHT", page, "RIGHT", -pad - 2, 0)

  local splitY = headY + 48
  local splitH = m.sectionPageH - splitY - pad
  local LIST_W = 300
  local lp = UI.Panel(page, LIST_W, splitH)
  lp:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -splitY)
  listHead = OneLine(UI.Text(lp, "OVERLAY", 12, "listHead", "LEFT"), 15)
  listHead:SetPoint("TOPLEFT", lp, "TOPLEFT", 10, -8)
  listHead:SetPoint("RIGHT", lp, "RIGHT", -10, 0)
  listScroll = UI.Scroll(lp, LIST_W - 8, splitH - 32)
  listScroll.frame:SetPoint("TOPLEFT", lp, "TOPLEFT", 4, -28)
  listEmpty = UI.Text(lp, "OVERLAY", 12, "listSoft", "CENTER")
  listEmpty:SetPoint("CENTER", lp, "CENTER", 0, 0)
  listEmpty:Hide()

  local dW = innerW - LIST_W - 8
  local dp = UI.Panel(page, dW, splitH)
  dp:SetPoint("TOPLEFT", page, "TOPLEFT", pad + LIST_W + 8, -splitY)
  dIcon = UI.RoundIcon(dp, 40)
  dIcon:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -10)
  dName = OneLine(UI.Text(dp, "OVERLAY", 15, "gold", "LEFT"), 18)
  dName:SetPoint("TOPLEFT", dp, "TOPLEFT", 58, -12)
  dName:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  dPts = OneLine(UI.Text(dp, "OVERLAY", 12, "listSoft", "LEFT"), 15)
  dPts:SetPoint("TOPLEFT", dp, "TOPLEFT", 58, -32)
  dPts:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  dDesc = UI.Text(dp, "OVERLAY", 12, "listInk", "LEFT")
  dDesc:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -60)
  dDesc:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  dDesc:SetHeight(32)
  if dDesc.SetJustifyV then dDesc:SetJustifyV("TOP") end
  dStatus = OneLine(UI.Text(dp, "OVERLAY", 12, "listSoft", "LEFT"), 15)
  dStatus:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -96)
  dStatus:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  dBar = UI.Bar(dp, dW - 20, 20)
  dBar:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -116)
  critHead = OneLine(UI.Text(dp, "OVERLAY", 12, "listHead", "LEFT"), 15)
  critHead:SetPoint("TOPLEFT", dp, "TOPLEFT", 10, -148)
  critHead:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  critScroll = UI.Scroll(dp, dW - 8, splitH - 168 - 30)
  critScroll.frame:SetPoint("TOPLEFT", dp, "TOPLEFT", 4, -168)
  critEmpty = UI.Text(dp, "OVERLAY", 12, "listSoft", "LEFT")
  critEmpty:SetPoint("TOPLEFT", dp, "TOPLEFT", 12, -170)
  critEmpty:SetPoint("RIGHT", dp, "RIGHT", -10, 0)
  critEmpty:Hide()
  dNote = OneLine(UI.Text(dp, "OVERLAY", 11, "listSoft", "LEFT"), 14)
  dNote:SetPoint("BOTTOMLEFT", dp, "BOTTOMLEFT", 10, 10)
  dNote:SetPoint("RIGHT", dp, "RIGHT", -10, 0)

  page:Hide()
  return page
end

function P.Widgets()
  return { page = page, drop = drop, menu = menu, menuRows = menuRows, menuScroll = menuScroll, menuHead = menuHead,
    listRows = listRows, critRows = critRows, title = title, meta = meta, listHead = listHead, listEmpty = listEmpty,
    dName = dName, dPts = dPts, dDesc = dDesc, dStatus = dStatus, dBar = dBar, critHead = critHead,
    critEmpty = critEmpty, dNote = dNote, fAll = fAll, fDone = fDone, fTodo = fTodo, dIcon = dIcon }
end
