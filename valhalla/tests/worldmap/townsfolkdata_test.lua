-- Box tests for Valhalla/Data/Forever/Townsfolk.lua (1.2.51: one pin per NPC per map). Lua 5.1.
-- Run: lua valhalla/tests/worldmap/townsfolkdata_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
local ns = {}
assert(loadfile(root .. "Data/Forever/Townsfolk.lua"))("Valhalla", ns)
local pass, fail = 0, 0
local function ok(c, name, detail)
  if c then pass = pass + 1 print("PASS  " .. name) else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end
local recs = ns.TownsfolkData.records
local n, per, byMap, kinds = 0, {}, {}, {}
for _, r in ipairs(recs) do
  n = n + 1
  byMap[r.map] = (byMap[r.map] or 0) + 1
  kinds[r.type] = (kinds[r.type] or 0) + 1
  if r.type ~= "mailbox" and r.type ~= "spirit" then
    local k = r.id .. ":" .. r.map .. ":" .. r.type
    per[k] = (per[k] or 0) + 1
  end
end
local twice = {}
for k, c in pairs(per) do if c > 1 then twice[#twice + 1] = k end end
ok(#twice == 0, "one pin per NPC per map (mailboxes and spirit healers apart)", table.concat(twice, " "))
ok(n == 1330, "1,489 records before, 1,330 now (159 duplicates gone)", tostring(n))
ok(kinds.mailbox == 50 and kinds.spirit == 8, "real separate mailboxes (50) and spirit healers (8) all kept",
  tostring(kinds.mailbox) .. " " .. tostring(kinds.spirit))
local want = { [1455] = 103, [1458] = 92, [1412] = 34, [1433] = 20, [1457] = 80, [1456] = 79, [1424] = 24,
  [1454] = 98, [1453] = 107, [1432] = 22, [1421] = 16, [1423] = 11, [1441] = 12 }
local bad = {}
for map, c in pairs(want) do if byMap[map] ~= c then bad[#bad + 1] = map .. "=" .. tostring(byMap[map]) end end
ok(#bad == 0, "the 13 maps' counts", table.concat(bad, " "))
local function find(id, map) for _, r in ipairs(recs) do if r.id == id and r.map == map then return r end end end
local b = find(6727, 1433)
ok(b and math.abs(b.x - 21.8) < 0.01 and math.abs(b.y - 44.8) < 0.01, "Redridge: Innkeeper Brianna at the Forever point (21.8, 44.8), checked in game",
  b and (b.x .. "," .. b.y))
local lake = 0
for _, r in ipairs(recs) do if r.map == 1433 and r.x < 30 then lake = lake + 1 if r.x > 26 then lake = -999 end end end
ok(lake == 16, "Lakeshire: 16 pins, all west of x 26 (no Classic-frame copies at x 26-31)", tostring(lake))
local k = find(3063, 1412)
ok(k and math.abs(k.x - 48.4) < 0.01 and math.abs(k.y - 63.6) < 0.01, "Mulgore: Krang Stonehoof at its Forever-only point", k and (k.x .. "," .. k.y))
local v = find(1246, 1455)
ok(v and v.x > 66.4 and v.x < 67.0, "Ironforge: Vosur Brakthel's near spots merged into one centre", v and (v.x .. "," .. v.y))
print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
