local _, ns = ...
local L = ns.L

--------------------------------------------------------------------------------
-- Profession trainers (1.2.0): when a profession trainer's window opens (TRAINER_SHOW), every recipe it teaches is
-- read with its required skill (GetTrainerServiceSkillReq) and the item it makes (GetTrainerServiceItemLink; else
-- the item of that profession with the recipe's name). The window's filters (available / unavailable / used) are
-- all turned on for the read, then set back as they were. Saved account-wide: ValhallaInvestDB.trainer[<skill
-- line>] = { items = { [itemID] = skill }, t = <time>, n = <count> }. Top 10's level filter takes these over the
-- bundled Data/Forever/TopSkills.lua (Market.lua's M.TopSkill).
--------------------------------------------------------------------------------

local I = ns.Invest
local R = {}
I.Trainer = R
R.TYPES = { "available", "unavailable", "used" }

local function Now() return time and time() or 0 end

-- a skill's name (the trainer's "Requires Alchemy (90)") to its skill line
function R.ProfOf(name)
	if type(name) ~= "string" or name == "" then return nil end
	local C = I.Craft
	for id, n in pairs(C and C.SKILL or {}) do if n == name then return id end end
	-- (another language: a name of the game's own, if it has one for the line)
	local GetName = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
	if GetName then
		for id in pairs(C and C.SKILL or {}) do
			local ok, n = pcall(GetName, id)
			if ok and n == name then return id end
		end
	end
	return nil
end

-- the item a recipe makes: its link, else the profession's item of that name (names: one index a read, made when needed)
function R.ItemOf(i, name, prof, names)
	if GetTrainerServiceItemLink then
		local ok, link = pcall(GetTrainerServiceItemLink, i)
		local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then return id end
	end
	if not (name and prof) then return nil end
	names = names or {}
	if not names[prof] then
		local idx = {}
		local C, V = I.Craft, I.Views
		local map = C and C.TopMap and C.TopMap("craft")
		for id in pairs(map and map[prof] or {}) do
			local n = V and V.ItemData and V.ItemData(id)
			if n then idx[n] = id end
		end
		names[prof] = idx
	end
	return names[prof][name]
end

-- every service with its skill: { { prof, id, skill, name } }
function R.Collect()
	local out, names = {}, {}
	for i = 1, GetNumTrainerServices() or 0 do
		local name, kind = GetTrainerServiceInfo(i)
		if kind ~= "header" and name then
			local skillName, rank
			if GetTrainerServiceSkillReq then skillName, rank = GetTrainerServiceSkillReq(i) end
			local prof = R.ProfOf(skillName)
			if not prof and GetTrainerServiceSkillLine then prof = R.ProfOf((GetTrainerServiceSkillLine(i))) end
			rank = tonumber(rank)
			if prof and rank then
				local id = R.ItemOf(i, name, prof, names)
				if id then out[#out + 1] = { prof = prof, id = id, skill = rank, name = name } end
			end
		end
	end
	return out
end

-- read the open trainer: filters all on, read, filters back; saved. Returns the count recorded (nil: not read)
function R.Read()
	if not (I.db and GetNumTrainerServices and GetTrainerServiceInfo) then return nil end
	if IsTradeskillTrainer then
		local ok, yes = pcall(IsTradeskillTrainer)
		if ok and not yes then return nil end
	end
	local keep = {}
	local can = GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter
	if can then
		for _, t in ipairs(R.TYPES) do
			local ok, on = pcall(GetTrainerServiceTypeFilter, t)
			keep[t] = ok and on and true or false
			if not keep[t] then pcall(SetTrainerServiceTypeFilter, t, true) end
		end
	end
	local ok, list = pcall(R.Collect)
	if can then
		for _, t in ipairs(R.TYPES) do if not keep[t] then pcall(SetTrainerServiceTypeFilter, t, false) end end
	end
	R.lastFilters = keep
	if not ok or type(list) ~= "table" then return nil end
	I.db.trainer = type(I.db.trainer) == "table" and I.db.trainer or {}
	local new, profs = 0, {}
	for _, e in ipairs(list) do
		local p = I.db.trainer[e.prof]
		if type(p) ~= "table" then p = { items = {} } I.db.trainer[e.prof] = p end
		p.items = p.items or {}
		if p.items[e.id] ~= e.skill then new = new + 1 end
		p.items[e.id] = e.skill
		p.t = Now()
		profs[e.prof] = true
	end
	for prof in pairs(profs) do
		local n = 0
		for _ in pairs(I.db.trainer[prof].items) do n = n + 1 end
		I.db.trainer[prof].n = n
	end
	if new > 0 then
		local C = I.Craft
		local names = {}
		for prof in pairs(profs) do names[#names + 1] = C and C.SKILL and C.SKILL[prof] or tostring(prof) end
		table.sort(names)
		ns:Print(L["Top 10: recorded %d skill levels from this %s trainer."]:format(new, table.concat(names, "/")))
		if I.Changed then I.Changed() end
	end
	return #list, new
end

-- the recorded skill of the recipe making id (nil: none recorded)
function R.Skill(prof, id)
	local t = I.db and type(I.db.trainer) == "table" and I.db.trainer[prof]
	return t and t.items and t.items[id] or nil
end
