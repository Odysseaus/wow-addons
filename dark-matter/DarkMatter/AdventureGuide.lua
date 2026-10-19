-- Adventure Guide data layer (0.3.0): dungeon list from the client's LFG data (read-only), merged with our own
-- static drop seed (Data_Dungeons.lua: validated on Wowhead WoW Forever), plus account-wide loot learning.
-- Taint-safe: read-only API calls (pcall), our own private event frame, no hooks, no Blizzard UI loads.
local _, NS = ...
local AG = {}
NS.AG = AG

local function Str(v)
  if type(v) ~= "string" or v == "" then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
local function Num(v) if type(v) == "number" and v == v then return v end return nil end

-- "The Deadmines" / "Deadmines" / "deadmines" -> "deadmines"
local function Norm(s)
  s = Str(s)
  if not s then return nil end
  s = s:lower():gsub("^the%s+", "")
  return (s:gsub("[^%w]", ""))
end
AG.Norm = Norm

---------------------------------------------------------------------------
-- static seed index
---------------------------------------------------------------------------
local seedIdx
local function SeedIndex()
  if seedIdx then return seedIdx end
  seedIdx = { byName = {}, bossByNpc = {} }
  for _, d in ipairs(NS.AdventureGuideSeed or {}) do
    local k = Norm(d.name)
    if k then seedIdx.byName[k] = d end
    for _, b in ipairs(d.bosses or {}) do
      if b.npcId then seedIdx.bossByNpc[b.npcId] = { dungeon = d, boss = b } end
    end
  end
  return seedIdx
end

---------------------------------------------------------------------------
-- C_Item.DoesItemExistByID gate (cached per session). Missing API: keep the (Forever-validated) seed entry.
---------------------------------------------------------------------------
local exists = {}
function AG.ItemExists(itemId)
  itemId = Num(itemId)
  if not itemId then return false end
  local v = exists[itemId]
  if v ~= nil then return v end
  v = true
  local CI = C_Item
  if CI and CI.DoesItemExistByID then
    local ok, r = pcall(CI.DoesItemExistByID, itemId)
    if ok and r == false then v = false end
  end
  exists[itemId] = v
  return v
end
function AG._ResetCaches() exists = {} seedIdx = nil AG._lfg = nil end

---------------------------------------------------------------------------
-- LFG scan (read-only; once per session). GetLFGDungeonInfo classic order:
-- name, typeID, subtypeID, minLevel, maxLevel, recLevel, minRecLevel, maxRecLevel, expansion, groupID, texture,
-- difficulty, maxPlayers
---------------------------------------------------------------------------
local SUBTYPE = { [1] = "Dungeon", [2] = "Heroic", [3] = "Raid", [4] = "Scenario", [5] = "Raid" }
local MAX_ID = 1300

