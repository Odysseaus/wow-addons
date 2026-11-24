--------------------------------------------------------------------------------
-- Townsfolk on the minimap (1.2.40). Valhalla's own buttons, parented to Minimap, pooled.
-- The same account-wide master and per-type checkboxes as the world map, plus Minimap
-- (on at first). Only pins inside the minimap's radius are shown. No Blizzard pin is moved.
--
-- (1.2.45) placed the way the game's own hybrid minimap places its map (Blizzard_HybridMinimap.lua):
-- the minimap's map (C_Minimap.GetUiMapID), that map's size in yards (C_Map.GetMapWorldSize), the
-- minimap's radius in yards (C_Minimap.GetViewRadius, read again on MINIMAP_UPDATE_ZOOM), and moved
-- every frame, so a pin stays on its spot as you walk. The list of pins near you is rebuilt every 0.5 s.
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

local function Rebuild()
	local data = ns.TownsfolkData
	local list = {}
	if type(data) == "table" and type(data.records) == "table" and mod.db and mod.db.townsfolkMaster and mod.db.townsfolkMinimap ~= false then
		for _, r in ipairs(data.records) do
			if Wanted(r.type) and Kept(r) then
				local x, y = Norm(r.x, r.y)
				if x and r.map then
					list[#list + 1] = { map = r.map, x = x, y = y, name = r.name, title = r.title, look = LookFor(r.type, r.icon) }
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
				for _, p in ipairs(points) do if p.map == mapID then pts[#pts + 1] = p end end
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
		if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then Boot() end
	end)
	if w.RegisterEvent then
		w:RegisterEvent("PLAYER_LOGIN")
		w:RegisterEvent("PLAYER_REGEN_ENABLED")
		pcall(w.RegisterEvent, w, "MINIMAP_UPDATE_ZOOM")
	end
	Boot()
end
