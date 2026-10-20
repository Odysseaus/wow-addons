-- Journals > Achievements (0.4.1 layout). Our own take on a challenges window:
--   top:   per-character summary bar: Dark Matter points and Legacy Points (this character), each with a progress bar
--   left:  search box + Filter control (All / Earned / Not yet) and a collapsible category tree: the game's categories
--          nested by GetCategoryInfo parent ids (Classes > Druid ...), then a "Dark Matter" section with our 6
--   right: a scrolling list of large cards (icon, name, description, points badge, earned date or progress bar);
--          clicking a card expands it inline with its criteria. Unearned cards are muted; ones another character
--          earned are muted with a small note.
-- Art: generated, photoreal Dark Matter art (Media/ach-atlas.tga, Media/ach-icons.tga via Atlas_Ach.lua, built by
-- tools/achievements/make_ach_textures.py). Without it the page falls back to the theme's own pane art and game icons.
-- Everything counts for THIS character only (wasEarnedByMe for game achievements). Stock frames only, no hooks.
local _, NS = ...
local UI = NS.UI
local P = {}
NS.AchPage = P

local page, sumPanel, slots, search, filterBtn, treePanel, treeScroll, rightPanel, title, meta, cardScroll, empty
local treeRows, cards = {}, {}
local TREE_H, LEFT_W, SUM_H, CRIT_H = 22, 208, 46, 18
local hooks = {}
local pending, onShowing = false, false
local GOLD = 10000
P.GAME_HEAD, P.DM_HEAD = "Legacy Challenges", "Dark Matter"
P.FILTERS = { "all", "done", "todo" }
P.FILTER_LABEL = { all = "Filter: All", done = "Filter: Earned", todo = "Filter: Not yet" }

local function OneLine(fs, h)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetHeight(h)
  return fs
end
local function Prefs() return NS.db or {} end
local function GoldText(c) return math.floor((c or 0) / GOLD) .. "g" end
local function EstW(text, size, fs)
  local w = #(text or "") * size * 0.52
  if fs then
    local ok, sw = pcall(fs.GetStringWidth, fs)
    if ok and type(sw) == "number" and sw > w then w = sw end
  end
  return w
end
local function Lower(s) return (s or ""):lower() end

---------------------------------------------------------------------------
-- generated art (optional)
---------------------------------------------------------------------------
local function Art() return NS.achArt end
local function SetArt(tex, key, file)
  local A = Art()
  local r = A and A.rects[key]
  if not r then return false end
  local f = file or A.file
  local W, H = A.size[f] and A.size[f][1] or 512, A.size[f] and A.size[f][2] or 512
  tex:SetTexture(A.path .. f)
  tex:SetTexCoord(r[1] / W, (r[1] + r[3]) / W, r[2] / H, (r[2] + r[4]) / H)
  return true
end
P.SetArt = SetArt

-- icon art for one achievement: key achievements get their own, the rest their category's
local ICON_BY_ID = { lvl60 = "i_summit", q250 = "i_tomes", q500 = "i_tomes", mc = "i_dragon", ony = "i_dragon", raid1 = "i_dragon",
  fishrare = "i_rarefish", deviate = "i_rarefish", eel = "i_rarefish", fireoil = "i_rarefish", zones15 = "i_spyglass",
  zones30 = "i_spyglass", gold10 = "i_coins", gold100 = "i_coins", gold1000 = "i_coins" }
local ICON_BY_CAT = { General = "i_level", Quests = "i_quests", ["Dungeons and Raids"] = "i_dungeon", Fishing = "i_fishing",
  Exploration = "i_explore", Loot = "i_loot" }
function P.IconKey(it)
  if not it.dm then return nil end
  return ICON_BY_ID[it.id] or ICON_BY_CAT[it.cat]
end

