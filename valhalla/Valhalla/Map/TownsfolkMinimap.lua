--------------------------------------------------------------------------------
-- Townsfolk on the minimap (1.2.40). Valhalla's own buttons, parented to Minimap, pooled.
-- The same account-wide master and per-type checkboxes as the world map, plus Minimap
-- (on at first). Only pins inside the minimap's radius are shown. No Blizzard pin is moved.
--
-- (1.2.45) placed the way the game's own hybrid minimap places its map (Blizzard_HybridMinimap.lua):
-- the minimap's map (C_Minimap.GetUiMapID), that map's size in yards (C_Map.GetMapWorldSize), the
-- minimap's radius in yards (C_Minimap.GetViewRadius, read again on MINIMAP_UPDATE_ZOOM), and moved
-- every frame, so a pin stays on its spot as you walk. The list of pins near you is rebuilt every 0.5 s.
--
-- (1.2.46) the types the game's own minimap tracking already shows (food, reagents, repair, inns, banks,
-- mailboxes, auctioneers, stable masters, class and profession trainers) are never drawn here: their
-- checkboxes read and set the game's tracking (C_Minimap) instead. A client without that tracking keeps
-- Valhalla's own pins for them.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("worldmap")
local Safe = ns.Safe

local REBUILD = 0.5             -- seconds between rebuilds of the minimap's map and its pins

local frame
local pool, used = {}, {}
local qpool, qused = {}, {}
local points = {}          -- { wx, wy, name, title, look } rebuilt when the checkboxes change
local quests = {}
local stamp = ""

local function Combat()
	if InCombatLockdown and InCombatLockdown() then return true end
	if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
	local C = ns.Combat
	return C and C.Blocked and C.Blocked() or false
end

local function LookFor(kind, icon)
	if icon == "repair" and mod.REPAIR_LOOK then return mod.REPAIR_LOOK end
	for _, k in ipairs(mod.TOWNSFOLK or {}) do
		if k.key == kind then return k.look end
	end
end

local function Wanted(key)
	local db = mod.db
	if not db or not db.townsfolkMaster or db.townsfolkMinimap == false then return false end
	return db.townsfolk and db.townsfolk[key] and true or false
end

-- the same people the world map draws: your faction, and every class
local function Kept(r)
	local fac = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
	local f = r.faction or "AH"
	if type(f) == "string" and not f:find(fac, 1, true) then return false end
	return true
end

local function Secret(v)
	return Safe and Safe.IsSecret and Safe.IsSecret(v) or false
end

