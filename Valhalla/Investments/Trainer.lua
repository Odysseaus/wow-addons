local _, ns = ...
local L = ns.L

--------------------------------------------------------------------------------
-- Profession trainers (1.2.0, 1.2.1): while a profession trainer's window is open, every recipe it teaches is read
-- with its required skill (GetTrainerServiceSkillReq) and the item it makes. The window's filters (available /
-- unavailable / used) are all turned on for each read, then set back as they were.
-- (1.2.1) Read when the window opens and again (once, half a second after the last) when its list or its recipe
-- names change (TRAINER_UPDATE, TRAINER_SERVICE_INFO_NAME_UPDATE) or an item name it waited for arrives; never for
-- the updates our own filter switching makes. The item: the service's item link; a spell or enchant link: what that
-- recipe makes (C_TradeSkillUI.GetRecipeSchematic); else the profession's item of the recipe's name (names not yet
-- loaded asked for, and read again when they come).
-- Saved account-wide: ValhallaInvestDB.trainer[<skill line>] = { items = { [itemID] = skill }, t, n,
--   last = { t, services, matched, unmatched = { names }, link = a sample link } } (what the last read saw).
-- Top 10's level filter takes these over the bundled Data/Forever/TopSkills.lua (Market.lua's M.TopSkill).
--------------------------------------------------------------------------------

local I = ns.Invest
local R = {}
I.Trainer = R
R.TYPES = { "available", "unavailable", "used" }
R.WAIT = 0.5          -- (seconds after the last update before reading again)
R.UNMATCHED_KEEP = 40
R.QUIET = 1           -- (seconds after a read when the window's updates are taken as our own filter switching)
R.MAX_READS = 6       -- (reads for one opening of the window, at most)

local function Now() return time and time() or 0 end

-- a skill's name (the trainer's "Requires Alchemy (90)") to its skill line
function R.ProfOf(name)
	if type(name) ~= "string" or name == "" then return nil end
	local C = I.Craft
	for id, n in pairs(C and C.SKILL or {}) do if n == name then return id end end
	local GetName = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
	if GetName then
		for id in pairs(C and C.SKILL or {}) do
			local ok, n = pcall(GetName, id)
			if ok and n == name then return id end
		end
	end
	return nil
end

