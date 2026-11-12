local _, ns = ...
local L = ns.L

--------------------------------------------------------------------------------
-- Item tooltips (1.2.0): two lines under every item tooltip (the game's GameTooltip and ItemRefTooltip, through
-- TooltipDataProcessor's post-call for items): the AH's lowest price from your last scan of the house shown in
-- AH Market, and, holding 2 or more (bags + bank), what they're worth at it. No line with no scan data, nothing
-- listed, or a soulbound item. Setting: "AH price on item tooltips" (ahTooltip, on by default).
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

-- the lines for an item: { text, ... } (empty: none to add)
function P.Lines(id, data)
	if not (id and On()) then return {} end
	if Soulbound(id, data) then return {} end
	local house = I.Market.House()
	local low, c = S().Lowest(house, id)
	if not (low and c) then return {} end
	local out = { L["AH lowest: %s each (%s)"]:format(S().Money(low), S().Age(c.t)) }
	local n, bags, bank = P.Held(id)
	if n >= 2 then
		local total = S().Money(low * n)
		if bank then out[2] = L["You have %d (bags %d, bank %d): %s"]:format(n, bags, bank, total)
		else out[2] = L["You have %d: %s"]:format(n, total) end
	end
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
	local ok, lines = pcall(P.Lines, id, data)
	if not ok or #lines == 0 then return end
	for _, t in ipairs(lines) do tip:AddLine(t, P.R, P.G, P.B) end
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
