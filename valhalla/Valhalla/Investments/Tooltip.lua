local _, ns = ...
local L = ns.L

--------------------------------------------------------------------------------
-- Item tooltips (1.2.0; 1.2.5 three priced lines, the game's coins): under every item tooltip (the game's GameTooltip
-- and ItemRefTooltip, through TooltipDataProcessor's post-call for items), label left, coins right, in this order:
--   Vendor         what a vendor pays (GetItemInfo's sellPrice): none at 0 (vendors won't buy it), none while the
--                  item isn't loaded, none when the tooltip already has the game's own "Sell Price" line (type 11)
--   AH (2 h ago)   the AH's lowest price from your last scan of the house shown in AH Market, and how old it is
--   AH total (N)   N x that price; N per the setting "AH total on item tooltips" (ahTotal):
--                    "stack" (default): the stack in the bag or bank slot you're hovering; no slot (a link, a
--                                       merchant, ...): no line
--                    "full": one full stack (GetItemInfo's max stack size), "AH total (stack of N)"
--                    "held": all you hold (bags + bank per "Count bank items"), "AH total (N held)"
--                  only for N of 2 or more
-- Nothing with no scan data, nothing listed, or a soulbound item. Setting: "AH price on item tooltips" (ahTooltip,
-- on by default). Coins: the game's own tooltip money format (MoneyFormatterUtil.FormatMoney with
-- GameTooltipMoneyFormat, as its Sell Price line), else GetCoinTextureString, GetMoneyString, else coin textures;
-- zero coins left out.
--------------------------------------------------------------------------------

local I = ns.Invest
local P = {}
I.Tooltip = P

local function S() return I.Scan end
local function On()
	local mod = ns:GetModule("invest")
	return mod and mod.enabled ~= false and I.S and I.S.ahTooltip ~= false and I.char ~= nil and S() ~= nil and I.Market ~= nil or false
end
P.On = On

local function Soulbound(id, data)
	local bound = _G.ITEM_SOULBOUND
	for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		local t = line.leftText
		if bound and t == bound then return true end
	end
	local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, bind = pcall(GetItemInfo, id)
	return ok and (bind == 1 or bind == 4) or false   -- (bind on pickup, quest item: never on the AH)
end
P.Soulbound = Soulbound

-- how many you hold: total, bags, bank (nil: the bank never seen, or not counted)
function P.Held(id)
	local c = I.char
	local bags = c.bags[id] or 0
	local bank
	if I.S.countBank ~= false and (c.bankSeen or (I.db.account and I.db.account.bankSeen)) then
		bank = (c.bank[id] or 0) + (((I.db.account or {}).bank or {})[id] or 0)
	end
	return bags + (bank or 0), bags, bank
end

