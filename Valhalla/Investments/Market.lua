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
M.SPARK, M.SPARK_STEP = 8, 4   -- (v0.4.2.6: bars 3 px on a 4 px step, 32 px: room for the numbers)
M.RANGES = { { "day", L["1 day"] }, { "week", L["7 days"] } }

local GOLD, GREY = T.GOLD, { 0.6, 0.6, 0.6 }
local GREEN, RED = { 0.3, 0.9, 0.3 }, { 1, 0.45, 0.3 }
local function S() return I.Scan end
local function Now() return time and time() or 0 end
local Text = function(...) return V.Text(...) end

-- the house shown: the one chosen, else the last one visited, else any with data
function M.House()
	local houses = S().HouseNames()
	-- (v0.4.2.7) the house picked with the buttons, kept in the settings; Alliance until one is picked
	-- (M.house: one set for a moment by code, never saved)
	return M.house or I.S.marketHouse or "Alliance", houses
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
	f:SetSize(M.SPARK * M.SPARK_STEP, 16)
	f.bars = {}
	for i = 1, M.SPARK do
		local b = f:CreateTexture(nil, "ARTWORK")
		b:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)
		b:SetWidth(M.SPARK_STEP - 1)
		b:SetPoint("BOTTOMLEFT", (i - 1) * M.SPARK_STEP, 0)
		f.bars[i] = b
	end
	-- (1.2.0) the last SPARK values, scaled to the highest of those shown (not of every point kept)
	function f.Set(values)
		local max = 0
		local first = #values - M.SPARK
		for i = math.max(1, first + 1), #values do if values[i] > max then max = values[i] end end
		f.max = max
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
-- Columns and sorting (v0.4.2.6): one spec per list for its headers and its rows (the two can't drift apart);
-- every header a button that sorts by its column (again: the other way), the chosen one gold with an arrow;
-- empty values last either way, ties by the list's default column then by id; kept per list in the settings
--------------------------------------------------------------------------------

M.LIST_X, M.HEAD_H, M.HEAD_H2, M.HEAD_FONT = 4, 20, 30, 10   -- (rows and header strips start LIST_X into their view)
local function NameOf(id) local n = id and V.ItemData(id) return n and n:lower() or nil end
local function Pos(v) return v and v > 0 and v or nil end
-- { key, label, x, w, justify (RIGHT), item (the row's item cell), first (a first click's direction: desc), value(e) }
M.COLS = {
	results = {
		{ key = "name", label = L["Name"], x = 2, w = 220, justify = "LEFT", item = true, first = "asc", value = function(e) return e.name and e.name:lower() end },
		{ key = "min", label = L["Lowest"], x = 226, w = 96, first = "asc", value = function(e) return Pos(e.min) end },
		{ key = "units", label = L["Quantity"], x = 326, w = 70, value = function(e) return e.units end },
		{ key = "auctions", label = L["Auctions"], x = 400, w = 70, value = function(e) return e.auctions end },
		{ key = "change", label = L["7-day change"], x = 474, w = 90, value = function(e) return e.change end },
	},
	mine = {
		{ key = "name", label = L["Item"], x = 2, w = 184, justify = "LEFT", item = true, first = "asc", value = function(e) return NameOf(e.id) end },
		{ key = "n", label = L["Have"], x = 190, w = 44, value = function(e) return e.n end },
		{ key = "vendor", label = L["Vendor"], x = 238, w = 80, value = function(e) return Pos(e.vendor) end },
		{ key = "ah", label = L["AH (after cut)"], x = 322, w = 96, value = function(e) return e.ah end },
		{ key = "best", label = L["Best"], x = 422, w = 60, value = function(e) return e.best == "ah" and 2 or e.best == "vendor" and 1 or nil end },
		{ key = "total", label = L["Total"], x = 486, w = 100, value = function(e) return Pos(e.total) end },
	},
	craft = {
		{ key = "name", label = L["Craft (makes)"], x = 2, w = 176, justify = "LEFT", item = true, first = "asc", value = function(e) return NameOf(e.out) end },
		{ key = "cost", label = L["Cost to Make"], x = 182, w = 72, value = function(e) return e.cost end },
		{ key = "sell", label = L["Sell at"], x = 258, w = 72, value = function(e) return e.sell end },
		{ key = "each", label = L["Profit/item"], x = 334, w = 80, value = function(e) return e.each end },
		{ key = "margin", label = L["Margin"], x = 418, w = 46, value = function(e) return e.margin end },
		{ key = "listed", label = L["Listed"], x = 468, w = 42, value = function(e) return e.listed end },
		{ key = "can", label = L["Can make"], x = 554, w = 56, value = function(e) return (M.Shown(e)) end },
		{ key = "total", label = L["Total"], x = 614, w = 90, value = function(e) return select(2, M.Shown(e)) end },
	},
	-- (Crafts' columns for a gathered item, no Cost: Sell at the AH's lowest, Profit/item after the cut, Have, Total)
	harvest = {
		{ key = "name", label = L["Item"], x = 2, w = 252, justify = "LEFT", item = true, first = "asc", value = function(e) return NameOf(e.id) end },
		{ key = "sell", label = L["Sell at"], x = 258, w = 72, value = function(e) return e.low end },
		{ key = "each", label = L["Profit/item"], x = 334, w = 80, value = function(e) return e.each end },
		{ key = "listed", label = L["Listed"], x = 468, w = 42, value = function(e) return e.low and e.units or nil end },
		{ key = "have", label = L["Have"], x = 554, w = 56, value = function(e) return e.have end },
		{ key = "total", label = L["Total"], x = 614, w = 90, value = function(e) return e.total end },
	},
}
M.SORT_DEFAULT = { results = "name:asc", mine = "total:desc", craft = "each:desc", harvest = "sell:desc" }
M.SORT_SETTING = { results = "sortResults", mine = "sortMine", craft = "sortCraft", harvest = "sortHarvest" }
local function ColOf(cols, key) for _, c in ipairs(cols) do if c.key == key then return c end end end
M.ColOf = ColOf
local function ParseSort(v)
	local k, d = tostring(v or ""):match("^([%w_]+):(%a+)$")
	if d == "asc" or d == "desc" then return k, d == "desc" end
end
-- list's column and direction (desc: true); a saved column the list no longer has: its default
function M.GetSort(list)
	local key, desc = ParseSort(I.S and I.S[M.SORT_SETTING[list]])
	if not (key and ColOf(M.COLS[list], key)) then key, desc = ParseSort(M.SORT_DEFAULT[list]) end
	return key, desc
end
-- a header clicked: its column (the column's own first direction), or the other way when it's the one sorted
function M.SetSort(list, key)
	local c = ColOf(M.COLS[list], key)
	if not c then return end
	local cur, desc = M.GetSort(list)
	if cur == key then desc = not desc else desc = (c.first or "desc") == "desc" end
	I.S[M.SORT_SETTING[list]] = key .. ":" .. (desc and "desc" or "asc")
end
function M.SortTag(list) local k, d = M.GetSort(list) return k .. ":" .. (d and "desc" or "asc") end
-- rows sorted in place by list's column: empty values (nil) last either way; ties by the default column, then id
function M.SortList(rows, list)
	local key, desc = M.GetSort(list)
	return M.SortBy(rows, list, key, desc)
end
-- (1.2.0) the order for the other direction from a sorted one, without sorting again: the groups of equal values
-- in reverse, each group's own order (by id) kept; empty values last either way. The same as M.SortBy's.
function M.Flip(sorted, list, key)
	local c = ColOf(M.COLS[list], key)
	local out, vals = {}, {}
	local last = 0
	for i, e in ipairs(sorted) do vals[i] = c.value(e) if vals[i] ~= nil then last = i end end
	local i = last
	while i >= 1 do
		local j = i
		while j > 1 and vals[j - 1] == vals[i] do j = j - 1 end
		for k = j, i do out[#out + 1] = sorted[k] end
		i = j - 1
	end
	for k = last + 1, #sorted do out[#out + 1] = sorted[k] end
	return out
end
function M.SortBy(rows, list, key, desc)
	local cols = M.COLS[list]
	local c = ColOf(cols, key)
	local v = {}
	for _, e in ipairs(rows) do v[e] = c.value(e) end
	local function Cmp(x, y, down)
		if x == y then return nil end
		if x == nil then return false end
		if y == nil then return true end
		if down then return x > y end
		return x < y
	end
	table.sort(rows, function(a, b)
		local r = Cmp(v[a], v[b], desc)
		if r ~= nil then return r end
		-- (v0.4.2.7) equal values: no other column decides; a fixed hidden order, the item's ID number (then the recipe's)
		local ia, ib = a.out or a.id or 0, b.out or b.id or 0
		if ia ~= ib then return ia < ib end
		return (a.id or 0) < (b.id or 0)
	end)
	return rows
end

-- the sort arrow: the look's small scroll arrows (Profession's art), else the game's plain ones
local ARROWS = { up = { "minimal-scrollbar-small-arrow-top-c60", "Interface\\Buttons\\Arrow-Up-Up" },
	down = { "minimal-scrollbar-small-arrow-bottom-c60", "Interface\\Buttons\\Arrow-Down-Up" } }
local function Arrow(tex, dir)
	local a = ARROWS[dir]
	local atlas = ns.Style and ns.Style.Atlas and ns.Style.Atlas(a[1])
	if atlas and tex.SetAtlas then tex:SetAtlas(atlas) else tex:SetTexture(a[2]) end
	tex.dir = dir
end
-- (v0.4.2.7) the widths measured with the game's own font: a column as wide as the wider of its title (one line, or two
-- when the row's too narrow for all on one) plus the arrow, and its widest value; the name column takes what's left
M.ROW_W = { results = 700, mine = 700, craft = 800, harvest = 800 }
M.NAME_MIN = 190
M.ARROW_W, M.HEAD_PAD, M.CELL_PAD, M.COL_GAP = 12, 9, 8, 4
local MONEY, SMONEY, BIG = "99g 99s 99c", "-99g 99s 99c", "999g 99s 99c"
M.SAMPLE = { cost = MONEY, sell = MONEY, each = SMONEY, total = SMONEY, min = BIG, vendor = MONEY, ah = MONEY, margin = "9999%",
	listed = "9999", units = "99999", auctions = "9999", can = "9999", have = "9999", n = "9999", known = "*", best = "Vendor", change = "+1234%" }
M.SAMPLE_LIST = { mine = { total = BIG } }
local function Halves(label)
	local best
	for i in label:gmatch("() ") do
		local a, b = label:sub(1, i - 1), label:sub(i + 1)
		if not best or math.max(#a, #b) < math.max(#best[1], #best[2]) then best = { a, b } end
	end
	return best
end
function M.FitCols(list, parent, samples, oneLine)
	local cols = M.COLS[list]
	parent._fitfs = parent._fitfs or parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	local fs = parent._fitfs
	local function W(t, size) T.Font(fs, size) fs:SetText(t) return V.TextWidth(fs, t) end
	local need, two = {}, {}
	for i, c in ipairs(cols) do
		if not c.item then
			local sample = (samples and samples[c.key]) or (M.SAMPLE_LIST[list] or {})[c.key] or M.SAMPLE[c.key] or "9999"
			local v = W(sample, 11) + M.CELL_PAD
			local one = W(c.label, M.HEAD_FONT) + M.ARROW_W + M.HEAD_PAD
			local h = Halves(c.label)
			local t = h and math.max(W(h[1], M.HEAD_FONT), W(h[2], M.HEAD_FONT)) + M.ARROW_W + M.HEAD_PAD
			need[i] = { one = math.ceil(math.max(v, one)), two = t and math.ceil(math.max(v, t)) }
		end
	end
	local function Sum()
		local n = 0
		for i, c in ipairs(cols) do if need[i] then n = n + (two[i] and need[i].two or need[i].one) + M.COL_GAP end end
		return n
	end
	local rowW = M.ROW_W[list]
	-- (too wide on one line: the titles with the most to gain go to two lines, one at a time)
	-- (1.0.1: a strip built one line high stays one line: its titles never go to two lines it can't show; the name gives way)
	while not oneLine and rowW - 2 - Sum() < M.NAME_MIN do
		local gain, at = 0, nil
		for i in pairs(need) do
			local g = (not two[i] and need[i].two) and (need[i].one - need[i].two) or 0
			if g > gain then gain, at = g, i end
		end
		if not at then break end
		two[at] = true
	end
	local x = 2
	local anyTwo = false
	for i, c in ipairs(cols) do
		if c.item then c.x, c.w = x, rowW - 2 - Sum() - 2 x = x + c.w + 2
		else
			c.two = two[i] or nil
			if c.two then anyTwo = true end
			c.x, c.w = x, two[i] and need[i].two or need[i].one
			x = x + c.w + M.COL_GAP
		end
	end
	fs:Hide()
	if samples then return end   -- (a relayout: the strip keeps the height it was built with)
	M.HEAD_OF = M.HEAD_OF or {}
	M.HEAD_OF[list] = anyTwo and M.HEAD_H2 or M.HEAD_H
	return M.HEAD_OF[list]
end
local DIM = { 0.72, 0.63, 0.45 }
-- list's header strip, y down in f: a button per column at the column's own x and width (the rows': LIST_X in),
-- its label aligned as the column's values are; onSort(key) after a click has set the sort
function M.Headers(f, y, list, onSort)
	local hh = M.FitCols(list, f)
	local cols = M.COLS[list]
	local last = cols[#cols]
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", M.LIST_X, y)
	head:SetSize(last.x + last.w, hh)
	head.list, head.buttons, head.h = list, {}, hh
	for i, c in ipairs(cols) do
		local b = V.Button(head, c.label, c.w, hh, function() M.SetSort(list, c.key) if onSort then onSort(c.key) end end)
		b:SetPoint("TOPLEFT", c.x, 0)
		b.key, b.col = c.key, c
		T.Font(b.text, M.HEAD_FONT)
		b.text:ClearAllPoints()
		b.text:SetWidth(c.w - M.ARROW_W - M.HEAD_PAD + 2)
		if b.text.SetWordWrap then b.text:SetWordWrap(c.two and true or false) end
		if b.text.SetMaxLines then b.text:SetMaxLines(c.two and 2 or 1) end
		b.arrow = b:CreateTexture(nil, "OVERLAY")
		b.arrow:SetSize(9, 9)
		-- (the arrow in its own place, never over the title: the far side from the title's)
		local j = c.justify or "RIGHT"
		if j == "LEFT" then b.text:SetPoint("LEFT", 6, 0) b.arrow:SetPoint("RIGHT", -5, 0)
		else b.text:SetPoint("RIGHT", -5, 0) b.arrow:SetPoint("LEFT", 4, 0) end
		b.text:SetJustifyH(j == "CENTER" and "RIGHT" or j)
		if b.vh then b.vh.keepText = true end   -- (the title's colour is the sort's alone: hovering doesn't light it)
		V.Tip(b, c.label, function() return M.HeadTip(list, c.key) end)   -- (v0.4.2.8: what the column means)
		b.arrow:Hide()
		head.buttons[i] = b
	end
	-- labels: { [key] = text } for a label that changes (Scan results' Lowest / Highest)
	function head.Update(labels)
		local key, desc = M.GetSort(list)
		for _, b in ipairs(head.buttons) do
			local on = b.key == key
			b.text:SetText(labels and labels[b.key] or b.col.label)
			T.Skin(b, 0.9, on and GOLD or T.BRONZE)
			local c = on and ((ns.Style and ns.Style.WHITE) or { 1, 1, 1 }) or DIM
			b.text:SetTextColor(c[1], c[2], c[3])
			if on then Arrow(b.arrow, desc and "down" or "up") end
			b.arrow:SetShown(on)
		end
	end
	return head
end
-- (v0.4.2.7) the widths again from the widest value in the WHOLE list shown (not one page), so columns
-- are only as wide as this list needs and the name gets the rest; laid out again only when that changes
M.MONEY_KEYS = { cost = true, sell = true, each = true, total = true, min = true, vendor = true, ah = true }
function M.Samples(rows, list)
	local out = {}
	for _, c in ipairs(M.COLS[list]) do
		if not c.item then
			local max, neg = nil, false
			for _, e in ipairs(rows) do
				local v = c.value(e)
				if type(v) == "number" then
					if v < 0 then neg = true end
					if not max or math.abs(v) > max then max = math.abs(v) end
				end
			end
			if max then
				if M.MONEY_KEYS[c.key] then out[c.key] = (neg and "-" or "") .. I.Scan.Money(max)
				elseif c.key == "margin" then out[c.key] = ("%d%%"):format(math.floor(max * 100 + 0.5))
				elseif c.key == "known" then out[c.key] = "*"
				else out[c.key] = tostring(math.floor(max)) end
			else out[c.key] = "-" end
		end
	end
	return out
end
function M.Relayout(f, head, list, rowsKey, samples)
	local sig = {}
	for _, c in ipairs(M.COLS[list]) do sig[#sig + 1] = samples[c.key] or "" end
	sig = table.concat(sig, "|")
	if head.sig == sig then return false end
	head.sig = sig
	M.FitCols(list, f, samples, head.h < M.HEAD_H2)
	for _, b in ipairs(head.buttons) do
		local c = b.col
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", c.x, 0)
		b:SetSize(c.w, head.h)
		b.text:SetWidth(c.w - M.ARROW_W - M.HEAD_PAD + 2)
		if b.text.SetWordWrap then b.text:SetWordWrap(c.two and true or false) end
		if b.text.SetMaxLines then b.text:SetMaxLines(c.two and 2 or 1) end
	end
	local item = M.COLS[list][1]
	for _, r in ipairs(f.rows) do
		r.cell:SetWidth(item.w)
		for _, fs in pairs(r[rowsKey]) do
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", fs.col.x, 0)
			fs:SetWidth(fs.col.w)
		end
	end
	return true
end
-- (v0.4.2.7) a sort that needs the game's item data (a name, a vendor price) waits for all of the list's items, not
-- only the page shown: the missing ones asked for (30 at a time, V.LoadItem), then sorted again (again()) once all
-- are in. Until then: a note says how many are still coming; the missing ones sort last (never by a placeholder).
M.NEEDS = { results = { name = true }, mine = { name = true, vendor = true, best = true, total = true }, craft = { name = true }, harvest = { name = true } }
function M.NeedsData(list) return M.NEEDS[list][(M.GetSort(list))] and true or false end
-- (1.2.0) the names a sort or a search needs, asked for (at most V.LOAD_MAX at a time). Each arrival checks only its
-- own item (no pass over the whole list) and asks for the next; the list is redrawn (again) at most once a second
-- while names arrive, and at once when the last is in. onName(id): each arrival, for a cache to take its name.
M.FETCH_EVERY = 1
function M.Fetch(f, ids, again, y, onName)
	f.fetchGen = (f.fetchGen or 0) + 1
	local gen = f.fetchGen
	local want, queue = {}, {}
	for _, id in ipairs(ids) do if not want[id] and not V.ItemData(id) then want[id] = true queue[#queue + 1] = id end end
	f.want, f.wantN = want, #queue
	if not f.loadNote then
		f.loadNote = Text(f, 11, GREY)
		f.loadNote:SetPoint("TOPRIGHT", -8, y or -6)
		f.loadNote:SetJustifyH("RIGHT")
	end
	local function Note()
		if gen ~= f.fetchGen then return end
		local n = f.wantN
		f.loadNote:SetText(n > 0 and L["Sorting: %d items still coming from the game..."]:format(n) or "")
		f.loadNote:SetShown(n > 0)
	end
	local later = false
	local function Fire()
		later = false
		if gen ~= f.fetchGen then return end
		f.againAt = GetTime and GetTime() or 0
		f.redraws = (f.redraws or 0) + 1
		again()
	end
	local function Soon()
		if f.wantN == 0 and not f.inFetch then Fire() return end
		if later or not (C_Timer and C_Timer.After) then return end
		later = true
		C_Timer.After(f.wantN == 0 and 0.01 or M.FETCH_EVERY, function() if later then Fire() end end)
	end
	local function Done(id)
		want[id] = nil
		f.wantN = f.wantN - 1
		if onName then onName(id) end
	end
	local Ask
	local function Got(id)
		if gen ~= f.fetchGen or not want[id] or not V.ItemData(id) then return end
		f.checked = (f.checked or 0) + 1
		Done(id) Note() Ask() Soon()
	end
	local pos, asking, retry = 1, false, false
	Ask = function()
		if asking then return end
		asking = true
		while pos <= #queue do
			local id = queue[pos]
			if not want[id] then pos = pos + 1
			elseif V.LoadItem(id, Got) then pos = pos + 1
			else
				-- (LOAD_MAX already asked for: the rest in a second; any that came meanwhile taken then)
				if not retry and C_Timer and C_Timer.After then
					retry = true
					C_Timer.After(1, function()
						retry = false
						if gen ~= f.fetchGen then return end
						local any = false
						for id2 in pairs(want) do if V.ItemData(id2) then Done(id2) any = true end end
						Note() Ask()
						if any then Soon() end
					end)
				end
				break
			end
		end
		asking = false
	end
	f.inFetch = true
	Ask()
	f.inFetch = nil
	Note()
	return f.wantN
end
-- a row's cells for list's columns (not the item column: the row's item cell): { [key] = font string }
function M.Cells(r, list)
	local cells = {}
	for _, c in ipairs(M.COLS[list]) do
		if not c.item then cells[c.key] = Column(r, "", c.x, c.w, c.justify) cells[c.key].col = c end
	end
	return cells
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
-- (1.2.0) a skill recorded at a trainer of the profession (Trainer.lua) before the bundled one
function M.TopSkill(kind, prof, id)
	if kind == "craft" and I.Trainer then
		local rec = I.Trainer.Skill(prof, id)
		if rec then return rec end
	end
	local C = I.Craft
	local map = C and C.TopMap and C.TopMap(kind)
	local t = map and map[prof]
	if not t then return nil end
	return t[id]
end
-- (1.2.0) an item with no known skill level shows at every level, marked "?" (unknown[id]); returns the list, the
-- count of those unknown, and unknown
function M.TopFilter(list, kind, prof, bracket)
	if kind ~= "craft" and kind ~= "harvest" then return list, 0, {} end
	local out, hidden, unknown = {}, 0, {}
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
			elseif not best then hidden = hidden + 1 unknown[e.id] = true out[#out + 1] = e
			elseif best >= b[3] and best <= b[4] then out[#out + 1] = e end
		end
	end
	return out, hidden, unknown
end

M.TOP_COLS_W = 660   -- (Rising and Falling: two columns of 330)
-- (v0.4.2.6) a Top 10 row, 320 wide: the item, the change, the price, the sparkline. The change and the price are as
-- wide as their widest shown text needs (measured: the game's own string widths, so never cut short, never wrapped;
-- +1234% and 9999g 99s 99c fit), at least TOP_CHANGE_W and TOP_PRICE_W; the item's name gets the rest
M.TOP_ROW_W, M.TOP_CHANGE_W, M.TOP_PRICE_W, M.TOP_GAP, M.TOP_PAD = 320, 48, 72, 4, 4
-- one column's numbers fitted (shown rows): the widths, right to left from the sparkline; the name what's left
-- (atLeast: the other column's widths, so Rising and Falling line up alike)
function M.FitTop(col, atLeast)
	local cw = math.max(M.TOP_CHANGE_W, atLeast and atLeast.change or 0)
	local pw = math.max(M.TOP_PRICE_W, atLeast and atLeast.price or 0)
	for _, r in ipairs(col.rows) do
		if r:IsShown() then
			cw = math.max(cw, math.ceil(V.TextWidth(r.change) + M.TOP_PAD))
			pw = math.max(pw, math.ceil(V.TextWidth(r.price) + M.TOP_PAD))
		end
	end
	local sx = M.TOP_ROW_W - M.SPARK * M.SPARK_STEP
	local px = sx - M.TOP_GAP - pw
	local cx = px - M.TOP_GAP - cw
	for _, r in ipairs(col.rows) do
		r.price:ClearAllPoints() r.price:SetPoint("LEFT", px, 0) r.price:SetWidth(pw)
		r.change:ClearAllPoints() r.change:SetPoint("LEFT", cx, 0) r.change:SetWidth(cw)
		r.spark:ClearAllPoints() r.spark:SetPoint("LEFT", sx, -2)
		r.cell:SetWidth(cx - M.TOP_GAP - 2)
	end
	col.fit = { change = cw, price = pw, changeX = cx, priceX = px, sparkX = sx, name = cx - M.TOP_GAP - 2 }
	-- (v0.4.2.8) the column titles over their columns
	if col.heads then
		col.heads[2]:ClearAllPoints() col.heads[2]:SetPoint("TOPLEFT", cx, -2) col.heads[2]:SetWidth(cw)
		col.heads[3]:ClearAllPoints() col.heads[3]:SetPoint("TOPLEFT", px, -2) col.heads[3]:SetWidth(pw)
		col.heads[4]:ClearAllPoints() col.heads[4]:SetPoint("TOPLEFT", sx, -2) col.heads[4]:SetWidth(M.SPARK * M.SPARK_STEP + 8)
	end
	return col.fit
end
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

M.HOUSES = { "Alliance", "Horde", "Neutral" }
M.INVEST_WAIT = 0.3   -- (seconds after the last key before the rows update)

-- (v0.4.2.8) what each column means (its header's tooltip); a function: worded for the settings now
local function CutPct() return ("%d%%"):format(math.floor(S().Cut(M.House()) * 100 + 0.5)) end
local REAGENTS = {
	market = "Market: each at the AH's lowest, or a merchant's price you've seen if cheaper.",
	free = "Owned: yours (per Count) count 0; the rest at the AH's lowest, or a merchant's if cheaper.",
}
M.HEAD_TIPS = {
	results = {
		name = "The item's name. Click a row for its price history.",
		min = "The lowest buyout per unit in your last full scan. \"bid only\": no auction with a buyout.",
		units = "Units listed, all auctions added up (bid-only ones too).",
		auctions = "How many auctions are listed.",
		change = "The lowest price's move over 7 days: the median of the recent half of your full scans against the earlier half's. \"-\": fewer than 3 full scans of it in 7 days.",
	},
	mine = {
		name = "What you have. Click a row for its price history.",
		n = "How many you have: bags, or bags + bank (as last seen), per Count.",
		vendor = "What a vendor pays you for one.",
		ah = function() return "The AH's lowest buyout for one, less its " .. CutPct() .. " cut." end,
		best = "Where one is worth more: the AH (after its cut) or a vendor.",
		total = "Have x the better of the two prices.",
	},
	craft = {
		name = "The recipe, by what it makes. Hover a row for its reagents and costs.",
		cost = function() return "What one craft's reagents cost. " .. (REAGENTS[I.S.craftOwned or "market"] or REAGENTS.market) end,
		sell = "The AH's lowest buyout for one of what it makes.",
		each = function() return "Per item made: the sale less the AH's " .. CutPct() .. " cut, less the cost to make." end,
		margin = "Profit as a share of the cost to make. \"-\": the reagents cost nothing.",
		listed = "Units of it on the AH now.",
		can = "Owned: how many crafts your reagents make (per Count). Market: how many the Invest Amount buys (0 without one).",
		total = function() return "Owned: Profit per craft x Can make (yours cost nothing). Market with an Invest Amount: the sale after the AH's " .. CutPct() .. " cut x Can make, less the gold spent." end,
	},
	harvest = {
		name = "What this profession gathers.",
		sell = "The AH's lowest buyout for one.",
		each = function() return "Sell at, less the AH's " .. CutPct() .. " cut. (You gathered it: no cost.)" end,
		listed = "Units of it on the AH now.",
		have = "How many you have: bags, or bags + bank, per Count (None: 0).",
		total = "Have x Profit/item.",
	},
}
function M.HeadTip(list, key)
	local t = (M.HEAD_TIPS[list] or {})[key]
	if type(t) == "function" then t = t() end
	return t and L[t] or ""
end

-- (v0.4.2.8) Top 10's two views, their titles over each column (no sorting) and what each means:
-- { list title, the number column, Price, the bars } per side
M.TOP_VIEWS = { { "movers", "Price movers" }, { "sold", "Trending" } }
local CHANGE = { "Change", "The lowest price's move: the median of the recent half of your full scans in 7 days against the earlier half's." }
local LAST8 = { "Last 8", "The last 8 full-scan lowest prices (one an hour at most), oldest left; bar height against the highest kept." }
local LISTED8 = { "Listed", "Units listed in each of your last 8 full scans, oldest left." }
local NOWPRICE = { "Price", "The lowest buyout in your last full scan." }
M.TOP_HEADS = {
	movers = {
		{ { "Rising", "Items whose lowest price went up over 7 days. Click one for its price history." }, CHANGE,
		  { "Price", "The recent half's median lowest buyout." }, LAST8 },
		{ { "Falling", "Items whose lowest price went down over 7 days. Click one for its price history." }, CHANGE,
		  { "Price", "The recent half's median lowest buyout." }, LAST8 },
	},
	sold = {
		{ { "Most units sold", "Estimated: the units that left the AH between your full scans, per day. Bought, expired and cancelled look the same." },
		  { "Sold/day", "Units gone per day: every drop in units listed between two full scans (12 h apart at most), added up, over the hours those scans cover." },
		  NOWPRICE, LISTED8 },
		{ { "Most gold sold", "Estimated: units gone per day x their lowest price at the time." },
		  { "Gold/day", "Each drop in units x the lowest price before it, added up, per day." },
		  NOWPRICE, LISTED8 },
	},
}
M.TOP_VIEW_TIPS = { movers = "Items whose lowest price moved most over 7 days.",
	sold = "Items selling the most, estimated from units leaving the AH between your full scans." }
M.UNKNOWN_MARK = " |cffaaaaaa?|r"
M.UNKNOWN_NOTE = "? %d shown with no known %s skill level yet: they show at every level. Open a %s trainer once to record the levels it teaches; a recipe you find or buy (not taught by trainers) stays ? until its level is in Valhalla's data."
M.SOLD_NOTE = "Estimate: units that left the AH between your full scans. Bought, expired and cancelled look the same; new listings hide some. More full scans, closer together: a better estimate."
function M.TopView() return I.S.topView == "sold" and "sold" or "movers" end

-- (v0.4.2.8) Craft's Count (None | Bags only | Bags + bank): its own setting, first from My items' (mineBank)
M.COUNTS = { { "none", "None" }, { "bags", "Bags only" }, { "bank", "Bags + bank" } }
function M.CraftCount()
	local c = I.S.craftCount
	if c ~= "none" and c ~= "bags" and c ~= "bank" then
		c = I.S.mineBank and "bank" or "bags"
		I.S.craftCount = c
	end
	return c
end
-- what C.Have / C.Rank take for it: "none", true (bags + bank) or false (bags)
-- (v0.4.2.9) Reagents = Market (crafts): Count greyed and None (Market prices every reagent, yours too); the choice kept
-- for Owned. Harvest has no reagents: Count works there as chosen
function M.CountLocked() return (I.S.craftOwned or "market") == "market" and M.craftMode ~= "harvest" end
-- (1.0.1) the Invest Amount counts with Reagents: Market only (Owned: greyed; Harvest: greyed)
function M.InvestOn() return (I.S.craftOwned or "market") == "market" and M.craftMode ~= "harvest" end
function M.CountNow() if M.CountLocked() then return "none" end return M.CraftCount() end
function M.CountArg() local c = M.CountNow() return c == "none" and "none" or c == "bank" end

-- (v0.4.2.8) the Invest Amount (one box over the Craft table, for every row; this session only): copper or nil
M.investAmount = nil
function M.ParseMoney(t)
	t = tostring(t or ""):lower():gsub("%s+", "")
	if t == "" then return nil end
	if t:match("^%d+%.?%d*$") or t:match("^%.%d+$") then
		local n = math.floor(tonumber(t) * 10000 + 0.5)
		return n > 0 and n or nil
	end
	if not t:match("^[%dgsc]+$") or not t:match("%d[gsc]") then return nil end
	local g, s, c = tonumber(t:match("(%d+)g") or 0), tonumber(t:match("(%d+)s") or 0), tonumber(t:match("(%d+)c") or 0)
	local n = g * 10000 + s * 100 + c
	return n > 0 and n or nil
end
-- how many crafts amount buys (v0.4.2.9): yours (per Count) used first, the rest bought at the AH with the amount: the
-- largest n whose gold fits. Returns n, the gold spent, and the cost taken off Total (the gold). (1.0.1: the amount is
-- Market's only, where Count is None: nothing of yours used; Owned shows what yours make, no amount.)
M.INVEST_MAX = 9999
function M.Afford(e, amount, have, owned)
	have = owned == "market" and {} or have or {}
	local function Gold(n)
		local gold, ownValue = 0, 0
		for _, p in ipairs(e.parts or {}) do
			local need = n * p.n
			local own = math.min(need, have[p.id] or 0)
			local buy = need - own
			if buy > 0 then
				if not p.unit then return math.huge, 0 end
				gold = gold + buy * p.unit
			end
		end
		return gold, ownValue
	end
	local function Out(n) local g, v = Gold(n) return n, g, g + v end
	if Gold(1) > amount then return 0, 0, 0 end
	if Gold(M.INVEST_MAX) <= amount then return Out(M.INVEST_MAX) end
	local lo, hi = 1, M.INVEST_MAX   -- (Gold(lo) fits, Gold(hi) doesn't)
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if Gold(mid) <= amount then lo = mid else hi = mid end
	end
	return Out(lo)
end
-- a craft row's Can make and Total as shown (and sorted): from the Invest Amount when there is one
function M.Shown(e)
	local amount = M.investAmount
	local cnt = M.CountNow()
	if not M.InvestOn() then amount = nil end   -- (1.0.1: Owned: what yours make; the amount is kept, not used)
	if amount and e.sell and e.parts then
		local owned = I.S.craftOwned or "market"
		local house = M.House()
		local tag = ("%d|%s|%s|%s|%s|%s"):format(amount, cnt, owned, house, tostring(I.char and I.char.bagsSeen), tostring(I.char and I.char.bankSeen))
		if e._shownTag ~= tag then
			if M._haveTag ~= tag then M._have, M._haveTag = I.Craft.Have(M.CountArg()), tag end
			local n, _, cost = M.Afford(e, amount, M._have, owned)
			e._shownN = n
			e._shownTotal = n > 0 and (n * e.sell * e.qty * (1 - S().Cut(house)) - cost) or nil
			e._shownTag = tag
		end
		return e._shownN, e._shownTotal
	end
	return e.can, e.total
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
	-- (v0.4.2.8) Price movers | Trending at the top right; the Level under them (right of the columns: no overlap)
	f.views = {}
	for k, vw in ipairs(M.TOP_VIEWS) do
		local b = V.Button(f, L[vw[2]], 100, 20, function() I.S.topView = vw[1] f.Redraw() end)
		b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8 - (#M.TOP_VIEWS - k) * 104, -6)
		b.view = vw[1]
		V.Tip(b, L[vw[2]], L[M.TOP_VIEW_TIPS[vw[1]]])
		f.views[k] = b
	end
	f.levelTitle = Text(f, 12)
	f.levelTitle:SetPoint("TOPLEFT", M.TOP_COLS_W + 8, -35)
	f.levelTitle:SetText(L["Level:"])
	f.level = DropMenu(f, 130, 5, function(v) I.S.topBracket = v f.Redraw() end)
	f.level:SetPoint("TOPLEFT", M.TOP_COLS_W + 8, -52)   -- (under its title: the title never runs into it at the game's font)
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
		-- (v0.4.2.8) the column titles (no sorting), each with what it means
		col.titleHit = CreateFrame("Frame", nil, col)
		col.titleHit:SetPoint("TOPLEFT", 0, 0)
		col.titleHit:SetSize(150, 16)
		if col.titleHit.EnableMouse then col.titleHit:EnableMouse(true) end
		V.Tip(col.titleHit, "", "")
		col.heads = {}
		for k = 2, 4 do
			local h = CreateFrame("Frame", nil, col)
			h:SetSize(60, 16)
			h.text = Text(h, 10, DIM)
			h.text:SetAllPoints()
			h.text:SetJustifyH(k == 4 and "LEFT" or "RIGHT")
			if h.EnableMouse then h:EnableMouse(true) end
			V.Tip(h, "", "")
			col.heads[k] = h
		end
		col.rows = {}
		for i = 1, M.TOP do
			local r = CreateFrame("Frame", nil, col)
			r:SetSize(320, 24)
			r:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 26)
			r.cell = V.ItemCell(r, 160)
			r.cell:SetPoint("LEFT", 2, 0)
			if r.cell.name.SetWordWrap then r.cell.name:SetWordWrap(true) end   -- (Top 10 keeps its two-line names)
			if r.cell.name.SetMaxLines then r.cell.name:SetMaxLines(2) end   -- (v0.4.2.6: a long name, two lines at most)
			r.cell.onClick = function(id) M.ShowHistory(page, id) end
			r.change = Column(r, "", 164, M.TOP_CHANGE_W)
			r.price = Column(r, "", 216, M.TOP_PRICE_W)
			for _, fs in ipairs({ r.change, r.price }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end   -- (one line, always)
			r.spark = Spark(r)
			r.spark:SetPoint("LEFT", M.TOP_ROW_W - M.SPARK * M.SPARK_STEP, -2)
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
		local view = M.TopView()
		for _, b in ipairs(f.views) do T.Skin(b, 0.9, b.view == view and GOLD or T.BRONZE) end
		local rising, falling, fulls, nextAt
		if view == "sold" then rising, falling, fulls, nextAt = S().SoldAll(house)
		else rising, falling, fulls, nextAt = S().TrendingAll(house) end
		for c, col in ipairs(f.cols) do
			local H = M.TOP_HEADS[view][c]
			col.title:SetText(L[H[1][1]])
			col.title:SetTextColor(unpack(view == "sold" and GOLD or (c == 1 and GREEN or RED)))
			col.titleHit.tip.title, col.titleHit.tip.text = L[H[1][1]], L[H[1][2]]
			for k = 2, 4 do
				col.heads[k].text:SetText(L[H[k][1]])
				col.heads[k].tip.title, col.heads[k].tip.text = L[H[k][1]], L[H[k][2]]
			end
		end
		local unkR, unkF, _
		rising, _, unkR = M.TopFilter(rising, kind, prof, bracket)
		falling, _, unkF = M.TopFilter(falling, kind, prof, bracket)
		local shown = {}
		local any = fulls >= 3 and (#rising > 0 or #falling > 0)
		f.empty:SetShown(not any)
		local when = (not nextAt or nextAt <= Now()) and L["now"] or (date and date("%H:%M", nextAt) or tostring(nextAt))
		local what = kind == "all" and "" or ((prof and ProfName(prof) or (kind == "craft" and L["crafted"] or L["harvested"])) .. (bracket ~= "all" and (" (" .. bl .. ")") or "") .. " ")
		if fulls < 3 then
			f.empty:SetText(L["Top 10 needs full scans in 3 different hours within 7 days (you have %d). History keeps one point an hour, so two scans in the same hour count once; your next full scan counts from %s. Scan at the Auction House: the Scan button is on Valhalla's list beside it."]:format(fulls, when))
		elseif view == "sold" then
			f.empty:SetText(L["Nothing left the AH between your full scans of the last 7 days (12 h apart at most). Your next full scan counts from %s."]:format(when))
		elseif kind == "all" then
			f.empty:SetText(L["No price moved in your scans of the last 7 days (full scans in %d different hours). Your next full scan counts from %s."]:format(fulls, when))
		else
			f.empty:SetText(L["No %sitem moved in your scans of the last 7 days (full scans in %d different hours). Your next full scan counts from %s."]:format(what, fulls, when))
		end
		-- (1.2.0) the rows marked "?" shown (an unknown skill level shows at every level)
		local marked = 0
		for c, list in ipairs({ rising, falling }) do
			local unk = c == 1 and unkR or unkF
			for i = 1, math.min(M.TOP, #list) do if unk[list[i].id] then marked = marked + 1 end end
		end
		local notes = {}
		if view == "sold" and any then notes[#notes + 1] = L[M.SOLD_NOTE] end
		if marked > 0 and any then notes[#notes + 1] = L[M.UNKNOWN_NOTE]:format(marked, prof and ProfName(prof) or "", prof and ProfName(prof) or "") end
		f.marked = marked
		f.note:SetShown(#notes > 0)
		f.note:SetText(table.concat(notes, " "))
		if not any then f.note:ClearAllPoints() f.note:SetPoint("TOPLEFT", 8, TOPY - 50)
		else f.note:ClearAllPoints() f.note:SetPoint("TOPLEFT", 8, TOPY - 30 - M.TOP * 26 - 6) end
		f.note:SetPoint("RIGHT", f, "RIGHT", -8, 0)   -- (v0.4.2.8: wraps inside the page)
		if f.note.SetWordWrap then f.note:SetWordWrap(true) end
		f.nextAt = nextAt
		for c, list in ipairs({ rising, falling }) do
			local col = f.cols[c]
			col:SetShown(any)
			for i, r in ipairs(col.rows) do
				local e = list[i]
				if e and any then
					r.cell.suffix = (c == 1 and unkR or unkF)[e.id] and M.UNKNOWN_MARK or nil
					r.cell:SetItem(e.id, M.Lines)
					if view == "sold" then
						r.change:SetText(c == 1 and tostring(math.floor(e.perDay + 0.5)) or (S().Money(e.goldDay):gsub(" %d+c$", "")))
						r.change:SetTextColor(1, 1, 1)
						r.price:SetText(e.now and e.now > 0 and S().Money(e.now) or "-")
						local units = {}
						for _, p in ipairs(S().Points(house, e.id)) do if not p.quick then units[#units + 1] = p.units end end
						r.spark.Set(units)
					else
						r.change:SetText(Pct(e.change))
						r.change:SetTextColor(unpack(e.change > 0 and GREEN or RED))
						r.price:SetText(S().Money(e.now))
						local mins = {}
						for _, p in ipairs(S().Points(house, e.id)) do if not p.quick and p.min > 0 then mins[#mins + 1] = p.min end end
						r.spark.Set(mins)
					end
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
		-- (v0.4.2.6) the numbers' columns as wide as the widest of both lists needs, the same in both
		local a, b = M.FitTop(f.cols[1]), M.FitTop(f.cols[2])
		M.FitTop(f.cols[1], b) M.FitTop(f.cols[2], a)
		f.rising, f.falling, f.fulls = rising, falling, fulls
		return shown
	end
end

--------------------------------------------------------------------------------
-- My items: bags (+ bank), vendor vs the AH (after its cut)
--------------------------------------------------------------------------------

-- (v0.4.2.7) every filter row's boxes start at the same x: after the widest of all the filter titles
M.FILTER_TITLES = { L["Reagents:"], L["Show:"], L["Count:"] }
function M.FilterStart(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	T.Font(fs, 12)
	local w = 0
	for _, t in ipairs(M.FILTER_TITLES) do fs:SetText(t) w = math.max(w, V.TextWidth(fs, t)) end
	fs:Hide()
	return math.floor(w + 16 + 0.5)
end

local function BuildMine(f, page)
	f.offset = 0
	f.scope = V.Radio(f, L["Count:"], { { false, L["Bags only"] }, { true, L["Bags + bank"] } },
		function() return I.S.mineBank and true or false end, function(v) I.S.mineBank = v f.offset = 0 f.Refresh() end)
	f.scope:SetPoint("TOPLEFT", 8, -4)
	V.Grid({ { frame = f.scope, title = f.scope.title, boxes = f.scope.boxes } }, M.FilterStart(f))   -- (Craft's filter columns)
	-- (v0.4.2.6) the headers sort (M.COLS.mine: the rows' own columns)
	f.head = M.Headers(f, -28, "mine", function() f.offset = 0 f.Refresh() end)
	f.sortButtons = f.head.buttons
	local item = M.COLS.mine[1]
	local top = 28 + f.head.h
	Paged(f, page, top, function(i)
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(M.ROW_W.mine, 24)
		r:SetPoint("TOPLEFT", M.LIST_X, -top - (i - 1) * M.ROW_H)
		r.cell = V.ItemCell(r, item.w)
		r.cell:SetPoint("LEFT", item.x, 0)
		r.cell.onClick = function(id) M.ShowHistory(page, id) end
		r.cells = M.Cells(r, "mine")
		for k, fs in pairs(r.cells) do r[k] = fs end   -- (r.n, r.vendor, r.ah, r.best, r.total)
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
		local tag = M.SortTag("mine")
		if not keep or not f.list or f.sortTag ~= tag then
			f.list, f.sums = S().Mine(house, I.S.mineBank)
			M.SortList(f.list, "mine")
			local ids = {}
			if M.NeedsData("mine") then for _, e in ipairs(f.list) do ids[#ids + 1] = e.id end end
			M.Fetch(f, ids, function() f.list = nil f.Refresh(true) end, -6)
			f.sortTag = tag
		end
		f.scope.Update()
		f.head.Update()
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
				r.best:SetTextColor(1, 1, 1)   -- (plain: green is for profit only)
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
	-- (1.2.0) hovering: one overlay over the plot; the nearest point's price, time, units and scan; a dot on it
	f.hover = CreateFrame("Frame", nil, f.plot)
	f.hover:SetAllPoints(f.plot)
	if f.hover.SetFrameLevel and f.plot.GetFrameLevel then f.hover:SetFrameLevel((f.plot:GetFrameLevel() or 1) + 5) end
	if f.hover.EnableMouse then f.hover:EnableMouse(true) end
	f.dot = f.hover:CreateTexture(nil, "OVERLAY")
	f.dot:SetSize(9, 9)
	f.dot:SetColorTexture(1, 1, 1, 1)
	f.dot:Hide()
	function f.HoverAt(x)
		local i = M.Nearest(f.xy, x)
		if not i then f.HoverOff() return nil end
		if i == f.hovered then return i end
		f.hovered = i
		local p, xy = f.pts[i], f.xy[i]
		f.dot:ClearAllPoints()
		f.dot:SetPoint("CENTER", f.plot, "BOTTOMLEFT", xy[1], xy[2])
		f.dot:Show()
		if GameTooltip then
			GameTooltip:SetOwner(f.hover, "ANCHOR_CURSOR")
			local lines = M.PointLines(p)
			GameTooltip:AddLine(lines[1], 1, 1, 1)
			for k = 2, #lines do GameTooltip:AddLine(lines[k], 0.8, 0.8, 0.8) end
			GameTooltip:Show()
		end
		return i
	end
	function f.HoverOff()
		f.hovered = nil
		f.dot:Hide()
		if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == f.hover then GameTooltip:Hide() end
	end
	local function CursorX()
		local x = GetCursorPosition and GetCursorPosition()
		local left = f.plot.GetLeft and f.plot:GetLeft()
		if not (x and left) then return nil end
		local scale = f.plot.GetEffectiveScale and f.plot:GetEffectiveScale() or 1
		return x / (scale or 1) - left
	end
	f.hover:SetScript("OnEnter", function(self)
		self:SetScript("OnUpdate", function() local x = CursorX() if x then f.HoverAt(x) end end)
	end)
	f.hover:SetScript("OnLeave", function(self) self:SetScript("OnUpdate", nil) f.HoverOff() end)
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
		f.HoverOff()
		f.pts, f.xy = {}, {}
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
		f.xy, f.pts = {}, pts
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

-- (1.2.0) the point nearest x (the plot's own x), and what its tooltip says
function M.Nearest(xy, x)
	local best, bd
	for i, p in ipairs(xy or {}) do
		local d = math.abs(p[1] - x)
		if not bd or d < bd then best, bd = i, d end
	end
	return best
end
function M.PointLines(p)
	return {
		S().Money(p.min),
		(date and date("%a %d %b, %H:%M", p.t) or tostring(p.t)) .. " (" .. S().Age(p.t) .. ")",
		p.quick and L["%d units listed"]:format(p.units or 0) or L["%d units in %d auctions"]:format(p.units or 0, p.auctions or 0),
		p.quick and L["Quick scan"] or L["Full scan"],
	}
end

function M.ShowHistory(page, id)
	M.historyID = id
	page:ShowSub("history")
end

--------------------------------------------------------------------------------
-- Scan results: every item of the last full scan, searchable and sortable
--------------------------------------------------------------------------------

-- (1.2.0) a house's last scan read once: { key, house, all, byId, orders, desc } (a new scan: read again)
function M.ResultsCache(f, house)
	local m = S().Market(house)
	local _, at = S().LastScan(house, "full")
	local key = ("%s:%d:%s"):format(house, m and m.scans and #m.scans or 0, tostring(at or ""))
	local C = f.cache
	if C and C.key == key then return C end
	C = { key = key, house = house, all = {}, byId = {}, orders = {}, desc = {} }
	for id in pairs(m and m.cur or {}) do
		local c = S().Cur(house, id)
		if c and not c.quick then
			local name = V.ItemData(id)
			local e = { id = id, name = name, lname = name and name:lower(), min = c.min, units = c.units, auctions = c.auctions or 0 }
			C.all[#C.all + 1] = e
			C.byId[id] = e
		end
	end
	f.cache = C
	f.cacheBuilds = (f.cacheBuilds or 0) + 1
	return C
end
-- a row's 7-day change, worked out once a scan (nil: none)
function M.ResultChange(C, e)
	if not e then return nil end
	if not e.changed then e.change, e.changed = M.Change(C and C.house or M.House(), e.id), true end
	return e.change
end
-- a column's order: sorted once (low to high), flipped for high to low
function M.ResultsOrder(C, key, desc)
	local asc = C.orders[key]
	if not asc then
		if key == "change" then for _, e in ipairs(C.all) do M.ResultChange(C, e) end end
		asc = {}
		for i, e in ipairs(C.all) do asc[i] = e end
		M.SortBy(asc, "results", key, false)
		C.orders[key], C.desc[key] = asc, nil
		C.sorts = (C.sorts or 0) + 1
	end
	if not desc then return asc end
	if not C.desc[key] then C.desc[key] = M.Flip(asc, "results", key) end
	return C.desc[key]
end
-- a name arrived: on its row; the name order made again when next asked
function M.ResultsName(C, id)
	local e = C.byId[id]
	if not e then return end
	local name = V.ItemData(id)
	e.name, e.lname = name, name and name:lower()
	C.orders.name, C.desc.name = nil, nil
end

local function BuildResults(f, page)
	f.search = V.EditBox(f, 200)
	f.search:SetPoint("TOPLEFT", 8, -4)
	f.search:SetScript("OnTextChanged", function() f.offset = 0 f.dirty = true f.Refresh() end)
	f.searchHint = Text(f, 10, GREY)
	f.searchHint:SetPoint("LEFT", f.search, "RIGHT", 8, 0)
	f.searchHint:SetText(L["search by name"])
	if ns.LinkBox then ns.LinkBox(f.search, M.TakeName) end   -- (v0.4.2.1: shift-click an item: its name searched)
	-- (v0.4.2.6) the sort buttons are the column headers, each over its own column (M.COLS.results; they were a
	-- row of equal buttons, off their columns); the price's reads Lowest, or Highest sorted high to low
	f.head = M.Headers(f, -30, "results", function() f.offset = 0 f.dirty = true f.Refresh() end)
	f.sortButtons = f.head.buttons
	local item = M.COLS.results[1]
	local top = 30 + f.head.h + 6
	Paged(f, page, top, function(i)
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(M.ROW_W.results, 24)
		r:SetPoint("TOPLEFT", M.LIST_X, -top - (i - 1) * M.ROW_H)
		r.cell = V.ItemCell(r, item.w)
		r.cell:SetPoint("LEFT", item.x, 0)
		r.cell.onClick = function(id) M.ShowHistory(page, id) end
		r.cells = M.Cells(r, "results")
		for k, fs in pairs(r.cells) do r[k] = fs end   -- (r.min, r.units, r.auctions, r.change)
		r:Hide()
		return r
	end)
	f.count = Text(f, 11, GREY)
	f.count:SetPoint("BOTTOMLEFT", 8, 6)
	-- (1.2.0) one scan read once (M.ResultsCache), each column's order sorted once, the other way flipped from it;
	-- a search filters that order; names asked for once a scan, each arrival taken into the cache alone
	function f.Build()
		local house = M.House()
		local C = M.ResultsCache(f, house)
		local key, desc = M.GetSort("results")
		local order = M.ResultsOrder(C, key, desc)
		local q = (f.search:GetText() or ""):lower()
		local list
		if q == "" then list = order
		else
			list = {}
			for _, e in ipairs(order) do if e.lname and e.lname:find(q, 1, true) then list[#list + 1] = e end end
		end
		if (M.NeedsData("results") or q ~= "") and not C.fetched then
			C.fetched = true
			local ids = {}
			for _, e in ipairs(C.all) do if not e.name then ids[#ids + 1] = e.id end end
			M.Fetch(f, ids, function() f.dirty = true f.Refresh(true) end, -6, function(id) M.ResultsName(C, id) end)
		end
		f.list, f.house = list, house
	end
	function f.Refresh(keep)
		local house = M.House()
		local m = S().Market(house)
		local key = ("%s:%d:%s:%s:%s"):format(house, m and #m.scans or 0, f.search:GetText() or "", M.SortTag("results"), "")
		if not f.list or (not keep and key ~= f.key) or f.dirty then
			if key ~= f.key then f.offset = 0 end   -- (another house, search, sort or scan: page 1)
			f.Build() f.key, f.dirty = key, nil
		end
		f.Clamp()
		local list, shown = f.list, {}
		local skey, sdesc = M.GetSort("results")
		f.head.Update({ min = (skey == "min" and sdesc) and L["Highest"] or L["Lowest"] })
		for i, r in ipairs(f.rows) do
			local e = i <= f.per and list[f.offset + i]
			if e then
				r.cell:SetItem(e.id, M.Lines)
				r.min:SetText(e.min > 0 and S().Money(e.min) or L["bid only"])
				r.units:SetText(tostring(e.units))
				r.auctions:SetText(tostring(e.auctions))
				local ch = M.ResultChange(f.cache, e)
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
M.CRAFT_TOP = 150          -- (the rows start here; the status above may take two lines)
M.CRAFT_STRIPS = 18        -- (a second line under the rows: Can't price and Not listed each have one)
M.OWNED = { { "market", L["Market"] }, { "free", L["Owned"] } }   -- (1.0.1: "Owned free" is Owned; Owned: vendor gone)
-- Craft's status line, short enough for one line (v0.4.2.7)
function M.CraftStatus(name, recipes, live, priced, cut, age, unknown, skipped)
	local t = L["%s: %d recipes (%s), %d priced; %d%% AH cut; scan %s"]:format(name, recipes, live and L["live"] or L["client data"],
		priced, math.floor(cut * 100 + 0.5), age)
	if (unknown or 0) > 0 then t = t .. L["; %d not loaded"]:format(unknown) end
	if (skipped or 0) > 0 then t = t .. L["; %d skipped"]:format(skipped) end
	return t .. "."
end
M.CRAFT_W = 800            -- (v0.4.2.7: the rows' width, M.ROW_W.craft; was 706)
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
	V.Grid({
		{ frame = f.owned, title = f.owned.title, boxes = f.owned.boxes },
		{ frame = f.showRow, title = f.showTitle, boxes = { f.known } },
	}, M.FilterStart(f))
	-- (v0.4.2.8) Count: None | Bags only | Bags + bank, a dropdown in Reagents' 2nd column (Craft's own setting)
	f.countDrop = DropMenu(f, 200, #M.COUNTS, function(v) I.S.craftCount = v f.offset = 0 page:Refresh() end)
	f.countDrop:SetPoint("LEFT", f.owned.boxes[2], "LEFT", 0, 0)
	f.countDrop:SetPoint("TOP", f.showRow, "TOP", 0, 1)
	local function CountEntries() local out = {} for i, x in ipairs(M.COUNTS) do out[i] = { x[1], L[x[2]] } end return out end
	function f.countDrop.Open() if f.countDrop.locked then return end f.countDrop.Fill(CountEntries(), M.CraftCount()) f.countDrop.menu:Show() end
	f.count = f.countDrop
	function f.count.Update()
		-- (v0.4.2.9) Reagents = Market: greyed, None (the choice kept for the Owned modes)
		local locked = M.CountLocked()
		f.countDrop.locked = locked
		if locked and f.countDrop.menu:IsShown() then f.countDrop.menu:Hide() end
		if f.countDrop.EnableMouse then f.countDrop:EnableMouse(not locked) end
		f.countDrop:SetAlpha(locked and 0.45 or 1)
		local c = M.CountNow()
		for _, x in ipairs(M.COUNTS) do if x[1] == c then f.countDrop.text:SetText(L["Count: %s"]:format(L[x[2]])) end end
	end
	-- (v0.4.2.8) Invest Amount: one box for every row, live as you type (this session only)
	f.investTitle = Text(f, 12)
	f.investTitle:SetPoint("LEFT", f.countDrop, "RIGHT", 12, 0)
	f.investTitle:SetText(L["Invest Amount:"])
	f.invest = V.EditBox(f, 100)
	f.invest:SetPoint("LEFT", f.countDrop, "RIGHT", 12 + math.ceil(f.investTitle:GetStringWidth() or 90) + 6, 0)   -- (after its title; on a frame, as the other filters)
	f.investHint = Text(f.invest, 10, GREY)
	f.investHint:SetPoint("LEFT", 8, 0)
	f.investHint:SetText(L["e.g. 50g"])
	f.invest.token = 0
	f.invest:SetScript("OnTextChanged", function(box)
		local text = box:GetText() or ""
		f.investHint:SetShown(text == "")
		box.token = box.token + 1
		local mine = box.token
		local function Apply()
			if mine ~= box.token then return end
			local amount = M.ParseMoney(text)
			if amount ~= M.investAmount then M.investAmount = amount page:Refresh() end
		end
		if C_Timer and C_Timer.After then C_Timer.After(M.INVEST_WAIT, Apply) else Apply() end
	end)
	-- (Harvest: Reagents greyed, it's for crafts only)
	f.ownedNote = Text(f, 10, GREY)
	f.ownedNote:SetPoint("LEFT", f.owned, "LEFT", (f.owned.right or 380) + 8, 0)
	f.ownedNote:SetText(L["(crafts only)"])
	f.ownedNote:Hide()
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
	-- the two header strips (v0.4.2.6: buttons that sort, from M.COLS.craft and M.COLS.harvest, the rows' own)
	local function Resort() f.offset = 0 page:Refresh() end
	f.head = { craftStrip = M.Headers(f, -98, "craft", Resort), harvestStrip = M.Headers(f, -98, "harvest", Resort) }
	M.CRAFT_TOP = 98 + math.max(f.head.craftStrip.h, f.head.harvestStrip.h) + 2
	f.head.craft, f.head.harvest = f.head.craftStrip.buttons, f.head.harvestStrip.buttons
	Paged(f, page, M.CRAFT_TOP + M.CRAFT_STRIPS, function(i)
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(M.CRAFT_W, 24)
		r:SetPoint("TOPLEFT", M.LIST_X, -M.CRAFT_TOP - (i - 1) * M.ROW_H)
		r.cell = V.ItemCell(r, M.COLS.craft[1].w)
		r.cell:SetPoint("LEFT", M.COLS.craft[1].x, 0)
		r.cell.onClick = function(id) M.ShowHistory(page, id) end
		r.Lines = function() return r.e and C.Lines(r.e, r.house) or {} end
		r.craft = M.Cells(r, "craft")
		for k, fs in pairs(r.craft) do r[k] = fs end   -- (r.cost, r.sell, r.each, r.margin, r.listed, r.can, r.total)
		r.harvest = M.Cells(r, "harvest")
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
		local crafts = mode == "crafts"
		f.head.craftStrip:SetShown(crafts)
		f.head.harvestStrip:SetShown(not crafts)
		local item = M.COLS[crafts and "craft" or "harvest"][1]
		for _, r in ipairs(f.rows) do
			for _, fs in pairs(r.craft) do fs:SetShown(crafts) end
			for _, fs in pairs(r.harvest) do fs:SetShown(not crafts) end
			r.cell:SetWidth(item.w)
		end
		-- (v0.4.2.6) the same filters in Harvest: Reagents greyed there (crafts only); Known only and Count work
		f.owned:SetAlpha(crafts and 1 or 0.45)
		for _, box in ipairs(f.owned.boxes) do if box.EnableMouse then box:EnableMouse(crafts) end end
		f.ownedNote:SetShown(not crafts)
		-- (v0.4.2.9) the Invest Amount is for crafts: greyed and off in Harvest; (1.0.1) and with Owned (what's typed is kept)
		local on = M.InvestOn()
		f.investTitle:SetAlpha(on and 1 or 0.45) f.invest:SetAlpha(on and 1 or 0.45)
		if f.invest.EnableMouse then f.invest:EnableMouse(on) end
		if not on and f.invest.ClearFocus then f.invest:ClearFocus() end
		f.invest.off = not on
	end

	-- the list shown: another list (profession, house, scan, setting) starts on page 1
	-- (v0.4.2.6: a copy, sorted by sortList's column: the ranking and its cache stay as they are)
	local function SetList(list, key, field, sortList)
		local q = (f.filter:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		local all = list
		list = {}
		for _, e in ipairs(all) do
			if q == "" or (V.ItemData(e[field]) or ""):lower():find(q, 1, true) then list[#list + 1] = e end
		end
		f.filterCount:SetText(q ~= "" and L["%d of %d"]:format(#list, #all) or "")
		M.SortList(list, sortList)
		local ids = {}
		if M.NeedsData(sortList) then for _, e in ipairs(list) do ids[#ids + 1] = e[field] end end
		M.Fetch(f, ids, function() page:Refresh(true) end, -34)
		key = key .. "|" .. q .. "|" .. M.SortTag(sortList)
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
		if not v then fs:SetText("-") fs._loss = nil fs:SetTextColor(unpack(GREY)) return end
		fs:SetText((v < 0 and "-" or "") .. S().Money(math.abs(v)))
		fs._loss = v < 0 or nil
		fs:SetTextColor(unpack(v >= 0 and GREEN or RED))
	end
	function f.Refresh(keep)
		local house = M.House()
		f.owned.Update() f.known.Update() f.count.Update()
		f.head.craftStrip.Update() f.head.harvestStrip.Update()
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
		local bank = M.CountArg()   -- (v0.4.2.8: Craft's own Count; "none": nothing counted)
		local shown = {}
		if mode == "harvest" then
			local knownOnly = I.S.craftKnownOnly and true or false
			local h = C.Harvest(house, p.key, bank, knownOnly)
			local m = S().Market(house)
			SetList(h.list, ("harvest|%s|%s|%d|%s|%s"):format(house, tostring(p.key), m and #m.scans or 0, tostring(bank), tostring(knownOnly)), "id", "harvest")
			M.Relayout(f, f.head.harvestStrip, "harvest", "harvest", M.Samples(f.list, "harvest"))
			for i, r in ipairs(f.rows) do
				local e = i <= f.per and f.list[f.offset + i]
				r.e = nil
				if e then
					local c = r.harvest
					r.cell:SetItem(e.id, M.Lines)
					c.sell:SetText(Money(e.low))
					Signed(c.each, e.each)
					c.listed:SetText(e.low and tostring(e.units) or "-")
					c.have:SetText(tostring(e.have))
					Signed(c.total, e.total)
					shown[#shown + 1] = e.id
					r:Show()
				else
					r.cell:SetItem(nil)
					r:Hide()
				end
			end
			f.missing:SetText("") f.unlisted:SetText("")
			-- (v0.4.2.7: one short line, never into the dropdown's row; what the columns mean: the Harvest button's tooltip)
			f.status:SetText(L["%s: %d %s%s, %d listed; %d%% AH cut; full scan %s."]:format(p.name, #h.list, h.label:lower(),
				knownOnly and L[" (%d above your skill hidden)"]:format(h.above) or "", h.listed, math.floor(S().Cut(house) * 100 + 0.5), S().Age(at)))
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
		SetList(res.list or res.rows, C.CacheKey(house, p.key, opts), "out", "craft")
		M.Relayout(f, f.head.craftStrip, "craft", "craft", M.Samples(f.list, "craft"))
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
				local n, total = M.Shown(e)   -- (v0.4.2.8: from the Invest Amount when one is typed)
				r.can:SetText(tostring(n or 0))
				Signed(r.total, total)
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
		-- (v0.4.2.7: kept to one line, above the profession dropdown)
		f.status:SetText(M.CraftStatus(p.name, #p.ids, p.source == "live", res.ranked or #f.list, S().Cut(house), S().Age(at), res.unknown, res.skipped))
		f.UpdatePager()
		return shown
	end
end

-- (v0.4.2.7) the filters' tooltips: every text in one place
M.TIPS = {
	all = { L["All"], L["Every item in your last full scan."] },
	crafted = { L["Crafted"], L["Only items a profession makes."] },
	harvested = { L["Harvested"], L["Only herbs, ore, skins and fish you gather."] },
	topProf = { L["Profession"], L["Only this profession's items. * = yours."] },
	topLevel = { L["Level"], L["Only items needing skill in this range. Items with no known level are left out."] },
	search = { L["Search"], L["Show only names containing this text. Shift-click an item to fill it in."] },
	bags = { L["Bags only"], L["Count only what's in your bags."] },
	bank = { L["Bags + bank"], L["Count your bags and your bank (as you last saw it)."] },
	day = { L["1 day"], L["Prices over the last 24 hours."] },
	week = { L["7 days"], L["Prices over the last 7 days."] },
	craftProf = { L["Profession"], L["Pick a profession. * = yours."] },
	crafts = { L["Crafts"], L["What this profession makes, with cost and profit."] },
	harvest = { L["Harvest"], L["What this profession gathers. Sell at: the AH's lowest; profit: that less the AH's cut (no cost)."] },
	filter = { L["Filter by name"], L["Show only names containing this text. Shift-click an item to fill it in."] },
	market = { L["Market"], L["Price every reagent at the AH's lowest, or a vendor's if cheaper."] },
	free = { L["Owned"], L["Reagents you have (per Count) cost nothing; the rest at market price. Can make: what yours make. The Invest Amount is off (greyed)."] },
	knownCrafts = { L["Known only"], L["Only recipes you have learned."] },
	knownHarvest = { L["Known only"], L["Hide what's above your skill. Items with no level data stay."] },
	craftCount = { L["Count"], L["What Can make, Have and owned reagents count: None (buy everything), your bags, or bags and bank (as last seen). With Reagents: Market it's greyed and None (Owned brings your choice back)."] },
	invest = { L["Invest Amount"], L["Gold to invest in each craft, with Reagents: Market: 50g, 1g 20s, or a number (gold). Can make and Total then show what it buys, on every row. Greyed with Owned and in Harvest (what you typed is kept). Not saved."] },
	Alliance = { L["Alliance"], L["Prices from the Alliance Auction House (your scans there)."] },
	Horde = { L["Horde"], L["Prices from the Horde Auction House (your scans there)."] },
	Neutral = { L["Neutral"], L["The goblin Auction House in Booty Bay, Gadgetzan and Everlook, shared by Alliance and Horde. Its own prices (your scans there); it keeps 15% of a sale."] },
}
local function Tip(w, key) local t = M.TIPS[key] return V.Tip(w, t[1], t[2]) end
M.TIP_ON = {
	top = function(f)
		for _, b in ipairs(f.kinds) do Tip(b, b.kind == "all" and "all" or b.kind == "craft" and "crafted" or "harvested") end
		Tip(f.prof, "topProf") Tip(f.level, "topLevel")
	end,
	results = function(f) Tip(f.search, "search") end,
	mine = function(f) Tip(f.scope.boxes[1], "bags") Tip(f.scope.boxes[2], "bank") end,
	history = function(f) Tip(f.range.boxes[1], "day") Tip(f.range.boxes[2], "week") end,
	craft = function(f)
		Tip(f.drop, "craftProf") Tip(f.modeCrafts, "crafts") Tip(f.modeHarvest, "harvest") Tip(f.filter, "filter")
		for _, b in ipairs(f.owned.boxes) do Tip(b, b.value) end
		V.Tip(f.known, L["Known only"], function() local t = M.TIPS[M.craftMode == "harvest" and "knownHarvest" or "knownCrafts"] return t[2] end)
		Tip(f.countDrop, "craftCount") Tip(f.invest, "invest")
	end,
}

local BUILD = { top = BuildTop, mine = BuildMine, history = BuildHistory, results = BuildResults, craft = BuildCraft }

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

function V.BuildMarket(page)
	V.Header(page, L["AH Market"])
	page.status = Text(page, 11)
	page.status:SetPoint("TOPLEFT", 14, -36)
	page.status:SetPoint("RIGHT", page, "RIGHT", -250, 0)
	page.status:SetJustifyH("LEFT")
	page.hint = Text(page, 11, GOLD)
	page.hint:SetPoint("TOPLEFT", 14, -52)
	page.hint:SetPoint("RIGHT", page, "RIGHT", -14, 0)
	page.hint:SetJustifyH("LEFT")
	-- (v0.4.2.7) Alliance | Horde | Neutral, each lit when picked (a house with no scan yet: dimmer)
	page.houseButtons = {}
	for k, h in ipairs(M.HOUSES) do
		local b = V.Button(page, L[h], 76, 20, function() I.S.marketHouse, M.house = h, nil page:Refresh() end)
		b:SetPoint("TOPRIGHT", -10 - (#M.HOUSES - k) * 80, -8)
		b.house = h
		Tip(b, h)
		page.houseButtons[k] = b
	end
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
		if M.TIP_ON[key] then M.TIP_ON[key](f) end
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
		local have = {}
		for _, h in ipairs(houses) do have[h] = true end
		for _, b in ipairs(self.houseButtons) do
			T.Skin(b, 0.9, b.house == house and GOLD or T.BRONZE)
			b:SetAlpha((have[b.house] or b.house == house) and 1 or 0.6)
		end
		for _, b in ipairs(self.subButtons) do T.Skin(b, 0.9, b.key == self.current and GOLD or T.BRONZE) end
		local f = self:Sub(self.current)
		f:Show()
		S().shown = f.Refresh(keep) or {}
	end
	page:ShowSub("top")
end
