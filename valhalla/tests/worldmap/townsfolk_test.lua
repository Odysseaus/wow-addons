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
ok(shaped == 12 and sized and fallback and noMask, "twelve professions: shaped file, square icon, Profession fallback, no mask", shaped)
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
			t.SetTexture = function(_, path) return fn(path) end
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
local restore = Gate(function(path) if path:find("Media\\Townsfolk\\", 1, true) then return false end return true end)
added = 0
mod.InstallTownsfolkData({ records = {
	{ id = 5153, name = "Jormund", title = "Expert Tailor", faction = "A", type = "tailoring", map = 1455, x = 43, y = 29 },
} })
restore()
ok(ValhallaDB.townsfolkIcons[tailorLook.texture] == tailorLook.square,
	"shaped file missing: the square icon is what was used", ValhallaDB.townsfolkIcons[tailorLook.texture])
local smith
for _, k in ipairs(mod.TOWNSFOLK) do if k.key == "blacksmithing" then smith = k.look end end
mod.db.townsfolk.tailoring = false
mod.db.townsfolk.blacksmithing = true
restore = Gate(function() return true end)
mod.InstallTownsfolkData({ records = {
	{ id = 2, name = "Smith", title = "Expert Blacksmith", faction = "A", type = "blacksmithing", map = 1455, x = 40, y = 30 },
} })
restore()
ok(ValhallaDB.townsfolkIcons[smith.texture] == smith.texture, "shaped file present: that file is what was used",
	ValhallaDB.townsfolkIcons[smith.texture])
local eng
for _, k in ipairs(mod.TOWNSFOLK) do if k.key == "engineering" then eng = k.look end end
mod.db.townsfolk.blacksmithing = false
mod.db.townsfolk.engineering = true
restore = Gate(function(path)
	if path:find("Media\\Townsfolk\\", 1, true) or path:find("Interface\\Icons\\", 1, true) then return false end
	return true
end)
mod.InstallTownsfolkData({ records = {
	{ id = 3, name = "Eng", title = "Expert Engineer", faction = "A", type = "engineering", map = 1455, x = 40, y = 30 },
} })
restore()
ok(ValhallaDB.townsfolkIcons[eng.texture] == eng.fallback, "square icon missing too: the Profession symbol is what was used",
	ValhallaDB.townsfolkIcons[eng.texture])

ns.Safe = { Call = function(fn, ...) return fn(...) end, IsSecret = function() return false end }
Minimap = { GetWidth = function() return 140 end, GetZoom = function() return 0 end }
function GetCVar(n) return n == "rotateMinimap" and "0" or "0" end
function IsIndoors() return false end
C_Map = C_Map or {}
function C_Map.GetBestMapForUnit() return 1453 end
local playerMX, playerMY = 0.5, 0.5
function C_Map.GetPlayerMapPosition() return { x = playerMX, y = playerMY, GetXY = function() return playerMX, playerMY end } end
function C_Map.GetWorldPosFromMapPos(mapID, vec)
	local x, y = 0, 0
	if vec.GetXY then x, y = vec:GetXY() elseif vec.x then x, y = vec.x, vec.y end
	return 0, { x = x * 1000, y = y * 1000 }
end
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
local levels = {}
local lastX, lastY
local oldCreate = CreateFrame
CreateFrame = function(kind, name, parent)
	local f = oldCreate(kind, name, parent)
	f.SetFrameLevel = function(self, n) levels[self] = n end
	f.GetFrameLevel = function(self) return levels[self] or 1 end
	f.SetParent = function() end
	f.ClearAllPoints = function() end
	f.SetPoint = function(self, _, _, _, x, y) self._x, self._y = x, y lastX, lastY = x, y end
	f.SetSize = function() end
	return f
