--------------------------------------------------------------------------------
-- The merchant's highlights (v0.3.0): on the game's merchant window, what's on your Shopping List gets a
-- gold glow and a "need N" tag; the rest is washed grey (still yours to buy: the wash is Valhalla's own
-- layer, which takes no clicks). Nothing on the game's buttons is changed or written on, and nothing
-- is bought for you: painted after the game lays a page out (a secure hook on
-- MerchantFrame_UpdateMerchantInfo); hidden on the buyback tab and when the merchant closes.
-- v0.3.2: only the active shopping list glows; a small "List: <name>" picker above the merchant window's
-- top right chooses which (Valhalla's own button: a menu of your lists; none yet: build one).
-- v0.3.3: what's on the active list keeps its glow once you have enough ("Done"); "None": no highlights.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("invest")
local I = mod.I
local M = {}
I.Merchant = M

M.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local overlays = {}
local hooked = false
local on = false

local function PerPage() return _G.MERCHANT_ITEMS_PER_PAGE or 10 end
function M.Overlays() return overlays end

local function Overlay(i)
	if overlays[i] then return overlays[i] end
	local slot = _G["MerchantItem" .. i]
	if not slot then return nil end
	local icon = _G["MerchantItem" .. i .. "ItemButton"] or slot
	local o = CreateFrame("Frame", nil, slot)       -- (takes no mouse: the game's buttons get every click)
	o:SetAllPoints(slot)
	o:SetFrameLevel((slot:GetFrameLevel() or 1) + 10)
	o.wash = o:CreateTexture(nil, "OVERLAY")
	o.wash:SetPoint("TOPLEFT", slot, "TOPLEFT", -2, 2)
	o.wash:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 2, -2)
	o.wash:SetColorTexture(0.05, 0.05, 0.05, 0.6)
	o.glow = o:CreateTexture(nil, "OVERLAY")
	o.glow:SetTexture(M.GLOW)
	o.glow:SetBlendMode("ADD")
	o.glow:SetVertexColor(1, 0.8, 0.2, 1)
	o.glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -14, 14)
	o.glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 14, -14)
	o.tag = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if ns.Look and ns.Look.Font then ns.Look:Font(o.tag, 10, "OUTLINE") end
	o.tag:SetTextColor(1, 0.82, 0)
	o.tag:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 3)
	o:Hide()
	overlays[i] = o
	return o
end

local picker
function M.Picker() return picker end

-- the list picker, above the merchant window's top right (made the first time it's needed)
function M.ShowPicker()
	local frame = _G.MerchantFrame
	if not (on and I.S.hiVendor and frame and I.Views and I.Views.Picker) then if picker then picker:Hide() end return end
	if not picker then
		picker = I.Views.Picker(frame, 200)
		picker:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
	end
	picker.Update()
	picker:Show()
end

function M.HideAll()
	for _, o in pairs(overlays) do o:Hide() end
	if picker then picker.menu:Hide() picker:Hide() end
end

-- what each slot on this page shows: "need" (glow, tag), "grey" (the wash) or nil (as the game drew it)
function M.Plan()
	local frame = _G.MerchantFrame
	if not (on and I.S.hiVendor and frame and frame:IsShown() and frame.selectedTab == 1) then return nil end
	local n = I.Call(GetMerchantNumItems) or 0
	local active = I.ActiveList()
	local needs, any = {}, false
	for idx = 1, n do
		local id = I.Call(GetMerchantItemID, idx)
		if id and active and I.LineOf(active, id) then needs[idx] = I.NeedOf(id) any = true end
	end
	local page = tonumber(frame.page) or 1
	local plan = {}
	for i = 1, PerPage() do
		local idx = (page - 1) * PerPage() + i
		if idx <= n then
			if needs[idx] then plan[i] = { state = "need", need = needs[idx], index = idx }
			elseif any then plan[i] = { state = "grey", index = idx } end
		end
	end
	return plan
end

function M.Paint()
	local plan = M.Plan()
	if not plan then M.HideAll() return end
	M.ShowPicker()
	for i = 1, PerPage() do
		local p = plan[i]
		local o = p and Overlay(i) or overlays[i]
		if o then
			if not p then
				o:Hide()
			else
				local need = p.state == "need"
				o.glow:SetShown(need)
				o.tag:SetShown(need and I.S.showNeed)
				local done = need and p.need <= 0
				o.tag:SetText(need and (done and ns.L["Done"] or ns.L["need %d"]:format(p.need)) or "")
				if done then o.tag:SetTextColor(0.3, 0.9, 0.3) else o.tag:SetTextColor(1, 0.82, 0) end
				o.wash:SetShown(not need)
				o.wash:SetColorTexture(0.05, 0.05, 0.05, I.S.greyAlpha)
				o:Show()
			end
		end
	end
end

function M.Enable()
	on = true
	if not hooked then
		if _G.MerchantFrame_UpdateMerchantInfo then
			hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function() if on then M.Paint() end end)
			hooked = true
		end
		if _G.MerchantFrame_UpdateBuybackInfo then hooksecurefunc("MerchantFrame_UpdateBuybackInfo", M.HideAll) end
	end
	if not M.listening then
		M.listening = true
		I.OnChanged(function() if on and I.merchantOpen then M.Paint() end end)
	end
	if I.merchantOpen then M.Paint() end
end

function M.Disable()
	on = false
	M.HideAll()
end
function M.Hooked() return hooked end
