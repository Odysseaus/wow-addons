-- Box tests for 1.2.47: Townsfolk's Icon size (Large / Medium / Small) on the world map only, this
-- character's (ValhallaCharDB.worldmap), applied live.
-- Run: lua5.1 valhalla/tests/worldmap/townsfolksize_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
	if cond then pass = pass + 1 print("PASS  " .. name)
	else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end
local function src(path) local f = assert(io.open(root .. path)) local s = f:read("*a") f:close() return s end

---------------------------------------------------------------------------
print("== 1. Stitch: a set's own scale, times the menu's Icon size, live on its pins")
do
	local ns = { Media = { tex = "T\\", path = "P\\" }, Client = "Forever" }
	function ns:GetModule() return {} end
	ns.L = setmetatable({}, { __index = function(_, k) return k end })
	function CreateFrame()
		local f = {}
		return setmetatable(f, { __index = function() return function() return f end end })
	end
	pcall(function() assert(loadfile(root .. "Map/Stitch.lua"))("Valhalla", ns) end)
	local S = ns.MapStitch
	ok(S and type(S.SetPinSetScale) == "function" and type(S.PinSet) == "function", "S.SetPinSetScale is there")
	local function Pin() return { scale = 1, SetScale = function(self, k) self.scale = k end } end
	local folk = S.PinSet("tf_innkeeper", 8)
	local boats = S.PinSet("boats", 1)
	folk.pins[1], folk.pins[2], boats.pins[1] = Pin(), Pin(), Pin()
	S.SetPinSetScale(folk, 0.8)
	ok(near(folk.pins[1].scale, 0.8) and near(folk.pins[2].scale, 0.8), "every pin of the set at 0.8 at once", folk.pins[1].scale)
	ok(boats.pins[1].scale == 1 and boats.iconScale == nil, "another set (boats) untouched")
	S.SetIconScale(1.5)
	ok(near(folk.pins[1].scale, 1.2) and near(boats.pins[1].scale, 1.5), "the menu's Icon size multiplies: townsfolk 1.5 x 0.8, boats 1.5", folk.pins[1].scale)
	S.SetPinSetScale(folk, 0.65)
	ok(near(folk.pins[2].scale, 1.5 * 0.65), "Small with the menu at 150%", folk.pins[2].scale)
	S.SetPinSetScale(folk, 1)
	ok(near(folk.pins[1].scale, 1.5) and folk.iconScale == 1, "back to Large: the menu's size only")
	S.SetIconScale(1)
	-- AddPin (it needs the built map to run here): its scale is the product
	ok(src("Map/Stitch.lua"):find("pin:SetScale((S.iconScale or 1) * (set.iconScale or 1))", 1, true) ~= nil,
		"a new or pooled pin gets the menu's size times its set's")
end

---------------------------------------------------------------------------
print("== 2. Townsfolk: the setting, its scales, every townsfolk set and only them")
local ns = {}
bit = { band = function(a, b) local n, m = 1, 0 while a > 0 or b > 0 do if a % 2 == 1 and b % 2 == 1 then m = m + n end a = math.floor(a / 2) b = math.floor(b / 2) n = n * 2 end return m end,
	bor = function(a, b) local n, m = 1, 0 while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then m = m + n end a = math.floor(a / 2) b = math.floor(b / 2) n = n * 2 end return m end }
local sets, scaled = {}, {}
local S = {
	IsBuilt = function() return true end,
	PinSet = function(key) local s = sets[key] or { key = key, on = true, pins = 0 } sets[key] = s return s end,
	GetPinSet = function(key) return sets[key] end,
	SetPinSetOn = function(set, on) set.on = on and true or false end,
	ClearPinSet = function(set) set.pins = 0 end,
	Rect = function() return 0, 1, 0, 1 end,
	AddPin = function(set) set.pins = set.pins + 1 set.added = (set.added or 0) + 1 set.addScale = set.iconScale return { SetScript = function() end } end,
	SetPinSetScale = function(set, k) set.iconScale = k scaled[set.key] = k end,
}
local mod = { defaults = {}, db = {} }
local panelRefreshed = 0
function mod:RefreshPanel() panelRefreshed = panelRefreshed + 1 end
function ns:GetModule() return mod end
ns.MapStitch = S
ns.L = setmetatable({}, { __index = function(_, k) return k end })
function ns:Print() end
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Mage", "MAGE" end
C_Timer = { After = function(_, fn) fn() end }
CreateFrame = function()
	return { CreateTexture = function() return { SetTexture = function() return true end } end, Hide = function() end }