end
local shows, levelsSeen = 0, {}
local baseCreate = CreateFrame
CreateFrame = function(...)
	local f = baseCreate(...)
	local show = f.Show
	f.Show = function(self) shows = shows + 1 if show then show(self) end end
	local setLevel = f.SetFrameLevel
	f.SetFrameLevel = function(self, n) levelsSeen[#levelsSeen + 1] = n if setLevel then setLevel(self, n) end end
	return f
end
assert(loadfile(root .. "Map/TownsfolkMinimap.lua"))("Valhalla", ns)
ns.TownsfolkData = { records = {
	{ id = 1, name = "Near", title = "Innkeeper", faction = "AH", type = "innkeeper", map = 1453, x = 51, y = 50 },
	{ id = 2, name = "Far", title = "Innkeeper", faction = "AH", type = "innkeeper", map = 1453, x = 100, y = 100 },
} }
mod.db.townsfolkMaster = true
mod.db.townsfolkMinimap = true
for k in pairs(mod.db.townsfolk) do mod.db.townsfolk[k] = false end
mod.db.townsfolk.innkeeper = true
mod.liveQuests = { { map = 1453, x = 0.5, y = 0.5, complete = false, id = 7 } }
shows, levelsSeen = 0, {}
mod:UpdateTownsfolkMinimap()
local folk, quest = false, false
for _, n in ipairs(levelsSeen) do if n == 4 then folk = true elseif n == 6 then quest = true end end
ok(shows == 2 and folk and quest, "minimap cull keeps the near pin and the quest badge above it; the far pin is hidden", shows)
mod.db.townsfolkMinimap = false
shows = 0
mod:UpdateTownsfolkMinimap()
ok(shows == 0, "minimap checkbox off draws nothing")

ns.TownsfolkData = { records = {
	{ id = 3, name = "East", title = "Innkeeper", faction = "AH", type = "innkeeper", map = 1453, x = 70, y = 50 },
} }
mod.liveQuests = {}
mod.db.townsfolkMinimap = true
mod.db.townsfolk.innkeeper = true
playerMX, playerMY = 0.5, 0.5
mod.db.townsfolk.vendor = true
mod:UpdateTownsfolkMinimap()
mod.db.townsfolk.vendor = false
mod:UpdateTownsfolkMinimap()
local eastX = lastX
playerMX = 0.6
mod:UpdateTownsfolkMinimap()
ok(type(eastX) == "number" and type(lastX) == "number" and lastX < eastX, "walking east moves the pin the other way", tostring(eastX) .. " -> " .. tostring(lastX))
playerMX, playerMY = 0.5, 0.3
mod:UpdateTownsfolkMinimap()
local northY = lastY
playerMY = 0.4
mod:UpdateTownsfolkMinimap()
ok(type(northY) == "number" and type(lastY) == "number" and lastY < northY, "walking north moves the pin the other way", tostring(northY) .. " -> " .. tostring(lastY))
playerMX, playerMY = 0.5, 0.5
function GetCVar(n) return n == "rotateMinimap" and "1" or "0" end
function GetPlayerFacing() return -math.pi / 2 end
mod:UpdateTownsfolkMinimap()
ok(type(lastY) == "number" and lastY > 20 and math.abs(lastX) < 1, "facing east, a pin to the east sits above the arrow", tostring(lastX) .. "," .. tostring(lastY))
function GetCVar() return "0" end
-- continent ids disagree, and the yard width is not real: a pin on this map is still drawn
function C_Map.GetWorldPosFromMapPos(mapID, vec)
	local x, y = 0, 0
	if vec.GetXY then x, y = vec:GetXY() elseif vec.x then x, y = vec.x, vec.y end
	return (x < 0.5) and 3 or 8, { x = x, y = y }
end
playerMX, playerMY = 0.5, 0.5
shows = 0
mod:UpdateTownsfolkMinimap()
ok(shows == 1, "no real yard width, and the corners disagree: the pin on this map is still drawn", shows)
function C_Map.GetWorldPosFromMapPos(mapID, vec)
	local x, y = 0, 0
	if vec.GetXY then x, y = vec:GetXY() elseif vec.x then x, y = vec.x, vec.y end
	return 0, { x = x * 1000, y = y * 1000 }
end

-- host map quests are drawn
function InCombatLockdown() return false end
Enum = Enum or { UIMapType = { Continent = 2, Zone = 3 } }
function C_Map.GetMapChildrenInfo() return { { mapID = 1453 } } end
function C_Map.GetMapInfo() return { mapType = 3 } end
C_QuestLog = {
	GetQuestsOnMap = function(id) if id == 1453 then return { { questID = 42, x = 0.2, y = 0.3 } } end return {} end,
	IsComplete = function() return true end,
}
mod.HostMap = function() return 1453 end
mod.IsStitched = function() return true end
mod.PadWaits = function() return false end
mod.ToWorld = function(_, x, y) return x, y end
mod.db.allQuests = true
S.Look = function() end
S.iconScale = 2
local questPins, badgeSize, markSize, pinScale, poiAtlas = 0
local oldAdd = S.AddPin
S.AddPin = function(set, ...)
	questPins = questPins + 1
	local look = select(3, ...)
	poiAtlas = look and look.atlas
	local pin = oldAdd(set, ...)
	pin.SetScale = function(self, s) pinScale = s end
	pin.SetSize = function(_, w) badgeSize = w end
	pin.Icon = { ClearAllPoints = function() end, SetPoint = function() end, SetSize = function(_, w) markSize = w end }
	pin.CreateTexture = function()
		return { SetPoint = function() end, SetSize = function() end, Show = function() end }
	end
	return pin
end
local prevCreate = CreateFrame
CreateFrame = function(kind, name, parent, template)
	if template == "ObjectiveTrackerPOIButtonTemplate" or template == "POIButtonTemplate" then
		local display = { w = 18, atlas = "UI-QuestPoi-Progress", GetWidth = function(self) return self.w end, GetAtlas = function(self) return self.atlas end }
		return {
			Display = display, Hide = function() end,
			GetWidth = function() return 24 end,
			SetStyle = function(self, style) self.style = style end,
			UpdateButtonStyle = function(self)
				self.Display.atlas = self.style == 3 and "UI-QuestPoi-Bang" or "UI-QuestPoi-Progress"
				self.Display.w = 18
			end,
		}
	end
	return prevCreate(kind, name, parent, template)
end
POIButtonUtil = { Style = { QuestInProgress = 5, QuestComplete = 3 } }
assert(loadfile(root .. "Map/Quests.lua"))("Valhalla", ns)
mod:RefreshQuests()
ok(questPins == 1, "a quest on the host map is drawn above the townsfolk layer", questPins)
ok(badgeSize == 20 and markSize and math.abs(markSize / badgeSize - 18 / 24) < 0.001,
	"the mark is the same share of the badge as the log button's display", tostring(markSize) .. "/" .. tostring(badgeSize))
ok(poiAtlas == "UI-QuestPoi-Bang" and pinScale == 1, "one combined atlas, and the Icon size slider does not scale it", tostring(poiAtlas) .. " " .. tostring(pinScale))
ok(ValhallaDB.questPoi and ValhallaDB.questPoi.button == 24 and ValhallaDB.questPoi.complete == 18 and ValhallaDB.questPoi.inProgress == 18,
	"the measured log widths are saved", ValhallaDB.questPoi and ValhallaDB.questPoi.button)
CreateFrame = prevCreate

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
