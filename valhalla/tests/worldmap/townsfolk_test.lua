-- Box tests for Data/Forever/Townsfolk.lua and Map/Townsfolk.lua (1.2.39). Lua 5.1.
-- Run: lua5.1 valhalla/tests/worldmap/townsfolk_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
	if cond then pass = pass + 1 print("PASS  " .. name)
	else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

-- maps Valhalla already draws (the same files the generator matches zone names against)
local known = {}
for _, file in ipairs({ "Data/Forever/Levels.lua", "Data/Forever/Fishing.lua", "Data/Forever/Banners.lua" }) do
	local text = assert(io.open(root .. file)):read("*a")
	for id in text:gmatch("%[(%d+)%]") do known[tonumber(id)] = true end
end

---------------------------------------------------------------------------
print("== 1. the Forever file: finite coordinates, on a map Valhalla draws")
local ns = {}
assert(loadfile(root .. "Data/Forever/Townsfolk.lua"))("Valhalla", ns)
local data = ns.TownsfolkData
ok(type(data) == "table" and type(data.records) == "table" and #data.records > 0, "Townsfolk.lua loads records", data and data.records and #data.records)
local types = {}
local bad = 0
for _, r in ipairs(data.records or {}) do
	types[r.type] = (types[r.type] or 0) + 1
	local x, y = r.x, r.y
	if type(r.id) ~= "number" or type(r.map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then bad = bad + 1
	elseif x ~= x or y ~= y or x < 0 or x > 100 or y < 0 or y > 100 then bad = bad + 1
	elseif not known[r.map] then bad = bad + 1 end
	if r.x == nil or r.y == nil then bad = bad + 1 end
end
ok(bad == 0, "every record has a finite x, y on a known map", bad)
ok(types.innkeeper and types.innkeeper > 0 and types.mailbox and types.mailbox > 0, "inns and mailboxes are both present", (types.innkeeper or 0) .. " inns, " .. (types.mailbox or 0) .. " mailboxes")
ok(types.vendor and types.classTrainer and types.tailoring and types.blacksmithing, "vendors, class trainers and professions are present")
local saw5153, saw1346, supplyVendor, weaponRepair = false, false, false, false
for _, r in ipairs(data.records) do
	if r.id == 5153 and r.type == "tailoring" and r.map == 1455 then saw5153 = true end
	if r.id == 1346 and r.type == "tailoring" and r.map == 1453 then saw1346 = true end
	if r.title and r.title:find("Blacksmithing Suppl", 1, true) and r.type == "vendor" then supplyVendor = true end
	if r.title == "Weapon Merchant" and not (r.type == "vendor" and r.icon == "repair") then weaponRepair = true end
end
ok(saw5153 and saw1346, "Ironforge tailor 5153 and Stormwind tailor 1346 are present")
ok(not supplyVendor, "blacksmithing supplies are not general vendors")
ok(not weaponRepair, "a weapon merchant stays a vendor and uses the repair icon")

---------------------------------------------------------------------------
print("== 2. pins: a checkbox off adds none; a built set is not built again")
bit = { band = function(a, b) local n, m = 1, 0 while a > 0 or b > 0 do if a % 2 == 1 and b % 2 == 1 then m = m + n end a = math.floor(a / 2) b = math.floor(b / 2) n = n * 2 end return m end,
	bor = function(a, b) local n, m = 1, 0 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then m = m + n end a = math.floor(a / 2) b = math.floor(b / 2) n = n * 2 end return m end }
local added = 0
local sets = {}
local S = {
	IsBuilt = function() return true end,
	PinSet = function(key) local s = sets[key] or { key = key, on = true, pins = 0 } sets[key] = s return s end,
	GetPinSet = function(key) return sets[key] end,
	SetPinSetOn = function(set, on) set.on = on and true or false end,
	ClearPinSet = function(set) set.pins = 0 set.cleared = (set.cleared or 0) + 1 end,
	Rect = function(id) if known[id] then return 0, 1, 0, 1 end end,
	AddPin = function(set) set.pins = set.pins + 1 added = added + 1 return { SetScript = function() end } end,
}
local mod = { defaults = {}, db = {} }
function ns:GetModule() return mod end
ns.MapStitch = S
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.printed = {}
function ns:Print(s) ns.printed[#ns.printed + 1] = s end
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Mage", "MAGE" end
C_Timer = { After = function(_, fn) fn() end }
CreateFrame = function()
	return {
		CreateTexture = function() return { SetTexture = function() return true end, SetAllPoints = function() end, SetPoint = function() end, SetSize = function() end, Show = function() end } end,
		Hide = function() end, Show = function() end, SetScript = function() end, RegisterEvent = function() end,
	}
end
C_Texture = { GetAtlasInfo = function() return nil end }
ValhallaDB = {}
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end }
function GameTooltip_Hide() end
MINIMAP_TRACKING_MAILBOX = "Mailbox"
LEVEL = "Level"
local saved = ns.TownsfolkData
assert(loadfile(root .. "Map/Townsfolk.lua"))("Valhalla", ns)
ok(mod.HasTownsfolk() == true, "the built-in data counts as a townsfolk database, with no Questie")
-- a record with no coordinates is not installed
local before = #ns.TownsfolkData.records
mod.InstallTownsfolkData({ records = { { id = 1, name = "Nowhere", title = "Innkeeper", faction = "A", type = "innkeeper" } } })
ok(mod.HasTownsfolk() == true, "a no-spawn record does not remove the database")
ns.TownsfolkData = saved
mod.InstallTownsfolkData(saved)
mod.db = { townsfolkMaster = false, townsfolk = {} }
for _, k in ipairs(mod.TOWNSFOLK) do mod.db.townsfolk[k.key] = false end
mod.db.townsfolk.innkeeper = true
added = 0
mod:RefreshTownsfolk()
ok(added == 0, "master off: an enabled type still creates no pins", added)
mod.db.townsfolkMaster = true
mod.db.townsfolk.vendor = false
mod:RefreshTownsfolk()
local inns = added
ok(inns > 0 and (not sets.tf_vendor or sets.tf_vendor.pins == 0), "innkeepers on, vendors off: only the inn pins are created", inns)
local again = added
mod:RefreshTownsfolk()
ok(added == again, "already built: a second refresh does not create the pins again", added - again)
mod.db.townsfolk.innkeeper = false
mod:RefreshTownsfolk()
ok(sets.tf_innkeeper and sets.tf_innkeeper.on == false and added == again, "checkbox off: the set is hidden and not rebuilt")
ok(type(ValhallaDB.townsfolkIcons) == "table" and ValhallaDB.townsfolkIcons["Interface\\Minimap\\Tracking\\Innkeeper"] == true,
	"an icon path that loaded is recorded on ValhallaDB", ValhallaDB.townsfolkIcons and ValhallaDB.townsfolkIcons["Interface\\Minimap\\Tracking\\Innkeeper"])
added = 0
mod.InstallTownsfolkData({ records = {
	{ id = 9, name = "No Spawn", title = "Innkeeper", faction = "A", type = "innkeeper" },
	{ id = 10, name = "Has Spawn", title = "Innkeeper", faction = "A", type = "innkeeper", map = 1453, x = 50, y = 50 },
} })
mod.db.townsfolkMaster = true
mod.db.townsfolk.innkeeper = true
mod:RefreshTownsfolk()
ok(added == 1, "a record with no coordinates is omitted; the one with a spawn is kept", added)

print("== 3. (1.2.40) size, profession migration, minimap cull, host-map quests")
local innSize, rareSize
for _, k in ipairs(mod.TOWNSFOLK) do
	if k.key == "innkeeper" then innSize = k.look.size end
	if k.key == "rare" then rareSize = k.look.size end
end
ok(innSize == 22 and rareSize == 18, "townsfolk pins match the flight master (22); rares stay 18", tostring(innSize) .. " " .. tostring(rareSize))
mod.db = { townsfolk = { profTrainer = true }, townsfolkMaster = false }
mod.MigrateTownsfolk()
local migrated = true
for _, key in ipairs(mod.PROFESSIONS) do if mod.db.townsfolk[key] ~= true then migrated = false end end
ok(migrated and mod.db.townsfolk.profTrainer == true and mod.db.townsfolkProfMigrated == true, "profTrainer on turns all twelve professions on once and keeps the old key")

print("== 4. (1.2.41) every class trainer; (1.2.43) profession pictures, no mask")
function UnitClass() return "Warlock", "WARLOCK" end
function UnitFactionGroup() return "Alliance" end
mod.db.townsfolkMaster = true
for _, k in ipairs(mod.TOWNSFOLK) do mod.db.townsfolk[k.key] = false end
mod.db.townsfolk.classTrainer = true
local shaped, sized, fallback, noMask = 0, true, true, true
for _, k in ipairs(mod.TOWNSFOLK) do
	if k.look and k.look.square then
		shaped = shaped + 1
		if k.look.mask then noMask = false end
		if k.look.size ~= 22 then sized = false end
		if k.look.fallback ~= "Interface\\Minimap\\Tracking\\Profession" then fallback = false end
		if not k.look.texture:find("Media\\Townsfolk\\" .. k.key .. ".tga", 1, true) then shaped = -100 end
		if not k.look.square:find("Interface\\Icons\\", 1, true) then shaped = -100 end
	end
end
local shipped = 0
for _ in pairs(mod.TOWNSFOLK_ART) do shipped = shipped + 1 end
ok(shaped == 12 and shipped == 12 and sized and fallback and noMask,
	"twelve shipped pictures: shaped file, square icon, Profession fallback, no mask", shaped)
added = 0
mod.InstallTownsfolkData({ records = {
	{ id = 1901, name = "Kelstrum", title = "Warrior Trainer", faction = "A", type = "classTrainer", trainerTag = "WARRIOR", map = 1455, x = 67, y = 88 },
	{ id = 5171, name = "Thistleheart", title = "Warlock Trainer", faction = "A", type = "classTrainer", trainerTag = "WARLOCK", map = 1455, x = 51, y = 8 },
	{ id = 6382, name = "Jubahl", title = "Demon Trainer", faction = "A", type = "classTrainer", trainerTag = "WARLOCK", map = 1455, x = 53, y = 7 },
	{ id = 2489, name = "Milstaff", title = "Portal Trainer", faction = "A", type = "classTrainer", trainerTag = "MAGE", map = 1455, x = 26, y = 8 },
	{ id = 10090, name = "Belia", title = "Pet Trainer", faction = "A", type = "classTrainer", trainerTag = "HUNTER", map = 1455, x = 70, y = 85 },
	{ id = 3324, name = "Grol'dar", title = "Warlock Trainer", faction = "H", type = "classTrainer", trainerTag = "WARLOCK", map = 1454, x = 48, y = 45 },
} })
ok(added == 5, "every Alliance class trainer is drawn, including pet, portal and demon; the Horde one is not", added)
local drawn = added
mod.db.townsfolkClassAll = nil
mod.MigrateTownsfolk()
mod:RefreshTownsfolk()
ok(added == drawn + 5, "clearing the old class set once draws every class again", added - drawn)
local function Gate(fn)
	local prev = CreateFrame
	CreateFrame = function(...)
		local f = prev(...)
		local make = f.CreateTexture
		f.CreateTexture = function(...)
			local t = make(...)
			t.SetTexture = function(self, path) self._path = path return fn(path, self) end
			t.GetWidth = function(self) return self._w or 0 end
			t.GetHeight = function(self) return self._h or self._w or 0 end
			return t
		end
		return f
	end
	return function() CreateFrame = prev end
end
local tailorLook
for _, k in ipairs(mod.TOWNSFOLK) do if k.key == "tailoring" then tailorLook = k.look end end
for _, k in ipairs(mod.TOWNSFOLK) do mod.db.townsfolk[k.key] = false end
mod.db.townsfolk.tailoring = true
ValhallaDB.townsfolkIcons["Interface\\Icons\\Trade_Tailoring"] = "mask"
local restore = Gate(function(path, tex)
	-- this client says every path loaded. A missing picture still has no size.
	if path:find("Media\\Townsfolk\\", 1, true) then tex._w, tex._h = 0, 0 else tex._w, tex._h = 64, 64 end
	return true
end)
added = 0
mod.InstallTownsfolkData({ records = {
	{ id = 5153, name = "Jormund", title = "Expert Tailor", faction = "A", type = "tailoring", map = 1455, x = 43, y = 29 },
} })
restore()
ok(added == 1, "tailoring on: the tailor pin is created", added)
local noted = ValhallaDB.townsfolkIcons[tailorLook.texture]
ok(type(noted) == "table" and noted.path == tailorLook.square and noted.width == 64,
	"SetTexture true but width 0: the square icon is what was used", noted and noted.path)
ok(ValhallaDB.townsfolkIcons["Interface\\Icons\\Trade_Tailoring"] == nil, "a stale mask entry is dropped")
local smith
for _, k in ipairs(mod.TOWNSFOLK) do if k.key == "blacksmithing" then smith = k.look end end
mod.db.townsfolk.tailoring = false
mod.db.townsfolk.blacksmithing = true
restore = Gate(function(path, tex)
	tex._w, tex._h = path:find("Media\\Townsfolk\\", 1, true) and 128 or 64, path:find("Media\\Townsfolk\\", 1, true) and 128 or 64
	return true
end)
mod.InstallTownsfolkData({ records = {
	{ id = 2, name = "Smith", title = "Expert Blacksmith", faction = "A", type = "blacksmithing", map = 1455, x = 40, y = 30 },
} })
restore()
noted = ValhallaDB.townsfolkIcons[smith.texture]
ok(type(noted) == "table" and noted.path == smith.texture and noted.width == 128,
	"shaped file with a real size: that file is what was used", noted and noted.width)
local eng
for _, k in ipairs(mod.TOWNSFOLK) do if k.key == "engineering" then eng = k.look end end
mod.db.townsfolk.blacksmithing = false
mod.db.townsfolk.engineering = true
restore = Gate(function(path, tex)
	tex._w, tex._h = 32, 32
	if path:find("Media\\Townsfolk\\", 1, true) or path:find("Interface\\Icons\\", 1, true) then return false end
	return true
end)
mod.InstallTownsfolkData({ records = {
	{ id = 3, name = "Eng", title = "Expert Engineer", faction = "A", type = "engineering", map = 1455, x = 40, y = 30 },
} })
restore()
noted = ValhallaDB.townsfolkIcons[eng.texture]
ok(type(noted) == "table" and noted.path == eng.fallback, "square icon missing too: the Profession symbol is what was used",
	noted and noted.path)

---------------------------------------------------------------------------
print("== 5. (1.2.45) the minimap: the game's view radius and map size, moved every frame")
local secretX = false
ns.Safe = { Call = function(fn, ...) return fn(...) end, IsSecret = function(v) return secretX and v == "SECRET" end }
local clock = 100
function GetTime() return clock end
Minimap = { GetWidth = function() return 140 end, GetZoom = function() return 0 end }
function GetCVar(n) return "0" end
function IsIndoors() return false end
local miniMapID, viewR = 1453, 200
C_Minimap = { GetUiMapID = function() return miniMapID end, GetViewRadius = function() return viewR end }
C_Map = C_Map or {}
function C_Map.GetBestMapForUnit() return 1453 end
function C_Map.GetMapWorldSize(id) if id == 1453 then return 1000, 800 end return 0, 0 end
local playerMX, playerMY = 0.5, 0.5
function C_Map.GetPlayerMapPosition()
	local x = secretX and "SECRET" or playerMX
	return { x = x, y = playerMY, GetXY = function() return x, playerMY end }
end
-- frames that keep their scripts, their offset and whether they are shown
local mm = { frames = {}, onUpdate = nil, onEvent = nil, events = {} }
local function Shown()
	local list = {}
	for _, f in ipairs(mm.frames) do if f._shown and f._x then list[#list + 1] = f end end
	return list
end
CreateFrame = function(kind, name, parent)
	local f = { _scripts = {} }
	function f:SetScript(n, fn) self._scripts[n] = fn if n == "OnUpdate" then mm.onUpdate = fn elseif n == "OnEvent" then mm.onEvent = fn end end
	function f:RegisterEvent(e) mm.events[e] = true end
	function f:CreateTexture() return { SetAllPoints = function() end, SetTexture = function() return true end } end
	function f:SetParent(p) self._parent = p end
	function f:SetFrameLevel(n) self._level = n end
	function f:SetSize() end
	function f:ClearAllPoints() end
	function f:SetPoint(_, rel, _, x, y) self._rel, self._x, self._y = rel, x, y end
	function f:Show() self._shown = true end
	function f:Hide() self._shown = false end
	mm.frames[#mm.frames + 1] = f
	return f
end
local mmCreate = CreateFrame
S.Look = function() end
local function Frame(dt) mm.onUpdate(nil, dt or 0.016) end
assert(loadfile(root .. "Map/TownsfolkMinimap.lua"))("Valhalla", ns)
ok(type(mm.onUpdate) == "function" and mm.events.MINIMAP_UPDATE_ZOOM, "an every-frame updater on the minimap, and the zoom event is watched")
ns.TownsfolkData = { records = {
	{ id = 1, name = "Near", title = "Innkeeper", faction = "AH", type = "innkeeper", map = 1453, x = 51, y = 50 },
	{ id = 2, name = "Far", title = "Innkeeper", faction = "AH", type = "innkeeper", map = 1453, x = 100, y = 100 },
} }
mod.db.townsfolkMaster = true
mod.db.townsfolkMinimap = true
for k in pairs(mod.db.townsfolk) do mod.db.townsfolk[k] = false end
mod.db.townsfolk.innkeeper = true
mod.liveQuests = { { map = 1453, x = 0.5, y = 0.5, complete = false, id = 7 } }
mod:UpdateTownsfolkMinimap()
local on = Shown()
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
-- 0.01 of a 1000-yard map = 10 yards east; 140 px across a 200-yard radius: 70/200 px a yard = 3.5 px
ok(#on == 1 and on[1]._rel == Minimap and on[1]._level == 4, "the near innkeeper is drawn on the minimap; the far one is outside the radius; no quest mark", #on)
ok(on[1] and near(on[1]._x, 3.5) and near(on[1]._y, 0), "10 yards east at a 200-yard view radius on a 140 px minimap is 3.5 px right", on[1] and on[1]._x)
local diag = ValhallaDB.minimapDiag and ValhallaDB.minimapDiag[#ValhallaDB.minimapDiag]
ok(type(diag) == "table" and diag.map == 1453 and diag.mapSource == "minimap" and diag.source == "worldsize"
	and diag.spanX == 1000 and diag.spanY == 800 and diag.radius == 200 and diag.radiusSource == "view" and near(diag.pinX, 3.5),
	"the sample saved for the next reload has the map, its yards, the view radius and its source", diag and diag.radiusSource)
-- every frame, not every 0.2 s: one frame after a step the pin is already back on its spot
local pin = on[1]
playerMX = 0.505
Frame(0.016)
ok(near(pin._x, 1.75), "one frame after a 5-yard step east the pin is 5 yards closer (moved that same frame)", pin._x)
local fixed = true
for i = 1, 40 do
	playerMX, playerMY = 0.5 + i * 0.0002, 0.5 - i * 0.0001
	Frame(0.016)
	local groundX = pin._x + (playerMX - 0.5) * 1000 * 0.35
	local groundY = pin._y + (0.5 - playerMY) * 800 * 0.35
	if not (near(groundX, 3.5) and near(groundY, 0)) then fixed = false end
end
ok(fixed, "walking for 40 frames: pin offset plus your own movement is the same spot every frame (it stays on the ground)")
playerMX, playerMY = 0.5, 0.5
Frame(0.016)
-- the minimap's zoom: read again on the game's event, used on the next frame
viewR = 100
Frame(0.016)
ok(near(pin._x, 3.5), "the radius is not re-read every frame", pin._x)
mm.onEvent(nil, "MINIMAP_UPDATE_ZOOM")
Frame(0.016)
ok(near(pin._x, 7), "after MINIMAP_UPDATE_ZOOM a 100-yard radius puts the same pin twice as far out", pin._x)
viewR = 200
mm.onEvent(nil, "MINIMAP_UPDATE_ZOOM")
-- the pin list is rebuilt every 0.5 s: a checkbox change shows up then
mod.db.townsfolk.innkeeper = false
Frame(0.1)
ok(#Shown() == 1, "between rebuilds the same pins are moved, not rebuilt", #Shown())
Frame(0.5)
ok(#Shown() == 0, "the 0.5 s rebuild drops a type whose checkbox was turned off", #Shown())
mod.db.townsfolk.innkeeper = true
Frame(0.5)
ok(#Shown() == 1, "and brings it back when turned on again", #Shown())
-- the minimap's map has no pins (or no size): the map the game says you're on
miniMapID = 9999
clock = clock + 10
Frame(0.5)
diag = ValhallaDB.minimapDiag[#ValhallaDB.minimapDiag]
ok(#Shown() == 1 and diag.mapSource == "best" and diag.map == 1453, "a minimap map with no pins falls back to the best map", diag.mapSource)
miniMapID = 1453
Frame(0.5)
-- walking east and north: the pin goes the other way
ns.TownsfolkData = { records = {
	{ id = 3, name = "East", title = "Innkeeper", faction = "AH", type = "innkeeper", map = 1453, x = 70, y = 50 },
} }
mod.db.townsfolk.vendor = true
mod:UpdateTownsfolkMinimap()
mod.db.townsfolk.vendor = false
mod:UpdateTownsfolkMinimap()
pin = Shown()[1]
local eastX = pin and pin._x
playerMX = 0.6
Frame(0.016)
ok(type(eastX) == "number" and pin._x < eastX, "walking east moves the pin the other way", tostring(eastX) .. " -> " .. tostring(pin and pin._x))
playerMX, playerMY = 0.6, 0.6
Frame(0.016)
local northY = pin._y
playerMY = 0.55
Frame(0.016)
ok(pin._y < northY, "walking north moves the pin down", tostring(northY) .. " -> " .. tostring(pin._y))
-- rotating minimap: facing east, a pin to the east is straight ahead
playerMX, playerMY = 0.5, 0.5
function GetCVar(n) return n == "rotateMinimap" and "1" or "0" end
function GetPlayerFacing() return -math.pi / 2 end
Frame(0.016)
ok(near(pin._y, 200 * 0.35) and math.abs(pin._x) < 1e-6, "facing east, a pin 200 yards east sits straight above the arrow", tostring(pin._x) .. "," .. tostring(pin._y))
function GetCVar() return "0" end
Frame(0.016)
-- combat: hidden, back after
function InCombatLockdown() return true end
Frame(0.016)
ok(#Shown() == 0, "in combat the minimap pins are hidden, not left behind", #Shown())
function InCombatLockdown() return false end
Frame(0.5)
ok(#Shown() == 1, "out of combat they come back", #Shown())
-- a secret position: nothing drawn
secretX = true
Frame(0.016)
ok(#Shown() == 0, "a secret player position draws nothing")
secretX = false
Frame(0.016)
-- no view radius from the game: nothing drawn, no guessed table
C_Minimap.GetViewRadius = nil
mm.onEvent(nil, "MINIMAP_UPDATE_ZOOM")
Frame(0.016)
ok(#Shown() == 0, "without the game's view radius nothing is drawn (no radius table)", #Shown())
C_Minimap.GetViewRadius = function() return viewR end
mm.onEvent(nil, "MINIMAP_UPDATE_ZOOM")
Frame(0.016)
ok(#Shown() == 1, "with it again, the pin is back", #Shown())
mod.db.townsfolkMinimap = false
mod:UpdateTownsfolkMinimap()
ok(#Shown() == 0, "minimap checkbox off draws nothing")
mod.db.townsfolkMinimap = true
ns.TownsfolkData = { records = {
	{ id = 9, name = "Tailor", title = "Expert Tailor", faction = "AH", type = "tailoring", map = 1453, x = 51, y = 50 },
} }
for k in pairs(mod.db.townsfolk) do mod.db.townsfolk[k] = false end
mod.db.townsfolk.tailoring = true
mod:UpdateTownsfolkMinimap()
local tailorOn = #Shown()
mod.db.townsfolk.tailoring = false
mod:UpdateTownsfolkMinimap()
ok(tailorOn == 1 and #Shown() == 0, "the profession checkbox shows the minimap pin, and off hides it", tailorOn)
local mmSrc = assert(io.open(root .. "Map/TownsfolkMinimap.lua")):read("*a")
ok(not mmSrc:find("R_OUT", 1, true) and not mmSrc:find("466.6667", 1, true) and not mmSrc:find("MapSpan", 1, true)
	and mmSrc:find("C_Minimap.GetViewRadius", 1, true) and mmSrc:find("C_Map.GetMapWorldSize", 1, true),
	"no hand-made radius table or Stitch span left; the game's view radius and map size are used")

---------------------------------------------------------------------------
print("== 6. (1.2.45) quest icons: the Objectives tracker's own button, styled as the tracker styles it")
function InCombatLockdown() return false end
Enum = Enum or { UIMapType = { Continent = 2, Zone = 3 } }
function C_Map.GetMapChildrenInfo() return { { mapID = 1453 }, { mapID = 1429 } } end
function C_Map.GetMapInfo() return { mapType = 3 } end
GameTooltip.SetText = function() end
local completeQ = { [42] = true }
C_QuestLog = {
	GetQuestsOnMap = function(id)
		if id == 1453 then return { { questID = 42, x = 0.2, y = 0.3 } } end
		if id == 1429 then return { { questID = 43, x = 0.4, y = 0.4 } } end
		return {}
	end,
	IsComplete = function(id) return completeQ[id] or false end,
}
local superQ = 43
C_SuperTrack = { GetSuperTrackedQuestID = function() return superQ end }
mod.HostMap = function() return 1453 end
mod.IsStitched = function() return true end
mod.PadWaits = function() return false end
mod.ToWorld = function(_, x, y) return x, y end
mod.db.allQuests = true
S.iconScale = 2
-- a pooled pin set, as Stitch's: a cleared pin is reused
local qset = { pins = {}, pool = {} }
S.PinSet = function() return qset end
S.ClearPinSet = function(set) for _, p in ipairs(set.pins) do p._shown = false set.pool[#set.pool + 1] = p end set.pins = {} end
S.SetPinSetOn = function(set, on) set.on = on end
local looks = {}
S.AddPin = function(set, u, v, look, data)
	looks[#looks + 1] = look
	local pin = table.remove(set.pool) or {
		_scripts = {},
		SetScript = function(self, n, fn) self._scripts[n] = fn end,
		SetScale = function(self, k) self._scale = k end,
		SetSize = function(self, w) self._size = w end,
		Hide = function(self) self._shown = false end,
		Icon = { SetAlpha = function(self, a) self.a = a end },
		Highlight = { SetAlpha = function(self, a) self.a = a end },
	}
	pin.u, pin.v, pin.data, pin._shown = u, v, data, true
	set.pins[#set.pins + 1] = pin
	return pin
end
local noTemplate = false
local made = 0
CreateFrame = function(kind, name, parent, template)
	local f = { _scripts = {}, SetScript = function(self, n, fn) self._scripts[n] = fn end, RegisterEvent = function() end,
		Hide = function() end, Show = function() end }
	if (template == "ObjectiveTrackerPOIButtonTemplate" or template == "POIButtonTemplate") and not noTemplate then
		made = made + 1
		f._template, f._parent, f._styled = template, parent, 0
		f.SetQuestID = function(self, q) self._q = q end
		f.SetStyle = function(self, st) self._style = st end
		f.SetSelected = function(self, v) self._selected = v end
		f.UpdateButtonStyle = function(self) self._styled = self._styled + 1 end
		f.EnableMouse = function(self, on) self._mouse = on end
		f.ClearAllPoints = function() end
		f.SetPoint = function(self, p, rel) self._anchor = rel end
		f.Show = function(self) self._shown = true end
		f.HighlightTexture = { SetShown = function(self, on) self.on = on end }
	end
	return f
end
POIButtonUtil = { Style = { QuestInProgress = 2, QuestComplete = 3 }, GetStyle = function(id) return completeQ[id] and 3 or 2 end }
ns.Util = nil
assert(loadfile(root .. "UI/Parts.lua"))("Valhalla", ns)
assert(loadfile(root .. "Map/Quests.lua"))("Valhalla", ns)
mod:RefreshQuests()
local byQ = {}
for _, p in ipairs(qset.pins) do if p.poi then byQ[p.poi._q] = p end end
ok(#qset.pins == 2 and byQ[42] and byQ[43], "a quest on the host map and one in the next zone are both drawn", #qset.pins)
ok(byQ[42] and byQ[42].poi._template == "ObjectiveTrackerPOIButtonTemplate" and byQ[42].poi._parent == byQ[42] and byQ[42].poi._anchor == byQ[42],
	"each icon is Valhalla's own ObjectiveTrackerPOIButtonTemplate button, on the pin")
ok(byQ[42] and byQ[42].poi._style == 3 and byQ[43].poi._style == 2, "complete and in progress: the style POIButtonUtil.GetStyle gives (as the map and log)",
	tostring(byQ[42] and byQ[42].poi._style) .. " " .. tostring(byQ[43] and byQ[43].poi._style))
ok(byQ[43] and byQ[43].poi._selected == true and byQ[42].poi._selected == false, "the super-tracked quest's button is selected (the game's glow)")
ok(byQ[42] and byQ[42].poi._styled == 1 and byQ[43].poi._styled == 1, "UpdateButtonStyle paints each once")
ok(byQ[42] and byQ[42]._scale == 1 and byQ[42]._size == 20 and byQ[42].Icon.a == 0 and byQ[42].Highlight.a == 0 and byQ[42].poi._mouse == false,
	"the pin is 20 px at scale 1, its own picture hidden, and the mouse stays on the pin")
local anyArt = false
for _, l in ipairs(looks) do if l.atlas or l.texture then anyArt = true end end
ok(not anyArt, "no atlas or texture of Valhalla's own is given to a quest pin")
byQ[43]._scripts.OnEnter(byQ[43])
ok(byQ[43].poi.HighlightTexture.on == true, "hover shows the button's own highlight")
byQ[43]._scripts.OnLeave(byQ[43])
ok(byQ[43].poi.HighlightTexture.on == false, "leaving hides it")
-- super-tracking moves: the pooled buttons are restyled, a new button is not made
superQ = 42
local before = made
mod:RefreshQuests()
byQ = {}
for _, p in ipairs(qset.pins) do if p.poi then byQ[p.poi._q] = p end end
ok(made == before and byQ[42] and byQ[42].poi._selected == true and byQ[43].poi._selected == false,
	"after super-tracking changes, the same buttons are restyled (selected moves)", made - before)
before = made
mod:RefreshQuests()
local right = 0
for _, p in ipairs(qset.pins) do
	local q = p.poi and p.poi._q
	if q and p.data.id == q and p.poi._style == (completeQ[q] and 3 or 2) and p.poi._selected == (q == superQ) then right = right + 1 end
end
ok(made == before and right == 2, "a pooled pin given another quest is repainted for that quest", right)
local qSrc = assert(io.open(root .. "Map/Quests.lua")):read("*a")
ok(not qSrc:find("QuestBang", 1, true) and not qSrc:find("GossipFrame", 1, true) and not qSrc:find("MeasureQuestPoi", 1, true)
	and not qSrc:find("questPoi", 1, true) and not qSrc:find("SetFrameLevel", 1, true) and not qSrc:find("layoutIndex", 1, true),
	"no measuring, no QuestBang or Gossip fallback, no frame level or layout writes")
-- (1.2.46) a click is the game's own POIButtonMixin.OnClick on the pin's button
local gameClicks = {}
POIButtonMixin = { OnClick = function(self, button) gameClicks[#gameClicks + 1] = { self = self, button = button } end }
local glided, flew, details = 0, 0, 0
S.GlideToWorld = function() glided = glided + 1 end
mod.QuestIconClick = function() flew = flew + 1 return true end
QuestMapFrame_ShowQuestDetails = function() details = details + 1 end
ns.Combat = nil
ValhallaDB.questClickDiag = nil
byQ = {}
for _, p in ipairs(qset.pins) do if p.poi then byQ[p.data.id] = p end end
byQ[43].OnClick(byQ[43])
ok(#gameClicks == 1 and gameClicks[1].self == byQ[43].poi and gameClicks[1].button == "LeftButton",
	"a click runs the game's POIButtonMixin.OnClick on our button, left button")
ok(glided == 0 and flew == 0 and details == 0, "the view does not move and no details open", glided .. flew .. details)
local cd = ValhallaDB.questClickDiag and ValhallaDB.questClickDiag[1]
ok(cd and cd.quest == 43 and cd.how == "now" and cd.ok == true and cd.before == 42, "the click is logged to questClickDiag",
	cd and (tostring(cd.quest) .. " " .. tostring(cd.ok) .. " " .. tostring(cd.before) .. " " .. tostring(cd.err)))
-- the gate closed (combat): the game's click waits and runs when it opens
local queued
ns.Combat = { Run = function(key, fn) if key == "supertrack" then queued = fn return false end end }
byQ[42].OnClick(byQ[42])
ok(#gameClicks == 1 and queued and ValhallaDB.questClickDiag[2].how == "waiting", "in combat the click waits (CombatQueue)")
queued()
ok(#gameClicks == 2 and gameClicks[2].self == byQ[42].poi and ValhallaDB.questClickDiag[3].how == "queued", "and runs once the gate opens")
ns.Combat = { Run = function(key, fn) fn() return true end }
byQ[42].OnClick(byQ[42])
ok(#gameClicks == 3 and ValhallaDB.questClickDiag[4].how == "now", "an open gate: at once, logged as now")
ns.Combat = nil
mod.QuestIconClick = nil
-- a client without the template: no quest icons (not a look that isn't the log's)
noTemplate = true
qset.pins, qset.pool = {}, {}
assert(loadfile(root .. "Map/Quests.lua"))("Valhalla", ns)
mod:RefreshQuests()
local visible = 0
for _, p in ipairs(qset.pins) do if p._shown then visible = visible + 1 end end
mod:RefreshQuests()
ok(visible == 0 and qset.on == false, "no POI button template: nothing is drawn, and the quest set is off", visible)
noTemplate = false

print("== 7. (1.2.45) Parts.PaintQuestPoi: restyled only when the quest, style or selection changed")
local b = ns.Parts.QuestPoi({})
ok(b and b.native and b.template == "ObjectiveTrackerPOIButtonTemplate", "Parts.QuestPoi: the tracker's template first")
ns.Parts.PaintQuestPoi(b, 5, 2, false)
ns.Parts.PaintQuestPoi(b, 5, 2, false)
ok(b._styled == 1 and b._q == 5, "the same paint twice: one UpdateButtonStyle", b._styled)
ns.Parts.PaintQuestPoi(b, 5, 3, false)
ns.Parts.PaintQuestPoi(b, 5, 3, true)
ns.Parts.PaintQuestPoi(b, 6, 3, true)
ok(b._styled == 4 and b._q == 6 and b._style == 3 and b._selected == true, "style, selection and quest changes each restyle", b._styled)

print("== 8. (1.2.46) the game's own minimap tracking: never a second pin, the checkbox is the game's")
CreateFrame = mmCreate
-- every record is the game's type or Valhalla's; professions split into trainers and suppliers
local tdata = {}
assert(loadfile(root .. "Data/Forever/Townsfolk.lua"))("Valhalla", tdata)
local profs = {}
for _, k in ipairs(mod.PROFESSIONS) do profs[k] = true end
local trainers, suppliers = 0, 0
for _, r in ipairs(tdata.TownsfolkData.records) do
	if profs[r.type] then
		if mod.TownsfolkGameKey(r) == "profTrainer" then trainers = trainers + 1 else suppliers = suppliers + 1 end
	end
end
ok(trainers > 200 and suppliers > 150, "profession records: trainers are the game's type, suppliers stay Valhalla's", trainers .. "/" .. suppliers)
ok(mod.TownsfolkGameKey({ type = "tailoring", title = "Expert Tailor" }) == "profTrainer"
	and mod.TownsfolkGameKey({ type = "tailoring", title = "Tailoring Supplies" }) == nil
	and mod.TownsfolkGameKey({ type = "innkeeper" }) == "innkeeper"
	and mod.TownsfolkGameKey({ type = "vendor", icon = "repair" }) == "repair"
	and mod.TownsfolkGameKey({ type = "vendor" }) == nil
	and mod.TownsfolkGameKey({ type = "spirit" }) == nil and mod.TownsfolkGameKey({ type = "rare" }) == nil
	and mod.TownsfolkGameKey({ type = "classTrainer" }) == "classTrainer" and mod.TownsfolkGameKey({ type = "food" }) == "food",
	"the type table: inns, repair (and repair vendors), class and profession trainers, food are the game's; vendors, suppliers, spirits, rares are not")
-- the game's tracking list (this client's filter values)
local track = {
	{ name = "Innkeeper", filterID = 32, active = true },
	{ name = "Profession Trainer", filterID = 128, active = false },
	{ name = "Flight Master", filterID = 8, active = true },
	{ name = "Food & Drink", filterID = 16, active = true },
}
local setCalls = {}
C_Minimap.GetNumTrackingTypes = function() return #track end
C_Minimap.GetTrackingFilter = function(i) return track[i] and { filterID = track[i].filterID } end
C_Minimap.GetTrackingInfo = function(i) local t = track[i] return t and { name = t.name, active = t.active, type = "townsfolk", subType = 0 } end
C_Minimap.SetTracking = function(i, on) setCalls[#setCalls + 1] = { i, on } track[i].active = on end
mod.db.townsfolkMaster, mod.db.townsfolkMinimap = true, true
for k in pairs(mod.db.townsfolk) do mod.db.townsfolk[k] = false end
local refreshed = 0
mod.RefreshTownsfolk = function() refreshed = refreshed + 1 end
mm.onEvent(nil, "MINIMAP_UPDATE_TRACKING")
ok(mod.db.townsfolk.innkeeper == true and mod.db.townsfolk.food == true and refreshed == 1,
	"MINIMAP_UPDATE_TRACKING: the checkboxes take the game's state, the world map is refreshed", tostring(mod.db.townsfolk.innkeeper))
local td = ValhallaDB.minimapTrackingDiag
ok(td and td.api == true and #td.entries == 4 and td.entries[1].name == "Innkeeper" and td.entries[1].filter == 32 and td.entries[1].active == true
	and td.mapping.innkeeper.index == 1 and td.mapping.profTrainer.index == 2 and td.mapping.banker.index == false and td.mapping.banker.filter == 2,
	"minimapTrackingDiag: the game's entries, names, filters, active, and the type mapping")
ok(mod.GameTrackingOn("innkeeper") == true and mod.GameTrackingOn("profTrainer") == false and mod.GameTrackingOn("banker") == nil
	and mod.GameTrackingOn("vendor") == nil, "the game's state per type; nil for a type the game doesn't track")
-- the minimap: no second innkeeper, no trainer; suppliers, vendors and the game-less types stay
ns.TownsfolkData = { records = {
	{ id = 1, name = "Inn", title = "Innkeeper", faction = "AH", type = "innkeeper", map = 1453, x = 51, y = 50 },
	{ id = 2, name = "Bank", title = "Banker", faction = "AH", type = "banker", map = 1453, x = 51, y = 51 },
	{ id = 3, name = "Tailor", title = "Expert Tailor", faction = "AH", type = "tailoring", map = 1453, x = 50, y = 51 },
	{ id = 4, name = "Cloth", title = "Tailoring Supplies", faction = "AH", type = "tailoring", map = 1453, x = 49, y = 50 },
	{ id = 5, name = "Goods", title = "General Goods", faction = "AH", type = "vendor", map = 1453, x = 50, y = 49 },
} }
mod.db.townsfolk.banker, mod.db.townsfolk.tailoring, mod.db.townsfolk.vendor = true, true, true
playerMX, playerMY = 0.5, 0.5
mod:UpdateTownsfolkMinimap()
local names = {}
for _, f in ipairs(Shown()) do names[#names + 1] = f.name end
table.sort(names)
ok(table.concat(names, ",") == "Bank,Cloth,Goods", "drawn: the banker (no game entry), the supplier and the vendor; not the game's innkeeper or trainer",
	table.concat(names, ","))
-- the checkbox sets the game's tracking (out of the gate: at once; held while it's closed)
ns.Combat = nil
ok(mod.SetGameTracking("innkeeper", false) == true and setCalls[1] and setCalls[1][1] == 1 and setCalls[1][2] == false,
	"turning the innkeeper tick off calls C_Minimap.SetTracking(its index, false)")
ok(mod.SetGameTracking("vendor", true) == false and #setCalls == 1, "a type the game doesn't track: not the game's call")
local held
ns.Combat = { Run = function(key, fn) held = { key, fn } return false end }
mod.SetGameTracking("innkeeper", true)
ok(#setCalls == 1 and held and held[1] == "tracking.innkeeper", "in combat the game's tracking change waits in CombatQueue")
held[2]()
ok(#setCalls == 2 and setCalls[2][2] == true, "and is made when the gate opens")
ns.Combat = nil
-- the menu's checkbox (Panel.lua's folk row, as written)
local panelSrc = assert(io.open(root .. "Map/Panel.lua")):read("*a")
local fa = panelSrc:find("\tlocal function folk(label, key)", 1, true)
local fb = fa and panelSrc:find("\n\tend\n", fa, true)
local folk
if fa and fb then
	local chunk = "local db, row, kinds, mod, Icon = ...\n" .. panelSrc:sub(fa, fb + 5) .. "\nreturn folk"
	folk = assert(loadstring(chunk))(mod.db, function(label, id, icon, get, set) return { label, get, set, id = id } end, {}, mod,
		function() return {} end)
end
local innRow, vendorRow = folk and folk("Innkeepers", "innkeeper"), folk and folk("Vendors", "vendor")
track[1].active = true
mod.db.townsfolk.innkeeper = false
ok(innRow and innRow[2]() == true, "the innkeeper tick shows the game's tracking, not Valhalla's saved value")
innRow[3](false)
ok(track[1].active == false and mod.db.townsfolk.innkeeper == false, "unticking it turns the game's innkeeper tracking off (and the world map's pins with it)")
mod.db.townsfolk.vendor = false
ok(vendorRow and vendorRow[2]() == false and (vendorRow[3](true) or true) and mod.db.townsfolk.vendor == true and #setCalls == 3,
	"a Valhalla-only type keeps Valhalla's own tick", #setCalls)
-- no tracking API: Valhalla's own control and pins, as before
C_Minimap.GetNumTrackingTypes = nil
mm.onEvent(nil, "MINIMAP_UPDATE_TRACKING")
mod.db.townsfolk.innkeeper = true
ok(mod.GameTracked("innkeeper") == nil and innRow[2]() == true and ValhallaDB.minimapTrackingDiag.api == false,
	"without the game's tracking API: the tick is Valhalla's again")
mod:UpdateTownsfolkMinimap()
names = {}
for _, f in ipairs(Shown()) do names[#names + 1] = f.name end
table.sort(names)
ok(table.concat(names, ","):find("Inn", 1, true) ~= nil, "and the innkeeper pin is Valhalla's again", table.concat(names, ","))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
