--------------------------------------------------------------------------------
-- Chain quest view (1.1.0): in the game's quest log (the log beside Valhalla's map is the game's own
-- QuestMapFrame), a setting "Chain quest view" (the log's gear menu and Valhalla's menu, off at first):
--   * on: the game's Track tick on the right of every quest row is hidden (tracking stays: by zone, the
--     pins, Shift-click and right-click > Track, all the game's or Objectives'), and quests in a known chain
--     get a chain button in its place;
--   * the chain button opens a window to the right of the map: the chain's quests in order, first at the
--     top. Done ones are grey; the quest clicked is highlighted ("In your log" on any that are in the log);
--     an 'or' quest (one of two at that step) is indented under its step, an optional one dimmed; where
--     two Wowhead series were joined end to end, a thin line between them. Profession / Norse (Look) live.
-- The chains: Data/Forever/QuestChains.lua (ns.QuestChainData), from Wowhead WoW Forever's "Series" boxes,
-- built on the box (tools/questchains). A quest with no chain there gets no button (never a guess).
-- How (Blizzard_UIPanels_Game QuestMapFrame.lua, forever 1.60.1): a secure hook after QuestLogQuests_Update;
-- each active row of QuestScrollFrame.titleFramePool: row.Checkbox shown or hidden (the game never shows it
-- itself), our button (a child of the row, kept in our own table) put on it. No fields written on the game's
-- frames, no Blizzard function called, nothing protected (fine in combat).
-- /valhalla chain coverage: the log's quests with and without chain data.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local mod = ns:NewModule("chains", { defaults = {
	chainView = false,          -- Chain quest view (the quest log's gear menu, Valhalla's menu)
} })

local QC = {}
mod.QC = QC
ns.QuestChains = QC

QC.BUTTON = 18
QC.ROW_H = 20
QC.INDENT = 18
QC.WIDTH = 340
QC.TEXTURE = (ns.Media and ns.Media.path or "Interface\\AddOns\\Valhalla\\Media\\") .. "Textures\\ValhallaChain"
QC.GREY = { 0.5, 0.5, 0.5 }
QC.IN_LOG = { 0.25, 1, 0.25 }
QC.URL = "https://www.wowhead.com/forever/quest=%d"

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
	return nil
end

