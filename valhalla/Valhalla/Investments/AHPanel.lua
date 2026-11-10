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
-- Buying is always your own click on the game's own Buy button: Valhalla buys nothing.
-- v0.3.5: the AH check's button is here (it needs the Auction House open, and the Valhalla window and the
-- AH can't be open together: the game shows one or the other). Run AH check / Stop, its step and a bar;
-- minimized, the small button's right-click runs or stops it.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local A = {}
I.AH = A

A.ROWS = 14
A.W = 270
A.H = 530
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
	b:SetSize(64, 20)
	T.Skin(b, 0.9)
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

local function Build()
	local ah = _G.AuctionHouseFrame
	if panel or not ah then return panel end
	if InCombatLockdown() then A.waiting = true return nil end   -- (secure buttons aren't made in combat: once it ends)
	local T, V = I.Tabs, I.Views
	panel = CreateFrame("Frame", "ValhallaAHList", ah, "BackdropTemplate")
	panel:SetSize(A.W, A.H)
	panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
	T.Skin(panel, 0.96)
	panel:EnableMouse(true)
	local title = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 13, T.GOLD)
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L["Valhalla: Shopping List"])
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
		r.name:SetWidth(120)
		r.name:SetJustifyH("LEFT")
		r.need = T.Font(r:CreateFontString(nil, "OVERLAY", "GameFontNormal"), 12, T.GOLD)
		r.need:SetPoint("LEFT", 150, 0)
		r.search = SearchButton(r, T, V)
		r.search:SetPoint("RIGHT", 0, 0)
		r:Hide()
		panel.rows[i] = r
	end
	panel.mail = T.Font(panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11, T.GOLD)
	panel.mail:SetPoint("BOTTOMLEFT", 12, 10)
	panel.mail:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
	panel.mail:SetJustifyH("LEFT")
	-- the AH check (v0.3.5): its button, what it's doing and a bar
	local check = CreateFrame("Frame", nil, panel)
	check:SetPoint("BOTTOMLEFT", 8, 26)
	check:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	check:SetHeight(34)
	check.button = V.Button(check, L["Run AH check"], 110, 22, function() A.CheckClick() end)
	check.button:SetPoint("TOPLEFT", 2, 0)
	check.button:HookScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Run AH check"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Measures how fast the Auction House answers (full scan and quick searches), for the coming AH Market. 1-4 minutes, without freezing the game. It only reads prices: nothing is posted, bid or bought. Keep the Auction House open, then /reload."], 1, 1, 1, true)
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
		GameTooltip:AddLine(A.CheckRunning() and L["Right-click: stop the AH check."] or L["Right-click: run the AH check."], 1, 1, 1)
		GameTooltip:AddLine(A.CheckStatus(), 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	mini:Hide()
	return panel
end

-- the AH check from here (v0.3.5)
function A.CheckRunning() return I.AHCheck and I.AHCheck.Running() or false end

function A.CheckClick()
	if A.CheckRunning() then I.AHCheck.Stop("stopped") else I.RunDiag("ah") end
	A.CheckRefresh()
end

function A.CheckStatus()
	local AC = I.AHCheck
	if AC and AC.Running() then
		local f, n, label, at, count = AC.Progress()
		local s = L["Step %d/7: %s (%d%%)"]:format(n, label ~= "" and label or "...", math.floor(f * 100))
		if at and count then s = s .. " " .. L["%d / %d auctions read"]:format(at, count) end
		return s, f
	end
	local d = I.LastDiag()
	local ac = d and d.ahcheck
	if ac then return L["Last AH check: %s (%s). /reload saves it."]:format(tostring(ac.state), tostring(d.when)), nil end
	return L["Not run yet. Read-only: nothing is posted, bid or bought."], nil
end

local ticker = 0
function A.CheckRefresh()
	local running = A.CheckRunning()
	local text, f = A.CheckStatus()
	if panel and panel.check then
		local c = panel.check
		c.button.text:SetText(running and L["Stop"] or L["Run AH check"])
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
	for i, r in ipairs(panel.rows) do
		local d = rows[i]
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
	A.waiting = nil
	Build()
	-- (the AH's Search button can be made after its frame: the targets set again on each visit)
	if panel then for _, r in ipairs(panel.rows) do if not r.search.armed then A.Arm(r.search) end end end
	A.Refresh()
end

function A.Hide()
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
