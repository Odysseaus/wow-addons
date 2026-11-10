--------------------------------------------------------------------------------
-- The Investments tab's pages (v0.3.0): Smart Vendor (what you want, counted against your bags and your
-- bank as last seen), Shopping List (what's still needed, by where to buy it), AH Market (Phase C: a
-- placeholder for now) and Settings. All Valhalla's own frames, in the window's rock and bronze.
-- v0.3.1: "Bank last seen" under the page menu on every page; Smart Vendor's Mail column, "Keep stocked"
-- tick and Undo (bought items come off the list); the Shopping List's "In the mail"; Settings' Diagnostic
-- buttons. Shift-click into the boxes: Links.lua (no stack-split box when the box took the item).
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local T = I.Tabs
local V = {}
I.Views = V

V.NAV_W = 150
V.ROW_H = 22
V.PAGES = {
	{ key = "vendor", label = L["Smart Vendor"], icon = "Interface\\Icons\\INV_Misc_Bag_10" },
	{ key = "list", label = L["Shopping List"], icon = "Interface\\Icons\\INV_Scroll_03" },
	{ key = "market", label = L["AH Market"], icon = "Interface\\Icons\\INV_Hammer_15" },
	{ key = "settings", label = L["Settings"], icon = "Interface\\Icons\\Trade_Engineering" },
}
local GOLD, BRONZE = T.GOLD, T.BRONZE
local GREEN, RED, GREY = { 0.3, 0.9, 0.3 }, { 1, 0.45, 0.3 }, { 0.6, 0.6, 0.6 }

local function Text(parent, size, color, template)
	return T.Font(parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight"), size or 12, color)
end

-- a bronze-edged button of our own
function V.Button(parent, label, w, h, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w or 100, h or 22)
	T.Skin(b, 0.9)
	b.text = Text(b, 12, GOLD)
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 1) end)
	return b
end

-- a tick box and its label: get() / set(v)
function V.Check(parent, label, get, set)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(16, 16)
	T.Skin(b, 0.9)
	b.tick = b:CreateTexture(nil, "OVERLAY")
	b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.tick:SetPoint("TOPLEFT", -3, 3)
	b.tick:SetPoint("BOTTOMRIGHT", 3, -3)
	b.label = Text(b, 12)
	b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
	b.label:SetText(label)
	function b.Update() b.tick:SetShown(get() and true or false) end
	b:SetScript("OnClick", function() set(not get()) b.Update() end)
	b.Update()
	return b
end

-- choose one: { {value, label}, ... }
function V.Radio(parent, label, options, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(420, 18)
	local title = Text(f, 12)
	title:SetPoint("LEFT")
	title:SetText(label)
	f.boxes = {}
	local x = 150
	for _, o in ipairs(options) do
		local box = V.Check(f, o[2], function() return get() == o[1] end, function() set(o[1]) for _, other in ipairs(f.boxes) do other.Update() end end)
		box:SetPoint("LEFT", f, "LEFT", x, 0)
		box.value = o[1]
		f.boxes[#f.boxes + 1] = box
		x = x + 90
	end
	function f.Update() for _, box in ipairs(f.boxes) do box.Update() end end
	return f
end

local function EditBox(parent, w)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	e:SetSize(w, 22)
	T.Skin(e, 0.95)
	e:SetFontObject(GameFontHighlight)
	e:SetTextInsets(6, 6, 0, 0)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return e
end

local function When(t)
	if not t then return L["never"] end
	return date and date("%b %d %H:%M", t) or tostring(t)
end

local function Header(parent, text)
	local h = Text(parent, 16, GOLD, "GameFontNormalLarge")
	h:SetPoint("TOPLEFT", 14, -12)
	h:SetText(text)
	return h
end

local function Wheel(f, scroll)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta) scroll(delta) end)
end

-- "Bank last seen" (every page)
function V.BankLine()
	local seen = I.char and I.char.bankSeen
	if not seen then return L["Bank not seen yet: open your bank once so it's counted."] end
	local r = I.char.bankInfo
	if r and r.items then return L["Bank last seen: %s (%d items). Open your bank to refresh it."]:format(When(seen), r.items) end
	return L["Bank last seen: %s. Open your bank to refresh it."]:format(When(seen))
end

-- Undo: the last item that came off the list (shown only when there is one)
function V.UndoButton(parent)
	local b = V.Button(parent, L["Undo"], 180, 24)
	b:SetScript("OnClick", function() I.Undo() end)
	function b.Update()
		local u = I.LastUndo()
		if u then
			b.text:SetText(L["Undo: %s"]:format(I.ItemName(u.id)))
			b:Show()
		else
			b:Hide()
		end
	end
	b:Hide()
	return b
