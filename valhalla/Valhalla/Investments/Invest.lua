--------------------------------------------------------------------------------
-- Investments (v0.3.0, v0.3.1): the module behind the Valhalla window's tabs (Tabs.lua), Smart Vendor and the
-- Shopping List (Views.lua), the merchant's highlights (Merchant.lua) and the Auction House's shopping
-- list (AHPanel.lua). This file: the saved data, what you have (bags live, the bank as last seen, what's
-- in the mail), what you want and need (bought: off the list, with Undo; "Keep stocked": a standing target),
-- the merchants' wares, the diagnostic (/valhalla invest diag and Settings' buttons), and the slash commands.
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
	tabPos = "bottom",                                          -- tabPos: "bottom" | "top" | "side"
	countBank = true, countAlts = false,
	hiVendor = true, greyAlpha = 0.6, showNeed = true,
	ahPanel = true, ahPanelMin = false,                         -- (the AH's list: shown; minimized to its small button)
	graphStyle = "lines",                                       -- Phase D: "lines" | "bars" (kept now, drawn later)
	-- Phase C (kept now so saves carry them): the AH market view
	panels = { trending = true, vendorVsAH = true, craft = true, graph = true },
	trendDays = 7, minScans = 3, priceSource = "min", keepDays = 14, maxSnapsPerItem = 60, ahCut = true,
}
I.CATS = { "mat", "reagent", "gear" }
I.CAT_NAME = { mat = L["Profession Mat"], reagent = L["Reagent"], gear = L["Gear Upgrade"] }
I.DIAG_KEEP = 10
I.RETIRED = { "rememberTab", "tab", "ahOneClick" }              -- (settings v0.3.1 took out: cleared from saves)
I.MAIL_DAYS = 30                                                -- (the game returns unopened mail after 30 days)
I.UNDO_KEEP = 5
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

-- ValhallaInvestDB: { v, settings, diag = { ... }, account = { bank, bankSeen, bankInfo },
--   realms = { [realm] = { chars = { [name] = { bags, bank, bankSeen, bankInfo, want = { [itemID] = { want, cat, keep, short } },
--     mail = { [itemID] = { n, t, bought } } } }, merchants = { [npcID] = { name, items = { [itemID] = price } } } } } }
function I.InitDB()
	local db = type(_G.ValhallaInvestDB) == "table" and _G.ValhallaInvestDB or {}
	_G.ValhallaInvestDB = db
	db.v = db.v or 1
	db.settings = Fill(type(db.settings) == "table" and db.settings or {}, I.SETTINGS)
	for _, k in ipairs(I.RETIRED) do db.settings[k] = nil end
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
	c.mail = c.mail or {}
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