-- copper as the game shows money: 1 [gold] 28 [silver] 98 [copper] (zero coins left out)
P.ICONS = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
function P.Coins(c)
	c = math.floor((c or 0) + 0.5)
	local function Try(fn, ...)
		if type(fn) ~= "function" then return nil end
		local ok, out = pcall(fn, ...)
		if ok and type(out) == "string" and out:find("%S") then return out end
	end
	local MF = rawget(_G, "MoneyFormatterUtil")
	local out = MF and rawget(_G, "GameTooltipMoneyFormat") and Try(MF.FormatMoney, c, rawget(_G, "GameTooltipMoneyFormat"))
		or Try(rawget(_G, "GetCoinTextureString"), c)
		or Try(rawget(_G, "GetMoneyString"), c)
	if out then return out end
	local parts = {}
	for i, n in ipairs({ math.floor(c / 10000), math.floor(c / 100) % 100, c % 100 }) do
		if n > 0 then parts[#parts + 1] = ("%d|T%s:0:0:2:0|t"):format(n, P.ICONS[i]) end
	end
	if #parts == 0 then parts[1] = ("0|T%s:0:0:2:0|t"):format(P.ICONS[3]) end
	return table.concat(parts, " ")
end

P.SELL_PRICE_LINE = 11   -- (Enum.TooltipDataLineType.SellPrice)
-- the game's own "Sell Price" line already in the tooltip's data
function P.GameSellLine(data)
	local kind = (Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice) or P.SELL_PRICE_LINE
	for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		if type(line) == "table" and line.type == kind then return true end
	end
	return false
end

-- the item's max stack size and vendor price (nil: not loaded)
function P.Info(id)
	local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	local ok, name, _, _, _, _, _, _, maxStack, _, _, sell = pcall(GetItemInfo, id)
	if not (ok and name) then return nil, nil end
	return tonumber(maxStack), tonumber(sell)
end

-- the stack in the bag or bank slot the tooltip is for (nil: not a slot, or not this item)
function P.Hovered(tip, id)
	local owner = tip and tip.GetOwner and tip:GetOwner()
	if type(owner) ~= "table" then return nil end
	local ok, bag, slot = pcall(function()
		if owner.GetBankTabID and owner.GetContainerSlotID then return owner:GetBankTabID(), owner:GetContainerSlotID() end
		if owner.GetSlotAndBagID then local sl, b = owner:GetSlotAndBagID() return b, sl end
	end)
	if not (ok and bag and slot) or not (C_Container and C_Container.GetContainerItemInfo) then return nil end
	local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
	if ok2 and type(info) == "table" and info.itemID == id then return info.stackCount end
end

P.TOTALS = { stack = true, full = true, held = true }
-- the lines for an item: { { label, coins }, ... } (empty: none to add); tip: the tooltip (its slot, for "stack")
function P.Lines(id, data, tip)
	if not (id and On()) then return {} end
	if Soulbound(id, data) then return {} end
	local house = I.Market.House()
	local low, c = S().Lowest(house, id)
	if not (low and c) then return {} end
	local out = {}
	local maxStack, sell = P.Info(id)
	if sell and sell > 0 and not P.GameSellLine(data) then out[#out + 1] = { L["Vendor"], P.Coins(sell) } end
	out[#out + 1] = { L["AH (%s)"]:format(S().Age(c.t)), P.Coins(low) }
	local mode = P.TOTALS[I.S.ahTotal] and I.S.ahTotal or "stack"
	local n, label
	if mode == "stack" then
		n = P.Hovered(tip, id)
		label = n and L["AH total (%d)"]:format(n)
	elseif mode == "full" then
		n = maxStack
		label = n and L["AH total (stack of %d)"]:format(n)
	else
		n = P.Held(id)
		label = L["AH total (%d held)"]:format(n)
	end
	if n and n >= 2 then out[#out + 1] = { label, P.Coins(low * n) } end
	return out
end

P.R, P.G, P.B = 0.95, 0.82, 0.45
function P.OnItem(tip, data)
	if not tip or (tip.IsForbidden and tip:IsForbidden()) then return end
	if tip ~= _G.GameTooltip and tip ~= _G.ItemRefTooltip then return end
	local id = type(data) == "table" and data.id
	if not id and tip.GetItem then
		local _, link = tip:GetItem()
		id = link and tonumber(link:match("item:(%d+)"))
	end
	local ok, lines = pcall(P.Lines, id, data, tip)
	if not ok or #lines == 0 then return end
	for _, l in ipairs(lines) do
		if tip.AddDoubleLine then tip:AddDoubleLine(l[1], l[2], P.R, P.G, P.B, 1, 1, 1)
		else tip:AddLine(l[1] .. "  " .. l[2], P.R, P.G, P.B) end
	end
	P.added = (P.added or 0) + #lines
end

-- once (a post-call can't be taken back: P.On says when to add nothing)
function P.Hook()
	if P.hooked then return P.hooked end
	local TDP = rawget(_G, "TooltipDataProcessor")
	local kind = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
	if TDP and TDP.AddTooltipPostCall and kind then
		TDP.AddTooltipPostCall(kind, P.OnItem)
		P.hooked = "processor"
	else
		for _, tip in ipairs({ _G.GameTooltip, _G.ItemRefTooltip }) do
			if tip and tip.HookScript then tip:HookScript("OnTooltipSetItem", function(t) P.OnItem(t) end) end
		end
		P.hooked = "script"
	end
	return P.hooked
end
