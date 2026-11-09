--------------------------------------------------------------------------------
-- The Valhalla window's tabs (v0.3.0): Map & Quest Log, Investments, Talents, Professions.
--
-- The window is the game's world map (WorldMapFrame, Map/Window.lua), so nothing of it is hidden, moved or
-- written on: the other tabs are Valhalla's own frame (the "view host") laid over the map and the quest
-- log, from under the title strip to the bottom edge, in the same dark rock and bronze. Back on Map &
-- Quest Log the host is simply hidden: the map and the quest log ran underneath all along.
-- Tabs: below the window (bottom, the default), along the top of its content, or icons down its right
-- side (Investments > Settings). Full-screen map: no tabs (the map's own layout), back to the map.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local T = {}
I.Tabs = T

T.LIST = {
	{ key = "map", label = L["Map & Quest Log"], icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ key = "invest", label = L["Investments"], icon = "Interface\\Icons\\INV_Misc_Coin_01" },
	{ key = "talents", label = L["Talents"], icon = "Interface\\Icons\\Ability_Marksmanship", soon = true },
	{ key = "professions", label = L["Professions"], icon = "Interface\\Icons\\Trade_BlackSmithing", soon = true },
}
T.TAB_W, T.TAB_H, T.GAP, T.EDGE = 132, 28, 4, 30      -- (bottom/top: clear of the corners' resize grips)
T.SIDE = 40                                          -- side icons
T.LEVEL = 9920                                       -- over the map, the quest log and Valhalla's map overlays (HIGH strata), under the grips (9990)
T.BRONZE = { 0.66, 0.49, 0.28 }
T.GOLD = { 1, 0.82, 0 }

local map, strip, host
local buttons = {}
local views = {}
local current = "map"
local attached = false
local hooked = false

local function Maximized() return map and map.IsMaximized and map:IsMaximized() or false end
function T.Current() return current end
function T.Host() return host end
function T.Strip() return strip end
function T.Buttons() return buttons end
function T.Views() return views end

-- a dark panel with a bronze edge (our own frames only)
function T.Skin(f, alpha, edge)
	if not f.SetBackdrop then return f end
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	f:SetBackdropColor(0.07, 0.06, 0.05, alpha or 0.95)
	local e = edge or T.BRONZE
	f:SetBackdropBorderColor(e[1], e[2], e[3], 1)
	return f
end

function T.Font(fs, size, color)
	if ns.Look and ns.Look.Font then ns.Look:Font(fs, size) end
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
	return fs
end

-- the host's background: the map window's own dark rock (Core.lua's Look:Window), darkened
local function Rock(f)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	if bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT") == false then
		bg:SetColorTexture(0.1, 0.09, 0.08, 1)
	end
	if bg.SetHorizTile then bg:SetHorizTile(true) bg:SetVertTile(true) end
	local shade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.45)
end

--------------------------------------------------------------------------------
-- The view host and the placeholders
--------------------------------------------------------------------------------

local function Placeholder(parent, entry)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints()
	local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
	card:SetSize(360, 170)
	card:SetPoint("CENTER")
	T.Skin(card, 0.9)
	local icon = card:CreateTexture(nil, "ARTWORK")
	icon:SetSize(48, 48)
	icon:SetPoint("TOP", 0, -18)
	icon:SetTexture(entry.icon)
	local title = T.Font(card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), 18, T.GOLD)
	title:SetPoint("TOP", icon, "BOTTOM", 0, -10)
	title:SetText(entry.label)
	local text = T.Font(card:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), 13)
	text:SetPoint("TOP", title, "BOTTOM", 0, -8)
	text:SetText(L["Under construction: coming soon"])
	f.title, f.text = title, text
	return f
end

local function BuildHost()
	host = CreateFrame("Frame", "ValhallaViews", map)
	host:SetFrameStrata("HIGH")
	host:SetFrameLevel(T.LEVEL)
	host:EnableMouse(true)            -- (clicks and the wheel stay here, not on the map under it)
	host:EnableMouseWheel(true)
	host:SetScript("OnMouseWheel", function() end)
	Rock(host)
	host:Hide()
	T.PlaceHost()
