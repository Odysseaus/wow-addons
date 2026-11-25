--------------------------------------------------------------------------------
-- Valhalla's core: saved settings, events, chat output, options plumbing and
-- the few look helpers the map uses. Loaded first; the map files (Map/*.lua)
-- add a module with ns:NewModule and Init.lua starts it at login.
--
-- Settings: ValhallaDB (account), ValhallaCharDB (per character), filled from
-- the module's defaults (missing keys only, so new defaults reach old saves).
-- (1.2.42) the world map's display toggles are per character. The first time a
-- character has none, they are copied from the account. Pins, sketches, paint,
-- flight times, window position and diagnostics stay on the account.
--------------------------------------------------------------------------------

local ADDON, ns = ...
_G.Valhalla = ns

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "dev"
if ns.version:find("^@") then ns.version = "dev" end   -- (a checkout: the packager fills it in for releases)
ns.ACCENT = "e6b85c"
-- where players send reports (the "Report a problem" button shows it to copy): a new issue on
-- GitHub, with the map-problem form
ns.ISSUES_URL = "https://github.com/Odysseaus/wow-addons/issues/new?title=Valhalla+map+problem&game=" .. ns.Client
ns.Media = { path = "Interface\\AddOns\\" .. ADDON .. "\\Media\\" }
-- the textures are each client's own (Data\<client>\Client.lua, loaded before this, names it)
ns.Media.tex = ns.Media.path .. "Textures\\" .. ns.Client .. "\\"
-- what loading costs (ms): its files, the login, the map's setup and its parts (/valhalla status)
ns.loadMs = { start = debugprofilestop and debugprofilestop(), parts = {} }

-- Translations: ns.L["English text"] gives the text for the player's language once a
-- translation fills it in (none yet), else the English. Place names come from the game.
ns.L = setmetatable({}, { __index = function(_, k) return k end })

function ns:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
	DEFAULT_CHAT_FRAME:AddMessage("|cff" .. ns.ACCENT .. "Valhalla|r: " .. msg)
end

--------------------------------------------------------------------------------
-- Secret-safe reads (clients with secret values, e.g. WoW Forever)
--------------------------------------------------------------------------------

local Safe = {}
ns.Safe = Safe

function Safe.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

function Safe.Value(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- a position's x, y: Blizzard's vectors have GetXY, but some APIs on this client hand back
-- a plain { x, y } table. (1.2.26) each plain, nil when secret, so callers check only for nil
function Safe.XY(vec)
	if type(vec) ~= "table" then return end
	local x, y
	if vec.GetXY then x, y = vec:GetXY() else x, y = vec.x, vec.y end
	return Safe.Value(x), Safe.Value(y)
end

-- a plain number that's neither NaN nor infinite (a view worked out while the map is 0 px across
-- divides by zero: one such view put into the map left it blank, and one such number saved with the
-- settings is text the game can't read back, so the whole file is lost: 1.2.34, OpenMap v0.8.10 #260 #261 #306)
function Safe.Finite(...)
	for i = 1, select("#", ...) do
		local n = select(i, ...)
		if type(n) ~= "number" or Safe.IsSecret(n) or n ~= n or n == math.huge or n == -math.huge then return false end
	end
	return true
end

-- calls fn(...) and returns its first result when it is plain, else nil
function Safe.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok then return nil end
	return Safe.Value(v)
end

--------------------------------------------------------------------------------
-- Events: any number of handlers per event, keyed by owner
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
	for owner, fn in pairs(handlers[event] or {}) do
		local ok, err = pcall(fn, owner, event, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

function ns.RegisterEvent(owner, event, fn)
	if not handlers[event] then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
		handlers[event] = {}
	end
	handlers[event][owner] = fn or owner[event]
	return true
end

function ns.UnregisterEvent(owner, event)
	local list = handlers[event]
	if not list then return end
	list[owner] = nil
	if next(list) == nil then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

--------------------------------------------------------------------------------
-- Modules (Valhalla has one, "worldmap")
--------------------------------------------------------------------------------

ns.modules = {}

function ns:NewModule(key, spec)
	local mod = spec or {}
	mod.key = key
	mod.defaults = mod.defaults or {}
	if mod.defaults.enabled == nil then mod.defaults.enabled = true end
	ns.modules[key] = mod
	return mod
end

function ns:GetModule(key)
	return ns.modules[key]
end

-- missing keys from defaults, recursively
local function Fill(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then
			t[k] = type(v) == "table" and Fill({}, v) or v
		elseif type(v) == "table" and type(t[k]) == "table" then
			Fill(t[k], v)
		end
	end
	return t
end

local function DeepCopy(v, seen)
	if type(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local out = {}
	seen[v] = out
	for k, val in pairs(v) do out[DeepCopy(k, seen)] = DeepCopy(val, seen) end
	return out
end

-- world-map choices that follow the character. Everything else in ValhallaDB.worldmap
-- (pins, sketches, paint, measured flight times, the window's place, diagnostics) stays shared.
local MAP_TOGGLE = {
	autoSwitch = true, hoverHighlight = true, icons = true, boats = true, zeppelins = true,
	flight = true, playerArrow = true, iconsFrom = true, iconScale = true, darkening = true,
	darkenColor = true, routes = true, foundOnly = true, colorMatch = true, desaturate = true,
	unexplored = true, gapFills = true, maxZoom = true, chart = true, padMap = true,
	townsfolkMaster = true, townsfolkMinimap = true, townsfolk = true,
	townsfolkProfMigrated = true, townsfolkClassAll = true, townsfolkSize = true,
	allQuests = true, coords = true, zoneLevels = true, moveFade = true, mapFpsCap = true,
	zoomHidePins = true, questFly = true, questFlySpeed = true, questFlyLanding = true,
	questFlyShort = true, group = true, friends = true, friendsShare = true,
	dungeonBosses = true, dungeonQuests = true, questSource = true, entranceClick = true,
	dungeonCard = true, dungeonLevels = true, dungeonTab = true,
	minimap = true, minimapMix = true, minimapDeep = true, minimapFrom = true,
	cityMinimap = true, soften = true, underground = true, gapMinimap = true,
	minimapButton = true, tabRail = true, mapButtons = true, flightTimer = true,
}

local function MapDB(account, char)
	return setmetatable({}, {
		__index = function(_, k)
			if MAP_TOGGLE[k] then return char[k] end
			return account[k]
		end,
		__newindex = function(_, k, v)
			if MAP_TOGGLE[k] then char[k] = v else account[k] = v end
		end,
	})
end

-- the character's first time: copy the account's toggles. A table that is already
-- there is kept (learned flights, the character's own pins). A second login does not copy again.
local function SeedMapToggles(account, char, defaults)
	if not char.mapSeeded then
		for k, v in pairs(account) do
			if MAP_TOGGLE[k] and char[k] == nil then char[k] = DeepCopy(v) end
		end
		char.mapSeeded = true
	end
	for k, v in pairs(defaults) do
		if MAP_TOGGLE[k] then
			if char[k] == nil then char[k] = DeepCopy(v)
			elseif type(char[k]) == "table" and type(v) == "table" then Fill(char[k], v) end
		end
	end
end

function ns:InitDB()
	ValhallaDB = ValhallaDB or {}
	ValhallaCharDB = ValhallaCharDB or {}
	for key, mod in pairs(ns.modules) do
		mod.fresh = ValhallaDB[key] == nil       -- (no saved settings yet: a new install)
		-- (an old save's settings carried to the keys that replace them, before the defaults fill those)
		if not mod.fresh and mod.Migrate then mod.Migrate(ValhallaDB[key]) end
		ValhallaDB[key] = Fill(ValhallaDB[key] or {}, mod.defaults)
		if key == "worldmap" then
			local absent = ValhallaCharDB[key] == nil
			local char = ValhallaCharDB[key]
			if type(char) ~= "table" then char = {} end
			if absent then ValhallaCharDB[key] = char end
			SeedMapToggles(ValhallaDB[key], char, mod.defaults)
			mod.db, mod.char = MapDB(ValhallaDB[key], char), char
		else
			ValhallaCharDB[key] = ValhallaCharDB[key] or {}
			mod.db, mod.char = ValhallaDB[key], ValhallaCharDB[key]
		end
	end
	-- (1.2.34) and as you log out: a NaN or infinite number in the saved settings is written as text the game
	-- can't read back, and the whole file is lost, every setting back to its default on the next login
	if not ns.scrubOwner then
		ns.scrubOwner = {}
		ns.RegisterEvent(ns.scrubOwner, "PLAYER_LOGOUT", function()
			ns.ScrubSaved(ValhallaDB)
			ns.ScrubSaved(ValhallaCharDB)
			ns.ScrubSaved(ValhallaInvestDB)
		end)
	end
end

-- every number in a saved table (and the tables in it) that isn't finite, removed
function ns.ScrubSaved(t, seen)
	if type(t) ~= "table" then return end
	seen = seen or {}
	if seen[t] then return end
	seen[t] = true
	for k, v in pairs(t) do
		if type(v) == "number" and not Safe.Finite(v) then t[k] = nil
		elseif type(v) == "table" then ns.ScrubSaved(v, seen) end
	end
end

function ns:EnableModules()
	for _, mod in pairs(ns.modules) do
		if mod.db.enabled and not mod.enabled then
			mod.enabled = true
			if mod.OnEnable then
				local ok, err = pcall(mod.OnEnable, mod)
				if not ok then
					mod.enabled = false
					ns:Print("|cffff6060failed to start|r: %s", tostring(err):sub(1, 300))
					geterrorhandler()(err)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Options (AceConfig tables)
--------------------------------------------------------------------------------

-- get / set for options stored in getTable(info)[key]; refresh() after a change
function ns.Bind(getTable, refresh)
	local function get(info)
		local v = getTable(info)[info[#info]]
		if info.type == "color" then
			v = v or { 1, 1, 1, 1 }
			return v[1], v[2], v[3], v[4] or 1
		end
		return v
	end
	local function set(info, a, b, c, d)
		local t = getTable(info)
		if info.type == "color" then
			t[info[#info]] = { a, b, c, d or 1 }
		else
			t[info[#info]] = a
		end
		if refresh then refresh(info) end
	end
	return get, set
end

function ns.Header(name, order)
	return { type = "header", name = name, order = order }
end

function ns.Desc(text, order)
	return { type = "description", name = text, order = order, fontSize = "medium" }
end

--------------------------------------------------------------------------------
-- Look: fonts and a plain dark panel (other addons may restyle these: every
-- panel is frame.omBackdrop, every font goes through ns.Look:Font)
--------------------------------------------------------------------------------

local Look = {}
ns.Look = Look

function Look:Font(fs, size, flags)
	if not fs:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "") then
		fs:SetFontObject(GameFontHighlight)
	end
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

-- a dark backdrop with a thin border behind `frame`; opts: inset, alpha
function Look:Panel(frame, opts)
	opts = opts or {}
	local bd = frame.omBackdrop
	if not bd then
		bd = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		bd:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
		frame.omBackdrop = bd
	end
	local inset = opts.inset or 0
	bd:ClearAllPoints()
	bd:SetPoint("TOPLEFT", -inset, inset)
	bd:SetPoint("BOTTOMRIGHT", inset, -inset)
	bd:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	bd:SetBackdropColor(0.06, 0.06, 0.07, opts.alpha or 0.9)
	bd:SetBackdropBorderColor(0, 0, 0, 1)
	if ns.Style then ns.Style.Panel(bd, opts.alpha or 0.9) end   -- (v0.4.2: the look's panel, UI/Style.lua)
	return bd
end

-- a dropdown list in the game's own menus' look (its dark rounded panel, which WoW Forever edges in
-- bronze: Blizzard_Menu's MenuStyle1, the same offsets), else the plain panel with a bronze edge.
-- Returns the room to leave inside it: left, top, right, bottom
function Look:Dropdown(frame)
	if ns.Style then return ns.Style.Menu(frame) end   -- (v0.4.2: the look's, the same room inside)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-dropdown-bg") then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAtlas("common-dropdown-bg")
		bg:SetPoint("TOPLEFT", -10, 3)
		bg:SetPoint("BOTTOMRIGHT", 10, -3)
		bg:SetAlpha(0.925)
		return 8, 8, 8, 15
	end
	local bd = Look:Panel(frame, { alpha = 0.97 })
	bd:SetBackdropBorderColor(0.66, 0.49, 0.28, 1)
	return 6, 6, 6, 6
end

-- a window in the game's own frame: the map window's metal border (Blizzard's nine-slice without the
-- portrait, which WoW Forever draws in bronze) over its dark rock, a title in its title bar and its
-- close button; else (a client without that layout) the plain panel with a title and a close button.
-- Returns the title bar's height (content starts below it), the title and the close button.
function Look:Window(frame, title, onClose)
	local top = 0
	if ns.Style then
		-- v0.4.2: the look's frame (UI/Style.lua): Profession the same metal nine-slice over the profession
		-- window's background, Norse heavy bronze with corner brackets; without the layout, a plain frame
		top = ns.Style.Frame(frame)
	else
		local util = _G.NineSliceUtil
		local layout = util and util.GetLayout and util.GetLayout("ButtonFrameTemplateNoPortrait") and "ButtonFrameTemplateNoPortrait"
		local ok, nine = false, nil
		if layout then ok, nine = pcall(CreateFrame, "Frame", nil, frame, "NineSlicePanelTemplate") end
		if ok and nine and pcall(util.ApplyLayoutByName, nine, layout) then
			nine:SetAllPoints()
			nine:SetFrameLevel(frame:GetFrameLevel())
			local bg = frame:CreateTexture(nil, "BACKGROUND")
			bg:SetPoint("TOPLEFT", 6, -21)
			bg:SetPoint("BOTTOMRIGHT", -2, 3)
			if bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT") == false then
				bg:SetColorTexture(0.1, 0.09, 0.08, 1)
			end
			bg:SetHorizTile(true)
			bg:SetVertTile(true)
			local shade = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
			shade:SetAllPoints(bg)
			shade:SetColorTexture(0, 0, 0, 0.45)       -- (the rock darkened, so the small print reads)
			top = 21
		else
			Look:Panel(frame, { alpha = 0.96 })
		end
	end
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	if ns.Style then ns.Style.Title(text, 12) end
	text:SetPoint("TOPLEFT", top > 0 and 30 or 12, top > 0 and -4 or -10)
	text:SetPoint("TOPRIGHT", -30, top > 0 and -4 or -10)
	text:SetJustifyH(top > 0 and "CENTER" or "LEFT")
	text:SetWordWrap(false)
	text:SetText(title or "")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetFrameLevel(frame:GetFrameLevel() + 20)
	close:SetHitRectInsets(-4, -4, -4, -4)
	if top > 0 then close:SetPoint("TOPRIGHT", 1, 0) else close:SetPoint("TOPRIGHT", 2, 2) end
	close:SetScript("OnClick", onClose or function() frame:Hide() end)
	return top, text, close
end
