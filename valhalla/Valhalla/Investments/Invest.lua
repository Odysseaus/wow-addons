--------------------------------------------------------------------------------
-- Investments (v0.3.0, v0.3.1): the module behind the Valhalla window's tabs (Tabs.lua), Smart Vendor and the
-- Shopping List (Views.lua), the merchant's highlights (Merchant.lua) and the Auction House's shopping
-- list (AHPanel.lua). This file: the saved data, what you have (bags live, the bank as last seen, what's
-- in the mail), what you want and need,
-- the merchants' wares, the diagnostic (/valhalla invest diag and Settings' buttons), and the slash commands.
-- v0.3.2: named shopping lists (built on the Shopping List page from a draft), one of them active for the
-- vendor's highlights and the AH's list. v0.3.3: buying never changes a list (only shown: still needed, Done,
-- In the mail); "None" can be chosen. The old want
-- list (Smart Vendor, now under construction) is kept in the save untouched; it became "My List" once.
-- v0.3.4: the AH check (Run AH check; below the diagnostic): what the coming AH Market can use, measured.
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
	-- AH Market (v0.4.0): read speed (smooth 4 / balanced 8 / fast 12 ms a frame), history days and cap,
	-- the 1c-dump filter (off: the raw lowest buyout), shift-hover compare, bags + bank in My items
	scanSpeed = "balanced", histDays = 7, histCapMB = 3, dumpFilter = false, compare = true, mineBank = true,
	-- Craft (v0.4.1): reagents "market" (all bought) | "free" (what you own costs nothing) | "vendor" (at its
	-- vendor value); only the recipes this character knows
	craftOwned = "market", craftKnownOnly = false,
}
I.CATS = { "mat", "reagent", "gear" }
I.CAT_NAME = { mat = L["Profession Mat"], reagent = L["Reagent"], gear = L["Gear Upgrade"] }
I.DIAG_KEEP = 10
I.RETIRED = { "rememberTab", "tab", "ahOneClick",               -- (settings v0.3.1 took out: cleared from saves)
	"panels", "trendDays", "minScans", "priceSource", "keepDays", "maxSnapsPerItem", "ahCut" }   -- (v0.4.0: Phase C's placeholders)
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
--   realms = { [realm] = { chars = { [name] = { bags, bank, bankSeen, bankInfo, want (v0.3.1's, kept, unused),
--     lists = { { id, name, created, items = { { id, n, name } } } }, activeList (an id or "none"), nextList, draft,
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
	I.MigrateLists(c)
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
	local c = I.char
	local w = c and c.want[id]
	if w and w.name then return w.name, false end
	for _, l in ipairs(c and c.lists or {}) do
		for _, e in ipairs(l.items) do if e.id == id and e.name then return e.name, false end end
	end
	for _, e in ipairs(c and type(c.draft) == "table" and c.draft.items or {}) do if e.id == id and e.name then return e.name, false end end
	return "item:" .. tostring(id), false
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
		I.SnapshotBank() I.Changed()
		return
	end
	I.bankOpen, I.bankVia, I.bankAnnounced = true, via, false
	I.SnapshotBank()
	I.Changed()
	-- (said a moment later: the tabs' items can arrive just after the bank opens)
	if C_Timer and C_Timer.After then
		C_Timer.After(1, function()
			if I.bankOpen then I.SnapshotBank() I.Changed() end
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
	if not (id and I.char and I.Listed(id)) or n <= 0 then return false end
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
		if I.Listed(id) then
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
-- Shopping lists (v0.3.2): a draft (the builder on the Shopping List page) saved as named lists; one of
-- them active (the vendor's highlights and the AH's list follow it). The old want list (Smart Vendor, v0.3.0
-- and v0.3.1) stays in the save as it was, untouched: read once to make "My List", never written.
--   lists = { { id, name, created, items = { { id, n, name } } } }, activeList = list id or "none",
--   draft = { name, items = { { id, n, name } }, editing = list id }
-- (v0.3.2's keep and short on lines, if saved, are left as they are and not used: v0.3.3 has no Keep.)
--------------------------------------------------------------------------------

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- the first time: the old wants become one list, "My List" (the wants themselves are left as they were)
function I.MigrateLists(c)
	if type(c.lists) == "table" then return false end
	c.lists = {}
	c.nextList = c.nextList or 1
	local ids = {}
	for id in pairs(c.want or {}) do ids[#ids + 1] = id end
	if #ids == 0 then return false end
	table.sort(ids)
	local l = { id = c.nextList, name = L["My List"], created = Now(), items = {} }
	c.nextList = c.nextList + 1
	for _, id in ipairs(ids) do
		local w = c.want[id]
		if type(w) == "table" and (tonumber(w.want) or 0) > 0 then
			l.items[#l.items + 1] = { id = id, n = math.floor(tonumber(w.want)), name = w.name }
		end
	end
	c.lists[1] = l
	c.activeList = l.id
	return true
end

function I.Lists() return I.char and I.char.lists or {} end

function I.ListByID(lid)
	for i, l in ipairs(I.Lists()) do if l.id == lid then return l, i end end
end

-- the active list (one list: that one, chosen for you); nil when there are none, several and none chosen,
-- or "None" chosen (v0.3.3: activeList = I.NONE, remembered: no list, no highlights)
I.NONE = "none"
function I.ActiveList()
	if not I.char or I.char.activeList == I.NONE then return nil end
	local l = I.char.activeList and I.ListByID(I.char.activeList)
	if l then return l end
	local lists = I.Lists()
	if #lists == 1 then I.char.activeList = lists[1].id return lists[1] end
	return nil
end

-- "None" chosen (and there are lists to choose from)
function I.NoneChosen()
	return I.char ~= nil and I.char.activeList == I.NONE and #I.Lists() > 0
end

-- a list's id, or I.NONE
function I.SetActive(lid)
	if not I.char then return false end
	if lid ~= I.NONE and not I.ListByID(lid) then return false end
	I.char.activeList = lid
	I.Changed()
	return true
end

-- on some saved list? (what's bought at the AH is followed in the mail only then)
function I.Listed(id)
	for _, l in ipairs(I.Lists()) do
		for _, e in ipairs(l.items) do if e.id == id then return true end end
	end
	return false
end

local function LineOf(l, id)
	for i, e in ipairs(l and l.items or {}) do if e.id == id then return e, i end end
end
I.LineOf = LineOf

-- how many more of an item the active list needs (the vendor's highlights)
function I.NeedOf(id)
	local e = LineOf(I.ActiveList(), id)
	if not e then return 0 end
	return math.max(0, e.n - (I.Have(id)))
end

-- sold by a merchant you've visited (on this realm)? (its price, the merchant's name)
function I.VendorPrice(id)
	for _, m in pairs(I.realm and I.realm.merchants or {}) do
		local p = m.items and m.items[id]
		if p then return p, m.name end
	end
end

-- one line, counted: { id, name, n, have, bags, bank, alts, mail, need, short, source = "vendor"|"ah", vendor }
-- (need counts the mail; short doesn't). Only shown: nothing here changes the list.
function I.LineRow(e)
	local have, bags, bank, alts, mail = I.Have(e.id)
	local price, vendor = I.VendorPrice(e.id)
	return { id = e.id, name = I.ItemName(e.id), n = e.n, want = e.n, have = have,
		bags = bags, bank = bank, alts = alts, mail = mail, need = math.max(0, e.n - have),
		short = math.max(0, e.n - (have - mail)), source = price and "vendor" or "ah", price = price, vendor = vendor }
end

-- a list's lines, counted, in the list's order
function I.ListRows(l)
	local rows = {}
	for _, e in ipairs(l and l.items or {}) do rows[#rows + 1] = I.LineRow(e) end
	return rows
end

-- a list by where to buy: what's still needed (vendor / ah), bought and on its way (mail), done (in hand)
-- (the active list when none is given)
function I.ShoppingList(l)
	l = l or I.ActiveList()
	local list = { vendor = {}, ah = {}, mail = {}, done = 0, total = 0, list = l, name = l and l.name }
	for _, r in ipairs(I.ListRows(l)) do
		list.total = list.total + 1
		if r.need > 0 then table.insert(list[r.source], r)
		elseif r.short > 0 then table.insert(list.mail, r)
		else list.done = list.done + 1 end
	end
	return list
end

-- Undo (v0.3.3): a deleted list, or the last Save List of an edit. Buying never changes a list (v0.3.3:
-- what you buy is only shown: still needed, Done, In the mail).
I.undo = {}
local function PushUndo(u)
	table.insert(I.undo, u)
	while #I.undo > I.UNDO_KEEP do table.remove(I.undo, 1) end
end

function I.LastUndo() return I.undo[#I.undo] end

-- what the last undo would put back, for its button
function I.UndoLabel(u)
	u = u or I.LastUndo()
	if not u then return nil end
	if u.kind == "list" then return L["the list '%s'"]:format(u.l.name) end
	return L["the edit of '%s'"]:format(u.name)
end

-- put the last one back: a deleted list (where it was), or a list as it was before its edit. Returns what (a label).
function I.Undo()
	local u = table.remove(I.undo)
	if not u then return nil end
	local label = I.UndoLabel(u)
	if u.kind == "list" then
		local lists = I.char.lists
		table.insert(lists, math.min(u.index, #lists + 1), u.l)
		if u.active then I.char.activeList = u.l.id end
	else
		local l = I.ListByID(u.list)
		if not l then return I.Undo() end      -- (its list is gone: the one before)
		l.name, l.items = u.name, u.items
	end
	I.Changed()
	return label
end

-- the builder's draft
function I.Draft()
	local c = I.char
	if type(c.draft) ~= "table" then c.draft = { name = "", items = {} } end
	c.draft.items = c.draft.items or {}
	return c.draft
end

function I.DraftAdd(id, n)
	id = tonumber(id)
	if not (id and I.char) then return false end
	local d = I.Draft()
	local e = LineOf(d, id)
	if e then
		if n then e.n = math.max(0, math.floor(tonumber(n) or e.n)) I.Changed() end
		return false
	end
	d.items[#d.items + 1] = { id = id, n = math.max(0, math.floor(tonumber(n) or 0)), name = (Call(GetItemInfo, id)) }
	I.Changed()
	return true
end

function I.DraftRemove(id)
	local d = I.Draft()
	local _, i = LineOf(d, tonumber(id))
	if not i then return false end
	table.remove(d.items, i)
	I.Changed()
	return true
end

function I.DraftSet(id, n)
	local e = LineOf(I.Draft(), id)
	if not e then return end
	e.n = math.max(0, math.floor(tonumber(n) or e.n))
	I.Changed()
end

function I.DraftName(text)
	I.Draft().name = Trim(text)
end

function I.DraftClear()
	local d = I.Draft()
	d.name, d.items, d.editing = "", {}, nil
	I.Changed()
end

-- "List N": the first N not taken
function I.AutoName()
	local taken = {}
	for _, l in ipairs(I.Lists()) do taken[l.name] = true end
	local n = 1
	while taken[L["List %d"]:format(n)] do n = n + 1 end
	return L["List %d"]:format(n)
end

-- Build Shopping List: the draft saved as a list (a new one, or the one being edited, in place), the draft
-- cleared. Lines with 0 are left out. Returns the list (nil when nothing to save).
function I.BuildList()
	local c, d = I.char, I.Draft()
	local items, zero = {}, 0
	for _, e in ipairs(d.items) do
		if (e.n or 0) > 0 then items[#items + 1] = { id = e.id, n = e.n, name = e.name or (Call(GetItemInfo, e.id)) }
		else zero = zero + 1 end
	end
	if #items == 0 then
		ns:Print("%s", #d.items == 0 and L["Add an item first: search it above, or shift-click it into the search box."]
			or L["Set how many you need (the numbers are 0), then Build Shopping List."])
		return nil
	end
	local name = Trim(d.name)
	local l = d.editing and I.ListByID(d.editing)
	if name == "" then name = l and l.name or I.AutoName() end
	local edited = l ~= nil
	if l then
		PushUndo({ kind = "edit", list = l.id, name = l.name, items = l.items })
		l.name, l.items = name, items
	else
		c.nextList = c.nextList or 1
		l = { id = c.nextList, name = name, created = Now(), items = items }
		c.nextList = c.nextList + 1
		c.lists[#c.lists + 1] = l
	end
	if not I.ActiveList() and c.activeList ~= I.NONE then c.activeList = l.id end   -- ("None" chosen: stays)
	d.name, d.items, d.editing = "", {}, nil
	local msg = L["Shopping list '%s' saved (%d items)."]:format(name, #items)
	if edited then msg = msg .. " " .. L["Undo puts back what it was."] end
	if zero > 0 then msg = msg .. " " .. L["%d with 0 left out."]:format(zero) end
	ns:Print("%s", msg)
	I.Changed()
	return l
end

-- Edit: a list back into the builder (what was in the draft is replaced); Build saves it in its place
function I.EditList(lid)
	local l = I.ListByID(lid)
	if not l then return false end
	local d = I.Draft()
	d.name, d.editing, d.items = l.name, l.id, {}
	for _, e in ipairs(l.items) do d.items[#d.items + 1] = { id = e.id, n = e.n, name = e.name } end
	I.Changed()
	return true
end

function I.DeleteList(lid)
	local l, i = I.ListByID(lid)
	if not l then return false end
	local wasActive = I.char.activeList == lid
	table.remove(I.char.lists, i)
	if wasActive then I.char.activeList = nil end
	if I.Draft().editing == lid then I.Draft().editing = nil end
	PushUndo({ kind = "list", l = l, index = i, active = wasActive })
	ns:Print("%s", L["Shopping list '%s' deleted. Undo: the Undo button, or /valhalla undo."]:format(l.name))
	I.ActiveList()
	I.Changed()
	return true
end

-- the item search box: up to max items whose names hold what's typed, from what Valhalla has seen (bags,
-- bank, merchants, your lists, the draft, the old wants, the mail), the game's own cache for an exact name;
-- a link or an ID: that item
function I.SearchItems(text, max)
	max = max or 6
	text = Trim(text)
	if text == "" then return {} end
	local id = text:match("item:(%d+)") or text:match("^(%d+)$")
	if id then return { tonumber(id) } end
	local low = text:lower()
	local found, seen = {}, {}
	local function Try(i)
		if seen[i] then return end
		seen[i] = true
		local n = Call(GetItemInfo, i)
		if n and n:lower():find(low, 1, true) then found[#found + 1] = { id = i, name = n, exact = n:lower() == low, prefix = n:lower():sub(1, #low) == low } end
	end
	local _, link = Call(GetItemInfo, text)
	local exact = link and tonumber(link:match("item:(%d+)"))
	if exact then Try(exact) end
	local c = I.char
	if c then
		for _, t in ipairs({ c.bags, c.bank, (I.db.account or {}).bank, c.want, c.mail }) do for i in pairs(t or {}) do Try(i) end end
		for _, l in ipairs(c.lists or {}) do for _, e in ipairs(l.items) do Try(e.id) end end
		for _, e in ipairs(I.Draft().items) do Try(e.id) end
	end
	for _, m in pairs(I.realm and I.realm.merchants or {}) do for i in pairs(m.items or {}) do Try(i) end end
	table.sort(found, function(a, b)
		if a.exact ~= b.exact then return a.exact end
		if a.prefix ~= b.prefix then return a.prefix end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(max, #found) do out[i] = found[i].id end
	return out
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
	"GET_ITEM_INFO_RECEIVED", "REPLICATE_ITEM_LIST_UPDATE",
	-- (v0.3.4: the AH check's: searches and the AH's throttle)
	"COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
	"AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
	-- (v0.4.1: a profession window's recipes, for Craft)
	"TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
	-- (v0.4.1.1: something learned, a profession taken or dropped: Known and your professions asked again)
	"LEARNED_SPELL_IN_TAB", "SKILL_LINES_CHANGED" }

function I.OnEvent(event, a1, a2)
	if I.AHCheck and I.AHCheck.run then I.AHCheck.OnEvent(event, a1) end
	if event == "BAG_UPDATE_DELAYED" then
		local old = I.char.bags
		I.CountBags()
		if I.bankOpen then I.SnapshotBank() end
		I.MailArrived(old, I.char.bags)
		I.Changed()
	elseif event == "BANKFRAME_OPENED" then
		I.BankOpened("BANKFRAME_OPENED")
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		if I.IsBanker(a1) then I.BankOpened("interaction") end
	elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "BANK_TABS_CHANGED" then
		if I.bankOpen then I.SnapshotBank() I.Changed() end
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
		if I.Scan then I.realm.ahLast = I.Scan.House() end   -- (AH Market shows the house you last visited)
		if I.AH then I.AH.Show() end
		I.Changed()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		I.ahOpen = false
		if I.Scan then I.Scan.OnAHClosed() end
		if I.AH then I.AH.Hide() end
		I.Changed()
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
		-- (a name arrived: kept on its lines, for when the game's cache is cold)
		if I.char and a1 then
			local name, hit = Call(GetItemInfo, a1), false
			for _, l in ipairs(I.char.lists or {}) do
				for _, e in ipairs(l.items) do if e.id == a1 then e.name = name or e.name hit = true end end
			end
			for _, e in ipairs(I.Draft().items) do if e.id == a1 then e.name = name or e.name hit = true end end
			if hit then I.Changed() end
		end
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "NEW_RECIPE_LEARNED" then
		if event == "NEW_RECIPE_LEARNED" and I.Craft and I.Craft.Learned then pcall(I.Craft.Learned) end
		if I.Craft and I.Craft.ReadOpen then pcall(I.Craft.ReadOpen, event ~= "TRADE_SKILL_LIST_UPDATE") end
	elseif event == "LEARNED_SPELL_IN_TAB" then
		if I.Craft and I.Craft.Learned then pcall(I.Craft.Learned) end
	elseif event == "SKILL_LINES_CHANGED" then
		if I.Craft then I.Craft.mine = nil end   -- (a skill-up fires it too: only your professions asked again)
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
	if I.Scan then pcall(I.Scan.PruneAll) end   -- (history past its days dropped at login)
	if I.Tabs then I.Tabs.Enable() end
	if I.Merchant then I.Merchant.Enable() end
	if I.AH then I.AH.Enable() end
end

function mod:OnDisable()
	if I.AHCheck then I.AHCheck.Stop("stopped: Investments turned off") end
	if I.Scan then I.Scan.Stop() end
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
	-- (v0.3.4: what the market scanner and the craft profit would use)
	"C_AuctionHouse.SendSearchQuery", "C_AuctionHouse.GetBrowseResults", "C_AuctionHouse.HasFullBrowseResults",
	"C_AuctionHouse.GetCommoditySearchResultInfo", "C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.MakeItemKey",
	"C_AuctionHouse.CalculateCommodityDeposit", "C_AuctionHouse.CalculateItemDeposit", "C_TradeSkillUI.GetRecipeInfo",
	"C_TradeSkillUI.GetRecipeOutputItemData", "C_TradeSkillUI.GetBaseProfessionInfo", "GetTimePreciseSec", "debugprofilestop",
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
	d.list = { lists = #I.Lists(), active = list.name, none = I.NoneChosen(), wanted = list.total, buy = #list.vendor + #list.ah, mail = #list.mail, done = list.done,
		merchants = merchants, draft = #I.Draft().items, oldWants = (function() local n = 0 for _ in pairs(I.char.want) do n = n + 1 end return n end)() }
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
	d.recipeProbe = I.RecipeProbe()
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
	out[3] = L["Lists: %d saved, active %s: %d to buy, %d in the mail, %d done; %d merchants known; %s."]:format(d.list.lists or 0,
		d.list.active and ("'" .. d.list.active .. "'") or (d.list.none and L["None (chosen)"] or L["none"]), d.list.buy, d.list.mail, d.list.done, d.list.merchants, ah)
	return out
end

-- Settings' buttons: kind nil (Run diagnostic) or "ah" (Run AH check)
function I.RunDiag(kind)
	if kind == "ah" and not I.ahOpen then
		ns:Print("%s", L["Run AH check: open the Auction House first."])
		return nil
	end
	if kind == "ah" and I.Scan and I.Scan.Running() then
		ns:Print("%s", L["A scan is running: wait for it (or press Stop on Valhalla's list beside the AH)."])
		return nil
	end
	if kind == "ah" and I.AHCheck.Running() then
		ns:Print("%s", L["The AH check is already running: keep the Auction House open (step %s)."]:format(tostring(I.AHCheck.run.out.step)))
		return nil
	end
	local d = I.Diag(kind or "")
	for _, line in ipairs(I.DiagSummary(d)) do ns:Print("%s", line) end
	if kind == "ah" then
		I.AHCheck.Start(d)
		ns:Print("%s", L["AH check started: keep the Auction House open, about 1-4 minutes (it asks for a full scan, which may wait on the game's 15-minute cooldown). It only reads prices: nothing is posted, bid or bought. Its results print here when it ends."])
	end
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
-- The AH check (v0.3.4, Phase C0): Investments > Settings > Run AH check (at the Auction House), or
-- /valhalla invest diag ah. Measures what the coming market scanner can use, step by step, a few ms per
-- frame (never a freeze), and saves it in the diagnostic's entry (ValhallaInvestDB.diag[n].ahcheck):
--   house (faction or neutral), deposit samples (calculated only: nothing is posted), recipes readable
--   (with the profession window open or closed, learned or not), quick-scan batches (SearchForItemKeys with
--   10 / 50 / 100 items) and the throttle's timing, one commodity search (Linen Cloth), the full scan
--   (ReplicateItems: time to answer, auctions, read time, commodities in it) and a second call (cooldown).
-- It only asks the Auction House for prices: it never posts, bids, buys or cancels, and calls nothing
-- protected. Nothing of the market is stored beyond these few numbers. Closing the AH stops it (saved as such).
--------------------------------------------------------------------------------

local AC = { BUDGET_MS = 8, CHUNK = 100 }
I.AHCheck = AC
AC.TIMEOUT = { throttle = 10, browse = 15, commodity = 15, replicate = 180, quiet = 5, second = 15 }
AC.BATCHES = { 10, 50, 100 }
AC.LINEN = 2589
-- Classic trade goods (cloth, ore, bars, stone, herbs, leather, enchanting, parts, cooking, gems): the
-- quick scan's sample keys
AC.SAMPLE = { 2589, 2592, 4306, 4338, 14047, 2770, 2771, 2772, 3858, 10620, 2775, 2776, 7911, 2840, 3576, 2841, 3575,
	3860, 12359, 3859, 2842, 3577, 6037, 2835, 2836, 2838, 7912, 12365, 2447, 765, 2449, 785, 2450, 2452, 3820, 2453, 3355,
	3369, 3356, 3357, 3818, 3821, 3358, 3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467,
	13468, 2318, 2319, 4234, 4304, 8170, 783, 4232, 4235, 8169, 8171, 2934, 10940, 11083, 11137, 11176, 16204, 10938, 10939,
	11082, 2996, 2997, 4305, 4339, 14048, 2321, 2320, 4291, 8343, 14341, 2324, 2604, 6260, 2605, 3371, 3372, 8925, 2678,
	2692, 159, 4470, 2880, 3466, 4357, 4364, 4377, 10505, 4359, 4361, 2672, 2673, 769, 3173, 1468, 5503, 5504, 6303, 6291,
	6308, 6289, 12808, 7076, 7078, 7080, 7082, 12803, 7067, 7068, 7069, 7070, 7972, 818, 1210, 1705, 1206, 1529, 3864, 7909,
	7910, 12361, 12799, 12800, 774 }
-- the replicate's totals kept for these (cloth, ore, herbs): compared with the commodity search
AC.WATCH = { 2589, 2592, 2770, 2447, 765, 2318 }
-- recipes to try (Bolt of Linen Cloth, Linen Bandage, Smelt Copper, Rough Sharpening Stone, Minor Healing
-- Potion, Charred Wolf Meat, Handstitched Leather Boots): readable when not learned, or the window closed?
I.PROBE_RECIPES = { 2963, 3275, 2657, 2660, 2330, 2538, 2149 }
-- neutral (Blackwater) houses: Booty Bay, Gadgetzan, Everlook (English names; zones Stranglethorn Vale,
-- Tanaris, Winterspring by name and Classic map ID): a guess, saved with what it's based on
AC.NEUTRAL_SUB = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }
AC.NEUTRAL_ZONE = { ["Tanaris"] = true, ["Stranglethorn Vale"] = true, ["Cape of Stranglethorn"] = true, ["Winterspring"] = true }
AC.NEUTRAL_MAP = { [1446] = true, [1434] = true, [1452] = true }

local ABORT = {}
local function T() return (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and debugprofilestop() / 1000) or Now() end
local function MS() return (debugprofilestop and debugprofilestop()) or T() * 1000 end
local function R2(x) return x and math.floor(x * 100 + 0.5) / 100 end
local SORTS = { { sortOrder = 0, reverseSort = false } }   -- (Enum.AuctionHouseSortOrder.Price)

local function Key(id)
	local k = C_AuctionHouse and C_AuctionHouse.MakeItemKey and Call(C_AuctionHouse.MakeItemKey, id)
	return type(k) == "table" and k or { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

local function ProfessionOpen()
	local f = _G.ProfessionsFrame
	return (f and f.IsShown and Call(f.IsShown, f)) and true or false
end

-- recipes: what the client tells with the profession window open or closed, learned or not (also in the
-- plain diagnostic)
function I.RecipeProbe()
	local T2 = C_TradeSkillUI
	local p = { window = ProfessionOpen(), samples = {} }
	if not T2 then p.api = false return p end
	p.ready = Call(T2.IsTradeSkillReady)
	local base = Call(T2.GetBaseProfessionInfo)
	if type(base) == "table" then p.profession = base.professionName or base.parentProfessionName end
	local all = T2.GetAllRecipeIDs and Call(T2.GetAllRecipeIDs)
	local filtered = T2.GetFilteredRecipeIDs and Call(T2.GetFilteredRecipeIDs)
	p.all = type(all) == "table" and #all or nil
	p.filtered = type(filtered) == "table" and #filtered or nil
	local ids = {}
	for _, id in ipairs(I.PROBE_RECIPES) do ids[#ids + 1] = id end
	if type(filtered) == "table" and filtered[1] then ids[#ids + 1] = filtered[1] p.fromWindow = filtered[1] end
	local read, learned = 0, 0
	for _, id in ipairs(ids) do
		local s = Call(T2.GetRecipeSchematic, id, false)
		local info = Call(T2.GetRecipeInfo, id)
		local out = Call(T2.GetRecipeOutputItemData, id)
		local e = { id = id, schematic = type(s) == "table", learned = type(info) == "table" and info.learned or nil, info = type(info) == "table" }
		if type(s) == "table" then
			read = read + 1
			e.name, e.out, e.qmin, e.qmax = s.name, s.outputItemID, s.quantityMin, s.quantityMax
			e.reagents = type(s.reagentSlotSchematics) == "table" and #s.reagentSlotSchematics or nil
			local first = type(s.reagentSlotSchematics) == "table" and s.reagentSlotSchematics[1]
			if type(first) == "table" then
				e.r1n = first.quantityRequired
				local r = type(first.reagents) == "table" and first.reagents[1]
				e.r1 = type(r) == "table" and r.itemID or nil
			end
		end
		if type(out) == "table" then e.outData = out.itemID or out.hyperlink and true end
		if e.learned then learned = learned + 1 end
		p.samples[#p.samples + 1] = e
	end
	p.read, p.learned, p.tried = read, learned, #ids
	return p
end

-- where this Auction House is (faction or neutral), and what the guess is based on
function AC.House()
	local h = { faction = Call(UnitFactionGroup, "player"), zone = Call(GetRealZoneText) or Call(GetZoneText), sub = Call(GetSubZoneText),
		map = C_Map and Call(C_Map.GetBestMapForUnit, "player"), npc = Call(UnitName, "npc") }
	h.neutral = (AC.NEUTRAL_SUB[h.sub or ""] or AC.NEUTRAL_ZONE[h.zone or ""] or AC.NEUTRAL_MAP[h.map or 0]) and true or false
	h.house = h.neutral and "Neutral" or (h.faction or "?")
	return h
end

-- deposits, calculated by the client for an item and a commodity in your bags (12 / 24 / 48 h): nothing posted
function AC.Deposits()
	local out = { item = nil, commodity = nil }
	local A = C_AuctionHouse
	if not (A and ItemLocation and ItemLocation.CreateFromBagAndSlot) then out.note = "no ItemLocation" return out end
	for bag = 0, 4 do
		for slot = 1, (Call(C_Container.GetContainerNumSlots, bag) or 0) do
			local info = Call(C_Container.GetContainerItemInfo, bag, slot)
			if type(info) == "table" and info.itemID and not info.isBound then
				local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
				local status = Call(A.GetItemCommodityStatus, loc)
				local kind = status == 2 and "commodity" or status == 1 and "item" or nil
				if kind and not out[kind] then
					local e = { id = info.itemID, stack = info.stackCount }
					local got = { pcall(GetItemInfo, info.itemID) }   -- (sellPrice: the 11th value)
					e.vendor = got[1] and Value(got[12]) or nil
					for dur = 1, 3 do
						if kind == "commodity" then e[dur] = Call(A.CalculateCommodityDeposit, info.itemID, dur, 1)
						else e[dur] = Call(A.CalculateItemDeposit, loc, dur, 1) end
					end
					out[kind] = e
				end
			end
			if out.item and out.commodity then return out end
		end
	end
	return out
end

-- the coroutine's helpers: wait (a frame at a time) for something, or until the time's up
local function Yield() coroutine.yield() end
local function Wait(cond, timeout)
	local t = T()
	while true do
		if not I.ahOpen then error(ABORT) end
		if cond() then return true, R2(T() - t) end
		if T() - t > timeout then return false, R2(T() - t) end
		Yield()
	end
end
local function Step(o, n, label)
	o.step = ("%d/7 %s"):format(n, label)
	I.Changed()
end
local function ThrottleReady(r)
	return Wait(function() return Call(C_AuctionHouse.IsThrottledMessageSystemReady) ~= false end, AC.TIMEOUT.throttle)
end

-- the full scan's read: only count, buyout and itemID per auction (the fields there at once), a few ms per frame
function AC.Read(r, rp)
	local A = C_AuctionHouse
	local n = Call(A.GetNumReplicateItems) or 0
	rp.count = n
	local Get = A.GetReplicateItemInfo
	local per, items, bidOnly, units = {}, 0, 0, 0
	local cpu, frames, t0 = 0, 1, T()
	local mem0 = collectgarbage and collectgarbage("count") or 0
	local i = 0
	while i < n do
		local s = MS()
		local last = math.min(n - 1, i + AC.CHUNK - 1)
		for k = i, last do
			local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(Get, k)
			if ok then
				itemID, count, buyout = Value(itemID), Value(count) or 0, Value(buyout) or 0
				if itemID then
					local e = per[itemID]
					if not e then e = { a = 0, q = 0 } per[itemID] = e items = items + 1 end
					e.a, e.q = e.a + 1, e.q + count
					units = units + count
					if buyout > 0 and count > 0 then
						local unit = math.floor(buyout / count)
						if not e.min or unit < e.min then e.min = unit end
					else
						bidOnly = bidOnly + 1
					end
				end
			end
		end
		i = last + 1
		cpu = cpu + (MS() - s)
		if i < n and MS() - r.frameStart > AC.BUDGET_MS then
			rp.readAt = i
			Yield()
			frames = frames + 1
			if not I.ahOpen then rp.aborted = i error(ABORT) end
		end
	end
	rp.readAt = nil
	rp.items, rp.bidOnly, rp.units = items, bidOnly, units
	rp.readSecs, rp.cpuMs, rp.frames = R2(T() - t0), R2(cpu), frames
	rp.memKB = collectgarbage and math.floor(collectgarbage("count") - mem0) or nil
	rp.watch = {}
	for _, id in ipairs(AC.WATCH) do
		local e = per[id]
		rp.watch[id] = e and { auctions = e.a, units = e.q, min = e.min } or false
	end
	-- the 5 items with the most auctions
	local top = {}
	for id, e in pairs(per) do top[#top + 1] = { id = id, auctions = e.a, units = e.q, min = e.min } end
	table.sort(top, function(a, b) if a.auctions ~= b.auctions then return a.auctions > b.auctions end return a.id < b.id end)
	rp.top = {}
	for k = 1, math.min(5, #top) do rp.top[k] = top[k] end
end

local function Run(r)
	local A, o = C_AuctionHouse, r.out
	Step(o, 1, "house, deposits, recipes")
	o.house = AC.House()
	o.deposit = AC.Deposits()
	o.recipes = I.RecipeProbe()
	Yield()
	-- quick scan batches, each when the throttle says ready
	Step(o, 2, "quick scan batches")
	o.quick = {}
	for _, size in ipairs(AC.BATCHES) do
		local b = {}
		b.ready, b.readyWait = ThrottleReady(r)
		local keys = {}
		for k = 1, math.min(size, #AC.SAMPLE) do keys[k] = Key(AC.SAMPLE[k]) end
		b.keys = #keys
		r.browse = nil
		local ok, err = pcall(A.SearchForItemKeys, keys, SORTS)
		if not ok then
			b.error = tostring(err)
		else
			local got, secs = Wait(function() return r.browse ~= nil end, AC.TIMEOUT.browse)
			b.secs, b.answer = secs, got and r.browse or "timeout"
			if got then
				local res = Call(A.GetBrowseResults)
				b.results = type(res) == "table" and #res or nil
				b.full = Call(A.HasFullBrowseResults)
				if type(res) == "table" then
					local priced = 0
					for _, x in ipairs(res) do if type(x) == "table" and (Value(x.minPrice) or 0) > 0 then priced = priced + 1 end end
					b.priced = priced
				end
			end
		end
		o.quick[#o.quick + 1] = b
		Yield()
	end
	-- one commodity search (Linen Cloth): commodity or item, and what it says
	Step(o, 3, "commodity search")
	local c = { itemID = AC.LINEN }
	c.ready, c.readyWait = ThrottleReady(r)
	r.commodity, r.itemSearch = nil, nil
	local ok, err = pcall(A.SendSearchQuery, Key(AC.LINEN), SORTS, false)
	if not ok then
		c.error = tostring(err)
	else
		local got, secs = Wait(function() return r.commodity or r.itemSearch end, AC.TIMEOUT.commodity)
		c.secs = secs
		c.kind = r.commodity and "commodity" or r.itemSearch and "item" or "timeout"
		if r.commodity then
			c.results = Call(A.GetNumCommoditySearchResults, AC.LINEN)
			c.full = Call(A.HasFullCommoditySearchResults, AC.LINEN)
			c.units = Call(A.GetCommoditySearchResultsQuantity, AC.LINEN)
			local first = Call(A.GetCommoditySearchResultInfo, AC.LINEN, 1)
			c.min = type(first) == "table" and Value(first.unitPrice) or nil
		elseif r.itemSearch then
			c.results = Call(A.GetNumItemSearchResults, Key(AC.LINEN))
		end
	end
	o.commodity = c
	Yield()
	-- the full scan
	Step(o, 4, "full scan: waiting for the Auction House")
	local acct = I.db.account
	local rp = { lastOkAt = acct.replicateAt, minutesSince = acct.replicateAt and R2((Now() - acct.replicateAt) / 60) or nil }
	r.replicated = nil
	r.repEvents = 0
	ok, err = pcall(A.ReplicateItems)
	rp.called = ok
	o.replicate = rp
	if not ok then
		rp.error = tostring(err)
	else
		local got, secs = Wait(function() return r.replicated ~= nil end, AC.TIMEOUT.replicate)
		rp.answered, rp.readySecs = got, secs
		if not got then
			rp.countNoAnswer = Call(A.GetNumReplicateItems)
		else
			acct.replicateAt = Now()
			Step(o, 5, "full scan: reading")
			AC.Read(r, rp)
			if c.units and rp.watch and rp.watch[AC.LINEN] then
				rp.linenVsSearch = R2(rp.watch[AC.LINEN].units / math.max(1, c.units))
			end
			-- the item data the read asked for also fires REPLICATE_ITEM_LIST_UPDATE: count them while quiet,
			-- then ask again (on Retail the second call within 15 min gets no answer)
			Step(o, 6, "full scan: second call (cooldown)")
			r.repEvents = 0
			Wait(function() return false end, AC.TIMEOUT.quiet)
			rp.quietEvents = r.repEvents
			r.repEvents, r.replicated = 0, nil
			local asked = T()
			rp.secondCalled = pcall(A.ReplicateItems)
			Wait(function() return false end, AC.TIMEOUT.second)
			rp.secondEvents = r.repEvents
			rp.secondFirst = r.replicated and R2(r.replicated - asked) or nil
			rp.secondCount = Call(A.GetNumReplicateItems)
		end
	end
	Step(o, 7, "done")
end

local driver
local function OnUpdate()
	local r = AC.run
	if not r then if driver then driver:SetScript("OnUpdate", nil) end return end
	r.frameStart = MS()
	local ok, err = coroutine.resume(r.co, r)
	local spent = MS() - r.frameStart
	if spent > (r.out.maxFrameMs or 0) then r.out.maxFrameMs = R2(spent) end
	if not ok then
		AC.Finish(err == ABORT and "stopped: the Auction House closed" or ("error: " .. tostring(err)))
	elseif coroutine.status(r.co) == "dead" then
		AC.Finish("done")
	end
end

AC.Tick = OnUpdate   -- (the tests drive it)
function AC.Running() return AC.run ~= nil end

-- how far it is (v0.3.5, for the AH list's bar): fraction 0-1, the step's number and label, and while the
-- full scan is read, how many of how many
function AC.Progress()
	local r = AC.run
	if not r then return nil end
	local o = r.out
	local n, label = tostring(o.step or ""):match("^(%d+)/7%s*(.*)$")
	n = tonumber(n) or 0
	local f = math.max(0, n - 1) / 7
	local rp = o.replicate
	local at, count = rp and rp.readAt, rp and rp.count
	if at and (count or 0) > 0 then f = f + (at / count) / 7 end
	return math.max(0, math.min(1, f)), n, label or "", at, count
end

-- start (the diagnostic's entry d gets d.ahcheck, filled as it goes: a /reload mid-way keeps what's done)
function AC.Start(d)
	if AC.run then return false end
	local o = { state = "running", started = d.when, budgetMs = AC.BUDGET_MS, maxFrameMs = 0, throttle = {} }
	d.ahcheck = o
	local r = { out = o, t0 = T(), co = coroutine.create(Run) }
	AC.run = r
	if not driver then driver = CreateFrame("Frame") end
	driver:SetScript("OnUpdate", OnUpdate)
	return true
end

function AC.Stop(why)
	if AC.run then AC.Finish(why or "stopped") end
end

function AC.Finish(state)
	local r = AC.run
	if not r then return end
	AC.run = nil
	if driver then driver:SetScript("OnUpdate", nil) end
	r.out.state, r.out.secs = state, R2(T() - r.t0)
	for _, line in ipairs(AC.Summary(r.out)) do ns:Print("%s", line) end
	I.Changed()
end

-- events (from I.OnEvent): only while it runs
local THROTTLE = { AUCTION_HOUSE_THROTTLED_MESSAGE_SENT = "sent", AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED = "queued",
	AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = "dropped", AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED = "response",
	AUCTION_HOUSE_THROTTLED_SYSTEM_READY = "ready" }
AC.EVENTS = { "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }
for e in pairs(THROTTLE) do AC.EVENTS[#AC.EVENTS + 1] = e end
table.sort(AC.EVENTS)

function AC.OnEvent(event, a1)
	local r = AC.run
	if not r then return end
	if event == "REPLICATE_ITEM_LIST_UPDATE" then
		r.repEvents = (r.repEvents or 0) + 1
		if not r.replicated then r.replicated = T() end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		r.browse = r.browse or "results"
	elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
		r.browse = r.browse or "failure"
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		if a1 == AC.LINEN then r.commodity = true end
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
		if type(a1) == "table" and a1.itemID == AC.LINEN then r.itemSearch = true end
	elseif THROTTLE[event] then
		local log = r.out.throttle
		if #log < 80 then log[#log + 1] = ("%s@%.2f"):format(THROTTLE[event], T() - r.t0) end
	end
end

local function Secs(x) return x and ("%.1f s"):format(x) or "?" end

-- the lines in chat when it ends
function AC.Summary(o)
	local out = {}
	local h = o.house or {}
	out[1] = ("AH check %s in %s at the %s house (%s%s). Longest frame %.1f ms (budget %d ms)."):format(tostring(o.state), Secs(o.secs),
		tostring(h.house or "?"), tostring(h.sub ~= "" and h.sub or h.zone or "?"), h.neutral and ", neutral" or "", o.maxFrameMs or 0, o.budgetMs or AC.BUDGET_MS)
	local rp = o.replicate
	if rp then
		if not rp.called then out[#out + 1] = "Full scan: the call failed: " .. tostring(rp.error)
		elseif not rp.answered then
			out[#out + 1] = ("Full scan: no answer in %s (cooldown? last one %s min ago)."):format(Secs(rp.readySecs), tostring(rp.minutesSince or "?"))
		else
			out[#out + 1] = ("Full scan: ready in %s; %s auctions of %s items read in %s (%s ms of work over %d frames%s). Second call: %d events in %d s."):format(
				Secs(rp.readySecs), tostring(rp.count), tostring(rp.items or "?"), Secs(rp.readSecs), tostring(rp.cpuMs or "?"), rp.frames or 0,
				rp.aborted and (", stopped at " .. rp.aborted) or "", rp.secondEvents or 0, AC.TIMEOUT.second)
		end
	else
		out[#out + 1] = "Full scan: not reached."
	end
	local c = o.commodity
	if c then
		local w = rp and rp.watch and rp.watch[AC.LINEN]
		out[#out + 1] = ("Linen Cloth search: %s in %s, %s prices, %s units, lowest %s; in the full scan: %s."):format(tostring(c.kind), Secs(c.secs),
			tostring(c.results or "-"), tostring(c.units or "-"), tostring(c.min or "-"),
			w and ("%d auctions, %d units"):format(w.auctions, w.units) or (w == false and "not in it" or "-"))
	end
	if o.quick then
		local parts = {}
		for _, b in ipairs(o.quick) do
			parts[#parts + 1] = ("%d keys %s (%s results)"):format(b.keys or 0, b.error and "error" or Secs(b.secs), tostring(b.results or b.answer or "-"))
		end
		out[#out + 1] = "Quick scan: " .. table.concat(parts, ", ") .. "; throttle events " .. #(o.throttle or {}) .. "."
	end
	local p = o.recipes
	if p then
		out[#out + 1] = ("Recipes (profession window %s): %d of %d sample recipes readable, %d learned."):format(p.window and "open" or "closed", p.read or 0, p.tried or 0, p.learned or 0)
	end
	out[#out + 1] = "Saved in ValhallaInvestDB.diag: /reload (or log out) writes it to disk."
	return out
end

--------------------------------------------------------------------------------
-- Slash commands (Init.lua sends them here)
--   /valhalla invest [vendor|list|market|settings]   open Investments (at that page; settings: the Settings tab)
--   /valhalla invest on|off                          the whole tabbed window and Investments (off: the map as before)
--   /valhalla invest diag [ah|replicate|stop]        what this client has, saved to the saved log (ah: the AH check)
--   /valhalla invest scan [stop]                     at the Auction House: Scan (full when ready, else quick), or stop
--   /valhalla undo                                   put back the last deleted list (or a list as it was before an edit)
--   /valhalla tab map|invest|talents|professions|settings   switch the window's tab
--   /valhalla want <item> [count], /valhalla unwant <item>   into / out of the Shopping List's builder
--   /valhalla list                                   the active shopping list
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
		if sub == "scan" then
			if rest == "stop" then I.Scan.Stop() else I.Scan.Toggle() end
			return
		end
		if sub == "diag" and (rest == "ah" or rest == "stop") then
			if rest == "stop" then
				if I.AHCheck.Running() then I.AHCheck.Stop("stopped") else Say("%s", L["The AH check isn't running."]) end
			else
				I.RunDiag("ah")
			end
			return
		end
		if sub == "diag" then
			local d = I.Diag(rest)
			for _, line in ipairs(I.DiagLines(d)) do Say("%s", line) end
			I.Changed()
			return
		end
		if sub == "settings" then if I.Tabs then I.Tabs.Open("settings") end return end   -- (v0.3.5: its own tab)
		local page = ({ vendor = "vendor", list = "list", shopping = "list", market = "market", ah = "market" })[sub]
		if I.Tabs then I.Tabs.Open("invest", page) end
		return
	end
	if not mod.enabled then Say(L["Investments is off. /valhalla invest on"]) return end
	if word == "undo" then
		local what = I.Undo()
		if what then Say(L["Put back: %s."], what) else Say("%s", L["Nothing to undo."]) end
	elseif word == "tab" then
		local key = ({ map = "map", invest = "invest", investments = "invest", talents = "talents", professions = "professions", settings = "settings" })[low]
		if not key then Say(L["/valhalla tab map|invest|talents|professions|settings"]) return end
		if I.Tabs then I.Tabs.Open(key) end
	elseif word == "want" then
		-- into the Shopping List's builder (the draft): the item may be a link (with spaces), then a count
		-- (an old category word after it is ignored)
		local item, n = arg:match("^(.-)%s+(%d+)%s+%a+%s*$")
		if not item then item, n = arg:match("^(.-)%s+(%d+)%s*$") end
		if not item or item == "" then item = arg end
		if not n and item then
			local i2, c2 = item:match("^(.-)%s+(%a+)$")
			if c2 and (c2 == "mat" or c2 == "reagent" or c2 == "gear") then item = i2 end
		end
		local id = I.ParseItem(item)
		if not id then Say(L["Which item? Shift-click it into the command, or give its item ID: /valhalla want <item> [count]"]) return end
		I.DraftAdd(id, n or 0)
		local e = I.LineOf(I.Draft(), id)
		Say(L["In the builder: %s x%d (Investments > Shopping List, then Build Shopping List)."], I.ItemName(id), e and e.n or 0)
	elseif word == "unwant" then
		local id = I.ParseItem(arg)
		if id and I.DraftRemove(id) then Say(L["Out of the builder: %s."], I.ItemName(id)) else Say("%s", L["That item isn't in the builder."]) end
	elseif word == "list" then
		local list = I.ShoppingList()
		if not list.list then
			Say("%s", #I.Lists() == 0 and L["No shopping list yet: build one in Investments > Shopping List."]
				or I.NoneChosen() and L["None chosen: no list at vendors or the Auction House (choose one there)."]
				or L["No list chosen: pick one at a vendor or the Auction House."])
			return
		end
		Say(L["Shopping list '%s' (%d of %d done):"], list.name, list.done, list.total)
		for _, src in ipairs({ "vendor", "ah" }) do
			for _, r in ipairs(list[src]) do
				Say("  %s: %s x%d", src == "vendor" and L["Vendor"] or L["Auction House"], r.name, r.need)
			end
		end
		for _, r in ipairs(list.mail) do Say(L["  In the mail: %s x%d"], r.name, r.mail) end
	end
end
