--------------------------------------------------------------------------------
-- The Auction House's shopping list (v0.3.0, v0.3.1): beside the game's Auction House, what you still
-- need from it, each with a Search button, and what you bought that's still in the mail.
--
-- Search (v0.3.1): one click searches. Each Search button is a secure "click" action button
-- (SecureActionButtonTemplate, type "click") whose target is the AH's own Search button: Valhalla only
-- puts the item's name in the AH's search box (PreClick), then the game clicks its own Search button for
-- you, on your click, so the AH's own search runs as if you'd pressed it (nothing of the AH's run by
-- Valhalla's code). If the game won't let it (the button missing, or not clickable for addons), the
-- name is left in the search box, focused: press Enter.
-- The list's "-" minimizes it to a small button at the AH's top right (with how many items are needed);
-- that button brings it back. Minimized or not is remembered across visits.
-- v0.3.2: the active shopping list only; a "List: <name>" picker under the title chooses which.
-- v0.3.3: the list's Auction House items stay listed once you have enough (Done) or bought them (In mail);
-- "None" chosen: no list here.
-- Buying (1.2.7): only from the checkout cart, and only on your clicks: one click per purchase (the game's rule).
-- Otherwise it's your own click on the game's own Buy button.
-- v0.3.5: the AH check's button was here. v0.4.0: Scan instead (the AH check: /valhalla invest diag ah):
-- a full scan when its 15 minutes are up, else a quick scan of your items; Stop, what it's doing and a bar;
-- minimized, the small button's right-click scans or stops. The rows' items show the game's tooltip.
-- 1.2.7: a checkout cart (one per character). Each row's + puts what's still needed in the cart (- takes it
-- out); Checkout (N) opens the cart: a stepper for each item, its price each and line total (the cart's own
-- Scan prices each item exactly, its cheapest listings; short supply said), the Total and your gold; Back,
-- Scan and Buy. Buy asks first (Yes / No): Yes buys the first item, then "Buy next" buys each of the rest, one
-- click each. Stackable goods (commodities): the game's price is asked for, and bought at once if it's within
-- the price guard (+5%: Settings) of the price shown, else skipped; other items: the cheapest auctions, at
-- their buyout. It stops on a failure, not enough gold, or the AH closing (what's pending is cancelled).
-- Every purchase is logged (/valhalla invest buys).
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local A = {}
I.AH = A

A.ROWS = 13                                 -- (v0.4.2.1: a page of 13, its pager under them)
A.offset = 0
A.W = 270
A.H = 560                                   -- (1.2.7: 530, and the cart's Checkout bar)
A.CART_ROWS = 6                             -- (1.2.7: the cart view's page: 6 items of 46 px)
A.CART_ROW_H = 46
A.TIMEOUT = 10                              -- (1.2.7: seconds to wait for the AH's answer to a purchase)
A.FRESH = 600                               -- (1.2.7: a cart price is good for 10 minutes, this visit only)
A.view = "list"
A.cartOffset = 0
A.WATCH = 3                                 -- (seconds to wait for the AH's answer to a search)
local panel, mini
local on = false
local hinted = false

function A.Panel() return panel end
function A.Mini() return mini end

-- the AH's own Search button, and whether the game lets a secure "click" press it (as SecureTemplates.lua checks)
function A.SearchButton()
	local ah = _G.AuctionHouseFrame
	local b = ah and ah.SearchBar and ah.SearchBar.SearchButton
	if type(b) ~= "table" then return nil, "missing" end
	local constrained = b.HasAccessConstraints and b:HasAccessConstraints() or false
	local forbidden = false
	if b.HasAnyForbiddenAspects and Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ScriptedInput then
		forbidden = b:HasAnyForbiddenAspects(Enum.ForbiddenAspect.ScriptedInput) or false
	end
	if constrained or forbidden then return b, "blocked", constrained, forbidden end
	return b, "ok", constrained, forbidden
end

-- for the diagnostic
function A.Check()
	local b, state, constrained, forbidden = A.SearchButton()
	return { button = b ~= nil, blocked = state == "blocked", constraints = constrained, forbidden = forbidden, last = A.last }
end

-- the fallback: the name is in the AH's search box; focus it and say so (once)
local function Fallback(name, why)
	local ah = _G.AuctionHouseFrame
	local box = ah and ah.SearchBar and ah.SearchBar.SearchBox
	if box and box.SetFocus then box:SetFocus() end
	if not hinted or why then
		hinted = true
		ns:Print("%s", L["%s is in the Auction House's search box: press Enter to search."]:format(name))
	end
end

-- before the click: the item's name into the AH's search box. Returns whether the AH's search may run.
function A.Prepare(id)
	local ah = _G.AuctionHouseFrame
	if not ah then return false end
	local name = I.ItemName(id)
	local ok, set = pcall(ah.SetSearchText, ah, name)
	if not (ok and set) then
		ns:Print("%s", L["Open the Auction House's Browse tab, then press Search again."])
		return false
	end
	local _, state = A.SearchButton()
	if state ~= "ok" then
		A.last = "fallback:" .. tostring(state)
		Fallback(name, true)
		return false
	end
	A.pending = { id = id, name = name, t = GetTime and GetTime() or 0 }
	A.last = "clicked"
	-- no answer from the AH in a few seconds: it didn't search; the name is there, press Enter
	if C_Timer and C_Timer.After then
		local p = A.pending
		C_Timer.After(A.WATCH, function()
			if A.pending == p then
				A.pending = nil
				A.last = "no answer"
				Fallback(p.name, true)
			end
		end)
	end
	return true
end

-- the AH answered a search (results or a failure)
function A.OnBrowse(event)
	if not A.pending then return end
	A.pending = nil
	A.last = event == "AUCTION_HOUSE_BROWSE_FAILURE" and "failed" or "searched"
end

-- a Search button: secure, its click the AH's own Search button's (set up once, out of combat)
local function SearchButton(r, T, V)
	local b = CreateFrame("Button", nil, r, "SecureActionButtonTemplate,BackdropTemplate")
	b:SetSize(54, 20)   -- (1.2.7: 64; room for the cart's +)
	T.SkinFlat(b, 0.9)   -- (v0.4.2: a secure button keeps the flat look; the looks never touch one)
	b.text = T.Font(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12, T.GOLD)
	b.text:SetPoint("CENTER")
	b.text:SetText(L["Search"])
	if b.RegisterForClicks then b:RegisterForClicks("AnyUp", "AnyDown") end
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(T.BRONZE[1], T.BRONZE[2], T.BRONZE[3], 1) end)
	-- the name first; when the AH's search can't run (not on Browse, or the game won't let it) no click goes through
	-- (registered for down and up, the game acts on one of them: one prepare per press)
	b:SetScript("PreClick", function(self, _, down)
		if down or not self.downDone then self.go = (r.id and A.Prepare(r.id)) and true or false end
		self.downDone = down and true or nil
		if not InCombatLockdown() then self:SetAttribute("type", self.go and "click" or nil) end
	end)
	b:SetScript("PostClick", function(self, _, down)
		if not down and not InCombatLockdown() then self:SetAttribute("type", "click") end
	end)
	A.Arm(b)
	return b
end

-- the secure button's target: the AH's own Search button (out of combat only: the game's rule)
function A.Arm(b)
	if InCombatLockdown() then return false end
	local target = A.SearchButton()
	b:SetAttribute("type", "click")
	b:SetAttribute("clickbutton", target)
	b.armed = target ~= nil
	return b.armed
end

--------------------------------------------------------------------------------
-- (1.2.7) The checkout cart: its bar on the list, its view, the Yes / No ask, and the buying
--------------------------------------------------------------------------------
local function Now() return time and time() or 0 end
local function Num(v) local x = ns.Safe and ns.Safe.Value and ns.Safe.Value(v) or v return tonumber(x) or x end
local function Money(c) return I.Scan.Money(math.floor((c or 0) + 0.5)) end
local function Gold() return (GetMoney and GetMoney()) or 0 end
function A.Guard() return math.max(0, tonumber(I.S.buyGuard) or 5) end
local ORANGE, GREY, GREEN, RED = { 1, 0.6, 0.2 }, { 0.65, 0.65, 0.65 }, { 0.3, 0.9, 0.3 }, { 1, 0.35, 0.3 }

-- a list row's + / -: in the cart (what's still needed, at least 1), or out of it
function A.RowCart(r)
	if not r.id then return end
	if I.CartLine(r.id) then I.CartRemove(r.id)
	else
		local list = I.ShoppingList()
		I.CartAdd(r.id, math.max(1, r.needN or 1), list.list and list.list.id)
	end
end

function A.SetView(v)
	A.view = v == "cart" and "cart" or "list"
	if panel and panel.confirm then panel.confirm:Hide() end
	A.Refresh()
end

-- a cart item's price: from this visit's cart Scan (exact: its cheapest listings), else the last scan's lowest
-- (shown, not bought from). Returns { each, line, got, priced, kind, note, noteColor }
function A.Fresh(house, id)
	local q = I.Scan.Quote(house, id)
	if not q or not q.t or q.t < (A.visitAt or 0) or Now() - q.t > A.FRESH then return nil end
	return q
end
function A.LinePrice(house, e)
	local q = A.Fresh(house, e.id)
	if q then
		local cost, got, _, kind = I.Scan.QuoteCost(house, e.id, e.n)
		if kind ~= "commodity" and kind ~= "item" or (got or 0) <= 0 then
			return { each = 0, line = 0, got = 0, priced = true, kind = kind, note = L["None listed"], noteColor = RED }
		end
		local x = { each = cost / got, line = cost, got = got, priced = true, kind = kind }
		if got < e.n then x.note, x.noteColor = L["Only %d listed (of %d)"]:format(got, e.n), ORANGE
		elseif got > e.n then x.note, x.noteColor = L["Whole auctions: %d for %d wanted"]:format(got, e.n), ORANGE
		else x.note, x.noteColor = kind == "commodity" and L["Priced now (stackable)"] or L["Priced now"], GREEN end
		return x
	end
	local low = I.Scan.Lowest(house, e.id)
	if low then return { each = low, line = low * e.n, got = e.n, priced = false, note = L["Last scan's price: press Scan"], noteColor = GREY } end
	return { each = 0, line = 0, got = 0, priced = false, note = L["No price yet: press Scan"], noteColor = GREY }
end

-- the purchases the cart makes: one per stackable line, one per auction otherwise (each its own click)
function A.Plan()
	local house = I.Scan.House()
	local steps, total, notes, unpriced = {}, 0, {}, 0
	for _, e in ipairs(I.Cart()) do
		if not A.Fresh(house, e.id) then unpriced = unpriced + 1
		else
			local cost, got, picks, kind = I.Scan.QuoteCost(house, e.id, e.n)
			if (got or 0) <= 0 then notes[#notes + 1] = L["%s: none listed (it stays in the cart)."]:format(I.ItemName(e.id))
			else
				if got < e.n then notes[#notes + 1] = L["%s: only %d of %d listed."]:format(I.ItemName(e.id), got, e.n) end
				if kind == "commodity" then
					steps[#steps + 1] = { kind = "commodity", id = e.id, n = got, expected = math.ceil(cost) }
				else
					for _, p in ipairs(picks) do steps[#steps + 1] = { kind = "item", id = e.id, n = p.n, auction = p.auction, expected = p.buyout } end
				end
				total = total + cost
			end
		end
	end
	return steps, math.ceil(total), notes, unpriced
end

local function StepText(st) return ("%s x%d"):format(I.ItemName(st.id), st.n) end

-- the cart's own Scan: each cart item's listings (the quick scan's way, one item at a time)
function A.CartScan()
	if I.Scan.Running() then I.Scan.Toggle() A.Refresh() return end
	local ids, need = {}, {}
	for _, e in ipairs(I.Cart()) do ids[#ids + 1] = e.id need[e.id] = e.n end
	if #ids == 0 then ns:Print("%s", L["The cart is empty: add items with the + on the list's rows."]) return end
	I.Scan.Start("cart", ids, need)
	A.Refresh()
end

-- Buy: asks first (Yes / No), saying what, the total, your gold, and that each purchase is its own click
function A.AskBuy()
	if A.buy and (A.buy.state == "waiting" or A.buy.state == "ready") then return end   -- (buying: Buy next)
	if I.Scan.Running() then ns:Print("%s", L["Wait for the scan to finish (or stop it), then Buy."]) return end
	local steps, total, notes, unpriced = A.Plan()
	if unpriced > 0 then
		A.status = L["Press Scan first: %d item(s) not priced this visit (prices are checked right before buying)."]:format(unpriced)
		A.Refresh()
		return
	end
	if #steps == 0 then A.status = L["Nothing to buy: none of the cart is listed."] A.Refresh() return end
	A.pendingSteps, A.pendingTotal = steps, total
	local c = panel.confirm
	local lines = {
		L["Buy the cart: %d purchase(s), total %s?"]:format(#steps, Money(total)),
		L["You have %s."]:format(Money(Gold())),
		L["Each purchase needs its own click: Yes buys the first (%s), then press Buy next for each of the rest."]:format(StepText(steps[1])),
		L["Stackable goods are bought only if the game's price is at most +%d%% over the price shown; else skipped."]:format(A.Guard()),
	}
	if total > Gold() then lines[#lines + 1] = L["Not enough gold for all of it: it stops when the gold runs out."] end
	for _, n in ipairs(notes) do lines[#lines + 1] = n end
	c.text:SetText(table.concat(lines, "\n"))
	c:Show()
end

-- the buying: one step per click of yours (Yes, then Buy next)
local buyer
local BUY_EVENTS = { "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
	"COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR" }
A.BUY_EVENTS = BUY_EVENTS
local function BuyEvents(listen)
	if not buyer then
		buyer = CreateFrame("Frame")
		buyer:SetScript("OnEvent", function(_, event, ...) A.OnBuyEvent(event, ...) end)
	end
	buyer:UnregisterAllEvents()
	if listen then for _, e in ipairs(BUY_EVENTS) do pcall(buyer.RegisterEvent, buyer, e) end end
end
function A.Buyer() return buyer end

local function Log(st, result, total, note)
	I.LogBuy({ house = A.buy and A.buy.house, id = st.id, n = st.n, total = total or st.expected, kind = st.kind, result = result, note = note })
end

local function Stop(reason)
	local b = A.buy
	if not b then return end
	BuyEvents(false)
	b.state = "stopped"
	b.note = L["Stopped: %s. Bought %d of %d purchases, spent %s; the rest is still in the cart."]:format(reason, b.bought, #b.steps, Money(b.spent))
	ns:Print("%s", b.note)
	A.Refresh()
end

local function Advance(note)
	local b = A.buy
	BuyEvents(false)
	b.i = b.i + 1
	if b.i > #b.steps then
		b.state = "done"
		b.note = (note and (note .. " ") or "") .. L["Done: bought %d of %d purchases, spent %s."]:format(b.bought, #b.steps, Money(b.spent))
		ns:Print("%s", b.note)
	else
		b.state = "ready"
		b.note = note
	end
	A.Refresh()
end

function A.BuyStart(steps, total)
	A.buy = { steps = steps, i = 1, total = total, spent = 0, bought = 0, house = I.Scan.House(), state = "ready", gen = 0 }
	return A.BuyNext()
end

-- the next purchase; only ever on your click (Yes, or Buy next): the game's purchase calls need one each
function A.BuyNext()
	local b = A.buy
	if not b or b.state ~= "ready" then return false end
	local st = b.steps[b.i]
	if not st then return false end
	if not I.ahOpen then Stop(L["the Auction House is closed"]) return false end
	local AHA = C_AuctionHouse
	if Gold() < st.expected then
		Log(st, "gold")
		Stop(L["not enough gold for %s (it costs %s, you have %s)"]:format(StepText(st), Money(st.expected), Money(Gold())))
		return false
	end
	b.state, b.gen = "waiting", b.gen + 1
	local gen = b.gen
	BuyEvents(true)
	local ok
	if st.kind == "commodity" then
		b.phase = "quote"
		ok = pcall(AHA.StartCommoditiesPurchase, st.id, st.n)
	else
		b.phase = "bid"
		ok = pcall(AHA.PlaceBid, st.auction, st.expected)
	end
	if not ok then Log(st, "failed") Stop(L["the game refused to buy %s"]:format(StepText(st))) return false end
	if C_Timer and C_Timer.After then
		C_Timer.After(A.TIMEOUT, function()
			if A.buy == b and b.gen == gen and b.state == "waiting" then
				if st.kind == "commodity" then pcall(AHA.CancelCommoditiesPurchase) end
				Log(st, "noanswer")
				Stop(L["no answer from the Auction House for %s"]:format(StepText(st)))
			end
		end)
	end
	A.Refresh()
	return true
end

local function Bought(st, paid)
	local b = A.buy
	b.spent, b.bought = b.spent + paid, b.bought + 1
	Log(st, "bought", paid)
	-- (its listings are spent: priced again before buying more of it)
	local q = I.Scan.quotes[b.house]
	if q and st.kind == "commodity" then q[st.id] = nil end
	I.cartBoughtAt = I.cartBoughtAt or {}
	I.cartBoughtAt[st.id] = Now()   -- (its mail still tracked when the game's purchase event comes after this)
	I.CartBought(st.id, st.n)
	Advance(L["Bought %s for %s."]:format(StepText(st), Money(paid)))
end

function A.OnBuyEvent(event, a1, a2)
	local b = A.buy
	if not b or b.state ~= "waiting" then return end
	local st = b.steps[b.i]
	local AHA = C_AuctionHouse
	if st.kind == "commodity" then
		if event == "COMMODITY_PRICE_UPDATED" and b.phase == "quote" then
			local unit, total = Num(a1), Num(a2)
			total = type(total) == "number" and total or (type(unit) == "number" and unit * st.n or math.huge)
			local limit = math.floor(st.expected * (1 + A.Guard() / 100))
			if total > limit then
				pcall(AHA.CancelCommoditiesPurchase)
				local pct = st.expected > 0 and math.floor((total / st.expected - 1) * 100 + 0.5) or 0
				Log(st, "rose", total, ("+%d%%"):format(pct))
				Advance(L["%s skipped: its price rose %d%% (%s; guard +%d%%)."]:format(StepText(st), pct, Money(total), A.Guard()))
				return
			end
			if Gold() < total then
				pcall(AHA.CancelCommoditiesPurchase)
				Log(st, "gold", total)
				Stop(L["not enough gold for %s (it costs %s, you have %s)"]:format(StepText(st), Money(total), Money(Gold())))
				return
			end
			st.quoted, b.phase = total, "confirm"
			if not pcall(AHA.ConfirmCommoditiesPurchase, st.id, st.n) then
				Log(st, "failed", total)
				Stop(L["the game refused to buy %s"]:format(StepText(st)))
			end
		elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
			pcall(AHA.CancelCommoditiesPurchase)
			Log(st, "unavailable")
			Stop(L["%s: its price isn't available (sold out or changed): Scan again"]:format(StepText(st)))
		elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and b.phase == "confirm" then
			Bought(st, st.quoted or st.expected)
		elseif event == "COMMODITY_PURCHASE_FAILED" or event == "AUCTION_HOUSE_SHOW_ERROR" then
			if b.phase == "quote" then pcall(AHA.CancelCommoditiesPurchase) end
			Log(st, "failed", st.quoted)
			Stop(L["buying %s failed"]:format(StepText(st)))
		end
	else
		if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" and Num(a1) == st.auction then
			Bought(st, st.expected)
		elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
			Log(st, "failed")
			Stop(L["buying %s failed (sold already, or not enough gold)"]:format(StepText(st)))
		end
	end
end

-- the AH closed: a purchase waiting is cancelled, the buying stopped
function A.CancelBuy(reason)
	local b = A.buy
	if not b or (b.state ~= "waiting" and b.state ~= "ready") then return end
	local st = b.steps[b.i]
	if b.state == "waiting" and st then
		if st.kind == "commodity" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
		Log(st, "cancelled")
	end
	Stop(reason or L["the Auction House closed"])
end

-- the cart's bar (on the list) and view
function A.BuildCart(panel, T, V)
	local bar = CreateFrame("Frame", nil, panel)
	bar:SetPoint("BOTTOMLEFT", 8, 64)
	bar:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	bar:SetHeight(24)
	bar.checkout = V.Button(bar, L["Checkout (%d)"]:format(0), 130, 22, function() A.SetView("cart") end)
	bar.checkout:SetPoint("LEFT", 2, 0)
	V.Tip(bar.checkout, L["Checkout cart"], L["Your cart (this character's): the items, their prices and the total. Scan there prices them exactly; Buy asks first, and each purchase is its own click."])
	bar.text = T.Font(bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10, GREY)
	bar.text:SetPoint("LEFT", bar.checkout, "RIGHT", 8, 0)
	bar.text:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
	bar.text:SetJustifyH("LEFT")
	panel.cartBar = bar
	local cv = CreateFrame("Frame", nil, panel)
	cv:SetPoint("TOPLEFT", 0, 0)
	cv:SetPoint("BOTTOMRIGHT", 0, 0)
	cv.rows = {}
	for i = 1, A.CART_ROWS do
		local r = CreateFrame("Frame", nil, cv)
		r:SetHeight(A.CART_ROW_H - 2)
		r:SetPoint("TOPLEFT", 8, -56 - (i - 1) * A.CART_ROW_H)
		r:SetPoint("RIGHT", cv, "RIGHT", -8, 0)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 20)
		r.icon:SetPoint("TOPLEFT", 2, -2)
		r.name = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12)
		r.name:SetPoint("TOPLEFT", 26, -4)
		r.name:SetWidth(196)
		r.name:SetJustifyH("LEFT")
		r.hover = CreateFrame("Button", nil, r)
		r.hover:SetPoint("TOPLEFT", 0, 0)
		r.hover:SetSize(222, 22)
		r.hover:SetScript("OnEnter", function(self) if r.id then V.ItemTooltip(self, r.id, I.Market and I.Market.Lines) end end)
		r.hover:SetScript("OnLeave", function() V.HideItemTooltip() end)
		r.remove = V.Button(r, "x", 18, 18, function() if r.id then I.CartRemove(r.id) end end)
		r.remove:SetPoint("TOPRIGHT", 0, -2)
		V.Tip(r.remove, L["Remove"], L["Take it out of the cart."])
		r.minus = V.Button(r, "-", 18, 18, function() local e = r.id and I.CartLine(r.id) if e and e.n > 1 then I.CartSet(r.id, e.n - (IsShiftKeyDown and IsShiftKeyDown() and 10 or 1)) end end)
		r.minus:SetPoint("TOPLEFT", 26, -22)
		r.qty = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12, T.GOLD)
		r.qty:SetPoint("TOPLEFT", 46, -24)
		r.qty:SetWidth(34)
		r.qty:SetJustifyH("CENTER")
		r.plus = V.Button(r, "+", 18, 18, function() local e = r.id and I.CartLine(r.id) if e then I.CartSet(r.id, e.n + (IsShiftKeyDown and IsShiftKeyDown() and 10 or 1)) end end)
		r.plus:SetPoint("TOPLEFT", 82, -22)
		V.Tip(r.plus, L["Quantity"], L["+ / -: one more or less (shift: 10)."])
		r.each = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10, GREY)
		r.each:SetPoint("TOPLEFT", 104, -25)
		r.each:SetWidth(70)
		r.each:SetJustifyH("LEFT")
		r.line = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 11)
		r.line:SetPoint("TOPRIGHT", 0, -25)
		r.line:SetWidth(76)
		r.line:SetJustifyH("RIGHT")
		r.note = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 9, GREY)
		r.note:SetPoint("TOPLEFT", 104, -36)
		r.note:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		r.note:SetJustifyH("LEFT")
		r:Hide()
		cv.rows[i] = r
	end
	cv.pager = V.Pager(cv, function(k)
		local n = I.CartCount()
		local _, cur, pages = V.PageOffset(math.floor(A.cartOffset / A.CART_ROWS) + 1, n, A.CART_ROWS)
		A.cartOffset = V.PageOffset(k == "first" and 1 or k == "prev" and cur - 1 or k == "next" and cur + 1 or pages, n, A.CART_ROWS)
		A.Refresh()
	end, A.W - 16 - 4 * 30 - 18)
	cv.pager:SetPoint("TOPLEFT", 8, -56 - A.CART_ROWS * A.CART_ROW_H - 2)
	cv.empty = T.Font(cv:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12, { 0.6, 0.6, 0.6 })
	cv.empty:SetPoint("TOPLEFT", 14, -60)
	cv.empty:SetPoint("RIGHT", cv, "RIGHT", -10, 0)
	cv.empty:SetJustifyH("LEFT")
	cv.empty:SetText(L["The cart is empty: Back, then + on the items to buy."])
	cv.total = T.Font(cv:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 13, T.GOLD)
	cv.total:SetPoint("BOTTOMLEFT", 12, 166)
	cv.total:SetPoint("RIGHT", cv, "RIGHT", -10, 0)
	cv.total:SetJustifyH("LEFT")
	cv.gold = T.Font(cv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11, GREY)
	cv.gold:SetPoint("BOTTOMLEFT", 12, 150)
	cv.gold:SetPoint("RIGHT", cv, "RIGHT", -10, 0)
	cv.gold:SetJustifyH("LEFT")
	cv.status = T.Font(cv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10, { 0.8, 0.8, 0.8 })
	cv.status:SetPoint("BOTTOMLEFT", 12, 116)
	cv.status:SetPoint("RIGHT", cv, "RIGHT", -10, 0)
	cv.status:SetHeight(32)
	cv.status:SetJustifyH("LEFT")
	cv.status:SetJustifyV("BOTTOM")
	cv.next = V.Button(cv, L["Buy next"], A.W - 16, 22, function() A.BuyNext() end)
	cv.next:SetPoint("BOTTOMLEFT", 8, 90)
	V.Tip(cv.next, L["Buy next"], L["Buys the next purchase in the cart (each needs its own click: the game's rule)."])
	cv.next:Hide()
	cv.back = V.Button(cv, L["Back"], 60, 22, function() A.SetView("list") end)
	cv.back:SetPoint("BOTTOMLEFT", 8, 64)
	cv.scan = V.Button(cv, L["Scan"], 70, 22, function() A.CartScan() end)
	cv.scan:SetPoint("BOTTOMLEFT", 72, 64)
	V.Tip(cv.scan, L["Scan"], L["Prices each cart item exactly: its cheapest listings now (enough for the quantity), and says when there aren't enough. Only reads: nothing is bought. Buy needs it (this visit)."])
	cv.buyBtn = V.Button(cv, L["Buy"], 110, 22, function() A.AskBuy() end)
	cv.buyBtn:SetPoint("BOTTOMRIGHT", -8, 64)
	V.Tip(cv.buyBtn, L["Buy"], function() return L["Asks first. Then each purchase is its own click (Yes, then Buy next). Price guard: +%d%% (Settings)."]:format(A.Guard()) end)
	cv:Hide()
	panel.cv = cv
	-- the ask: Yes / No (Valhalla's own, over the panel)
	local c = CreateFrame("Frame", "ValhallaCartConfirm", panel, "BackdropTemplate")
	c:SetSize(A.W - 16, 210)
	c:SetPoint("CENTER", panel, "CENTER", 0, 0)
	if c.SetFrameStrata then c:SetFrameStrata("DIALOG") end
	T.Skin(c, 0.98)
	c:EnableMouse(true)
	c.text = T.Font(c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 11)
	c.text:SetPoint("TOPLEFT", 10, -10)
	c.text:SetPoint("RIGHT", c, "RIGHT", -10, 0)
	c.text:SetJustifyH("LEFT")
	c.yes = V.Button(c, L["Yes"], 90, 22, function()
		c:Hide()
		local steps, total = A.pendingSteps, A.pendingTotal
		A.pendingSteps = nil
		if steps then A.BuyStart(steps, total) end
	end)
	c.yes:SetPoint("BOTTOMLEFT", 12, 10)
	c.no = V.Button(c, L["No"], 90, 22, function() c:Hide() A.pendingSteps = nil end)
	c.no:SetPoint("BOTTOMRIGHT", -12, 10)
	c:Hide()
	panel.confirm = c
end

function A.RefreshCart()
	local cv = panel.cv
	local house = I.Scan.House()
	local cart = I.Cart()
	local cur, pages
	A.cartOffset, cur, pages = I.Views.PageOffset(math.floor(A.cartOffset / A.CART_ROWS) + 1, #cart, A.CART_ROWS)
	cv.pager:SetShown(#cart > A.CART_ROWS)
	cv.pager.Set(cur, pages, L["%d of %d"]:format(cur, pages))
	cv.empty:SetShown(#cart == 0)
	local total, allPriced, short = 0, #cart > 0, 0
	for _, e in ipairs(cart) do
		local x = A.LinePrice(house, e)
		total = total + x.line
		if not x.priced then allPriced = false end
		if x.priced and x.got < e.n then short = short + 1 end
	end
	for i, r in ipairs(cv.rows) do
		local e = cart[A.cartOffset + i]
		if e then
			local x = A.LinePrice(house, e)
			r.id = e.id
			r.icon:SetTexture(I.ItemIcon(e.id))
			r.name:SetText(I.ItemName(e.id))
			r.qty:SetText(tostring(e.n))
			r.each:SetText(x.each > 0 and L["%s each"]:format(Money(x.each)) or "-")
			r.line:SetText(x.line > 0 and Money(x.line) or "-")
			r.note:SetText(x.note or "")
			local col = x.noteColor or GREY
			r.note:SetTextColor(col[1], col[2], col[3])
			r:Show()
		else
			r.id = nil
			r:Hide()
		end
	end
	local gold = Gold()
	cv.total:SetText(L["Total: %s"]:format(Money(total)) .. (allPriced and "" or (" " .. L["(estimate)"])))
	cv.gold:SetText(L["Your gold: %s"]:format(Money(gold)) .. (total > gold and ("  " .. L["(not enough)"]) or ""))
	if total > gold then cv.gold:SetTextColor(RED[1], RED[2], RED[3]) else cv.gold:SetTextColor(GREY[1], GREY[2], GREY[3]) end
	local b = A.buy
	local status
	if b and (b.state == "ready" or b.state == "waiting") then
		local st = b.steps[b.i]
		if b.state == "waiting" then
			status = L["Buying %s (%d/%d)..."]:format(StepText(st), b.i, #b.steps)
			cv.next:Hide()
		else
			cv.next.text:SetText(L["Buy next: %s (%d/%d) - %s"]:format(StepText(st), b.i, #b.steps, Money(st.expected)))
			cv.next:Show()
			status = b.note or ""
		end
	else
		cv.next:Hide()
		if b and b.note then status = b.note end
	end
	if A.status then status = A.status A.status = nil end
	if not status then
		status = #cart == 0 and "" or I.Scan.Running() and "" or not allPriced and L["Press Scan to price the cart exactly, then Buy."]
			or short > 0 and L["%d item(s) short: buys what's listed."]:format(short) or L["Priced: press Buy (it asks first)."]
	end
	cv.status:SetText(status)
	local busy = (b and b.state == "waiting") or I.Scan.Running()
	I.Views.Off(cv.buyBtn, #cart == 0 or busy or (b and b.state == "ready"))
	cv.scan.text:SetText(I.Scan.Running() and L["Stop"] or L["Scan"])
	I.Views.Off(cv.scan, #cart == 0 and not I.Scan.Running())
end

local function Build()
	local ah = _G.AuctionHouseFrame
	if panel or not ah then return panel end
	if InCombatLockdown() then A.waiting = true return nil end   -- (secure buttons aren't made in combat: once it ends)
	local T, V = I.Tabs, I.Views
	panel = CreateFrame("Frame", "ValhallaAHList", ah, "BackdropTemplate")
	panel:SetSize(A.W, A.H)
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
	T.Skin(panel, 0.96, nil, true)   -- (v0.4.2.1: framed: in Norse the bronze frame and its corner brackets)
	panel:EnableMouse(true)
	local title = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 13, T.GOLD)
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["Valhalla: Shopping List"])
	if ns.Style then ns.Style.Title(title, 13) end
	local minimize = V.Button(panel, "-", 20, 20, function() A.SetMinimized(true) end)
	minimize:SetPoint("TOPRIGHT", -6, -6)
	panel.minimize = minimize
	panel.picker = V.Picker(panel, A.W - 20)
	panel.picker:SetPoint("TOPLEFT", 10, -30)
	panel.sub = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10, { 0.6, 0.6, 0.6 })
	panel.sub:SetPoint("TOPLEFT", 12, -58)
	panel.sub:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.sub:SetJustifyH("LEFT")
	panel.rows = {}
	for i = 1, A.ROWS do
		local r = CreateFrame("Frame", nil, panel)
		r:SetHeight(24)
		r:SetPoint("TOPLEFT", 8, -84 - (i - 1) * 26)
		r:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 20)
		r.icon:SetPoint("LEFT", 2, 0)
		r.name = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12)
		r.name:SetPoint("LEFT", 26, 0)
		r.name:SetWidth(104)   -- (1.2.7: 120; the cart's + after need)
		r.name:SetJustifyH("LEFT")
		r.hover = CreateFrame("Button", nil, r)
		r.hover:SetPoint("LEFT", 0, 0)
		r.hover:SetSize(130, 22)
		r.hover:SetScript("OnEnter", function(self) if r.id then V.ItemTooltip(self, r.id, I.Market and I.Market.Lines) end end)
		r.hover:SetScript("OnLeave", function() V.HideItemTooltip() end)
		r.need = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 12, T.GOLD)
		r.need:SetPoint("LEFT", 132, 0)
		r.need:SetWidth(40)
		r.need:SetJustifyH("LEFT")
		r.search = SearchButton(r, T, V)
		r.search:SetPoint("RIGHT", 0, 0)
		-- (1.2.7) the cart: + puts what's still needed in it (1 if done), - takes it out
		r.cart = V.Button(r, "+", 20, 18, function() A.RowCart(r) end)
		r.cart:SetPoint("RIGHT", r.search, "LEFT", -4, 0)
		V.Tip(r.cart, L["Checkout cart"], function()
			if not r.id then return "" end
			local e = I.CartLine(r.id)
			return e and L["%s is in the cart (x%d): click to take it out."]:format(I.ItemName(r.id), e.n)
				or L["Put %s in the cart (x%d), to buy it with Checkout."]:format(I.ItemName(r.id), math.max(1, r.needN or 1))
		end)
		r:Hide()
		panel.rows[i] = r
	end
	-- (v0.4.2.1: a page at a time, no scrolling: |<  <  1 of 2  >  >|)
	panel.pager = V.Pager(panel, function(k)
		local n = #A.Rows()
		local _, cur, pages = V.PageOffset(math.floor(A.offset / A.ROWS) + 1, n, A.ROWS)
		A.offset = V.PageOffset(k == "first" and 1 or k == "prev" and cur - 1 or k == "next" and cur + 1 or pages, n, A.ROWS)
		A.Refresh()
	end, A.W - 16 - 4 * 30 - 18)
	panel.pager:SetPoint("TOPLEFT", 8, -84 - A.ROWS * 26 - 2)
	panel.pager:Hide()
	panel.mail = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11, T.GOLD)
	panel.mail:SetPoint("BOTTOMLEFT", 12, 10)
	panel.mail:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.mail:SetJustifyH("LEFT")
	-- the AH check (v0.3.5): its button, what it's doing and a bar
	local check = CreateFrame("Frame", nil, panel)
	check:SetPoint("BOTTOMLEFT", 8, 26)
	check:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	check:SetHeight(34)
	check.button = V.Button(check, L["Scan"], 110, 22, function() A.CheckClick() end)
	check.button:SetPoint("TOPLEFT", 2, 0)
	check.button:HookScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Scan"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Full scan (the whole market, about 15 seconds) when its 15 minutes are up, else a quick scan of your items (shopping list, bags, bank). Keep the Auction House open. It only reads prices: nothing is posted, bid or bought. The quick scan uses the AH's own browse list (its results show there)."], 1, 1, 1, true)
		GameTooltip:AddLine(I.Scan.CooldownText(), 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	check.button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	check.status = T.Font(check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10, { 0.75, 0.75, 0.75 })
	check.status:SetPoint("LEFT", check.button, "RIGHT", 8, 0)
	check.status:SetPoint("RIGHT", check, "RIGHT", -2, 0)
	check.status:SetJustifyH("LEFT")
	check.track = check:CreateTexture(nil, "BACKGROUND")
	check.track:SetColorTexture(0, 0, 0, 0.6)
	check.track:SetPoint("BOTTOMLEFT", 2, 0)
	check.track:SetPoint("BOTTOMRIGHT", -2, 0)
	check.track:SetHeight(6)
	check.bar = check:CreateTexture(nil, "ARTWORK")
	check.bar:SetColorTexture(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.9)
	check.bar:SetPoint("TOPLEFT", check.track, "TOPLEFT", 0, 0)
	check.bar:SetPoint("BOTTOMLEFT", check.track, "BOTTOMLEFT", 0, 0)
	check.bar:SetWidth(1)
	panel.check = check
	A.BuildCart(panel, T, V)
	panel.title = title
	panel.empty = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12, { 0.6, 0.6, 0.6 })
	panel.empty:SetPoint("TOPLEFT", 14, -88)
	panel.empty:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.empty:SetJustifyH("LEFT")
	panel:Hide()
	-- minimized: a small button at the AH's top right, with how many items are needed
	mini = CreateFrame("Button", "ValhallaAHListButton", ah, "BackdropTemplate")
	mini:SetSize(30, 30)
	mini:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
	T.Skin(mini, 0.96)
	mini.icon = mini:CreateTexture(nil, "ARTWORK")
	mini.icon:SetPoint("TOPLEFT", 3, -3)
	mini.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	mini.icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
	mini.count = T.Font(mini:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 12, T.GOLD)
	mini.count:SetPoint("BOTTOMRIGHT", -2, 2)
	if mini.RegisterForClicks then mini:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
	mini:SetScript("OnClick", function(_, button)
		if button == "RightButton" then A.CheckClick() else A.SetMinimized(false) end
	end)
	mini.ring = mini:CreateTexture(nil, "OVERLAY")
	mini.ring:SetColorTexture(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.9)
	mini.ring:SetPoint("BOTTOMLEFT", 2, 2)
	mini.ring:SetHeight(3)
	mini.ring:SetWidth(1)
	mini.ring:Hide()
	mini:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Valhalla: Shopping List"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Click to show it again."], 1, 1, 1)
		GameTooltip:AddLine(A.CheckRunning() and L["Right-click: stop the scan."] or L["Right-click: scan."], 1, 1, 1)
		GameTooltip:AddLine(A.CheckStatus(), 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	mini:Hide()
	return panel
end

-- Scan from here (v0.4.0; v0.3.5's AH check button: now /valhalla invest diag ah)
function A.CheckRunning() return I.Scan and I.Scan.Running() or false end

function A.CheckClick()
	I.Scan.Toggle()
	A.CheckRefresh()
end

function A.CheckStatus()
	local Sc = I.Scan
	if Sc.Running() then
		local f, text = Sc.Progress()
		return ("%s (%d%%)"):format(text, math.floor(f * 100)), f
	end
	local last = Sc.last
	local cd = Sc.CooldownText()
	if Sc.NextFull() > 0 then cd = cd .. " " .. L["Scan: a quick scan now."] end
	if last then
		local what = last.kind == "full" and L["full scan"] or L["quick scan"]
		return cd .. " " .. L["Last %s: %s, %s."]:format(what, L[last.state] or last.state, Sc.Age(last.at)), nil
	end
	return cd, nil
end

local ticker = 0
function A.CheckRefresh()
	local running = A.CheckRunning()
	local text, f = A.CheckStatus()
	if panel and panel.check then
		local c = panel.check
		c.button.text:SetText(running and L["Stop"] or L["Scan"])
		c.status:SetText(text)
		local w = (c.track:GetWidth() or 0)
		if w <= 0 then w = A.W - 20 end
		c.bar:SetWidth(math.max(1, w * (f or 0)))
		c.bar:SetShown(running)
		c.track:SetShown(running)
		-- while it runs: the bar moves on its own (the scan's read gives no event), four times a second
		if running and not c.ticking then
			c.ticking = true
			c:SetScript("OnUpdate", function(_, e)
				ticker = ticker + (e or 0)
				if ticker < 0.25 then return end
				ticker = 0
				if not A.CheckRunning() then c.ticking = nil c:SetScript("OnUpdate", nil) end
				A.CheckRefresh()
			end)
		end
	end
	if mini then
		mini.ring:SetWidth(math.max(1, 26 * (f or 0)))
		mini.ring:SetShown(running)
		if running and not mini.ticking then
			mini.ticking = true
			mini:SetScript("OnUpdate", function(_, e)
				ticker = ticker + (e or 0)
				if ticker < 0.25 then return end
				ticker = 0
				if not A.CheckRunning() then mini.ticking = nil mini:SetScript("OnUpdate", nil) end
				A.CheckRefresh()
			end)
		end
	end
	return running, text, f
end

function A.SetMinimized(v)
	I.S.ahPanelMin = v and true or false
	A.Refresh()
end

-- the active list's Auction House items (what no vendor you've visited sells), whatever their state;
-- needed: how many are still to buy
function A.Rows()
	local list = I.ShoppingList()
	local rows, needed = {}, 0
	for _, r in ipairs(I.ListRows(list.list)) do
		if r.source == "ah" then
			rows[#rows + 1] = r
			if r.need > 0 then needed = needed + 1 end
		end
	end
	return rows, list, needed
end

function A.Refresh()
	if not panel then return end
	if not (on and I.ahOpen and I.S.ahPanel) then panel:Hide() mini:Hide() return end
	local rows, list, needed = A.Rows()
	if I.S.ahPanelMin then
		panel:Hide()
		mini.count:SetText(needed > 0 and tostring(needed) or "")
		mini:Show()
		A.CheckRefresh()
		return
	end
	mini:Hide()
	-- (1.2.7) the cart's view, or the list (its Checkout bar)
	local cart = A.view == "cart"
	panel.cv:SetShown(cart)
	panel.title:SetText(cart and L["Valhalla: Checkout cart"] or L["Valhalla: Shopping List"])
	panel.picker:SetShown(not cart)
	panel.sub:SetShown(not cart)
	panel.cartBar:SetShown(not cart)
	panel.check.button:SetShown(not cart)
	if cart then
		panel.picker.menu:Hide()
		panel.empty:Hide()
		panel.pager:Hide()
		for _, r in ipairs(panel.rows) do r:Hide() end
		A.RefreshCart()
		local mailedC = {}
		for _, d in ipairs(I.ListRows(list.list)) do if d.mail > 0 then mailedC[#mailedC + 1] = ("%s x%d"):format(d.name, d.mail) end end
		panel.mail:SetText(#mailedC > 0 and L["In the mail: %s"]:format(table.concat(mailedC, ", ")) or "")
		A.CheckRefresh()
		panel:Show()
		return
	end
	if panel.confirm then panel.confirm:Hide() end
	local nCart = I.CartCount()
	panel.cartBar.checkout.text:SetText(L["Checkout (%d)"]:format(nCart))
	panel.cartBar.text:SetText(nCart == 0 and L["+ on a row: into the cart"] or "")
	panel.picker.Update()
	if list.list then
		panel.sub:SetText(L["Still needed: %d. Done %d / %d. Search, then buy with the AH's own button."]:format(needed, list.done, list.total))
		panel.empty:SetText(L["Nothing on this list from the Auction House."])
	else
		panel.sub:SetText("")
		panel.empty:SetText(#I.Lists() == 0 and L["No shopping list yet: build one in Investments > Shopping List (click the button above)."]
			or I.NoneChosen() and L["No list selected (None). Choose one above."]
			or L["Choose a shopping list above."])
	end
	panel.empty:SetShown(#rows == 0)
	local cur, pages
	local lid = list.list and list.list.id or false
	if lid ~= A.shownList then A.shownList, A.offset = lid, 0 end   -- (another list: its first page)
	A.offset, cur, pages = I.Views.PageOffset(math.floor(A.offset / A.ROWS) + 1, #rows, A.ROWS)
	panel.pager:SetShown(#rows > A.ROWS)
	panel.pager.Set(cur, pages, L["%d of %d"]:format(cur, pages))
	for i, r in ipairs(panel.rows) do
		local d = rows[A.offset + i]
		if d then
			r.icon:SetTexture(I.ItemIcon(d.id))
			r.name:SetText(d.name)
			if d.need > 0 then
				r.need:SetText("x" .. d.need)
				r.need:SetTextColor(1, 0.82, 0)
			elseif d.short > 0 then
				r.need:SetText(L["In mail"])
				r.need:SetTextColor(1, 0.82, 0)
			else
				r.need:SetText(L["Done"])
				r.need:SetTextColor(0.3, 0.9, 0.3)
			end
			r.id = d.id
			r.needN = d.need
			r.cart.text:SetText(I.CartLine(d.id) and "-" or "+")
			r:Show()
		else
			r.id = nil
			r:Hide()
		end
	end
	-- bought, in the mail (not to buy again)
	local mailed = {}
	for _, d in ipairs(I.ListRows(list.list)) do if d.mail > 0 then mailed[#mailed + 1] = ("%s x%d"):format(d.name, d.mail) end end
	panel.mail:SetText(#mailed > 0 and L["In the mail: %s"]:format(table.concat(mailed, ", ")) or "")
	A.CheckRefresh()
	panel:Show()
end

function A.Show()
	if not on then return end
	if not A.visitAt or not A.visiting then A.visitAt, A.visiting = Now(), true end   -- (1.2.7: cart prices are this visit's)
	A.waiting = nil
	Build()
	-- (v0.4.2.1: the look painted again on this window each visit, the secure Search buttons refused as ever)
	if panel and ns.Style then ns.Style.ReskinUnder(panel) ns.Style.ReskinUnder(mini) end
	-- (the AH's Search button can be made after its frame: the targets set again on each visit)
	if panel then for _, r in ipairs(panel.rows) do if not r.search.armed then A.Arm(r.search) end end end
	A.Refresh()
end

-- for /valhalla look check: this window's frame in the look
function A.LookInfo()
	local vh = panel and panel.vh
	local n1 = vh and vh.parts and vh.parts.n1
	local info = {
		ahPanel = panel and true or false,
		ahLook = vh and vh.look or "none",
		ahFramed = vh and vh.framed and true or false,
		ahBronze = (n1 and n1:IsShown()) and true or false,
	}
	info.line = panel and ("AH side window: %s look, framed %s, bronze %s."):format(info.ahLook, info.ahFramed and "yes" or "no", info.ahBronze and "shown" or "hidden")
		or "AH side window: not built yet (open the Auction House once)."
	return info
end

function A.Hide()
	-- (1.2.7) the AH closed: buying stops, a purchase waiting cancelled; the cart's prices are for that visit only
	A.CancelBuy(L["the Auction House closed"])
	A.visiting, A.visitAt = nil, nil
	A.pendingSteps = nil
	if panel and panel.confirm then panel.confirm:Hide() end
	if panel then panel.picker.menu:Hide() panel:Hide() end
	if mini then mini:Hide() end
	A.pending = nil
end

function A.Enable()
	on = true
	if not A.listening then
		A.listening = true
		I.OnChanged(function() if on and I.ahOpen then A.Refresh() end end)
	end
	if I.ahOpen then A.Show() end
end

function A.Disable()
	on = false
	A.Hide()
end
