--------------------------------------------------------------------------------
-- The Watchlist (1.2.14): your own target prices per item, like limit orders on a stock market.
--   Buy target   BUY when the AH's lowest price is at or below it
--   Sell target  SELL when the AH's lowest price is at or above it
-- The price is the listed lowest buyout per unit (Scan.lua's S.Lowest: the dump filter if it's on), never after
-- the AH's cut. Either target may be blank. Each item's targets belong to one house (Alliance, Horde, Neutral:
-- the one you're at, else the one AH Market shows) and stay until you change or remove them.
-- Saved (1.2.58): ValhallaInvestDB.realms[realm].chars[name].targets[itemID] = { house, buy, sell, set,
--   added, lastMet, lastSig, lastPrice, alerted } (copper). This character's list (not shared).
-- (1.2.57 and before: realms[realm].targets, shared by every character on that realm key.)
-- Where: AH Market > Watchlist (add by name, Edit, columns Item, Lowest, Buy <= target, Sell >= target, Signal,
-- Last met); alt-click any item (it goes on the list, its targets open); right-click any item > Set target...;
-- a Target line under item tooltips (Tooltip.lua), green when met.
-- After a scan (full or quick; Scan.lua's Finish, state "done"): the house's targets checked against what that
-- scan saw; any met: a popup in Valhalla's Look (click an item: its History), a chat line each, a sound
-- (setting). Alert frequency: "every" scan while met (default) | "once" until that target changes. Near
-- (Off / 5% / 10%, default 5%): only the Signal column, no popup.
-- Read only, like the scanner: nothing is bought, posted or bid (WoW Forever blocks an addon's purchases).
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local V, T, M = I.Views, I.Tabs, I.Market
local W = {}
I.Watch = W

local function S() return I.Scan end
local Now, Trim = ns.Util.Time, ns.Util.Trim

W.NEARS = { [0] = true, [5] = true, [10] = true }
W.POPUP_MAX = 10                  -- (rows in the popup; the rest: "and N more")
W.POP_W, W.ROW_H = 420, 22
W.SOUND = 8959                    -- (SOUNDKIT.RAID_WARNING)
W.GREEN, W.SELL, W.NEAR, W.GREY = { 0.3, 0.9, 0.3 }, { 1, 0.6, 0.2 }, { 0.85, 0.85, 0.7 }, { 0.6, 0.6, 0.6 }

--------------------------------------------------------------------------------
-- The saved targets
--------------------------------------------------------------------------------

function W.Store()
	local c = I.char
	if not c then return {} end
	if type(c.targets) ~= "table" then c.targets = {} end
	return c.targets
end
function W.Get(id)
	id = tonumber(id)
	local t = id and W.Store()[id]
	return type(t) == "table" and t or nil
end
function W.Has(id) return W.Get(id) ~= nil end
function W.Count() local n = 0 for _ in pairs(W.Store()) do n = n + 1 end return n end

local HOUSE = {}
for _, h in ipairs(M.HOUSES) do HOUSE[h] = true end
W.IsHouse = function(h) return HOUSE[h] == true end
-- a new target's house: the AH you're at, else the house AH Market shows
function W.DefaultHouse()
	if I.ahOpen and S() then
		local h = S().House()
		if HOUSE[h] then return h end
	end
	local h = M.House()
	return HOUSE[h] and h or "Alliance"
end
function W.HouseOf(t) return (t and HOUSE[t.house]) and t.house or W.DefaultHouse() end

local function Money(v) v = tonumber(v) if v and v > 0 then return math.floor(v + 0.5) end return nil end

-- on the list (no targets yet); returns its entry and whether it's new
function W.Add(id, house)
	id = tonumber(id)
	if not id then return nil end
	local store = W.Store()
	local t = store[id]
	if type(t) == "table" then return t, false end
	t = { house = HOUSE[house] and house or W.DefaultHouse(), added = Now() }
	store[id] = t
	I.Changed()
	return t, true
end

-- its targets (copper; nil: none), and its house; a change re-arms "once" alerts
function W.Set(id, buy, sell, house)
	id = tonumber(id)
	if not id then return nil end
	local t = W.Add(id, house)
	buy, sell = Money(buy), Money(sell)
	if t.buy ~= buy or t.sell ~= sell or (HOUSE[house] and t.house ~= house) then t.alerted = nil end
	t.buy, t.sell = buy, sell
	if HOUSE[house] then t.house = house end
	t.set = Now()
	I.Changed()
	return t
end

function W.Remove(id)
	id = tonumber(id)
	if not (id and W.Store()[id]) then return false end
	W.Store()[id] = nil
	if W.editor and W.editor.id == id then W.editor:Hide() end
	I.Changed()
	return true
end

function W.NearPct()
	local n = tonumber(I.S and I.S.watchNear)
	if n and W.NEARS[n] then return n end
	return 5
end
function W.Mode() return (I.S and I.S.watchAlerts == "once") and "once" or "every" end

-- the items a quick scan of house should look up
function W.InterestIDs(house)
	local out = {}
	for id, t in pairs(W.Store()) do
		if type(t) == "table" and (not house or W.HouseOf(t) == house) then out[#out + 1] = id end
	end
	table.sort(out)
	return out
end

--------------------------------------------------------------------------------
-- Signals
--------------------------------------------------------------------------------

-- "buy" | "sell" | "near" (with how far, in whole per cent rounded up, and its side) | nil; low: the lowest price
function W.Signal(t, low, near)
	low = tonumber(low)
	if not (t and low and low > 0) then return nil end
	if t.buy and low <= t.buy then return "buy" end
	if t.sell and low >= t.sell then return "sell" end
	near = tonumber(near) or 0
	if near <= 0 then return nil end
	local best, side
	if t.buy then
		local d = (low - t.buy) * 100 / t.buy
		if d <= near then best, side = d, "buy" end
	end
	if t.sell then
		local d = (t.sell - low) * 100 / t.sell
		if d <= near and (not best or d < best) then best, side = d, "sell" end
	end
	if best then return "near", math.max(1, math.ceil(best - 1e-9)), side end
	return nil
end

-- one item now: { id, t, house, low, c, sig, pct, side }
function W.Eval(id, t, near)
	t = t or W.Get(id)
	if not t then return nil end
	local house = W.HouseOf(t)
	local low, c = S().Lowest(house, id)
	local sig, pct, side = W.Signal(t, low, near == nil and W.NearPct() or near)
	return { id = id, t = t, house = house, low = low, c = c, sig = sig, pct = pct, side = side }
end

function W.SignalText(e)
	if not e then return "-" end
	if e.sig == "buy" then return L["BUY"] end
	if e.sig == "sell" then return L["SELL"] end
	if e.sig == "near" then return L["Near %d%% (%s)"]:format(e.pct, e.side == "buy" and L["buy"] or L["sell"]) end
	return "-"
end
function W.SignalColor(e)
	if e and e.sig == "buy" then return W.GREEN end
	if e and e.sig == "sell" then return W.SELL end
	if e and e.sig == "near" then return W.NEAR end
	return W.GREY
end
-- the Signal column's order: BUY, SELL, then the nearest; none last
function W.SignalRank(e)
	if not e then return nil end
	if e.sig == "buy" then return 1 end
	if e.sig == "sell" then return 2 end
	if e.sig == "near" then return 10 + (e.pct or 0) end
	return nil
end

-- the Watchlist's rows (every item, each at its own house)
function W.Rows()
	local out = {}
	local near = W.NearPct()
	for id, t in pairs(W.Store()) do
		if type(t) == "table" then out[#out + 1] = W.Eval(id, t, near) end
	end
	return out
end

-- under item tooltips: { label, coins, r, g, b }
function W.TooltipLines(id)
	local t = W.Get(id)
	if not (t and (t.buy or t.sell)) then return {} end
	local P = I.Tooltip
	local house = W.HouseOf(t)
	local low = S().Lowest(house, id)
	local sig = W.Signal(t, low, 0)
	local where = house ~= M.House() and (" (" .. L[house] .. ")") or ""
	local out = {}
	local G = W.GREEN
	if t.buy then
		local met = sig == "buy"
		out[#out + 1] = { L["Target buy <="] .. where .. (met and (" " .. L["(met)"]) or ""), P.Coins(t.buy), met and G[1] or nil, met and G[2] or nil, met and G[3] or nil }
	end
	if t.sell then
		local met = sig == "sell"
		out[#out + 1] = { L["Target sell >="] .. where .. (met and (" " .. L["(met)"]) or ""), P.Coins(t.sell), met and G[1] or nil, met and G[2] or nil, met and G[3] or nil }
	end
	return out
end

--------------------------------------------------------------------------------
-- After a scan: what's met, and the alert
--------------------------------------------------------------------------------

-- house's targets against the prices a scan saw at or after since (the scan's own minute): met ones recorded
-- (lastMet, lastSig, lastPrice); returns those to alert (per the alert frequency)
function W.Check(house, since)
	local out = {}
	local once = W.Mode() == "once"
	local now = Now()
	for id, t in pairs(W.Store()) do
		if type(t) == "table" and (t.buy or t.sell) and W.HouseOf(t) == house then
			local c = S().Cur(house, id)
			if c and (not since or (c.t or 0) >= since) then
				local low = S().Lowest(house, id)
				local sig = W.Signal(t, low, 0)
				if sig == "buy" or sig == "sell" then
					t.lastMet, t.lastSig, t.lastPrice = now, sig, low
					local key = ("%s:%s:%s"):format(sig, tostring(t.buy or ""), tostring(t.sell or ""))
					if not (once and t.alerted == key) then
						t.alerted = key
						out[#out + 1] = { id = id, t = t, house = house, low = low, sig = sig, target = sig == "buy" and t.buy or t.sell }
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.sig ~= b.sig then return a.sig == "buy" end
		local na, nb = I.ItemName(a.id) or "", I.ItemName(b.id) or ""
		if na ~= nb then return na < nb end
		return a.id < b.id
	end)
	return out
end

function W.OnScanDone(r)
	if not (r and r.house and HOUSE[r.house]) then return {} end
	local m = S().Market(r.house)
	if not m then return {} end
	local since = r.tmin and S().AbsTime(m, r.tmin) or nil
	local met = W.Check(r.house, since)
	W.last = { house = r.house, kind = r.kind, met = #met, at = Now() }
	if #met > 0 then W.Alert(met, r.house) end
	I.Changed()
	return met
end

-- one met target, for chat: "BUY Linen Cloth: lowest 1s 20c <= your buy target 1s 50c (Alliance)"
function W.ChatLine(e)
	local _, link = V.ItemData(e.id)
	local name = link or I.ItemName(e.id)
	local Money = S().Money
	if e.sig == "buy" then
		return L["Watchlist BUY %s: lowest %s <= your buy target %s (%s)."]:format(name, Money(e.low), Money(e.target), e.house)
	end
	return L["Watchlist SELL %s: lowest %s >= your sell target %s (%s)."]:format(name, Money(e.low), Money(e.target), e.house)
end

function W.Alert(met, house)
	for _, e in ipairs(met) do ns:Print("%s", W.ChatLine(e)) end
	if I.S.watchSound ~= false and PlaySound then
		local id = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or W.SOUND
		pcall(PlaySound, id, "Master")
		W.played = (W.played or 0) + 1
	end
	W.ShowPopup(met, house)
end

--------------------------------------------------------------------------------
-- The popup: "Watchlist targets met (Alliance)", in Valhalla's Look (UI/Style.lua's popup frame)
--------------------------------------------------------------------------------

function W.Popup()
	if W.popup then return W.popup end
	local f = CreateFrame("Frame", "ValhallaWatchAlert", UIParent)
	f:SetSize(W.POP_W, 120)
	f:SetFrameStrata("DIALOG")
	if f.SetClampedToScreen then f:SetClampedToScreen(true) end
	f:SetMovable(true)
	f:EnableMouse(true)
	if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	f:SetPoint("TOP", UIParent, "TOP", 0, -150)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.title:SetPoint("TOPRIGHT", -34, -10)
	f.title:SetJustifyH("LEFT")
	T.Font(f.title, 13)
	if ns.Style and ns.Style.Title then ns.Style.Title(f.title, 13) end
	f.close = V.Button(f, "x", 20, 20, function() f:Hide() end)
	f.close:SetPoint("TOPRIGHT", -8, -6)
	f.rows = {}
	for i = 1, W.POPUP_MAX do
		local r = CreateFrame("Button", nil, f)
		r:SetSize(W.POP_W - 24, W.ROW_H - 2)
		r:SetPoint("TOPLEFT", 12, -34 - (i - 1) * W.ROW_H)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18)
		r.icon:SetPoint("LEFT", 0, 0)
		r.sig = V.Text(r, 12)
		r.sig:SetPoint("LEFT", 22, 0)
		r.sig:SetWidth(40)
		r.sig:SetJustifyH("LEFT")
		r.name = V.Text(r, 12)
		r.name:SetPoint("LEFT", 64, 0)
		r.name:SetWidth(150)
		r.name:SetJustifyH("LEFT")
		if r.name.SetWordWrap then r.name:SetWordWrap(false) end
		r.price = V.Text(r, 11)
		r.price:SetPoint("RIGHT", 0, 0)
		r.price:SetWidth(W.POP_W - 24 - 220)
		r.price:SetJustifyH("RIGHT")
		r:SetScript("OnClick", function(self) if self.id then W.OpenHistory(self.id) end end)
		r:SetScript("OnEnter", function(self) if self.id then V.ItemTooltip(self, self.id) end end)
		r:SetScript("OnLeave", function() V.HideItemTooltip() end)
		r:Hide()
		f.rows[i] = r
	end
	f.more = V.Text(f, 11, W.GREY)
	f.more:SetJustifyH("LEFT")
	f.hint = V.Text(f, 10, W.GREY)
	f.hint:SetJustifyH("LEFT")
	f.hint:SetText(L["Click an item for its price history. Drag to move."])
	if ns.Style and ns.Style.Popup then ns.Style.Popup(f) elseif ns.Look and ns.Look.Panel then ns.Look:Panel(f, { alpha = 0.9 }) else T.SkinFlat(f, 0.95) end
	f:Hide()
	W.popup = f
	return f
end

function W.ShowPopup(met, house)
	local f = W.Popup()
	f.title:SetText(L["Watchlist targets met (%s)"]:format(house or "?"))
	f.house = house
	local Money = S().Money
	local shown = math.min(#met, W.POPUP_MAX)
	for i, r in ipairs(f.rows) do
		local e = met[i]
		if e then
			r.id = e.id
			r.icon:SetTexture(I.ItemIcon(e.id))
			local name, _, q = V.ItemData(e.id)
			r.name:SetText(name or I.ItemName(e.id))
			r.name:SetTextColor(V.QualityColor(q))
			local c = e.sig == "buy" and W.GREEN or W.SELL
			r.sig:SetText(e.sig == "buy" and L["BUY"] or L["SELL"])
			r.sig:SetTextColor(c[1], c[2], c[3])
			r.price:SetText((e.sig == "buy" and L["%s <= target %s"] or L["%s >= target %s"]):format(Money(e.low), Money(e.target)))
			r:Show()
		else
			r.id = nil
			r:Hide()
		end
	end
	local y = -34 - shown * W.ROW_H - 4
	f.more:ClearAllPoints()
	f.more:SetPoint("TOPLEFT", 12, y)
	f.more:SetText(#met > shown and L["and %d more (AH Market > Watchlist)"]:format(#met - shown) or "")
	if #met > shown then y = y - 16 end
	f.hint:ClearAllPoints()
	f.hint:SetPoint("TOPLEFT", 12, y)
	f:SetHeight(-y + 22)
	f.met = met
	f:Show()
	return f
end

-- an item's History in AH Market (the window opened if it's closed)
function W.OpenHistory(id)
	M.historyID = id
	local function Go()
		local v = T.Views and T.Views().invest
		local root = v and v.page
		local mp = root and root.Page and root.Page("market")
		if not (mp and mp.ShowSub) then return false end
		-- (History the view it opens on, the others hidden: the page's own refresh shows only its current view)
		mp.current = "history"
		for _, g in ipairs(mp.allSubs or {}) do if g.view ~= "history" then g:Hide() end end
		if root.current == "market" and mp:IsVisible() then mp:ShowSub("history") end
		return true
	end
	Go()
	local opened = T.Open and T.Open("invest", "market")
	if opened then Go() if C_Timer and C_Timer.After then C_Timer.After(0.2, Go) end end
	return opened
end

--------------------------------------------------------------------------------
-- The target editor (1.2.15): Buy and Sell, each three number boxes (gold, silver, copper) with the coin
-- icons; the house. All three blank: no target; a blank box is 0 when another is filled; silver or copper
-- over 99 carries over (150s: 1g 50s), shown so when the box is left. 500 wide; "Lowest now" its own line
-- under the title; every text line a fixed width (nothing runs past the frame in either Look).
--------------------------------------------------------------------------------

W.EDIT_W, W.EDIT_H, W.EDIT_PAD = 500, 248, 18
W.COIN_W = { 64, 40, 40 }        -- the gold, silver, copper boxes
W.COIN_MAX = { 6, 3, 3 }         -- digits each (silver / copper: 3, so 150 can be typed and carried)
W.COIN_ICONS = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }

-- copper -> the three boxes' texts (nil: all blank; no gold: its box blank)
function W.CoinTexts(v)
	v = Money(v)
	if not v then return "", "", "" end
	local g, s, c = math.floor(v / 10000), math.floor(v / 100) % 100, v % 100
	return g > 0 and tostring(g) or "", tostring(s), tostring(c)
end

-- the three texts -> copper (nil: no target), ok
function W.FromCoins(g, s, c)
	local t = { Trim(g), Trim(s), Trim(c) }
	if t[1] == "" and t[2] == "" and t[3] == "" then return nil, true end
	local v = 0
	for i, x in ipairs(t) do
		if x ~= "" then
			if not x:match("^%d+$") then return nil, false end
			v = v + tonumber(x) * ({ 10000, 100, 1 })[i]
		end
	end
	return Money(v), true
end

local function RowRead(row) return W.FromCoins(row[1]:GetText(), row[2]:GetText(), row[3]:GetText()) end
local function RowFill(row, v)
	local a, b, c = W.CoinTexts(v)
	row[1]:SetText(a) row[2]:SetText(b) row[3]:SetText(c)
end
-- a box left: the row shown carried over (150s -> 1g 50s); a bad or blank row left as typed
local function RowNormalize(row)
	local v, ok = RowRead(row)
	if ok and v then RowFill(row, v) end
end
W.RowRead, W.RowFill, W.RowNormalize = RowRead, RowFill, RowNormalize

function W.Editor()
	if W.editor then return W.editor end
	local PAD, EW = W.EDIT_PAD, W.EDIT_W
	local TW = EW - 2 * PAD          -- every full-width text line
	local e = CreateFrame("Frame", "ValhallaWatchEdit", UIParent, "BackdropTemplate")
	e:SetSize(EW, W.EDIT_H)
	e:SetFrameStrata("DIALOG")
	if e.SetClampedToScreen then e:SetClampedToScreen(true) end
	e:SetMovable(true)
	e:EnableMouse(true)
	if e.RegisterForDrag then e:RegisterForDrag("LeftButton") end
	e:SetScript("OnDragStart", function(self) self:StartMoving() end)
	e:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	e:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	e.icon = e:CreateTexture(nil, "ARTWORK")
	e.icon:SetSize(22, 22)
	e.icon:SetPoint("TOPLEFT", PAD, -12)
	e.title = V.Text(e, 13)
	e.title:SetPoint("LEFT", e.icon, "RIGHT", 6, 0)
	e.title:SetWidth(TW - 28 - 30)
	e.title:SetJustifyH("LEFT")
	if e.title.SetWordWrap then e.title:SetWordWrap(false) end
	e.close = V.Button(e, "x", 20, 20, function() e:Hide() end)
	e.close:SetPoint("TOPRIGHT", -10, -10)
	-- "Lowest now: ..." under the title, the full width
	e.low = V.Text(e, 12, W.GREY)
	e.low:SetPoint("TOPLEFT", PAD, -42)
	e.low:SetWidth(TW)
	e.low:SetJustifyH("LEFT")
	if e.low.SetWordWrap then e.low:SetWordWrap(false) end
	e.boxes = {}                     -- the six boxes, in Tab order
	local LABEL_W, X0 = 170, PAD + 176
	local function Row(label, y)
		local fs = V.Text(e, 12)
		fs:SetPoint("TOPLEFT", PAD, y - 4)
		fs:SetWidth(LABEL_W)
		fs:SetJustifyH("LEFT")
		if fs.SetWordWrap then fs:SetWordWrap(false) end
		fs:SetText(label)
		local row, x = { label = fs, icons = {} }, X0
		for i = 1, 3 do
			local box = V.EditBox(e, W.COIN_W[i])
			box:SetPoint("TOPLEFT", x, y)
			if box.SetNumeric then box:SetNumeric(true) end
			if box.SetMaxLetters then box:SetMaxLetters(W.COIN_MAX[i]) end
			if box.SetJustifyH then box:SetJustifyH("RIGHT") end
			box:SetScript("OnEnterPressed", function() W.Save() end)
			box:SetScript("OnEscapePressed", function() e:Hide() end)
			box:SetScript("OnTextChanged", function() e.err:SetText("") end)
			box:HookScript("OnEditFocusLost", function() RowNormalize(row) end)   -- (hooked: the Look's own focus art stays)
			box:SetScript("OnTabPressed", function(self)
				local k = self.tab
				local n = #e.boxes
				local back = IsShiftKeyDown and IsShiftKeyDown()
				local nextBox = e.boxes[back and ((k - 2) % n + 1) or (k % n + 1)]
				RowNormalize(row)
				nextBox:SetFocus()
				if nextBox.HighlightText then nextBox:HighlightText() end
			end)
			local icon = e:CreateTexture(nil, "ARTWORK")
			icon:SetSize(14, 14)
			icon:SetPoint("LEFT", box, "RIGHT", 3, 0)
			icon:SetTexture(W.COIN_ICONS[i])
			row[i], row.icons[i] = box, icon
			e.boxes[#e.boxes + 1] = box
			box.tab = #e.boxes
			x = x + W.COIN_W[i] + 3 + 14 + 10
		end
		row.right = x - 10           -- (where the copper icon ends)
		return row
	end
	e.buy = Row(L["Buy when lowest is <="], -66)
	e.sell = Row(L["Sell when lowest is >="], -96)
	e.houses = V.Radio(e, L["House:"], { { "Alliance", L["Alliance"] }, { "Horde", L["Horde"] }, { "Neutral", L["Neutral"] } },
		function() return e.house end, function(v) e.house = v e.Lowest() end)
	e.houses:SetPoint("TOPLEFT", PAD, -128)
	e.hint = V.Text(e, 11, W.GREY)
	e.hint:SetPoint("TOPLEFT", PAD, -156)
	e.hint:SetWidth(TW)
	e.hint:SetJustifyH("LEFT")
	if e.hint.SetWordWrap then e.hint:SetWordWrap(true) end
	e.hint:SetText(L["Leave all three boxes blank for no target; a blank box is 0. 150 silver becomes 1g 50s. The AH's lowest listed price is compared (before its cut)."])
	e.err = V.Text(e, 11, { 1, 0.35, 0.3 })
	e.err:SetPoint("TOPLEFT", PAD, -194)
	e.err:SetWidth(TW)
	e.err:SetJustifyH("LEFT")
	if e.err.SetWordWrap then e.err:SetWordWrap(false) end
	e.save = V.Button(e, L["Save"], 100, 22, function() W.Save() end)
	e.save:SetPoint("BOTTOMLEFT", PAD, 14)
	e.remove = V.Button(e, L["Remove from Watchlist"], 170, 22, function() if e.id then W.Remove(e.id) end e:Hide() end)
	e.remove:SetPoint("LEFT", e.save, "RIGHT", 8, 0)
	e.cancel = V.Button(e, L["Cancel"], 90, 22, function() e:Hide() end)
	e.cancel:SetPoint("BOTTOMRIGHT", -PAD, 14)
	function e.Lowest()
		local low, c
		if e.id then low, c = S().Lowest(e.house, e.id) end
		local what = low and L["%s (%s)"]:format(S().Money(low), S().Age(c and c.t)) or (c and L["none listed"]) or L["not in your scans yet"]
		e.low:SetText(L["Lowest now: %s, %s"]:format(what, L[e.house or W.DefaultHouse()] or tostring(e.house)))
	end
	if ns.Style and ns.Style.Popup then ns.Style.Popup(e) else T.SkinFlat(e, 0.98) end
	e:Hide()
	W.editor = e
	return e
end

-- open the editor on an item (it goes on the list when saved; Remove takes it off)
function W.Edit(id)
	id = tonumber(id)
	if not id then return nil end
	local e = W.Editor()
	local t = W.Get(id)
	e.id = id
	e.house = t and W.HouseOf(t) or W.DefaultHouse()
	e.icon:SetTexture(I.ItemIcon(id))
	local name, _, q = V.ItemData(id)
	e.title:SetText(name or I.ItemName(id))
	e.title:SetTextColor(V.QualityColor(q))
	RowFill(e.buy, t and t.buy)
	RowFill(e.sell, t and t.sell)
	e.err:SetText("")
	e.houses.Update()
	e.Lowest()
	e.remove:SetShown(t ~= nil)
	e:Show()
	if e.Raise then e:Raise() end
	e.buy[1]:SetFocus()
	return e
end

function W.Save()
	local e = W.editor
	if not (e and e.id) then return false end
	local buy, okB = RowRead(e.buy)
	local sell, okS = RowRead(e.sell)
	if not okB then e.err:SetText(L["Buy: whole numbers only in the gold, silver and copper boxes."]) return false end
	if not okS then e.err:SetText(L["Sell: whole numbers only in the gold, silver and copper boxes."]) return false end
	RowFill(e.buy, buy) RowFill(e.sell, sell)
	local t = W.Set(e.id, buy, sell, e.house)
	local Money = S().Money
	ns:Print("%s", L["Watchlist: %s (%s): buy <= %s, sell >= %s."]:format(I.ItemName(e.id), t.house,
		t.buy and Money(t.buy) or L["none"], t.sell and Money(t.sell) or L["none"]))
	e:Hide()
	return true
end

--------------------------------------------------------------------------------
-- AH Market > Watchlist
--------------------------------------------------------------------------------

local MONEY = "999g 99s 99c"
M.COLS.watch = {
	{ key = "name", label = L["Item"], x = 2, w = 200, justify = "LEFT", item = true, first = "asc", value = function(e) local n = V.ItemData(e.id) return n and n:lower() or nil end },
	{ key = "min", label = L["Lowest"], x = 0, w = 90, first = "asc", value = function(e) return e.low end },
	{ key = "buy", label = L["Buy <= target"], x = 0, w = 90, first = "asc", value = function(e) return e.t.buy end },
	{ key = "sell", label = L["Sell >= target"], x = 0, w = 90, first = "asc", value = function(e) return e.t.sell end },
	{ key = "signal", label = L["Signal"], x = 0, w = 100, first = "asc", value = function(e) return W.SignalRank(e) end },
	{ key = "last", label = L["Last met"], x = 0, w = 80, value = function(e) return e.t.lastMet end },
	{ key = "edit", label = L["Edit"], x = 0, w = 44, button = true, bw = 40 },
}
M.ROW_W.watch = 760
M.SAMPLE_LIST.watch = { min = MONEY, buy = MONEY, sell = MONEY, signal = "Near 10% (sell)", last = "59 min ago" }
M.SORT_DEFAULT.watch = "signal:asc"
M.SORT_SETTING.watch = "sortWatch"
M.NEEDS.watch = { name = true }
M.HEAD_TIPS.watch = {
	name = "The item. Click it for its price history; right-click for its menu.",
	min = "The AH's lowest listed buyout per unit at the target's house, from your last scan there (before the AH's cut).",
	buy = "Your buy target: BUY when the lowest is at or below it. Blank: none.",
	sell = "Your sell target: SELL when the lowest is at or above it (the listed price, not after the cut). Blank: none.",
	signal = "BUY or SELL when a target is met now; Near x% when the lowest is within the Near setting of one (Settings > Watchlist); - otherwise.",
	last = "When a scan last found a target met (the popup and chat said so).",
	edit = "Edit: change the item's targets or house, or remove it.",
}
M.TIPS.watchAdd = { L["Add an item"], L["Type a name and pick it (Enter: the first), or shift-click an item here. Its targets open."] }

local GREY, GOLD = W.GREY, T.GOLD

function W.BuildView(f, page)
	f.search = V.EditBox(f, 220)
	f.search:SetPoint("TOPLEFT", 8, -4)
	f.searchHint = V.Text(f, 10, GREY)
	f.searchHint:SetPoint("LEFT", f.search, "RIGHT", 8, 0)
	f.searchHint:SetText(L["add an item by name (or alt-click any item)"])
	-- the search's dropdown: the Shopping List's (V.ItemSearch: I.SearchItems, the names Valhalla has seen; 1.2.26:
	-- its steady rows and click-outside close too); Add, or Edit when it's on the Watchlist
	local Pick
	local box = V.ItemSearch(f, f.search, 30, function(id)
		return W.Has(id) and L["Edit"] or L["Add"], function() Pick(id) end
	end)
	local Close = box.Close
	function Pick(id)
		W.Add(id)
		f.search:SetText("")
		Close()
		if f.search.ClearFocus then f.search:ClearFocus() end
		W.Edit(id)
	end
	f.Pick = Pick
	f.SearchResults = box.Results
	f.search:SetScript("OnEnterPressed", function(self)
		-- (Enter before the search ran: it runs now; else the rows shown)
		local text = Trim(self:GetText())
		if text ~= "" and box.frozen.text ~= text then f.found = box.Compute(text) end
		local id = (f.found and f.found[1]) or I.ParseItem(self:GetText())
		if id then Pick(id)
		elseif text ~= "" then ns:Print("%s", L["No item by that name seen yet: shift-click it from your bags, drop it here, or type its item ID."]) end
	end)
	if ns.LinkBox then
		ns.LinkBox(f.search, function(_, link)
			if type(link) ~= "string" or not link:find("|Hitem:", 1, true) then return false end
			local id = I.ParseItem(link)
			if not id then return false end
			Pick(id)
			return true
		end)
	end
	-- the list
	f.head = M.Headers(f, -30, "watch", function() f.offset = 0 f.Refresh() end)
	f.sortButtons = f.head.buttons
	local item = M.COLS.watch[1]
	local editCol = M.ColOf(M.COLS.watch, "edit")
	local top = 30 + f.head.h + 6
	M.Paged(f, page, top, function(i)
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(M.ROW_W.watch, 24)
		r:SetPoint("TOPLEFT", M.LIST_X, -top - (i - 1) * M.ROW_H)
		r.cell = V.ItemCell(r, item.w)
		r.cell:SetPoint("LEFT", item.x, 0)
		r.cell.onClick = function(id) M.ShowHistory(page, id) end
		r.cells = M.Cells(r, "watch")
		for k, fs in pairs(r.cells) do r[k] = fs end   -- (r.min, r.buy, r.sell, r.signal, r.last)
		r.edit = V.Button(r, L["Edit"], editCol.bw, 18, function() if r.id then W.Edit(r.id) end end)
		r.edit:SetPoint("LEFT", r, "LEFT", editCol.x + math.floor((editCol.w - editCol.bw) / 2), 0)
		r:Hide()
		return r
	end)
	f.count = V.Text(f, 11, GREY)
	f.count:SetPoint("BOTTOMLEFT", 8, 6)
	f.count:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.count:SetJustifyH("LEFT")
	f.empty = V.Text(f, 12, GREY)
	f.empty:SetPoint("TOPLEFT", 8, -top - 8)
	f.empty:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	f.empty:SetJustifyH("LEFT")
	f.empty:SetText(L["Nothing on your Watchlist yet. Type an item's name above, alt-click any item, or right-click one > Set target..."])
	function f.Refresh(keep)
		local tag = M.SortTag("watch")
		f.list = W.Rows()
		M.SortList(f.list, "watch")
		if M.NeedsData("watch") and (not keep or f.sortTag ~= tag) then
			local ids = {}
			for _, e in ipairs(f.list) do ids[#ids + 1] = e.id end
			M.Fetch(f, ids, function() f.Refresh(true) end, -6)
		end
		f.sortTag = tag
		f.head.Update()
		f.Clamp()
		local list, shown = f.list, {}
		local shownHouse = M.House()
		local Money = S().Money
		local counts = { buy = 0, sell = 0, near = 0 }
		for _, e in ipairs(list) do if e.sig then counts[e.sig] = counts[e.sig] + 1 end end
		f.empty:SetShown(#list == 0)
		for i, r in ipairs(f.rows) do
			local e = i <= f.per and list[f.offset + i]
			if e then
				r.id = e.id
				r.cell.suffix = e.house ~= shownHouse and ("  |cffaaaaaa" .. L[e.house] .. "|r") or nil
				r.cell:SetItem(e.id, M.Lines)
				r.min:SetText(e.low and Money(e.low) or (e.c and L["none listed"]) or "-")
				r.buy:SetText(e.t.buy and Money(e.t.buy) or "-")
				r.sell:SetText(e.t.sell and Money(e.t.sell) or "-")
				r.signal:SetText(W.SignalText(e))
				local c = W.SignalColor(e)
				r.signal:SetTextColor(c[1], c[2], c[3])
				r.last:SetText(e.t.lastMet and S().Age(e.t.lastMet) or "-")
				shown[#shown + 1] = e.id
				r:Show()
			else
				r.id = nil
				r.cell.suffix = nil
				r.cell:SetItem(nil)
				r:Hide()
			end
		end
		local near = W.NearPct()
		f.count:SetText(#list == 0 and "" or L["%d watched: %d BUY, %d SELL, %d near (%s). Checked after every scan at the Auction House."]:format(
			#list, counts.buy, counts.sell, counts.near, near > 0 and L["within %d%%"]:format(near) or L["Near off"]))
		f.UpdatePager()
		return shown
	end
end

M.BUILD.watch = W.BuildView
M.TIP_ON.watch = function(f) M.Tip(f.search, "watchAdd") end
