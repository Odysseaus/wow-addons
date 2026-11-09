--------------------------------------------------------------------------------
-- The Auction House's shopping list (v0.3.0): beside the game's Auction House, what you still need from
-- it, each with a Search button. Search puts the item's name in the AH's own search box (as shift-clicking
-- an item does); press Enter to search. With "One-click Search" on (Investments > Settings) the AH's own
-- search runs too. Buying is always your own click on the game's own Buy button: Valhalla buys nothing.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local A = {}
I.AH = A

A.ROWS = 14
A.W = 270
local panel
local on = false
local closedThisVisit = false
local hinted = false

function A.Panel() return panel end

local function Build()
	local ah = _G.AuctionHouseFrame
	if panel or not ah then return panel end
	local T, V = I.Tabs, I.Views
	panel = CreateFrame("Frame", "ValhallaAHList", ah, "BackdropTemplate")
	panel:SetSize(A.W, 440)
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
	T.Skin(panel, 0.96)
	panel:EnableMouse(true)
	local title = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 13, T.GOLD)
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["Valhalla: Shopping List"])
	local close = V.Button(panel, "x", 20, 20, function() closedThisVisit = true panel:Hide() end)
	close:SetPoint("TOPRIGHT", -6, -6)
	panel.sub = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 10, { 0.6, 0.6, 0.6 })
	panel.sub:SetPoint("TOPLEFT", 12, -28)
	panel.sub:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.sub:SetJustifyH("LEFT")
	panel.rows = {}
	for i = 1, A.ROWS do
		local r = CreateFrame("Frame", nil, panel)
		r:SetHeight(24)
		r:SetPoint("TOPLEFT", 8, -56 - (i - 1) * 26)
		r:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 20)
		r.icon:SetPoint("LEFT", 2, 0)
		r.name = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12)
		r.name:SetPoint("LEFT", 26, 0)
		r.name:SetWidth(120)
		r.name:SetJustifyH("LEFT")
		r.need = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 12, T.GOLD)
		r.need:SetPoint("LEFT", 150, 0)
		r.search = V.Button(r, L["Search"], 64, 20)
		r.search:SetPoint("RIGHT", 0, 0)
		r:Hide()
		panel.rows[i] = r
	end
	panel.empty = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 12, { 0.6, 0.6, 0.6 })
	panel.empty:SetPoint("TOPLEFT", 14, -60)
	panel.empty:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.empty:SetJustifyH("LEFT")
	panel.empty:SetText(L["Nothing needed from the Auction House. (Investments > Smart Vendor: what you want.)"])
	panel:Hide()
	return panel
end

-- the item's name into the AH's search box (and, with One-click Search, the AH's own search)
function A.Search(id)
	local ah = _G.AuctionHouseFrame
	if not ah then return false end
	local name = I.ItemName(id)
	local ok, set = pcall(ah.SetSearchText, ah, name)
	if not (ok and set) then
		ns:Print(L["Open the Auction House's Browse tab, then press Search again."])
		return false
	end
	if I.S.ahOneClick and ah.SearchBar and ah.SearchBar.StartSearch then
		pcall(ah.SearchBar.StartSearch, ah.SearchBar)
	else
		local box = ah.SearchBar and ah.SearchBar.SearchBox
		if box and box.SetFocus then box:SetFocus() end
		if not hinted then hinted = true ns:Print(L["%s is in the Auction House's search box: press Enter to search."]:format(name)) end
	end
	return true
end

function A.Rows()
	local list = I.ShoppingList()
	return list.ah, list
end

function A.Refresh()
	if not panel then return end
	if not (on and I.ahOpen and I.S.ahPanel) or closedThisVisit then panel:Hide() return end
	local rows, list = A.Rows()
	panel.sub:SetText(L["Still needed: %d. Done %d / %d. Search, then buy with the AH's own button."]:format(#rows, list.done, list.total))
	panel.empty:SetShown(#rows == 0)
	for i, r in ipairs(panel.rows) do
		local d = rows[i]
		if d then
			r.icon:SetTexture(I.ItemIcon(d.id))
			r.name:SetText(d.name)
			r.need:SetText("x" .. d.need)
			r.search:SetScript("OnClick", function() A.Search(d.id) end)
			r.id = d.id
			r:Show()
		else
			r.id = nil
			r:Hide()
		end
	end
	panel:Show()
end

function A.Show()
	closedThisVisit = false
	if not on then return end
	Build()
	A.Refresh()
end

function A.Hide()
	if panel then panel:Hide() end
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
