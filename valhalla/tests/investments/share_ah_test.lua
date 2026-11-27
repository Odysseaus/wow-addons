-- Box tests for 1.2.58: shared account AH markets, per-character Watchlists, one-time migrate.
-- Run: lua valhalla/tests/investments/share_ah_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
dofile(here .. "stubs.lua")

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or "")) end
end
local function N(t) local k = 0 for _ in pairs(t or {}) do k = k + 1 end return k end

print("== 1.2.58 load")
local toc = assert(io.open(root .. "Valhalla.toc")):read("*a")
ok(toc:find("## Version: 1.2.60", 1, true) ~= nil, "TOC: version 1.2.60")

local ns = { modules = {}, version = "v1.2.58", Media = { path = "Interface\\AddOns\\Valhalla\\Media\\" } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Safe = { Value = function(v) return v end }
ns.Look = { Font = function(_, fs, size) fs._size = size return fs end }
ns.printed = {}
function ns:Print(fmt, ...) ns.printed[#ns.printed + 1] = fmt:format(...) end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} if m.defaults.enabled == nil then m.defaults.enabled = true end self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
ns.modules.worldmap = { key = "worldmap", enabled = true }
function ns.modules.worldmap.TabAway() end
assert(loadfile(root .. "Util.lua"))("Valhalla", ns)
assert(loadfile(root .. "UI/Style.lua"))("Valhalla", ns)
assert(loadfile(root .. "Links.lua"))("Valhalla", ns)
for _, f in ipairs({ "Invest", "Scan", "Tabs", "Views", "Market", "Watch", "Tooltip", "Data/Forever/Recipes", "Data/Forever/TopSkills", "Craft", "Trainer", "Merchant", "AHPanel" }) do
  assert(loadfile(root .. (f:find("/") and f or ("Investments/" .. f)) .. ".lua"))("Valhalla", ns)
end
local mod = ns:GetModule("invest")
local I, Sc, Wt = mod.I, nil, nil
mod.db, mod.char, mod.enabled = { enabled = true }, {}, true

local CAM, TB = "CAMWOW US2 Realm 8 PvP", "Thunderbuns"
-- Vaelan's 11:11 AM scan, as minutes-since-base on the CAMWOW market
local now = W.now
local camBase = 29905762
local camT = 24229                 -- AbsTime = 1795799460 when this was live; here we just need it newest
local tbBase = 29905762 - 2000
local tbT = 2622
-- make AbsTime(cam) later than AbsTime(tb): camBase+camT > tbBase+tbT
ok((camBase + camT) > (tbBase + tbT), "fixture: CAMWOW Alliance point is newer than Thunderbuns")

local function Targets21()
  local t = {}
  for i = 1, 20 do t[8000 + i] = { house = "Alliance", sell = 800, buy = 500, added = now - 10000, set = now - 9000, lastMet = now - 10, lastSig = "sell", lastPrice = 885 } end
  t[8831] = { house = "Alliance", sell = 800, buy = 500, added = now - 8000, set = now - 7000, lastMet = now - 5, lastSig = "sell", lastPrice = 885, alerted = "sell:500:800" }
  return t
end

local function Fixture(extra)
  extra = extra or {}
  local histDays, cap = extra.histDays, extra.histCapMB
  return {
    settings = { histDays = histDays or 7, histCapMB = cap or 3, marketHouse = "Alliance" },
    account = { names = { [8831] = "Purple Lotus" }, replicateAt = now - 4 },
    realms = {
      [CAM] = {
        targets = Targets21(),
        ahLast = "Alliance",
        scanLast = { state = "done", house = "Alliance", saved = true, at = now, kind = "full",
          text = "Full scan done: 199293 auctions of 6998 items (Alliance). Next full scan in 14:56." },
        ah = {
          Alliance = {
            base = camBase,
            scans = { { t = 14224, kind = "full", n = 176833, items = 6811, secs = 11.7 },
              { t = camT, kind = "full", n = 199293, items = 6998, secs = 13.1, ms = 9.1 } },
            cur = { [8831] = "885,1325,144," .. camT, [7786] = "19500,1,1," .. camT, [15347] = "2200,4,4," .. camT },
            hist = { [8831] = "14224:620:165:39;" .. camT .. ":885:1325:144", [15347] = "14224:2599:6:6;" .. camT .. ":2200:4:4" },
          },
          Neutral = {
            base = camBase,
            scans = { { t = 21667, kind = "full", n = 32772, items = 3838, secs = 1.7 } },
            cur = { [14342] = "629595,10,10,21667" },
            hist = { [14342] = "21667:629595:10:10" },
          },
        },
        chars = { Vaelan = { bags = { [8831] = 7 }, bagsSeen = now - 20, lists = {}, want = {}, mail = {}, draft = { items = {}, name = "" } } },
      },
      [TB] = {
        targets = {},
        ahLast = "Alliance",
        scanLast = { state = "done", house = "Alliance", saved = true, at = now - 2 * 86400, kind = "full",
          text = "Full scan done: 218447 auctions of 6995 items (Alliance). Next full scan in 14:56." },
        ah = {
          Alliance = {
            base = tbBase,
            scans = { { t = 0, kind = "full", n = 221479, items = 6959, secs = 20.6 },
              { t = tbT, kind = "full", n = 218447, items = 6995, secs = 14.4 } },
            cur = { [8831] = "629,1977,214," .. tbT, [3358] = "555,10,10," .. tbT },
            hist = { [8831] = "0:500:2136:278;" .. tbT .. ":629:1977:214", [3358] = tbT .. ":555:10:10" },
          },
        },
        chars = {
          Darlocklinn = { bags = { [6948] = 1 }, bagsSeen = now - 4 * 86400, lists = {}, want = {}, mail = {}, draft = { items = {}, name = "" } },
          Heimdall = { bags = { [4234] = 8 }, bagsSeen = now - 86400, lists = {}, want = {}, mail = {}, draft = { items = {}, name = "" } },
        },
      },
    },
  }
end

local function Login(name, realm, aliases)
  W.me = name
  _G.GetRealmName = function() return CAM end
  _G.GetNormalizedRealmName = function() return CAM end
  _G.UnitName = function(u) if u == "player" then return name end end
  _G.UnitFullName = function() return name, TB end
  mod.char = { realm = realm, aliases = aliases }
  I.InitDB()
  Sc, Wt = I.Scan, I.Watch
  return _G.ValhallaInvestDB
end

print("== 2. migrate both realm buckets into one shared Alliance (and Neutral) market")
_G.ValhallaInvestDB = Fixture()
local db = Login("Vaelan", CAM, { [TB] = CAM })
ok(db.account.shareMigrated == "1.2.58" and type(db.account.shareMigrateDiag) == "table", "shareMigrated and shareMigrateDiag written")
local diag = db.account.shareMigrateDiag
ok(type(diag.buckets) == "table" and table.concat(diag.buckets, ",") == CAM .. "," .. TB, "diag.buckets lists both realm keys", table.concat(diag.buckets or {}, ","))
ok(diag.scanLast and diag.scanLast.at == now and diag.scanLast.house == "Alliance" and diag.scanLast.kind == "full",
  "diag.scanLast is Vaelan's newest Alliance full scan", diag.scanLast and diag.scanLast.at)
ok(diag.targetsMoved and diag.targetsMoved.Vaelan == 21 and diag.targetsMoved.Heimdall == 0 and diag.targetsMoved.Darlocklinn == 0,
  "diag.targetsMoved: Vaelan 21, alts 0", (function()
    local t = {} for k, v in pairs(diag.targetsMoved or {}) do t[#t+1] = k.."="..tostring(v) end table.sort(t) return table.concat(t, ",") end)())
ok(db.account.scanLast and db.account.scanLast.at == now and db.account.ahLast == "Alliance" and db.account.replicateAt == now - 4,
  "account.scanLast / ahLast / replicateAt kept")
local A = db.account.ah.Alliance
local Neut = db.account.ah.Neutral
ok(A and Neut and A.base == camBase, "shared stores exist; Alliance keeps the older (CAMWOW) base")
ok(#A.scans == 4, "Alliance scans: both buckets merged (2+2), no drop", #A.scans)
ok(A.cur[8831] == "885,1325,144," .. camT and A.cur[7786] == "19500,1,1," .. camT,
  "current Alliance prices are Vaelan's 11:11 scan (newer cur wins)", A.cur[8831])
ok(A.cur[3358] ~= nil, "Thunderbuns-only item kept in cur with its (older) point")
ok(A.hist[8831] and A.hist[8831]:find(camT .. ":885:1325:144", 1, true) and A.hist[8831]:find(":629:1977:214", 1, true),
  "hist merges points from both buckets", A.hist[8831])
ok(Neut.cur[14342] == "629595,10,10,21667", "Neutral market comes along from CAMWOW")
ok(db.realms[CAM].ah == nil and db.realms[TB].ah == nil and db.realms[CAM].scanLast == nil and db.realms[TB].scanLast == nil,
  "realm.ah / scanLast cleared so a realm-name split cannot fork scans again")
local last, lastAt = Sc.LastScan("Alliance", "full")
ok(last and last.n == 199293 and last.items == 6998 and lastAt == Sc.AbsTime(A, camT),
  "LastScan(Alliance, full) is Vaelan's 199293 / 6998 scan")
ok(Sc.Cur("Alliance", 8831).min == 885 and Sc.Cur("Alliance", 7786).min == 19500, "AH Market Cur reads the shared store")
ok(N(I.char.targets) == 21 and I.char.targets[8831].lastPrice == 885 and I.char.targets[8831].lastMet == now - 5,
  "Vaelan has the 21 CAMWOW targets, lastMet kept on the character")
ok(N(db.realms[TB].chars.Heimdall.targets) == 0 and N(db.realms[TB].chars.Darlocklinn.targets) == 0,
  "Heimdall and Darlocklinn start with an empty Watchlist")
ok(N(db.realms[CAM].chars.Vaelan.bags) == 1 and db.realms[CAM].chars.Vaelan.bags[8831] == 7
  and db.realms[TB].chars.Heimdall.bags[4234] == 8, "bags / char records unchanged")

print("== 3. an alt on the leftover Thunderbuns key sees the same shared scans, not Vaelan's Watchlist")
db = Login("Heimdall", TB)
ok(I.me == "Heimdall" and I.realm == db.realms[TB], "Heimdall still binds to the Thunderbuns realm key", I.realmInfo and I.realmInfo.key)
ok(db.account.ah.Alliance.cur[8831] == "885,1325,144," .. camT and Sc.Cur("Alliance", 8831).min == 885
  and Sc.LastScan("Alliance", "full").n == 199293,
  "Heimdall reads Vaelan's 11:11 Alliance market (no new scan)")
ok(Wt.Count() == 0 and not Wt.Get(8831), "Heimdall's Watchlist is empty (Vaelan's 21 are not shared)")
Wt.Set(3358, nil, 500, "Alliance")
ok(Wt.Get(3358) and Wt.Get(3358).sell == 500 and Wt.Count() == 1, "Heimdall can set a target of his own")
ok(db.realms[CAM].chars.Vaelan.targets[8831] and not db.realms[CAM].chars.Vaelan.targets[3358]
  and N(db.realms[CAM].chars.Vaelan.targets) == 21, "Vaelan's 21 targets are untouched by Heimdall's edit")

print("== 4. per-character isolation both ways, and Watch.Store after a reload")
db = Login("Vaelan", CAM, { [TB] = CAM })
ok(Wt.Count() == 21 and Wt.Get(8831).lastPrice == 885 and not Wt.Get(3358),
  "Vaelan reloaded: his 21 targets still, not Heimdall's Khadgar's Whisker")
ok(Sc.Cur("Alliance", 8831).min == 885, "shared scan still current after the second login")

print("== 5. idempotent rerun")
local before = db.account.shareMigrateDiag
local cur = db.account.ah.Alliance.cur[8831]
local moved = before.targetsMoved.Vaelan
I.InitDB()
ok(db.account.shareMigrated == "1.2.58" and db.account.shareMigrateDiag == before,
  "second InitDB: same diag table, flag unchanged")
ok(db.account.ah.Alliance.cur[8831] == cur and N(db.realms[CAM].chars.Vaelan.targets) == 21
  and N(db.realms[TB].chars.Heimdall.targets) == 1,
  "second InitDB: cur, Vaelan's 21 and Heimdall's 1 not overwritten")
ok(I.ShareMigrate() == before, "ShareMigrate() itself is a no-op once shareMigrated is set")

print("== 6. hist cap is applied during the migrate")
-- many old full-scan points so the 0.0002 MB cap (~209 bytes) must drop the oldest scans, but keep the newest
local fat = Fixture({ histCapMB = 0.0002, histDays = 7 })
local scans = fat.realms[CAM].ah.Alliance.scans
for i = 1, 40 do
  scans[#scans + 1] = { t = 100 + i, kind = "full", n = 10, items = 1 }
  fat.realms[CAM].ah.Alliance.hist[1000 + i] = (100 + i) .. ":1:1:1"
  fat.realms[CAM].ah.Alliance.cur[1000 + i] = "1,1,1," .. (100 + i)
end
_G.ValhallaInvestDB = fat
db = Login("Vaelan", CAM, { [TB] = CAM })
A = db.account.ah.Alliance
local last = Sc.LastScan("Alliance", "full")
ok(last and last.n == 199293 and last.items == 6998, "after cap prune: the newest (Vaelan 11:11) full scan is still current", last and last.n)
ok(Sc.TotalSize() <= 0.0002 * 1024 * 1024 or #A.scans == 1,
  "after cap prune: under histCapMB or trimmed to a single remaining scan time",
  tostring(Sc.TotalSize()) .. " bytes, " .. tostring(A and #A.scans) .. " scans")
ok(A.cur[8831] == "885,1325,144," .. camT, "after cap prune: current Alliance cur is still Vaelan's 11:11 prices")

print("== 7. a brand-new character gets an empty Watchlist and the shared market")
db = Login("Newbie")
ok(I.char and N(I.char.targets) == 0 and Sc.Cur("Alliance", 8831).min == 885,
  "new character: empty Watchlist, same shared Alliance prices")

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
