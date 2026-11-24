--------------------------------------------------------------------------------
-- Townsfolk on the world map. Valhalla's own Forever data (Data/Forever/Townsfolk.lua) is
-- registered as the provider, so the pins do not need Questie. Another addon may still register
-- a database of the same shape (ValhallaAPI.RegisterTownsfolkProvider). Rare mobs stay on
-- Questie's database when Questie itself is installed. Each kind is a pin set, built the first
-- time it's turned on (a few hundred NPCs a frame, so nothing stalls).
--------------------------------------------------------------------------------

local _, ns = ...
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")

-- kind -> look, the zoom it shows from, and what picks its NPCs.
-- (1.2.40) every townsfolk icon is the learned flight master's size (22). Rares stay 18.
local PIN = 22
local PROF_FALLBACK = "Interface\\Minimap\\Tracking\\Profession"
local function Prof(key, name, icon)
	return { key = key, name = ns.L[name], flag = key:upper(), zoom = 8,
		look = { texture = "Interface\\Icons\\" .. icon, fallback = PROF_FALLBACK, size = PIN } }
end
local KINDS = {
	{ key = "vendor", name = ns.L["Vendors"], flag = "VENDOR", zoom = 8,
		look = { texture = "Interface\\GossipFrame\\VendorGossipIcon", size = PIN } },
	{ key = "food", name = ns.L["Food and drink"], flag = "FOOD", zoom = 8,
		look = { texture = "Interface\\Minimap\\Tracking\\Food", fallback = "Interface\\GossipFrame\\VendorGossipIcon", size = PIN } },
	{ key = "reagent", name = ns.L["Reagents"], flag = "REAGENT", zoom = 8,
		look = { texture = "Interface\\Minimap\\Tracking\\Reagents", fallback = "Interface\\GossipFrame\\VendorGossipIcon", size = PIN } },
	{ key = "repair", name = ns.L["Repair"], flag = "REPAIR", zoom = 6,
		look = { texture = "Interface\\Minimap\\Tracking\\Repair", fallback = "Interface\\GossipFrame\\VendorGossipIcon", size = PIN } },
	{ key = "innkeeper", name = ns.L["Innkeepers"], flag = "INNKEEPER", zoom = 4,
		look = { texture = "Interface\\Minimap\\Tracking\\Innkeeper", fallback = "Interface\\GossipFrame\\BinderGossipIcon", size = PIN } },
	{ key = "banker", name = ns.L["Bankers"], flag = "BANKER", zoom = 6,
		look = { texture = "Interface\\Minimap\\Tracking\\Banker", fallback = "Interface\\GossipFrame\\BankerGossipIcon", size = PIN } },
	{ key = "mailbox", name = ns.L["Mailboxes"], mailbox = true, zoom = 6,
		look = { texture = "Interface\\Minimap\\Tracking\\Mailbox", fallback = "Interface\\Icons\\INV_Letter_15", size = PIN } },
	{ key = "auctioneer", name = ns.L["Auctioneers"], flag = "AUCTIONEER", zoom = 6,
		look = { texture = "Interface\\Minimap\\Tracking\\Auctioneer", fallback = "Interface\\GossipFrame\\VendorGossipIcon", size = PIN } },
	{ key = "stable", name = ns.L["Stable masters"], flag = "STABLEMASTER", zoom = 6,
		look = { texture = "Interface\\Minimap\\Tracking\\StableMaster", fallback = "Interface\\GossipFrame\\PetitionGossipIcon", size = PIN } },
	{ key = "classTrainer", name = ns.L["Class trainers"], flag = "TRAINER", class = true, zoom = 6,
		look = { texture = "Interface\\Minimap\\Tracking\\Class", fallback = "Interface\\GossipFrame\\TrainerGossipIcon", size = PIN } },
	Prof("alchemy", "Alchemy", "Trade_Alchemy"),
	Prof("blacksmithing", "Blacksmithing", "Trade_BlackSmithing"),
	Prof("enchanting", "Enchanting", "Trade_Engraving"),
	Prof("engineering", "Engineering", "Trade_Engineering"),
	Prof("herbalism", "Herbalism", "Trade_Herbalism"),
	Prof("leatherworking", "Leatherworking", "Trade_LeatherWorking"),
	Prof("mining", "Mining", "Trade_Mining"),
	Prof("skinning", "Skinning", "INV_Misc_Pelt_Wolf_01"),
	Prof("tailoring", "Tailoring", "Trade_Tailoring"),
	Prof("cooking", "Cooking", "INV_Misc_Food_15"),
	Prof("firstaid", "First Aid", "Spell_Holy_SealOfSacrifice"),
	Prof("fishing", "Fishing", "Trade_Fishing"),
	{ key = "spirit", name = ns.L["Spirit healers"], ids = { [6491] = true }, zoom = 3, hostile = true,
		look = { atlas = "poi-soulspiritghost", texture = "Interface\\Minimap\\ObjectIcons", size = PIN } },
	{ key = "rare", name = ns.L["Rare mobs"], rare = true, zoom = 3, hostile = true,
		look = { atlas = "VignetteKillElite", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", size = 18 } },
}
mod.PROFESSIONS = { "alchemy", "blacksmithing", "enchanting", "engineering", "herbalism", "leatherworking",
	"mining", "skinning", "tailoring", "cooking", "firstaid", "fishing" }
mod.REPAIR_LOOK = { texture = "Interface\\Minimap\\Tracking\\Repair", fallback = "Interface\\GossipFrame\\VendorGossipIcon", size = PIN }
mod.TOWNSFOLK = KINDS

local d = mod.defaults
d.townsfolkMaster = false       -- (1.2.39) one switch for every townsfolk type. Each type has its own checkbox too.
d.townsfolkMinimap = true       -- (1.2.40) the same townsfolk on the minimap. Off hides only the minimap pins.
d.townsfolk = {}
for _, k in ipairs(KINDS) do d.townsfolk[k.key] = false end

local built = {}                -- kind key -> true once its pins exist
local building = false
local tries = 0                 -- retries while Questie's database loads
local RANK = { [2] = ns.L["Rare Elite"], [4] = ns.L["Rare"] }
-- the classes' English names, as Questie's subnames have them on every client
local ENGLISH_CLASS_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid", DEATHKNIGHT = "Death Knight",
	MONK = "Monk", DEMONHUNTER = "Demon Hunter", EVOKER = "Evoker",
}
mod.TOWNSFOLK_CLASSES = ENGLISH_CLASS_NAMES
local told = false              -- said once this session that Questie isn't installed

-- another addon's NPC database in Questie's shape (ValhallaAPI.RegisterTownsfolkProvider): { db, zones,
-- mailboxes = fn(faction "A" / "H") -> object IDs (optional) }
local provider
function mod.SetTownsfolkProvider(p)
	provider = p
	for k in pairs(built) do
		built[k] = nil
		local set = S.GetPinSet("tf_" .. k)
		if set then S.ClearPinSet(set) end
	end
	tries = 0
	if mod.RefreshPanel then mod:RefreshPanel() end
	mod:RefreshTownsfolk()
end

-- whether there's a database to read: Questie's, or one given (a player's own: Questie's database
-- without Questie)
function mod.HasTownsfolk()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	return provider ~= nil or _G.QuestieLoader ~= nil or (loaded and loaded("Questie")) and true or false
end

local function Questie(forRare)
	-- rares stay on Questie's own database. Everything else prefers the registered provider
	-- (Valhalla's Forever file, or another addon).
	if not forRare and provider then return provider.db, provider.zones, provider end
	local loader = _G.QuestieLoader
	if not loader then return end
	local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
	local ok2, zones = pcall(loader.ImportModule, loader, "ZoneDB")
	if ok and ok2 and db and db.NPCPointers and db.QueryNPCSingle and zones then return db, zones end
end

-- An NPC that walks about (Girl with Puppies round Orgrimmar) has every point of its path among its
-- spawns: past WANDER of them in one zone, one pin, at the spawn nearest the middle of them all
local WANDER = 6
local function Middle(coords)
	local sx, sy, n = 0, 0, 0
	for _, c in ipairs(coords) do
		if c[1] and c[1] >= 0 then sx, sy, n = sx + c[1], sy + c[2], n + 1 end
	end
	if n == 0 then return coords end
	sx, sy = sx / n, sy / n
	local best, bestD
	for _, c in ipairs(coords) do
		if c[1] and c[1] >= 0 then
			local d = (c[1] - sx) ^ 2 + (c[2] - sy) ^ 2
			if not bestD or d < bestD then best, bestD = c, d end
		end
	end
	return { best }
end

local function InCombat()
	if InCombatLockdown and InCombatLockdown() then return true end
	if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
	local C = ns.Combat
	return C and C.Blocked and C.Blocked() or false
end
-- our own pins only. In combat the game's tooltip is left alone (it reads secret values).
local function PinEnter(pin)
	if InCombat() then return end
	local n = pin.data
	if not (GameTooltip and GameTooltip.SetOwner) then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(n.name, 1, 0.82, 0)
	if n.sub then GameTooltip:AddLine(n.sub, 1, 1, 1) end
	local lv = n.min and (n.min == n.max and tostring(n.min) or (n.min .. "-" .. (n.max or n.min)))
	if lv or n.rank then
		GameTooltip:AddLine(((lv and (LEVEL .. " " .. lv)) or "") .. (n.rank and ("  " .. n.rank) or ""), 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end

-- every wanted NPC, sorted into kinds; then pins for the kinds that are on
local function Saved()
	local db = rawget(_G, "ValhallaDB")
	if type(db) ~= "table" then return nil end
	return db
end
local function NoteMiss(mapID)
	local db = Saved()
	if not db then return end
	local m = db.townsfolkMiss
	if type(m) ~= "table" then m = { spawns = 0, maps = {} } db.townsfolkMiss = m end
	m.spawns = (tonumber(m.spawns) or 0) + 1
	m.maps = type(m.maps) == "table" and m.maps or {}
	local key = tostring(mapID)
	m.maps[key] = (tonumber(m.maps[key]) or 0) + 1
end
local iconNoted = {}
local function NoteIcon(look)
	local db = Saved()
	if not db or type(look) ~= "table" then return end
	local key = look.atlas or look.texture
	if not key or iconNoted[key] then return end
	iconNoted[key] = true
	local icons = db.townsfolkIcons
	if type(icons) ~= "table" then icons = {} db.townsfolkIcons = icons end
	local ok = false
	if look.atlas and C_Texture and type(C_Texture.GetAtlasInfo) == "function" then
		local good, info = pcall(C_Texture.GetAtlasInfo, look.atlas)
		ok = good and type(info) == "table"
	end
	if not ok and look.texture and CreateFrame then
		local f = CreateFrame("Frame")
		local tex = f and f.CreateTexture and f:CreateTexture()
		if tex and tex.SetTexture then
			local good, res = pcall(tex.SetTexture, tex, look.texture)
			ok = good and res ~= false
		end
		if f and f.Hide then f:Hide() end
	end
	icons[key] = ok and true or false
end

local function Build(kinds, done, forRare)
	local QDB, ZoneDB = Questie(forRare)
	if not QDB then return done(false) end
	local flags = QDB.npcFlags or {}
	local faction = UnitFactionGroup("player") == "Horde" and "H" or "A"
	local myClass = select(2, UnitClass("player"))
	-- a trainer's class from its subname, by class token: Questie's subnames are English ("Warrior
	-- Trainer") whatever the client's language, or translated by Questie, so both are looked for, in
	-- lower case ("Maître des guerriers"); longest first (Demon Hunter before Hunter)
	local classNames = {}
	local function AddNames(t)
		for token, n in pairs(t or {}) do
			if type(n) == "string" and n ~= "" then classNames[#classNames + 1] = { n:lower(), token } end
		end
	end
	AddNames(ENGLISH_CLASS_NAMES)
	AddNames(LOCALIZED_CLASS_NAMES_MALE)
	AddNames(LOCALIZED_CLASS_NAMES_FEMALE)
	table.sort(classNames, function(a, b) return #a[1] > #b[1] end)

	-- a kind's pins at each of its spawns ({ [areaID] = { { x, y }, ... } }, as Questie keeps them);
	-- `walker`: one NPC's, a path walked taken as one place (Middle)
	local function Pins(k, spawns, info, walker)
		local set = S.PinSet("tf_" .. k.key, k.zoom, 3)
		for areaID, coords in pairs(spawns) do
			if walker and #coords > WANDER then coords = Middle(coords) end
			local uiMapID = ZoneDB:GetUiMapIdByAreaId(areaID)
			local l, r, t, b
			if uiMapID then l, r, t, b = S.Rect(uiMapID) end
			if not l then NoteMiss(uiMapID or areaID)
			else
				local look = (info and info.icon == "repair") and mod.REPAIR_LOOK or k.look
				NoteIcon(look)
				if look.fallback then NoteIcon({ texture = look.fallback }) end
				for _, c in ipairs(coords) do
					if c[1] and c[1] >= 0 then
						local pin = S.AddPin(set, l + c[1] / 100 * (r - l), t + c[2] / 100 * (b - t), look, info)
						pin:SetScript("OnEnter", PinEnter)
						pin:SetScript("OnLeave", GameTooltip_Hide)
					end
				end
			end
		end
	end
	-- the mailboxes, all at once (a few dozen objects): your faction's, as Questie sorts them, or
	-- every one where it can't
	local function Mailboxes(k)
		if provider then
			if not (provider.mailboxes and QDB.QueryObjectSingle) then return end
			local info = { name = MINIMAP_TRACKING_MAILBOX or "Mailbox" }
			for _, id in ipairs(provider.mailboxes(faction) or {}) do
				local spawns = QDB.QueryObjectSingle(id, "spawns")
				if spawns then Pins(k, spawns, info) end
			end
			return
		end
		local folk = _G.QuestieLoader and select(2, pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "Townsfolk"))
		if type(folk) ~= "table" or not folk.GetMailboxes or not QDB.QueryObjectSingle then return end
		local list
		if folk.GetFactionSpecificMailboxes then
			local ok, alliance, horde = pcall(folk.GetFactionSpecificMailboxes)
			if ok then list = faction == "H" and horde or alliance end
		end
		list = (type(list) == "table" and #list > 0) and list or folk.GetMailboxes() or {}
		local info = { name = MINIMAP_TRACKING_MAILBOX or "Mailbox" }
		for _, id in ipairs(list) do
			local spawns = QDB.QueryObjectSingle(id, "spawns")
			if spawns then Pins(k, spawns, info) end
		end
	end

	local ids = {}
	for id in pairs(QDB.NPCPointers) do ids[#ids + 1] = id end
	local i = 0
	local Step
	local function Chunk()
		for _ = 1, 400 do
			i = i + 1
			local id = ids[i]
			if not id then return true end
			local f = QDB.QueryNPCSingle(id, "npcFlags") or 0
			local rank = QDB.QueryNPCSingle(id, "rank") or 0
			local want = {}
			for _, k in ipairs(kinds) do
				local hit
				if k.ids then
					hit = k.ids[id] or false
				elseif k.rare then
					hit = RANK[rank] ~= nil
				elseif flags[k.flag] and bit.band(f, flags[k.flag]) ~= 0 then
					hit = true
					if k.class or k.profession then
						local sub = (QDB.QueryNPCSingle(id, "subName") or ""):lower()
						local cls
						for _, c in ipairs(classNames) do
							if sub:find(c[1], 1, true) then cls = c[2] break end
						end
						local tag = QDB.QueryNPCSingle(id, "trainerTag")
					if type(tag) == "string" then
						if k.class then hit = tag ~= "PROF" and tag == myClass else hit = tag == "PROF" end
					elseif k.class then hit = cls ~= nil and cls == myClass else hit = cls == nil end
					end
				end
				if hit then want[#want + 1] = k end
			end
			if #want > 0 then
				local friendly = QDB.QueryNPCSingle(id, "friendlyToFaction") or ""
				local spawns = QDB.QueryNPCSingle(id, "spawns")
				local info = {
					name = QDB.QueryNPCSingle(id, "name") or "?", sub = QDB.QueryNPCSingle(id, "subName"),
					min = QDB.QueryNPCSingle(id, "minLevel"), max = QDB.QueryNPCSingle(id, "maxLevel"), rank = RANK[rank],
					icon = QDB.QueryNPCSingle(id, "pinIcon"),
				}
				for _, k in ipairs(want) do
					-- (not spirit healers or rare mobs: one NPC at many places, each a place of its own)
					if (k.hostile or friendly:find(faction, 1, true)) and spawns then Pins(k, spawns, info, not (k.ids or k.rare)) end
				end
			end
		end
	end
	local npcs = false              -- (any kind picked from the NPCs: else no NPC to go through)
	for _, k in ipairs(kinds) do
		if k.mailbox then
			local ok, err = pcall(Mailboxes, k)
			if not ok then geterrorhandler()(err) end
		else
			npcs = true
		end
	end
	if not npcs then return done(true) end
	function Step()
		local ok, finished = pcall(Chunk)
		if not ok then
			geterrorhandler()(finished)
			return done(false)
		end
		if finished then return done(true) end
		C_Timer.After(0, Step)
	end
	Step()
end

-- shows / hides each kind; builds the ones turned on for the first time
-- (1.2.40) the old single "Profession trainers" box, on, turns every profession on once. The old key stays.
function mod.MigrateTownsfolk()
	local db = mod.db
	if not db or type(db.townsfolk) ~= "table" or db.townsfolkProfMigrated then return end
	if db.townsfolk.profTrainer then
		for _, key in ipairs(mod.PROFESSIONS) do db.townsfolk[key] = true end
	end
	db.townsfolkProfMigrated = true
end

function mod:RefreshTownsfolk()
	mod.MigrateTownsfolk()
	if mod.UpdateTownsfolkMinimap then mod:UpdateTownsfolkMinimap() end
	if not S.IsBuilt() then return end
	local master = self.db.townsfolkMaster and true or false
	local questieUp = _G.QuestieLoader ~= nil
	local todo = {}
	for _, k in ipairs(KINDS) do
		local on = master and self.db.townsfolk[k.key] and true or false
		if k.rare and not questieUp then on = false end   -- (rares stay on Questie; this pass does not invent them)
		if on and not built[k.key] then todo[#todo + 1] = k end
		local set = S.GetPinSet("tf_" .. k.key)
		if set then S.SetPinSetOn(set, on and true or false) end
	end
	-- one pass of townsfolk, then a later pass for rares (they read Questie, not our file)
	local rest = {}
	for _, k in ipairs(todo) do if not k.rare then rest[#rest + 1] = k end end
	if #rest > 0 then todo = rest end
	local forRare = todo[1] and todo[1].rare or false
	if #todo == 0 or building then return end
	-- no Questie at all (not just its database still loading): nothing to wait for
	if not mod.HasTownsfolk() then
		if not told then
			told = true
			ns:Print(ns.L["World map: townsfolk and rare mobs come from Questie's database. Install and enable Questie to see them."])
		end
		return
	end
	building = true
	for _, k in ipairs(todo) do built[k.key] = true end
	Build(todo, function(ok)
		building = false
		if not ok then
			-- Questie's database isn't ready yet (it loads after login), or a build failed: try again shortly
			for _, k in ipairs(todo) do
				built[k.key] = nil
				local set = S.GetPinSet("tf_" .. k.key)
				if set then S.ClearPinSet(set) end
			end
			tries = tries + 1
			if tries <= 12 then C_Timer.After(5, function() self:RefreshTownsfolk() end)
			else ns:Print(ns.L["World map: townsfolk and rares need Questie's database, which isn't available."]) end
			return
		end
		tries = 0
		self:RefreshTownsfolk()
	end, forRare)
end

-- Valhalla's own Forever file, in the shape Build already reads (Questie's fields).
local FLAGS = { vendor = 1, repair = 2, innkeeper = 4, banker = 8, auctioneer = 16, stable = 32,
	classTrainer = 64, food = 128, reagent = 256,
	alchemy = 512, blacksmithing = 1024, enchanting = 2048, engineering = 4096,
	herbalism = 8192, leatherworking = 16384, mining = 32768, skinning = 65536,
	tailoring = 131072, cooking = 262144, firstaid = 524288, fishing = 1048576 }
function mod.InstallTownsfolkData(data)
	local records = type(data) == "table" and data.records
	if type(records) ~= "table" then return end
	local byId, pointers, objects, spirit = {}, {}, {}, {}
	for _, r in ipairs(records) do
		if type(r) == "table" and type(r.id) == "number" and type(r.map) == "number"
			and type(r.x) == "number" and type(r.y) == "number" then
			if r.type == "mailbox" then
				local e = objects[r.id]
				if not e then
					e = { name = r.name or "Mailbox", faction = r.faction or "AH", spawns = {} }
					objects[r.id] = e
				end
				local list = e.spawns[r.map] or {}
				e.spawns[r.map] = list
				list[#list + 1] = { r.x, r.y }
			else
				local e = byId[r.id]
				if not e then
					e = { name = r.name or "?", sub = r.title, faction = r.faction or "AH",
						tag = r.trainerTag, icon = r.icon, flags = 0, spawns = {} }
					byId[r.id] = e
					pointers[r.id] = true
				end
				if r.icon == "repair" then e.icon = "repair" end
				local bitv = FLAGS[r.type]
				if bitv then e.flags = bit.bor(e.flags, bitv) end
				if r.type == "spirit" then spirit[r.id] = true end
				if r.trainerTag then e.tag = r.trainerTag end
				local list = e.spawns[r.map] or {}
				e.spawns[r.map] = list
				list[#list + 1] = { r.x, r.y }
			end
		end
	end
	for _, k in ipairs(KINDS) do
		if k.key == "spirit" then k.ids = spirit end
	end
	mod.SetTownsfolkProvider({
		db = {
			NPCPointers = pointers,
			npcFlags = { VENDOR = 1, REPAIR = 2, INNKEEPER = 4, BANKER = 8, AUCTIONEER = 16,
				STABLEMASTER = 32, TRAINER = 64, FOOD = 128, REAGENT = 256,
				ALCHEMY = 512, BLACKSMITHING = 1024, ENCHANTING = 2048, ENGINEERING = 4096,
				HERBALISM = 8192, LEATHERWORKING = 16384, MINING = 32768, SKINNING = 65536,
				TAILORING = 131072, COOKING = 262144, FIRSTAID = 524288, FISHING = 1048576 },
			QueryNPCSingle = function(id, field)
				local e = byId[id]
				if not e then return nil end
				if field == "name" then return e.name end
				if field == "subName" then return e.sub end
				if field == "npcFlags" then return e.flags end
				if field == "spawns" then return e.spawns end
				if field == "friendlyToFaction" then return e.faction or "" end
				if field == "trainerTag" then return e.tag end
				if field == "pinIcon" then return e.icon end
				if field == "rank" then return 0 end
			end,
			QueryObjectSingle = function(id, field)
				local e = objects[id]
				if not e then return nil end
				if field == "spawns" then return e.spawns end
				if field == "name" then return e.name end
			end,
		},
		zones = { GetUiMapIdByAreaId = function(_, id) return id end },
		mailboxes = function(fac)
			local out = {}
			for id, e in pairs(objects) do
				local f = e.faction or "AH"
				if f == "AH" or f == fac then out[#out + 1] = id end
			end
			return out
		end,
	})
end
if type(ns.TownsfolkData) == "table" then mod.InstallTownsfolkData(ns.TownsfolkData) end