-- nine-slice of an art rect over a frame (corners keep their pixels; edges and centre stretch)
local function NineArt(owner, key, srcC, dispC, layer)
  local A = Art()
  local r = A and A.rects[key]
  if not r then return nil end
  local W, H = A.size[A.file][1], A.size[A.file][2]
  local x0, y0, x1, y1 = r[1], r[2], r[1] + r[3], r[2] + r[4]
  local xs = { x0, x0 + srcC, x1 - srcC, x1 }
  local ys = { y0, y0 + srcC, y1 - srcC, y1 }
  local parts = {}
  for row = 1, 3 do
    for col = 1, 3 do
      local t = owner:CreateTexture(nil, layer or "BACKGROUND")
      t:SetTexture(A.path .. A.file)
      t:SetTexCoord(xs[col] / W, xs[col + 1] / W, ys[row] / H, ys[row + 1] / H)
      parts[#parts + 1] = t
    end
  end
  local function P9(i, a1, f1, a2, f2, x1_, y1_, x2_, y2_)
    parts[i]:SetPoint(a1, owner, f1, x1_, y1_)
    parts[i]:SetPoint(a2, owner, f2, x2_, y2_)
  end
  local c = dispC
  P9(1, "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPLEFT", 0, 0, c, -c)
  P9(2, "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", c, 0, -c, -c)
  P9(3, "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "TOPRIGHT", -c, 0, 0, -c)
  P9(4, "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", 0, -c, c, c)
  P9(5, "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", c, -c, -c, c)
  P9(6, "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", -c, -c, 0, c)
  P9(7, "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", 0, c, c, 0)
  P9(8, "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", c, c, -c, 0)
  P9(9, "TOPLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", -c, c, 0, 0)
  function parts.SetVertexColor(_, r_, g_, b_, a_) for i = 1, 9 do parts[i]:SetVertexColor(r_, g_, b_, a_ or 1) end end
  return parts
end

-- three-slice (caps + stretched middle) of an art rect
local function ThreeArt(owner, key, srcCap, dispCap, layer)
  local A = Art()
  local r = A and A.rects[key]
  if not r then return nil end
  local W, H = A.size[A.file][1], A.size[A.file][2]
  local x0, y0, x1, y1 = r[1], r[2], r[1] + r[3], r[2] + r[4]
  local l, m, rr = owner:CreateTexture(nil, layer or "BACKGROUND"), owner:CreateTexture(nil, layer or "BACKGROUND"),
    owner:CreateTexture(nil, layer or "BACKGROUND")
  for _, t in ipairs({ l, m, rr }) do t:SetTexture(A.path .. A.file) end
  l:SetTexCoord(x0 / W, (x0 + srcCap) / W, y0 / H, y1 / H)
  m:SetTexCoord((x0 + srcCap) / W, (x1 - srcCap) / W, y0 / H, y1 / H)
  rr:SetTexCoord((x1 - srcCap) / W, x1 / W, y0 / H, y1 / H)
  l:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0) l:SetPoint("BOTTOMRIGHT", owner, "BOTTOMLEFT", dispCap, 0)
  rr:SetPoint("TOPLEFT", owner, "TOPRIGHT", -dispCap, 0) rr:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
  m:SetPoint("TOPLEFT", owner, "TOPLEFT", dispCap, 0) m:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -dispCap, 0)
  local o = { l, m, rr }
  function o.Show() for _, t in ipairs({ l, m, rr }) do t:Show() end end
  function o.Hide() for _, t in ipairs({ l, m, rr }) do t:Hide() end end
  return o
end

---------------------------------------------------------------------------
-- data model
---------------------------------------------------------------------------
local function GameItem(a)
  local ACH = NS.Ach
  local crit = {}
  for _, c in ipairs(ACH.GameCriteria(a.id)) do
    crit[#crit + 1] = { name = c.name, done = c.done, cur = c.cur, need = c.need, other = c.other,
      text = c.other and "other character" or (c.need > 1 and (c.text or (c.cur .. " / " .. c.need)) or nil) }
  end
  local cur, need
  if #crit == 1 and (crit[1].need or 0) > 1 then cur, need = crit[1].cur, crit[1].need
  elseif #crit > 0 then
    cur, need = 0, #crit
    for _, c in ipairs(crit) do if c.done then cur = cur + 1 end end
  else cur, need = a.completed and 1 or 0, 1 end
  if a.completed then cur = need end
  local lp = (a.legacy and a.legacy > 0) and a.legacy or nil
  return { key = a.key, id = a.id, name = a.name, desc = a.desc, badge = lp or a.points, legacyBadge = lp and true or false,
    pts = lp and (lp .. (lp == 1 and " Legacy Point" or " Legacy Points")) or (a.points .. " points"),
    done = a.completed, when = a.when, cur = cur, need = need, icon = a.icon, crit = crit, game = true,
    other = a.other, otherBy = a.earnedBy, reward = a.reward, catName = a.catName, catKey = a.catKey }
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
  return { key = a.key, id = a.id, name = a.name, desc = a.desc, badge = a.points, pts = a.points .. " points",
    done = e and true or false, when = e and e.when or nil, retro = e and e.retro, cur = cur, need = need,
    curText = curText, icon = a.icon, crit = out, dm = true, cat = a.cat, catName = a.cat, catKey = a.catKey }
end