end
C_Texture = { GetAtlasInfo = function() return nil end }
ValhallaDB = {}
assert(loadfile(root .. "Data/Forever/Townsfolk.lua"))("Valhalla", ns)
assert(loadfile(root .. "Map/Townsfolk.lua"))("Valhalla", ns)
ok(mod.defaults.townsfolkSize == "large", "default: Large (the size before 1.2.47)")
local scales = {}
for _, s in ipairs(mod.TOWNSFOLK_SIZES) do scales[#scales + 1] = s.key .. "=" .. s.scale end
ok(table.concat(scales, ",") == "large=1,medium=0.8,small=0.65", "Large 100%, Medium 80%, Small 65%", table.concat(scales, ","))

mod.db = { townsfolkMaster = true, townsfolk = {} }
for _, k in ipairs(mod.TOWNSFOLK) do mod.db.townsfolk[k.key] = false end
mod.db.townsfolk.innkeeper = true
ok(mod.TownsfolkSize() == "large" and mod.TownsfolkScale() == 1, "no saved choice: Large")
mod:RefreshTownsfolk()
ok(sets.tf_innkeeper and sets.tf_innkeeper.added > 0 and sets.tf_innkeeper.addScale == 1, "inn pins built at Large", sets.tf_innkeeper and sets.tf_innkeeper.added)
sets.boats = { key = "boats", pins = 0 }
sets.dungeons = { key = "dungeons", pins = 0 }
sets.quests = { key = "quests", pins = 0 }
local built = sets.tf_innkeeper.added
panelRefreshed = 0
mod.SetTownsfolkSize("medium")
ok(mod.db.townsfolkSize == "medium" and near(sets.tf_innkeeper.iconScale, 0.8), "Medium: the built inn pins at 0.8, live", sets.tf_innkeeper.iconScale)
ok(sets.tf_innkeeper.added == built, "no rebuild for a size change")
ok(panelRefreshed > 0, "the menu's ticks follow (the radio's other two clear)")
ok(scaled.boats == nil and scaled.dungeons == nil and scaled.quests == nil, "boats, dungeons, quest icons not scaled")
mod.db.townsfolk.mailbox = true
mod:RefreshTownsfolk()
ok(sets.tf_mailbox and sets.tf_mailbox.added > 0 and near(sets.tf_mailbox.addScale, 0.8), "a type turned on later is built at Medium", sets.tf_mailbox and sets.tf_mailbox.addScale)
mod.SetTownsfolkSize("small")
ok(near(sets.tf_innkeeper.iconScale, 0.65) and near(sets.tf_mailbox.iconScale, 0.65), "Small: every townsfolk set at 0.65")
mod.SetTownsfolkSize("huge")
ok(mod.db.townsfolkSize == "small", "an unknown size is ignored")
mod.db.townsfolkSize = "huge"
ok(mod.TownsfolkSize() == "large" and mod.TownsfolkScale() == 1, "a bad saved value reads as Large")
mod.db.townsfolkSize = "small"
mod:RefreshTownsfolk()
ok(near(sets.tf_innkeeper.iconScale, 0.65), "a refresh keeps the chosen size")

---------------------------------------------------------------------------
print("== 3. saved per character (ValhallaCharDB.worldmap), not shared")
do
	local saveCF = CreateFrame
	CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() return true end, UnregisterEvent = function() end } end
	function GetAddOnMetadata() return "1.2.47" end
	C_AddOns = { GetAddOnMetadata = GetAddOnMetadata }
	DEFAULT_CHAT_FRAME = { AddMessage = function() end }
	function geterrorhandler() return function() end end
	local cns = { Client = "Forever" }
	assert(loadfile(root .. "Core.lua"))("Valhalla", cns)
	local function Module()
		cns.modules = {}
		return cns:NewModule("worldmap", { defaults = { townsfolkSize = "large", iconScale = 1, townsfolk = {} } })
	end
	ValhallaDB, ValhallaCharDB = { worldmap = { iconScale = 1 } }, { worldmap = { mapSeeded = true } }
	local m = Module()
	cns:InitDB()
	ok(m.db.townsfolkSize == "large" and ValhallaCharDB.worldmap.townsfolkSize == "large", "an existing character gets Large, on the character")
	m.db.townsfolkSize = "small"
	ok(ValhallaCharDB.worldmap.townsfolkSize == "small" and ValhallaDB.worldmap.townsfolkSize ~= "small", "a choice is written to ValhallaCharDB.worldmap, not the account")
	local first = ValhallaCharDB
	ValhallaCharDB = {}
	m = Module()
	cns:InitDB()
	ok(m.db.townsfolkSize == "large", "another character keeps its own (Large)", m.db.townsfolkSize)
	ValhallaCharDB = first
	m = Module()
	cns:InitDB()
	ok(m.db.townsfolkSize == "small", "the first character's Small is kept after a reload")
	CreateFrame = saveCF
