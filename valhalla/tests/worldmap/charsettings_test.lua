-- Box tests for 1.2.42: map display toggles are per character, seeded once from the account.
-- Run: lua5.1 valhalla/tests/worldmap/charsettings_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
	if cond then pass = pass + 1 print("PASS  " .. name)
	else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

function CreateFrame()
	return { SetScript = function() end, RegisterEvent = function() return true end, UnregisterEvent = function() end }
end
function GetAddOnMetadata() return "1.2.42" end
C_AddOns = { GetAddOnMetadata = GetAddOnMetadata }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function geterrorhandler() return function() end end

local ns = { Client = "Forever" }
assert(loadfile(root .. "Core.lua"))("Valhalla", ns)

local function Module()
	ns.modules = {}
	return ns:NewModule("worldmap", { defaults = {
		enabled = true,
		iconScale = 1,
		townsfolkMaster = false,
		townsfolkMinimap = true,
		townsfolk = { innkeeper = false, alchemy = false },
		flight = true,
		flightTimer = true,
		allQuests = true,
		pins = { list = {}, nextId = 1 },
		flightTimes = {},
		window = false,
	} })
end

print("== 1. a character with no worldmap table is seeded once from the account")
local mod = Module()
ValhallaDB = { worldmap = {
	townsfolkMaster = true, iconScale = 1.5, flight = false,
	townsfolk = { innkeeper = true },
	pins = { list = { "keep" }, nextId = 2 },
	flightTimes = { ["A|B"] = 10 },
	window = { "CENTER", "CENTER", 0, 0 },
	townsfolkIcons = "not here",
} }
ValhallaDB.townsfolkIcons = { Trade_Tailoring = "mask" }
ValhallaCharDB = {}
ns:InitDB()
ok(ValhallaCharDB.worldmap.townsfolkMaster == true and ValhallaCharDB.worldmap.iconScale == 1.5
	and ValhallaCharDB.worldmap.flight == false and ValhallaCharDB.worldmap.townsfolk.innkeeper == true,
	"first login copies the account's toggles")
ok(ValhallaCharDB.worldmap.mapSeeded == true, "the seed is marked so it happens once")
ok(ValhallaCharDB.worldmap.pins == nil and ValhallaCharDB.worldmap.flightTimes == nil and ValhallaCharDB.worldmap.window == nil,
	"pins, flight times and the window's place are not copied onto the character")
ok(ValhallaDB.townsfolkIcons.Trade_Tailoring == "mask", "townsfolkIcons stays on the account")
mod.db.townsfolk.innkeeper = false
ok(ValhallaDB.worldmap.townsfolk.innkeeper == true, "a character's edit does not change the account copy")
mod.db.townsfolkMaster = false
mod.db.pins.list[2] = "shared"
ok(ValhallaDB.worldmap.townsfolkMaster == true and ValhallaDB.worldmap.pins.list[2] == "shared",
	"the old account keys stay, and a pin is written on the account")

print("== 2. a second login does not seed again")
ns:InitDB()
ok(mod.db.townsfolkMaster == false and ValhallaCharDB.worldmap.townsfolkMaster == false,
	"the character's own toggle survives the next login")
ok(ValhallaDB.worldmap.townsfolkMaster == true and ValhallaDB.worldmap.iconScale == 1.5,
	"the account keys are still the originals")

print("== 3. two characters stay independent; account data is shared")
local charA = ValhallaCharDB
mod.db.flightTimes["A|B"] = 12
ValhallaCharDB = {}
ns:InitDB()
local charB = ValhallaCharDB
ok(charB ~= charA and charB.worldmap.townsfolkMaster == true and charA.worldmap.townsfolkMaster == false,
	"one character can show townsfolk while the other does not")
ok(charA.worldmap.flightTimes == nil and charB.worldmap.flightTimes == nil
	and ValhallaDB.worldmap.flightTimes["A|B"] == 12 and mod.db.pins.list[1] == "keep",
	"flight times and pins stay on the account for both characters")
ValhallaCharDB = charA
ns:InitDB()
ok(mod.db.townsfolkMaster == false and mod.db.flightTimes["A|B"] == 12,
	"switching back reads that character's toggles and the shared times")

print("== 4. a character who already has a table keeps it, and gains the account toggles once")
ValhallaDB = { worldmap = { townsfolkMaster = true, iconScale = 1.5, pins = { list = { "p" } } } }
local existing = { flightsKnown = { ["Stormwind"] = true } }
ValhallaCharDB = { worldmap = existing }
ns:InitDB()
ok(ValhallaCharDB.worldmap == existing and existing.flightsKnown.Stormwind == true,
	"an existing character table is not replaced")
ok(existing.townsfolkMaster == true and existing.mapSeeded == true, "its missing toggles are seeded from the account")
existing.townsfolkMaster = false
ValhallaDB.worldmap.townsfolkMaster = true
ns:InitDB()
ok(existing.townsfolkMaster == false, "the next login does not copy over the character")

print("== 5. a missing toggle is filled from the defaults, not from a later account edit")
existing.iconScale = nil
existing.mapSeeded = true
ValhallaDB.worldmap.iconScale = 9
ns:InitDB()
ok(mod.db.iconScale == 1 and ValhallaDB.worldmap.iconScale == 9, "the default fills the gap; the account value stays 9")
existing.townsfolk = { innkeeper = true }
ns:InitDB()
ok(existing.townsfolk.innkeeper == true and existing.townsfolk.alchemy == false,
	"a new profession key arrives from the defaults without clearing the ones already set")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
