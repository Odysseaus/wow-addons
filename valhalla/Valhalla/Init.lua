--------------------------------------------------------------------------------
-- Init: loaded last. Settings at ADDON_LOADED; the map, options and slash
-- commands at PLAYER_LOGIN.
--
--   /valhalla (/vh)        options
--   /valhalla status         what the map is doing
--   /valhalla notes          map notes (paint areas, say what's there, export them)
--   /valhalla debug          the debug overlay (frame rate, frame times, what Valhalla costs)
--   /valhalla bench [zoom]   times the map at several zooms, each part off in turn (Bench.lua)
--   /valhalla pins           the map pins (Pins.lua)
--   /valhalla news           what's new in this version (News.lua)
--   /valhalla draw           the quill: draw on the map (Sketch.lua)
--   /valhalla dungeons       which map each dungeon entrance opens (Dungeons.lua)
--   /valhalla entrance <name>  where you stand, as a dungeon entrance for tools/map-data (Dungeons.lua)
--   /valhalla highlights     where the game draws each zone's highlight, for tools/map-preview (Debug.lua)
--   /valhalla objectives on|off|why [questID]  the All Objectives tracker by zone, Ready to Turn In, pins (Objectives/Objectives.lua)
--------------------------------------------------------------------------------

local ADDON, ns = ...
if ns.loadMs.start then ns.loadMs.files = debugprofilestop() - ns.loadMs.start end

local function Options()
	local mod = ns:GetModule("worldmap")
	local args = mod.Options and mod:Options() or {}
	args.enabled = { type = "toggle", name = ns.L["Enable Valhalla"], order = 0, width = "full",
		desc = ns.L["Turning Valhalla off takes a reload."],
		get = function() return mod.db.enabled end,
		set = function(_, v) mod.db.enabled = v; ns:Print(ns.L["Takes effect after a /reload."]) end }
	local objectives = ns:GetModule("objectives")
	if objectives then
		args.objectives = { type = "toggle", name = ns.L["Objectives: zone quests, Ready to Turn In and pins"], order = 0.2, width = "full",
			desc = ns.L["The game's All Objectives tracker lists this zone's quests (lowest level first), a Ready to Turn In section and a pin per quest. Off: the game's own tracking. Also /valhalla objectives on|off."],
			get = function() return objectives.db.enabled end,
			set = function(_, v) objectives.O.SetOn(v) end }
	end
	args.padWaits = { type = "description", order = 0.5, fontSize = "medium",
		name = function() return "|cffff8040" .. mod.PadOffText() .. "|r" end,
		hidden = function() return not mod.padWaits end }
	return { type = "group", name = "|cff" .. ns.ACCENT .. "Valhalla|r " .. ns.version, args = args }
end

-- Valhalla's settings are the map's own menu (Panel.lua); with the map off (no menu), the options window,
-- which can turn it back on
local function OpenOptions()
	local mod = ns:GetModule("worldmap")
	if mod.enabled and mod.OpenMenu and mod:OpenMenu() then return end
	local ACD = LibStub("AceConfigDialog-3.0", true)
	if ACD then ACD:Open("Valhalla") end
end
ns.OpenOptions = OpenOptions

local function Slash(msg)
	local raw = (msg or ""):match("^%s*(.-)%s*$")
	msg = raw:lower()
	local mod = ns:GetModule("worldmap")
	local word, rest = msg:match("^(%S+)%s+(.+)$")
	-- /valhalla objectives [on|off] (also /vh obj): the zone quests, Ready to Turn In and pins (Objectives/Objectives.lua)
	local objWord, objArg = msg:match("^(%S+)%s*(.-)$")
	if objWord == "objectives" or objWord == "obj" then
		local objectives = ns:GetModule("objectives")
		if objectives then objectives:Slash(objArg) end
		return
	end
	local takes = { bench = true, entrance = true }  -- (/valhalla bench 16: at that zoom; /valhalla entrance Dire Maul - East)
	if takes[word] then msg, rest = word, raw:match("^%S+%s+(.+)$") end
	local run = {
		status = "Diag", paint = "TogglePaint", notes = "TogglePaint", debug = "ToggleDebugOverlay",
		bench = "Bench", pins = "TogglePins", news = "ToggleNews", entrance = "Entrance", draw = "ToggleSketch", dungeons = "DungeonDiag",
		welcome = "ShowWelcome", highlights = "Highlights", warm = "ToggleWarm",
		reset = "ResetWindow",   -- (reset: the windowed map's size and place, for one off the screen)
	}
	if run[msg] then
		if mod.enabled and mod[run[msg]] then mod[run[msg]](mod, takes[msg] and rest or nil)
		elseif mod.padWaits then ns:Print(mod.PadOffText())
		else ns:Print(ns.L["The map is off."]) end
	else
		OpenOptions()
	end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		ns:InitDB()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		local t0 = debugprofilestop and debugprofilestop()
		ns:EnableModules()
		if t0 then ns.loadMs.login = debugprofilestop() - t0 end
		local AC = LibStub("AceConfig-3.0", true)
		if AC then AC:RegisterOptionsTable("Valhalla", Options) end
		-- a page in Blizzard's settings that opens the options window
		if Settings and Settings.RegisterCanvasLayoutCategory then
			local panel = CreateFrame("Frame")
			local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
			title:SetPoint("TOPLEFT", 16, -16)
			title:SetText("|cff" .. ns.ACCENT .. "Open|rMap")
			local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			button:SetSize(180, 26)
			button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
			button:SetText(ns.L["Open Valhalla's settings"])
			button:SetScript("OnClick", function()
				if SettingsPanel then HideUIPanel(SettingsPanel) end
				OpenOptions()
			end)
			Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "Valhalla"))
		end
		SLASH_VALHALLA1, SLASH_VALHALLA2 = "/valhalla", "/vh"
		SlashCmdList.VALHALLA = Slash
		self:UnregisterEvent("PLAYER_LOGIN")
	end
end)

function ns.NotifyOptions()
	local ACR = LibStub("AceConfigRegistry-3.0", true)
	if ACR then ACR:NotifyChange("Valhalla") end
end
