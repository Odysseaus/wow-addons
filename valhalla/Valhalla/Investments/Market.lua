--------------------------------------------------------------------------------
-- Investments > AH Market (v0.4.0): what your scans at the Auction House saw (Scan.lua), as four views:
-- Top 10 (rising and falling over 7 days), My items (bags and bank: vendor or AH), History (one item's
-- lowest price over a day or a week), Scan results (every item of the last full scan), Craft (v0.4.1: crafts per
-- profession by profit, Craft.lua; v0.4.1.1: all the priced ones, paged, a profession dropdown, Harvest, Total).
-- v0.4.1.1: Top 10 counts the hours with a full scan (history keeps one point an hour), says when the next counts.
-- Every item is an item cell (Views.lua): its icon, name and the game's tooltip, with AH lines under it.
-- My items and Scan results page (v0.4.0.1): as many rows as the window fits (6-20), page buttons under them.
-- Each view is built once and listed before it's built; a resize lays out only its own rows (v0.4.0.2).
-- Prices are the raw lowest buyout per unit (the 1c-dump filter is a setting, off). The AH can't be open
-- while this window is: scanning is on Valhalla's list beside the Auction House.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local V, T = I.Views, I.Tabs
local M = {}
I.Market = M

M.SUBS = {
	{ key = "top", label = L["Top 10"] },
	{ key = "mine", label = L["My items"] },
	{ key = "history", label = L["History"] },
	{ key = "results", label = L["Scan results"] },
	{ key = "craft", label = L["Craft"] },
}
M.TOP = 10
M.ROWS = 12   -- (Top 10's columns; My items and Scan results fit their rows to the window: M.FitRows)
M.ROW_H, M.MIN_ROWS, M.MAX_ROWS = 25, 6, 20
M.BELOW = 52  -- (under the rows: the page buttons, then the totals or the count line)
M.SPARK = 8
M.SORTS = { { "name", L["Name"] }, { "min", L["Lowest"] }, { "units", L["Units"] }, { "auctions", L["Auctions"] }, { "change", L["7-day change"] } }
M.RANGES = { { "day", L["1 day"] }, { "week", L["7 days"] } }

local GOLD, GREY = T.GOLD, { 0.6, 0.6, 0.6 }
local GREEN, RED = { 0.3, 0.9, 0.3 }, { 1, 0.45, 0.3 }
local function S() return I.Scan end
local function Now() return time and time() or 0 end
local Text = function(...) return V.Text(...) end

-- the house shown: the one chosen, else the last one visited, else any with data
function M.House()
	local houses = S().HouseNames()
	local want = M.house or I.realm.ahLast
	for _, h in ipairs(houses) do if h == want then return h, houses end end
	return houses[1] or want or "?", houses
end

-- under every item's tooltip: what the AH said
function M.Lines(id)
	local house = M.House()
	local low, c, dumped = S().Lowest(house, id)
	local out = {}
	if not c then
		out[1] = L["Valhalla AH (%s): not seen in your scans."]:format(house)
	elseif not low then
		out[1] = L["Valhalla AH (%s): none listed (%s)."]:format(house, S().Age(c.t))
	else
		out[1] = L["Valhalla AH (%s): lowest %s each"]:format(house, S().Money(low)) .. (dumped and L[" (a dump ignored)"] or "")
		out[2] = c.quick and L["%d units listed, quick scan %s"]:format(c.units, S().Age(c.t))
			or L["%d units in %d auctions, full scan %s"]:format(c.units, c.auctions or 0, S().Age(c.t))
	end
	return out
end

-- one item's change over 7 days (the two halves of the window from its first point)
-- a search box's shift-click (v0.4.2.1, as the game's own search boxes): the item's name, in place of what was typed
function M.TakeName(box, link)
	local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
	if not name or name == "" then return false end
	box:SetText(name)
	if box.SetCursorPosition then box:SetCursorPosition(#name) end
	return true
end

function M.Change(house, id)
	local pts = {}
	local from = Now() - 7 * 86400
	for _, p in ipairs(S().Points(house, id)) do if not p.quick and p.t >= from and p.min > 0 then pts[#pts + 1] = p end end
	if #pts < 3 then return nil end
	local mid = (pts[1].t + Now()) / 2
	local a, b = {}, {}
	for _, p in ipairs(pts) do if p.t < mid then a[#a + 1] = p.min else b[#b + 1] = p.min end end
	if #a == 0 or #b == 0 then return nil end
	local ma, mb = S().Median(a), S().Median(b)
	return (mb - ma) / ma
end

local function Pct(x)
	if not x then return "-" end
	return ("%s%d%%"):format(x > 0 and "+" or "", math.floor(x * 100 + (x > 0 and 0.5 or -0.5)))
end

-- a sparkline: the item's last points (lowest price), as small bars
local function Spark(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(M.SPARK * 5, 16)
	f.bars = {}
	for i = 1, M.SPARK do
		local b = f:CreateTexture(nil, "ARTWORK")
		b:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
		b:SetWidth(4)
		b:SetPoint("BOTTOMLEFT", (i - 1) * 5, 0)
		f.bars[i] = b
	end
	function f.Set(values)
		local max = 0
		for _, v in ipairs(values) do if v > max then max = v end end
		local first = #values - M.SPARK
		for i, b in ipairs(f.bars) do
			local v = values[first + i]
			if v and max > 0 then b:SetHeight(math.max(1, 16 * v / max)) b:Show() else b:Hide() end
		end
	end
	return f
end

local function Column(parent, text, x, w, justify)
	local fs = Text(parent, 11)
	fs:SetPoint("LEFT", x, 0)
	fs:SetWidth(w)
	fs:SetJustifyH(justify or "RIGHT")
	fs:SetText(text or "")
	return fs
end

--------------------------------------------------------------------------------
-- Pages (v0.4.0.1): a list view's rows fit its height, and page buttons go through all of it
--------------------------------------------------------------------------------

-- the rows that fit a view h high whose rows start top px down
function M.FitRows(h, top)
	local n = math.floor(((h or 0) - top - M.BELOW) / M.ROW_H)
	return math.max(M.MIN_ROWS, math.min(M.MAX_ROWS, n))
end

-- f.list, f.offset (always a whole page), f.per rows; newRow(i) makes row i when the view first needs it.
-- (v0.4.0.2) No size is asked while the view is built: in the game, asking a new frame its size lays it out
-- there and then and fires OnSizeChanged. And a resize redraws only this view's own list, never the page.
local function Paged(f, page, top, newRow)
	local key = f.view
	f.offset, f.rows, f.per = 0, {}, nil
	-- the rows for a view h high (no h: as it is, 12 at first)
	function f.Fit(h)
		local per = h and M.FitRows(h, top) or f.per or M.ROWS
		for i = #f.rows + 1, per do f.rows[i] = newRow(i) end
		if per == f.per then return false end
		f.per = per
		f.offset = math.floor(f.offset / per) * per   -- (the page with the first item shown on it)
		return true
	end
	function f.Pages()
		local n = #(f.list or {})
		return math.max(1, math.ceil(n / f.per)), math.floor(f.offset / f.per) + 1, n
	end
	-- a list that shrank: back onto its last page
	function f.Clamp()
		local pages = f.Pages()
		f.offset = math.max(0, math.min(f.offset, (pages - 1) * f.per))
	end
	-- this view's list drawn again (the same list; S.shown: what a quick scan asks about)
	function f.Redraw()
		S().shown = f.Refresh(true) or {}
	end
	function f.Page(k)
		local pages, cur = f.Pages()
		k = math.max(1, math.min(pages, k))
		if k == cur then return end
		f.offset = (k - 1) * f.per
		f.Redraw()
	end
	-- (v0.4.2.1: the pager only, no wheel: one page built at a time)
	local p = V.Pager(f, function(k)
		local pages, cur = f.Pages()
		f.Page(k == "first" and 1 or k == "prev" and cur - 1 or k == "next" and cur + 1 or pages)
	end)
	p:SetPoint("BOTTOMLEFT", 8, 26)
	f.pager = p
	function f.UpdatePager()
		local pages, cur, n = f.Pages()
		p:SetShown(n > f.per)
		p.Set(cur, pages, L["Page %d of %d · items %d-%d of %d"]:format(cur, pages, math.min(n, f.offset + 1), math.min(n, f.offset + f.per), n))
	end
	f:SetScript("OnSizeChanged", function(self, _, h)
		if f.building or f.fitting or page.current ~= key or not f:IsShown() then return end
		f.fitting = true
		local ok, changed = pcall(f.Fit, h or self:GetHeight())
		if ok and changed then ok, changed = pcall(f.Redraw) end
		f.fitting = nil
		if not ok then error(changed, 0) end
	end)
	f.Fit()
end

--------------------------------------------------------------------------------
-- Top 10
--------------------------------------------------------------------------------

-- (v0.4.2.3) the filter: All | Crafted | Harvested, a profession, and (one profession picked) its level bracket.
-- The levels: Data/Forever/TopSkills.lua (Wowhead Forever; an item with no known level is hidden from a bracket and
-- counted). Mining is Harvested only. Kept in the settings (topKind, topProf, topBracket). Filter first, then the top 10.
M.TOP_KINDS = { { "all", L["All"] }, { "craft", L["Crafted"] }, { "harvest", L["Harvested"] } }
M.TOP_BRACKETS = { { "all", L["All levels"] }, { "1", "1-150", 1, 150 }, { "151", "151-225", 151, 225 }, { "226", "226-300", 226, 300 }, { "301", "301-375+", 301, math.huge } }
M.TOP_CRAFT = { 171, 164, 333, 202, 165, 197, 185, 129 }   -- (Mining: Harvested only)
M.TOP_HARVEST = { 182, 186, 393, 356 }
-- the item's skill for a profession: a number, false (made or gathered by it, skill unknown), nil (not its)
function M.TopSkill(kind, prof, id)
	local C = I.Craft
	local map = C and C.TopMap and C.TopMap(kind)
	local t = map and map[prof]
	if not t then return nil end
	return t[id]
end
function M.TopFilter(list, kind, prof, bracket)
	if kind ~= "craft" and kind ~= "harvest" then return list, 0 end
	local out, hidden = {}, 0
	local profs = {}
	if prof then profs[1] = prof else for _, p in ipairs(kind == "craft" and M.TOP_CRAFT or M.TOP_HARVEST) do profs[#profs + 1] = p end end
	local b
	for _, x in ipairs(M.TOP_BRACKETS) do if x[1] == bracket then b = x end end
	for _, e in ipairs(list) do
		local best, member
		for _, p in ipairs(profs) do
			local sk = M.TopSkill(kind, p, e.id)
			if sk ~= nil then member = true if sk and (not best or sk < best) then best = sk end end
		end
		if member then
			if not prof or not b or b[1] == "all" then out[#out + 1] = e
			elseif not best then hidden = hidden + 1
			elseif best >= b[3] and best <= b[4] then out[#out + 1] = e end
		end
	end
	return out, hidden
end

M.TOP_COLS_W = 660   -- (Rising and Falling: two columns of 330)
-- the saved filter, made sane: (kind, profession or nil, bracket)
function M.TopState()
	local kind = I.S.topKind
	if kind ~= "craft" and kind ~= "harvest" then kind = "all" end
	local prof = I.S.topProf
	local okProf = false
	if kind ~= "all" then for _, p in ipairs(kind == "craft" and M.TOP_CRAFT or M.TOP_HARVEST) do if p == prof then okProf = true end end end
	prof = okProf and prof or nil
	local bracket = "all"
	if prof then for _, x in ipairs(M.TOP_BRACKETS) do if x[1] == I.S.topBracket then bracket = x[1] end end end
	return kind, prof, bracket
end

local function DropMenu(f, w, n, onPick)
	local drop = V.Button(f, "", w, 20)
	local menu = CreateFrame("Frame", nil, drop, "BackdropTemplate")
	menu:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(w)
	menu:SetFrameStrata("DIALOG")
	if ns.Style then ns.Style.Dropdown(drop, menu, w, 20) else T.Skin(menu, 0.98) end
	menu:EnableMouse(true)
	menu.items = {}
	for i = 1, n do
		local it = V.Button(menu, "", w - 8, 20, function(self) menu:Hide() onPick(self.value) end, "item")
		it:SetPoint("TOPLEFT", 4, -10 - (i - 1) * 22)   -- (inside the menu art: its edge and shadow take about 10 above, 20 below)
		it:Hide()
		menu.items[i] = it
	end
	menu:Hide()
	drop.menu = menu
	function drop.Fill(entries, cur)
		for i, it in ipairs(menu.items) do
			local e = entries[i]
			it.value = e and e[1]
			if e then it.text:SetText((e[1] == cur and "> " or "") .. e[2]) it:Show() else it:Hide() end
		end
		menu:SetHeight(10 + math.min(#entries, n) * 22 + 20)
	end
	drop:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else drop.Open() end end)
	f:HookScript("OnHide", function() menu:Hide() end)
	return drop
end

local function BuildTop(f, page)
	local TOPY = -34
	local C = I.Craft
	-- the filter row: All | Crafted | Harvested, a profession, a level
	f.kinds = {}
	for k, kd in ipairs(M.TOP_KINDS) do
		local b = V.Button(f, kd[2], 76, 20, function() I.S.topKind = kd[1] I.S.topProf = 0 I.S.topBracket = "all" f.Redraw() end)
		b:SetPoint("TOPLEFT", 8 + (k - 1) * 80, -6)
		b.kind = kd[1]
		f.kinds[k] = b
	end
	local function ProfName(p) return C and C.SKILL and C.SKILL[p] or tostring(p) end
	local function ProfEntries()
		local out = { { false, L["Any profession"] } }
		local mine = C and C.Mine and C.Mine() or {}
		local list = {}
		for _, p in ipairs(I.S.topKind == "harvest" and M.TOP_HARVEST or M.TOP_CRAFT) do list[#list + 1] = p end
		table.sort(list, function(a, b) if (mine[a] and 1 or 0) ~= (mine[b] and 1 or 0) then return mine[a] and true or false end return ProfName(a) < ProfName(b) end)
		for _, p in ipairs(list) do out[#out + 1] = { p, (mine[p] and "|cffffd100*|r " or "") .. ProfName(p) } end
		return out
	end
	f.prof = DropMenu(f, 190, 10, function(v) I.S.topProf = v or 0 I.S.topBracket = "all" f.Redraw() end)
	f.prof:SetPoint("TOPLEFT", 252, -6)
	function f.prof.Open() f.prof.Fill(ProfEntries(), select(2, M.TopState()) or false) f.prof.menu:Show() end
	-- the level: right of the columns, so its menu opens over no prices (columns end at M.TOP_COLS_W)
	f.levelTitle = Text(f, 12)
	f.levelTitle:SetPoint("TOPLEFT", M.TOP_COLS_W + 8, -9)
	f.levelTitle:SetText(L["Level:"])
	f.level = DropMenu(f, 130, 5, function(v) I.S.topBracket = v f.Redraw() end)
	f.level:SetPoint("TOPLEFT", M.TOP_COLS_W + 50, -6)
	function f.level.Open() f.level.Fill(M.TOP_BRACKETS, I.S.topBracket or "all") f.level.menu:Show() end
	f.empty = Text(f, 12, GREY)
	f.empty:SetPoint("TOPLEFT", 8, TOPY - 4)
	f.empty:SetPoint("RIGHT", f, "LEFT", M.TOP_COLS_W - 8, 0)   -- (left of the Level dropdown and its menu)
	f.empty:SetJustifyH("LEFT")
	f.note = Text(f, 11, GREY)
	f.note:SetPoint("TOPLEFT", 8, TOPY - 30 - M.TOP * 26 - 6)
	f.note:SetJustifyH("LEFT")
	f.cols = {}
	for c, title in ipairs({ L["Rising"], L["Falling"] }) do
		local col = CreateFrame("Frame", nil, f)
		col:SetPoint("TOPLEFT", (c - 1) * 330 + 4, TOPY)
		col:SetSize(320, 30 + M.TOP * 26)
		col.title = Text(col, 13, c == 1 and GREEN or RED)
		col.title:SetPoint("TOPLEFT", 4, 0)
		col.title:SetText(title)
		col.rows = {}
		for i = 1, M.TOP do
			local r = CreateFrame("Frame", nil, col)
			r:SetSize(320, 24)
			r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 26)
			r.cell = V.ItemCell(r, 160)
			r.cell:SetPoint("LEFT", 2, 0)
			r.cell.onClick = function(id) M.ShowHistory(page, id) end
			r.change = Column(r, "", 164, 46)
			r.price = Column(r, "", 212, 64)
			r.spark = Spark(r)
			r.spark:SetPoint("LEFT", 280, -2)
			r:Hide()
			col.rows[i] = r
		end
		f.cols[c] = col
	end
	function f.Redraw() f.Refresh() end
	function f.Refresh()
		local kind, prof, bracket = M.TopState()
		for _, b in ipairs(f.kinds) do T.Skin(b, 0.9, b.kind == kind and GOLD or T.BRONZE) end
		f.prof:SetShown(kind ~= "all")
		f.prof.text:SetText(prof and ProfName(prof) or L["Any profession"])
		f.levelTitle:SetShown(prof ~= nil) f.level:SetShown(prof ~= nil)
		local bl for _, x in ipairs(M.TOP_BRACKETS) do if x[1] == bracket then bl = x[2] end end
		f.level.text:SetText(bl or L["All levels"])
		local house = M.House()
		local rising, falling, fulls, nextAt = S().TrendingAll(house)
		local hr, hf
		rising, hr = M.TopFilter(rising, kind, prof, bracket)
		falling, hf = M.TopFilter(falling, kind, prof, bracket)
		local shown = {}
		local any = fulls >= 3 and (#rising > 0 or #falling > 0)
		f.empty:SetShown(not any)
		local when = (not nextAt or nextAt <= Now()) and L["now"] or (date and date("%H:%M", nextAt) or tostring(nextAt))
		local what = kind == "all" and "" or ((prof and ProfName(prof) or (kind == "craft" and L["crafted"] or L["harvested"])) .. (bracket ~= "all" and (" (" .. bl .. ")") or "") .. " ")
		if fulls < 3 then
			f.empty:SetText(L["Top 10 needs full scans in 3 different hours within 7 days (you have %d). History keeps one point an hour, so two scans in the same hour count once; your next full scan counts from %s. Scan at the Auction House: the Scan button is on Valhalla's list beside it."]:format(fulls, when))
		elseif kind == "all" then
			f.empty:SetText(L["No price moved in your scans of the last 7 days (full scans in %d different hours). Your next full scan counts from %s."]:format(fulls, when))
		else
			f.empty:SetText(L["No %sitem moved in your scans of the last 7 days (full scans in %d different hours). Your next full scan counts from %s."]:format(what, fulls, when))
		end
		local hidden = (hr or 0) + (hf or 0)
		f.note:SetShown(hidden > 0)
		f.note:SetText(L["%d %s items with no known skill level are hidden from this level."]:format(hidden, prof and ProfName(prof) or ""))
		if not any then f.note:ClearAllPoints() f.note:SetPoint("TOPLEFT", 8, TOPY - 50)
		else f.note:ClearAllPoints() f.note:SetPoint("TOPLEFT", 8, TOPY - 30 - M.TOP * 26 - 6) end
		f.nextAt = nextAt
		for c, list in ipairs({ rising, falling }) do
			local col = f.cols[c]
			col:SetShown(any)
			for i, r in ipairs(col.rows) do
				local e = list[i]
				if e and any then
					r.cell:SetItem(e.id, M.Lines)
					r.change:SetText(Pct(e.change))
					r.change:SetTextColor(unpack(e.change > 0 and GREEN or RED))
					r.price:SetText(S().Money(e.now))
					local mins = {}
					for _, p in ipairs(S().Points(house, e.id)) do if not p.quick and p.min > 0 then mins[#mins + 1] = p.min end end
					r.spark.Set(mins)
					r.id = e.id
					shown[#shown + 1] = e.id
					r:Show()
				else
					r.id = nil
					r.cell:SetItem(nil)
					r:Hide()
				end
			end
		end
		f.rising, f.falling, f.fulls = rising, falling, fulls
		return shown
	end
end

--------------------------------------------------------------------------------
-- My items: bags (+ bank), vendor vs the AH (after its cut)
--------------------------------------------------------------------------------

local function BuildMine(f, page)
	f.offset = 0
	f.scope = V.Radio(f, L["Count:"], { { false, L["Bags only"] }, { true, L["Bags + bank"] } },
		function() return I.S.mineBank and true or false end, function(v) I.S.mineBank = v f.offset = 0 f.Refresh() end)
	f.scope:SetPoint("TOPLEFT", 8, -4)
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", 4, -28)
	head:SetSize(640, 18)
	f.head = {
		Column(head, L["Item"], 2, 180, "LEFT"), Column(head, L["Have"], 190, 44), Column(head, L["Vendor"], 238, 80),
		Column(head, L["AH (after cut)"], 322, 96), Column(head, L["Best"], 422, 60), Column(head, L["Total"], 486, 100),
	}
	Paged(f, page, 48, function(i)
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(640, 24)
		r:SetPoint("TOPLEFT", 4, -48 - (i - 1) * M.ROW_H)
		r.cell = V.ItemCell(r, 184)
		r.cell:SetPoint("LEFT", 2, 0)
		r.cell.onClick = function(id) M.ShowHistory(page, id) end
		r.n = Column(r, "", 190, 44)
		r.vendor = Column(r, "", 238, 80)
		r.ah = Column(r, "", 322, 96)
		r.best = Column(r, "", 422, 60)
		r.total = Column(r, "", 486, 100)
		r:Hide()
		return r
	end)
	f.totals = Text(f, 11, GOLD)
	f.totals:SetPoint("BOTTOMLEFT", 8, 6)
	f.totals:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.totals:SetJustifyH("LEFT")
	f.empty = Text(f, 12, GREY)
	f.empty:SetPoint("TOPLEFT", 8, -52)
	function f.Refresh(keep)
		local house = M.House()
		if house ~= f.house then f.offset, f.house = 0, house end   -- (another house: page 1)
		if not keep or not f.list then f.list, f.sums = S().Mine(house, I.S.mineBank) end
		f.scope.Update()
		f.Clamp()
		local list, shown = f.list, {}
		f.empty:SetShown(#list == 0)
		f.empty:SetText(L["Nothing in your bags yet."])
		for i, r in ipairs(f.rows) do
			local e = i <= f.per and list[f.offset + i]
			if e then
				r.cell:SetItem(e.id, M.Lines)
				r.n:SetText(tostring(e.n))
				r.vendor:SetText(e.vendor and e.vendor > 0 and S().Money(e.vendor) or "-")
				r.ah:SetText(e.ah and S().Money(e.ah) or "-")
				r.best:SetText(e.best == "ah" and L["AH"] or e.best == "vendor" and L["Vendor"] or "-")
				r.best:SetTextColor(unpack(e.best == "ah" and GREEN or GOLD))
				r.total:SetText(e.total > 0 and S().Money(e.total) or "-")
				shown[#shown + 1] = e.id
				r:Show()
			else
				r.cell:SetItem(nil)
				r:Hide()
			end
		end
		local s = f.sums
		f.totals:SetText(L["All at a vendor: %s.  All on the AH (after its %d%% cut): %s.  The better of each: %s."]:format(
			S().Money(s.vendor), math.floor(S().Cut(house) * 100 + 0.5), S().Money(s.ah), S().Money(s.best)))
		f.UpdatePager()
		return shown
	end
end

--------------------------------------------------------------------------------
-- History: one item's lowest price over a day or a week (lines or bars, Settings' graph style)
--------------------------------------------------------------------------------

M.PLOT_W, M.PLOT_H = 560, 170
M.POINTS = 200   -- (7 days of hourly points: 168)

local function BuildHistory(f, page)
	f.cell = V.ItemCell(f, 300)
	f.cell:SetPoint("TOPLEFT", 8, -4)
	f.range = V.Radio(f, L["Range:"], M.RANGES, function() return M.range or "week" end, function(v) M.range = v f.Refresh() end)
	f.range:SetPoint("TOPLEFT", 8, -30)
	f.plot = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.plot:SetPoint("TOPLEFT", 60, -56)
	f.plot:SetSize(M.PLOT_W, M.PLOT_H)
	T.Skin(f.plot, 0.5)
	f.top = Text(f, 10, GREY)
	f.top:SetPoint("TOPRIGHT", f.plot, "TOPLEFT", -4, 0)
	f.bottom = Text(f, 10, GREY)
	f.bottom:SetPoint("BOTTOMRIGHT", f.plot, "BOTTOMLEFT", -4, 0)
	f.note = Text(f, 11, GREY)
	f.note:SetPoint("TOPLEFT", f.plot, "BOTTOMLEFT", 0, -6)
	f.note:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.note:SetJustifyH("LEFT")
	f.empty = Text(f, 12, GREY)
	f.empty:SetPoint("CENTER", f.plot, "CENTER")
	f.marks, f.lines = {}, {}
	local function Mark(i)
		local t = f.marks[i]
		if not t then t = f.plot:CreateTexture(nil, "OVERLAY") f.marks[i] = t end
		return t
	end
	local function Line(i)
		if not f.plot.CreateLine then return nil end
		local l = f.lines[i]
		if not l then l = f.plot:CreateLine(nil, "ARTWORK") l:SetThickness(2) l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9) f.lines[i] = l end
		return l
	end
	function f.Points()
		local house = M.House()
		local id = M.historyID
		if not id then return {}, 0, 0 end
		local span = (M.range or "week") == "day" and 86400 or 7 * 86400
		local now = Now()
		local pts = {}
		for _, p in ipairs(S().Points(house, id)) do if p.t >= now - span and p.min > 0 then pts[#pts + 1] = p end end
		while #pts > M.POINTS do table.remove(pts, 1) end
		return pts, now - span, now
	end
	function f.Refresh()
		local id = M.historyID
		f.range.Update()
		for _, t in ipairs(f.marks) do t:Hide() end
		for _, l in ipairs(f.lines) do l:Hide() end
		f.cell:SetItem(id, M.Lines)
		if not id then
			f.empty:SetText(L["Click any item in AH Market to see its history here."])
			f.empty:Show() f.top:SetText("") f.bottom:SetText("") f.note:SetText("")
			f.drawn = 0
			return {}
		end
		local pts, from, to = f.Points()
		local bars = I.S.graphStyle == "bars"
		local max = 0
		for _, p in ipairs(pts) do if p.min > max then max = p.min end end
		f.empty:SetShown(#pts == 0)
		f.empty:SetText(L["No listing of this item in your scans of this range. One point per scan, at most one an hour; no minimum."])
		f.top:SetText(max > 0 and S().Money(max) or "")
		f.bottom:SetText(max > 0 and "0" or "")
		local W, H = M.PLOT_W - 8, M.PLOT_H - 8
		local span = math.max(1, to - from)
		local prev
		f.xy = {}
		for i, p in ipairs(pts) do
			local x = 4 + W * (p.t - from) / span
			local y = 4 + (max > 0 and H * p.min / max or 0)
			if x ~= x then x = 4 end
			if y ~= y then y = 4 end
			f.xy[i] = { x, y }
			local t = Mark(i)
			t:ClearAllPoints()
			if bars then
				t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], p.quick and 0.4 or 0.9)
				t:SetSize(math.max(2, math.min(10, W / math.max(1, #pts) - 1)), math.max(1, y - 4))
				t:SetPoint("BOTTOM", f.plot, "BOTTOMLEFT", x, 4)
			else
				t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], p.quick and 0.4 or 1)   -- (quick points: hollow-looking, faint)
				t:SetSize(p.quick and 4 or 5, p.quick and 4 or 5)
				t:SetPoint("CENTER", f.plot, "BOTTOMLEFT", x, y)
				local l = prev and Line(i - 1)
				if l then
					l:SetStartPoint("BOTTOMLEFT", f.plot, prev[1], prev[2])
					l:SetEndPoint("BOTTOMLEFT", f.plot, x, y)
					l:Show()
				end
			end
			t:Show()
			prev = { x, y }
		end
		f.drawn = #pts
		local last = pts[#pts]
		if #pts == 1 then
			f.note:SetText(L["One point so far: %s (%s). Each scan adds one (one an hour at most)."]:format(S().Money(last.min), S().Age(last.t)))
		elseif last then
			local units = {}
			for _, p in ipairs(pts) do units[#units + 1] = p.units end
			f.note:SetText(L["%d points. Now %s, %d units listed. Faint points: quick scans."]:format(#pts, S().Money(last.min), last.units))
		else
			f.note:SetText("")
		end
		return { id }
	end
end

function M.ShowHistory(page, id)
	M.historyID = id
	page:ShowSub("history")
end

--------------------------------------------------------------------------------
-- Scan results: every item of the last full scan, searchable and sortable
--------------------------------------------------------------------------------

local function BuildResults(f, page)
	f.search = V.EditBox(f, 200)
	f.search:SetPoint("TOPLEFT", 8, -4)
	f.search:SetScript("OnTextChanged", function() f.offset = 0 f.dirty = true f.Refresh() end)
	f.searchHint = Text(f, 10, GREY)
	f.searchHint:SetPoint("LEFT", f.search, "RIGHT", 8, 0)
	f.searchHint:SetText(L["search by name"])
	if ns.LinkBox then ns.LinkBox(f.search, M.TakeName) end   -- (v0.4.2.1: shift-click an item: its name searched)
	f.sortButtons = {}
	local x = 8
	for _, s in ipairs(M.SORTS) do
		local b = V.Button(f, s[2], 96, 20, function()
			if M.sort == s[1] then M.desc = not M.desc else M.sort, M.desc = s[1], s[1] ~= "name" and s[1] ~= "min" end
			f.offset = 0 f.dirty = true f.Refresh()
		end)
		b:SetPoint("TOPLEFT", x, -30)
		b.key = s[1]
		f.sortButtons[#f.sortButtons + 1] = b
		x = x + 100
	end
	Paged(f, page, 56, function(i)
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(640, 24)
		r:SetPoint("TOPLEFT", 4, -56 - (i - 1) * M.ROW_H)
		r.cell = V.ItemCell(r, 220)
		r.cell:SetPoint("LEFT", 2, 0)
		r.cell.onClick = function(id) M.ShowHistory(page, id) end
		r.min = Column(r, "", 226, 96)
		r.units = Column(r, "", 326, 70)
		r.auctions = Column(r, "", 400, 70)
		r.change = Column(r, "", 474, 70)
		r:Hide()
		return r
	end)
	f.count = Text(f, 11, GREY)
	f.count:SetPoint("BOTTOMLEFT", 8, 6)
	function f.Build()
		local house = M.House()
		local m = S().Market(house)
		local q = (f.search:GetText() or ""):lower()
		local list = {}
		for id in pairs(m and m.cur or {}) do
			local c = S().Cur(house, id)
			if c and not c.quick then
				local name = V.ItemData(id)
				if q == "" or (name and name:lower():find(q, 1, true)) then
					list[#list + 1] = { id = id, name = name or ("~" .. id), min = c.min, units = c.units, auctions = c.auctions or 0 }
				end
			end
		end
		local key, desc = M.sort or "name", M.desc
		if key == "change" then for _, e in ipairs(list) do e.change = M.Change(house, e.id) or 0 end end
		table.sort(list, function(a, b)
			local x, y = a[key], b[key]
			if x == y then return a.id < b.id end
			if desc then return x > y end
			return x < y
		end)
		f.list, f.house = list, house
	end
	function f.Refresh(keep)
		local house = M.House()
		local m = S().Market(house)
		local key = ("%s:%d:%s:%s:%s"):format(house, m and #m.scans or 0, f.search:GetText() or "", tostring(M.sort), tostring(M.desc))
		if not f.list or (not keep and key ~= f.key) or f.dirty then
			if key ~= f.key then f.offset = 0 end   -- (another house, search, sort or scan: page 1)
			f.Build() f.key, f.dirty = key, nil
		end
		f.Clamp()
		local list, shown = f.list, {}
		for _, b in ipairs(f.sortButtons) do T.Skin(b, 0.9, b.key == (M.sort or "name") and GOLD or T.BRONZE) end
		for i, r in ipairs(f.rows) do
			local e = i <= f.per and list[f.offset + i]
			if e then
				r.cell:SetItem(e.id, M.Lines)
				r.min:SetText(e.min > 0 and S().Money(e.min) or L["bid only"])
				r.units:SetText(tostring(e.units))
				r.auctions:SetText(tostring(e.auctions))
				local ch = e.change or M.Change(f.house, e.id)
				r.change:SetText(Pct(ch))
				r.change:SetTextColor(unpack(not ch and GREY or ch > 0 and GREEN or ch < 0 and RED or GREY))
				shown[#shown + 1] = e.id
				r:Show()
			else
				r.cell:SetItem(nil)
				r:Hide()
			end
		end
		local sc, at = S().LastScan(f.house, "full")
		f.count:SetText(#list == 0 and L["No full scan of this house yet."]
			or L["%d items (showing %d-%d). Full scan %s, %d auctions."]:format(#list, f.offset + 1, math.min(#list, f.offset + f.per), S().Age(at), sc and sc.n or 0))
		f.UpdatePager()
		return shown
	end
end

--------------------------------------------------------------------------------
-- Craft (v0.4.1, v0.4.1.1): every priced craft of a profession by profit at the house shown (Craft.lua works it
-- out), paged like My items; a dropdown of all the professions (yours starred, first); Crafts | Harvest on the
-- gathering ones. Built once (rows made by Paged as the view first needs them); a resize lays out only its own
-- rows (Paged's guarded OnSizeChanged); nothing asks a size while building.
--------------------------------------------------------------------------------

M.PROF_MAX = 16
M.CRAFT_TOP = 116          -- (the rows start here; the status above may take two lines)
M.CRAFT_STRIPS = 18        -- (a second line under the rows: Can't price and Not listed each have one)
M.OWNED = { { "market", L["Market"] }, { "free", L["Owned free"] }, { "vendor", L["Owned: vendor"] } }
local STAR = "|cffffd100*|r"

local function BuildCraft(f, page)
	local C = I.Craft
	f.status = Text(f, 11, GREY)
	f.status:SetPoint("TOPLEFT", 8, -2)
	f.status:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.status:SetJustifyH("LEFT")
	f.status:SetJustifyV("TOP")
	f.status:SetHeight(26)
	if f.status.SetMaxLines then f.status:SetMaxLines(2) end   -- (two lines at most: never over the controls)
	-- the profession: a dropdown (v0.4.1.1; was a row of buttons)
	f.drop = V.Button(f, "", 230, 20)
	f.drop:SetPoint("TOPLEFT", 8, -30)
	local menu = CreateFrame("Frame", nil, f.drop, "BackdropTemplate")
	menu:SetPoint("TOPLEFT", f.drop, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(230)
	menu:SetFrameStrata("DIALOG")
	if ns.Style then ns.Style.Dropdown(f.drop, menu, 230, 20) else T.Skin(menu, 0.98) end   -- (v0.4.2: the look's dropdown)
	menu:EnableMouse(true)
	menu.items = {}
	for i = 1, M.PROF_MAX do
		local it = V.Button(menu, "", 222, 20, function(self)
			menu:Hide()
			M.craftProf = self.prof
			page:Refresh()
		end, "item")
		it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
		it:Hide()
		menu.items[i] = it
	end
	menu:Hide()
	f.menu = menu
	f:HookScript("OnHide", function() menu:Hide() end)   -- (another view, the window closed: the menu goes too)
	function f.FillMenu()
		local profs = f.profs or {}
		for i, it in ipairs(menu.items) do
			local p = profs[i]
			it.prof = p and p.key
			if p then
				it.text:SetText((p.key == M.craftProf and "> " or "") .. (p.mine and STAR .. " " or "") .. p.name
					.. (p.secondary and " |cff999999" .. L["(secondary)"] .. "|r" or ""))
				it:Show()
			else
				it:Hide()
			end
		end
		menu:SetHeight(8 + math.min(#profs, M.PROF_MAX) * 22)
	end
	f.drop:SetScript("OnClick", function()
		if menu:IsShown() then menu:Hide() else f.FillMenu() menu:Show() end
	end)
	-- Crafts | Harvest (Herbalism, Mining, Skinning, Fishing)
	f.modeCrafts = V.Button(f, L["Crafts"], 70, 20, function() M.craftMode = "crafts" f.offset = 0 page:Refresh() end)
	f.modeCrafts:SetPoint("TOPLEFT", 246, -30)
	f.modeHarvest = V.Button(f, L["Harvest"], 70, 20, function() M.craftMode = "harvest" f.offset = 0 page:Refresh() end)
	f.modeHarvest:SetPoint("TOPLEFT", 320, -30)
	f.owned = V.Radio(f, L["Reagents:"], M.OWNED, function() return I.S.craftOwned or "market" end,
		function(v) I.S.craftOwned = v page:Refresh() end)
	f.owned:SetPoint("TOPLEFT", 8, -54)
	-- (v0.4.2.1) the second row, Show:, its boxes in the same columns as Reagents' (measured: no label over a box)
	f.showRow = CreateFrame("Frame", nil, f)
	f.showRow:SetSize(420, 18)
	f.showRow:SetPoint("TOPLEFT", 8, -76)
	f.showTitle = Text(f.showRow, 12)
	f.showTitle:SetPoint("LEFT")
	f.showTitle:SetText(L["Show:"])
	f.known = V.Check(f.showRow, L["Known only"], function() return I.S.craftKnownOnly end, function(v) I.S.craftKnownOnly = v page:Refresh() end)
	f.bank = V.Check(f.showRow, L["Count the bank"], function() return I.S.mineBank end, function(v) I.S.mineBank = v page:Refresh() end)
	V.Grid({
		{ frame = f.owned, title = f.owned.title, boxes = f.owned.boxes },
		{ frame = f.showRow, title = f.showTitle, boxes = { f.known, f.bank } },
	})
	-- (v0.4.2.1) a name filter: this profession's crafts (or harvest) whose item's name has it; shift-click an item: its name
	f.filter = V.EditBox(f, 150)
	f.filter:SetPoint("TOPLEFT", 400, -29)
	f.filterHint = Text(f.filter, 10, GREY)
	f.filterHint:SetPoint("LEFT", 8, 0)
	f.filterHint:SetText(L["filter by name"])
	f.filterCount = Text(f, 10, GREY)
	f.filterCount:SetPoint("LEFT", f.filter, "RIGHT", 8, 0)
	f.filter:SetScript("OnTextChanged", function(box)
		f.filterHint:SetShown((box:GetText() or "") == "")
		if f.Redraw then f.Redraw() end
	end)
	if ns.LinkBox then ns.LinkBox(f.filter, M.TakeName) end
	-- the two headers (crafts, harvest)
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", 4, -96)
	head:SetSize(706, 18)
	f.head = head
	f.head.craft = {
		Column(head, L["Craft (makes)"], 2, 176, "LEFT"), Column(head, L["Cost"], 182, 72), Column(head, L["Sell at"], 258, 72),
		Column(head, L["Profit/item"], 334, 80), Column(head, L["Margin"], 418, 46), Column(head, L["Listed"], 468, 42),
		Column(head, L["Known"], 512, 38, "CENTER"), Column(head, L["Can make"], 554, 56), Column(head, L["Total"], 614, 90),
	}
	f.head.harvest = {
		Column(head, L["Item"], 2, 220, "LEFT"), Column(head, L["AH lowest"], 226, 90), Column(head, L["Listed"], 320, 60),
		Column(head, L["Vendor"], 384, 80), Column(head, L["Have"], 468, 50), Column(head, L["7-day change"], 522, 80),
	}
	Paged(f, page, M.CRAFT_TOP + M.CRAFT_STRIPS, function(i)
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(706, 24)
		r:SetPoint("TOPLEFT", 4, -M.CRAFT_TOP - (i - 1) * M.ROW_H)
		r.cell = V.ItemCell(r, 176)
		r.cell:SetPoint("LEFT", 2, 0)
		r.cell.onClick = function(id) M.ShowHistory(page, id) end
		r.Lines = function() return r.e and C.Lines(r.e, r.house) or {} end
		r.cost = Column(r, "", 182, 72)
		r.sell = Column(r, "", 258, 72)
		r.each = Column(r, "", 334, 80)
		r.margin = Column(r, "", 418, 46)
		r.listed = Column(r, "", 468, 42)
		r.known = Column(r, "", 512, 38, "CENTER")
		r.can = Column(r, "", 554, 56)
		r.total = Column(r, "", 614, 90)
		r.craftCols = { r.cost, r.sell, r.each, r.margin, r.listed, r.known, r.can, r.total }
		r.low = Column(r, "", 226, 90)
		r.hunits = Column(r, "", 320, 60)
		r.vendor = Column(r, "", 384, 80)
		r.have = Column(r, "", 468, 50)
		r.change = Column(r, "", 522, 80)
		r.harvestCols = { r.low, r.hunits, r.vendor, r.have, r.change }
		r:Hide()
		return r
	end)
	f.pager:ClearAllPoints()
	f.pager:SetPoint("BOTTOMLEFT", 8, 44)   -- (above the two strips)
	f.missing = Text(f, 11, GREY)
	f.missing:SetPoint("BOTTOMLEFT", 8, 24)
	f.missing:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.missing:SetJustifyH("LEFT")
	f.unlisted = Text(f, 11, GREY)
	f.unlisted:SetPoint("BOTTOMLEFT", 8, 6)
	f.unlisted:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.unlisted:SetJustifyH("LEFT")
	local function Names(list, field, most)
		local out, seen = {}, {}
		for _, e in ipairs(list) do
			for _, id in ipairs(field == "missing" and e.missing or { e.out }) do
				if not seen[id] then seen[id] = true out[#out + 1] = V.ItemData(id) or L["Item #%d"]:format(id) end
			end
		end
		local n = #out
		while #out > most do table.remove(out) end
		return table.concat(out, ", ") .. (n > most and L[", and %d more"]:format(n - most) or "")
	end
	local function Mode(mode)
		for _, c in ipairs(f.head.craft) do c:SetShown(mode == "crafts") end
		for _, c in ipairs(f.head.harvest) do c:SetShown(mode == "harvest") end
		for _, r in ipairs(f.rows) do
			for _, c in ipairs(r.craftCols) do c:SetShown(mode == "crafts") end
			for _, c in ipairs(r.harvestCols) do c:SetShown(mode == "harvest") end
		end
		f.owned:SetShown(mode == "crafts")
		f.known:SetShown(mode == "crafts")
	end
	-- the list shown: another list (profession, house, scan, setting) starts on page 1
	local function SetList(list, key, field)
		local q = (f.filter:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if q ~= "" then
			local all = list
			list = {}
			for _, e in ipairs(all) do
				local name = V.ItemData(e[field]) or ""
				if name:lower():find(q, 1, true) then list[#list + 1] = e end
			end
			f.filterCount:SetText(L["%d of %d"]:format(#list, #all))
		else
			f.filterCount:SetText("")
		end
		key = key .. "|" .. q
		if key ~= f.listKey then f.offset, f.listKey = 0, key end
		f.list = list
		f.Clamp()
	end
	local function Clear()
		f.list = {}
		for _, r in ipairs(f.rows) do r.e = nil r.cell:SetItem(nil) r:Hide() end
		f.missing:SetText("") f.unlisted:SetText("")
		f.UpdatePager()
	end
	local function Money(v) return v and S().Money(v) or "-" end
	local function Signed(fs, v)
		if not v then fs:SetText("-") fs:SetTextColor(unpack(GREY)) return end
		fs:SetText((v < 0 and "-" or "") .. S().Money(math.abs(v)))
		fs:SetTextColor(unpack(v >= 0 and GREEN or RED))
	end
	function f.Refresh(keep)
		local house = M.House()
		f.owned.Update() f.known.Update() f.bank.Update()
		local profs = C.Professions()
		f.profs = profs
		if #profs == 0 then
			Clear()
			f.drop.text:SetText(L["Profession"] .. (ns.Style and "" or "  v"))
			f.modeCrafts:Hide() f.modeHarvest:Hide()
			f.status:SetText(L["No recipes yet: open a profession window once (any character); Valhalla reads its whole list for every character."])
			return {}
		end
		local p
		for _, q in ipairs(profs) do if q.key == M.craftProf then p = q end end
		p = p or profs[1]
		M.craftProf = p.key
		f.drop.text:SetText((p.mine and STAR .. " " or "") .. p.name .. (ns.Style and "" or "  v"))   -- (v0.4.2: the look's arrow says it)
		if f.menu:IsShown() then f.FillMenu() end
		local gather = C.GATHER[p.key] and C.GatherInfo(p.key)
		local mode = (gather and M.craftMode == "harvest") and "harvest" or "crafts"
		f.modeCrafts:SetShown(gather and true or false) f.modeHarvest:SetShown(gather and true or false)
		T.Skin(f.modeCrafts, 0.9, mode == "crafts" and GOLD or T.BRONZE)
		T.Skin(f.modeHarvest, 0.9, mode == "harvest" and GOLD or T.BRONZE)
		Mode(mode)
		local sc, at = S().LastScan(house, "full")
		if not sc then
			Clear()
			f.status:SetText(L["No full scan of %s yet: scan at its Auction House (the Scan button is on Valhalla's list beside it)."]:format(house))
			return {}
		end
		local bank = I.S.mineBank and true or false
		local shown = {}
		if mode == "harvest" then
			local h = C.Harvest(house, p.key, bank)
			local m = S().Market(house)
			SetList(h.list, ("harvest|%s|%s|%d"):format(house, tostring(p.key), m and #m.scans or 0), "id")
			for i, r in ipairs(f.rows) do
				local e = i <= f.per and f.list[f.offset + i]
				r.e = nil
				if e then
					r.cell:SetItem(e.id, M.Lines)
					r.low:SetText(Money(e.low))
					r.hunits:SetText(e.low and tostring(e.units) or "-")
					r.vendor:SetText(e.vendor and e.vendor > 0 and S().Money(e.vendor) or "-")
					r.have:SetText(tostring(e.have))
					r.change:SetText(Pct(e.change))
					r.change:SetTextColor(unpack(not e.change and GREY or e.change > 0 and GREEN or e.change < 0 and RED or GREY))
					shown[#shown + 1] = e.id
					r:Show()
				else
					r.cell:SetItem(nil)
					r:Hide()
				end
			end
			f.missing:SetText("") f.unlisted:SetText("")
			f.status:SetText(L["%s: %d %s, %d listed at %s. AH lowest (before the cut), vendor price, what you have; full scan %s."]:format(
				p.name, #h.list, h.label:lower(), h.listed, house, S().Age(at)))
			f.UpdatePager()
			return shown
		end
		local opts = { owned = I.S.craftOwned or "market", bank = bank, knownOnly = I.S.craftKnownOnly and true or false }
		local res, done, of = C.Get(house, p.key, opts)
		if not res then
			Clear()
			f.status:SetText(L["%s: reading %d recipes... %d/%d"]:format(p.name, #p.ids, done or 0, of or #p.ids))
			return {}
		end
		SetList(res.list or res.rows, C.CacheKey(house, p.key, opts), "out")
		for i, r in ipairs(f.rows) do
			local e = i <= f.per and f.list[f.offset + i]
			r.e, r.house = e or nil, house
			if e then
				r.cell:SetItem(e.out, r.Lines)
				r.cost:SetText(S().Money(e.cost))
				r.sell:SetText(S().Money(e.sell))
				Signed(r.each, e.each)
				r.margin:SetText(e.margin and ("%d%%"):format(math.floor(e.margin * 100 + 0.5)) or "-")
				r.listed:SetText(tostring(e.listed))
				r.known:SetText(e.known and STAR or "")
				r.can:SetText(tostring(e.can))
				Signed(r.total, e.total)
				shown[#shown + 1] = e.out
				for _, part in ipairs(e.parts) do shown[#shown + 1] = part.id end
				r:Show()
			else
				r.cell:SetItem(nil)
				r:Hide()
			end
		end
		for _, e in ipairs(res.missing) do for _, id in ipairs(e.missing) do shown[#shown + 1] = id end end
		for _, e in ipairs(res.unlisted) do shown[#shown + 1] = e.out end
		f.missing:SetText(#res.missing > 0 and L["Can't price (%d): no price for %s."]:format(#res.missing, Names(res.missing, "missing", 4)) or "")
		f.unlisted:SetText(#res.unlisted > 0 and L["Not listed (%d): %s."]:format(#res.unlisted, Names(res.unlisted, "out", 4)) or "")
		local src = p.source == "live" and L["from its profession window"] or L["client data"]
		f.status:SetText(L["%s: %d recipes (%s), %d priced, by profit per craft at %s after its %d%% cut; full scan %s.%s"]:format(p.name, #p.ids, src,
			res.ranked or #f.list, house, math.floor(S().Cut(house) * 100 + 0.5), S().Age(at),
			(res.unknown > 0 and L[" %d unknown to this client."]:format(res.unknown) or "") .. (res.skipped > 0 and L[" %d skipped (enchants, bind on pickup)."]:format(res.skipped) or "")))
		f.UpdatePager()
		return shown
	end
end

local BUILD = { top = BuildTop, mine = BuildMine, history = BuildHistory, results = BuildResults, craft = BuildCraft }

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function V.BuildMarket(page)
	V.Header(page, L["AH Market"])
	page.status = Text(page, 11)
	page.status:SetPoint("TOPLEFT", 14, -36)
	page.status:SetPoint("RIGHT", page, "RIGHT", -120, 0)
	page.status:SetJustifyH("LEFT")
	page.hint = Text(page, 11, GOLD)
	page.hint:SetPoint("TOPLEFT", 14, -52)
	page.hint:SetPoint("RIGHT", page, "RIGHT", -14, 0)
	page.hint:SetJustifyH("LEFT")
	page.houseButton = V.Button(page, "", 110, 20, function()
		local cur, houses = M.House()
		for i, h in ipairs(houses) do if h == cur then M.house = houses[i % #houses + 1] break end end
		page:Refresh()
	end)
	page.houseButton:SetPoint("TOPRIGHT", -10, -8)
	page.subButtons, page.subs = {}, {}
	local x = 12
	for _, s in ipairs(M.SUBS) do
		local b = V.Button(page, s.label, 104, 22, function() if not s.soon then page:ShowSub(s.key) end end, "tab")
		if ns.Style then ns.Style.Tab(b, "top", 104, 22) end
		b:SetPoint("TOPLEFT", x, -72)
		b.key, b.soon = s.key, s.soon
		if s.soon then b:SetAlpha(0.5) b.text:SetText(s.label .. " " .. L["(soon)"]) end
		page.subButtons[#page.subButtons + 1] = b
		x = x + 108
	end
	page.current = "top"
	page.allSubs = {}
	function page:Sub(key)
		if self.subs[key] then return self.subs[key] end
		local f = CreateFrame("Frame", nil, self)
		f:SetPoint("TOPLEFT", 8, -100)
		f:SetPoint("BOTTOMRIGHT", -8, 8)
		f.view, f.building = key, true   -- (f.view: Scan results keeps its own f.key, its list cache key)
		self.subs[key] = f   -- (v0.4.0.2: registered before it's built, so a lookup while building finds this one)
		self.allSubs[#self.allSubs + 1] = f
		BUILD[key](f, self)
		f.building = nil
		f:Hide()
		return f
	end
	function page:ShowSub(key)
		if not BUILD[key] then key = "top" end
		self.current = key
		local f = self:Sub(key)
		for _, g in ipairs(self.allSubs) do if g ~= f then g:Hide() end end   -- (every view ever made, not only the listed ones)
		f:Show()
		-- fit its rows now that it's listed and shown (its own OnSizeChanged waits while this runs)
		if f.Fit and not f.fitting then
			f.fitting = true
			local ok, err = pcall(f.Fit, f:GetHeight())
			f.fitting = nil
			if not ok then error(err, 0) end
		end
		self:Refresh()
	end
	function page:Refresh(keep)   -- (keep: the same list, another page)
		local house, houses = M.House()
		local sc, at = S().LastScan(house, "full")
		self.status:SetText(L["%s Auction House. Last full scan: %s%s. %s"]:format(house, S().Age(at),
			sc and L[" (%d items)"]:format(sc.items or 0) or "", S().CooldownText()))
		self.hint:SetText(I.ahOpen and "" or L["Scan at the Auction House: the Scan button is on Valhalla's list beside it."])
		self.houseButton.text:SetText(house)
		self.houseButton:SetShown(#houses > 1)
		for _, b in ipairs(self.subButtons) do T.Skin(b, 0.9, b.key == self.current and GOLD or T.BRONZE) end
		local f = self:Sub(self.current)
		f:Show()
		S().shown = f.Refresh(keep) or {}
	end
	page:ShowSub("top")
end
