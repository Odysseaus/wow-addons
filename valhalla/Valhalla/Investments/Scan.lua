--------------------------------------------------------------------------------
-- The Auction House scanner (v0.4.0): AH Market's prices, from scans you start at the Auction House
-- (the Scan button on Valhalla's list beside it). Read only: nothing is posted, bid or bought.
--
-- Full scan: the game's whole-market copy (C_AuctionHouse.ReplicateItems: one every 15 minutes, account-
-- wide). Read 50 auctions at a time, a few ms per frame (8 by default), so the game never stalls. For each
-- item it keeps the lowest buyout per unit, the units and the auctions listed. If the Auction House closes
-- while it's read, nothing is kept (a partial market would look like prices vanished).
-- Quick scan (while the full scan's 15 minutes run): your own items only (the active list, bags and bank,
-- what AH Market shows), 100 per search (SearchForItemKeys), each search sent when the game says it's
-- ready. It gives the lowest price and units (no auction count).
-- One request at a time, and only it listens: its events are registered while it runs and dropped the
-- moment they're answered (the full scan's update event also fires once per item loaded afterwards).
-- Each house (Alliance, Horde, Neutral) is its own market. History: one point per item per hour (the
-- latest wins), 7 days, at most 3 MB (the oldest scans dropped first).
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local mod = ns:GetModule("invest")
local I = mod.I
local S = {}
I.Scan = S

