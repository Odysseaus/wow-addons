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
ok(types.vendor and types.classTrainer and types.profTrainer, "vendors and both kinds of trainer are present")

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
CreateFrame = function() return { CreateTexture = function() return { SetTexture = function() return true end } end, Hide = function() end } end
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

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