-- what a recipe spell makes (nil: none, or the game doesn't say)
function R.SpellOutput(spellID)
	local Get = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
	if not (Get and spellID) then return nil end
	local ok, s = pcall(Get, spellID, false)
	return ok and type(s) == "table" and tonumber(s.outputItemID) or nil
end

-- the item a recipe makes. names: one index a read (made when needed); wait: item IDs whose names were asked for
function R.ItemOf(i, name, prof, names, wait)
	local link
	if GetTrainerServiceItemLink then
		local ok, l = pcall(GetTrainerServiceItemLink, i)
		link = ok and type(l) == "string" and l or nil
	end
	if link then
		local id = tonumber(link:match("item:(%d+)"))
		if id then return id, link end
		local spell = tonumber(link:match("spell:(%d+)") or link:match("enchant:(%d+)"))
		id = R.SpellOutput(spell)
		if id then return id, link end
	end
	if not (name and prof) then return nil, link end
	names = names or {}
	if not names[prof] then
		local idx = {}
		local C, V = I.Craft, I.Views
		local map = C and C.TopMap and C.TopMap("craft")
		for id in pairs(map and map[prof] or {}) do
			local n = V and V.ItemData and V.ItemData(id)
			if n then idx[n] = id
			elseif wait then
				wait[id] = true
				if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			end
		end
		names[prof] = idx
	end
	return names[prof][name], link
end

-- every service: { list = { { prof, id, skill, name } }, stats = { [prof] = { services, matched, unmatched, link } }, wait }
function R.Collect()
	local out, names, stats, wait = {}, {}, {}, {}
	for i = 1, GetNumTrainerServices() or 0 do
		local name, kind = GetTrainerServiceInfo(i)
		if kind ~= "header" then
			local skillName, rank
			if GetTrainerServiceSkillReq then skillName, rank = GetTrainerServiceSkillReq(i) end
			local prof = R.ProfOf(skillName)
			if not prof and GetTrainerServiceSkillLine then prof = R.ProfOf((GetTrainerServiceSkillLine(i))) end
			rank = tonumber(rank)
			if prof and rank then
				local st = stats[prof] or { services = 0, matched = 0, unmatched = {} }
				stats[prof] = st
				st.services = st.services + 1
				local id, link = R.ItemOf(i, name, prof, names, wait)
				st.link = st.link or link
				if id then
					st.matched = st.matched + 1
					out[#out + 1] = { prof = prof, id = id, skill = rank, name = name }
				elseif #st.unmatched < R.UNMATCHED_KEEP then
					st.unmatched[#st.unmatched + 1] = name or ("#" .. i)
				end
			end
		end
	end
	return { list = out, stats = stats, wait = wait }
end

-- read the open trainer: filters all on, read, filters back; saved. Returns the count read, the count new (nil: not read)
function R.Read()
	if R.reading then return nil end
	if not (I.db and GetNumTrainerServices and GetTrainerServiceInfo) then return nil end
	if IsTradeskillTrainer then
		local ok, yes = pcall(IsTradeskillTrainer)
		if ok and not yes then return nil end
	end
	R.reading = true
	local keep = {}
	local can = GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter
	if can then
		for _, t in ipairs(R.TYPES) do
			local ok, on = pcall(GetTrainerServiceTypeFilter, t)
			keep[t] = ok and on and true or false
			if not keep[t] then pcall(SetTrainerServiceTypeFilter, t, true) end
		end
	end
	local ok, res = pcall(R.Collect)
	if can then
		for _, t in ipairs(R.TYPES) do if not keep[t] then pcall(SetTrainerServiceTypeFilter, t, false) end end
	end
	R.reading = nil
	R.readAt = GetTime and GetTime() or 0
	R.openReads = (R.openReads or 0) + 1
	R.lastFilters = keep
	R.reads = (R.reads or 0) + 1
	if not ok or type(res) ~= "table" then return nil end
	R.wait = res.wait
	I.db.trainer = type(I.db.trainer) == "table" and I.db.trainer or {}
	local new, profs = 0, {}
	for prof, st in pairs(res.stats) do
		local p = I.db.trainer[prof]
		if type(p) ~= "table" then p = { items = {} } I.db.trainer[prof] = p end
		p.items = p.items or {}
		p.last = { t = Now(), services = st.services, matched = st.matched, unmatched = st.unmatched, link = st.link }
		profs[prof] = st
	end
	for _, e in ipairs(res.list) do
		local p = I.db.trainer[e.prof]
		if p.items[e.id] ~= e.skill then new = new + 1 end
		p.items[e.id] = e.skill
		p.t = Now()
	end
	for prof in pairs(profs) do
		local n = 0
		for _ in pairs(I.db.trainer[prof].items) do n = n + 1 end
		I.db.trainer[prof].n = n
	end
	if new > 0 then
		local C = I.Craft
		local names, miss = {}, 0
		for prof, st in pairs(profs) do names[#names + 1] = C and C.SKILL and C.SKILL[prof] or tostring(prof) miss = miss + (st.services - st.matched) end
		table.sort(names)
		ns:Print(L["Top 10: recorded %d skill levels from this %s trainer (%d not matched to an item; /valhalla invest trainer)."]:format(new, table.concat(names, "/"), miss))
		if I.Changed then I.Changed() end
	end
	return #res.list, new
end

-- read again soon (once, R.WAIT after the last call), while the trainer is open
function R.Soon()
	if not R.open or R.reading or (R.openReads or 0) >= R.MAX_READS then return end
	R.gen = (R.gen or 0) + 1
	local gen = R.gen
	if C_Timer and C_Timer.After then
		C_Timer.After(R.WAIT, function() if gen == R.gen and R.open then R.Read() end end)
	else
		R.Read()
	end
end

function R.OnEvent(event, a1)
	if event == "TRAINER_SHOW" then
		R.open, R.openReads = true, 0
		R.Read()
	elseif event == "TRAINER_CLOSED" then
		R.open, R.wait = nil, nil
		R.gen = (R.gen or 0) + 1
	elseif event == "TRAINER_UPDATE" or event == "TRAINER_SERVICE_INFO_NAME_UPDATE" then
		local now = GetTime and GetTime() or 0
		if R.open and not R.reading and not (R.readAt and now - R.readAt < R.QUIET) then R.Soon() end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if R.open and R.wait and a1 and R.wait[a1] then R.wait[a1] = nil R.Soon() end
	end
end

-- the recorded skill of the recipe making id (nil: none recorded)
function R.Skill(prof, id)
	local t = I.db and type(I.db.trainer) == "table" and I.db.trainer[prof]
	return t and t.items and t.items[id] or nil
end

-- /valhalla invest trainer: what each profession's trainers gave
function R.Report()
	local C = I.Craft
	local out = {}
	local profs = {}
	for prof in pairs(I.db and type(I.db.trainer) == "table" and I.db.trainer or {}) do profs[#profs + 1] = prof end
	table.sort(profs)
	if #profs == 0 then return { L["Top 10: no trainer read yet. Open a profession trainer once."] } end
	for _, prof in ipairs(profs) do
		local p = I.db.trainer[prof]
		local last = p.last or {}
		out[#out + 1] = L["%s: %d skill levels recorded. Last read: %d recipes, %d matched to an item."]:format(
			C and C.SKILL and C.SKILL[prof] or tostring(prof), p.n or 0, last.services or 0, last.matched or 0)
		if last.unmatched and #last.unmatched > 0 then out[#out + 1] = L["  Not matched: %s"]:format(table.concat(last.unmatched, ", ")) end
	end
	return out
end
