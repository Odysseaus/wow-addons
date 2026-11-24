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

ns.Safe = { Call = function(fn, ...) return fn(...) end, IsSecret = function() return false end }
Minimap = { GetWidth = function() return 140 end, GetZoom = function() return 0 end }
function GetCVar(n) return n == "rotateMinimap" and "0" or "0" end
function IsIndoors() return false end
C_Map = C_Map or {}
function C_Map.GetBestMapForUnit() return 1453 end
function C_Map.GetPlayerMapPosition() return { GetXY = function() return 0.5, 0.5 end } end
function C_Map.GetWorldPosFromMapPos(mapID, vec)
	local x, y = 0, 0
	if vec.GetXY then x, y = vec:GetXY() elseif vec.x then x, y = vec.x, vec.y end
	return 0, { x = x * 1000, y = y * 1000 }
end
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
local levels = {}
local oldCreate = CreateFrame
CreateFrame = function(kind, name, parent)
	local f = oldCreate(kind, name, parent)
	f.SetFrameLevel = function(self, n) levels[self] = n end
	f.GetFrameLevel = function(self) return levels[self] or 1 end
	f.SetParent = function() end
	f.ClearAllPoints = function() end
	f.SetPoint = function(self, _, _, _, x) self._x = x end
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
local questPins = 0
local oldAdd = S.AddPin
S.AddPin = function(set, ...)
	questPins = questPins + 1
	local pin = oldAdd(set, ...)
	pin.CreateTexture = function() return { SetPoint = function() end, SetSize = function() end, Show = function() end } end
	return pin
end
assert(loadfile(root .. "Map/Quests.lua"))("Valhalla", ns)
mod:RefreshQuests()
ok(questPins == 1, "a quest on the host map is drawn above the townsfolk layer", questPins)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