end

function T.PlaceHost()
	if not host then return end
	host:ClearAllPoints()
	local top = map.ScrollContainer or map
	host:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
	host:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -2, 2)
end

local function View(key)
	if views[key] then return views[key] end
	local entry
	for _, e in ipairs(T.LIST) do if e.key == key then entry = e end end
	if not entry or key == "map" then return nil end
	local inner = CreateFrame("Frame", nil, host)
	inner:SetPoint("TOPLEFT", 0, (I.S.tabPos == "top") and -(T.TAB_H + 6) or 0)
	inner:SetPoint("BOTTOMRIGHT")
	if key == "invest" and I.Views then
		inner.page = I.Views.BuildInvest(inner)
	else
		inner.page = Placeholder(inner, entry)
	end
	inner:Hide()
	views[key] = inner
	return inner
end

--------------------------------------------------------------------------------
-- The tab buttons
--------------------------------------------------------------------------------

local function Paint(b)
	local on = b.key == current
	local e = on and T.GOLD or T.BRONZE
	T.Skin(b, on and 0.98 or 0.85, e)
	if b.label then
		if on then b.label:SetTextColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
		elseif b.soon then b.label:SetTextColor(0.55, 0.52, 0.48)
		else b.label:SetTextColor(0.85, 0.8, 0.7) end
	end
	if b.icon and b.icon.SetDesaturated then b.icon:SetDesaturated(b.soon and not on) end   -- (our own texture)
end

local function MakeButton(entry)
	local b = CreateFrame("Button", nil, strip, "BackdropTemplate")
	b.key, b.soon = entry.key, entry.soon
	b.label = T.Font(b:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 12)
	b.label:SetText(entry.label)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(entry.icon)
	if entry.soon then
		b.tag = T.Font(b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 9, { 0.6, 0.6, 0.6 })
		b.tag:SetText(L["soon"])
	end
	b:SetScript("OnClick", function(self) T.Select(self.key) end)
	b:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(entry.label, 1, 0.82, 0)
		if entry.soon then GameTooltip:AddLine(L["Under construction: coming soon"], 1, 1, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	return b
end

-- where the tabs go: bottom (hanging below the window), top (a row at the top of the content), side
-- (icons down the right edge, outside)
function T.Layout()
	if not strip then return end
	local pos = I.S.tabPos
	local n = #buttons
	local width = (map.GetWidth and map:GetWidth()) or 800
	for i, b in ipairs(buttons) do
		b:ClearAllPoints()
		b.label:ClearAllPoints()
		b.icon:ClearAllPoints()
		if b.tag then b.tag:ClearAllPoints() end
		if pos == "side" then
			b:SetSize(T.SIDE, T.SIDE)
			b:SetPoint("TOPLEFT", map, "TOPRIGHT", 0, -70 - (i - 1) * (T.SIDE + T.GAP))
			b.icon:SetSize(T.SIDE - 10, T.SIDE - 10)
			b.icon:SetPoint("CENTER")
			b.icon:Show()
			b.label:Hide()
			if b.tag then b.tag:SetPoint("BOTTOM", b, "BOTTOM", 0, 1) end
		else
			local w = math.max(80, math.min(T.TAB_W, math.floor((width - 2 * T.EDGE - (n - 1) * T.GAP) / n)))
			b:SetSize(w, T.TAB_H)
			local x = T.EDGE + (i - 1) * (w + T.GAP)
			if pos == "top" then
				b:SetPoint("TOPLEFT", host, "TOPLEFT", x, -3)
			else
				b:SetPoint("TOPLEFT", map, "BOTTOMLEFT", x, 1)
			end
			b.icon:Hide()
			b.label:Show()
			b.label:SetPoint("CENTER", 0, b.tag and 4 or 0)
			if b.tag then b.tag:SetPoint("BOTTOM", b, "BOTTOM", 0, 2) end
		end
		Paint(b)
	end
	-- the views' tops follow the top row
	for _, v in pairs(views) do
		v:ClearAllPoints()
		v:SetPoint("TOPLEFT", 0, pos == "top" and -(T.TAB_H + 6) or 0)
		v:SetPoint("BOTTOMRIGHT")
	end
end

local function BuildStrip()
	strip = CreateFrame("Frame", nil, map)
	strip:SetFrameStrata("HIGH")
	strip:SetFrameLevel(T.LEVEL + 40)
	strip:SetAllPoints(map)
	for _, entry in ipairs(T.LIST) do buttons[#buttons + 1] = MakeButton(entry) end
end

--------------------------------------------------------------------------------
-- Switching
--------------------------------------------------------------------------------

function T.Select(key, page)
	if not attached then return false end
	if Maximized() then key = "map" end
	current = key
	I.S.tab = key
	if key == "map" then
		host:Hide()
	else
		local v = View(key)
		for k, other in pairs(views) do if k ~= key then other:Hide() end end
		host:Show()
		if v then v:Show() end
		if key == "invest" and v and v.page and v.page.ShowPage then v.page:ShowPage(page) end
	end
	for _, b in ipairs(buttons) do Paint(b) end
	return true
end

-- shown with the map (not full screen), hidden with it
function T.Refresh()
	if not attached then return end
	if Maximized() then
		strip:Hide()
		if current ~= "map" then T.Select("map") end
		host:Hide()
		return
	end
	strip:Show()
	T.Layout()
	if current ~= "map" then T.Select(current) end
end

-- /valhalla tab, /valhalla invest: the map opened first if it's closed (never in combat: the menu's rule)
function T.Open(key, page)
	if not attached then
		ns:Print(L["The tabs need Valhalla's map (it's off, or waiting for the Gamepad UI to be off)."])
		return false
	end
	if map:IsShown() then return T.Select(key, page) end
	if InCombatLockdown() then ns:Print(L["The map can't be opened in combat."]) return false end
	if ToggleWorldMap then ToggleWorldMap() end
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function() if map:IsShown() then T.Select(key, page) end end)
	end
	return true
