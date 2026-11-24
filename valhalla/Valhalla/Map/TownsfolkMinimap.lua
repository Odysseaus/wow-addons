--------------------------------------------------------------------------------
-- Townsfolk on the minimap (1.2.40). Valhalla's own buttons, parented to Minimap, pooled.
-- The same account-wide master and per-type checkboxes as the world map, plus Minimap
-- (on at first). Only pins inside the minimap's radius are shown. Quest badges from the
-- log, when both are drawn, use a higher frame level. No Blizzard pin is moved.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("worldmap")
local Safe = ns.Safe

-- The client's minimap radii in yards, the sizes the minimap texture has used since classic:
-- outdoor zoom 0 is about 466.67 yards across the radius, indoor starts at 300.
local R_OUT = { [0] = 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 }
local R_IN = { [0] = 300, 240, 180, 120, 80, 50 }

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

local function Radius()
	local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
	zoom = tonumber(zoom) or 0
	if zoom < 0 then zoom = 0 elseif zoom > 5 then zoom = 5 end
	local indoor = IsIndoors and IsIndoors()
	local t = indoor and R_IN or R_OUT
	return t[zoom] or t[0]
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

-- yards across this map, from the same world rectangle and yard table the world map uses.
-- Not from GetWorldPosFromMapPos of the two corners: on this client that width is not the map's.
local function MapSpan(mapID)
	local S = ns.MapStitch
	if not (S and S.Rect and S.ToYards) then return nil, nil, "rejected" end
	local l, r, t, b = S.Rect(mapID)
	if not (type(l) == "number" and type(r) == "number" and r > l and type(b) == "number" and b > t) then
		return nil, nil, "rejected"
	end
	local u, v = (l + r) / 2, (t + b) / 2
	local step = 0.02
	local function yards(uu, vv)
		for _, cont in ipairs({ 0, 1 }) do
			local x, y = S.ToYards(cont, uu, vv)
			if type(x) == "number" and type(y) == "number" then return x, y, cont end
		end
	end
	local x0, y0, cont = yards(u, v)
	if not x0 then return nil, nil, "rejected" end
	local x1, y1 = S.ToYards(cont, u + (r - l) * step, v)
	local x2, y2 = S.ToYards(cont, u, v + (b - t) * step)
	local function stepYards(ax, ay, bx, by)
		if type(ax) ~= "number" or type(bx) ~= "number" or type(ay) ~= "number" or type(by) ~= "number" then return end
		return math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / step
	end
	local spanX, spanY = stepYards(x0, y0, x1, y1), stepYards(x0, y0, x2, y2)
	if not spanX or not spanY or (spanX <= 2 and spanY <= 2) then return nil, nil, "rejected" end
	return spanX, spanY, "rect"
end

local diagNext = 0
local function NoteDiag(mapID, px, py, spanX, spanY, source, pin)
	local now = (GetTime and GetTime()) or 0
	if diagNext == -1 then return end
	if diagNext > 0 and now < diagNext then return end
	diagNext = now > 0 and (now + 3) or -1
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return end
	local log = db.minimapDiag
	if type(log) ~= "table" then log = {} db.minimapDiag = log end
	log[#log + 1] = {
		map = mapID, x = px, y = py,
		spanX = spanX, spanY = spanY, source = source,
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

local function Place(list, poolList, usedList, level)
	for i, p in ipairs(list) do
		local b = usedList[i]
		if not b then b = Button(poolList) usedList[i] = b end
		b:SetParent(Minimap)
		b:SetFrameLevel(level)
		b:SetSize(12, 12)
		if p.look and ns.MapStitch and ns.MapStitch.Look then ns.MapStitch.Look(b.icon, p.look) end
		b.name, b.title = p.name, p.title
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", p.px, p.py)
		b:Show()
	end
	for i = #list + 1, #usedList do
		usedList[i]:Hide()
		poolList[#poolList + 1] = usedList[i]
		usedList[i] = nil
	end
end

local function HideAll()
	Place({}, pool, used, 4)
	Place({}, qpool, qused, 6)
end

function mod:UpdateTownsfolkMinimap()
	if not Minimap or Combat() then return end
	if not (mod.db and mod.db.townsfolkMaster and mod.db.townsfolkMinimap ~= false) then HideAll() return end
	local function Call(fn, ...)
		if Safe and Safe.Call then return Safe.Call(fn, ...) end
		if type(fn) ~= "function" then return end
		local ok, a = pcall(fn, ...)
		if ok then return a end
	end
	-- where you stand on the map, as a fraction. Pins on that same map are drawn from there.
	local mapID = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local pos = mapID and Call(C_Map.GetPlayerMapPosition, mapID, "player")
	if not pos then HideAll() return end
	local rawX, rawY
	if pos.GetXY then rawX, rawY = pos:GetXY() else rawX, rawY = pos.x, pos.y end
	if Secret(rawX) or Secret(rawY) then HideAll() return end
	local px, py = Norm(rawX, rawY)
	if not px then HideAll() return end
	local spanX, spanY, spanSource = MapSpan(mapID)
	local want = {}
	if mod.db.townsfolkMaster then
		for _, k in ipairs(mod.TOWNSFOLK or {}) do if Wanted(k.key) then want[#want + 1] = k.key end end
	end
	local sig = table.concat(want, ",")
	if sig ~= stamp then stamp = sig Rebuild() end
	local radius = Radius()
	local rot = GetCVar and GetCVar("rotateMinimap") == "1"
	local face = 0
	if rot and GetPlayerFacing then
		local f = GetPlayerFacing()
		if type(f) == "number" and not (Safe and Safe.IsSecret and Safe.IsSecret(f)) then face = f end
	end
	local half = (Minimap:GetWidth() or 140) / 2
	local near, qnear = {}, {}
	local function take(src, dest)
		for _, p in ipairs(src) do
			if p.map == mapID then
				-- map x grows east, map y grows south. Screen +y is up.
				local dx, dy = p.x - px, py - p.y
				if spanX then
					dx, dy = dx * spanX, dy * spanY
				else
					-- no real yard width: still place from the map position. A quarter of the map fills the radius.
					dx, dy = dx / 0.25 * radius, dy / 0.25 * radius
				end
				-- facing 0 is north and increases counterclockwise, so a point straight ahead sits above the arrow
				if rot then
					local s, c = math.sin(face), math.cos(face)
					dx, dy = dx * c + dy * s, -dx * s + dy * c
				end
				if dx * dx + dy * dy <= radius * radius then
					p.px = dx / radius * half
					p.py = dy / radius * half
					dest[#dest + 1] = p
				end
			end
		end
	end
	take(points, near)
	-- in-progress quest question marks are not drawn here. The world map has those.
	Place(near, pool, used, 4)
	Place({}, qpool, qused, 6)
	NoteDiag(mapID, px, py, spanX, spanY, spanSource, near[1])
end

local function Boot()
	if frame or not Minimap or Combat() then return end
	frame = CreateFrame("Frame", nil, Minimap)
	frame:SetScript("OnUpdate", function(_, dt)
		frame.t = (frame.t or 0) + dt
		if frame.t < 0.2 then return end
		frame.t = 0
		if mod.UpdateTownsfolkMinimap then mod:UpdateTownsfolkMinimap() end
	end)
end
if CreateFrame then
	local w = CreateFrame("Frame")
	w:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then Boot() end
	end)
	if w.RegisterEvent then
		w:RegisterEvent("PLAYER_LOGIN")
		w:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	Boot()
end