S.COOLDOWN = 900                                  -- (the full scan: one every 15 minutes, account-wide)
S.CHUNK = 50                                      -- auctions read between clock checks
S.STORE_CHUNK = 200                               -- items stored between clock checks
S.BATCH = 100                                     -- item keys per quick search
S.MAX_INTEREST = 600
S.MORE = 5                                        -- (a quick search's "more results" asked at most this often)
S.TIMEOUT = { replicate = 45, browse = 10, throttle = 10 }
S.SPEEDS = { smooth = 4, balanced = 8, fast = 12 }
S.SLOT = 60                                       -- history: one point per item per this many minutes
S.CUT = { Neutral = 0.15 }                        -- the AH's cut (faction houses 5 %)
S.CUT_DEFAULT = 0.05

local Call = I.Call
local Value = ns.Safe and ns.Safe.Value or function(v) return v end
local function Now() return time and time() or 0 end
local function T() return (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and debugprofilestop() / 1000) or Now() end
local function MS() return (debugprofilestop and debugprofilestop()) or T() * 1000 end
local ABORT = {}

--------------------------------------------------------------------------------
-- Markets: ValhallaInvestDB.realms[realm].ah[house] = { base, scans = { {t, kind, n, items, secs, ms} },
--   cur = { [id] = "min,units,auctions,t" }, hist = { [id] = "t:min:units:auctions;..." } }
-- (t: minutes since base; a quick point's auctions is "q"; min 0 = none listed)
--------------------------------------------------------------------------------

function S.Houses()
	local r = I.realm
	r.ah = type(r.ah) == "table" and r.ah or {}
	return r.ah
end

function S.Market(house, make)
	local all = S.Houses()
	local m = all[house]
	if not m and make then
		m = { base = math.floor(Now() / 60), scans = {}, cur = {}, hist = {} }
		all[house] = m
	end
	return m
end

function S.HouseNames()
	local out = {}
	for h, m in pairs(S.Houses()) do if type(m) == "table" and next(m.cur or {}) then out[#out + 1] = h end end
	table.sort(out)
	return out
end

-- where the AH is now (the AH check's detection: faction, or Neutral at Booty Bay, Gadgetzan, Everlook)
function S.House()
	local h = I.AHCheck and I.AHCheck.House and I.AHCheck.House() or {}
	return h.house or "?", h
end

function S.Cut(house) return S.CUT[house] or S.CUT_DEFAULT end

local function Min(m, t) return math.floor(t / 60) - m.base end
function S.AbsTime(m, tmin) return (m.base + tmin) * 60 end

-- a stored line back as numbers
function S.Cur(house, id)
	local m = S.Market(house)
	local s = m and m.cur[id]
	if not s then return nil end
	local min, units, auctions, t = s:match("^(%d+),(%d+),([%dq]+),(%-?%d+)$")
	return { min = tonumber(min), units = tonumber(units), auctions = tonumber(auctions), quick = auctions == "q", t = S.AbsTime(m, tonumber(t)) }
end

function S.Points(house, id)
	local m = S.Market(house)
	local s = m and m.hist[id]
	local out = {}
	if not s then return out end
	for t, min, units, auctions in s:gmatch("(%-?%d+):(%d+):(%d+):([%dq]+)") do
		out[#out + 1] = { t = S.AbsTime(m, tonumber(t)), tmin = tonumber(t), min = tonumber(min), units = tonumber(units),
			auctions = tonumber(auctions), quick = auctions == "q" }
	end
	return out
end

-- one point into an item's history: a point in the same hour replaces the last one (the latest wins)
local function AddPoint(m, id, tmin, min, units, auctions)
	local p = ("%d:%d:%d:%s"):format(tmin, min, units, tostring(auctions))
	local s = m.hist[id]
	if not s or s == "" then m.hist[id] = p return end
	local head, last = s:match("^(.*);([^;]+)$")
	if not last then head, last = nil, s end
	local lt = tonumber(last:match("^(%-?%d+):"))
	if lt and math.floor(lt / S.SLOT) == math.floor(tmin / S.SLOT) then
		m.hist[id] = head and (head .. ";" .. p) or p
	else
		m.hist[id] = s .. ";" .. p
	end
end
S.AddPoint = AddPoint

-- the size of a house's saved market (bytes, about what SavedVariables writes)
function S.Size(m)
	if not m then return 0 end
	local n = 0
	for _, s in pairs(m.cur) do n = n + #s + 14 end
	for _, s in pairs(m.hist) do n = n + #s + 14 end
	n = n + #m.scans * 60
	return n
end

function S.TotalSize()
	local n = 0
	for _, m in pairs(S.Houses()) do n = n + S.Size(m) end
	return n
end

-- drop the points older than t (minutes since base) from every item
local function DropBefore(m, tmin)
	-- (points are in time order: only the front of each line is cut)
	for id, s in pairs(m.hist) do
		local pt = tonumber(s:match("^(%-?%d+):"))
		while pt and pt < tmin do
			local k = s:find(";", 1, true)
			if not k then s = nil break end
			s = s:sub(k + 1)
			pt = tonumber(s:match("^(%-?%d+):"))
		end
		m.hist[id] = s
	end
	local scans = {}
	for _, sc in ipairs(m.scans) do if sc.t >= tmin then scans[#scans + 1] = sc end end
	m.scans = scans
end

-- 7 days (Settings: 1-7), then the size cap (3 MB over all houses: the oldest scans go first)
function S.Prune(m)
	local days = math.max(1, math.min(7, tonumber(I.S.histDays) or 7))
	local cutoff = Min(m, Now() - days * 86400)
	if m.scans[1] and m.scans[1].t < cutoff then DropBefore(m, cutoff) end
	local cap = (tonumber(I.S.histCapMB) or 3) * 1024 * 1024
	local guard = 0
	while S.TotalSize() > cap and #m.scans > 1 and guard < 500 do
		guard = guard + 1
		DropBefore(m, m.scans[2].t)
	end
end

function S.PruneAll()
	for _, m in pairs(S.Houses()) do if type(m) == "table" and m.hist then S.Prune(m) end end
end

--------------------------------------------------------------------------------
-- The cooldown
--------------------------------------------------------------------------------

function S.NextFull()
	local at = I.db and I.db.account.replicateAt
	if not at then return 0 end
	return math.max(0, at + S.COOLDOWN - Now())
end

function S.Clock(secs)
	secs = math.max(0, math.floor(secs or 0))
	return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

function S.CooldownText()
	local left = S.NextFull()
	if left <= 0 then return L["Full scan ready."] end
	return L["Next full scan in %s."]:format(S.Clock(left))
end

--------------------------------------------------------------------------------
-- The one request, and only its listener
--------------------------------------------------------------------------------

local listener, driver
local function Listen(events)
	if not listener then
		listener = CreateFrame("Frame")
		listener:SetScript("OnEvent", function(_, event, ...) local r = S.run if r and r.OnEvent then r.OnEvent(event, ...) end end)
	end
	listener:UnregisterAllEvents()
	for _, e in ipairs(events or {}) do pcall(listener.RegisterEvent, listener, e) end
end
local function Unlisten() if listener then listener:UnregisterAllEvents() end end
S.Listener = function() return listener end

local function Yield() coroutine.yield() end
local function Budget() return S.SPEEDS[I.S.scanSpeed or "balanced"] or 8 end
local function Spent(r) return MS() - r.frameStart > Budget() end

local function Wait(r, cond, timeout)
	local t = T()
	while true do
		if not I.ahOpen then error(ABORT) end
		if cond() then return true end
		if T() - t > timeout then return false end
		Yield()
	end
end

-- the AH's throttle: wait until it takes another message
local function Ready(r)
	return Wait(r, function() return Call(C_AuctionHouse.IsThrottledMessageSystemReady) ~= false end, S.TIMEOUT.throttle)
end

-- full scan: ask, wait for the answer (its event, once), read, store
local function Full(r)
	local A = C_AuctionHouse
	r.phase = "wait"
	Listen({ "REPLICATE_ITEM_LIST_UPDATE" })
	r.OnEvent = function(event) if event == "REPLICATE_ITEM_LIST_UPDATE" then r.answered = true Unlisten() end end
	r.askedAt = T()
	Call(A.ReplicateItems)
	I.Changed()
	if not Wait(r, function() return r.answered end, S.TIMEOUT.replicate) then
		Unlisten()
		r.fail = L["The Auction House didn't answer the full scan (its 15-minute cooldown may still be running). Nothing saved. Press Scan for a quick scan."]
		return
	end
	r.answerSecs = T() - r.askedAt
	I.db.account.replicateAt = Now()                -- (the 15 minutes start: whatever happens next)
	r.phase = "read"
	local n = Call(A.GetNumReplicateItems) or 0
	r.count, r.readAt = n, 0
	local Get = A.GetReplicateItemInfo
	local per, items = {}, 0
	local i = 0
	while i < n do
		local last = math.min(n - 1, i + S.CHUNK - 1)
		for k = i, last do
			local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(Get, k)
			if ok then
				itemID, count, buyout = Value(itemID), Value(count) or 0, Value(buyout) or 0
				if itemID then
					local e = per[itemID]
					if not e then e = { 0, 0, 0 } per[itemID] = e items = items + 1 end   -- min, units, auctions
					e[3] = e[3] + 1
					e[2] = e[2] + count
					if buyout > 0 and count > 0 then
						local unit = math.floor(buyout / count)
						if e[1] == 0 or unit < e[1] then e[1] = unit end
					end
				end
			end
		end
		i = last + 1
		r.readAt = i
		if i < n and Spent(r) then
			Yield()
			if not I.ahOpen then error(ABORT) end
		end
	end
	-- store (the AH may close now: what was read is whole)
	r.phase, r.items = "store", items
	local m = S.Market(r.house, true)
	local now = Now()
	local tmin = Min(m, now)
	local cur, stored = {}, 0
	for id, e in pairs(per) do
		cur[id] = ("%d,%d,%d,%d"):format(e[1], e[2], e[3], tmin)
		AddPoint(m, id, tmin, e[1], e[2], e[3])
		stored = stored + 1
		r.storedAt = stored
		if stored % S.STORE_CHUNK == 0 and Spent(r) then r.storing = true Yield() end
	end
	r.storing = nil
	-- now: what this scan saw (an item not in it isn't listed any more)
	m.cur = cur
	m.scans[#m.scans + 1] = { t = tmin, kind = "full", n = n, items = items, secs = math.floor((T() - r.t0) * 10 + 0.5) / 10, ms = math.floor(r.maxMs * 10 + 0.5) / 10 }
	S.Prune(m)
	-- Top 10 worked out here too, a little each frame (reading 7 days of every item is the costly part)
	r.phase = "trend"
	S.TrendingAll(r.house, function() if Spent(r) then Yield() end end)
	r.done = L["Full scan done: %d auctions of %d items (%s). %s"]:format(n, items, r.house, S.CooldownText())
end

-- quick scan: the items you care about, 100 per search, paced by the AH's throttle
function S.Interest(house)
	local seen, out = {}, {}
	local function Add(id) id = tonumber(id) if id and not seen[id] and #out < S.MAX_INTEREST then seen[id] = true out[#out + 1] = id end end
	local l = I.ActiveList and I.ActiveList()
	for _, e in ipairs(l and l.items or {}) do Add(e.id) end
	for id in pairs(I.char.bags or {}) do Add(id) end
	if I.S.countBank ~= false then for id in pairs(I.char.bank or {}) do Add(id) end end
	for _, id in ipairs(S.shown or {}) do Add(id) end
	table.sort(out, function(a, b) return a < b end)
	return out
end

local SORTS = { { sortOrder = 0, reverseSort = false } }
local function Key(id)
	local k = C_AuctionHouse.MakeItemKey and Call(C_AuctionHouse.MakeItemKey, id)
	return type(k) == "table" and k or { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

local function Quick(r)
	local A = C_AuctionHouse
	local ids = S.Interest(r.house)
	r.phase, r.total, r.batch = "quick", #ids, 0
	r.batches = math.ceil(#ids / S.BATCH)
	if #ids == 0 then r.fail = L["Quick scan: nothing to look up (no shopping list, nothing in your bags or bank)."] return end
	local got = {}
	for b = 1, r.batches do
		r.batch = b
		if not Ready(r) then r.fail = L["Quick scan stopped: the Auction House stayed busy. Nothing saved."] Unlisten() return end
		local keys = {}
		for k = (b - 1) * S.BATCH + 1, math.min(#ids, b * S.BATCH) do keys[#keys + 1] = Key(ids[k]) end
		local answered, failed = false, false
		Listen({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_FAILURE" })
		r.OnEvent = function(event)
			if event == "AUCTION_HOUSE_BROWSE_FAILURE" then failed = true end
			answered = true
		end
		r.sent = (r.sent or 0) + 1
		Call(A.SearchForItemKeys, keys, SORTS)
		local more = 0
		while true do
			if not Wait(r, function() return answered end, S.TIMEOUT.browse) or failed then
				Unlisten()
				r.fail = failed and L["Quick scan stopped: the Auction House refused a search. Nothing saved."] or L["Quick scan stopped: no answer from the Auction House. Nothing saved."]
				return
			end
			if Call(A.HasFullBrowseResults) ~= false or more >= S.MORE then break end
			more = more + 1
			answered = false
			r.more = (r.more or 0) + 1
			Call(A.RequestMoreBrowseResults)
		end
		Unlisten()
		local res = Call(A.GetBrowseResults)
		for _, x in ipairs(type(res) == "table" and res or {}) do
			local id = type(x.itemKey) == "table" and Value(x.itemKey.itemID)
			if id then got[id] = { Value(x.minPrice) or 0, Value(x.totalQuantity) or 0 } end
		end
	end
	-- store: what answered, and "none listed" for the rest
	r.phase = "store"
	local m = S.Market(r.house, true)
	local tmin = Min(m, Now())
	local priced = 0
	for _, id in ipairs(ids) do
		local e = got[id] or { 0, 0 }
		if e[1] > 0 then priced = priced + 1 end
		m.cur[id] = ("%d,%d,q,%d"):format(e[1], e[2], tmin)
		AddPoint(m, id, tmin, e[1], e[2], "q")
	end
	m.scans[#m.scans + 1] = { t = tmin, kind = "quick", n = #ids, items = priced, secs = math.floor((T() - r.t0) * 10 + 0.5) / 10 }
	S.Prune(m)
	r.done = L["Quick scan done: %d of your %d items listed (%s). %s"]:format(priced, #ids, r.house, S.CooldownText())
end

local function Finish(r, state, text)
	if S.run ~= r then return end
	S.run = nil
	Unlisten()
	if driver then driver:SetScript("OnUpdate", nil) end
	r.state = state
	S.last = { kind = r.kind, state = state, text = text, at = Now() }
	if text then ns:Print("%s", text) end
	I.Changed()
end

local function Tick()
	local r = S.run
	if not r then return end
	if InCombatLockdown and InCombatLockdown() then return end
	r.frameStart = MS()
	local ok, err = coroutine.resume(r.co, r)
	local spent = MS() - r.frameStart
	if spent > r.maxMs then r.maxMs = spent end
	if not ok then
		if err == ABORT then
			Finish(r, "closed", r.kind == "full" and L["Full scan stopped: the Auction House closed. Nothing saved. %s"]:format(S.CooldownText())
				or L["Quick scan stopped: the Auction House closed. Nothing saved."])
		else
			Finish(r, "error", L["Scan stopped by an error: %s. Nothing saved."]:format(tostring(err)))
		end
	elseif coroutine.status(r.co) == "dead" then
		if r.fail then Finish(r, "failed", r.fail) else Finish(r, "done", r.done) end
	end
end
S.Tick = Tick   -- (the tests drive it)

function S.Running() return S.run ~= nil end

-- Scan: a full scan when its 15 minutes are up, else a quick scan (kind forces one)
function S.Start(kind)
	if S.run then return false end
	if not I.ahOpen then ns:Print("%s", L["Scan: open the Auction House first (the Scan button is on Valhalla's list beside it)."]) return false end
	if I.AHCheck and I.AHCheck.Running() then ns:Print("%s", L["The AH check is running: wait for it (or /valhalla invest diag stop)."]) return false end
	kind = kind or (S.NextFull() <= 0 and "full" or "quick")
	local house = S.House()
	local r = { kind = kind, house = house, t0 = T(), maxMs = 0, frameStart = MS() }
	r.co = coroutine.create(kind == "full" and Full or Quick)
	S.run = r
	if not driver then driver = CreateFrame("Frame") end
	driver:SetScript("OnUpdate", Tick)
	ns:Print("%s", kind == "full" and L["Full scan started (%s): keep the Auction House open, about 15 seconds."]:format(house)
		or L["Quick scan started (%s): your items, %s"]:format(house, S.CooldownText()))
	I.Changed()
	return true
end

function S.Stop()
	local r = S.run
	if r then Finish(r, "stopped", r.kind == "full" and L["Full scan stopped. Nothing saved. %s"]:format(S.CooldownText()) or L["Quick scan stopped. Nothing saved."]) end
end

function S.Toggle() if S.run then S.Stop() else S.Start() end end

-- how far: fraction 0-1 and a line for the button's status
function S.Progress()
	local r = S.run
	if not r then return nil end
	if r.kind == "full" then
		if r.phase == "wait" then
			local f = math.min(0.6, (T() - r.askedAt) / 8 * 0.6)
			return 0.02 + f * 0.1 / 0.6, L["Waiting for the Auction House..."]
		elseif r.phase == "read" then
			local f = (r.count or 0) > 0 and r.readAt / r.count or 0
			return 0.1 + 0.8 * f, L["Reading %d / %d"]:format(r.readAt or 0, r.count or 0)
		elseif r.phase == "trend" then
			return 0.98, L["Working out the Top 10..."]
		else
			local f = (r.items or 0) > 0 and (r.storedAt or 0) / r.items or 1
			return 0.9 + 0.08 * f, L["Saving %d items..."]:format(r.items or 0)
		end
	end
	local f = (r.batches or 0) > 0 and math.max(0, (r.batch or 1) - 1) / r.batches or 0
	return f, L["Quick scan: search %d of %d"]:format(r.batch or 0, r.batches or 0)
end

-- the AH closing: the coroutine notices on its next step; the listener stops at once
function S.OnAHClosed() if S.run then Unlisten() Tick() end end

--------------------------------------------------------------------------------
-- What AH Market reads: the lowest price (dump filter optional), the trend, vendor vs AH
--------------------------------------------------------------------------------

local function Median(t)
	if #t == 0 then return nil end
	table.sort(t)
	local n = #t
	if n % 2 == 1 then return t[(n + 1) / 2] end
	return (t[n / 2] + t[n / 2 + 1]) / 2
end
S.Median = Median

-- the 7-day median of an item's lowest prices (listed points only)
function S.Median7(house, id)
	local mins = {}
	local from = Now() - 7 * 86400
	for _, p in ipairs(S.Points(house, id)) do if p.t >= from and p.min > 0 then mins[#mins + 1] = p.min end end
	return Median(mins), #mins
end

-- the lowest buyout now; with the dump filter on, a lowest below 30 % of the 7-day median is ignored
function S.Lowest(house, id)
	local c = S.Cur(house, id)
	if not c or c.min <= 0 then return nil, c end
	if I.S.dumpFilter then
		local med, n = S.Median7(house, id)
		if med and n >= 3 and c.min < 0.3 * med then return math.floor(med), c, true end
	end
	return c.min, c
end

-- trending: items in at least 3 full scans of the last 7 days. The window (from your first scan in it to
-- now) is cut in two halves; change = the median lowest price of the second half against the first's.
-- Ties: the change in auctions listed.
S.trendCache = {}
-- (v0.4.2.3) the full sorted lists are kept (cached per house and scan); a caller filters them, then takes its top
-- max (the Top 10 filter: profession, crafted or harvested, level). S.Trending gives the first max (10 if none).
function S.TrendingAll(house, step)
	local m = S.Market(house)
	if not m then return {}, {}, 0 end
	local last = m.scans[#m.scans]
	local key = ("%d:%s:%s"):format(#m.scans, last and last.t or "-", tostring(I.S.histDays))
	local c = S.trendCache[house]
	if c and c.key == key and c.m == m then return c.rising, c.falling, c.fulls, c.nextAt end
	local rising, falling, fulls, nextAt = S.TrendingNow(house, nil, step)
	S.trendCache[house] = { key = key, m = m, rising = rising, falling = falling, fulls = fulls, nextAt = nextAt }
	return rising, falling, fulls, nextAt
end
local function Head(list, max)
	local out = {}
	for i = 1, math.min(#list, max) do out[i] = list[i] end
	return out
end
function S.Trending(house, max, step)
	local rising, falling, fulls, nextAt = S.TrendingAll(house, step)
	max = max or 10
	return Head(rising, max), Head(falling, max), fulls, nextAt
end

function S.TrendingNow(house, max, step)
	local m = S.Market(house)
	local rising, falling = {}, {}
	local now = Now()
	local from = now - 7 * 86400
	local first
	-- (v0.4.1.1) fulls: the hours with a full scan, not the scans: history keeps one point an hour (S.SLOT), so two
	-- scans in one hour are one point. nextAt: when the next full scan starts a new hour (a new point).
	local fulls, hours, last = 0, {}, nil
	for _, sc in ipairs(m.scans) do
		local t = S.AbsTime(m, sc.t)
		if sc.kind == "full" and t >= from then
			local h = math.floor(sc.t / S.SLOT)
			if not hours[h] then hours[h] = true fulls = fulls + 1 end
			if not last or h > last then last = h end
			if not first or t < first then first = t end
		end
	end
	local nextAt = last and S.AbsTime(m, (last + 1) * S.SLOT) or nil
	if fulls < 3 then return rising, falling, fulls, nextAt end
	local mid = (first + now) / 2
	local k = 0
	for id in pairs(m.hist) do
		k = k + 1
		if step and k % 100 == 0 then step() end
		local a, b, aa, ba, n = {}, {}, {}, {}, 0
		for _, p in ipairs(S.Points(house, id)) do
			if not p.quick and p.t >= from and p.min > 0 then
				n = n + 1
				if p.t < mid then a[#a + 1] = p.min aa[#aa + 1] = p.auctions else b[#b + 1] = p.min ba[#ba + 1] = p.auctions end
			end
		end
		if n >= 3 and #a > 0 and #b > 0 then
			local ma, mb = Median(a), Median(b)
			local change = (mb - ma) / ma
			local e = { id = id, change = change, before = ma, now = mb, auctions = (Median(ba) or 0) - (Median(aa) or 0), points = n }
			if change > 0 then rising[#rising + 1] = e elseif change < 0 then falling[#falling + 1] = e end
		end
	end
	table.sort(rising, function(x, y) if x.change ~= y.change then return x.change > y.change end if x.auctions ~= y.auctions then return x.auctions > y.auctions end return x.id < y.id end)
	table.sort(falling, function(x, y) if x.change ~= y.change then return x.change < y.change end if x.auctions ~= y.auctions then return x.auctions < y.auctions end return x.id < y.id end)
	if max then   -- (none: the full lists)
		for k = #rising, max + 1, -1 do rising[k] = nil end
		for k = #falling, max + 1, -1 do falling[k] = nil end
	end
	return rising, falling, fulls, nextAt
end

-- an item's vendor price (what a merchant pays you): the game's sellPrice
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
function S.SellPrice(id)
	local got = { pcall(GetItemInfo, id) }
	if not got[1] or got[2] == nil then return nil end
	return Value(got[12])
end

-- bags (+ bank): each item, vendor vs the AH's lowest after the cut, the better of the two
function S.Mine(house, withBank)
	local counts = {}
	for id, n in pairs(I.char.bags or {}) do counts[id] = (counts[id] or 0) + n end
	if withBank then for id, n in pairs(I.char.bank or {}) do counts[id] = (counts[id] or 0) + n end end
	local rows, totals = {}, { vendor = 0, ah = 0, best = 0 }
	local cut = S.Cut(house)
	for id, n in pairs(counts) do
		local vendor = S.SellPrice(id)
		local low = S.Lowest(house, id)
		local net = low and math.floor(low * (1 - cut)) or nil
		local best = (net and (not vendor or net > vendor)) and "ah" or (vendor and vendor > 0) and "vendor" or nil
		local each = best == "ah" and net or best == "vendor" and vendor or 0
		rows[#rows + 1] = { id = id, n = n, vendor = vendor, ah = net, best = best, total = each * n }
		totals.vendor = totals.vendor + (vendor or 0) * n
		totals.ah = totals.ah + (net or 0) * n
		totals.best = totals.best + each * n
	end
	table.sort(rows, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.id < b.id end)
	return rows, totals
end

-- the last full scan's items (for Scan results), and its scan line
function S.LastScan(house, kind)
	local m = S.Market(house)
	if not m then return nil end
	for k = #m.scans, 1, -1 do if not kind or m.scans[k].kind == kind then return m.scans[k], S.AbsTime(m, m.scans[k].t) end end
end

function S.Forget(house)
	S.Houses()[house] = nil
	I.Changed()
end

-- copper as gold / silver / copper
function S.Money(c)
	if not c then return "-" end
	c = math.floor(c + 0.5)
	local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	if g > 0 then return ("%dg %02ds %02dc"):format(g, s, k) end
	if s > 0 then return ("%ds %02dc"):format(s, k) end
	return ("%dc"):format(k)
end

function S.Age(t)
	if not t then return L["never"] end
	local d = math.max(0, Now() - t)
	if d < 90 then return L["just now"] end
	if d < 3600 then return L["%d min ago"]:format(math.floor(d / 60)) end
	if d < 86400 then return L["%d h ago"]:format(math.floor(d / 3600)) end
	return L["%d days ago"]:format(math.floor(d / 86400))
end