end

local function Attach()
	if attached or not mod.enabled then return end
	local wm = ns:GetModule("worldmap")
	if wm and not wm.enabled then return end
	map = _G.WorldMapFrame
	if not map then return end
	if not host then BuildHost() BuildStrip() end
	attached = true
	if not hooked then
		hooked = true
		map:HookScript("OnShow", function()
			if not attached then return end
			if not I.S.rememberTab then current = "map" end
			T.Refresh()
		end)
		if map.HookScript then map:HookScript("OnSizeChanged", function() if attached then T.Layout() end end) end
		for _, method in ipairs({ "Maximize", "Minimize" }) do
			if map[method] then hooksecurefunc(map, method, function() if attached then T.Refresh() end end) end
		end
	end
	current = I.S.rememberTab and I.S.tab or "map"
	T.Refresh()
end
T.Attach = Attach

function T.Enable()
	if _G.WorldMapFrame then
		if C_Timer and C_Timer.After then C_Timer.After(0, Attach) else Attach() end
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function() C_Timer.After(0, Attach) end)
	end
end

function T.Disable()
	if not attached then return end
	current = "map"
	host:Hide()
	strip:Hide()
	attached = false
end

function T.Attached() return attached end

-- the map's menu: Investments (Map/Panel.lua)
function ns.InvestAction(Icon)
	return { L["Investments"], id = "invest", icon = Icon and Icon("INV_Misc_Coin_01") or { texture = "Interface\\Icons\\INV_Misc_Coin_01" },
		tip = L["Smart Vendor, your Shopping List and (soon) the Auction House market: the Investments tab."],
		run = function()
			if not mod.enabled then ns:Print(L["Investments is off. /valhalla invest on"]) return end
			T.Open("invest")
		end, lit = function() return attached and current == "invest" end }
end