end

--------------------------------------------------------------------------------
-- Smart Vendor
--------------------------------------------------------------------------------

V.ROWS = 12

local function BuildVendor(page)
	Header(page, L["Smart Vendor: items I want"])
	local hint = Text(page, 11, GREY)
	hint:SetPoint("TOPLEFT", 16, -36)
	hint:SetText(L["Shift-click or drop an item in the box (or type its name or item ID), how many you want, and Add. Bought: it comes off the list (Undo below); tick Keep to keep it stocked."])

	local box = EditBox(page, 240)
	box:SetPoint("TOPLEFT", 14, -56)
	page.box = box
	local count = EditBox(page, 44)
	count:SetPoint("LEFT", box, "RIGHT", 6, 0)
	count:SetNumeric(true)
	count:SetText("20")
	page.count = count
	-- shift-click while either box has the cursor: the item goes in the item box (no stack-split box)
	local function TakeItem(_, link)
		if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return false end
		box:SetText(link)
		return true
	end
	if ns.LinkBox then ns.LinkBox(box, TakeItem) ns.LinkBox(count, TakeItem) end
	page.cat = "mat"
	local catBtn = V.Button(page, I.CAT_NAME.mat, 110, 22)
	catBtn:SetPoint("LEFT", count, "RIGHT", 6, 0)
	catBtn:SetScript("OnClick", function(self)
		local idx = 1
		for i, c in ipairs(I.CATS) do if c == page.cat then idx = i end end
		page.cat = I.CATS[idx % #I.CATS + 1]
		self.text:SetText(I.CAT_NAME[page.cat])
	end)
	page.catBtn = catBtn
	local function Add()
		local id = I.ParseItem(box:GetText())
		if not id then ns:Print(L["Which item? Shift-click it into the box, drop it there, or type its item ID."]) return end
		I.Want(id, tonumber(count:GetText()) or 1, page.cat)
		box:SetText("")
		box:ClearFocus()
	end
	page.Add = Add
	local add = V.Button(page, L["Add"], 60, 22, Add)
	add:SetPoint("LEFT", catBtn, "RIGHT", 6, 0)
	box:SetScript("OnEnterPressed", Add)
	local function Drop()
		if not GetCursorInfo then return end
		local kind, id = GetCursorInfo()
		if kind == "item" and id then
			box:SetText("item:" .. id)
			if ClearCursor then ClearCursor() end
			Add()
		end
	end
	page.Drop = Drop
	box:SetScript("OnReceiveDrag", Drop)
	box:SetScript("OnMouseDown", function() if GetCursorInfo and GetCursorInfo() == "item" then Drop() end end)

	-- the table
	local cols = { { L["Item"], 30 }, { L["Category"], 230 }, { L["Want"], 340 }, { L["Bags"], 410 }, { L["Bank"], 455 },
		{ L["Mail"], 500 }, { L["Need"], 545 }, { L["Keep"], 612 } }
	for _, c in ipairs(cols) do
		local h = Text(page, 12, GOLD)
		h:SetPoint("TOPLEFT", c[2] - 10 + 14, -88)
		h:SetText(c[1])
	end
	page.rows = {}
	page.offset = 0
	for i = 1, V.ROWS do
		local r = CreateFrame("Frame", nil, page, "BackdropTemplate")
		r:SetHeight(V.ROW_H)
		r:SetPoint("TOPLEFT", 14, -104 - (i - 1) * (V.ROW_H + 2))
		r:SetPoint("RIGHT", page, "RIGHT", -14, 0)
		T.Skin(r, 0.55, { 0.25, 0.2, 0.15 })
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18)
		r.icon:SetPoint("LEFT", 3, 0)
		r.name = Text(r, 12)
		r.name:SetPoint("LEFT", 26, 0)
		r.name:SetWidth(190)
		r.name:SetJustifyH("LEFT")
		r.cat = V.Button(r, "", 100, 18)
		r.cat:SetPoint("LEFT", 216, 0)
		r.minus = V.Button(r, "-", 18, 18)
		r.minus:SetPoint("LEFT", 322, 0)
		r.want = Text(r, 12)
		r.want:SetPoint("LEFT", 344, 0)
		r.plus = V.Button(r, "+", 18, 18)
		r.plus:SetPoint("LEFT", 376, 0)
		r.bags = Text(r, 12)
		r.bags:SetPoint("LEFT", 400, 0)
		r.bank = Text(r, 12)
		r.bank:SetPoint("LEFT", 445, 0)
		r.mail = Text(r, 12)
		r.mail:SetPoint("LEFT", 490, 0)
		r.need = Text(r, 12)
		r.need:SetPoint("LEFT", 535, 0)
		r.keep = V.Check(r, "", function() return r.keepOn end, function(v) if r.id then I.SetKeep(r.id, v) end end)
		r.keep:SetPoint("LEFT", 604, 0)
		r.remove = V.Button(r, "x", 18, 18)
		r.remove:SetPoint("RIGHT", -3, 0)
		r:Hide()
		page.rows[i] = r
	end
	local foot = Text(page, 11, GREY)
	foot:SetPoint("BOTTOMLEFT", 16, 16)
	page.foot = foot
	local build = V.Button(page, L["Build Shopping List"], 160, 24, function() page.root:ShowPage("list") end)
	build:SetPoint("BOTTOMRIGHT", -14, 10)
	page.undo = V.UndoButton(page)
	page.undo:SetPoint("RIGHT", build, "LEFT", -8, 0)
	page.empty = Text(page, 12, GREY)
	page.empty:SetPoint("TOPLEFT", 30, -112)
	page.empty:SetPoint("RIGHT", page, "RIGHT", -30, 0)
	page.empty:SetJustifyH("LEFT")
	page.empty:SetText(L["Nothing wanted yet. Add an item above (shift-click it from your bags, drop it on the box, or type its name or item ID) and how many you want. Each row then shows how many you have in your Bags, in your Bank (as of your last visit: open your bank once to count it), in the Mail (bought at the Auction House, not yet looted), and how many you still Need. Bought enough? It comes off the list by itself (Undo brings it back); tick Keep to keep it stocked instead."])
	Wheel(page, function(delta) page.offset = math.max(0, page.offset - delta) page:Refresh() end)

	function page:Refresh()
		local rows = I.Rows()
		self.offset = math.min(self.offset, math.max(0, #rows - V.ROWS))
		self.empty:SetShown(#rows == 0)
		for i, r in ipairs(self.rows) do
			local d = rows[i + self.offset]
			if d then
				r.id = d.id
				r.icon:SetTexture(I.ItemIcon(d.id))
				r.name:SetText(d.name)
				r.cat.text:SetText(I.CAT_NAME[d.cat] or d.cat)
				r.cat:SetScript("OnClick", function()
					local idx = 1
					for k, c in ipairs(I.CATS) do if c == d.cat then idx = k end end
					I.Want(d.id, d.want, I.CATS[idx % #I.CATS + 1])
				end)
				r.want:SetText(tostring(d.want))
				r.minus:SetScript("OnClick", function() I.SetWantCount(d.id, d.want - 1) end)
				r.plus:SetScript("OnClick", function() I.SetWantCount(d.id, d.want + 1) end)
				r.bags:SetText(tostring(d.bags + (d.alts or 0)))
				r.bank:SetText(I.S.countBank and tostring(d.bank) or "-")
				r.mail:SetText(d.mail > 0 and tostring(d.mail) or "-")
				if d.need > 0 then
					r.need:SetText(tostring(d.need))
					r.need:SetTextColor(RED[1], RED[2], RED[3])
				elseif d.short > 0 then
					r.need:SetText(L["In mail"])
					r.need:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
				else
					r.need:SetText(d.keep and L["Stocked"] or L["Done"])
					r.need:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
				end
				r.keepOn = d.keep
				r.keep.Update()
				r.remove:SetScript("OnClick", function() I.Unwant(d.id) end)
				r:Show()
			else
				r.id = nil
				r:Hide()
			end
		end
		self.foot:SetText(V.BankLine())
		self.undo.Update()
	end
end

--------------------------------------------------------------------------------
-- Shopping List
--------------------------------------------------------------------------------

V.LINES = 16

local function BuildList(page)
	Header(page, L["Shopping List"])
	local sub = Text(page, 11, GREY)
	sub:SetPoint("TOPLEFT", 16, -36)
	sub:SetText(L["What you still need, by where to buy it. At a vendor these glow gold (the rest are greyed, still buyable); at the Auction House a list with Search buttons opens beside it. Bought at the Auction House: In the mail until you loot it. Bought enough: off the list (Undo)."])
	sub:SetPoint("RIGHT", page, "RIGHT", -14, 0)
	sub:SetJustifyH("LEFT")
	page.lines = {}
	page.offset = 0
	for i = 1, V.LINES do
		local ln = CreateFrame("Frame", nil, page)
		ln:SetHeight(20)
		ln:SetPoint("TOPLEFT", 14, -70 - (i - 1) * 21)
		ln:SetPoint("RIGHT", page, "RIGHT", -14, 0)
		ln.icon = ln:CreateTexture(nil, "ARTWORK")
		ln.icon:SetSize(18, 18)
		ln.icon:SetPoint("LEFT", 10, 0)
		ln.name = Text(ln, 12)
		ln.name:SetPoint("LEFT", 34, 0)
		ln.name:SetJustifyH("LEFT")
		ln.where = Text(ln, 11, GREY)
		ln.where:SetPoint("LEFT", 260, 0)
		ln.count = Text(ln, 12, GOLD)
		ln.count:SetPoint("RIGHT", -10, 0)
		ln:Hide()
		page.lines[i] = ln
	end
	page.progress = Text(page, 12, GOLD)
	page.progress:SetPoint("BOTTOMLEFT", 16, 16)
	page.bar = CreateFrame("Frame", nil, page, "BackdropTemplate")
	page.bar:SetSize(220, 10)
	page.bar:SetPoint("LEFT", page.progress, "RIGHT", 10, 0)
	T.Skin(page.bar, 0.9)
	page.fill = page.bar:CreateTexture(nil, "ARTWORK")
	page.fill:SetPoint("TOPLEFT", 1, -1)
	page.fill:SetPoint("BOTTOMLEFT", 1, 1)
	page.fill:SetColorTexture(GOLD[1], GOLD[2] * 0.8, 0.1, 0.9)
	page.undo = V.UndoButton(page)
	page.undo:SetPoint("BOTTOMRIGHT", -14, 10)
	page.empty = Text(page, 12, GREY)
	page.empty:SetPoint("TOPLEFT", 30, -80)
	page.empty:SetText(L["Nothing to buy: everything you want is in your bags and bank (or nothing is wanted yet)."])
	Wheel(page, function(delta) page.offset = math.max(0, page.offset - delta) page:Refresh() end)

	function page:Refresh()
		local list = I.ShoppingList()
		local entries = {}
		local HEAD = { vendor = L["Vendor"], ah = L["Auction House"], mail = L["In the mail (bought, not yet looted)"] }
		for _, src in ipairs({ "vendor", "ah", "mail" }) do
			if #list[src] > 0 then
				entries[#entries + 1] = { header = HEAD[src] }
				for _, r in ipairs(list[src]) do entries[#entries + 1] = { row = r, mailed = src == "mail" } end
			end
		end
		self.entries = entries
		self.offset = math.min(self.offset, math.max(0, #entries - V.LINES))
		self.empty:SetShown(#entries == 0)
		for i, ln in ipairs(self.lines) do
			local e = entries[i + self.offset]
			if not e then
				ln:Hide()
			elseif e.header then
				ln.icon:SetTexture(nil)
				ln.name:SetText(e.header)
				ln.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
				ln.where:SetText("")
				ln.count:SetText("")
				ln:Show()
			else
				local r = e.row
				ln.icon:SetTexture(I.ItemIcon(r.id))
				ln.name:SetText(r.name)
				ln.name:SetTextColor(1, 1, 1)
				if e.mailed then
					ln.where:SetText(L["in your mailbox"])
					ln.count:SetText(L["%d in the mail"]:format(r.mail))
				else
					local where = r.vendor and L["at %s"]:format(r.vendor) or ""
					if r.mail > 0 then where = where .. (where ~= "" and "; " or "") .. L["%d more in the mail"]:format(r.mail) end
					ln.where:SetText(where)
					ln.count:SetText("x" .. r.need)
				end
				ln:Show()
			end
		end
		self.progress:SetText(L["Done %d / %d"]:format(list.done, list.total))
		local frac = list.total > 0 and list.done / list.total or 0
		self.fill:SetWidth(math.max(1, 218 * frac))
		self.fill:SetShown(frac > 0)
		self.undo.Update()
	end
end

--------------------------------------------------------------------------------
-- AH Market (Phase C) and Settings
--------------------------------------------------------------------------------

local function BuildMarket(page)
	Header(page, L["AH Market"])
	local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
	card:SetSize(420, 170)
	card:SetPoint("CENTER")
	T.Skin(card, 0.9)
	local t = Text(card, 16, GOLD, "GameFontNormalLarge")
	t:SetPoint("TOP", 0, -16)
	t:SetText(L["Coming in Phase C"])
	local d = Text(card, 12)
	d:SetPoint("TOPLEFT", 18, -46)
	d:SetPoint("RIGHT", card, "RIGHT", -18, 0)
	d:SetJustifyH("LEFT")
	d:SetText(L["Top 10 trending from your own scans, your bags and bank at vendor price vs the AH's lowest, what your professions can craft and sell for, and a market graph. Prices come only from scans you make at the Auction House: the game keeps no price history."])
	page.Refresh = function() end
end

local function BuildSettings(page)
	Header(page, L["Investments settings"])
	local S = I.S
	-- the settings scroll (the wheel) inside the page, under its header
	local view = CreateFrame("Frame", nil, page)
	view:SetPoint("TOPLEFT", 0, -36)
	view:SetPoint("BOTTOMRIGHT", 0, 4)
	if view.SetClipsChildren then view:SetClipsChildren(true) end
	local body = CreateFrame("Frame", nil, view)
	page.view, page.body, page.scroll = view, body, 0
	local function Scroll(to)
		local max = math.max(0, (body:GetHeight() or 0) - (view:GetHeight() or 0))
		page.scroll = math.max(0, math.min(max, to))
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", view, "TOPLEFT", 0, page.scroll)
		body:SetPoint("RIGHT", view, "RIGHT", 0, 0)
	end
	local y = -8
	local items = {}
	local function Section(text)
		local h = Text(body, 13, GOLD)
		h:SetPoint("TOPLEFT", 16, y)
		h:SetText(text)
		y = y - 22
	end
	local function Place(w, h)
		w:SetPoint("TOPLEFT", 26, y)
		y = y - (h or 22)
		items[#items + 1] = w
		return w
	end
	local function Opt(label, key, after)
		return Place(V.Check(body, label, function() return S[key] end, function(v) S[key] = v if after then after() end I.Changed() end))
	end
	Section(L["Window tabs"])
	page.tabPos = Place(V.Radio(body, L["Tabs:"], { { "bottom", L["Bottom"] }, { "top", L["Top"] }, { "side", L["Side icons"] } },
		function() return S.tabPos end, function(v) S.tabPos = v if T.Layout then T.Layout() end end))
	local tabNote = Text(body, 11, GREY)
	Place(tabNote, 18)
	tabNote:SetText(L["M, L and anything else that opens the window open it on Map & Quest Log."])
	Section(L["Diagnostic"])
	local run = V.Button(body, L["Run diagnostic"], 150, 22, function() I.RunDiag() end)
	local runAH = V.Button(body, L["Run AH check"], 150, 22, function() I.RunDiag("ah") end)
	runAH:SetPoint("LEFT", run, "RIGHT", 10, 0)
	Place(run, 26)
	page.run, page.runAH = run, runAH
	local last = Text(body, 11)
	Place(last, 16)
	page.last = last
	local how = Text(body, 11, GREY)
	Place(how, 30)
	how:SetWidth(520)
	how:SetJustifyH("LEFT")
	how:SetText(L["Saves what Valhalla sees (your bank above all) and prints three lines. Then type /reload: that writes it to disk where it can be read back. Run AH check works at the Auction House."])
	Section(L["Smart Vendor"])
	Opt(L["Count bank items (as last seen)"], "countBank")
	Opt(L["Count my other characters' items on this realm"], "countAlts")
	Section(L["Shopping List at vendors"])
	Opt(L["Highlight what I need at vendors (the rest greyed, still buyable)"], "hiVendor")
	Opt(L["Show 'need N' on those items"], "showNeed")
	local grey = CreateFrame("Frame", nil, body)
	grey:SetSize(400, 22)
	local gl = Text(grey, 12)
	gl:SetPoint("LEFT")
	local function GreyText() gl:SetText(L["Grey-out strength: %d%%"]:format(math.floor(S.greyAlpha * 100 + 0.5))) end
	local minus = V.Button(grey, "-", 22, 20, function() S.greyAlpha = math.max(0.2, S.greyAlpha - 0.1) GreyText() I.Changed() end)
	minus:SetPoint("LEFT", 200, 0)
	local plus = V.Button(grey, "+", 22, 20, function() S.greyAlpha = math.min(0.9, S.greyAlpha + 0.1) GreyText() I.Changed() end)
	plus:SetPoint("LEFT", 226, 0)
	GreyText()
	page.grey = { frame = grey, minus = minus, plus = plus, label = gl }
	Place(grey)
	Section(L["Auction House"])
	Opt(L["Show my Shopping List beside the Auction House"], "ahPanel", function() if I.AH then I.AH.Refresh() end end)
	local ahNote = Text(body, 11, GREY)
	Place(ahNote, 18)
	ahNote:SetText(L["Search runs the Auction House's own search, on your click. The list's - minimizes it to a small button."])
	Section(L["Graphs (Phase D)"])
	page.graph = Place(V.Radio(body, L["Graph style:"], { { "lines", L["Lines"] }, { "bars", L["Bars"] } },
		function() return S.graphStyle end, function(v) S.graphStyle = v end))
	Section(L["Data"])
	local forget = V.Button(body, L["Forget the bank snapshot"], 200, 22, function()
		I.char.bank, I.char.bankSeen, I.char.bankInfo = {}, nil, nil
		I.Changed()
	end)
	Place(forget, 28)
	local off = Text(body, 11, GREY)
	Place(off)
	off:SetText(L["Turn the tabs and Investments off: /valhalla invest off (the map is as before)."])
	body:SetHeight(-y + 10)
	Scroll(0)
	Wheel(page, function(delta) Scroll(page.scroll - delta * 40) end)
	page.items = items
	function page:Refresh()
		for _, w in ipairs(items) do if w.Update then w.Update() end end
		GreyText()
		local d = I.LastDiag()
		self.last:SetText(d and L["Last run: %s%s"]:format(tostring(d.when), d.kind == "ah" and L[" (AH check)"] or "") or L["Last run: never"])
		local ahOn = I.ahOpen and true or false
		if runAH.SetEnabled then runAH:SetEnabled(ahOn) end
		runAH:SetAlpha(ahOn and 1 or 0.45)
	end
end

--------------------------------------------------------------------------------
-- The tab: its menu down the left and the page
--------------------------------------------------------------------------------

local BUILD = { vendor = BuildVendor, list = BuildList, market = BuildMarket, settings = BuildSettings }

function V.BuildInvest(parent)
	local root = CreateFrame("Frame", nil, parent)
	root:SetAllPoints()
	local nav = CreateFrame("Frame", nil, root, "BackdropTemplate")
	nav:SetPoint("TOPLEFT", 8, -8)
	nav:SetPoint("BOTTOMLEFT", 8, 8)
	nav:SetWidth(V.NAV_W)
	T.Skin(nav, 0.75)
	root.nav, root.pages, root.navButtons = nav, {}, {}
	root.current = "vendor"
	for i, p in ipairs(V.PAGES) do
		local b = V.Button(nav, p.label, V.NAV_W - 12, 30, function() root:ShowPage(p.key) end)
		b:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 36)
		b.text:ClearAllPoints()
		b.text:SetPoint("LEFT", 36, 0)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(22, 22)
		b.icon:SetPoint("LEFT", 7, 0)
		b.icon:SetTexture(p.icon)
		b.key = p.key
		root.navButtons[i] = b
	end
	local function Page(key)
		if root.pages[key] then return root.pages[key] end
		local page = CreateFrame("Frame", nil, root, "BackdropTemplate")
		page:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
		page:SetPoint("BOTTOMRIGHT", -8, 8)
		T.Skin(page, 0.6)
		page.root = root
		page.key = key
		BUILD[key](page)
		page:Hide()
		root.pages[key] = page
		return page
	end
	root.Page = Page
	function root:ShowPage(key)
		key = key or self.current or "vendor"
		if not BUILD[key] then key = "vendor" end
		self.current = key
		for k, p in pairs(self.pages) do if k ~= key then p:Hide() end end
		local page = Page(key)
		page:Show()
		page:Refresh()
		for _, b in ipairs(self.navButtons) do
			local on = b.key == key
			T.Skin(b, on and 0.98 or 0.9, on and GOLD or BRONZE)
		end
		self.bankLine:SetText(V.BankLine())
	end
	-- "Bank last seen" under the page menu: on every page
	root.bankLine = Text(nav, 11, GREY)
	root.bankLine:SetPoint("BOTTOMLEFT", 8, 10)
	root.bankLine:SetPoint("RIGHT", nav, "RIGHT", -8, 0)
	root.bankLine:SetJustifyH("LEFT")
	I.OnChanged(function()
		root.bankLine:SetText(V.BankLine())
		local page = root.pages[root.current]
		if page and page:IsShown() and page:IsVisible() then page:Refresh() end
	end)
	root:ShowPage("vendor")
	return root
end
