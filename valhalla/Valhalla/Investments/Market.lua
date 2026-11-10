--------------------------------------------------------------------------------
-- Investments > AH Market (v0.4.0): what your scans at the Auction House saw (Scan.lua), as four views:
-- Top 10 (rising and falling over 7 days), My items (bags and bank: vendor or AH), History (one item's
-- lowest price over a day or a week), Scan results (every item of the last full scan). Craft: v0.4.1.
-- Every item is an item cell (Views.lua): its icon, name and the game's tooltip, with AH lines under it.
-- My items and Scan results page (v0.4.0.1): as many rows as the window fits (6-20), page buttons under them.
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
	{ key = "craft", label = L["Craft"], soon = true },
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

local function Off(b, off)
	b.off = off
	b:SetAlpha(off and 0.4 or 1)
end

-- f.list, f.offset (always a whole page), f.per rows; newRow(i) makes row i when the view first needs it
local function Paged(f, page, top, newRow)
	f.offset, f.rows, f.per = 0, {}, nil
	function f.Fit()
		local per = M.FitRows(f:GetHeight(), top)
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
	function f.Page(k)
		local pages, cur = f.Pages()
		k = math.max(1, math.min(pages, k))
		if k == cur then return end
		f.offset = (k - 1) * f.per
		page:Refresh(true)
	end
	local p = CreateFrame("Frame", nil, f)
	p:SetPoint("BOTTOMLEFT", 8, 26)
	p:SetSize(420, 20)
	p.first = V.Button(p, "<<", 30, 20, function() f.Page(1) end)
	p.first:SetPoint("LEFT", 0, 0)
	p.prev = V.Button(p, "<", 30, 20, function() local _, cur = f.Pages() f.Page(cur - 1) end)
	p.prev:SetPoint("LEFT", 34, 0)
	p.label = Text(p, 11, GREY)
	p.label:SetPoint("LEFT", 70, 0)
	p.label:SetWidth(276)
	p.next = V.Button(p, ">", 30, 20, function() local _, cur = f.Pages() f.Page(cur + 1) end)
	p.next:SetPoint("LEFT", 350, 0)
	p.last = V.Button(p, ">>", 30, 20, function() f.Page(f.Pages()) end)
	p.last:SetPoint("LEFT", 384, 0)
	f.pager = p
	function f.UpdatePager()
		local pages, cur, n = f.Pages()
		p:SetShown(n > f.per)
		p.label:SetText(L["Page %d of %d · items %d-%d of %d"]:format(cur, pages, math.min(n, f.offset + 1), math.min(n, f.offset + f.per), n))
		Off(p.first, cur <= 1) Off(p.prev, cur <= 1)
		Off(p.next, cur >= pages) Off(p.last, cur >= pages)
	end
	V.Wheel(f, function(delta) local _, cur = f.Pages() f.Page(cur - delta) end)   -- (a notch: a page)
	f:SetScript("OnSizeChanged", function() if f.Fit() and f:IsShown() then page:Refresh(true) end end)
	f.Fit()
end

--------------------------------------------------------------------------------
-- Top 10
--------------------------------------------------------------------------------

local function BuildTop(f, page)
	f.empty = Text(f, 12, GREY)
	f.empty:SetPoint("TOPLEFT", 8, -8)
	f.empty:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.empty:SetJustifyH("LEFT")
	f.cols = {}
	for c, title in ipairs({ L["Rising"], L["Falling"] }) do
		local col = CreateFrame("Frame", nil, f)
		col:SetPoint("TOPLEFT", (c - 1) * 330 + 4, -4)
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
	function f.Refresh()
		local house = M.House()
		local rising, falling, fulls = S().Trending(house, M.TOP)
		local shown = {}
		f.empty:SetShown(fulls < 3 or (#rising == 0 and #falling == 0))
		if fulls < 3 then
			f.empty:SetText(L["Top 10 needs 3 full scans in 7 days (you have %d). Scan at the Auction House: the Scan button is on Valhalla's list beside it."]:format(fulls))
		else
			f.empty:SetText(L["No price moved in your scans of the last 7 days."])
		end
		for c, list in ipairs({ rising, falling }) do
			local col = f.cols[c]
			col:SetShown(fulls >= 3)
			for i, r in ipairs(col.rows) do
				local e = list[i]
				if e and fulls >= 3 then
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

local function BuildCraft(f)
	local t = Text(f, 13, GREY)
	t:SetPoint("CENTER")
	t:SetText(L["Craft profit (Top 10 per profession): coming in v0.4.1."])
	function f.Refresh() return {} end
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
		local b = V.Button(page, s.label, 104, 22, function() if not s.soon then page:ShowSub(s.key) end end)
		b:SetPoint("TOPLEFT", x, -72)
		b.key, b.soon = s.key, s.soon
		if s.soon then b:SetAlpha(0.5) b.text:SetText(s.label .. " " .. L["(soon)"]) end
		page.subButtons[#page.subButtons + 1] = b
		x = x + 108
	end
	page.current = "top"
	function page:Sub(key)
		if self.subs[key] then return self.subs[key] end
		local f = CreateFrame("Frame", nil, self)
		f:SetPoint("TOPLEFT", 8, -100)
		f:SetPoint("BOTTOMRIGHT", -8, 8)
		BUILD[key](f, self)
		f:Hide()
		self.subs[key] = f
		return f
	end
	function page:ShowSub(key)
		if not BUILD[key] then key = "top" end
		self.current = key
		for k, f in pairs(self.subs) do if k ~= key then f:Hide() end end
		self:Sub(key):Show()
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