--------------------------------------------------------------------------------
-- The data: ns.QuestChainData = { meta = {...}, chains = { chain, ... } }
--   chain = { step, step, ..., side = "A"|"H"?, class = "DRUID"|{...}?, breaks = { i, ... } (a line after step i),
--             src = { "id@fetched", ... } }
--   step  = { questID, "Name", opt = true?, side?, class? (its own, else the chain's), alt = { step, ... }? }
-- QC.Build keeps what's for this character (faction, class) and indexes every quest it shows.
--------------------------------------------------------------------------------

-- for this character: a step's own side / class, else its chain's
local function For(s, c, side, class)
	local sd, cl = s.side or c.side, s.class or c.class
	if sd and side and sd ~= side then return false end
	if cl and class then
		if type(cl) == "string" then return cl == class end
		for _, x in ipairs(cl) do if x == class then return true end end
		return false
	end
	return true
end

-- one step for this character: the step itself, else its first alternative that is (then the rest of them)
local function KeepStep(s, c, side, class)
	local alts = {}
	for _, a in ipairs(s.alt or {}) do
		if type(a) == "table" and type(a[1]) == "number" and For(a, c, side, class) then alts[#alts + 1] = { id = a[1], name = a[2] or "", opt = a.opt and true or nil } end
	end
	local main
	if type(s[1]) == "number" and For(s, c, side, class) then main = { id = s[1], name = s[2] or "", opt = s.opt and true or nil }
	elseif #alts > 0 then main = table.remove(alts, 1) end
	if not main then return nil end
	main.alt = #alts > 0 and alts or nil
	return main
end

function QC.Build(data, side, class)
	local byQuest, chains = {}, {}
	if type(data) ~= "table" or type(data.chains) ~= "table" then QC.byQuest, QC.chains = byQuest, chains return 0 end
	if side == "Alliance" then side = "A" elseif side == "Horde" then side = "H" end
	for _, c in ipairs(data.chains) do
		if type(c) == "table" then
			local steps, breaks, map = {}, {}, {}
			for i, s in ipairs(c) do
				local k = type(s) == "table" and KeepStep(s, c, side, class)
				if k then steps[#steps + 1] = k end
				map[i] = #steps   -- (a line after source step i: after the last kept step up to it)
			end
			for _, b in ipairs(c.breaks or {}) do
				local at = map[b]
				if at and at > 0 and at < #steps then breaks[at] = true end
			end
			if #steps >= 2 then
				local chain = { steps = steps, breaks = breaks, src = c.src }
				chains[#chains + 1] = chain
				-- (a quest in two chains, two series joined to one: the chain that shows more steps)
				local function Put(id, i, alt)
					local had = byQuest[id]
					if not had or #had.chain.steps < #steps then byQuest[id] = { chain = chain, step = i, alt = alt } end
				end
				for i, s in ipairs(steps) do
					Put(s.id, i)
					for _, a in ipairs(s.alt or {}) do Put(a.id, i, true) end
				end
			end
		end
	end
	QC.byQuest, QC.chains = byQuest, chains
	return #chains
end
QC.byQuest, QC.chains = {}, {}

function QC.Player()
	local side = Call(UnitFactionGroup, "player")
	local _, class = Call(UnitClass, "player")
	return side, class
end

function QC.Load()
	local side, class = QC.Player()
	return QC.Build(ns.QuestChainData, side, class)
end

function QC.Of(questID) return questID and QC.byQuest[questID] or nil end

--------------------------------------------------------------------------------
-- A quest's state: done (flagged completed), in the log, else to do
--------------------------------------------------------------------------------

function QC.Done(id)
	local C = rawget(_G, "C_QuestLog")
	if C and C.IsQuestFlaggedCompleted then return Call(C.IsQuestFlaggedCompleted, id) and true or false end
	return Call(rawget(_G, "IsQuestFlaggedCompleted"), id) and true or false
end
function QC.InLog(id)
	local C = rawget(_G, "C_QuestLog")
	return C and C.GetLogIndexForQuestID and Call(C.GetLogIndexForQuestID, id) ~= nil or false
end

-- what the window shows for a chain, from the quest clicked: rows in order (steps, their 'or' quests
-- indented after them, a line after a joined series), the counts
function QC.Lines(chain, current)
	local out, done = {}, 0
	for i, s in ipairs(chain.steps) do
		local sDone = QC.Done(s.id)
		local anyDone = sDone
		for _, a in ipairs(s.alt or {}) do if QC.Done(a.id) then anyDone = true end end
		if anyDone then done = done + 1 end
		out[#out + 1] = { id = s.id, name = s.name, n = i, done = sDone, inLog = QC.InLog(s.id), opt = s.opt, here = s.id == current,
			other = anyDone and not sDone or nil }
		for _, a in ipairs(s.alt or {}) do
			local aDone = QC.Done(a.id)
			out[#out + 1] = { id = a.id, name = a.name, n = i, alt = true, done = aDone, inLog = QC.InLog(a.id), opt = a.opt,
				here = a.id == current, other = anyDone and not aDone or nil }
		end
		if chain.breaks[i] then out[#out].line = true end
	end
	return out, done
end

-- a line's colour: done grey; the quest clicked the Look's selected; optional or the other path dimmed;
-- to do (and in progress) the Look's text colour
function QC.Color(line, th)
	if line.done then return QC.GREY end
	if line.here then return th.selected or { 1, 1, 1 } end
	if line.opt or line.other then return th.dim or { 0.7, 0.62, 0.45 } end
	return th.text or { 1, 0.82, 0 }
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local win, shownFor
local lines = {}

local function Theme()
	local St = ns.Style
	return St and St.Theme and St.Theme() or { text = { 1, 0.82, 0 }, selected = { 1, 1, 1 }, dim = { 0.72, 0.63, 0.45 }, highlight = { 1, 0.85, 0.45, 0.16 } }
end

local function MapFrame() return rawget(_G, "WorldMapFrame") end

local function Make()
	if win then return win end
	win = CreateFrame("Frame", "ValhallaQuestChain", UIParent)
	win:SetFrameStrata("DIALOG")
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetSize(QC.WIDTH, 120)
	local top = 0
	if ns.Look and ns.Look.Window then top = ns.Look:Window(win, L["Quest chain"], function() QC.Close() end) or 0 end
	win.top = top
	win.head = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	win.head:SetPoint("TOPLEFT", 14, -top - 10)
	win.head:SetPoint("TOPRIGHT", -14, -top - 10)
	win.head:SetJustifyH("LEFT")
	win.head:SetWordWrap(false)
	win.sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	win.sub:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", 0, -4)
	win.sub:SetJustifyH("LEFT")
	win.foot = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	win.foot:SetJustifyH("LEFT")
	win.foot:SetText(L["Grey: done. Order: Wowhead (WoW Forever)."])
	win:Hide()
	if type(rawget(_G, "UISpecialFrames")) == "table" then tinsert(UISpecialFrames, "ValhallaQuestChain") end   -- (Escape closes it)
	-- (1.2.0) the map window (Valhalla's main window) closed: the chain closes with it
	local map = MapFrame()
	if map and map.HookScript then map:HookScript("OnHide", function() QC.Close() end) end
	return win
end

local function Line(i)
	local r = lines[i]
	if r then return r end
	r = CreateFrame("Frame", nil, win)
	r:SetSize(QC.WIDTH - 28, QC.ROW_H)
	r.hl = r:CreateTexture(nil, "BACKGROUND")
	r.hl:SetAllPoints()
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetSize(14, 12)
	r.mark:SetAtlas("common-dropdown-icon-checkmark-yellow")
	if r.mark.SetDesaturated then r.mark:SetDesaturated(true) end
	r.num = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.num:SetSize(24, 16)
	r.num:SetJustifyH("RIGHT")
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.text:SetJustifyH("LEFT")
	r.text:SetWordWrap(false)
	r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.tag:SetPoint("RIGHT", -6, 0)
	r.tag:SetJustifyH("RIGHT")
	r.line = r:CreateTexture(nil, "ARTWORK")
	r.line:SetHeight(1)
	r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 22, -1)
	r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -6, -1)
	lines[i] = r
	return r
end

-- (also after a turn-in, an accept, a Look change)
function QC.Fill()
	if not (win and shownFor) then return end
	local entry = QC.Of(shownFor)
	if not entry then QC.Close() return end
	local th = Theme()
	local list, done = QC.Lines(entry.chain, shownFor)
	local steps = #entry.chain.steps
	win.head:SetText(entry.chain.steps[1].name)
	win.sub:SetText(L["Step %d of %d    %d done"]:format(entry.step, steps, done))
	local d = th.dim or { 0.72, 0.63, 0.45 }
	win.sub:SetTextColor(d[1], d[2], d[3])
	local y = -(win.top or 0) - 52
	for i, ln in ipairs(list) do
		local r = Line(i)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", win, "TOPLEFT", 14, y)
		local x = ln.alt and QC.INDENT or 0
		r.mark:ClearAllPoints()
		r.mark:SetPoint("LEFT", r, "LEFT", 2 + x, 0)
		r.mark:SetShown(ln.done)
		r.mark:SetAlpha(0.7)
		r.num:ClearAllPoints()
		r.num:SetPoint("LEFT", r, "LEFT", 18 + x, 0)
		r.num:SetText(ln.alt and "" or (ln.n .. "."))
		r.text:ClearAllPoints()
		r.text:SetPoint("LEFT", r, "LEFT", 46 + x, 0)
		r.text:SetPoint("RIGHT", r, "RIGHT", -84, 0)
		local name = ln.name
		if ln.alt then name = L["or %s"]:format(name) end
		if ln.opt then name = name .. " " .. L["(optional)"] end
		if ln.other then name = name .. " " .. L["(other path)"] end
		r.text:SetText(name)
		local c = QC.Color(ln, th)
		r.text:SetTextColor(c[1], c[2], c[3])
		r.num:SetTextColor(c[1], c[2], c[3])
		if ln.here then
			local h = th.highlight or { 1, 0.85, 0.45, 0.16 }
			r.hl:SetColorTexture(h[1], h[2], h[3], 0.32)
			r.hl:Show()
		else
			r.hl:Hide()
		end
		r.tag:SetText((ln.inLog and not ln.done) and L["In your log"] or "")
		r.tag:SetTextColor(QC.IN_LOG[1], QC.IN_LOG[2], QC.IN_LOG[3])
		if ln.line then r.line:SetColorTexture(d[1], d[2], d[3], 0.5) r.line:Show() else r.line:Hide() end
		r:Show()
		y = y - QC.ROW_H
	end
	for i = #list + 1, #lines do lines[i]:Hide() end
	win.foot:ClearAllPoints()
	win.foot:SetPoint("TOPLEFT", win, "TOPLEFT", 16, y - 8)
	win.foot:SetPoint("RIGHT", win, "RIGHT", -14, 0)
	win:SetHeight(-y + 36)
	QC.shownLines = list
end

-- to the right of the map window, its top level with the row clicked (kept on the screen)
function QC.Place(row)
	local map = MapFrame()
	win:ClearAllPoints()
	local mt, rt = map and map.GetTop and map:GetTop(), row and row.GetTop and row:GetTop()
	local dy = (mt and rt) and (rt - mt + 10) or -40
	if dy > 0 then dy = 0 end
	if map then win:SetPoint("TOPLEFT", map, "TOPRIGHT", 8, dy) else win:SetPoint("CENTER") end
end

function QC.Open(questID, row)
	if not QC.Of(questID) then return false end
	Make()
	shownFor = questID
	QC.Place(row)
	win:Show()
	QC.Fill()
	return true
end

function QC.Close()
	shownFor = nil
	if win then win:Hide() end
end

function QC.Toggle(questID, row)
	if win and win:IsShown() and shownFor == questID then QC.Close() return false end
	return QC.Open(questID, row)
end
function QC.ShownFor() return win and win:IsShown() and shownFor or nil end
function QC.Window() return win end

--------------------------------------------------------------------------------
-- The quest log's rows: the Track tick hidden (every row, while on), our chain button in its place
--------------------------------------------------------------------------------

local buttons = setmetatable({}, { __mode = "k" })   -- row -> our button
local hooked = false

local function Pool()
	local q = rawget(_G, "QuestScrollFrame")
	return type(q) == "table" and q.titleFramePool or nil
end

function QC.On() return mod.db and mod.db.chainView and mod.enabled and true or false end

local function ButtonFor(row)
	local b = buttons[row]
	if b then return b end
	b = CreateFrame("Button", nil, row)
	b:SetSize(QC.BUTTON, QC.BUTTON)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(QC.TEXTURE)
	b.hl = b:CreateTexture(nil, "HIGHLIGHT")
	b.hl:SetAllPoints()
	b.hl:SetTexture(QC.TEXTURE)
	b.hl:SetBlendMode("ADD")
	b.hl:SetAlpha(0.4)
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function(self) QC.Toggle(self.questID, self.row) end)
	b.row = row
	buttons[row] = b
	return b
end

function QC.OnUpdate()
	local pool = Pool()
	if not (pool and pool.EnumerateActive) then return end
	local on = QC.On()
	for row in pool:EnumerateActive() do
		local cb = row.Checkbox
		if cb and cb.SetShown then cb:SetShown(not on) end
		local q = row.questID
		if on and q and QC.Of(q) then
			local b = ButtonFor(row)
			b.questID = q
			b:ClearAllPoints()
			if cb then b:SetPoint("CENTER", cb, "CENTER", 0, 0) else b:SetPoint("TOPRIGHT", row, "TOPRIGHT", 2, -6) end
			b:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
			b:Show()
		elseif buttons[row] then
			buttons[row]:Hide()
		end
	end
end

function QC.Hook()
	if hooked then return true end
	local pool = Pool()
	if not (pool and type(rawget(_G, "QuestLogQuests_Update")) == "function" and hooksecurefunc) then return false end
	hooksecurefunc("QuestLogQuests_Update", QC.OnUpdate)
	hooked = true
	return true
end
function QC.Hooked() return hooked end

-- the rows as they are now (no log update needed: ours only)
function QC.Refresh()
	QC.Hook()
	QC.OnUpdate()
	if not QC.On() then QC.Close() end
end

--------------------------------------------------------------------------------
-- The setting
--------------------------------------------------------------------------------

function QC.IsViewOn() return mod.db and mod.db.chainView and true or false end

function QC.SetView(v)
	if not mod.db then return end
	mod.db.chainView = v and true or false
	QC.Refresh()
	if ns.NotifyOptions then pcall(ns.NotifyOptions) end
end

-- the quest log's gear menu (QuestMapFrame_SetupSettingsDropdown: MENU_QUEST_MAP_FRAME_SETTINGS)
local menuAdded = false
function QC.AddToMenu()
	if menuAdded then return true end
	local M = rawget(_G, "Menu")
	if not (type(M) == "table" and type(M.ModifyMenu) == "function") then return false end
	local ok = pcall(M.ModifyMenu, "MENU_QUEST_MAP_FRAME_SETTINGS", function(_, root)
		if root and root.CreateCheckbox then
			root:CreateCheckbox(L["Chain quest view"], function() return QC.IsViewOn() end, function() QC.SetView(not QC.IsViewOn()) end)
		end
	end)
	menuAdded = ok and true or false
	return menuAdded
end

--------------------------------------------------------------------------------
-- /valhalla chain coverage
--------------------------------------------------------------------------------

function QC.Coverage()
	local C = rawget(_G, "C_QuestLog")
	local with, without, names = 0, 0, {}
	local none = {}   -- quests whose Wowhead page was read and has no Series box
	local data = ns.QuestChainData
	for _, q in ipairs(type(data) == "table" and type(data.noSeries) == "table" and data.noSeries or {}) do none[q] = true end
	local n = C and C.GetNumQuestLogEntries and Call(C.GetNumQuestLogEntries) or 0
	for i = 1, n do
		local info = Call(C.GetInfo, i)
		if type(info) == "table" and not info.isHeader and info.questID and not info.isHidden then
			if QC.Of(info.questID) then with = with + 1 else without = without + 1 names[#names + 1] = ("%s (%d)%s"):format(info.title or "?", info.questID, none[info.questID] and L[": no series on Wowhead"] or "") end
		end
	end
	local meta = type(ns.QuestChainData) == "table" and ns.QuestChainData.meta or {}
	local out = {
		L["Chain data: %d chains for this character (%s, built %s)."]:format(#QC.chains, tostring(meta.source or "none"), tostring(meta.built or "-")),
		L["Your quest log: %d with chain data, %d without."]:format(with, without),
	}
	if #names > 0 then out[#out + 1] = L["Without: %s"]:format(table.concat(names, ", ")) end
	out[#out + 1] = L["Chain quest view: %s."]:format(QC.IsViewOn() and L["on"] or L["off"])
	return out, with, without
end

function mod:Slash(arg)
	arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if arg == "on" then QC.SetView(true) elseif arg == "off" then QC.SetView(false) end
	if arg == "coverage" or arg == "on" or arg == "off" or arg == "" then
		for _, line in ipairs((QC.Coverage())) do ns:Print("%s", line) end
	end
	if arg ~= "coverage" then ns:Print("%s", L["/valhalla chain coverage | on | off"]) end
end

--------------------------------------------------------------------------------
-- on / off
--------------------------------------------------------------------------------

local events
function mod:OnEnable()
	QC.Load()
	QC.AddToMenu()
	if not events then
		events = CreateFrame("Frame")
		events:SetScript("OnEvent", function(_, event)
			if event == "PLAYER_ENTERING_WORLD" then QC.Hook() QC.AddToMenu() return end
			if QC.ShownFor() then QC.Fill() end
		end)
	end
	for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, e)
	end
	QC.Hook()
	if not QC.lookHooked and ns.Style and ns.Style.OnLook then
		QC.lookHooked = true
		ns.Style.OnLook(function() if QC.ShownFor() then QC.Fill() end end)   -- (the frame itself: Style.Reskin)
	end
end

function mod:OnDisable()
	if events then events:UnregisterAllEvents() end
	mod.enabled = false
	QC.Refresh()
end
