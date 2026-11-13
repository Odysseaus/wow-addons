--------------------------------------------------------------------------------
-- The Investments tab's pages (v0.3.0): Smart Vendor (what you want, counted against your bags and your
-- bank as last seen), Shopping List (what's still needed, by where to buy it), AH Market (Phase C: a
-- placeholder for now) and Settings. All Valhalla's own frames, in the window's rock and bronze.
-- v0.3.1: "Bank last seen" under the page menu on every page; Smart Vendor's Mail column, "Keep stocked"
-- tick and Undo (bought items come off the list); the Shopping List's "In the mail"; Settings' Diagnostic
-- buttons. Shift-click into the boxes: Links.lua (no stack-split box when the box took the item).
-- v0.3.2: Smart Vendor is under construction; the Shopping List page builds named lists (a name, items
-- found by name, shift-click or drop, how many, Keep) and shows them below, each with what's still needed;
-- V.Picker: the active list's chooser (at a vendor, at the AH).
-- v0.3.4: Settings' Run AH check runs the AH check (Invest.lua) and shows its step.
-- v0.3.3: no Keep (buying never changes a list: lines show still needed, Done, In the mail); the picker's
-- first choice is None (no list: no highlights, nothing beside the AH), remembered.
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
}
local GOLD, BRONZE = T.GOLD, T.BRONZE
local GREEN, RED, GREY = { 0.3, 0.9, 0.3 }, { 1, 0.45, 0.3 }, { 0.6, 0.6, 0.6 }

local function Text(parent, size, color, template)
	return T.Font(parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight"), size or 12, color)
end

-- a button of our own, in the look (UI/Style.lua, v0.4.2: the red and gold one; "-", "+", "x" its square
-- ones, "<<" "<" ">" ">>" its arrows); as: another kind (dec, inc, nav, tab, item, dropdown)
function V.Button(parent, label, w, h, onClick, as)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w or 100, h or 22)
	b.text = Text(b, 12, GOLD)
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	b:SetScript("OnClick", onClick)
	if ns.Style then
		ns.Style.Button(b, as or ns.Style.AutoKind(label), w or 100, h or 22)
	else
		T.SkinFlat(b, 0.9)
		b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
		b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 1) end)
	end
	return b
end

--------------------------------------------------------------------------------
-- An item, as AH Market shows it (v0.4.0): its icon, its name in its quality's colour, and the game's own
-- tooltip on hover (shift: compared with what you wear). An item the game hasn't loaded yet shows its
-- icon at once (client data) and "Item #id" until its name arrives (Item:ContinueOnItemLoad; at most 30
-- asked at a time, only for rows on screen; a reused row never takes an old answer).
-- Clicks: shift puts its link in chat (or in the Valhalla box that has the cursor), ctrl opens the
-- dressing room, a plain click opens its History, right-click adds it to the Shopping List's builder.
-- Only the game's tooltip API is used (SetOwner, SetItemByID / SetHyperlink, AddLine, Show, Hide).
--------------------------------------------------------------------------------

V.LOAD_MAX = 30
V.loading = {}
V.loadingCount = 0
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

-- the item's name, link and quality, if the game has it
function V.ItemData(id)
	local ok, name, link, quality = pcall(GetItemInfo, id)
	if ok and name then return name, link, quality end
end

function V.QualityColor(q)
	local c = q and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