-- the bank's containers: the tab data C_Bank gives (on Forever its first, free tab is the bank itself, then
-- the bags bought: Camelot's BankFrame), and every bank tab bag that has slots, so the bank's own first tab
-- is read even if the tab data leaves it out. (Slots read 0 while the bank is closed.)
function I.BankBags(bankType)
	local ids, seen = {}, {}
	local function Add(id) if id and not seen[id] then seen[id] = true ids[#ids + 1] = id end end
	local data = C_Bank and C_Bank.FetchPurchasedBankTabData and Call(C_Bank.FetchPurchasedBankTabData, bankType)
	if type(data) == "table" then
		for _, t in ipairs(data) do if type(t) == "table" and t.ID then Add(t.ID) end end
	end
	if Enum and Enum.BagIndex then
		local prefix = bankType == (Enum.BankType and Enum.BankType.Account) and "AccountBankTab_" or "CharacterBankTab_"
		for i = 1, 9 do
			local id = Enum.BagIndex[prefix .. i]
			if id and not seen[id] and (Call(C_Container and C_Container.GetContainerNumSlots, id) or 0) > 0 then Add(id) end
		end
	end
	return ids
end

-- what a read found: tabs, slots, kinds of item, items
local function Info(ids, items)
	local slots, kinds, total = 0, 0, 0
	for _, b in ipairs(ids) do slots = slots + (Call(C_Container and C_Container.GetContainerNumSlots, b) or 0) end
	for _, n in pairs(items) do kinds = kinds + 1 total = total + n end
	return { tabs = #ids, slots = slots, kinds = kinds, items = total }
end

function I.SnapshotBank()
	if not (I.char and I.bankOpen) then return false end
	local BT = Enum and Enum.BankType or {}
	local ids = I.BankBags(BT.Character or 0)
	I.char.bank = ReadBags(ids)
	I.char.bankSeen = Now()
	I.char.bankBags = ids
	I.char.bankInfo = Info(ids, I.char.bank)
	I.char.bankInfo.via = I.bankVia
	if BT.Account and (Call(C_Bank and C_Bank.CanViewBank, BT.Account)) then
		local aids = I.BankBags(BT.Account)
		I.db.account.bank = ReadBags(aids)
		I.db.account.bankSeen = Now()
		I.db.account.bankInfo = Info(aids, I.db.account.bank)
	end
	return true
end

-- the bank opening: BANKFRAME_OPENED, or the banker interaction (PLAYER_INTERACTION_MANAGER_FRAME_SHOW),
-- whichever comes first; the other is the same visit. Said once per visit in chat, with the counts.
I.bankEvents = {}
function I.IsBanker(t)
	local P = Enum and Enum.PlayerInteractionType
	if P and P.Banker then return t == P.Banker or t == P.CharacterBanker or t == P.AccountBanker end
	return t == 8 or t == 67 or t == 68
end

function I.BankOpened(via)
	I.bankEvents[via] = (I.bankEvents[via] or 0) + 1
	if I.bankOpen then
		I.SnapshotBank() I.Reconcile() I.Changed()
		return
	end
	I.bankOpen, I.bankVia, I.bankAnnounced = true, via, false
	I.SnapshotBank()
	I.Reconcile()
	I.Changed()
	-- (said a moment later: the tabs' items can arrive just after the bank opens)
	if C_Timer and C_Timer.After then
		C_Timer.After(1, function()
			if I.bankOpen then I.SnapshotBank() I.Reconcile() I.Changed() end
			I.AnnounceBank()
		end)
	end
end

function I.BankClosed()
	if not I.bankOpen then return end
	I.SnapshotBank()
	I.bankOpen = false
	I.AnnounceBank()
	I.Changed()
end

function I.AnnounceBank()
	if I.bankAnnounced or not I.char then return end
	I.bankAnnounced = true
	local c = I.char.bankInfo or {}
	if (c.tabs or 0) == 0 then
		ns:Print("%s", L["Bank opened, but none of its tabs could be read. Please: Investments > Settings > Run diagnostic, then /reload."])
		return
	end
	local msg = L["Bank counted: %d items (%d kinds) in %d tabs."]:format(c.items or 0, c.kinds or 0, c.tabs or 0)
	local a = I.db.account.bankInfo
	if a and (a.tabs or 0) > 0 and I.db.account.bankSeen == I.char.bankSeen then
		msg = msg .. " " .. L["Warband bank: %d items."]:format(a.items or 0)
	end
	ns:Print("%s", msg)
end

--------------------------------------------------------------------------------
-- In the mail: what you bought at the Auction House comes by mail. Counted toward what you have (so it
-- isn't bought twice) until it reaches your bags; the mailbox, when open, says what's really there.
--------------------------------------------------------------------------------

function I.MailOf(id)
	local m = I.char and I.char.mail[id]
	return m and m.n or 0
end

function I.AddMail(id, n)
	id, n = tonumber(id), tonumber(n) or 1
	if not (id and I.char and I.char.want[id]) or n <= 0 then return false end
	local m = I.char.mail[id] or { n = 0 }
	m.n = m.n + n
	m.t = Now()
	m.bought = Now()
	I.char.mail[id] = m
	return true
end

-- items reaching the bags come off what's in the mail; old mail (returned by now) is dropped
function I.MailArrived(old, new)
	for id, m in pairs(I.char.mail) do
		local gain = (new[id] or 0) - (old[id] or 0)
		if gain > 0 then m.n = m.n - gain end
		if m.n <= 0 or (m.t and Now() - m.t > I.MAIL_DAYS * 86400) then I.char.mail[id] = nil end
	end
end

-- the mailbox open: what's in it, counted (purchases of the last 5 minutes may not be delivered yet: kept)
function I.ReadInbox()
	if not (I.char and GetInboxNumItems and GetInboxItem) then return false end
	local n = Call(GetInboxNumItems) or 0
	local found = {}
	local per = _G.ATTACHMENTS_MAX_RECEIVE or 16
	for i = 1, n do
		for j = 1, per do
			local _, id, _, count = Call(GetInboxItem, i, j)
			if id then found[id] = (found[id] or 0) + (count or 1) end
		end
	end
	local now = Now()
	local function Fresh(m) return m.bought and now - m.bought < 300 end
	for id, m in pairs(I.char.mail) do
		if not found[id] and not Fresh(m) then I.char.mail[id] = nil end
	end
	for id, count in pairs(found) do
		if I.char.want[id] then
			local m = I.char.mail[id]
			if m then
				m.n = Fresh(m) and math.max(m.n, count) or count
			else
				I.char.mail[id] = { n = count, t = now }
			end
		end
	end
	return true
end

-- how many of an item you have: bags + bank (+ the warband bank) (+ your other characters on this realm)
-- (+ what's in the mail)
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
	local mail = I.MailOf(id)
	return bags + bank + alts + mail, bags, bank, alts, mail
end

--------------------------------------------------------------------------------
-- What you want, and what you need
--------------------------------------------------------------------------------

-- still short of it, counting what's in hand only (the mail isn't, yet)
function I.ShortOf(id)
	local w = I.char and I.char.want[id]
	if not w then return 0 end
	local have, _, _, _, mail = I.Have(id)
	return math.max(0, w.want - (have - mail))
end

function I.Want(id, n, cat, keep)
	id = tonumber(id)
	if not (id and I.char) then return false end
	n = math.max(1, math.floor(tonumber(n) or 1))
	local w = I.char.want[id] or {}
	w.want = n
	w.cat = (cat == "mat" or cat == "reagent" or cat == "gear") and cat or w.cat or "mat"
	w.added = w.added or Now()
	w.name = Call(GetItemInfo, id) or w.name
	if keep ~= nil then w.keep = keep and true or nil end
	I.char.want[id] = w
	w.short = I.ShortOf(id) > 0 or nil
	I.Changed()
	return true
end

function I.Unwant(id)
	id = tonumber(id)
	if not (id and I.char and I.char.want[id]) then return false end
	I.char.want[id] = nil
	I.char.mail[id] = nil
	I.Changed()
	return true
end

function I.SetWantCount(id, n)
	local w = I.char and I.char.want[id]
	if not w then return end
	w.want = math.max(1, math.floor(tonumber(n) or w.want))
	w.short = I.ShortOf(id) > 0 or nil
	I.Changed()
end

-- "Keep stocked": a standing target, hidden while you have enough, back when it's used up
function I.SetKeep(id, on)
	local w = I.char and I.char.want[id]
	if not w then return end
	w.keep = on and true or nil
	I.Changed()
end

-- bought: a want you were short of that's now in hand (it reached your bags) comes off the list, with
-- Undo; "Keep stocked" ones stay. gains: { [itemID] = how many more are in the bags } (none: only notes
-- what you're short of)
I.undo = {}
function I.Reconcile(gains)
	if not I.char then return {} end
	local removed = {}
	for id, w in pairs(I.char.want) do
		if I.ShortOf(id) > 0 then
			w.short = true
		elseif w.short and gains and (gains[id] or 0) > 0 then
			w.short = nil
			if not w.keep then removed[#removed + 1] = id end
		end
	end
	table.sort(removed)
	for _, id in ipairs(removed) do
		local w = I.char.want[id]
		I.char.want[id] = nil
		I.char.mail[id] = nil
		table.insert(I.undo, { id = id, w = w })
		while #I.undo > I.UNDO_KEEP do table.remove(I.undo, 1) end
		ns:Print("%s", L["%s x%d: you have them, so it's off your list. Undo: the Undo button in Investments, or /valhalla undo."]:format(I.ItemName(id), w.want))
	end
	return removed
end

function I.LastUndo() return I.undo[#I.undo] end

function I.Undo()
	local u = table.remove(I.undo)
	if not u then return nil end
	u.w.short = nil
	I.char.want[u.id] = u.w
	I.Changed()
	return u.id
end

-- sold by a merchant you've visited (on this realm)? (its price, the merchant's name)
function I.VendorPrice(id)
	for _, m in pairs(I.realm and I.realm.merchants or {}) do
		local p = m.items and m.items[id]
		if p then return p, m.name end
	end
end

-- every wanted item: { id, name, cat, keep, want, have, bags, bank, alts, mail, need, short, source = "vendor"|"ah" }
-- (need counts the mail; short doesn't)
function I.Rows()
	local rows = {}
	for id, w in pairs(I.char and I.char.want or {}) do
		local have, bags, bank, alts, mail = I.Have(id)
		local name = I.ItemName(id)
		local price, vendor = I.VendorPrice(id)
		rows[#rows + 1] = { id = id, name = name, cat = w.cat, keep = w.keep and true or false, want = w.want, have = have,
			bags = bags, bank = bank, alts = alts, mail = mail, need = math.max(0, w.want - have),
			short = math.max(0, w.want - (have - mail)), source = price and "vendor" or "ah", price = price, vendor = vendor }
	end
	table.sort(rows, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	return rows
end

-- the shopping list: what's still needed, by where to buy it; mail = bought, on its way; done = wanted
-- items you have enough of in hand (the "Keep stocked" ones)
function I.ShoppingList()
	local list = { vendor = {}, ah = {}, mail = {}, done = 0, total = 0 }
	for _, r in ipairs(I.Rows()) do
		list.total = list.total + 1
		if r.need > 0 then table.insert(list[r.source], r)
		elseif r.short > 0 then table.insert(list.mail, r)
		else list.done = list.done + 1 end
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
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
	"ITEM_PURCHASED", "COMMODITY_PURCHASED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_FAILURE",
	"MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "PLAYER_REGEN_ENABLED",
	"GET_ITEM_INFO_RECEIVED", "REPLICATE_ITEM_LIST_UPDATE" }

local function Gains(old, new)
	local g = {}
	for id, n in pairs(new) do if n > (old[id] or 0) then g[id] = n - (old[id] or 0) end end
	return g
end

function I.OnEvent(event, a1, a2)
	if event == "BAG_UPDATE_DELAYED" then
		local old = I.char.bags
		I.CountBags()
		if I.bankOpen then I.SnapshotBank() end
		I.MailArrived(old, I.char.bags)
		I.Reconcile(Gains(old, I.char.bags))
		I.Changed()
	elseif event == "BANKFRAME_OPENED" then
		I.BankOpened("BANKFRAME_OPENED")
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		if I.IsBanker(a1) then I.BankOpened("interaction") end
	elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "BANK_TABS_CHANGED" then
		if I.bankOpen then I.SnapshotBank() I.Reconcile() I.Changed() end
	elseif event == "BANKFRAME_CLOSED" then
		I.BankClosed()
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		if I.IsBanker(a1) then I.BankClosed() end
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
	elseif event == "ITEM_PURCHASED" then
		if I.AddMail(a1, 1) then I.Changed() end
	elseif event == "COMMODITY_PURCHASED" then
		if I.AddMail(a1, a2) then I.Changed() end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_FAILURE" then
		if I.AH and I.AH.OnBrowse then I.AH.OnBrowse(event) end
	elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
		I.mailOpen = true
		if I.ReadInbox() then I.Changed() end
	elseif event == "MAIL_CLOSED" then
		I.mailOpen = false
	elseif event == "PLAYER_REGEN_ENABLED" then
		if I.AH and I.AH.waiting and I.ahOpen then I.AH.Show() end
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
		events:SetScript("OnEvent", function(_, event, a1, a2) I.OnEvent(event, a1, a2) end)
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
-- The diagnostic: Investments > Settings > Run diagnostic (or Run AH check, at the Auction House), or
-- /valhalla invest diag [ah|replicate]. What this client has and what Valhalla saw (the bank above all),
-- saved to ValhallaInvestDB.diag (the saved log: /reload writes it to disk, where it can be read back).
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
	"C_Bank.ShouldUsePlayerBagsInBank", "GetInboxNumItems", "GetInboxItem", "ToggleQuestLog", "ToggleWorldMap", "HideUIPanel",
}

local function Copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = Copy(v) end
	return o
end

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
	-- the bank: what Valhalla last read, how it knew the bank was open (this session), and now
	d.bankInfo = { open = I.bankOpen or false, via = I.bankVia, events = Copy(I.bankEvents), seen = I.char.bankSeen,
		read = Copy(I.char.bankInfo), bags = Copy(I.char.bankBags), account = Copy(I.db.account.bankInfo), accountSeen = I.db.account.bankSeen,
		playerBagsInBank = C_Bank and Call(C_Bank.ShouldUsePlayerBagsInBank) }
	local list = I.ShoppingList()
	local merchants = 0
	for _ in pairs(I.realm.merchants) do merchants = merchants + 1 end
	d.list = { wanted = list.total, buy = #list.vendor + #list.ah, mail = #list.mail, done = list.done, merchants = merchants }
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
		if I.AH and I.AH.Check then d.ah.search = I.AH.Check() end
		if arg == "replicate" and C_AuctionHouse.ReplicateItems then
			I.diagReplicate = { started = (GetTimePreciseSec and GetTimePreciseSec()) or Now(), entry = d }
			local ok, err = pcall(C_AuctionHouse.ReplicateItems)
			d.ah.replicateCalled = ok
			if not ok then d.ah.replicateError = tostring(err) I.diagReplicate = nil end
		end
	elseif arg == "replicate" or arg == "ah" then
		d.notes[#d.notes + 1] = arg .. ": only at the Auction House"
	end
	d.kind = arg ~= "" and arg or nil
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

-- the three lines in chat (the buttons in Settings)
function I.DiagSummary(d)
	local missing = 0
	for _, p in ipairs(I.DIAG_APIS) do if not d.apis[p] then missing = missing + 1 end end
	local out = {}
	out[1] = L["Diagnostic saved (%s, Valhalla %s, client %s): %d of the APIs checked missing. /reload writes it to disk."]:format(
		tostring(d.when), tostring(d.version), tostring(d.build), missing)
	local b = d.bankInfo
	local r = b.read
	if b.seen and r then
		out[2] = L["Bank: last read %s: %d items in %d tabs (via %s)%s."]:format(date and date("%b %d %H:%M", b.seen) or tostring(b.seen),
			r.items or 0, r.tabs or 0, tostring(r.via or "?"), b.open and L[", open now"] or "")
	else
		local ev = {}
		for k, n in pairs(b.events or {}) do ev[#ev + 1] = ("%s x%d"):format(k, n) end
		out[2] = L["Bank: never read on this character (bank events this session: %s)."]:format(#ev > 0 and table.concat(ev, ", ") or L["none"])
	end
	local ah = L["AH closed"]
	if d.ah then
		local s = d.ah.search or {}
		ah = L["AH open: its Search button %s"]:format(s.button and (s.blocked and L["can't be clicked for you (Enter fallback)"] or L["ready for one-click Search"]) or L["not found"])
	end
	out[3] = L["List: %d wanted, %d to buy, %d in the mail, %d done; %d merchants known; %s."]:format(d.list.wanted, d.list.buy, d.list.mail, d.list.done, d.list.merchants, ah)
	return out
end

-- Settings' buttons: kind nil (Run diagnostic) or "ah" (Run AH check)
function I.RunDiag(kind)
	if kind == "ah" and not I.ahOpen then
		ns:Print("%s", L["Run AH check: open the Auction House first."])
		return nil
	end
	local d = I.Diag(kind or "")
	for _, line in ipairs(I.DiagSummary(d)) do ns:Print("%s", line) end
	I.Changed()
	return d
end

function I.LastDiag() return I.db and I.db.diag[#I.db.diag] end

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
	local b = d.bankInfo
	out[#out + 1] = ("  bank: seen %s, open %s, via %s, events %s; read %s tabs, %s slots, %s items; warband %s items; player bags in bank %s"):format(
		tostring(b.seen), tostring(b.open), tostring(b.via), (function() local t = {} for k, n in pairs(b.events or {}) do t[#t + 1] = k .. "=" .. n end return #t > 0 and table.concat(t, ",") or "none" end)(),
		tostring(b.read and b.read.tabs), tostring(b.read and b.read.slots), tostring(b.read and b.read.items), tostring(b.account and b.account.items), tostring(b.playerBagsInBank))
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
		local s = d.ah.search
		if s then
			out[#out + 1] = ("  AH Search button: found %s, access constraints %s, scripted input forbidden %s; last search %s"):format(
				tostring(s.button), tostring(s.constraints), tostring(s.forbidden), tostring(s.last))
		end
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
--   /valhalla invest diag [ah|replicate]             what this client has, saved to the saved log
--   /valhalla undo                                   put back the last item that came off the list
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
			I.Changed()
			return
		end
		local page = ({ vendor = "vendor", list = "list", shopping = "list", market = "market", ah = "market", settings = "settings" })[sub]
		if I.Tabs then I.Tabs.Open("invest", page) end
		return
	end
	if not mod.enabled then Say(L["Investments is off. /valhalla invest on"]) return end
	if word == "undo" then
		local id = I.Undo()
		if id then Say(L["Back on your list: %s."], I.ItemName(id)) else Say("%s", L["Nothing to undo."]) end
	elseif word == "tab" then
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
		for _, r in ipairs(list.mail) do Say(L["  In the mail: %s x%d"], r.name, r.mail) end
	end
end
