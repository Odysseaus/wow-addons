--------------------------------------------------------------------------------
-- Investments (v0.3.0): the module behind the Valhalla window's tabs (Tabs.lua), Smart Vendor and the
-- Shopping List (Views.lua), the merchant's highlights (Merchant.lua) and the Auction House's shopping
-- list (AHPanel.lua). This file: the saved data, what you have (bags live, the bank as last seen), what
-- you want and need, the merchants' wares, /valhalla invest diag, and the slash commands.
--
-- Saved: ValhallaInvestDB (its own file: a reset of the map's settings doesn't touch it; a new saved
-- variable needs a full restart of the game, not /reload). On/off: ValhallaDB.invest.enabled
-- (/valhalla invest on|off), like the other modules.
--
-- What it never does: buy, sell, post or bid for you; write on the game's frames; call anything
-- protected. Every purchase is your own click on the game's own button.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:NewModule("invest", { defaults = { enabled = true } })
local I = {}
mod.I = I
ns.Invest = I

I.SETTINGS = {
	tab = "map", rememberTab = false, tabPos = "bottom",       -- tabPos: "bottom" | "top" | "side"
	countBank = true, countAlts = false,
	hiVendor = true, greyAlpha = 0.6, showNeed = true,
	ahPanel = true, ahOneClick = false,                         -- (one click: the AH's own search runs too; off: it fills the search box)
	graphStyle = "lines",                                       -- Phase D: "lines" | "bars" (kept now, drawn later)
	-- Phase C (kept now so saves carry them): the AH market view
	panels = { trending = true, vendorVsAH = true, craft = true, graph = true },
	trendDays = 7, minScans = 3, priceSource = "min", keepDays = 14, maxSnapsPerItem = 60, ahCut = true,
}
I.CATS = { "mat", "reagent", "gear" }
I.CAT_NAME = { mat = L["Profession Mat"], reagent = L["Reagent"], gear = L["Gear Upgrade"] }
I.DIAG_KEEP = 10
I.ITEMS = { linen = 2589, copperOre = 2770, peacebloom = 2447 }   -- (diag: Linen Cloth, Copper Ore, Peacebloom)

local function Now() return time and time() or 0 end
local Value = ns.Safe and ns.Safe.Value or function(v) return v end
local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return nil end
	return Value(a), Value(b), Value(c), Value(d)
end
I.Call = Call

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------

local function Fill(t, d)
	for k, v in pairs(d) do
		if t[k] == nil then t[k] = type(v) == "table" and Fill({}, v) or v
		elseif type(v) == "table" and type(t[k]) == "table" then Fill(t[k], v) end
	end
	return t
end

-- ValhallaInvestDB: { v, settings, diag = { ... }, account = { bank, bankSeen },
--   realms = { [realm] = { chars = { [name] = { bags, bank, bankSeen, want } }, merchants = { [npcID] = { name, items = { [itemID] = price } } } } } }
function I.InitDB()
	local db = type(_G.ValhallaInvestDB) == "table" and _G.ValhallaInvestDB or {}
	_G.ValhallaInvestDB = db
	db.v = db.v or 1
	db.settings = Fill(type(db.settings) == "table" and db.settings or {}, I.SETTINGS)
	db.diag = type(db.diag) == "table" and db.diag or {}
	db.account = type(db.account) == "table" and db.account or {}
	db.realms = type(db.realms) == "table" and db.realms or {}
	local realm = Call(GetRealmName) or "?"
	local name = Call(UnitName, "player") or "?"
	local r = db.realms[realm] or {}
	db.realms[realm] = r
	r.chars = r.chars or {}
	r.merchants = r.merchants or {}
	local c = r.chars[name] or {}
	r.chars[name] = c
	c.bags = c.bags or {}
	c.bank = c.bank or {}
	c.want = c.want or {}
	I.db, I.realm, I.char, I.me = db, r, c, name
	I.S = db.settings
	return db
end

--------------------------------------------------------------------------------
-- Items: a name for an ID, an ID for what's typed (a link, "item:123", 123, or a name seen before)
--------------------------------------------------------------------------------

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
function I.ItemName(id)
	local name = Call(GetItemInfo, id)
	if name then return name, true end
	if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	local w = I.char and I.char.want[id]
	return (w and w.name) or ("item:" .. tostring(id)), false
end

function I.ItemIcon(id)
	local fn = (C_Item and C_Item.GetItemIconByID) or _G.GetItemIcon
	return Call(fn, id) or 134400   -- (the question mark)
end

function I.ParseItem(text)
	if type(text) == "number" then return text end
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	local id = text:match("item:(%d+)") or text:match("^(%d+)$")
	if id then return tonumber(id) end
	-- a name: the game's cache, then what Valhalla has seen (bags, bank, wants, merchants)
	local _, link = Call(GetItemInfo, text)
	if link then return tonumber(link:match("item:(%d+)")) end
	local low = text:lower()
	local function Seen(t) for i in pairs(t or {}) do local n = Call(GetItemInfo, i) if n and n:lower() == low then return i end end end
	local c = I.char
	if c then
		for i, w in pairs(c.want) do if w.name and w.name:lower() == low then return i end end
		local hit = Seen(c.bags) or Seen(c.bank)
		if hit then return hit end
	end
	for _, m in pairs(I.realm and I.realm.merchants or {}) do local hit = Seen(m.items) if hit then return hit end end
	return nil
end

--------------------------------------------------------------------------------
-- What you have: bags (live) and the bank (as last seen open)
--------------------------------------------------------------------------------

I.BAGS = { 0, 1, 2, 3, 4, 5 }   -- backpack, bags 1-4, the reagent bag (Enum.BagIndex 0-5)

local function ReadBags(list)
	local out = {}
	local C = C_Container
	if not C then return out end
	for _, bag in ipairs(list) do
		local n = Call(C.GetContainerNumSlots, bag) or 0
		for slot = 1, n do
			local info = Call(C.GetContainerItemInfo, bag, slot)
			if type(info) == "table" and info.itemID then
				local count = Value(info.stackCount) or 1
				out[info.itemID] = (out[info.itemID] or 0) + count
			end
		end
	end
	return out
end
I.ReadBags = ReadBags

function I.CountBags()
	if not I.char then return {} end
	I.char.bags = ReadBags(I.BAGS)
	I.char.bagsSeen = Now()
	return I.char.bags
end

-- the bank's containers: its purchased tabs (Forever's bank: C_Bank's tab data, each a bag ID), else the
-- character bank tab bag IDs that have slots
function I.BankBags(bankType)
	local ids = {}
	local data = C_Bank and C_Bank.FetchPurchasedBankTabData and Call(C_Bank.FetchPurchasedBankTabData, bankType)
	if type(data) == "table" then
		for _, t in ipairs(data) do if type(t) == "table" and t.ID then ids[#ids + 1] = t.ID end end
	end
	if #ids == 0 and Enum and Enum.BagIndex then
		local prefix = bankType == (Enum.BankType and Enum.BankType.Account) and "AccountBankTab_" or "CharacterBankTab_"
		for i = 1, 9 do
			local id = Enum.BagIndex[prefix .. i]
			if id and (Call(C_Container and C_Container.GetContainerNumSlots, id) or 0) > 0 then ids[#ids + 1] = id end
		end
	end
	return ids
end

function I.SnapshotBank()
	if not (I.char and I.bankOpen) then return false end
	local BT = Enum and Enum.BankType or {}
	I.char.bank = ReadBags(I.BankBags(BT.Character or 0))
	I.char.bankSeen = Now()
	I.char.bankBags = I.BankBags(BT.Character or 0)
	if BT.Account and (Call(C_Bank and C_Bank.CanViewBank, BT.Account)) then
		I.db.account.bank = ReadBags(I.BankBags(BT.Account))
		I.db.account.bankSeen = Now()
	end
	return true
end

-- how many of an item you have: bags + bank (+ the warband bank) (+ your other characters on this realm)
function I.Have(id)
	local S, c = I.S, I.char
	local bags = c.bags[id] or 0
	local bank = 0
	if S.countBank then
		bank = (c.bank[id] or 0) + ((I.db.account.bank or {})[id] or 0)
	end
	local alts = 0
	if S.countAlts then
		for name, o in pairs(I.realm.chars) do
			if name ~= I.me then alts = alts + (o.bags[id] or 0) + (S.countBank and (o.bank[id] or 0) or 0) end
		end
	end
	return bags + bank + alts, bags, bank, alts
end

--------------------------------------------------------------------------------
-- What you want, and what you need
--------------------------------------------------------------------------------

function I.Want(id, n, cat)
	id = tonumber(id)
	if not (id and I.char) then return false end
	n = math.max(1, math.floor(tonumber(n) or 1))
	local w = I.char.want[id] or {}
	w.want = n
	w.cat = (cat == "mat" or cat == "reagent" or cat == "gear") and cat or w.cat or "mat"
	w.added = w.added or Now()
	w.name = Call(GetItemInfo, id) or w.name
	I.char.want[id] = w
	I.Changed()
	return true
end

function I.Unwant(id)
	id = tonumber(id)
	if not (id and I.char and I.char.want[id]) then return false end
	I.char.want[id] = nil
	I.Changed()
	return true
end

function I.SetWantCount(id, n)
	local w = I.char and I.char.want[id]
	if not w then return end
	w.want = math.max(1, math.floor(tonumber(n) or w.want))
	I.Changed()
end

-- sold by a merchant you've visited (on this realm)? (its price, the merchant's name)
function I.VendorPrice(id)
	for _, m in pairs(I.realm and I.realm.merchants or {}) do
		local p = m.items and m.items[id]
		if p then return p, m.name end
	end
end

-- every wanted item: { id, name, cat, want, have, bags, bank, alts, need, source = "vendor"|"ah" }
function I.Rows()
	local rows = {}
	for id, w in pairs(I.char and I.char.want or {}) do
		local have, bags, bank, alts = I.Have(id)
		local name = I.ItemName(id)
		local price, vendor = I.VendorPrice(id)
		rows[#rows + 1] = { id = id, name = name, cat = w.cat, want = w.want, have = have, bags = bags, bank = bank, alts = alts,
			need = math.max(0, w.want - have), source = price and "vendor" or "ah", price = price, vendor = vendor }
	end
	table.sort(rows, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	return rows
end

-- the shopping list: what's still needed, by where to buy it; done = wanted items you have enough of
function I.ShoppingList()
	local list = { vendor = {}, ah = {}, done = 0, total = 0 }
	for _, r in ipairs(I.Rows()) do
		list.total = list.total + 1
		if r.need > 0 then table.insert(list[r.source], r) else list.done = list.done + 1 end
	end
	return list
end

function I.NeedOf(id)
	local w = I.char and I.char.want[id]
	if not w then return 0 end
	return math.max(0, w.want - (I.Have(id)))
end

--------------------------------------------------------------------------------
-- Merchants: what each sells (for "buy at a vendor" and the overlay)
--------------------------------------------------------------------------------

function I.NpcID()
	local guid = Call(UnitGUID, "npc")
	local id = type(guid) == "string" and guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	return tonumber(id)
end

function I.CacheMerchant()
	if not I.realm then return 0 end
	local n = Call(GetMerchantNumItems) or 0
	local npc = I.NpcID() or 0
	local m = I.realm.merchants[npc] or { items = {} }
	m.name = Call(UnitName, "npc") or m.name
	m.seen = Now()
	local count = 0
	for i = 1, n do
		local id = Call(GetMerchantItemID, i)
		if id then
			local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and Call(C_MerchantFrame.GetItemInfo, i)
			local price = type(info) == "table" and Value(info.price) or 0
			m.items[id] = price or 0
			count = count + 1
		end
	end
	if count > 0 then I.realm.merchants[npc] = m end
	return count
end

--------------------------------------------------------------------------------
-- Listeners: the views, the merchant's highlights and the AH's list repaint when anything changes
--------------------------------------------------------------------------------

I.listeners = {}
function I.OnChanged(fn) I.listeners[#I.listeners + 1] = fn end
function I.Changed()
	if not mod.enabled then return end
	for _, fn in ipairs(I.listeners) do
		local ok, err = pcall(fn)
		if not ok and geterrorhandler then geterrorhandler()(err) end
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

I.EVENTS = { "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
	"MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
	"GET_ITEM_INFO_RECEIVED", "REPLICATE_ITEM_LIST_UPDATE" }

function I.OnEvent(event, a1)
	if event == "BAG_UPDATE_DELAYED" then
		I.CountBags()
		if I.bankOpen then I.SnapshotBank() end
		I.Changed()
	elseif event == "BANKFRAME_OPENED" then
		I.bankOpen = true
		I.SnapshotBank()
		I.Changed()
	elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "BANK_TABS_CHANGED" then
		if I.bankOpen then I.SnapshotBank() I.Changed() end
	elseif event == "BANKFRAME_CLOSED" then
		if I.bankOpen then I.SnapshotBank() end
		I.bankOpen = false
	elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
		I.merchantOpen = true
		I.CacheMerchant()
		if I.Merchant then I.Merchant.Paint() end
	elseif event == "MERCHANT_CLOSED" then
		I.merchantOpen = false
		if I.Merchant then I.Merchant.HideAll() end
	elseif event == "AUCTION_HOUSE_SHOW" then
		I.ahOpen = true
		if I.AH then I.AH.Show() end
	elseif event == "AUCTION_HOUSE_CLOSED" then
		I.ahOpen = false
		if I.AH then I.AH.Hide() end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if I.char and a1 and I.char.want[a1] then
			I.char.want[a1].name = Call(GetItemInfo, a1) or I.char.want[a1].name
			I.Changed()
		end
	elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
		if I.diagReplicate then I.DiagReplicateDone() end
	end
end

local events
function mod:OnEnable()
	I.InitDB()
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", function(_, event, a1) I.OnEvent(event, a1) end)
	end
	for _, e in ipairs(I.EVENTS) do pcall(events.RegisterEvent, events, e) end
	I.CountBags()
	if I.Tabs then I.Tabs.Enable() end
	if I.Merchant then I.Merchant.Enable() end
	if I.AH then I.AH.Enable() end
end

function mod:OnDisable()
	if events then events:UnregisterAllEvents() end
	if I.Tabs then I.Tabs.Disable() end
	if I.Merchant then I.Merchant.Disable() end
	if I.AH then I.AH.Disable() end
end

function I.SetOn(on)
	on = on and true or false
	mod.db.enabled = on
	if on and not mod.enabled then
		mod.enabled = true
		mod:OnEnable()
	elseif not on and mod.enabled then
		mod.enabled = false
		mod:OnDisable()
	end
end

--------------------------------------------------------------------------------
-- /valhalla invest diag: what this client has, saved to ValhallaInvestDB.diag (the saved log: /reload
-- writes it to disk, where it can be read back)
--------------------------------------------------------------------------------

local function Has(path)
	local t = _G
	for part in path:gmatch("[^%.]+") do
		if type(t) ~= "table" then return false end
		t = t[part]
	end
	return type(t) == "function"
end

I.DIAG_APIS = {
	"C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems", "C_AuctionHouse.GetReplicateItemInfo",
	"C_AuctionHouse.SendBrowseQuery", "C_AuctionHouse.SearchForItemKeys", "C_AuctionHouse.GetItemCommodityStatus",
	"C_AuctionHouse.IsThrottledMessageSystemReady", "QueryAuctionItems", "GetAuctionItemInfo",
	"C_MerchantFrame.GetItemInfo", "GetMerchantItemID", "GetMerchantNumItems", "MerchantFrame_UpdateMerchantInfo",
	"C_Bank.FetchPurchasedBankTabData", "C_Bank.CanViewBank", "C_Container.GetContainerItemInfo", "C_Item.GetItemCount",
	"C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetFilteredRecipeIDs", "C_TradeSkillUI.GetRecipeSchematic",
	"GetInboxInvoiceInfo", "GetInboxHeaderInfo", "GetMoney", "ChatFrameUtil.InsertLink", "ChatEdit_InsertLink",
}

function I.Diag(arg)
	local d = { t = Now(), when = date and date("%Y-%m-%d %H:%M:%S") or "", version = ns.version, apis = {}, notes = {} }
	local build, buildNum, _, toc = Call(GetBuildInfo)
	d.build, d.buildNum, d.toc = build, buildNum, toc
	for _, p in ipairs(I.DIAG_APIS) do d.apis[p] = Has(p) end
	d.open = { bank = I.bankOpen or false, merchant = I.merchantOpen or false, ah = I.ahOpen or false,
		profession = (_G.ProfessionsFrame and _G.ProfessionsFrame.IsShown and Call(_G.ProfessionsFrame.IsShown, _G.ProfessionsFrame)) or false }
	-- counts with the bank closed: does GetItemCount(includeBank) know the bank?
	d.counts = {}
	local GetCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	for key, id in pairs(I.ITEMS) do
		d.counts[key] = { id = id, bagsOnly = Call(GetCount, id, false), withBank = Call(GetCount, id, true),
			withAccount = Call(GetCount, id, true, false, false, true), bagsSeen = I.char.bags[id] or 0, bankSeen = I.char.bank[id] or 0 }
	end
	if I.bankOpen then
		local BT = Enum and Enum.BankType or {}
		d.bank = { character = {}, account = {} }
		for _, b in ipairs(I.BankBags(BT.Character or 0)) do d.bank.character[#d.bank.character + 1] = { bag = b, slots = Call(C_Container.GetContainerNumSlots, b) } end
		if BT.Account then for _, b in ipairs(I.BankBags(BT.Account)) do d.bank.account[#d.bank.account + 1] = { bag = b, slots = Call(C_Container.GetContainerNumSlots, b) } end end
	end
	if I.ahOpen and C_AuctionHouse then
		d.ah = { throttleReady = Call(C_AuctionHouse.IsThrottledMessageSystemReady), commodity = {} }
		-- (commodity or not, for the first few things in your bags)
		if C_AuctionHouse.GetItemCommodityStatus and ItemLocation and ItemLocation.CreateFromBagAndSlot then
			local n = 0
			for bag = 0, 4 do
				for slot = 1, (Call(C_Container.GetContainerNumSlots, bag) or 0) do
					local info = Call(C_Container.GetContainerItemInfo, bag, slot)
					if n < 6 and type(info) == "table" and info.itemID and not d.ah.commodity[info.itemID] then
						local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
						d.ah.commodity[info.itemID] = Call(C_AuctionHouse.GetItemCommodityStatus, loc)
						n = n + 1
					end
				end
			end
		end
		if arg == "replicate" and C_AuctionHouse.ReplicateItems then
			I.diagReplicate = { started = (GetTimePreciseSec and GetTimePreciseSec()) or Now(), entry = d }
			local ok, err = pcall(C_AuctionHouse.ReplicateItems)
			d.ah.replicateCalled = ok
			if not ok then d.ah.replicateError = tostring(err) I.diagReplicate = nil end
		end
	elseif arg == "replicate" then
		d.notes[#d.notes + 1] = "replicate: only at the Auction House"
	end
	if d.open.profession and C_TradeSkillUI then
		local all = C_TradeSkillUI.GetAllRecipeIDs and Call(C_TradeSkillUI.GetAllRecipeIDs)
		local filtered = C_TradeSkillUI.GetFilteredRecipeIDs and Call(C_TradeSkillUI.GetFilteredRecipeIDs)
		d.recipes = { all = type(all) == "table" and #all or nil, filtered = type(filtered) == "table" and #filtered or nil }
	end
	local log = I.db.diag
	table.insert(log, d)
	while #log > I.DIAG_KEEP do table.remove(log, 1) end
	return d
end

function I.DiagReplicateDone()
	local r = I.diagReplicate
	I.diagReplicate = nil
	if not r then return end
	local now = (GetTimePreciseSec and GetTimePreciseSec()) or Now()
	r.entry.ah.replicateSeconds = now - r.started
	r.entry.ah.replicateCount = Call(C_AuctionHouse.GetNumReplicateItems)
	ns:Print(L["Investments diag: the AH sent %s auctions in %.1f s (saved; /reload to write it to disk)."],
		tostring(r.entry.ah.replicateCount), r.entry.ah.replicateSeconds)
end

function I.DiagLines(d)
	local out = {}
	local missing, present = {}, {}
	for _, p in ipairs(I.DIAG_APIS) do if d.apis[p] then present[#present + 1] = p else missing[#missing + 1] = p end end
	out[#out + 1] = ("Investments diag %s (Valhalla %s, client %s %s, toc %s)"):format(d.when, tostring(d.version), tostring(d.build), tostring(d.buildNum), tostring(d.toc))
	out[#out + 1] = ("  missing: %s"):format(#missing > 0 and table.concat(missing, ", ") or "none")
	out[#out + 1] = ("  open: bank %s, merchant %s, AH %s, profession %s"):format(tostring(d.open.bank), tostring(d.open.merchant), tostring(d.open.ah), tostring(d.open.profession))
	for key, c in pairs(d.counts) do
		out[#out + 1] = ("  %s (%d): bags %s, +bank %s, +warband %s; Valhalla saw bags %d, bank %d"):format(key, c.id,
			tostring(c.bagsOnly), tostring(c.withBank), tostring(c.withAccount), c.bagsSeen, c.bankSeen)
	end
	if d.bank then
		local parts = {}
		for _, b in ipairs(d.bank.character) do parts[#parts + 1] = ("%d:%s"):format(b.bag, tostring(b.slots)) end
		out[#out + 1] = "  bank bags (bag:slots): " .. (#parts > 0 and table.concat(parts, " ") or "none")
	end
	if d.ah then
		local parts = {}
		for id, s in pairs(d.ah.commodity) do parts[#parts + 1] = ("%d=%s"):format(id, tostring(s)) end
		out[#out + 1] = ("  AH: throttle ready %s; commodity status %s%s"):format(tostring(d.ah.throttleReady),
			#parts > 0 and table.concat(parts, " ") or "-", d.ah.replicateCalled and "; replicate asked (wait for its line)" or "")
	end
	if d.recipes then out[#out + 1] = ("  recipes: GetAllRecipeIDs %s, GetFilteredRecipeIDs %s"):format(tostring(d.recipes.all), tostring(d.recipes.filtered)) end
	for _, n in ipairs(d.notes) do out[#out + 1] = "  " .. n end
	out[#out + 1] = L["  Saved in ValhallaInvestDB.diag. /reload (or log out) to write it to disk."]
	return out
end

--------------------------------------------------------------------------------
-- Slash commands (Init.lua sends them here)
--   /valhalla invest [vendor|list|market|settings]   open Investments (at that page)
--   /valhalla invest on|off                          the whole tabbed window and Investments (off: the map as before)
--   /valhalla invest diag [replicate]                what this client has, saved to the saved log
--   /valhalla tab map|invest|talents|professions     switch the window's tab
--   /valhalla want <item> [count] [mat|reagent|gear], /valhalla unwant <item>, /valhalla list
--------------------------------------------------------------------------------

local function Say(fmt, ...) ns:Print(fmt, ...) end

function mod:Slash(word, arg)
	arg = arg or ""
	local low = arg:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if word == "invest" then
		local sub, rest = low:match("^(%S*)%s*(.-)$")
		if sub == "on" then I.SetOn(true) Say(L["Investments and the window's tabs: on."]) return end
		if sub == "off" then I.SetOn(false) Say(L["Investments and the window's tabs: off (the map is as before). /valhalla invest on brings them back."]) return end
		if not mod.enabled then Say(L["Investments is off. /valhalla invest on"]) return end
		if sub == "diag" then
			local d = I.Diag(rest)
			for _, line in ipairs(I.DiagLines(d)) do Say("%s", line) end
			return
		end
		local page = ({ vendor = "vendor", list = "list", shopping = "list", market = "market", ah = "market", settings = "settings" })[sub]
		if I.Tabs then I.Tabs.Open("invest", page) end
		return
	end
	if not mod.enabled then Say(L["Investments is off. /valhalla invest on"]) return end
	if word == "tab" then
		local key = ({ map = "map", invest = "invest", investments = "invest", talents = "talents", professions = "professions" })[low]
		if not key then Say(L["/valhalla tab map|invest|talents|professions"]) return end
		if I.Tabs then I.Tabs.Open(key) end
	elseif word == "want" then
		-- the item may be a link (with spaces), then an optional count and category
		local item, n, cat = arg:match("^(.-)%s+(%d+)%s+(%a+)%s*$")
		if not item then item, n = arg:match("^(.-)%s+(%d+)%s*$") end
		if not item or item == "" then item = arg end
		if not cat and item then
			local i2, c2 = item:match("^(.-)%s+(%a+)$")
			if c2 and (c2 == "mat" or c2 == "reagent" or c2 == "gear") then item, cat = i2, c2 end
		end
		local id = I.ParseItem(item)
		if not id then Say(L["Which item? Shift-click it into the command, or give its item ID: /valhalla want <item> [count] [mat|reagent|gear]"]) return end
		I.Want(id, n or (I.char.want[id] and I.char.want[id].want) or 1, cat and cat:lower())
		Say(L["Wanted: %s x%d (need %d)."], I.ItemName(id), I.char.want[id].want, I.NeedOf(id))
	elseif word == "unwant" then
		local id = I.ParseItem(arg)
		if id and I.Unwant(id) then Say(L["No longer wanted: %s."], I.ItemName(id)) else Say(L["That item isn't on your want list."]) end
	elseif word == "list" then
		local list = I.ShoppingList()
		Say(L["Shopping list (%d of %d done):"], list.done, list.total)
		for _, src in ipairs({ "vendor", "ah" }) do
			for _, r in ipairs(list[src]) do
				Say("  %s: %s x%d", src == "vendor" and L["Vendor"] or L["Auction House"], r.name, r.need)
			end
		end
	end
end