end

---------------------------------------------------------------------------
print("== 4. the menu: three ticks under Townsfolk, one ticked, as a radio")
do
	local text = src("Map/Panel.lua")
	local a = text:find("-- (1.2.47) their icons' size", 1, true)
	local b = a and text:find("\n\tend\n\t-- the look", a, true)
	ok(a and b, "the size rows sit at the end of the Townsfolk section")
	local chunk = a and b and text:sub(a, b) or ""
	local fn = loadstring("local rows, row, L, mod, Icon = ...\n" .. chunk .. "\nreturn rows")
	ok(fn ~= nil, "the rows' code runs on its own")
	local rows = {}
	local function row(label, id, icon, get, set) return { label, get, set, id = id, icon = icon } end
	local function Icon(n) return { texture = n } end
	fn = fn or function() return rows end
	fn(rows, row, setmetatable({}, { __index = function(_, k) return k end }), mod, Icon)
	ok(rows[1] and rows[1][1] == "Icon size on the world map" and rows[1][2] == nil, "a heading: Icon size on the world map")
	ok(rows[2] and rows[2][1] == "Large" and rows[3][1] == "Medium" and rows[4][1] == "Small" and #rows == 4, "Large, Medium, Small")
	ok(rows[2] and rows[2].id == "townsfolkSize.large" and rows[4].id == "townsfolkSize.small", "each has a fixed id (favourites)")
	mod.db.townsfolkSize = "medium"
	ok(rows[3] and rows[3][2]() == true and rows[2][2]() == false and rows[4][2]() == false, "only the chosen one is ticked")
	rows[4][3](true)
	ok(mod.db.townsfolkSize == "small" and rows[4][2]() and not rows[3][2](), "ticking Small chooses Small, Medium clears")
	panelRefreshed = 0
	rows[4][3](false)
	ok(mod.db.townsfolkSize == "small" and panelRefreshed > 0, "unticking the chosen one keeps it (re-ticked)")
end

---------------------------------------------------------------------------
print("== 5. not the minimap; no Blizzard frame touched")
local mm = src("Map/TownsfolkMinimap.lua")
ok(not mm:find("townsfolkSize", 1, true) and not mm:find("TownsfolkScale", 1, true), "the minimap's pins don't read the setting")
local tf = src("Map/Townsfolk.lua")
local s = tf:find("d.townsfolkSize", 1, true)
local e = tf:find("function mod.SetTownsfolkSize", 1, true)
local part = s and e and tf:sub(s, e + 300) or ""
ok(not part:find("SetFrameLevel", 1, true) and not part:find("layoutIndex", 1, true) and not part:find("Layout", 1, true), "no layout or frame level writes")

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