-- 0-100 records and 0-1 map positions, both as a fraction of the map
local function Norm(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then return end
	if x > 1 or y > 1 then x, y = x / 100, y / 100 end
	return x, y
end

-- a call's first results, each plain (nil for a secret), nil when it errors (Util.Call: both of
-- GetMapWorldSize's numbers, not only the first)
local function Call(fn, ...)
	local U = ns.Util
	if U and U.Call then return U.Call(fn, ...) end
	if type(fn) ~= "function" then return end
	local ok, a, b = pcall(fn, ...)
	if not ok then return end
	if Secret(a) then a = nil end
	if Secret(b) then b = nil end
	return a, b
end

-- a plain positive number (not secret, not NaN or infinite), else nil
local function Plain(v)
	if type(v) ~= "number" or Secret(v) or v ~= v or v <= 0 or v == math.huge then return end
	return v
end

-- the minimap's radius in yards, as the game's hybrid minimap reads it
local radius, radiusSource
local function ReadRadius()
	local r = C_Minimap and C_Minimap.GetViewRadius and Plain(Call(C_Minimap.GetViewRadius))
	radius, radiusSource = r, r and "view" or "none"
end

-- a map's width and height in yards
local function WorldSize(mapID)
	if not (mapID and C_Map and C_Map.GetMapWorldSize) then return end
	local w, h = Call(C_Map.GetMapWorldSize, mapID)
	w, h = Plain(w), Plain(h)
	if w and h then return w, h end
end

local diagNext = 0
local function NoteDiag(cur, px, py, pin)
	local now = (GetTime and GetTime()) or 0
	if diagNext == -1 then return end
	if diagNext > 0 and now < diagNext then return end
	diagNext = now > 0 and (now + 3) or -1
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local log = db.minimapDiag
	if type(log) ~= "table" then log = {} db.minimapDiag = log end
	log[#log + 1] = {
		map = cur.map, mapSource = cur.mapSource, x = px, y = py,
		spanX = cur.w, spanY = cur.h, source = "worldsize",
		radius = radius, radiusSource = radiusSource, width = Minimap.GetWidth and Minimap:GetWidth() or nil,
		pinX = pin and pin.px, pinY = pin and pin.py, pinMap = pin and pin.map,
	}
	while #log > 20 do table.remove(log, 1) end
end

-- (1.2.46) the game's own minimap tracking. Valhalla type -> the game's filter (Enum.MinimapTrackingFilter,
-- with this client's values: MinimapConstantsDocumentation.lua). profTrainer: the profession records that
-- are trainers (a supplier's title says Supplies, Vendor, Merchant or Goods; those stay Valhalla's).
local GAME = {
	food = { "VenderFood", 16 }, reagent = { "VendorReagent", 256 }, repair = { "Repair", 512 },
	innkeeper = { "Innkeeper", 32 }, banker = { "Banker", 2 }, mailbox = { "Mailbox", 64 },
	auctioneer = { "Auctioneer", 1 }, stable = { "Stablemaster", 2048 },
	classTrainer = { "TrainerClass", 8388608 }, profTrainer = { "TrainerProfession", 128 },
}
mod.GAME_TRACKING = GAME
local SUPPLIER = { "Suppl", "Vendor", "Merchant", "Goods" }

function mod.IsProfessionSupplier(title)
	title = type(title) == "string" and title or ""
	for _, w in ipairs(SUPPLIER) do if title:find(w, 1, true) then return true end end
	return false
end

-- the game type a townsfolk record is, or nil (Valhalla's alone)
function mod.TownsfolkGameKey(r)
	local kind = r and r.type
	if not kind then return end
	if GAME[kind] and kind ~= "profTrainer" then return kind end
	if kind == "vendor" and r.icon == "repair" then return "repair" end
	for _, p in ipairs(mod.PROFESSIONS or {}) do
		if p == kind then return (not mod.IsProfessionSupplier(r.title)) and "profTrainer" or nil end
	end
end

local function FilterID(key)
	local g = GAME[key]
	local E = Enum and Enum.MinimapTrackingFilter
	return E and E[g[1]] or g[2]
end

-- key -> the game's tracking index. Kept once the game has given its list (it has none until its
-- tracking events: Minimap.lua), asked again after MINIMAP_UPDATE_TRACKING and SPELLS_CHANGED.
local indexOf
local function TrackingAPI()
	return C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter and C_Minimap.GetTrackingInfo
		and C_Minimap.SetTracking and true or false
end
local function Indexes()
	if indexOf then return indexOf end
	local t, any = {}, false
	if TrackingAPI() then
		local n = Call(C_Minimap.GetNumTrackingTypes)
		local byFilter = {}
		for i = 1, (type(n) == "number" and n or 0) do
			local f = Call(C_Minimap.GetTrackingFilter, i)
			local id = type(f) == "table" and f.filterID
			if type(id) == "number" and not Secret(id) then byFilter[id] = i end
		end
		for key in pairs(GAME) do
			t[key] = byFilter[FilterID(key)]
			if t[key] then any = true end
		end
	end
	if any then indexOf = t end
	return t
end

-- the game's tracking index when the game's minimap shows this type, else nil
function mod.GameTracked(key)
	if not GAME[key] then return end
	return Indexes()[key]
end

-- whether the game's minimap tracks this type now; nil: not the game's (Valhalla's own checkbox)
function mod.GameTrackingOn(key)
	local i = mod.GameTracked(key)
	if not i then return end
	local info = Call(C_Minimap.GetTrackingInfo, i)
	local on = type(info) == "table" and info.active
	if on == nil or Secret(on) then return end
	return on and true or false
end

-- the game's tracking for this type on or off (C_Minimap.SetTracking, as its tracking menu sets it). Not
-- protected (MinimapDocumentation.lua), but it is held by CombatQueue's gate like Valhalla's other calls
-- into the game's UI state. false: not the game's.
function mod.SetGameTracking(key, on)
	if not mod.GameTracked(key) then return false end
	local function Set()
		local i = mod.GameTracked(key)
		if i then pcall(C_Minimap.SetTracking, i, on and true or false) end
	end
	local C = ns.Combat
	if C and C.Run then C.Run("tracking." .. key, Set, ns.L["Minimap tracking changed in combat: it applies when combat ends."])
	elseif not Combat() then Set() end
	return true
end

-- what the game's tracking list is, for the next reload (ValhallaDB.minimapTrackingDiag)
local function NoteTracking()
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local d = { api = TrackingAPI(), clock = date and date("%Y-%m-%d %H:%M:%S") or nil, entries = {}, mapping = {} }
	if d.api then
		local n = Call(C_Minimap.GetNumTrackingTypes)
		for i = 1, (type(n) == "number" and n or 0) do
			local info = Call(C_Minimap.GetTrackingInfo, i)
			local f = Call(C_Minimap.GetTrackingFilter, i)
			local e = { index = i }
			if type(info) == "table" then
				e.name = not Secret(info.name) and info.name or nil
				e.active = not Secret(info.active) and info.active or nil
				e.type = not Secret(info.type) and info.type or nil
				e.subType = not Secret(info.subType) and info.subType or nil
			end
			if type(f) == "table" then e.filter = not Secret(f.filterID) and f.filterID or nil end
			d.entries[#d.entries + 1] = e
		end
	end
	for key in pairs(GAME) do
		d.mapping[key] = { filter = FilterID(key), index = mod.GameTracked(key) or false, active = mod.GameTrackingOn(key) }
	end
	db.minimapTrackingDiag = d
end

-- the game's tracking changed (its menu, or ours): the checkboxes follow it. The same checkbox governs the
-- type's world map pins, so those follow too.
local function SyncFromGame()
	indexOf = nil
	local db = mod.db
	if db and type(db.townsfolk) == "table" then
		local changed = false
		for key in pairs(GAME) do
			local on = mod.GameTrackingOn(key)
			if on ~= nil and key ~= "profTrainer" and (db.townsfolk[key] and true or false) ~= on then
				db.townsfolk[key] = on
				changed = true
			end
		end
		if changed and mod.RefreshTownsfolk then mod:RefreshTownsfolk() end
		if mod.RefreshPanel then pcall(mod.RefreshPanel, mod) end
	end
	NoteTracking()
end
mod.SyncGameTracking = SyncFromGame

local function Rebuild()
	local data = ns.TownsfolkData
	local list = {}
	if type(data) == "table" and type(data.records) == "table" and mod.db and mod.db.townsfolkMaster and mod.db.townsfolkMinimap ~= false then
		for _, r in ipairs(data.records) do
			if Wanted(r.type) and Kept(r) then
				local x, y = Norm(r.x, r.y)
				if x and r.map then
					list[#list + 1] = { map = r.map, x = x, y = y, name = r.name, title = r.title, look = LookFor(r.type, r.icon),
						game = mod.TownsfolkGameKey(r) }
				end
			end
		end
	end
	points = list
end

local function Button(poolList)
	local b = table.remove(poolList)
	if b then return b end
	b = CreateFrame("Button", nil, Minimap)
	b:SetSize(12, 12)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b:SetScript("OnEnter", function(self)
		if Combat() or not GameTooltip or not self.name then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.name, 1, 0.82, 0)
		if self.title and self.title ~= "" then GameTooltip:AddLine(self.title, 1, 1, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip_Hide then GameTooltip_Hide() end end)
	return b
end

-- the buttons for a list of points (p.px, p.py: offsets from the minimap's centre). A button is set up
-- (parent, level, picture) only when it gets a new point; every frame only its offset changes.
local function Place(list, poolList, usedList, level)
	for i, p in ipairs(list) do
		local b = usedList[i]
		if not b then b = Button(poolList) usedList[i] = b end
		if b.p ~= p then
			b.p = p
			b:SetParent(Minimap)
			b:SetFrameLevel(level)
			b:SetSize(12, 12)
			if p.look and ns.MapStitch and ns.MapStitch.Look then ns.MapStitch.Look(b.icon, p.look) end
			b.name, b.title = p.name, p.title
		end
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", p.px, p.py)
		b:Show()
	end
	for i = #list + 1, #usedList do
		usedList[i]:Hide()
		usedList[i].p = nil
		poolList[#poolList + 1] = usedList[i]
		usedList[i] = nil
	end
end

local function HideAll()
	Place({}, pool, used, 4)
	Place({}, qpool, qused, 6)
end

-- the minimap's map and the pins on it, rebuilt every REBUILD seconds (and when a setting changes).
-- The minimap's own map first; when no pin is on it, the map the game says you're on.
local cur                       -- { map, mapSource, w, h, pts }
local function Refresh()
	cur = nil
	if not (mod.db and mod.db.townsfolkMaster and mod.db.townsfolkMinimap ~= false) then return end
	local want = {}
	for _, k in ipairs(mod.TOWNSFOLK or {}) do if Wanted(k.key) then want[#want + 1] = k.key end end
	local sig = table.concat(want, ",")
	if sig ~= stamp then stamp = sig Rebuild() end
	if not radius then ReadRadius() end
	local mini = C_Minimap and C_Minimap.GetUiMapID and Call(C_Minimap.GetUiMapID)
	local best = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local fallback
	for _, c in ipairs({ { mini, "minimap" }, { best, "best" } }) do
		local mapID = c[1]
		if type(mapID) == "number" and not Secret(mapID) then
			local w, h = WorldSize(mapID)
			if w then
				local pts = {}
				for _, p in ipairs(points) do
					-- (the game's minimap draws this type itself: never a second pin)
					if p.map == mapID and not (p.game and mod.GameTracked(p.game)) then pts[#pts + 1] = p end
				end
				local entry = { map = mapID, mapSource = c[2], w = w, h = h, pts = pts }
				if #pts > 0 then cur = entry return end
				fallback = fallback or entry
			end
		end
	end
	cur = fallback
end

-- every frame: where you stand on that map, and each pin's offset from the arrow in minimap pixels
local function Position()
	if not Minimap then return end
	if Combat() then HideAll() return end
	if not (cur and radius) or #cur.pts == 0 then HideAll() return end
	local pos = Call(C_Map.GetPlayerMapPosition, cur.map, "player")
	if not pos then HideAll() return end
	local rawX, rawY
	if pos.GetXY then rawX, rawY = pos:GetXY() else rawX, rawY = pos.x, pos.y end
	if Secret(rawX) or Secret(rawY) then HideAll() return end
	local px, py = Norm(rawX, rawY)
	if not px then HideAll() return end
	local rot = GetCVar and GetCVar("rotateMinimap") == "1"
	local face = 0
	if rot and GetPlayerFacing then
		local f = GetPlayerFacing()
		if type(f) == "number" and not Secret(f) then face = f end
	end
	local s, c = math.sin(face), math.cos(face)
	local half = (Minimap:GetWidth() or 140) / 2
	local perYard = half / radius   -- (= Minimap:GetWidth() / (2 * the view radius))
	local near = {}
	for _, p in ipairs(cur.pts) do
		-- map x grows east, map y grows south. Screen +y is up.
		local dx, dy = (p.x - px) * cur.w, (py - p.y) * cur.h
		-- facing 0 is north and increases counterclockwise, so a point straight ahead sits above the arrow
		if rot then dx, dy = dx * c + dy * s, -dx * s + dy * c end
		if dx * dx + dy * dy <= radius * radius then
			p.px, p.py = dx * perYard, dy * perYard
			near[#near + 1] = p
		end
	end
	Place(near, pool, used, 4)
	-- in-progress quest question marks are not drawn here. The world map has those.
	Place({}, qpool, qused, 6)
	NoteDiag(cur, px, py, near[1])
end

-- a full update now (a setting changed, the quest log changed)
function mod:UpdateTownsfolkMinimap()
	if not Minimap or Combat() then return end
	if not (mod.db and mod.db.townsfolkMaster and mod.db.townsfolkMinimap ~= false) then cur = nil HideAll() return end
	Refresh()
	Position()
end

local function Boot()
	if frame or not Minimap or Combat() then return end
	frame = CreateFrame("Frame", nil, Minimap)
	frame.t = REBUILD
	frame:SetScript("OnUpdate", function(_, dt)
		frame.t = (frame.t or 0) + (dt or 0)
		if frame.t >= REBUILD then
			frame.t = 0
			if Combat() then HideAll() return end
			ReadRadius()
			Refresh()
		end
		Position()
	end)
end
if CreateFrame then
	local w = CreateFrame("Frame")
	w:SetScript("OnEvent", function(_, event)
		if event == "MINIMAP_UPDATE_ZOOM" then ReadRadius() return end
		if event == "MINIMAP_UPDATE_TRACKING" or event == "SPELLS_CHANGED" then SyncFromGame() return end
		if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then Boot() end
		if event == "PLAYER_LOGIN" then SyncFromGame() end
	end)
	if w.RegisterEvent then
		w:RegisterEvent("PLAYER_LOGIN")
		w:RegisterEvent("PLAYER_REGEN_ENABLED")
		pcall(w.RegisterEvent, w, "MINIMAP_UPDATE_ZOOM")
		pcall(w.RegisterEvent, w, "MINIMAP_UPDATE_TRACKING")
		pcall(w.RegisterEvent, w, "SPELLS_CHANGED")
	end
	Boot()
end