function AG.ScanLFG()
  if AG._lfg then return AG._lfg end
  local list, byKey = {}, {}
  if type(GetLFGDungeonInfo) == "function" then
    for id = 1, MAX_ID do
      local ok, name, typeID, subtypeID, minL, maxL, recL, _, _, _, _, _, _, maxP = pcall(GetLFGDungeonInfo, id)
      name = ok and Str(name) or nil
      if name then
        local n = 0
        if type(GetLFGDungeonNumEncounters) == "function" then
          local ok2, c = pcall(GetLFGDungeonNumEncounters, id)
          n = ok2 and Num(c) or 0
        end
        local bosses = {}
        if n > 0 and type(GetLFGDungeonEncounterInfo) == "function" then
          local seen = {}
          for i = 1, n do
            local ok3, bn = pcall(GetLFGDungeonEncounterInfo, id, i)
            bn = ok3 and Str(bn) or nil
            if bn and not seen[bn] then seen[bn] = true bosses[#bosses + 1] = bn end
          end
        end
        local key = Norm(name)
        -- dungeons with encounters (random/queue entries have none); one entry per name
        if key and n > 0 and not byKey[key] then
          local e = { lfgId = id, name = name, key = key, typeID = Num(typeID), subtypeID = Num(subtypeID),
            minLevel = Num(minL), maxLevel = Num(maxL), recLevel = Num(recL), maxPlayers = Num(maxP),
            numEncounters = n, bosses = bosses }
          byKey[key] = e
          list[#list + 1] = e
        end
      end
    end
  end
  AG._lfg = list
  return list
end

local function Kind(e)
  local k = e.subtypeID and SUBTYPE[e.subtypeID]
  if k then return k end
  if e.maxPlayers and e.maxPlayers > 5 then return "Raid" end
  return "Dungeon"
end

-- Visible drops of a seeded boss (gated on the client).
local function Drops(b)
  local out = {}
  for _, it in ipairs((b and b.drops) or {}) do
    if AG.ItemExists(it.itemId) then out[#out + 1] = it end
  end
  return out
end

-- Merged list: every LFG dungeon (with its seed drops when we have them) + seed dungeons the LFG list lacks.
function AG.Dungeons()
  local idx = SeedIndex()
  local out, used = {}, {}
  for _, e in ipairs(AG.ScanLFG()) do
    local sd = idx.byName[e.key]
    local d = { name = e.name, key = e.key, lfgId = e.lfgId, source = "lfg", kind = Kind(e),
      minLevel = e.minLevel, maxLevel = e.maxLevel, recLevel = e.recLevel, size = e.maxPlayers,
      numEncounters = e.numEncounters, seeded = sd ~= nil, zone = sd and sd.zone, short = sd and sd.short, bosses = {} }
    if sd then
      used[e.key] = true
      if not d.minLevel and sd.levels then d.minLevel, d.maxLevel = sd.levels[1], sd.levels[2] end
      local have = {}
      for _, b in ipairs(sd.bosses or {}) do
        have[Norm(b.name)] = true
        d.bosses[#d.bosses + 1] = { name = b.name, npcId = b.npcId, rare = b.rare, src = b.src, dropSrc = b.dropSrc, drops = Drops(b), seeded = true }
      end
      for _, bn in ipairs(e.bosses) do
        if not have[Norm(bn)] then d.bosses[#d.bosses + 1] = { name = bn, drops = {}, seeded = false } end
      end
    else
      for _, bn in ipairs(e.bosses) do d.bosses[#d.bosses + 1] = { name = bn, drops = {}, seeded = false } end
    end
    out[#out + 1] = d
  end
  for _, sd in ipairs(NS.AdventureGuideSeed or {}) do
    local k = Norm(sd.name)
    if k and not used[k] then
      local d = { name = sd.name, key = k, source = "seed", kind = "Dungeon", minLevel = sd.levels and sd.levels[1],
        maxLevel = sd.levels and sd.levels[2], size = 5, seeded = true, zone = sd.zone, short = sd.short, bosses = {} }
      for _, b in ipairs(sd.bosses or {}) do
        d.bosses[#d.bosses + 1] = { name = b.name, npcId = b.npcId, rare = b.rare, src = b.src, dropSrc = b.dropSrc, drops = Drops(b), seeded = true }
      end
      out[#out + 1] = d
    end
  end
  table.sort(out, function(a, b)
    local la, lb = a.minLevel or 999, b.minLevel or 999
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  return out
end

-- Filter: text matches dungeon, boss or drop names; level "mine" keeps dungeons around the player's level;
-- kind nil/"all" or a kind name.
function AG.Filter(list, text, level, kind, playerLevel)
  local q = Str(text) and text:lower() or nil
  local out = {}
  for _, d in ipairs(list) do
    local ok = true
    if kind and kind ~= "all" and d.kind ~= kind then ok = false end
    if ok and level == "mine" and playerLevel and d.minLevel and d.maxLevel then
      if playerLevel < d.minLevel - 2 or playerLevel > d.maxLevel then ok = false end
    end
    if ok and q then
      local hit = d.name:lower():find(q, 1, true) ~= nil or (d.short and d.short:lower() == q)
      if not hit then
        for _, b in ipairs(d.bosses) do
          if b.name:lower():find(q, 1, true) then hit = true break end
          for _, it in ipairs(b.drops) do
            if it.name:lower():find(q, 1, true) then hit = true break end
          end
          if hit then break end
        end
      end
      ok = hit
    end
    if ok then out[#out + 1] = d end
  end
  return out
end

function AG.Kinds(list)
  local seen, out = {}, {}
  for _, d in ipairs(list) do if not seen[d.kind] then seen[d.kind] = true out[#out + 1] = d.kind end end
  table.sort(out)
  return out
end

---------------------------------------------------------------------------
-- loot learning (account-wide): DarkMatterDB.agSeen[dungeonKey][bossKey][itemId] = count
-- bossKey = Norm(boss name), or "_other" for loot we can't tie to a boss.
---------------------------------------------------------------------------
local function SeenDB()
  if type(DarkMatterDB) ~= "table" then return nil end
  if type(DarkMatterDB.agSeen) ~= "table" then DarkMatterDB.agSeen = {} end
  return DarkMatterDB.agSeen
end

function AG.SeenCount(dungeonKey, bossName, itemId)
  local db = SeenDB()
  local d = db and dungeonKey and db[dungeonKey]
  local b = d and d[Norm(bossName) or "_other"]
  return (b and Num(b[itemId])) or 0
end

local function ItemIdFromLink(link)
  link = Str(link)
  if not link then return nil end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

local function NpcIdFromGuid(guid)
  guid = Str(guid)
  if not guid then return nil end
  local kind, npc = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
  if kind == "Creature" or kind == "Vehicle" then return tonumber(npc) end
  return nil
end
AG._NpcIdFromGuid = NpcIdFromGuid

local lastKill -- { name, t }
local lootedGuids = {}
local KILL_WINDOW = 120

local function Now() return (GetTime and GetTime()) or 0 end

local function InstanceName()
  if not GetInstanceInfo then return nil end
  local ok, name, itype = pcall(GetInstanceInfo)
  if not ok then return nil end
  if itype ~= "party" and itype ~= "raid" then return nil end
  return Str(name)
end

local function Record(dkey, bossName, itemId)
  local db = SeenDB()
  if not (db and dkey and itemId) then return end
  db[dkey] = db[dkey] or {}
  local bk = Norm(bossName) or "_other"
  db[dkey][bk] = db[dkey][bk] or {}
  db[dkey][bk][itemId] = (Num(db[dkey][bk][itemId]) or 0) + 1
end

function AG.OnLootOpened()
  local inst = InstanceName()
  if not inst or not GetNumLootItems then return 0 end
  local dkey = Norm(inst)
  local okN, n = pcall(GetNumLootItems)
  n = okN and Num(n) or 0
  local idx = SeedIndex()
  local recorded = 0
  for slot = 1, n do
    local okL, link = pcall(GetLootSlotLink, slot)
    local itemId = okL and ItemIdFromLink(link) or nil
    if itemId then
      local guid
      if GetLootSourceInfo then
        local okS, g = pcall(GetLootSourceInfo, slot)
        guid = okS and Str(g) or nil
      end
      local tag = guid and (guid .. ":" .. itemId)
      if not (tag and lootedGuids[tag]) then
        if tag then lootedGuids[tag] = true end
        local boss
        local npc = NpcIdFromGuid(guid)
        local hit = npc and idx.bossByNpc[npc]
        if hit then
          boss = hit.boss.name
          dkey = Norm(hit.dungeon.name) or dkey
        elseif lastKill and Now() - lastKill.t <= KILL_WINDOW then
          boss = lastKill.name
        end
        Record(dkey, boss, itemId)
        recorded = recorded + 1
      end
    end
  end
  return recorded
end

function AG.OnBossKilled(name)
  name = Str(name)
  if name then lastKill = { name = name, t = Now() } end
end

local ev
function AG.StartTracker()
  if ev or not CreateFrame then return end
  ev = CreateFrame("Frame")
  for _, e in ipairs({ "ENCOUNTER_END", "BOSS_KILL", "LOOT_OPENED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function(_, event, _, a2, _, _, a5)
    if event == "LOOT_OPENED" then
      pcall(AG.OnLootOpened)
      if AG.onChange then pcall(AG.onChange) end
    elseif event == "ENCOUNTER_END" then
      if a5 == 1 or a5 == true then AG.OnBossKilled(a2) end
    elseif event == "BOSS_KILL" then
      AG.OnBossKilled(a2)
    end
  end)
end
function AG._Frame() return ev end
