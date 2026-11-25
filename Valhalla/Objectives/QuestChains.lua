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
-- 1.2.11: the log's zones always in alphabetical order (the game re-sorted them on every map change, a quest's
-- click too); setting "Show Ready to Turn In section" (after Chain quest view, off at first): ready quests
-- listed in their own section at the bottom (see QC.Arrange).
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local mod = ns:NewModule("chains", { defaults = {
	chainView = false,          -- Chain quest view (the quest log's gear menu, Valhalla's menu)
	readyInLog = false,         -- (1.2.11) Show Ready to Turn In section (the gear menu, after Chain quest view)
	readyLogCollapsed = false,  -- (1.2.11) that section folded to its header (its header saves it)
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

local Call = ns.Util.Call

-- (1.2.23) the game's tracker and quest log changed only out of combat (CombatQueue.lua): in combat it waits
-- (1.2.24: CombatQueue.lua's gate: combat, the player in combat, secret auras, the settle after combat)
local InCombat, Defer = ns.Util.InCombat, ns.Util.Defer

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
	-- (1.2.22: the zone headers' clicks heard, their states noted)
	if QC.Zones then
		local ok, err = pcall(QC.Zones.Watch)
		if not ok then QC.lastError = tostring(err) end
	end
	-- (1.2.11: the zones in order, the Ready section; an error said once, never breaking the game's log)
	-- (1.2.36: only while the quest log is open. Closed, the game's rows are left alone)
	QC.ArrangeSoon()
end

-- the quest log open: beside the map, or over it full screen (the same frames WorldMap.lua's QuestLogShown uses)
function QC.LogVisible()
	local qm = rawget(_G, "QuestMapFrame")
	if type(qm) == "table" then
		local shown = qm.IsVisible or qm.IsShown
		if type(shown) == "function" then return shown(qm) and true or false end
	end
	local wm = rawget(_G, "WorldMapFrame")
	if type(wm) == "table" and type(wm.IsSidePanelShown) == "function" and wm:IsSidePanelShown() then return true end
	return false
end

-- (1.2.26) the arrange writes the game's quest log rows' layoutIndex / topPadding and lays the log out again:
-- only when CombatQueue.lua's gate is clear (combat, secret auras, the settle after combat); else queued under
-- one key, run once clear (the log as it is then)
function QC.ArrangeSafe()
	if not QC.Arrange then return end
	local ok, err = pcall(QC.Arrange)
	if not ok then
		QC.lastError = tostring(err)
		if not QC.errorSaid then QC.errorSaid = true ns:Print("%s", L["Quest log order: an error (%s). The game's own order is kept."]:format(QC.lastError)) end
	end
end
function QC.ArrangeSoon()
	if not QC.LogVisible() then return end   -- (1.2.36)
	return Defer("questlog:arrange", QC.ArrangeSafe)
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

--------------------------------------------------------------------------------
-- (1.2.11) The quest log's zones in alphabetical order, and the Ready to Turn In section
-- Why: the game sorts its quest log (SortQuests, in C) for the map shown, on every map change
-- (WorldMapMixin:OnMapChanged -> QuestLogMixin:Refresh), and a quest's click moves the map to the quest's
-- zone (QuestMapFrame_ShowQuestDetails -> SetMapID); Valhalla's seamless map switches maps as it pans: the
-- zones jumped about. Now, after each QuestLogQuests_Update (and Layout), the zone headers of the normal
-- section (QuestScrollFrame.headerFramePool; campaign headers have their own pools, left first) and their
-- quest rows are put in order by the zone's name: only their layoutIndex / topPadding (the spacing the game
-- would give: QuestMapFrame.lua's spacing pairs) are set, then Contents:Layout() again.
-- Ready to Turn In (setting readyInLog, off at first: the gear menu and Valhalla's menu): every quest ready to
-- turn in (ReadyForTurnIn, else IsComplete, as Objectives.lua) leaves its zone (its row, objectives and quest
-- icon hidden) and is listed in our own section at the very bottom, "Ready to Turn In (N)": the game's header
-- look (ListHeaderVisualTemplate), its collapse state saved (readyLogCollapsed). A zone whose every quest is
-- there keeps its header, with "Quests are in the Ready to Turn In section" under it (when expanded). Our rows:
-- left-click opens the quest (QuestMapFrame_ShowQuestDetails, as the game's row), Shift-click tracks it
-- (QuestMapQuestOptions_TrackQuest, as the game's row; a quest link into an open chat first), the chain button
-- on them with Chain quest view. Off: the rows we hid shown again; nothing of ours shown.
--------------------------------------------------------------------------------

QC.READY_W = 290
-- the game's spacing pairs (QuestMapFrame.lua QuestLogQuests_UpdateButtonSpacing) for what we move
local SPACE = { HeaderHeader = 6, QuestHeader = 4, NoneHeader = 8, HeaderQuest = 2, QuestQuest = -3 }
QC.SPACE = SPACE

local ours = { rows = {}, notes = {} }   -- our header, rows (by position) and notes (by zone header button)
local hiddenByUs = setmetatable({}, { __mode = "k" })   -- the game's frames we hid (shown again when not ready / off)
QC.ours = ours

function QC.IsReadyOn() return mod.db and mod.db.readyInLog and true or false end
local function ReadyOn() return QC.IsReadyOn() and mod.enabled and true or false end

function QC.SetReady(v)
	if not mod.db then return end
	mod.db.readyInLog = v and true or false
	QC.Refresh()
	if ns.NotifyOptions then pcall(ns.NotifyOptions) end
end

local function Contents()
	local q = rawget(_G, "QuestScrollFrame")
	return type(q) == "table" and q.Contents or nil
end

-- ready to turn in, as the tracker says it
function QC.IsReady(id)
	local C = rawget(_G, "C_QuestLog")
	if not (C and id) then return false end
	local r = Call(C.ReadyForTurnIn, id)
	if not r then r = Call(C.IsComplete, id) end
	return r and true or false
end

-- the log's quests by zone: { [headerLogIndex] = { name, quests = { { id, idx, title, ready }, ... } } }, ready list
function QC.ReadLog()
	local C = rawget(_G, "C_QuestLog")
	local zones, ready, cur = {}, {}, nil
	local n = C and C.GetNumQuestLogEntries and Call(C.GetNumQuestLogEntries) or 0
	for i = 1, n do
		local info = Call(C.GetInfo, i)
		if type(info) == "table" then
			if info.isHeader then
				cur = { name = info.title or "", idx = i, quests = {} }
				zones[i] = cur
			elseif info.questID and not info.isHidden and not info.isTask and not info.isBounty then
				local e = { id = info.questID, idx = i, title = info.title or ("Quest " .. info.questID), info = info, zone = cur }
				e.ready = QC.IsReady(info.questID)
				if cur then cur.quests[#cur.quests + 1] = e end
				if e.ready then ready[#ready + 1] = e end
			end
		end
	end
	return zones, ready
end

local function Lower(s) return tostring(s or ""):lower() end
local function Before(a, b)
	local x, y = Lower(a.name), Lower(b.name)
	local cmp = rawget(_G, "strcmputf8i")
	if type(cmp) == "function" then
		local ok, r = pcall(cmp, a.name or "", b.name or "")
		if ok and type(r) == "number" and r ~= 0 then return r < 0 end
	elseif x ~= y then return x < y end
	return (a.order or 0) < (b.order or 0)
end
QC.ZoneBefore = Before

local function HeaderName(h)
	local C = rawget(_G, "C_QuestLog")
	local info = rawget(h, "questLogIndex") and C and Call(C.GetInfo, rawget(h, "questLogIndex"))
	if type(info) == "table" and info.title then return info.title end
	local t = rawget(h, "ButtonText") or rawget(h, "Text")
	return type(t) == "table" and t:GetText() or (h.GetText and h:GetText()) or ""
end

-- our header: the game's list header look; a plain button where the template isn't there
local function ReadyHeader(parent)
	local h = ours.header
	if h then return h end
	local ok, f = pcall(CreateFrame, "Button", nil, parent, "ListHeaderVisualTemplate, ListHeaderCodeTemplate")
	if not ok or not f then f = CreateFrame("Button", nil, parent) end
	local native = type(rawget(f, "CollapseButton")) == "table" and type(rawget(f, "ButtonText")) == "table"   -- (the template took)
	f.valhallaNative = native
	f:SetSize(QC.READY_W - 1, 22)
	f.leftPadding = 9
	f.valhallaReady = true
	if type(rawget(f, "ButtonText")) ~= "table" then
		f.ButtonText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.ButtonText:SetPoint("LEFT", 8, 0)
	end
	local function Toggle()
		if mod.db then mod.db.readyLogCollapsed = not mod.db.readyLogCollapsed end
		QC.ArrangeSoon()
	end
	if native and f.SetClickHandler then f:SetClickHandler(function(_, button) if button == "LeftButton" then Toggle() end end)
	else f:SetScript("OnClick", Toggle) end
	if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp") end
	ours.header = f
	return f
end

local function ShowTitle(f, s) local t = rawget(f, "ButtonText") if type(t) == "table" then t:SetText(s) else f:SetText(s) end end

local function TitleOf(e)
	local title = e.title
	local U = rawget(_G, "QuestUtilsOverrides")
	if type(U) == "table" and type(U.GetQuestTitlePrefix) == "function" then
		local ok, p = pcall(U.GetQuestTitlePrefix, e.info)
		if ok and type(p) == "string" then title = p .. title end
	end
	return title
end

function QC.RowClick(row, button)
	local q = rawget(row, "questID")
	if not q then return end
	if IsShiftKeyDown and IsShiftKeyDown() then
		local CF = rawget(_G, "ChatFrameUtil")
		if type(CF) == "table" and type(CF.TryInsertQuestLinkForQuestID) == "function" then
			local ok, did = pcall(CF.TryInsertQuestLinkForQuestID, q)
			if ok and did then return end
		end
		-- (1.2.54) Shift-click with the chat closed: nothing (it toggled tracking: the Objectives panel changed)
		return
	elseif button == "LeftButton" or button == nil then
		-- (1.2.24) the game's quest details (they move the tracker's selection) wait on the gate too
		Defer("details", function()
			local show = rawget(_G, "QuestMapFrame_ShowQuestDetails")
			if type(show) == "function" then show(q) end
		end, "Quest details open when combat ends.")
	end
end

local function ReadyRow(parent, i)
	local r = ours.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, parent)
	r:SetSize(QC.READY_W, 16)
	r.leftPadding = 4
	r.valhallaReady = true
	r.Icon = r:CreateTexture(nil, "ARTWORK")
	r.Icon:SetSize(18, 18)
	r.Icon:SetPoint("TOPLEFT", 6, -4)
	r.Icon:SetAtlas("QuestTurnin")
	r.Text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
	r.Text:SetPoint("TOPLEFT", 31, -8)
	r.Text:SetPoint("RIGHT", r, "RIGHT", -26, 0)
	r.Text:SetTextColor(0.75, 0.61, 0)
	if r.Text.SetJustifyH then r.Text:SetJustifyH("LEFT") end
	r.Sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.Sub:SetPoint("TOPLEFT", r.Text, "BOTTOMLEFT", 0, -3)
	r.Sub:SetPoint("RIGHT", r, "RIGHT", -26, 0)
	r.Sub:SetTextColor(0.8, 0.8, 0.8)
	if r.Sub.SetJustifyH then r.Sub:SetJustifyH("LEFT") end
	r.Glow = r:CreateTexture(nil, "HIGHLIGHT")
	r.Glow:SetAtlas("questlog-quest-glow-yellow")
	r.Glow:SetPoint("TOPLEFT", r.Text, "TOPLEFT", -8, 4)
	r.Glow:SetPoint("BOTTOMRIGHT", r.Text, "BOTTOMRIGHT", 8, -4)
	r:RegisterForClicks("LeftButtonUp")
	r:SetScript("OnClick", function(self, button) QC.RowClick(self, button) end)
	r:SetScript("OnEnter", function(self) self.Text:SetTextColor(1, 0.82, 0) end)
	r:SetScript("OnLeave", function(self) self.Text:SetTextColor(0.75, 0.61, 0) end)
	ours.rows[i] = r
	return r
end

local function Note(parent, h)
	local n = ours.notes[h]
	if n then return n end
	n = CreateFrame("Frame", nil, parent)
	n:SetSize(QC.READY_W, 20)
	n.leftPadding = 31
	n.valhallaReady = true
	n.Text = n:CreateFontString(nil, "OVERLAY", "GameFontDisableSmallLeft")
	n.Text:SetPoint("TOPLEFT", 0, -4)
	n.Text:SetPoint("RIGHT", n, "RIGHT", -10, 0)
	if n.Text.SetJustifyH then n.Text:SetJustifyH("LEFT") end
	n.Text:SetText(L["Quests are in the Ready to Turn In section"])
	ours.notes[h] = n
	return n
end

-- (1.2.38) this Arrange showed or hid a row, the Ready header, a Ready row, or a note: lay out even when
-- the indices that remain would already sort into place. A hidden frame keeps no layoutIndex, so it cannot
-- sit on the number we then give to a row that is still shown.
local showedOrHid = false
local function DropIndex(f)
	if type(f) == "table" and rawget(f, "layoutIndex") ~= nil then f.layoutIndex = nil end
end
local function HideFromLayout(f)
	if type(f) ~= "table" then return end
	if f.IsShown and f:IsShown() then f:Hide() showedOrHid = true end
	DropIndex(f)
end
local function ShowInLayout(f)
	if type(f) ~= "table" then return end
	if f.IsShown and not f:IsShown() then showedOrHid = true end
	f:Show()
end

local function HideOurs()
	if ours.header then HideFromLayout(ours.header) end
	for _, r in ipairs(ours.rows) do HideFromLayout(r) end
	for _, n in pairs(ours.notes) do HideFromLayout(n) end
end

-- the game folded this row's zone (QuestLogQuests_Update hid it): do not show it again
local function ZoneFolded(row)
	local idx = rawget(row, "questLogIndex")
	local C = rawget(_G, "C_QuestLog")
	if not (type(idx) == "number" and type(C) == "table" and C.GetInfo) then return false end
	for i = idx, 1, -1 do
		local info = Call(C.GetInfo, i)
		if type(info) == "table" and info.isHeader then return info.isCollapsed and true or false end
	end
	return false
end

-- a ready quest's row: hidden with its objective lines and its quest icon (shown again when no longer)
local function SetRowShown(row, show)
	local q = rawget(row, "questID")
	local SF = rawget(_G, "QuestScrollFrame")
	local function Each(fn)
		local op = SF and SF.objectiveFramePool
		if op and op.EnumerateActive then for o in op:EnumerateActive() do if rawget(o, "questID") == q then fn(o) end end end
		local c = SF and SF.Contents
		local poi = c and type(c.FindButtonByQuestID) == "function" and Call(c.FindButtonByQuestID, c, q)
		if type(poi) ~= "table" then poi = nil end
		if poi and rawget(poi, "parent") == row then fn(poi) end
	end
	if show then
		if hiddenByUs[row] then
			hiddenByUs[row] = nil
			if not ZoneFolded(row) then
				ShowInLayout(row)
				Each(function(f) if hiddenByUs[f] then hiddenByUs[f] = nil ShowInLayout(f) end end)
			end
		end
	elseif row:IsShown() then
		hiddenByUs[row] = true
		HideFromLayout(row)
		Each(function(f) if f:IsShown() then hiddenByUs[f] = true HideFromLayout(f) end end)
	end
end

-- after the game's update (and on our setting / collapse changes): the order, the Ready section
function QC.Arrange()
	showedOrHid = false
	if not QC.LogVisible() then return false end   -- (1.2.36: queued, then the log closed)
	local SF = rawget(_G, "QuestScrollFrame")
	local contents = Contents()
	if not (SF and contents and SF.headerFramePool and SF.titleFramePool and SF.headerFramePool.EnumerateActive) then return false end
	local readyOn = ReadyOn()
	-- (switched off, or Valhalla's quest log parts off: every row back, nothing of ours)
	for row in SF.titleFramePool:EnumerateActive() do
		if not (readyOn and rawget(row, "questID") and QC.IsReady(rawget(row, "questID"))) then SetRowShown(row, true) end
	end
	if not mod.enabled then HideOurs() return false end
	local zones, ready = QC.ReadLog()
	-- the game's zone headers and rows now (by log index), and where the normal section starts
	local heads, rows, base, firstPad, firstAt = {}, {}, nil, nil, nil
	for h in SF.headerFramePool:EnumerateActive() do
		if h:IsShown() and rawget(h, "layoutIndex") then
			heads[#heads + 1] = h
			if not base or rawget(h, "layoutIndex") < base then base = rawget(h, "layoutIndex") end
			if not firstAt or rawget(h, "layoutIndex") < firstAt then firstAt, firstPad = rawget(h, "layoutIndex"), rawget(h, "topPadding") end
		end
	end
	for r in SF.titleFramePool:EnumerateActive() do
		if r:IsShown() or (hiddenByUs[r] and rawget(r, "layoutIndex")) then
			-- (a campaign's quests sit above the normal section: only rows under a zone header move)
			rows[#rows + 1] = r
		end
	end
	-- (the normal section starts after the game's Separator, which comes after the campaigns and the zone story)
	local sep = rawget(contents, "Separator")
	local sepAt = type(sep) == "table" and rawget(sep, "layoutIndex")
	if type(sepAt) == "number" and (not base or sepAt + 1 > base) then base = sepAt + 1 end
	if not base then HideOurs() return false end   -- (nothing to place it after: the game's order, untouched)
	local groups = {}
	for i, h in ipairs(heads) do groups[i] = { head = h, name = HeaderName(h), idx = rawget(h, "questLogIndex") or 0, rows = {}, order = rawget(h, "layoutIndex") } end
	table.sort(groups, function(a, b) return a.idx < b.idx end)
	local loose = {}
	for _, r in ipairs(rows) do
		local info0 = rawget(r, "info")
		local idx = rawget(r, "questLogIndex") or (type(info0) == "table" and info0.questLogIndex)
		local g
		if idx then for _, x in ipairs(groups) do if x.idx < idx then g = x end end end
		if not g then   -- (no index: the header just above it by position)
			for _, x in ipairs(groups) do if (x.order or 0) < (rawget(r, "layoutIndex") or 0) and (not g or x.order > g.order) then g = x end end
		end
		if g then g.rows[#g.rows + 1] = r elseif rawget(r, "layoutIndex") >= base then loose[#loose + 1] = r end
	end
	table.sort(groups, Before)
	-- the sequence: each zone (header, its note, its rows still shown), then the Ready section
	local seq = {}
	local function Add(f, kind) seq[#seq + 1] = { f = f, kind = kind } end
	for _, r in ipairs(loose) do Add(r, "Quest") end
	local used = {}
	for _, g in ipairs(groups) do
		Add(g.head, "Header")
		table.sort(g.rows, function(a, b) return (rawget(a, "questLogIndex") or rawget(a, "layoutIndex") or 0) < (rawget(b, "questLogIndex") or rawget(b, "layoutIndex") or 0) end)
		local left = 0
		for _, r in ipairs(g.rows) do
			if readyOn and rawget(r, "questID") and QC.IsReady(rawget(r, "questID")) then SetRowShown(r, false) else left = left + 1 end
		end
		local z = zones[rawget(g.head, "questLogIndex") or -1]
		local info = z and Call(rawget(_G, "C_QuestLog").GetInfo, z.idx)
		local collapsed = type(info) == "table" and info.isCollapsed
		local allReady = false
		if readyOn and z and #z.quests > 0 then
			allReady = true
			for _, e in ipairs(z.quests) do if not e.ready then allReady = false break end end
		end
		if allReady and not collapsed and left == 0 then
			local n = Note(contents, g.head)
			ShowInLayout(n)
			used[n] = true
			Add(n, "Quest")
		end
		for _, r in ipairs(g.rows) do if r:IsShown() then Add(r, "Quest") end end
	end
	for h, n in pairs(ours.notes) do if not used[n] then HideFromLayout(n) end end
	-- the Ready section
	local nShown = 0
	if readyOn then
		local hdr = ReadyHeader(contents)
		local collapsed = mod.db and mod.db.readyLogCollapsed and true or false
		ShowTitle(hdr, L["Ready to Turn In (%d)"]:format(#ready))
		if rawget(hdr, "valhallaNative") then pcall(hdr.UpdateCollapsedState, hdr, collapsed) end
		hdr.collapsed = collapsed
		ShowInLayout(hdr)
		Add(hdr, "Header")
		if not collapsed then
			-- (by zone name, then as in the log)
			table.sort(ready, function(a, b)
				local za, zb = a.zone and a.zone.name or "", b.zone and b.zone.name or ""
				if za ~= zb then return Before({ name = za }, { name = zb }) end
				return a.idx < b.idx
			end)
			local showObj = true
			if GetCVarBool then local ok, v = pcall(GetCVarBool, "showQuestObjectivesInLog") if ok then showObj = v and true or false end end
			for i, e in ipairs(ready) do
				local r = ReadyRow(contents, i)
				r.questID, r.questLogIndex = e.id, e.idx
				r.Text:SetText(TitleOf(e))
				local sub = showObj and (Call(rawget(_G, "GetQuestLogCompletionText"), e.idx) or rawget(_G, "QUEST_WATCH_QUEST_READY") or L["Ready for turn-in"]) or ""
				r.Sub:SetText(sub)
				r.Sub:SetShown(sub ~= "")
				local th = (r.Text.GetStringHeight and r.Text:GetStringHeight()) or 12
				local sh = sub ~= "" and (((r.Sub.GetStringHeight and r.Sub:GetStringHeight()) or 12) + 3) or 4
				r:SetHeight(8 + (tonumber(th) or 12) + sh + 6)
				ShowInLayout(r)
				Add(r, "Quest")
				nShown = i
				-- the chain button, as on the game's rows (Chain quest view on)
				if QC.On() and QC.Of(e.id) then
					local b = ButtonFor(r)
					b.questID = e.id
					b:ClearAllPoints()
					b:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -6)
					b:SetFrameLevel((r:GetFrameLevel() or 1) + 2)
					b:Show()
				elseif buttons[r] then buttons[r]:Hide() end
			end
		end
	elseif ours.header then HideFromLayout(ours.header) end
	for i = nShown + 1, #ours.rows do HideFromLayout(ours.rows[i]) end
	QC.lastSeq = seq
	-- (1.2.38) lay out unless every shown frame already has the index and the padding we would write,
	-- and this pass did not show or hide anything. A shared index is not a match.
	local function PadAt(i, kind, prev)
		if i == 1 then
			if kind == "Header" then return firstPad end
			return SPACE["None" .. kind] or 0
		end
		return SPACE[(prev or "") .. kind] or 0
	end
	local function Placed()
		local prev
		for i, s in ipairs(seq) do
			local f = s.f
			if not f:IsShown() then return false end
			if rawget(f, "layoutIndex") ~= base + i - 1 then return false end
			if rawget(f, "topPadding") ~= PadAt(i, s.kind, prev) then return false end
			prev = s.kind
		end
		return true
	end
	if not showedOrHid and Placed() then return true end
	local prev
	for i, s in ipairs(seq) do
		local f = s.f
		f.layoutIndex = base + i - 1
		f.topPadding = PadAt(i, s.kind, prev)
		prev = s.kind
	end
	if type(contents.Layout) == "function" then pcall(contents.Layout, contents) end
	return true
end

--------------------------------------------------------------------------------
-- (1.2.22) The log's zones stay as you leave them
-- Why: the game's quest log sets every zone header on each map change (WorldMapMixin:OnMapChanged ->
-- QuestLogMixin:Refresh -> QuestMapFrame_ResetFilters: the zones on the map shown expanded, every other one
-- collapsed), as the map opens and at every loading screen too; Valhalla's seamless map changes the map as
-- it pans. A zone you folded opened again, one you opened folded. Now a zone header you click (left button,
-- the header or its +/-) is remembered for the character by the zone's name (mod.char.logZones[name] =
-- true folded / false open), and put back after each ResetFilters and at PLAYER_ENTERING_WORLD with the
-- game's own ExpandQuestHeader / CollapseQuestHeader. Zones never clicked keep the game's way. Only clicks
-- are saved: not ResetFilters, not the search's save / restore (QuestSearcher), not a map pin's hover
-- (ExpandHeaderForQuest); nothing saved or put back while the search box has text. No field is written on
-- the game's frames (our own weak tables), its click handler stays its own (HookScript after it).
--------------------------------------------------------------------------------

local Z = { applying = false, hooked = false }
QC.Zones = Z
local clickHooked = setmetatable({}, { __mode = "k" })   -- the game's header buttons we hooked
local seenFolded = setmetatable({}, { __mode = "k" })    -- header -> folded when last laid out
local preFolded = setmetatable({}, { __mode = "k" })     -- header -> folded just before a click (PreClick)

local function Store()
	if not mod.char then return nil end
	mod.char.logZones = mod.char.logZones or {}
	return mod.char.logZones
end
Z.Store = Store

-- the search box has text: the game's search has the headers (its own save / restore)
local function Searching()
	local SF = rawget(_G, "QuestScrollFrame")
	local box = type(SF) == "table" and rawget(SF, "SearchBox")
	if type(box) ~= "table" or type(box.GetText) ~= "function" then return false end
	local ok, t = pcall(box.GetText, box)
	return ok and type(t) == "string" and t ~= ""
end
Z.Searching = Searching

local function InfoAt(i)
	local C = rawget(_G, "C_QuestLog")
	local info = i and C and Call(C.GetInfo, i)
	return type(info) == "table" and info or nil
end

-- a header clicked: after the game's own click (it expanded or collapsed it), its new state saved
function Z.OnHeaderClick(h, button)
	if button and button ~= "LeftButton" then return end
	if not mod.enabled or Z.applying or Searching() then return end
	local info = InfoAt(rawget(h, "questLogIndex"))
	if not (info and info.isHeader and type(info.title) == "string" and info.title ~= "") then return end
	local now = info.isCollapsed and true or false
	local before = preFolded[h]
	preFolded[h] = nil
	if before == nil then before = seenFolded[h] end
	-- (the game's state may follow a moment later: unchanged yet, it's the other one)
	if before ~= nil and now == before then now = not before end
	local store = Store()
	if not store then return end
	store[info.title] = now
	seenFolded[h] = now
end

-- the game's zone headers laid out: each hooked once (after its own OnClick), its state noted
function Z.Watch()
	local SF = rawget(_G, "QuestScrollFrame")
	local pool = type(SF) == "table" and SF.headerFramePool
	if not (pool and pool.EnumerateActive) then return end
	for h in pool:EnumerateActive() do
		if not clickHooked[h] and type(h.HookScript) == "function" then
			clickHooked[h] = true
			-- (its state just before the click: the game may update it at once or a moment later)
			h:HookScript("PreClick", function(self)
				local info = InfoAt(rawget(self, "questLogIndex"))
				if info and info.isHeader then preFolded[self] = info.isCollapsed and true or false end
			end)
			h:HookScript("OnClick", function(self, button)
				local ok, err = pcall(Z.OnHeaderClick, self, button)
				if not ok then geterrorhandler()(err) end
			end)
		end
		local info = InfoAt(rawget(h, "questLogIndex"))
		if info and info.isHeader then seenFolded[h] = info.isCollapsed and true or false end
	end
end

-- the saved zones put back (after the game set them all); the rest left as the game set them
function Z.Apply()
	if Z.applying or not mod.enabled or Searching() then return 0 end
	-- (1.2.23) never in combat: the headers' changes lay the game's tracker out from Valhalla's code, and in
	-- combat its aura read errors. Put back once combat ends (one queued apply, whatever asked for it)
	if InCombat() then
		Defer("questlog:zones", function() Z.Apply() end)
		return 0
	end
	local store = mod.char and mod.char.logZones
	if type(store) ~= "table" or next(store) == nil then return 0 end
	local C = rawget(_G, "C_QuestLog")
	local expand, collapse = rawget(_G, "ExpandQuestHeader"), rawget(_G, "CollapseQuestHeader")
	if not (C and type(expand) == "function" and type(collapse) == "function") then return 0 end
	local n = Call(C.GetNumQuestLogEntries) or 0
	local todo = {}
	for i = 1, n do
		local info = InfoAt(i)
		if info and info.isHeader and info.title ~= nil then
			local want = store[info.title]
			if want ~= nil and (info.isCollapsed and true or false) ~= want then todo[#todo + 1] = { i, want } end
		end
	end
	if #todo == 0 then return 0 end
	Z.applying = true
	for _, t in ipairs(todo) do
		local ok, err = pcall(t[2] and collapse or expand, t[1], true)   -- (as ResetFilters calls them)
		if not ok then QC.lastError = tostring(err) end
	end
	Z.applying = false
	-- (the headers on show: their states as now set, for a click before the next layout)
	local SF = rawget(_G, "QuestScrollFrame")
	local pool = type(SF) == "table" and SF.headerFramePool
	if pool and pool.EnumerateActive then
		for h in pool:EnumerateActive() do
			local info = InfoAt(rawget(h, "questLogIndex"))
			if info and info.isHeader then seenFolded[h] = info.isCollapsed and true or false end
		end
	end
	return #todo
end

function Z.Hook()
	if Z.hooked then return true end
	if type(rawget(_G, "QuestMapFrame_ResetFilters")) ~= "function" or not hooksecurefunc then return false end
	hooksecurefunc("QuestMapFrame_ResetFilters", function()
		local ok, err = pcall(Z.Apply)
		if not ok then geterrorhandler()(err) end
	end)
	Z.hooked = true
	return true
end

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
			root:CreateCheckbox(L["Show Ready to Turn In section"], function() return QC.IsReadyOn() end, function() QC.SetReady(not QC.IsReadyOn()) end)
		end
	end)
	menuAdded = ok and true or false
	return menuAdded
end

--------------------------------------------------------------------------------
-- /valhalla chain coverage
--------------------------------------------------------------------------------

-- a quest in this character's log: chain (in one of this character's chains), noSeries (its Wowhead
-- page was read and had no Series box), unread (not on Wowhead Forever's quest list), otherChain
-- (on that list, but not this character's chain and not a page we read with no Series box).
local NOTE = {
	noSeries = ": no series on Wowhead",
	unread = ": not on Wowhead Forever's list",
	otherChain = ": another chain",
}

local function Status(id, none, forever, haveList)
	if QC.Of(id) then return "chain" end
	if none[id] then return "noSeries" end
	if haveList and not forever[id] then return "unread" end
	return "otherChain"
end

function QC.Coverage()
	QC.Load()
	local C = rawget(_G, "C_QuestLog")
	local with, without, names = 0, 0, {}
	local none, forever, haveList = {}, {}, false
	local data = ns.QuestChainData
	if type(data) == "table" then
		for _, q in ipairs(type(data.noSeries) == "table" and data.noSeries or {}) do none[q] = true end
		if type(data.forever) == "table" then
			haveList = true
			for _, q in ipairs(data.forever) do forever[q] = true end
		end
	end
	local saved = {}
	local n = C and C.GetNumQuestLogEntries and Call(C.GetNumQuestLogEntries) or 0
	for i = 1, n do
		local info = Call(C.GetInfo, i)
		if type(info) == "table" and not info.isHeader and info.questID and not info.isHidden then
			local status = Status(info.questID, none, forever, haveList)
			saved[#saved + 1] = { id = info.questID, name = info.title or "?", status = status }
			if status == "chain" then with = with + 1
			else
				without = without + 1
				names[#names + 1] = ("%s (%d)%s"):format(info.title or "?", info.questID, NOTE[status] and L[NOTE[status]] or "")
			end
		end
	end
	if type(mod.char) == "table" then
		local runs = mod.char.coverage
		if type(runs) ~= "table" then runs = {} mod.char.coverage = runs end
		local now = (type(time) == "function" and time()) or (os and os.time and os.time()) or 0
		table.insert(runs, 1, { at = now, quests = saved })
		while #runs > 3 do table.remove(runs) end
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
	arg = ns.Util.Trim(arg):lower()
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
			if event == "PLAYER_ENTERING_WORLD" then
				QC.Hook() QC.AddToMenu() Z.Hook()
				-- (1.2.22: the saved zones back after the game's own Refresh of this event, whichever ran first)
				pcall(Z.Apply)
				if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(Z.Apply) end) end
				return
			end
			if QC.ShownFor() then QC.Fill() end
		end)
	end
	for _, e in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, e)
	end
	QC.Hook()
	Z.Hook()
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
