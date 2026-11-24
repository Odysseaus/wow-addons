-- Box tests for the Watchlist (1.2.14, Investments/Watch.lua) (Lua 5.1): money parsing, the BUY / SELL / Near
-- signals, saved targets, the quick scan's items, the check after a full and a quick scan, alert frequency
-- (every scan while met | once until the target changes), the popup, the tooltip lines, the AH Market view,
-- the editor, the right-click menu and alt-click, and the TOC's load order.
-- Run: lua valhalla/tests/investments/watchlist_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
dofile(here .. "stubs.lua")

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")) end
end

print("== 1. load order: the TOC's Investments files, Watch.lua after Market.lua")
local toc = assert(io.open(root .. "Valhalla.toc")):read("*a")
local files = {}
for line in toc:gmatch("[^\r\n]+") do
  local f = line:match("^Investments\\(%w+)%.lua%s*$") or line:match("^(Data\\Forever\\%w+)%.lua%s*$")
  if f and (line:find("^Investments") or f:find("Recipes") or f:find("TopSkills")) then files[#files + 1] = f:gsub("\\", "/") end
end
local order = table.concat(files, ",")
ok(order == "Invest,Scan,Tabs,Views,Market,Watch,Tooltip,Data/Forever/Recipes,Data/Forever/TopSkills,Craft,Trainer,Merchant,AHPanel", "TOC: Watch.lua right after Market.lua, before Tooltip.lua", order)
ok(toc:find("## Version: 1.2.39", 1, true) ~= nil, "TOC: version 1.2.39")

local ns = { modules = {}, version = "v1.2.16", Media = { path = "Interface\\AddOns\\Valhalla\\Media\\" } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Safe = { Value = function(v) return v end }
ns.Look = { Font = function(_, fs, size) fs._size = size return fs end }
ns.printed = {}
function ns:Print(fmt, ...) ns.printed[#ns.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} if m.defaults.enabled == nil then m.defaults.enabled = true end self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
ns.modules.worldmap = { key = "worldmap", enabled = true }
function ns.modules.worldmap.TabAway(away) ns.modules.worldmap.away = away end
assert(loadfile(root .. "Util.lua"))("Valhalla", ns)   -- (1.2.26: the shared helpers, after Core.lua)
assert(loadfile(root .. "UI/Style.lua"))("Valhalla", ns)
assert(loadfile(root .. "Links.lua"))("Valhalla", ns)
for _, f in ipairs(files) do
  assert(loadfile(root .. (f:find("/") and f or ("Investments/" .. f)) .. ".lua"))("Valhalla", ns)   -- (the TOC's order)
end
local mod = ns:GetModule("invest")
local I = mod.I
local Wt, Mk, Sc, T, V, P = I.Watch, I.Market, I.Scan, I.Tabs, I.Views, I.Tooltip
ok(Wt and Mk.BUILD.watch == Wt.BuildView and Mk.TIP_ON.watch and Mk.COLS.watch, "loaded: I.Watch, AH Market's Watchlist view registered")
local subs = {} for _, s in ipairs(Mk.SUBS) do subs[#subs + 1] = s.key end
ok(table.concat(subs, ",") == "top,mine,history,results,craft,watch", "AH Market's views: Watchlist last", table.concat(subs, ","))

ValhallaInvestDB = nil
mod.db, mod.char, mod.enabled = { enabled = true }, {}, true
W.bags[0] = { { 2589, 12 }, { 2770, 30 }, size = 16 }
mod:OnEnable()
ok(I.S.watchSound == true and I.S.watchAlerts == "every" and I.S.watchNear == 5 and I.S.sortWatch == "signal:asc", "settings: sound on, every scan while met, Near 5%, sorted by Signal")

print("== 2. money: g/s/c (M.ParseMoney), a blank box is no target")
local PM = Mk.ParseMoney
ok(PM("1g 50s") == 15000 and PM("75s") == 7500 and PM("20c") == 20 and PM("1.5") == 15000 and PM("1g50s3c") == 15003 and PM("2g 5c") == 20005, "1g 50s, 75s, 20c, 1.5 (gold), 1g50s3c, 2g 5c")
ok(PM("abc") == nil and PM("0") == nil and PM("") == nil and PM("5x") == nil, "not prices: abc, 0, blank, 5x")
local FC, CT = Wt.FromCoins, Wt.CoinTexts
local v, good = FC("", " ", "")
local v2, good2 = FC("1", "", "")
local v3, good3 = FC("", "3", "4")
local v4, good4 = FC("", "150", "")
local v5, good5 = FC("1", "50", "3")
local v6, good6 = FC("", "", "250")
local v7, good7 = FC("2", "x", "")
ok(v == nil and good and v2 == 10000 and good2 and v3 == 304 and good3, "(1.2.15) the coin boxes: all blank = none; 1 gold (blanks are 0); 3s 4c = 304")
ok(v4 == 15000 and good4 and v5 == 15003 and good5 and v6 == 250 and good6 and v7 == nil and not good7, "150s carries to 1g 50s; 1g 50s 3c; 250c = 2s 50c; not a number refused")
local a1, b1, c1 = CT(15000)
local a2, b2, c2 = CT(1000)
local a3, b3, c3 = CT(nil)
local a4, b4, c4 = CT(1234567)
ok(a1 == "1" and b1 == "50" and c1 == "0" and a2 == "" and b2 == "10" and c2 == "0" and a3 == "" and b3 == "" and c3 == "" and a4 == "123" and b4 == "45" and c4 == "67",
  "a target split into the boxes (no gold: its box blank; none: all blank)")
ok(FC(CT(15003)) == 15003 and FC(CT(7)) == 7, "split and read back: itself")
ok(Sc.Money(15000) == "1g 50s 00c" and PM(Sc.Money(15000)) == 15000 and PM(Sc.Money(304)) == 304, "a saved target shown in the box parses back to itself")

print("== 3. signals: BUY at or below, SELL at or above (the listed price), Near x%")
local Sig = Wt.Signal
ok(Sig({ buy = 100 }, 100) == "buy" and Sig({ buy = 100 }, 99) == "buy" and Sig({ buy = 100 }, 101) == nil, "buy: equal or less is BUY")
ok(Sig({ sell = 500 }, 500) == "sell" and Sig({ sell = 500 }, 501) == "sell" and Sig({ sell = 500 }, 499) == nil, "sell: equal or more is SELL")
ok(Sig({ buy = 100, sell = 500 }, 300) == nil and Sig({ buy = 100, sell = 500 }, 90) == "buy" and Sig({ buy = 100, sell = 500 }, 600) == "sell", "both: between them nothing; below BUY; above SELL")
ok(Sig({ buy = 100 }, nil) == nil and Sig({ buy = 100 }, 0) == nil and Sig({}, 100) == nil and Sig(nil, 100) == nil, "no price (not listed, never scanned) or no targets: no signal")
local s1, p1, d1 = Sig({ buy = 100 }, 104, 5)
local s2 = Sig({ buy = 100 }, 106, 5)
local s3, p3, d3 = Sig({ buy = 100 }, 106, 10)
local s4, p4, d4 = Sig({ sell = 1000 }, 951, 5)
local s5, p5 = Sig({ buy = 100 }, 105, 5)
local s6 = Sig({ buy = 100 }, 101, 0)
local s7, p7 = Sig({ buy = 10000 }, 10001, 5)
ok(s1 == "near" and p1 == 4 and d1 == "buy" and s2 == nil and s3 == "near" and p3 == 6 and d3 == "buy", "Near (buy): 4% at 5%; 6% only at 10%")
ok(s4 == "near" and p4 == 5 and d4 == "sell" and s5 == "near" and p5 == 5 and s6 == nil and s7 == "near" and p7 == 1, "Near (sell) 4.9% shows 5%; exactly 5% is near; Off: none; a hair over: 1%")
local s8, p8, d8 = Sig({ buy = 100, sell = 120 }, 110, 10)
ok(s8 == "near" and d8 == "sell" and p8 == 9, "both near: the closer one (sell 8.3% -> 9%, buy 10%)", tostring(p8) .. " " .. tostring(d8))
ok(Wt.SignalText({ sig = "buy" }) == "BUY" and Wt.SignalText({ sig = "sell" }) == "SELL" and Wt.SignalText({ sig = "near", pct = 4, side = "buy" }) == "Near 4% (buy)" and Wt.SignalText({}) == "-", "Signal column: BUY, SELL, Near 4% (buy), -")
ok(Wt.SignalRank({ sig = "buy" }) < Wt.SignalRank({ sig = "sell" }) and Wt.SignalRank({ sig = "sell" }) < Wt.SignalRank({ sig = "near", pct = 1 }) and Wt.SignalRank({}) == nil, "sorted: BUY, SELL, nearest, none last")

print("== 4. saved: realms[realm].targets[id], per house, kept until changed")
Mk.house = nil
I.S.marketHouse = "Horde"
I.ahOpen = false
local t = Wt.Set(2589, 150, nil)
local saved = ValhallaInvestDB.realms.Forever.targets[2589]
ok(saved == t and t.buy == 150 and t.sell == nil and t.house == "Horde" and t.set == W.now, "Set: in ValhallaInvestDB.realms.Forever.targets, the house AH Market shows (not at the AH)")
function GetSubZoneText() return "The Commons" end
function GetRealZoneText() return "Ironforge" end
function UnitFactionGroup() return "Alliance" end
I.ahOpen = true
ok(Wt.DefaultHouse() == "Alliance", "at the AH: the house you're at", Wt.DefaultHouse())
I.ahOpen = false
Wt.Set(2589, "150", 900, "Alliance")
ok(saved.buy == 150 and saved.sell == 900 and saved.house == "Alliance", "both targets, the house changed")
Wt.Set(2770, nil, 1000, "Alliance")
Wt.Add(2447, "Horde")
-- a /reload: the saved table read again
local keep = ValhallaInvestDB
ValhallaInvestDB = keep
I.InitDB()
ok(Wt.Get(2589) and Wt.Get(2589).buy == 150 and Wt.Get(2589).sell == 900 and Wt.Get(2770).sell == 1000 and Wt.Get(2447) and not Wt.Get(2447).buy, "after a /reload: all three kept (one with no targets yet)")
ok(Wt.Count() == 3 and Wt.Has(2447) and not Wt.Has(765), "three watched")
Wt.Set(2447, nil, nil)
ok(Wt.Get(2447).buy == nil and Wt.Get(2447).sell == nil, "blank both: still watched, no targets")

print("== 5. quick scans look up the Watchlist's items (this house's)")
local ids = Wt.InterestIDs("Alliance")
ok(table.concat(ids, ",") == "2589,2770", "Alliance's: 2589, 2770", table.concat(ids, ","))
W.bags[0] = { size = 16 }
I.char.bags = {}
local interest = {} for _, id in ipairs(Sc.Interest("Alliance")) do interest[id] = true end
local hInterest = {} for _, id in ipairs(Sc.Interest("Horde")) do hInterest[id] = true end
ok(interest[2589] and interest[2770] and not interest[2447] and hInterest[2447] and not hInterest[2589], "S.Interest: each house's watched items, not the other's")

print("== 6. a full scan, then quick scans: met targets alert (popup, chat, sound)")
W.clock = 0
function debugprofilestop() return W.clock end
function GetTimePreciseSec() return W.clock / 1000 end
W.pending = {}
local function Later(n, event, ...) W.pending[#W.pending + 1] = { n = n, event = event, args = { ... } } end
local function STick()
  W.clock = W.clock + 16
  local keepP = {}
  for _, p in ipairs(W.pending) do p.n = p.n - 1 if p.n <= 0 then W.Fire(p.event, unpack(p.args)) else keepP[#keepP + 1] = p end end
  W.pending = keepP
  Sc.Tick()
end
local function SUntil(cond, max) for _ = 1, max or 6000 do if cond() then return true end STick() end return cond() end
local CA = C_AuctionHouse
local auctions = {}
CA.IsThrottledMessageSystemReady = function() return true end
CA.MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
CA.ReplicateItems = function() W.Count("ReplicateItems") Later(5, "REPLICATE_ITEM_LIST_UPDATE") end
CA.GetNumReplicateItems = function() return #auctions end
CA.GetReplicateItemInfo = function(i)
  local r = auctions[i + 1]
  return nil, nil, r.count, 1, true, 1, nil, 0, 0, r.buyout, 0, nil, nil, nil, nil, 0, r.id, false
end
local quick = {}
CA.SearchForItemKeys = function(keys) W.sent = {} for _, k in ipairs(keys) do W.sent[#W.sent + 1] = k.itemID end Later(2, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end
CA.HasFullBrowseResults = function() return true end
CA.GetBrowseResults = function()
  local out = {}
  for _, id in ipairs(W.sent) do if quick[id] then out[#out + 1] = { itemKey = { itemID = id }, totalQuantity = 4, minPrice = quick[id] } end end
  return out
end
W.played = {}
SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound(id, ch) W.played[#W.played + 1] = id end
-- Linen Cloth at 140 each (<= 150: BUY), Copper Ore at 980 (< 1000: no SELL, 2% off: Near), Silverleaf unwatched
auctions = { { id = 2589, count = 5, buyout = 700 }, { id = 2589, count = 1, buyout = 200 }, { id = 2770, count = 2, buyout = 1960 }, { id = 765, count = 1, buyout = 50 } }
W.now = W.now - (W.now % 3600) + 3600 + 60
I.ahOpen = true
I.db.account.replicateAt = nil
ns.printed = {}
ok(Sc.Start("full"), "full scan started")
SUntil(function() return not Sc.Running() end)
ok(Sc.last and Sc.last.state == "done" and Sc.Cur("Alliance", 2589).min == 140, "full scan done: Linen Cloth 140 each", Sc.last and Sc.last.text)
local pop = Wt.popup
ok(pop and pop:IsShown() and pop.title._text == "Watchlist targets met (Alliance)", "a popup: Watchlist targets met (Alliance)", pop and pop.title._text)
ok(pop.rows[1].id == 2589 and pop.rows[1].sig._text == "BUY" and pop.rows[1].price._text == "1s 40c <= target 1s 50c" and not pop.rows[2]:IsShown(), "one row: BUY Linen Cloth, lowest vs target", pop.rows[1].price._text)
ok(pop.rows[1].sig._tc[2] == 0.9 and pop.vh and pop.vh.kind == "popup", "BUY green; the frame is the Look's popup (Style.Popup)")
local chat = table.concat(ns.printed, " || ")
ok(chat:find("Full scan done", 1, true) and chat:find("Watchlist BUY |cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r: lowest 1s 40c <= your buy target 1s 50c (Alliance).", 1, true), "chat: the scan's line, then one line per met item (its link)", chat)
ok(#W.played == 1 and W.played[1] == 8959, "a sound (the setting is on)")
ok(Wt.Get(2589).lastMet == W.now and Wt.Get(2589).lastSig == "buy" and Wt.Get(2589).lastPrice == 140 and not Wt.Get(2770).lastMet, "Last met recorded for the met one only")
ok(Wt.last.met == 1 and Wt.last.kind == "full", "the check ran after the full scan")
-- a quick scan 5 minutes later (the cooldown): Copper Ore up to 1000 (SELL), Linen still 140
pop:Hide()
W.now = W.now + 300
quick = { [2589] = 140, [2770] = 1000 }
ns.printed, W.played = {}, {}
ok(Sc.Start(), "a quick scan (inside the 15 minutes)")
ok(Sc.run.kind == "quick", "kind: quick")
SUntil(function() return not Sc.Running() end)
local sentSet = {} for _, id in ipairs(W.sent or {}) do sentSet[id] = true end
ok(sentSet[2589] and sentSet[2770] and not sentSet[2447], "the quick scan asked for this house's watched items", table.concat(W.sent or {}, ","))
ok(pop:IsShown() and pop.rows[1].sig._text == "BUY" and pop.rows[2].sig._text == "SELL" and pop.rows[2].id == 2770 and pop.rows[2].price._text == "10s 00c >= target 10s 00c", "every scan while met: Linen again (BUY), Copper Ore now (SELL, at its target)", pop.rows[2].price._text)
ok(pop.rows[2].sig._tc[1] == 1 and pop.rows[2].sig._tc[2] == 0.6, "SELL orange")
ok(#W.played == 1 and #ns.printed >= 3, "one sound, a chat line each")
-- the sound off
I.S.watchSound = false
W.now = W.now + 300
ns.printed, W.played = {}, {}
Sc.Start("quick") SUntil(function() return not Sc.Running() end)
ok(#W.played == 0 and pop:IsShown(), "sound off: no sound, the popup still")
I.S.watchSound = true

print("== 7. alert frequency: once until the target changes")
I.S.watchAlerts = "once"
pop:Hide()
for _, id in ipairs({ 2589, 2770 }) do Wt.Get(id).alerted = nil end
W.now = W.now + 300
ns.printed = {}
Sc.Start("quick") SUntil(function() return not Sc.Running() end)
ok(pop:IsShown() and pop.rows[1]:IsShown() and pop.rows[2]:IsShown(), "once: the first scan alerts both")
pop:Hide()
W.now = W.now + 300
ns.printed = {}
Sc.Start("quick") SUntil(function() return not Sc.Running() end)
ok(not pop:IsShown() and not table.concat(ns.printed, " "):find("Watchlist BUY", 1, true), "once: the next scan, still met: quiet", table.concat(ns.printed, " || "))
ok(Wt.Get(2589).lastMet == W.now, "but Last met still kept up to date")
Wt.Set(2589, 145, 900, "Alliance")
W.now = W.now + 300
Sc.Start("quick") SUntil(function() return not Sc.Running() end)
ok(pop:IsShown() and pop.rows[1].id == 2589 and not pop.rows[2]:IsShown(), "once: the target changed: it alerts again (only that one)")
pop:Hide()
I.S.watchAlerts = "every"
-- a price that isn't from this scan doesn't alert (an old quick price: not asked again)
local m = Sc.Market("Alliance")
local r = { house = "Alliance", kind = "quick", tmin = math.floor(W.now / 60) - m.base + 10 }
ok(#Wt.OnScanDone(r) == 0, "only prices this scan saw are checked")
ok(#Wt.OnScanDone({ house = "Nowhere" }) == 0 and #Wt.OnScanDone(nil) == 0, "no house: nothing")
-- no price met: no popup
quick = { [2589] = 300, [2770] = 500 }
W.now = W.now + 300
Sc.Start("quick") SUntil(function() return not Sc.Running() end)
ok(not pop:IsShown() and Wt.last.met == 0, "nothing met: no popup")

print("== 8. the popup: click an item for its History")
WorldMapFrame:Show()
mod:Slash("invest", "market")
local rootPage = T.Views().invest.page
local mp = rootPage.pages.market
quick = { [2589] = 100, [2770] = 2000 }
W.now = W.now + 300
Sc.Start("quick") SUntil(function() return not Sc.Running() end)
ok(pop:IsShown(), "met again: the popup")
W.Click(pop.rows[2])
ok(Mk.historyID == pop.rows[2].id and mp.current == "history" and mp.subs.history:IsShown() and not mp.subs.top:IsShown(), "click: AH Market > History of that item", tostring(Mk.historyID))
W.Click(pop.close)
ok(not pop:IsShown(), "x closes it")
WorldMapFrame:Hide()
local opened = Wt.OpenHistory(2770)
W.RunTimers()
ok(opened and WorldMapFrame:IsShown() and T.Current() == "invest" and mp.current == "history" and Mk.historyID == 2770 and mp.subs.history:IsShown(), "the window closed: opened on that item's History")

print("== 9. tooltips: Target lines, green when met")
Mk.house, I.S.marketHouse = nil, "Alliance"
local lines = P.Lines(2589, {}, nil)
local tb, ts
for _, l in ipairs(lines) do if l[1]:find("^Target buy") then tb = l end if l[1]:find("^Target sell") then ts = l end end
ok(tb and tb[1] == "Target buy <= (met)" and tb[3] == 0.3 and tb[4] == 0.9, "Linen at 100: Target buy <= (met), green", tb and tb[1])
ok(ts and ts[1] == "Target sell >=" and ts[3] == nil, "its sell target: not met, the usual colour")
ok(lines[1][1]:find("^AH") or lines[1][1] == "Vendor", "the AH lines still first", lines[1][1])
ok(#P.Lines(765, {}, nil) >= 1 and not table.concat((function() local o = {} for _, l in ipairs(P.Lines(765, {}, nil)) do o[#o + 1] = l[1] end return o end)(), "|"):find("Target"), "an unwatched item: no Target line")
ok(#P.Lines(2447, {}, nil) == 0, "watched with no targets: no Target line")
Wt.Set(2447, 5000, nil, "Horde")
local hl = P.Lines(2447, {}, nil)
ok(#hl == 1 and hl[1][1] == "Target buy <= (Horde)" and hl[1][3] == nil, "a target at another house: its house said; no scan there, not met", hl[1] and hl[1][1])
local GT = GameTooltip
local added = {}
GT.AddDoubleLine = function(_, a, b, r1, g1, b1, r2, g2, b2) added[#added + 1] = { a, r1, g1, r2, g2 } end
P.OnItem(GT, { id = 2589, lines = {} })
local found
for _, a in ipairs(added) do if a[1] == "Target buy <= (met)" then found = a end end
ok(found and found[2] == 0.3 and found[3] == 0.9 and found[4] == 0.3, "on the tooltip: green, both sides")
GT.AddDoubleLine = nil

print("== 10. AH Market > Watchlist")
WorldMapFrame:Show()
mp:ShowSub("watch")
local f = mp.subs.watch
ok(f and f:IsShown() and f.head and #f.head.buttons == 7, "the view: its header strip")
local heads = {} for _, b in ipairs(f.head.buttons) do heads[#heads + 1] = b.text._text end
ok(table.concat(heads, "|") == "Item|Lowest|Buy <= target|Sell >= target|Signal|Last met|Edit", "columns: Item, Lowest, Buy <= target, Sell >= target, Signal, Last met, Edit", table.concat(heads, "|"))
local function Row(id) for _, r in ipairs(f.rows) do if r:IsShown() and r.id == id then return r end end end
local r1, r2, r3 = Row(2589), Row(2770), Row(2447)
ok(r1 and r1.signal._text == "BUY" and r1.min._text == "1s 00c" and r1.buy._text == "1s 45c" and r1.sell._text == "9s 00c" and r1.last._text == "just now", "Linen: BUY, lowest, both targets, Last met", r1 and r1.signal._text)
ok(r2 and r2.signal._text == "SELL" and r2.buy._text == "-" and r2.sell._text == "10s 00c", "Copper Ore: SELL; no buy target: -")
ok(r3 and r3.signal._text == "-" and r3.min._text == "-" and r3.cell.suffix and r3.cell.suffix:find("Horde"), "Peacebloom (Horde, never scanned there): -, its house beside its name")
ok(f.rows[1].id == 2589 and f.rows[2].id == 2770, "sorted by Signal: BUY first, then SELL")
ok(f.count._text:find("3 watched: 1 BUY, 1 SELL, 0 near", 1, true), "the count line", f.count._text)
-- Near shown in the column only
quick = { [2589] = 150, [2770] = 960 }
W.now = W.now + 300
pop:Hide()
Sc.Start("quick") SUntil(function() return not Sc.Running() end)
mp:Refresh()
r1, r2 = Row(2589), Row(2770)
ok(r1.signal._text == "Near 4% (buy)" and r2.signal._text == "Near 4% (sell)" and not pop:IsShown(), "Near 4%: the Signal column only, no popup", r1.signal._text .. " / " .. r2.signal._text)
I.S.watchNear = 0
mp:Refresh()
ok(Row(2589).signal._text == "-", "Near Off: -")
I.S.watchNear = 10
mp:Refresh()
ok(Row(2589).signal._text == "Near 4% (buy)", "Near 10%: shown")
I.S.watchNear = 5
-- Edit: the editor on that item
W.Click(Row(2770).edit)
local ed = Wt.editor
local function Boxes(row) return row[1]._text .. "|" .. row[2]._text .. "|" .. row[3]._text end
local function Type(row, g, sv, c) row[1]:SetText(g) row[2]:SetText(sv) row[3]:SetText(c) end
ok(ed and ed:IsShown() and ed.id == 2770 and Boxes(ed.buy) == "||" and Boxes(ed.sell) == "|10|0" and ed.house == "Alliance" and ed.remove:IsShown(), "Edit: the editor, its targets split into the boxes, its house", Boxes(ed.sell))
ok(ed.vh and ed.vh.kind == "popup", "the editor in the Look's popup frame")
function IsShiftKeyDown() return W.shift end
-- (1.2.15) the coin boxes: number only, the coin icons, Tab order
ok(#ed.boxes == 6 and ed.boxes[1] == ed.buy[1] and ed.boxes[4] == ed.sell[1] and ed.buy[1]._numeric and ed.buy[2]._maxLetters == 3 and ed.buy[1]._maxLetters == 6,
  "six number boxes (gold 6 digits, silver / copper 3), Buy then Sell")
ok(ed.buy.icons[1]._tex:find("UI%-GoldIcon") and ed.buy.icons[2]._tex:find("UI%-SilverIcon") and ed.sell.icons[3]._tex:find("UI%-CopperIcon"), "each box with its coin icon")
ok(W.focus == ed.buy[1], "the Buy gold box has the focus")
-- (1.2.15) the layout: 500 wide, "Lowest now" its own full-width line under the title, every text line a fixed width inside
local EW, PAD = ed:GetWidth(), Wt.EDIT_PAD
ok(EW == 500 and ed.low._text:find("^Lowest now: ") and ed.low._text:find(", Alliance$") and ed.buy.cur == nil, "\"Lowest now: ..., Alliance\" on its own line (not beside the Buy box)", ed.low._text)
local unfixed, past = {}, {}
for _, f in ipairs(W.frames) do
  if f._kind == "FontString" and f._parent == ed and f ~= ed.title then
    if not rawget(f, "_w") then unfixed[#unfixed + 1] = tostring(f._text) end
    local p = f._points[1]
    local x = p and (type(p[2]) == "number" and p[2] or type(p[4]) == "number" and p[4]) or 0
    if rawget(f, "_w") and x + f._w > EW - PAD then past[#past + 1] = tostring(f._text) end
  end
end
ok(#unfixed == 0 and #past == 0, "every text line has a fixed width, all inside the frame's margin", table.concat(unfixed, " | ") .. " / " .. table.concat(past, " | "))
ok(ed.low._w == EW - 2 * PAD and ed.hint._w == EW - 2 * PAD and ed.err._w == EW - 2 * PAD and ed.hint._wrap == true and ed.low._wrap == false, "Lowest, help and error lines: the full width less 18 px each side; the help text wraps")
ok(156 + ed.hint:GetStringHeight() <= 194 and 194 + 13 <= ed:GetHeight() - 14 - 22, "the help text ends above the error line, the error line above the buttons", ed.hint:GetStringHeight())
ok(ed.buy.right <= EW - PAD and ed.sell.right <= EW - PAD and ed.buy.label._w == 170, "the coin boxes and icons end inside the margin", ed.buy.right)
local order = {}
for _ = 1, 6 do W.Run(W.focus, "OnTabPressed") order[#order + 1] = W.focus.tab end
ok(table.concat(order, ",") == "2,3,4,5,6,1", "Tab: gold, silver, copper, then Sell's, round again", table.concat(order, ","))
W.shift = true W.Run(W.focus, "OnTabPressed") W.shift = false
ok(W.focus == ed.sell[3], "shift-Tab: back")
-- carry over when a box is left (150s -> 1g 50s)
Type(ed.buy, "", "150", "")
W.Run(ed.buy[2], "OnEditFocusLost")
ok(Boxes(ed.buy) == "1|50|0", "150 silver shown as 1g 50s 0c when the box is left", Boxes(ed.buy))
Type(ed.buy, "", "", "")
W.Run(ed.buy[2], "OnEditFocusLost")
ok(Boxes(ed.buy) == "||", "all blank stays blank")
Type(ed.buy, "", "8x", "")
ok(not Wt.Save() and ed.err._text:find("^Buy: whole numbers") and ed:IsShown() and Wt.Get(2770).buy == nil, "not a number (a paste): said, nothing saved")
Type(ed.buy, "", "8", "50")
Type(ed.sell, "", "", "")
W.Run(ed.buy[3], "OnEnterPressed")
ok(not ed:IsShown() and Wt.Get(2770).buy == 850 and Wt.Get(2770).sell == nil, "Enter saves: buy 8s 50c, sell blank (none)")
ok(table.concat(ns.printed, " "):find("Watchlist: Copper Ore (Alliance): buy <= 8s 50c, sell >= none.", 1, true), "chat says what was saved")
W.Click(Row(2770).edit)
W.Click(ed.remove)
ok(not Wt.Has(2770) and not ed:IsShown() and not Row(2770), "Remove from Watchlist: gone from the list")
-- add by name: the Shopping List's search
f.search:SetText("silver")
W.RunTimers()
ok(f.results:IsShown() and f.results.rows[1].id == 765 and f.results.rows[1].act.text._text == "Add", "type a name: found (Add)", f.results.rows[1].id)
W.Click(f.results.rows[1].act)
ok(Wt.Has(765) and ed:IsShown() and ed.id == 765 and not ed.remove:IsShown() == false and f.search._text == "", "Add: on the Watchlist, its targets open")
Type(ed.sell, "1", "", "")
Wt.Save()
ok(Wt.Get(765).sell == 10000 and Row(765), "saved: 1g sell target, a row")
f.search:SetText("copper")
W.Run(f.search, "OnEnterPressed")
ok(Wt.Has(2770) and ed.id == 2770, "Enter: the first found picked")
W.Click(ed.cancel)
ok(not ed:IsShown() and Wt.Has(2770) and not Wt.Get(2770).buy, "Cancel: on the list (added), no targets")
-- (1.2.26) the Watchlist's dropdown is the Shopping List's (V.ItemSearch): its rows stay put, a click outside closes it
do
  local function Ids() local t = {} for _, r in ipairs(f.results.rows) do if r:IsShown() then t[#t + 1] = r.id end end return table.concat(t, ",") end
  f.search:SetText("silver") W.RunTimers()
  local first = Ids()
  I.RememberName(969301, "Aaa Silver Ingot")
  f.SearchResults()
  ok(first ~= "" and f.frozen.text == "silver" and Ids() == first .. ",969301", "1.2.26: a name coming in later goes below, the rows don't move", Ids())
  ok(f.searchOpen and f.results:IsShown(), "(open)")
  W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  ok(not f.results:IsShown() and not f.searchOpen, "1.2.26: a click outside the Watchlist's dropdown closes it")
  f.search:SetText("") W.RunTimers()
end

print("== 11. any item: alt-click, the right-click menu")
local cell = V.ItemCell(UIParent, 200)
cell:SetItem(2320)
function IsAltKeyDown() return W.alt end
W.alt = true W.Click(cell) W.alt = false
ok(Wt.Has(2320) and ed:IsShown() and ed.id == 2320, "alt-click: on the Watchlist, its targets open")
W.Click(ed.cancel)
local clicked
cell.onClick = function(id) clicked = id end
W.Click(cell)
ok(clicked == 2320, "a plain click: still its History")
cell:SetItem(3371)
W.Click(cell, "RightButton")
local menu = V.itemMenu
ok(menu:IsShown() and #menu.entries == 2 and menu.items[1].text._text == "Add to the Shopping List's builder" and menu.items[2].text._text == "Set target..." and not menu.items[3]:IsShown(), "right-click, not watched: builder, Set target...")
ok(menu._events and menu._events.GLOBAL_MOUSE_DOWN, "a click elsewhere will close it")
W.Click(menu.items[2])
ok(not menu:IsShown() and ed:IsShown() and ed.id == 3371 and not Wt.Has(3371), "Set target...: the editor (on the list when saved)")
Type(ed.buy, "2", "150", "")
Wt.Save()
ok(Wt.Get(3371).buy == 35000, "saved 2g + 150s = 3g 50s (carried)")
W.Click(cell, "RightButton")
ok(#menu.entries == 3 and menu.items[2].text._text == "Edit target..." and menu.items[3].text._text == "Remove from Watchlist", "watched: Edit target..., Remove from Watchlist")
W.Click(menu.items[3])
ok(not Wt.Has(3371), "Remove from Watchlist")
W.Click(cell, "RightButton")
W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
ok(not menu:IsShown(), "a click elsewhere: closed")

print("== 12. Settings > Watchlist")
mod:Slash("invest", "settings")
local sp = T.Views().settings.page
ok(sp.watchSound and sp.watchSound.tick:IsShown() and sp.watchAlerts and sp.watchNear and sp.watchNote._text:find("before the AH's cut", 1, true), "the sound box (ticked), Alert frequency, Near, the note")
W.Click(sp.watchAlerts.boxes[2])
ok(I.S.watchAlerts == "once" and Wt.Mode() == "once", "Alert frequency: Once until target changed")
W.Click(sp.watchAlerts.boxes[1])
W.Click(sp.watchNear.boxes[3])
ok(I.S.watchAlerts == "every" and I.S.watchNear == 10 and Wt.NearPct() == 10, "Every scan while met; Near 10%")
W.Click(sp.watchNear.boxes[1])
ok(Wt.NearPct() == 0, "Near Off")
I.S.watchNear = 7
ok(Wt.NearPct() == 5, "an odd saved value: 5%")
W.Click(sp.watchSound)
ok(I.S.watchSound == false, "sound off")

print("== 13. read only: nothing bought, posted or bid")
ok(not W.calls.PlaceBid and not W.calls.StartCommoditiesPurchase and not W.calls.PostItem and not W.calls.ConfirmCommoditiesPurchase, "no purchase or post call, ever")
ok(#W.sizeErrors == 0, "no layout errors", W.sizeErrors[1])

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