-- tree entries in display order: { head } | { parent=true, key, name, open, small } | { key, name, small, depth, game|dm }
function P.Tree()
  local ACH = NS.Ach
  local mode = ACH.Mode()
  local db = Prefs()
  local open = type(db.achOpen) == "table" and db.achOpen or {}
  local out = {}
  if mode ~= "dm" then
    local g = ACH.ReadGame()
    if #(g.tree or {}) > 0 then out[#out + 1] = { head = P.GAME_HEAD } end
    for _, n in ipairs(g.tree or {}) do
      if #n.children > 0 then
        local isOpen = open[n.key] == true
        out[#out + 1] = { parent = true, key = n.key, name = n.name, open = isOpen, small = n.done .. "/" .. n.total,
          cat = n.cat, game = true, depth = 0 }
        if isOpen then
          for _, c in ipairs(n.children) do
            out[#out + 1] = { key = c.key, name = c.short or c.name, full = c.name, game = true, cat = c, small = c.done .. "/" .. #c.list,
              depth = 1, parentKey = n.key }
          end
        end
      elseif n.cat then
        out[#out + 1] = { key = n.cat.key, name = n.cat.short or n.cat.name, full = n.cat.name, game = true, cat = n.cat,
          small = n.cat.done .. "/" .. #n.cat.list, depth = 0 }
      end
    end
  end
  if mode ~= "game" then
    out[#out + 1] = { head = P.DM_HEAD }
    local t = ACH.Totals()
    for _, name in ipairs(ACH.CATS) do
      local tc = t.cats[name] or { count = 0, earned = 0 }
      out[#out + 1] = { key = "dm:" .. name, name = name, full = name, dm = true, small = tc.earned .. "/" .. tc.count, depth = 0 }
    end
  end
  return out, mode
end

-- every selectable category (whether its parent is open or not)
function P.AllCats()
  local ACH = NS.Ach
  local mode = ACH.Mode()
  local out = {}
  if mode ~= "dm" then
    for _, c in ipairs(ACH.ReadGame().cats) do
      out[#out + 1] = { key = c.key, name = c.short or c.name, full = c.name, game = true, cat = c, parentKey = c.parentId and ("n:" .. c.parentId) or nil }
    end
  end
  if mode ~= "game" then
    for _, name in ipairs(ACH.CATS) do out[#out + 1] = { key = "dm:" .. name, name = name, full = name, dm = true } end
  end
  return out, mode
end
P.Categories = P.AllCats -- 0.4.0 name

local function SourceItems(entry)
  local src = {}
  if not entry then return src end
  if entry.game then
    for _, a in ipairs(entry.cat.list) do src[#src + 1] = GameItem(a) end
  else
    for _, a in ipairs(NS.Ach.Defs()) do if a.catKey == entry.key then src[#src + 1] = DMItem(a) end end
  end
  return src
end

local function PassFilter(it, filter)
  if filter == "done" then return it.done end
  if filter == "todo" then return not it.done end
  return true
end

local function Matches(it, q)
  if q == "" then return true end
  return Lower(it.name):find(q, 1, true) or Lower(it.desc):find(q, 1, true) or Lower(it.catName):find(q, 1, true)
end

-- achievements of one category entry, filtered and searched
function P.Items(entry, filter, query)
  local q = Lower(query)
  local out, n = {}, 0
  for _, it in ipairs(SourceItems(entry)) do
    if Matches(it, q) then
      n = n + 1
      if PassFilter(it, filter) then out[#out + 1] = it end
    end
  end
  return out, n
end

-- search across every category: { items, total, perCat = { [key] = n } }
function P.SearchAll(filter, query)
  local q = Lower(query)
  local items, total, per = {}, 0, {}
  for _, c in ipairs(P.AllCats()) do
    for _, it in ipairs(SourceItems(c)) do
      if Matches(it, q) then
        total = total + 1
        per[c.key] = (per[c.key] or 0) + 1
        if c.parentKey then per[c.parentKey] = (per[c.parentKey] or 0) + 1 end
        if PassFilter(it, filter) then items[#items + 1] = it end
      end
    end
  end
  return items, total, per
end

local function StatusText(it)
  if it.done then
    local s = "Earned" .. (it.when and (" " .. it.when) or "")
    if it.retro then s = s .. " · at install" end      -- level the game confirmed when Dark Matter was installed
    return s, "good"
  end
  if it.other then return "Not yet (earned on another character)", "listSoft" end
  return "In progress: " .. (it.curText or (it.cur .. " / " .. it.need)), "listSoft"
end
P.StatusText = StatusText

---------------------------------------------------------------------------
-- summary bar
---------------------------------------------------------------------------
local function MakeSlot(parent, badgeKey)
  local s = CreateFrame("Frame", nil, parent)
  s.badge = s:CreateTexture(nil, "ARTWORK")
  s.badge:SetSize(38, 38)
  s.badge:SetPoint("LEFT", s, "LEFT", 2, 0)
  s.hasArt = SetArt(s.badge, badgeKey) and true or false
  if not s.hasArt then NS.OnSkin(function() NS.SetPiece(s.badge, "medal") end) end
  s.num = OneLine(UI.Text(s, "OVERLAY", 12, "badge", "CENTER"), 15)
  s.num:SetPoint("CENTER", s.badge, "CENTER", 0, badgeKey == "b_legacy" and -2 or 0)
  s.num:SetWidth(34)
  s.label = OneLine(UI.Text(s, "OVERLAY", 11, "listHead", "LEFT"), 14)
  s.label:SetPoint("TOPLEFT", s, "TOPLEFT", 46, -3)
  s.label:SetPoint("RIGHT", s, "RIGHT", -4, 0)
  s.barHolder = CreateFrame("Frame", nil, s)
  s.barHolder:SetPoint("TOPLEFT", s, "TOPLEFT", 46, -20)
  s.barHolder:SetPoint("RIGHT", s, "RIGHT", -4, 0)
  s.barHolder:SetHeight(20)
  s.pbar, s.pbars = false, {}
  return s
end

local function LayoutSlot(s, x, w)
  s:ClearAllPoints()
  s:SetPoint("TOPLEFT", sumPanel, "TOPLEFT", x, -4)
  s:SetSize(w, SUM_H - 8)
  if s.pbar then s.pbar:Hide() end
  s.pbar = s.pbars[w] or false
  if not s.pbar then
    local b = UI.Bar(s.barHolder, w - 50, 18)
    b:SetPoint("TOPLEFT", s.barHolder, "TOPLEFT", 0, -1)
    b.frame = CreateFrame("Frame", nil, b)
    b.frame:SetPoint("TOPLEFT", b, "TOPLEFT", -6, 4)
    b.frame:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -4)
    if b.frame.SetFrameLevel and b.GetFrameLevel then b.frame:SetFrameLevel((b:GetFrameLevel() or 1) + 2) end
    b.art = ThreeArt(b.frame, "summary", 40, 10, "OVERLAY") or false
    s.pbars[w] = b
    s.pbar = b
  end
  s.pbar:Show()
end

local function RefreshSummary(mode)
  local ACH = NS.Ach
  local g = ACH.ReadGame()
  local t = ACH.Totals()
  local innerW = sumPanel:GetWidth()
  local show = {}
  if mode ~= "game" then
    show[#show + 1] = { s = slots.dm, label = "Dark Matter points (this character)", cur = t.pointsEarned, max = t.points }
  end
  if mode ~= "dm" then
    if mode == "game" then
      show[#show + 1] = { s = slots.legacy, label = "Achievement points (this character)", cur = g.pointsDone or 0, max = g.points }
    else
      show[#show + 1] = { s = slots.legacy, label = "Legacy Points (this character)", cur = g.legacyDone, max = g.legacy }
    end
  end
  slots.dm:Hide() slots.legacy:Hide()
  local w = math.floor((innerW - 12 - (#show - 1) * 14) / math.max(1, #show))
  for i, e in ipairs(show) do
    LayoutSlot(e.s, 6 + (i - 1) * (w + 14), w)
    e.s.label:SetText(e.label)
    e.s.num:SetText(tostring(e.cur))
    e.s.pbar:SetProgress(e.cur, math.max(1, e.max), e.cur .. " / " .. e.max)
    e.s.cur, e.s.max = e.cur, e.max
    e.s:Show()
  end
  P._summary = show
end

---------------------------------------------------------------------------
-- tree
---------------------------------------------------------------------------
local function GetTreeRow(i)
  local r = treeRows[i]
  if r then return r end
  local w = treeScroll.w - NS.theme.m.sbWidth
  r = CreateFrame("Button", nil, treeScroll.content)
  r:SetSize(w, TREE_H)
  r.bgN = ThreeArt(r, "row_n", 14, 8, "BACKGROUND") or false
  r.bgS = ThreeArt(r, "row_s", 14, 8, "BACKGROUND") or false
  r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.sel:SetAllPoints(r)
  r.sel:Hide()
  r.toggle = r:CreateTexture(nil, "OVERLAY")
  r.toggle:SetSize(14, 14)
  r.toggle:SetPoint("LEFT", r, "LEFT", 4, 0)
  r.text = OneLine(UI.Text(r, "OVERLAY", 12, "listInk", "LEFT"), 15)
  r.small = OneLine(UI.Text(r, "OVERLAY", 11, "listSoft", "RIGHT"), 14)
  r.small:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.small:SetWidth(32)
  r:SetScript("OnClick", function(self)
    local db = NS.db
    if not db or self.isHeader then return end
    if P._searching then
      -- while searching, a category narrows the results to it (click again for every match)
      local k = self.isParent and self.ownKey or self.catKey
      if type(k) == "string" then db.achSearchCat = (db.achSearchCat ~= k) and k or nil db.achCard = nil end
    elseif self.isParent then
      db.achOpen = type(db.achOpen) == "table" and db.achOpen or {}
      db.achOpen[self.nodeKey] = db.achOpen[self.nodeKey] ~= true -- explicit true/false: nil = never toggled
      if type(self.ownKey) == "string" then db.achCat = self.ownKey db.achCard = nil end
    elseif type(self.catKey) == "string" then
      db.achCat = self.catKey
      db.achCard = nil
    end
    P.Refresh()
  end)
  treeRows[i] = r
  return r
end

local function RefreshTree(items, selKey, searching, per)
  local rowW = treeScroll.w - NS.theme.m.sbWidth
  local shown = 0
  for i = 1, math.max(#items, #treeRows) do
    local it, r = items[i], treeRows[i]
    if it then
      r = GetTreeRow(i)
      shown = shown + 1
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", treeScroll.content, "TOPLEFT", 0, -(i - 1) * TREE_H)
      r.text:ClearAllPoints()
      r.isHeader, r.isParent, r.catKey, r.nodeKey, r.ownKey, r.fullName = false, false, nil, nil, nil, it.full or it.name
      local on = false
      if it.head then
        r.isHeader = true
        r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.text:SetText(it.head)
        r.text:SetTextColor(NS.Color("gold"))
        r.small:SetText("")
        r.toggle:Hide()
        r:EnableMouse(false)
      else
        r:EnableMouse(true)
        local x = 22 + (it.depth or 0) * 12 -- top level lines up with the parents' text (after the +/- toggle)
        if it.parent then
          r.isParent, r.nodeKey, r.ownKey = true, it.key, it.cat and it.cat.key or nil
          NS.SetPiece(r.toggle, it.open and "coin_minus" or "coin_plus")
          r.toggle:Show()
          on = it.cat and it.cat.key == selKey
        else
          r.catKey = it.key
          r.toggle:Hide()
          on = it.key == selKey
        end
        r.text:SetPoint("LEFT", r, "LEFT", x, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -40, 0)
        r.text:SetText(it.name)
        r.textW = rowW - x - 40
        r.text:SetTextColor(NS.Color(on and "liOn" or "listInk"))
        if searching then
          local n = per[it.key] or 0
          r.small:SetText(tostring(n))
          if n == 0 then r.text:SetTextColor(NS.Color("listSoft")) end
        else
          r.small:SetText(it.small or "")
        end
      end
      if r.bgN then
        if it.head then r.bgN.Hide() r.bgS.Hide()
        elseif on then r.bgN.Hide() r.bgS.Show()
        else r.bgN.Show() r.bgS.Hide() end
        r.sel:Hide()
      elseif on then NS.SetPiece(r.sel, "hilite") r.sel:Show() else r.sel:Hide() end
      r.selected = on
      r:Show()
    elseif r then
      r:Hide()
      r.catKey, r.nodeKey = nil, nil
    end
  end
  treeScroll:SetContentHeight(math.max(1, #items * TREE_H))
  return shown
end

---------------------------------------------------------------------------
-- cards
---------------------------------------------------------------------------
local function CardWidth() return cardScroll.w - NS.theme.m.sbWidth - 2 end

local function GetCard(i)
  local c = cards[i]
  if c then return c end
  local w = CardWidth()
  c = CreateFrame("Button", nil, cardScroll.content)
  c:SetSize(w, 70)
  c.art = NineArt(c, "card", 26, 12, "BACKGROUND") or false
  if not c.art then
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints(c)
    c.border = UI.NineSlice(c, "pane", 4, "BORDER", 1)
  end
  c.icon = UI.RoundIcon(c, 40)
  c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -12)
  c.iconArt = c:CreateTexture(nil, "ARTWORK", nil, 2)
  c.iconArt:SetPoint("TOPLEFT", c.icon, "TOPLEFT", 2, -2)
  c.iconArt:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", -2, 2)
  c.badge = c:CreateTexture(nil, "ARTWORK")
  c.badge:SetSize(40, 40)
  c.badge:SetPoint("TOPRIGHT", c, "TOPRIGHT", -8, -8)
  c.badgeNum = OneLine(UI.Text(c, "OVERLAY", 13, "badge", "CENTER"), 16)
  c.badgeNum:SetPoint("CENTER", c.badge, "CENTER", 0, -1)
  c.badgeNum:SetWidth(34)
  c.name = OneLine(UI.Text(c, "OVERLAY", 14, "gold", "LEFT"), 17)
  c.name:SetPoint("TOPLEFT", c, "TOPLEFT", 62, -10)
  c.name:SetPoint("RIGHT", c, "RIGHT", -56, 0)
  c.desc = UI.Text(c, "OVERLAY", 11, "listInk", "LEFT")
  c.desc:SetPoint("TOPLEFT", c, "TOPLEFT", 62, -29)
  c.desc:SetPoint("RIGHT", c, "RIGHT", -56, 0)
  if c.desc.SetJustifyV then c.desc:SetJustifyV("TOP") end
  c.status = OneLine(UI.Text(c, "OVERLAY", 11, "listSoft", "LEFT"), 14)
  c.status:SetPoint("RIGHT", c, "RIGHT", -56, 0)
  c.bar = UI.Bar(c, w - 62 - 56, 12, true)
  c.critHead = OneLine(UI.Text(c, "OVERLAY", 11, "listHead", "LEFT"), 14)
  c.critHead:SetPoint("RIGHT", c, "RIGHT", -14, 0)
  c.note = OneLine(UI.Text(c, "OVERLAY", 10, "listSoft", "LEFT"), 13)
  c.note:SetPoint("RIGHT", c, "RIGHT", -14, 0)
  c.crit = {}
  c:SetScript("OnClick", function(self)
    if not NS.db then return end
    NS.db.achCard = (NS.db.achCard ~= self.itemKey) and self.itemKey or nil
    P.Refresh()
  end)
  cards[i] = c
  return c
end

local function GetCritRow(c, i)
  local r = c.crit[i]
  if r then return r end
  r = CreateFrame("Frame", nil, c)
  r:SetHeight(CRIT_H)
  r.text = OneLine(UI.Text(r, "OVERLAY", 11, "listInk", "LEFT"), 14)
  r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -96, 0)
  r.val = OneLine(UI.Text(r, "OVERLAY", 11, "listSoft", "RIGHT"), 14)
  r.val:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.val:SetWidth(90)
  r.line = r:CreateTexture(nil, "BACKGROUND")
  r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 4, 0)
  r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -4, 0)
  r.line:SetHeight(1)
  r.line:SetColorTexture(1, 1, 1, 0.07)
  c.crit[i] = r
  return r
end

local function DescLines(c, text)
  local w = CardWidth() - 62 - 56
  c.desc:SetText(text)
  local n = math.ceil(EstW(text, 11, c.desc) / math.max(1, w))
  return math.max(1, math.min(3, n))
end

local function NoteText(it)
  if it.dm then
    local db = NS.Ach.DB()
    return "Dark Matter (not Blizzard) · since " .. ((db and db.since or "install"):sub(1, 10))
  end
  return it.other and ("Game data · earned on " .. (it.otherBy or "another character") .. ", not this one")
    or "Game data · Legacy Challenge · this character"
end

-- lays one card out; returns its height
local function FillCard(c, it, expanded)
  c.itemKey, c.item, c.expanded = it.key, it, expanded
  local earned = it.done
  -- frame tone: earned bright, the rest muted
  if c.art then
    local v = earned and 1 or 0.62
    c.art:SetVertexColor(v, v, v * (earned and 1 or 0.95), 1)
  else
    c.bg:SetColorTexture(earned and 0.10 or 0.05, earned and 0.09 or 0.05, earned and 0.07 or 0.05, 0.92)
  end
  -- icon: our art for Dark Matter achievements, else the game's
  local key = P.IconKey(it)
  if key and SetArt(c.iconArt, key, Art() and Art().iconFile) then
    c.iconArt:Show()
    if c.iconArt.SetDesaturated then pcall(c.iconArt.SetDesaturated, c.iconArt, not earned) end
    c.iconArt:SetVertexColor(earned and 1 or 0.7, earned and 1 or 0.7, earned and 1 or 0.7, 1)
    c.icon:SetItem(nil, earned and 2 or 1, nil)
  else
    c.iconArt:Hide()
    c.icon:SetItem(nil, earned and 2 or 1, it.icon)
    if c.icon.tex and c.icon.tex.SetDesaturated then pcall(c.icon.tex.SetDesaturated, c.icon.tex, not earned) end
  end
  -- points badge: Legacy crest for game Legacy Points, the Dark Matter orb for ours
  if not SetArt(c.badge, it.legacyBadge and "b_legacy" or "b_dm") then NS.SetPiece(c.badge, "medal") end
  c.badge:SetVertexColor(earned and 1 or 0.6, earned and 1 or 0.6, earned and 1 or 0.6, 1)
  c.badgeNum:SetText(tostring(it.badge or 0))
  c.badgeNum:SetTextColor(NS.Color(earned and "badge" or "listSoft"))
  c.name:SetText(it.name)
  c.name:SetTextColor(NS.Color(earned and "gold" or "listSoft"))
  local d = (it.desc and it.desc ~= "") and it.desc or "No description from the game."
  local lines = DescLines(c, d)
  c.desc:SetHeight(lines * 13)
  c.desc:SetTextColor(NS.Color(earned and "listInk" or "listSoft"))
  local y = 29 + lines * 13 + 4
  local st, col = StatusText(it)
  c.status:ClearAllPoints()
  c.status:SetPoint("TOPLEFT", c, "TOPLEFT", 62, -y)
  c.status:SetPoint("RIGHT", c, "RIGHT", -56, 0)
  c.status:SetText(st)
  c.status:SetTextColor(NS.Color(col))
  y = y + 15
  local partial = not earned and not it.other and (it.cur or 0) > 0
  c.bar:ClearAllPoints()
  if partial then
    c.bar:SetPoint("TOPLEFT", c, "TOPLEFT", 62, -(y + 1))
    c.bar:SetProgress(it.cur, it.need, it.curText or (it.cur .. " / " .. it.need))
    c.bar:Show()
    y = y + 16
  else
    c.bar:Hide()
  end
  local h = math.max(64, y + 10)
  -- expanded: criteria + note inline
  for _, r in ipairs(c.crit) do r:Hide() end
  if expanded then
    local cy = h - 2
    local crit = it.crit or {}
    c.critHead:ClearAllPoints()
    c.critHead:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -cy)
    c.critHead:SetPoint("RIGHT", c, "RIGHT", -14, 0)
    c.critHead:SetText(#crit > 0 and string.format("Criteria (%d)", #crit)
      or (it.need > 1 and "Progress is counted as a total (no separate criteria)." or "A single goal (no separate criteria)."))
    c.critHead:Show()
    cy = cy + 18
    for i, cr in ipairs(crit) do
      local r = GetCritRow(c, i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -cy)
      r:SetPoint("RIGHT", c, "RIGHT", -10, 0)
      r.text:SetText(cr.name)
      r.text:SetTextColor(NS.Color(cr.done and "good" or (cr.other and "listSoft" or "listInk")))
      r.val:SetText(cr.text or (cr.done and "done" or "not yet"))
      r.val:SetTextColor(NS.Color(cr.done and "good" or "listSoft"))
      r:Show()
      cy = cy + CRIT_H
    end
    c.note:ClearAllPoints()
    c.note:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -(cy + 4))
    c.note:SetPoint("RIGHT", c, "RIGHT", -14, 0)
    c.note:SetText(NoteText(it))
    c.note:Show()
    h = cy + 4 + 13 + 12
  else
    c.critHead:Hide()
    c.note:Hide()
  end
  c:SetHeight(h)
  return h
end

---------------------------------------------------------------------------
-- refresh
---------------------------------------------------------------------------
function P.Refresh()
  if not page or not NS.Ach then return end
  local ACH = NS.Ach
  local db = Prefs()
  local items, mode = P.Tree()
  local all = P.AllCats()
  local query = search and search:GetText() or ""
  query = query:gsub("^%s+", ""):gsub("%s+$", "")
  local searching = query ~= ""
  local filter = (db.achFilter == "done" or db.achFilter == "todo") and db.achFilter or "all"
  filterBtn.text:SetText(P.FILTER_LABEL[filter])

  -- selection (a category; its parent opens so it is visible)
  local sel
  for _, c in ipairs(all) do if c.key == db.achCat then sel = c end end
  if not sel then sel = all[1] end
  if sel and NS.db then
    NS.db.achCat = sel.key
    if sel.parentKey and not searching then
      NS.db.achOpen = type(NS.db.achOpen) == "table" and NS.db.achOpen or {}
      if NS.db.achOpen[sel.parentKey] == nil then -- never toggled: open the selected category's parent
        NS.db.achOpen[sel.parentKey] = true
        items = P.Tree()
      end
    end
  end

  local list, total, per
  if searching then
    -- search spans every category; the tree shows match counts and every parent opens
    local _, _, perAll = P.SearchAll(filter, query)
    per = perAll
    local open = {}
    for k in pairs(per) do if k:find("^n:") then open[k] = true end end
    local saved = NS.db and NS.db.achOpen
    if NS.db then NS.db.achOpen = open end
    items = P.Tree()
    if NS.db then NS.db.achOpen = saved end
    if db.achSearchCat and per[db.achSearchCat] then
      for _, c in ipairs(all) do if c.key == db.achSearchCat then sel = c end end
      list, total = P.Items(sel, filter, query)
    else
      list, total = P.SearchAll(filter, query)
      sel = nil
    end
  else
    list, total = P.Items(sel, filter, "")
  end
  RefreshSummary(mode)
  P._treeCount = RefreshTree(items, sel and sel.key, searching, per or {})

  -- header
  if searching then
    title:SetText(sel and (sel.full or sel.name) or "Search results")
    meta:SetText(string.format("Search \"%s\" · %d %s", query, total, total == 1 and "match" or "matches")
      .. (filter ~= "all" and (" · " .. #list .. " shown") or ""))
  elseif not sel then
    title:SetText("Achievements")
    meta:SetText("No achievement data.")
  else
    title:SetText(sel.full or sel.name)
    if sel.game then
      local c = sel.cat
      local bits = { "Game", c.done .. " of " .. #c.list .. " done (this character)" }
      local other = (c.accountDone or c.done) - c.done
      if other > 0 then bits[#bits + 1] = other .. " on other characters" end
      meta:SetText(table.concat(bits, " · "))
    else
      local tc = ACH.Totals().cats[sel.name] or { earned = 0, count = 0, pointsEarned = 0, points = 0 }
      meta:SetText("Dark Matter · " .. tc.earned .. " of " .. tc.count .. " earned · " .. tc.pointsEarned .. " / " .. tc.points
        .. " points" .. (mode == "dm" and " · no game API" or ""))
    end
  end

  -- cards
  local y, openTop, openH = 0, nil, 0
  for i = 1, math.max(#list, #cards) do
    local it, c = list[i], cards[i]
    if it then
      c = GetCard(i)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", cardScroll.content, "TOPLEFT", 0, -y)
      local h = FillCard(c, it, db.achCard == it.key)
      if db.achCard == it.key then openTop, openH = y, h end
      c:Show()
      y = y + h + 6
    elseif c then
      c:Hide() c.itemKey = nil
    end
  end
  cardScroll:SetContentHeight(math.max(1, y))
  -- a new category, filter or search starts at the top; expanding a card keeps the position and brings the card into view
  local ctx = tostring(sel and sel.key) .. "|" .. filter .. "|" .. query .. "|" .. tostring(db.achSearchCat)
  if P._scrollCtx ~= ctx then
    P._scrollCtx = ctx
    cardScroll:ScrollTo(0)
  elseif openTop then
    local v, vh = cardScroll:GetScroll(), cardScroll.h or 0
    if openTop + openH > v + vh then cardScroll:ScrollTo(math.min(openTop, openTop + openH - vh))
    elseif openTop < v then cardScroll:ScrollTo(openTop) end
  end
  if #list == 0 then
    empty:SetText(searching and "No achievements match your search." or
      (filter == "done" and "Nothing earned here yet." or (filter == "todo" and "All earned." or "No achievements.")))
    empty:Show()
  else empty:Hide() end

  if hooks.badge then
    if mode == "game" or (sel and sel.game) then
      local g = ACH.ReadGame()
      hooks.badge("Done " .. g.done .. "/" .. g.total)
    else
      local t = ACH.Totals()
      hooks.badge("Earned " .. t.earned .. "/" .. t.count)
    end
  end
  P._list, P._sel, P._mode, P._items, P._searching = list, sel, mode, items, searching
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
    if on then page:Show() P.Refresh() else
      if search and search.edit and search.edit.ClearFocus then search.edit:ClearFocus() end
      page:Hide()
    end
  end
end
function P.SetMenuOpen() end -- 0.4.0 dropdown is gone (the tree replaced it); kept so older callers stay harmless

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

  -- summary bar
  sumPanel = UI.Panel(page, innerW, SUM_H)
  sumPanel:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -pad)
  slots = { dm = MakeSlot(sumPanel, "b_dm"), legacy = MakeSlot(sumPanel, "b_legacy") }

  local colY = pad + SUM_H + 8
  local colH = m.sectionPageH - colY - pad

  -- left column: search + Filter, tree
  search = UI.SearchBox(page, LEFT_W - 84, 24)
  search:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -colY)
  search.onChange = function()
    if NS.db then NS.db.achSearchCat = nil NS.db.achCard = nil end
    P.Refresh()
  end
  filterBtn = UI.Button(page, P.FILTER_LABEL.all, 80, 24, "red", 11)
  filterBtn:SetPoint("TOPLEFT", page, "TOPLEFT", pad + LEFT_W - 80, -colY)
  filterBtn:SetScript("OnClick", function()
    local db = NS.db
    if not db then return end
    local cur = db.achFilter or "all"
    local nxt = "all"
    for i, f in ipairs(P.FILTERS) do if f == cur then nxt = P.FILTERS[i % #P.FILTERS + 1] end end
    db.achFilter = nxt
    db.achCard = nil
    P.Refresh()
  end)
  treePanel = UI.Panel(page, LEFT_W, colH - 30)
  treePanel:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -(colY + 30))
  treeScroll = UI.Scroll(treePanel, LEFT_W - 8, colH - 30 - 12)
  treeScroll.frame:SetPoint("TOPLEFT", treePanel, "TOPLEFT", 4, -6)

  -- right column: header + cards
  local RW = innerW - LEFT_W - 8
  rightPanel = UI.Panel(page, RW, colH)
  rightPanel:SetPoint("TOPLEFT", page, "TOPLEFT", pad + LEFT_W + 8, -colY)
  title = OneLine(UI.Text(rightPanel, "OVERLAY", 16, "gold", "LEFT"), 20)
  title:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 12, -8)
  title:SetPoint("RIGHT", rightPanel, "RIGHT", -12, 0)
  meta = OneLine(UI.Text(rightPanel, "OVERLAY", 11, "listSoft", "LEFT"), 14)
  meta:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 12, -29)
  meta:SetPoint("RIGHT", rightPanel, "RIGHT", -12, 0)
  cardScroll = UI.Scroll(rightPanel, RW - 8, colH - 52)
  cardScroll.frame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -48)
  empty = UI.Text(rightPanel, "OVERLAY", 12, "listSoft", "CENTER")
  empty:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
  empty:Hide()

  page:Hide()
  return page
end

function P.Widgets()
  return { page = page, summary = sumPanel, slots = slots, search = search, filterBtn = filterBtn, tree = treePanel,
    treeScroll = treeScroll, treeRows = treeRows, right = rightPanel, title = title, meta = meta, cardScroll = cardScroll,
    cards = cards, empty = empty }
end