-- ask the game for an item's data once (at most LOAD_MAX at a time); done(id) when it's there
function V.LoadItem(id, done)
	if V.loading[id] then V.loading[id][#V.loading[id] + 1] = done return true end
	if V.loadingCount >= V.LOAD_MAX then
		-- (an item the game never answers for: given up after 10 seconds, so it can't hold a place)
		local now = GetTime and GetTime() or 0
		for k, w in pairs(V.loading) do
			if w.at and now - w.at > 10 then V.loading[k] = nil V.loadingCount = math.max(0, V.loadingCount - 1) end
		end
		if V.loadingCount >= V.LOAD_MAX then return false end
	end
	local Item = _G.Item
	if not (Item and Item.CreateFromItemID) then
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		return false
	end
	local ok, item = pcall(Item.CreateFromItemID, Item, id)
	if not ok or not item then return false end
	V.loading[id] = { done, at = GetTime and GetTime() or 0 }
	V.loadingCount = V.loadingCount + 1
	local ok2 = pcall(item.ContinueOnItemLoad, item, function()
		local waiting = V.loading[id]
		V.loading[id] = nil
		V.loadingCount = math.max(0, V.loadingCount - 1)
		for _, fn in ipairs(waiting or {}) do pcall(fn, id) end
	end)
	if not ok2 then V.loading[id] = nil V.loadingCount = math.max(0, V.loadingCount - 1) return false end
	return true
end

-- the game's tooltip for an item, and our lines under it
function V.ItemTooltip(owner, id, extra)
	if not (GameTooltip and id) then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local _, link = V.ItemData(id)
	if link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(link)
	elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(id) end
	-- (1.2.0) the AH lines already under every item tooltip: AH Market's own lines not added again
	if extra and I.Market and extra == I.Market.Lines and I.Tooltip and I.Tooltip.hooked == "processor" and I.Tooltip.On() then extra = nil end
	if extra then
		for _, line in ipairs(extra(id) or {}) do GameTooltip:AddLine(line, 0.7, 0.7, 0.7, true) end
	end
	GameTooltip:Show()
	if I.S.compare ~= false and IsShiftKeyDown and IsShiftKeyDown() and _G.GameTooltip_ShowCompareItem then
		pcall(_G.GameTooltip_ShowCompareItem, GameTooltip)
		V.comparing = true
	else
		V.comparing = nil
	end
end

function V.HideItemTooltip()
	if GameTooltip then
		if _G.GameTooltip_HideShoppingTooltips then pcall(_G.GameTooltip_HideShoppingTooltips, GameTooltip) end
		GameTooltip:Hide()
	end
	V.comparing = nil
end

function V.InsertLink(link)
	if not link then return false end
	if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink then return _G.ChatFrameUtil.InsertLink(link) end
	if _G.ChatEdit_InsertLink then return _G.ChatEdit_InsertLink(link) end
	return false
end

-- an item cell: cell:SetItem(id[, extra]) / cell:SetItem(nil); cell.onClick(id) for a plain click
function V.ItemCell(parent, w)
	local cell = CreateFrame("Button", nil, parent)
	cell:SetSize(w or 200, 22)
	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetSize(20, 20)
	cell.icon:SetPoint("LEFT", 0, 0)
	cell.name = Text(cell, 12)
	cell.name:SetPoint("LEFT", 24, 0)
	cell.name:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
	cell.name:SetJustifyH("LEFT")
	if cell.name.SetWordWrap then cell.name:SetWordWrap(false) end   -- (v0.4.2.7: one line; a name too long ends in "...", the tooltip has it all)
	if cell.SetHyperlinksEnabled then cell:SetHyperlinksEnabled(false) end
	if cell.RegisterForClicks then cell:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
	function cell:Paint()
		local id = self.id
		if not id then self.name:SetText("") self.icon:SetTexture(nil) return end
		self.icon:SetTexture(I.ItemIcon(id))
		local name, _, q = V.ItemData(id)
		if name then
			self.name:SetText(name .. (self.suffix or ""))   -- (1.2.0: Top 10's " ?", an unknown skill level)
			self.name:SetTextColor(V.QualityColor(q))
			self.loaded = true
		else
			self.name:SetText(L["Item #%d"]:format(id))
			self.name:SetTextColor(0.6, 0.6, 0.6)
			self.loaded = false
			local want = id
			V.LoadItem(id, function() if self.id == want then self:Paint() end end)
		end
	end
	function cell:SetItem(id, extra)
		self.id, self.extra = id, extra
		self:Paint()
		self:SetShown(id ~= nil)
	end
	cell:SetScript("OnEnter", function(self)
		if not self.id then return end
		V.ItemTooltip(self, self.id, self.extra)
		if self.RegisterEvent then self:RegisterEvent("MODIFIER_STATE_CHANGED") end
	end)
	cell:SetScript("OnLeave", function(self)
		if self.UnregisterEvent then self:UnregisterEvent("MODIFIER_STATE_CHANGED") end
		V.HideItemTooltip()
	end)
	cell:SetScript("OnEvent", function(self, event)
		if event == "MODIFIER_STATE_CHANGED" and self.id and GameTooltip and GameTooltip:IsShown() then
			if _G.GameTooltip_HideShoppingTooltips then pcall(_G.GameTooltip_HideShoppingTooltips, GameTooltip) end
			V.ItemTooltip(self, self.id, self.extra)
		end
	end)
	cell:SetScript("OnClick", function(self, button)
		local id = self.id
		if not id then return end
		local _, link = V.ItemData(id)
		link = link or ("item:%d"):format(id)
		if button == "RightButton" then
			I.DraftAdd(id)
			ns:Print("%s", L["%s: in the Shopping List's builder."]:format(V.ItemData(id) or L["Item #%d"]:format(id)))
		elseif IsShiftKeyDown and IsShiftKeyDown() then
			V.InsertLink(link)
		elseif IsControlKeyDown and IsControlKeyDown() then
			if _G.DressUpItemLink then pcall(_G.DressUpItemLink, link) end
		elseif self.onClick then
			self.onClick(id)
		end
	end)
	return cell
end

-- a tick box and its label: get() / set(v)
function V.Check(parent, label, get, set)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(16, 16)
	b.tick = b:CreateTexture(nil, "OVERLAY")
	b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.tick:SetPoint("TOPLEFT", -3, 3)
	b.tick:SetPoint("BOTTOMRIGHT", 3, -3)
	b.label = Text(b, 12)
	b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
	b.label:SetText(label)
	if ns.Style then ns.Style.Check(b, 16) else T.SkinFlat(b, 0.9) end   -- (the look's tick box, the same 16 px)
	function b.Update() b.tick:SetShown(get() and true or false) end
	b:SetScript("OnClick", function() set(not get()) b.Update() end)
	b.Update()
	return b
end

-- (v0.4.2.7) a short tooltip on a control, shown after the mouse rests on it V.TIP_DELAY seconds (moving off,
-- clicking or the control hiding cancels it). text: a string, or a function(control) for one that depends on the mode
V.TIP_DELAY = 1
function V.Tip(w, title, text)
	if not w then return w end
	w.tip = { title = title, text = text }
	if w.tipHooked or not w.HookScript then return w end
	w.tipHooked = true
	local token = 0
	local function Cancel(self)
		token = token + 1
		if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end
	w:HookScript("OnEnter", function(self)
		token = token + 1
		local mine = token
		if not (C_Timer and C_Timer.After and GameTooltip) then return end
		C_Timer.After(V.TIP_DELAY, function()
			if mine ~= token or not self:IsVisible() or (self.IsMouseOver and not self:IsMouseOver()) then return end
			local t = self.tip
			local body = type(t.text) == "function" and t.text(self) or t.text
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(t.title, 1, 0.82, 0)
			if body and body ~= "" then GameTooltip:AddLine(body, 1, 1, 1, true) end
			GameTooltip:Show()
		end)
	end)
	w:HookScript("OnLeave", Cancel)
	w:HookScript("OnMouseDown", Cancel)
	w:HookScript("OnHide", Cancel)
	return w
end

-- a label's width (v0.4.2.1: measured, the text's own; an estimate where the game can't say yet)
function V.TextWidth(fs, text)
	local w = fs and fs.GetStringWidth and fs:GetStringWidth()
	if type(w) ~= "number" or w <= 0 then w = #tostring(text or (fs and fs.GetText and fs:GetText()) or "") * 6.5 end
	return w
end

-- tick boxes in columns (v0.4.2.1): each row a title then its boxes; the boxes start where the widest title ends,
-- each column as wide as its widest label needs (the box, its art's 3 px over each side, 6 px, the label, a gap),
-- 90 at least; a label's click ticks its box too
V.COL_MIN, V.COL_GAP = 90, 33
function V.Grid(rows, x0)
	local start = x0 or 0
	for _, r in ipairs(rows) do
		if r.title then start = math.max(start, math.floor(V.TextWidth(r.title) + 16 + 0.5)) end
	end
	local cols = {}
	for _, r in ipairs(rows) do
		for k, box in ipairs(r.boxes) do
			local lw = V.TextWidth(box.label)
			box.labelW = lw
			if box.SetHitRectInsets then box:SetHitRectInsets(0, -math.floor(lw + 6), 0, 0) end
			cols[k] = math.max(cols[k] or V.COL_MIN, math.floor(lw + V.COL_GAP + 0.5))
		end
	end
	for _, r in ipairs(rows) do
		local x = start
		for k, box in ipairs(r.boxes) do
			box:ClearAllPoints()
			box:SetPoint("LEFT", r.frame, "LEFT", x, 0)
			box.col = x
			x = x + cols[k]
		end
		r.frame.right = x
	end
	return start, cols
end

-- choose one: { {value, label}, ... } (its boxes in measured columns: V.Grid)
function V.Radio(parent, label, options, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(420, 18)
	local title = Text(f, 12)
	title:SetPoint("LEFT")
	title:SetText(label)
	f.title = title
	f.boxes = {}
	for _, o in ipairs(options) do
		local box = V.Check(f, o[2], function() return get() == o[1] end, function() set(o[1]) for _, other in ipairs(f.boxes) do other.Update() end end)
		box.value = o[1]
		f.boxes[#f.boxes + 1] = box
	end
	V.Grid({ { frame = f, boxes = f.boxes } }, 150)
	function f.Update() for _, box in ipairs(f.boxes) do box.Update() end end
	return f
end

-- a pager (v0.4.2.1, every paged list's): |<  <  Page 2 of 6  >  >| ; go("first" | "prev" | "next" | "last");
-- the four the same size, the first and last one arrow with a stop bar (the look's)
local function Off(b, off)
	b.off = off and true or nil
	b:SetAlpha(off and 0.4 or 1)
end
V.Off = Off
function V.Pager(parent, go, labelW, size)
	labelW = labelW or 276
	local bw = size or 30
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(4 * bw + 3 * 4 + 6 + labelW, 20)
	p.first = V.Button(p, "<<", bw, 20, function() go("first") end)
	p.first:SetPoint("LEFT", 0, 0)
	p.prev = V.Button(p, "<", bw, 20, function() go("prev") end)
	p.prev:SetPoint("LEFT", bw + 4, 0)
	p.label = Text(p, 11, GREY)
	p.label:SetPoint("LEFT", 2 * bw + 10, 0)
	p.label:SetWidth(labelW)
	p.label:SetJustifyH("CENTER")
	p.next = V.Button(p, ">", bw, 20, function() go("next") end)
	p.next:SetPoint("LEFT", 2 * bw + 10 + labelW + 4, 0)
	p.last = V.Button(p, ">>", bw, 20, function() go("last") end)
	p.last:SetPoint("LEFT", 3 * bw + 18 + labelW, 0)
	-- cur of pages: the buttons that can't go further dimmed
	function p.Set(cur, pages, text)
		p.label:SetText(text or "")
		Off(p.first, cur <= 1) Off(p.prev, cur <= 1)
		Off(p.next, cur >= pages) Off(p.last, cur >= pages)
	end
	return p
end

-- page k's first index (0-based offset) of n things, per a page, clamped
function V.PageOffset(k, n, per)
	local pages = math.max(1, math.ceil(n / per))
	k = math.max(1, math.min(pages, k))
	return (k - 1) * per, k, pages
end

local function EditBox(parent, w)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	e:SetSize(w, 22)
	if ns.Style then ns.Style.Input(e, w, 22) else T.SkinFlat(e, 0.95) end
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
	if ns.Style then ns.Style.Title(h, 16) end
	h:SetPoint("TOPLEFT", 14, -12)
	h:SetText(text)
	return h
end

local function Trim(t) return (tostring(t or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function Wheel(f, scroll)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta) scroll(delta) end)
end
V.Text, V.EditBox, V.Header, V.Wheel, V.When = Text, EditBox, Header, Wheel, When   -- (for Market.lua)

-- "Bank last seen" (every page)
function V.BankLine()
	local seen = I.char and I.char.bankSeen
	if not seen then return L["Bank not seen yet: open your bank once so it's counted."] end
	local r = I.char.bankInfo
	if r and r.items then return L["Bank last seen: %s (%d items). Open your bank to refresh it."]:format(When(seen), r.items) end
	return L["Bank last seen: %s. Open your bank to refresh it."]:format(When(seen))
end

-- Undo: the last list deleted, or a list as it was before its last edit (shown only when there is one)
function V.UndoButton(parent)
	local b = V.Button(parent, L["Undo"], 200, 24)
	b:SetScript("OnClick", function() I.Undo() end)
	function b.Update()
		local what = I.UndoLabel()
		if what then
			b.text:SetText(L["Undo: %s"]:format(what))
			b:Show()
		else
			b:Hide()
		end
	end
	b:Hide()
	return b
end

-- which shopping list is active (at a vendor and at the Auction House): a button that opens a menu of your
-- lists; none yet: it says so and opens the Shopping List page
V.PICK_MAX = 12
local ARROW_V = ns.Style and "" or "  v"   -- (v0.4.2.1: the look's dropdown arrow says it; no trailing " v")
function V.Picker(parent, w)
	local b = V.Button(parent, "", w or 220, 22)
	local menu = CreateFrame("Frame", nil, b, "BackdropTemplate")
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(w or 220)
	menu:SetFrameStrata("DIALOG")
	if ns.Style then ns.Style.Dropdown(b, menu, w or 220, 22) else T.SkinFlat(menu, 0.98) end
	menu:EnableMouse(true)
	menu.items = {}
	for i = 1, V.PICK_MAX + 1 do
		local it = V.Button(menu, "", (w or 220) - 8, 20, nil, "item")
		it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
		it:Hide()
		menu.items[i] = it
	end
	menu:Hide()
	b.menu = menu
	function b.Update()
		local lists = I.Lists()
		local l = I.ActiveList()
		if #lists == 0 then
			b.text:SetText(L["No shopping list: build one"])
		elseif I.NoneChosen() then
			b.text:SetText(L["List: None"] .. ARROW_V)
		elseif l then
			b.text:SetText(L["List: %s"]:format(l.name) .. ARROW_V)
		else
			b.text:SetText(L["Choose a shopping list"] .. ARROW_V)
		end
		if menu:IsShown() then b.Fill() end
	end
	function b.Fill()
		local lists = I.Lists()
		local active = I.ActiveList()
		-- first: None (no list); then your lists
		local none = menu.items[1]
		none.text:SetText((I.NoneChosen() and "> " or "") .. L["None"])
		none:SetScript("OnClick", function() menu:Hide() I.SetActive(I.NONE) b.Update() end)
		none:Show()
		for i = 2, #menu.items do
			local it, l = menu.items[i], lists[i - 1]
			if l then
				it.text:SetText((active and active.id == l.id and "> " or "") .. l.name)
				it:SetScript("OnClick", function() menu:Hide() I.SetActive(l.id) b.Update() end)
				it:Show()
			else
				it:Hide()
			end
		end
		menu:SetHeight(8 + (1 + math.min(#lists, V.PICK_MAX)) * 22)
	end
	b:SetScript("OnClick", function()
		if #I.Lists() == 0 then
			menu:Hide()
			ns:Print("%s", L["No shopping list yet: build one in Investments > Shopping List."])
			if I.Tabs and I.Tabs.Open and not InCombatLockdown() then I.Tabs.Open("invest", "list") end
			return
		end
		if menu:IsShown() then menu:Hide() else b.Fill() menu:Show() end
	end)
	b.Update()
	return b
end

--------------------------------------------------------------------------------
-- Smart Vendor (v0.3.2: under construction; what it did is on the Shopping List page)
--------------------------------------------------------------------------------

local function BuildVendor(page)
	Header(page, L["Smart Vendor"])
	local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
	card:SetSize(440, 170)
	card:SetPoint("CENTER")
	T.Skin(card, 0.9)
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(40, 40)
	icon:SetPoint("TOP", 0, -16)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
	local t = Text(card, 16, GOLD, "GameFontNormalLarge")
	t:SetPoint("TOP", icon, "BOTTOM", 0, -10)
	t:SetText(L["Under construction: coming soon"])
	page.title = t
	local d = Text(card, 12)
	d:SetPoint("TOPLEFT", 18, -98)
	d:SetPoint("RIGHT", card, "RIGHT", -18, 0)
	d:SetJustifyH("LEFT")
	d:SetText(L["Making a list of what you want to buy is now on the Shopping List page: name a list, add items and how many, then Build Shopping List."])
	page.text = d
	page.Refresh = function() end
end

--------------------------------------------------------------------------------
-- Shopping List (v0.3.2): the builder above (a name, items found by name or shift-clicked in, how many;
-- Build Shopping List saves it), your saved lists below (each with what's still needed, live)
--------------------------------------------------------------------------------

V.RESULTS = 6
V.DRAFT_ROWS = 6
V.LINES = 12

local function Icon(parent, x)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetSize(18, 18)
	t:SetPoint("LEFT", x, 0)
	return t
end

local function BuildList(page)
	Header(page, L["Shopping List"])
	-- the builder
	local bh = Text(page, 13, GOLD)
	bh:SetPoint("TOPLEFT", 16, -40)
	bh:SetText(L["New list"])
	page.builderHead = bh
	local nl = Text(page, 12)
	nl:SetPoint("TOPLEFT", 16, -66)
	nl:SetText(L["Name:"])
	local name = EditBox(page, 240)
	name:SetPoint("TOPLEFT", 70, -60)
	page.name = name
	local nameHint = Text(page, 11, GREY)
	nameHint:SetPoint("LEFT", name, "RIGHT", 8, 0)
	page.nameHint = nameHint
	name:SetScript("OnTextChanged", function(self) I.DraftName(self:GetText()) end)
	name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	local sl = Text(page, 12)
	sl:SetPoint("TOPLEFT", 16, -94)
	sl:SetText(L["Item:"])
	local search = EditBox(page, 240)
	search:SetPoint("TOPLEFT", 70, -88)
	page.search = search
	local sHint = Text(page, 11, GREY)
	sHint:SetPoint("LEFT", search, "RIGHT", 8, 0)
	sHint:SetText(L["Type a name (or shift-click or drop an item here)"])
	-- what the search found: Add, or Remove if it's in the list already
	local res = CreateFrame("Frame", nil, page, "BackdropTemplate")
	res:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -2)
	res:SetSize(380, 8 + V.RESULTS * 22)
	res:SetFrameLevel((page:GetFrameLevel() or 1) + 20)
	T.Skin(res, 0.98)
	res:EnableMouse(true)
	res.rows = {}
	for i = 1, V.RESULTS do
		local r = CreateFrame("Frame", nil, res)
		r:SetHeight(20)
		r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
		r:SetPoint("RIGHT", res, "RIGHT", -4, 0)
		r.icon = Icon(r, 2)
		r.name = Text(r, 12)
		r.name:SetPoint("LEFT", 24, 0)
		r.name:SetWidth(260)
		r.name:SetJustifyH("LEFT")
		r.act = V.Button(r, L["Add"], 70, 18)
		r.act:SetPoint("RIGHT", 0, 0)
		r:Hide()
		res.rows[i] = r
	end
	res:Hide()
	page.results = res
	local function Results()
		local ids = I.SearchItems(search:GetText(), V.RESULTS)
		page.found = ids
		for i, r in ipairs(res.rows) do
			local id = ids[i]
			if id then
				r.id = id
				r.icon:SetTexture(I.ItemIcon(id))
				r.name:SetText(I.ItemName(id))
				local inDraft = I.LineOf(I.Draft(), id) ~= nil
				r.act.text:SetText(inDraft and L["Remove"] or L["Add"])
				r.act:SetScript("OnClick", function()
					if I.LineOf(I.Draft(), id) then I.DraftRemove(id) else I.DraftAdd(id) end
					Results()
				end)
				r:Show()
			else
				r.id = nil
				r:Hide()
			end
		end
		res:SetHeight(8 + math.max(1, #ids) * 22)
		res:SetShown(#ids > 0)
	end
	page.Results = Results
	search:SetScript("OnTextChanged", Results)
	local function AddTop()
		local id = (page.found and page.found[1]) or I.ParseItem(search:GetText())
		if not id then
			if Trim(search:GetText()) ~= "" then ns:Print("%s", L["No item by that name seen yet: shift-click it from your bags, drop it here, or type its item ID."]) end
			return
		end
		I.DraftAdd(id)
		search:SetText("")
		Results()
	end
	page.AddTop = AddTop
	search:SetScript("OnEnterPressed", AddTop)
	search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() Results() end)
	-- shift-click while the search box (or a quantity box) has the cursor: that item, into the list (no split box)
	local function TakeItem(_, link)
		if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return false end
		local id = I.ParseItem(link)
		if not id then return false end
		I.DraftAdd(id)
		search:SetText("")
		Results()
		return true
	end
	page.TakeItem = TakeItem
	if ns.LinkBox then ns.LinkBox(search, TakeItem) end
	local function Drop()
		if not GetCursorInfo then return end
		local kind, id = GetCursorInfo()
		if kind == "item" and id then
			if ClearCursor then ClearCursor() end
			I.DraftAdd(id)
			search:SetText("")
			Results()
		end
	end
	page.Drop = Drop
	search:SetScript("OnReceiveDrag", Drop)
	search:SetScript("OnMouseDown", function() if GetCursorInfo and GetCursorInfo() == "item" then Drop() end end)

	-- the draft's rows
	local cols = { { L["Item"], 30 }, { L["How many"], 262 }, { L["Bags"], 372 }, { L["Bank"], 422 } }
	for _, c in ipairs(cols) do
		local h = Text(page, 12, GOLD)
		h:SetPoint("TOPLEFT", c[2] - 10 + 14, -120)
		h:SetText(c[1])
	end
	page.drows = {}
	page.doffset = 0
	for i = 1, V.DRAFT_ROWS do
		local r = CreateFrame("Frame", nil, page, "BackdropTemplate")
		r:SetHeight(V.ROW_H)
		r:SetPoint("TOPLEFT", 14, -136 - (i - 1) * (V.ROW_H + 2))
		r:SetWidth(500)
		T.Skin(r, 0.55, { 0.25, 0.2, 0.15 })
		r.icon = Icon(r, 3)
		r.name = Text(r, 12)
		r.name:SetPoint("LEFT", 26, 0)
		r.name:SetWidth(220)
		r.name:SetJustifyH("LEFT")
		r.minus = V.Button(r, "-", 18, 18)
		r.minus:SetPoint("LEFT", 250, 0)
		r.qty = EditBox(r, 46)
		r.qty:SetSize(46, 18)
		r.qty:SetPoint("LEFT", 270, 0)
		r.qty:SetNumeric(true)
		r.qty:SetJustifyH("CENTER")
		local function Commit(self) if r.id then I.DraftSet(r.id, tonumber(self:GetText()) or 0) end end
		r.qty:SetScript("OnEnterPressed", function(self) Commit(self) self:ClearFocus() end)
		r.qty:SetScript("OnEditFocusLost", Commit)
		if ns.LinkBox then ns.LinkBox(r.qty, TakeItem) end
		r.plus = V.Button(r, "+", 18, 18)
		r.plus:SetPoint("LEFT", 318, 0)
		if ns.Style then ns.Style.Stepper(r.minus, r.plus, r.qty, 46, 18) end   -- (- [qty] +: the look's arrows round its box)
		r.bags = Text(r, 12)
		r.bags:SetPoint("LEFT", 362, 0)
		r.bank = Text(r, 12)
		r.bank:SetPoint("LEFT", 412, 0)
		r.remove = V.Button(r, "x", 18, 18)
		r.remove:SetPoint("RIGHT", -3, 0)
		r:Hide()
		page.drows[i] = r
	end
	page.dempty = Text(page, 12, GREY)
	page.dempty:SetPoint("TOPLEFT", 30, -142)
	page.dempty:SetWidth(520)
	page.dempty:SetJustifyH("LEFT")
	page.dempty:SetText(L["Nothing in this list yet. Find an item above (type its name, or shift-click or drop it into the box) and Add it, then set how many you need. Bags and Bank show what you have (the bank as of your last visit). Buying never changes a list: it shows what's still needed, Done, or In the mail."])
	-- (v0.4.2.1: the draft pages, no wheel: |<  <  1 of 2  >  >|, left of Clear and Build)
	page.dpager = V.Pager(page, function(k)
		local n = #I.Draft().items
		local _, cur, pages = V.PageOffset(page.doffset / V.DRAFT_ROWS + 1, n, V.DRAFT_ROWS)
		page.doffset = V.PageOffset(k == "first" and 1 or k == "prev" and cur - 1 or k == "next" and cur + 1 or pages, n, V.DRAFT_ROWS)
		page:Refresh()
	end, 150)
	page.dpager:SetPoint("TOPLEFT", 14, -136 - V.DRAFT_ROWS * (V.ROW_H + 2) - 10)
	page.dpager:Hide()
	local build = V.Button(page, L["Build Shopping List"], 170, 24, function()
		page.name:ClearFocus()
		for _, r in ipairs(page.drows) do if r.qty:HasFocus() then r.qty:ClearFocus() end end
		I.DraftName(page.name:GetText())
		I.BuildList()
	end)
	build:SetPoint("TOPLEFT", 400, -136 - V.DRAFT_ROWS * (V.ROW_H + 2) - 8)
	page.build = build
	local clear = V.Button(page, L["Clear"], 70, 24, function() I.DraftClear() page.name:SetText("") end)
	clear:SetPoint("RIGHT", build, "LEFT", -8, 0)
	page.clear = clear

	-- the saved lists
	local top = -136 - V.DRAFT_ROWS * (V.ROW_H + 2) - 44
	local lh = Text(page, 13, GOLD)
	lh:SetPoint("TOPLEFT", 16, top)
	lh:SetText(L["Your shopping lists"])
	local lsub = Text(page, 11, GREY)
	lsub:SetPoint("LEFT", lh, "RIGHT", 10, 0)
	lsub:SetText(L["Still needed, from your bags and bank. The active list glows at vendors and opens beside the Auction House (choose it there)."])
	page.lines = {}
	page.offset = 0
	page.per = V.LINES
	local function NewLine(i)
		local ln = CreateFrame("Frame", nil, page)
		ln:SetHeight(20)
		ln:SetPoint("TOPLEFT", 14, top - 20 - (i - 1) * 21)
		ln:SetPoint("RIGHT", page, "RIGHT", -14, 0)
		ln.icon = Icon(ln, 26)
		ln.name = Text(ln, 12)
		ln.name:SetPoint("LEFT", 50, 0)
		ln.name:SetJustifyH("LEFT")
		ln.where = Text(ln, 11, GREY)
		ln.where:SetPoint("LEFT", 290, 0)
		ln.count = Text(ln, 12, GOLD)
		ln.count:SetPoint("RIGHT", -130, 0)
		ln.edit = V.Button(ln, L["Edit"], 56, 18)
		ln.edit:SetPoint("RIGHT", -64, 0)
		ln.delete = V.Button(ln, L["Delete"], 60, 18)
		ln.delete:SetPoint("RIGHT", 0, 0)
		ln:Hide()
		return ln
	end
	for i = 1, page.per do page.lines[i] = NewLine(i) end
	page.undo = V.UndoButton(page)
	page.undo:SetPoint("BOTTOMRIGHT", -14, 10)
	page.empty = Text(page, 12, GREY)
	page.empty:SetPoint("TOPLEFT", 30, top - 24)
	page.empty:SetText(L["No shopping lists yet: build one above."])
	-- (v0.4.2.1: the saved lists page too, under their lines)
	page.lpager = V.Pager(page, function(k)
		local n = #(page.entries or {})
		local _, cur, pages = V.PageOffset(page.offset / page.per + 1, n, page.per)
		page.offset = V.PageOffset(k == "first" and 1 or k == "prev" and cur - 1 or k == "next" and cur + 1 or pages, n, page.per)
		page:Refresh()
	end, 150)
	page.lpager:SetPoint("TOPLEFT", 14, top - 20 - page.per * 21 - 2)
	page.lpager:Hide()
	-- (v0.4.2.1) as many lines as the page has room for (3 to 20), from its own OnSizeChanged's height: no size asked,
	-- lines made only when first needed, the pager under the last
	function page.FitLines(h)
		local per = math.max(3, math.min(20, math.floor(((h or 0) + top - 20 - 30) / 21)))
		if per == page.per then return false end
		for i = #page.lines + 1, per do page.lines[i] = NewLine(i) end
		for i = per + 1, #page.lines do page.lines[i]:Hide() end
		page.per = per
		page.offset = math.floor(page.offset / per) * per
		page.lpager:ClearAllPoints()
		page.lpager:SetPoint("TOPLEFT", 14, top - 20 - per * 21 - 2)
		return true
	end
	page:HookScript("OnSizeChanged", function(_, _, h)
		if page.fitting or not h or h <= 0 then return end
		page.fitting = true
		local ok, changed = pcall(page.FitLines, h)
		if ok and changed and page:IsShown() then ok, changed = pcall(page.Refresh, page) end
		page.fitting = nil
		if not ok then error(changed, 0) end
	end)

	function page:Refresh()
		local d = I.Draft()
		local editing = d.editing and I.ListByID(d.editing)
		self.builderHead:SetText(editing and L["Editing '%s'"]:format(editing.name) or L["New list"])
		self.build.text:SetText(editing and L["Save List"] or L["Build Shopping List"])
		if not self.name:HasFocus() and self.name:GetText() ~= (d.name or "") then
			self.name:SetScript("OnTextChanged", nil)
			self.name:SetText(d.name or "")
			self.name:SetScript("OnTextChanged", function(box) I.DraftName(box:GetText()) end)
		end
		self.nameHint:SetText(L["Empty: it's named %s"]:format(editing and editing.name or I.AutoName()))
		if self.results:IsShown() then self.Results() end
		-- the draft
		local dcur, dpages
		self.doffset, dcur, dpages = V.PageOffset(math.floor(self.doffset / V.DRAFT_ROWS) + 1, #d.items, V.DRAFT_ROWS)
		self.dempty:SetShown(#d.items == 0)
		for i, r in ipairs(self.drows) do
			local e = d.items[i + self.doffset]
			if e then
				local _, bags, bank, alts = I.Have(e.id)
				r.id = e.id
				r.icon:SetTexture(I.ItemIcon(e.id))
				r.name:SetText(I.ItemName(e.id))
				if not r.qty:HasFocus() then r.qty:SetText(tostring(e.n or 0)) end
				r.minus:SetScript("OnClick", function() I.DraftSet(e.id, (e.n or 0) - 1) end)
				r.plus:SetScript("OnClick", function() I.DraftSet(e.id, (e.n or 0) + 1) end)
				r.bags:SetText(tostring(bags + (alts or 0)))
				r.bank:SetText(I.S.countBank and tostring(bank) or "-")
				r.remove:SetScript("OnClick", function() I.DraftRemove(e.id) end)
				r:Show()
			else
				r.id = nil
				r:Hide()
			end
		end
		self.dpager:SetShown(#d.items > V.DRAFT_ROWS)
		self.dpager.Set(dcur, dpages, L["%d of %d · %d items"]:format(dcur, dpages, #d.items))
		-- the saved lists: each name, its lines beneath
		local entries = {}
		local active = I.ActiveList()
		for _, l in ipairs(I.Lists()) do
			entries[#entries + 1] = { list = l, active = active and active.id == l.id }
			local rows = I.ListRows(l)
			for _, r in ipairs(rows) do entries[#entries + 1] = { row = r } end
			if #rows == 0 then entries[#entries + 1] = { note = L["Nothing left to buy."] } end
		end
		self.entries = entries
		local lcur, lpages
		self.offset, lcur, lpages = V.PageOffset(math.floor(self.offset / self.per) + 1, #entries, self.per)
		self.lpager:SetShown(#entries > self.per)
		self.lpager.Set(lcur, lpages, L["%d of %d"]:format(lcur, lpages))
		self.empty:SetShown(#I.Lists() == 0)
		for i, ln in ipairs(self.lines) do
			local e = i <= self.per and entries[i + self.offset]
			ln.entry = e
			ln.edit:Hide()
			ln.delete:Hide()
			if not e then
				ln:Hide()
			elseif e.list then
				local l = e.list
				ln.icon:SetTexture(nil)
				ln.name:ClearAllPoints()
				ln.name:SetPoint("LEFT", 2, 0)
				ln.name:SetText(l.name .. (e.active and L["  (active)"] or ""))
				ln.name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
				ln.where:SetText(L["%d items"]:format(#l.items))
				ln.count:SetText("")
				ln.edit:SetScript("OnClick", function() I.EditList(l.id) end)
				ln.delete:SetScript("OnClick", function() I.DeleteList(l.id) end)
				ln.edit:Show()
				ln.delete:Show()
				ln:Show()
			elseif e.note then
				ln.icon:SetTexture(nil)
				ln.name:ClearAllPoints()
				ln.name:SetPoint("LEFT", 50, 0)
				ln.name:SetText(e.note)
				ln.name:SetTextColor(GREY[1], GREY[2], GREY[3])
				ln.where:SetText("")
				ln.count:SetText("")
				ln:Show()
			else
				local r = e.row
				ln.icon:SetTexture(I.ItemIcon(r.id))
				ln.name:ClearAllPoints()
				ln.name:SetPoint("LEFT", 50, 0)
				ln.name:SetText(r.name)
				ln.name:SetTextColor(1, 1, 1)
				local where = r.source == "vendor" and L["at %s"]:format(r.vendor or "?") or L["Auction House"]
				if r.need > 0 then
					if r.mail > 0 then where = where .. "; " .. L["%d in the mail"]:format(r.mail) end
					ln.count:SetText("x" .. r.need)
					ln.count:SetTextColor(RED[1], RED[2], RED[3])
				elseif r.short > 0 then
					where = L["%d in the mail (bought, not yet looted)"]:format(r.mail)
					ln.count:SetText(L["In the mail"])
					ln.count:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
				else
					ln.count:SetText(L["Done"])
					ln.count:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
				end
				ln.where:SetText(where)
				ln:Show()
			end
		end
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
	Header(page, L["Settings"])
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
	-- v0.3.5: rows laid out top to bottom, a note's height measured from its text (at the page's width), and
	-- laid out again when the page is resized or a note's text changes (no fixed heights: nothing overlaps)
	local rows, items = {}, {}
	page.rows = rows
	local function Row(w, x, h, note) rows[#rows + 1] = { w = w, x = x, h = h, note = note } return w end
	local function Section(text)
		local h = Text(body, 13, GOLD)
		h:SetText(text)
		Row(h, 16, 22)
	end
	local function Place(w, h)
		items[#items + 1] = w
		return Row(w, 26, h or 22)
	end
	local function Note(text, color, min)
		local fs = Text(body, 11, color or GREY)
		fs:SetJustifyH("LEFT")
		fs:SetText(text or "")
		Row(fs, 26, min or 16, true)
		return fs
	end
	local function Reflow()
		local width = math.max(260, math.floor((view:GetWidth() or 560) - 46))
		local y = -8
		for _, r in ipairs(rows) do
			r.w:ClearAllPoints()
			r.w:SetPoint("TOPLEFT", r.x, y)
			local h = r.h
			if r.note then
				r.w:SetWidth(width)
				local text = r.w:GetText() or ""
				local sh = text ~= "" and r.w.GetStringHeight and r.w:GetStringHeight() or 0
				h = (text == "") and 4 or math.max(r.h, math.ceil(sh or 0) + 6)
			end
			r.y, r.height = y, h
			y = y - h
		end
		body:SetHeight(-y + 10)
		Scroll(page.scroll or 0)
	end
	page.Reflow = Reflow
	local function Opt(label, key, after)
		return Place(V.Check(body, label, function() return S[key] end, function(v) S[key] = v if after then after() end I.Changed() end))
	end
	-- v0.4.2: the look (UI/Style.lua): Profession (the default) or Norse, for all of Valhalla, at once
	if ns.Style then
		Section(L["Look"])
		page.look = Place(V.Radio(body, L["Look:"], { { "profession", L["Profession"] }, { "norse", L["Norse"] } },
			function() return ns.Style.Look() end, function(v) ns.Style.SetLook(v) end))
		page.lookNote = Note(L["Profession: WoW Forever's profession window (its red and gold buttons, bronze frame). Norse: heavy bronze with corner brackets over dark iron. It changes at once, everywhere (the game's own parts, such as the close buttons and the map menu's tabs, stay the game's)."])
	end
	Section(L["Window tabs"])
	page.tabPos = Place(V.Radio(body, L["Tabs:"], { { "bottom", L["Bottom"] }, { "top", L["Top"] }, { "side", L["Side icons"] } },
		function() return S.tabPos end, function(v) S.tabPos = v if T.Layout then T.Layout() end end))
	page.tabNote = Note(L["M, L and anything else that opens the window open it on Map & Quest Log."])
	Section(L["Diagnostic"])
	local run = V.Button(body, L["Run diagnostic"], 150, 22, function() I.RunDiag() end)
	local function Tip(b, lines)
		b:HookScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			for i, l in ipairs(lines) do GameTooltip:AddLine(l, i == 1 and 1 or 1, i == 1 and 0.82 or 1, i == 1 and 0 or 1, i > 1) end
			GameTooltip:Show()
		end)
		b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	Tip(run, { L["Run diagnostic"], L["Saves what Valhalla sees (your bank above all, and which recipes can be read) and prints three lines. Then /reload writes it to disk, where it can be read back."] })
	Place(run, 26)
	page.run = run
	page.last = Note("", { 1, 1, 1 })
	page.hint = Note("", GOLD)
	page.how = Note(L["Run diagnostic saves what Valhalla sees, then /reload writes it to disk. The AH check (scan speed, at the Auction House): type /valhalla invest diag ah there; it only reads prices."])
	Section(L["Counting what you have"])
	Opt(L["Count bank items (as last seen)"], "countBank")
	Opt(L["Count my other characters' items on this realm"], "countAlts")
	Section(L["The active shopping list at vendors"])
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
	if ns.Style then ns.Style.Stepper(minus, plus) end
	GreyText()
	page.grey = { frame = grey, minus = minus, plus = plus, label = gl }
	Place(grey)
	Section(L["Auction House"])
	Opt(L["Show my Shopping List beside the Auction House"], "ahPanel", function() if I.AH then I.AH.Refresh() end end)
	Note(L["Search runs the Auction House's own search, on your click. The list's - minimizes it to a small button. Scan (AH Market's prices) is on that list too."])
	Section(L["AH Market"])
	page.speed = Place(V.Radio(body, L["Scan speed:"], { { "smooth", L["Smooth"] }, { "balanced", L["Balanced"] }, { "fast", L["Fast"] } },
		function() return S.scanSpeed end, function(v) S.scanSpeed = v end))
	Note(L["How much of each frame a full scan may use to read: Smooth 4 ms, Balanced 8 ms, Fast 12 ms (faster scans, small hitches)."])
	local days = CreateFrame("Frame", nil, body)
	days:SetSize(400, 22)
	local dl = Text(days, 12)
	dl:SetPoint("LEFT")
	local function DaysText() dl:SetText(L["Keep history: %d days"]:format(S.histDays)) end
	local dminus = V.Button(days, "-", 22, 20, function() S.histDays = math.max(1, S.histDays - 1) DaysText() if I.Scan then I.Scan.PruneAll() end I.Changed() end)
	dminus:SetPoint("LEFT", 200, 0)
	local dplus = V.Button(days, "+", 22, 20, function() S.histDays = math.min(7, S.histDays + 1) DaysText() I.Changed() end)
	dplus:SetPoint("LEFT", 226, 0)
	if ns.Style then ns.Style.Stepper(dminus, dplus) end
	DaysText()
	page.days = { frame = days, minus = dminus, plus = dplus, label = dl }
	Place(days)
	page.size = Note("", { 1, 1, 1 })
	page.dump = Opt(L["Ignore a 1c dump (a lowest price under 30% of its 7-day median)"], "dumpFilter")
	page.compare = Opt(L["Shift-hover: compare with what I wear"], "compare")
	page.ahTooltip = Opt(L["AH price on item tooltips"], "ahTooltip")   -- (1.2.0)
	local forgetAH = V.Button(body, L["Forget this house's market"], 220, 22, function()
		if I.Scan and I.Market then I.Scan.Forget((I.Market.House())) end
	end)
	Place(forgetAH, 28)
	page.forgetAH = forgetAH
	Section(L["Graphs (Phase D)"])
	page.graph = Place(V.Radio(body, L["Graph style:"], { { "lines", L["Lines"] }, { "bars", L["Bars"] } },
		function() return S.graphStyle end, function(v) S.graphStyle = v end))
	Section(L["Data"])
	local forget = V.Button(body, L["Forget the bank snapshot"], 200, 22, function()
		I.char.bank, I.char.bankSeen, I.char.bankInfo = {}, nil, nil
		I.Changed()
	end)
	Place(forget, 28)
	Note(L["Turn the tabs and Investments off: /valhalla invest off (the map is as before)."])
	Reflow()
	view:SetScript("OnSizeChanged", Reflow)
	Scroll(0)
	Wheel(page, function(delta) Scroll(page.scroll - delta * 40) end)
	page.items = items
	function page:Refresh()
		for _, w in ipairs(items) do if w.Update then w.Update() end end
		GreyText()
		local d = I.LastDiag()
		local check = I.AHCheck and I.AHCheck.run
		if check then
			self.last:SetText(L["AH check running, step %s: keep the Auction House open."]:format(tostring(check.out.step or "1/7")))
		else
			local ac = d and d.ahcheck
			self.last:SetText(d and L["Last run: %s%s"]:format(tostring(d.when), d.kind == "ah" and (ac and L[" (AH check: %s)"]:format(tostring(ac.state)) or L[" (AH check)"]) or "") or L["Last run: never"])
		end
		self.hint:SetText("")
		DaysText()
		local size = I.Scan and I.Scan.TotalSize() or 0
		self.size:SetText(L["History: %.1f MB of %d MB (one point per item an hour, the oldest scans dropped first)."]:format(size / 1048576, S.histCapMB or 3))
		Reflow()
	end
end

-- the Settings tab (v0.3.5: its own tab, right of Professions)
function V.BuildSettings(parent)
	local page = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	page:SetPoint("TOPLEFT", 8, -8)
	page:SetPoint("BOTTOMRIGHT", -8, 8)
	T.Skin(page, 0.6, nil, true)
	page.key = "settings"
	BuildSettings(page)
	I.OnChanged(function() if page:IsShown() and page:IsVisible() then page:Refresh() end end)
	return page
end

--------------------------------------------------------------------------------
-- The tab: its menu down the left and the page
--------------------------------------------------------------------------------

local BUILD = { vendor = BuildVendor, list = BuildList,
	market = function(page) return (V.BuildMarket or BuildMarket)(page) end }   -- (AH Market: Market.lua, v0.4.0; Settings: its own tab, v0.3.5)

function V.BuildInvest(parent)
	local root = CreateFrame("Frame", nil, parent)
	root:SetAllPoints()
	local nav = CreateFrame("Frame", nil, root, "BackdropTemplate")
	nav:SetPoint("TOPLEFT", 8, -8)
	nav:SetPoint("BOTTOMLEFT", 8, 8)
	nav:SetWidth(V.NAV_W)
	T.Skin(nav, 0.75, nil, true)
	root.nav, root.pages, root.navButtons = nav, {}, {}
	root.current = "list"
	for i, p in ipairs(V.PAGES) do
		local b = V.Button(nav, p.label, V.NAV_W - 12, 30, function() root:ShowPage(p.key) end, "nav")
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
		T.Skin(page, 0.6, nil, true)
		page.root = root
		page.key = key
		BUILD[key](page)
		page:Hide()
		root.pages[key] = page
		return page
	end
	root.Page = Page
	function root:ShowPage(key)
		if key == "settings" then return T.Select("settings") end   -- (v0.3.5: its own tab)
		key = key or self.current or "list"
		if not BUILD[key] then key = "list" end
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
	root:ShowPage("list")
	return root
end
