--------------------------------------------------------------------------------
-- AH Market > Craft (v0.4.1): the Top 10 crafts per profession by profit at the Auction House shown.
-- Recipes: each profession's whole list as the game gives it when its window opens (any character, kept for
-- the account), and Data/Forever/Recipes.lua's bundled recipe IDs for professions not opened yet. Only IDs are
-- bundled: the output, its quantity and the reagents always come from the game (C_TradeSkillUI.
-- GetRecipeSchematic, which answers with the profession window closed, learned or not).
-- Per craft: sell = the output's lowest buyout (no undercut) x its quantity, less the house's cut (5%, 15% at
-- a neutral house); cost = each reagent at the cheaper of the AH's lowest and a merchant you've visited (or,
-- with "owned", what you have counts free or at its vendor value). The deposit isn't taken off: the game
-- gives it back when the item sells (the tooltip shows it, estimated). A craft with a reagent nobody prices,
-- or whose output isn't listed, isn't ranked: it's listed under the Top 10 instead. Enchants and bind-on-
-- pickup outputs are skipped (they can't be sold on the AH).
-- Reading and ranking run a little each frame (a coroutine, 8 ms), cached until a scan or a setting changes.
--------------------------------------------------------------------------------

local _, ns = ...
local mod = ns:GetModule("invest")
local I = mod and mod.I
if not I then return end
local L = ns.L
local C = { ready = true }
I.Craft = C
local function S() return I.Scan end
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local function Now() return time and time() or 0 end
local function MS() return (debugprofilestop and debugprofilestop()) or Now() * 1000 end

C.SHOWN = 10                -- the Top 10
C.EVERY = 5                 -- recipes between looks at the clock (a recipe's read costs an unknown few us)
C.BUDGET = 8                -- ms a frame
C.DEPOSIT_RATE, C.DEPOSIT_MIN, C.DEPOSIT_HOURS = 0.15, 100, 24   -- (est.: the AH check's 3 samples fit vendor x 15% a 12 h, 100c at least)
-- the professions by their skill line (the game's IDs) and English name
C.SKILL = { [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering", [182] = "Herbalism",
	[165] = "Leatherworking", [186] = "Mining", [393] = "Skinning", [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid",
	[356] = "Fishing", [755] = "Jewelcrafting", [773] = "Inscription" }
C.BYNAME = {}
for id, name in pairs(C.SKILL) do C.BYNAME[name:lower()] = id end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local got = { pcall(fn, ...) }
	if not got[1] then return nil end
	return unpack(got, 2, table.maxn(got))
end

local function Split(s)
	local out = {}
	for id in tostring(s or ""):gmatch("%d+") do out[#out + 1] = tonumber(id) end
	return out
end

-- a profession's key: its skill line for a name the table knows, else the game's ID, else its name
function C.Key(id, name)
	local low = name and tostring(name):lower()
	local known = low and C.BYNAME[low]
	if not known and low then   -- (a name with more to it, "Classic Tailoring": the profession it names)
		for n, k in pairs(C.BYNAME) do if low:find(n, 1, true) then known = k break end end
	end
	if known then return known end
	id = tonumber(id)
	if id and id > 0 then return id end
	if name and name ~= "" then return name end
end

local function Store() local a = I.db.account a.recipes = type(a.recipes) == "table" and a.recipes or {} return a.recipes end
local function KnownStore() I.char.known = type(I.char.known) == "table" and I.char.known or {} return I.char.known end

--------------------------------------------------------------------------------
-- Recipes: the profession window's list (live), the bundled IDs
--------------------------------------------------------------------------------

C.lastRead = {}
-- a profession window is open: all its recipes (learned or not) for the account, what this character knows
function C.ReadOpen(force)
	local T2 = C_TradeSkillUI
	if not T2 then return false end
	local base = Call(T2.GetBaseProfessionInfo)
	if type(base) ~= "table" then return false end
	local pid = (tonumber(base.parentProfessionID) or 0) > 0 and base.parentProfessionID or base.professionID
	local name = (base.parentProfessionName and base.parentProfessionName ~= "" and base.parentProfessionName) or base.professionName
	local key = C.Key(pid, name)
	if not key then return false end
	local ids = Call(T2.GetAllRecipeIDs)
	if type(ids) ~= "table" or #ids == 0 then return false end
	local all = {}
	for _, id in ipairs(ids) do id = tonumber(id) if id then all[#all + 1] = id end end
	table.sort(all)
	local s = table.concat(all, ",")
	local e = Store()[key]
	-- (the list updates in bursts: the same list within 3 s isn't read again; a longer one always is)
	if not force and e and e.ids == s and C.lastRead[key] and Now() - C.lastRead[key] < 3 then return false end
	local known = {}
	for _, id in ipairs(all) do
		local info = Call(T2.GetRecipeInfo, id)
		if type(info) == "table" and info.learned then known[#known + 1] = id end
	end
	C.lastRead[key] = Now()
	local ks = table.concat(known, ",")
	local changed = not e or e.ids ~= s or KnownStore()[key] ~= ks
	Store()[key] = { name = (name and name ~= "") and name or C.SKILL[key] or tostring(key), ids = s, t = Now() }
	KnownStore()[key] = ks
	if changed then C.results = {} I.Changed() end
	return true, key, #all, #known
end

-- the bundled IDs (Data/Forever/Recipes.lua): { [skill line] = { name, ids = "id,id,..." } }
function C.Bundled() return (ns.Recipes and ns.Recipes.professions) or {} end

-- every profession with recipes: { key, name, ids, source = "live" | "bundled" }, by name
function C.Professions()
	local byKey = {}
	for k, e in pairs(C.Bundled()) do
		local key = C.Key(k, e.name) or k
		byKey[key] = { key = key, name = e.name or C.SKILL[key] or tostring(key), ids = Split(e.ids), source = "bundled" }
	end
	for key, e in pairs(Store()) do
		local ids = Split(e.ids)
		if #ids > 0 then byKey[key] = { key = key, name = e.name or C.SKILL[key] or tostring(key), ids = ids, source = "live", t = e.t } end
	end
	local out = {}
	for _, p in pairs(byKey) do if #p.ids > 0 then out[#out + 1] = p end end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

function C.Profession(key) for _, p in ipairs(C.Professions()) do if p.key == key then return p end end end

-- this character knows it (from its profession windows)
function C.Known(key)
	local set = {}
	for _, id in ipairs(Split(KnownStore()[key])) do set[id] = true end
	return set
end

--------------------------------------------------------------------------------
-- One recipe, as the game tells it (cached for the session)
--------------------------------------------------------------------------------

C.schem = {}
function C.Resolve(id)
	local cached = C.schem[id]
	if cached ~= nil then return cached end
	local s = C_TradeSkillUI and Call(C_TradeSkillUI.GetRecipeSchematic, id, false)
	local r = false
	local enchant = Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Enchant
	local out = type(s) == "table" and tonumber(s.outputItemID)
	if type(s) == "table" and enchant and s.recipeType == enchant then
		r = { id = id, skip = "enchant" }   -- (no item to sell)
	elseif out and out > 0 then
		local qmin = tonumber(s.quantityMin) or 1
		local qmax = tonumber(s.quantityMax) or qmin
		local qty = (qmin + qmax) / 2
		if qty > 0 then
			local reagents, at = {}, {}
			for _, slot in ipairs(type(s.reagentSlotSchematics) == "table" and s.reagentSlotSchematics or {}) do
				local first = type(slot) == "table" and slot.required ~= false and type(slot.reagents) == "table" and slot.reagents[1]
				local rid = type(first) == "table" and tonumber(first.itemID)
				if rid then
					local n = tonumber(slot.quantityRequired) or 1
					if at[rid] then at[rid].n = at[rid].n + n
					else at[rid] = { id = rid, n = n } reagents[#reagents + 1] = at[rid] end
				end
			end
			r = { id = id, out = out, qty = qty, name = s.name, reagents = reagents }
		end
	end
	C.schem[id] = r
	return r
end

--------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------

-- a reagent's unit cost: the cheaper of the AH's lowest and a merchant you've visited (its price, "AH" / "vendor")
function C.Unit(house, id)
	local ah = S().Lowest(house, id)
	local v = I.VendorPrice and I.VendorPrice(id)
	v = v and v > 0 and v or nil
	if ah and (not v or ah <= v) then return ah, "ah" end
	if v then return v, "vendor" end
end

local function BindType(id)
	local got = { pcall(GetItemInfo, id) }
	return got[1] and got[15] or nil
end

-- what you have: bags (+ bank)
function C.Have(withBank)
	local have = {}
	for id, n in pairs(I.char.bags or {}) do have[id] = (have[id] or 0) + n end
	if withBank then for id, n in pairs(I.char.bank or {}) do have[id] = (have[id] or 0) + n end end
	return have
end

-- the deposit if the auction doesn't sell (est.: the game refunds it on a sale)
function C.Deposit(sch)
	local v = S().SellPrice(sch.out)
	if not v then return nil end
	return math.max(C.DEPOSIT_MIN, math.floor(v * sch.qty * C.DEPOSIT_RATE * C.DEPOSIT_HOURS / 12))
end

-- one craft at a house: { sell, net, cost, profit, each, margin, can, parts, missing } (sell nil: not listed)
function C.Price(house, sch, opts, have)
	local cut = S().Cut(house)
	local e = { id = sch.id, out = sch.out, qty = sch.qty, parts = {}, missing = {} }
	e.sell, e.c = S().Lowest(house, sch.out)
	e.listed = e.c and e.c.units or 0
	local cost, can = 0, nil
	for _, r in ipairs(sch.reagents) do
		local own = (opts.owned ~= "market") and math.min(r.n, have[r.id] or 0) or 0
		local buy = r.n - own
		local unit, src = C.Unit(house, r.id)
		local part = 0
		if own > 0 and opts.owned == "vendor" then part = own * (S().SellPrice(r.id) or 0) end
		if buy > 0 then
			if unit then part = part + buy * unit else e.missing[#e.missing + 1] = r.id end
		end
		cost = cost + part
		e.parts[#e.parts + 1] = { id = r.id, n = r.n, own = own, unit = unit, src = src, cost = part }
		local k = math.floor((have[r.id] or 0) / r.n)
		can = can and math.min(can, k) or k
	end
	e.can = can or 0
	e.cost = cost
	if e.sell then
		e.net = e.sell * sch.qty * (1 - cut)
		e.profit = e.net - cost
		e.each = e.profit / sch.qty
		e.margin = cost > 0 and e.profit / cost or nil
	end
	return e
end

-- a profession ranked at a house: { rows (the Top 10), missing, unlisted, skipped, unknown, total, known }
function C.Rank(house, key, opts, step)
	local p = C.Profession(key)
	local res = { rows = {}, missing = {}, unlisted = {}, skipped = 0, unknown = 0, total = 0, house = house, key = key }
	if not p then return res end
	local known = C.Known(key)
	local have = C.Have(opts.bank)
	local ranked = {}
	for i, id in ipairs(p.ids) do
		local sch = C.Resolve(id)
		if not sch then
			res.unknown = res.unknown + 1
		elseif sch.skip then
			res.skipped = res.skipped + 1
		elseif opts.knownOnly and not known[id] then
			-- (not this character's)
		elseif BindType(sch.out) == 1 then
			res.skipped = res.skipped + 1
		else
			res.total = res.total + 1
			local e = C.Price(house, sch, opts, have)
			e.known = known[id] or false
			if not e.sell then res.unlisted[#res.unlisted + 1] = e
			elseif #e.missing > 0 then res.missing[#res.missing + 1] = e
			else ranked[#ranked + 1] = e end
		end
		if step and i % C.EVERY == 0 then step(i, #p.ids) end
	end
	table.sort(ranked, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return a.id < b.id end)
	for i = 1, math.min(C.SHOWN, #ranked) do res.rows[i] = ranked[i] end
	res.ranked = #ranked
	return res
end

-- under a craft row's tooltip: the reagents, the cut, the sale, the deposit
function C.Lines(e, house)
	local Money, out = S().Money, {}
	local function Name(id) return (I.Views and I.Views.ItemData(id)) or L["Item #%d"]:format(id) end
	out[#out + 1] = L["Valhalla craft (%s): %s per craft (makes %s)"]:format(house, e.profit and Money(e.profit) or "-", tostring(e.qty))
	for _, r in ipairs(e.parts) do
		local how = r.own > 0 and (I.S.craftOwned == "vendor" and L["%d yours at vendor value"] or L["%d yours, free"]):format(r.own) or nil
		local buy = r.n - r.own
		local price = buy > 0 and (r.unit and L["%d x %s (%s)"]:format(buy, Money(r.unit), r.src == "vendor" and L["vendor"] or L["AH"]) or L["%d x no price"]:format(buy)) or nil
		local said = {}
		if how then said[#said + 1] = how end
		if price then said[#said + 1] = price end
		out[#out + 1] = ("  %s: %s = %s"):format(Name(r.id), table.concat(said, ", "), Money(r.cost))
	end
	if e.sell then
		out[#out + 1] = L["Sells at %s each x %s, less the %d%% cut: %s"]:format(Money(e.sell), tostring(e.qty), math.floor(S().Cut(house) * 100 + 0.5), Money(e.net))
	end
	local dep = C.Deposit({ out = e.out, qty = e.qty })
	out[#out + 1] = L["Deposit if unsold (est., 24 h): %s. Refunded when it sells, so not taken off the profit."]:format(dep and Money(dep) or "?")
	return out
end

--------------------------------------------------------------------------------
-- The work: read and rank a little each frame
--------------------------------------------------------------------------------

C.results = {}
local driver

function C.CacheKey(house, key, opts)
	local m = S().Market(house)
	local p = C.Profession(key)
	local own = opts.owned ~= "market" and ("%s:%s"):format(tostring(I.char.bagsSeen), opts.bank and tostring(I.char.bankSeen) or "-") or ""
	return ("%s|%s|%d|%s|%s|%s|%d|%s|%s"):format(tostring(house), tostring(key), m and #m.scans or 0, tostring(opts.owned), tostring(opts.bank),
		tostring(opts.knownOnly), p and #p.ids or 0, own, tostring(KnownStore()[key] and #KnownStore()[key] or 0))
end

function C.Tick()
	local job = C.job
	if not job then return end
	job.frameStart = MS()
	local ok, err = coroutine.resume(job.co)
	local spent = MS() - job.frameStart
	if spent > job.maxMs then job.maxMs = spent end
	if not ok or coroutine.status(job.co) == "dead" then
		C.job = nil
		if driver then driver:SetScript("OnUpdate", nil) end
		if not ok then
			C.lastError = tostring(err)
			if geterrorhandler then geterrorhandler()(err) end
		else
			C.results[job.cacheKey] = job.res
			C.last = { maxMs = job.maxMs, frames = job.frames }
		end
		I.Changed()
	else
		job.frames = job.frames + 1
	end
end

-- the ranking for a profession at a house: the cached one, else it's worked out (nil, "reading i/n")
function C.Get(house, key, opts)
	local ck = C.CacheKey(house, key, opts)
	local res = C.results[ck]
	if res then return res end
	if C.job and C.job.cacheKey == ck then return nil, C.job.done, C.job.of end
	local job = { cacheKey = ck, maxMs = 0, frames = 0, done = 0, of = 0 }
	job.co = coroutine.create(function()
		job.res = C.Rank(house, key, opts, function(i, n)
			job.done, job.of = i, n
			if MS() - job.frameStart > C.BUDGET then coroutine.yield() end
		end)
	end)
	C.job = job
	if CreateFrame then
		if not driver then driver = CreateFrame("Frame") end
		driver:SetScript("OnUpdate", C.Tick)
	end
	return nil, 0, 0
end

function C.Running() return C.job ~= nil end
