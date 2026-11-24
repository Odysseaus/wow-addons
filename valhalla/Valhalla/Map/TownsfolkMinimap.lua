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

local function World(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
	if not (type(mapID) == "number" and type(x) == "number" and type(y) == "number") then return end
	if x > 1 then x, y = x / 100, y / 100 end
	local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not (ok and type(cont) == "number" and type(world) == "table") then return end
	local wx, wy
	if world.GetXY then wx, wy = world:GetXY() else wx, wy = world.x, world.y end
	if type(wx) ~= "number" or type(wy) ~= "number" then return end
	if Safe and Safe.IsSecret and (Safe.IsSecret(wx) or Safe.IsSecret(wy) or Safe.IsSecret(cont)) then return end
	return cont, wx, wy
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

-- the same people the world map draws: your faction, and only your own class's trainers
local function Kept(r)
	local fac = (UnitFactionGroup and UnitFactionGroup("player") == "Horde") and "H" or "A"
	local f = r.faction or "AH"
	if type(f) == "string" and not f:find(fac, 1, true) then return false end
	if r.type ~= "classTrainer" then return true end
	local _, token = UnitClass and UnitClass("player")
	local classes = mod.TOWNSFOLK_CLASSES
	local mine = token and classes and classes[token]
	if type(mine) ~= "string" then return false end
	local title = (r.title or ""):lower()
	local best, bestName = 0, nil
	for _, n in pairs(classes) do
		if type(n) == "string" then
			local ln = n:lower()
			if title:find(ln, 1, true) and #ln > best then best, bestName = #ln, n end
		end
	end
	return bestName ~= nil and bestName:lower() == mine:lower()
end

local function Rebuild()
	local data = ns.TownsfolkData
	local list = {}
	if type(data) == "table" and type(data.records) == "table" and mod.db and mod.db.townsfolkMaster and mod.db.townsfolkMinimap ~= false then
		for _, r in ipairs(data.records) do
			if Wanted(r.type) and Kept(r) then
				local cont, wx, wy = World(r.map, r.x, r.y)
				if cont then
					list[#list + 1] = { cont = cont, wx = wx, wy = wy, name = r.name, title = r.title, look = LookFor(r.type, r.icon) }
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
	local mapID = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	local pos = mapID and Call(C_Map.GetPlayerMapPosition, mapID, "player")
	if not pos then HideAll() return end
	local px, py
	if pos.GetXY then px, py = pos:GetXY() else px, py = pos.x, pos.y end
	if type(px) ~= "number" or type(py) ~= "number" then HideAll() return end
	if Safe and Safe.IsSecret and (Safe.IsSecret(px) or Safe.IsSecret(py)) then HideAll() return end
	local cont, wx, wy = World(mapID, px, py)
	if not cont then HideAll() return end
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
			if p.cont == cont then
				local dx, dy = p.wx - wx, p.wy - wy
				if rot then
					local ang = math.atan2(dx, dy) - face
					local hyp = math.sqrt(dx * dx + dy * dy)
					dx, dy = math.sin(ang) * hyp, math.cos(ang) * hyp
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
	quests = {}
	for _, q in ipairs(mod.liveQuests or {}) do
		local c, qx, qy = World(q.map, q.x, q.y)
		if c then
			quests[#quests + 1] = {
				cont = c, wx = qx, wy = qy, name = q.complete and "Ready to turn in" or "Quest", title = "",
				look = { texture = q.complete and "Interface\\GossipFrame\\ActiveQuestIcon" or "Interface\\GossipFrame\\IncompleteQuestIcon" },
			}
		end
	end
	take(quests, qnear)
	Place(near, pool, used, 4)
	Place(qnear, qpool, qused, 6)
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
