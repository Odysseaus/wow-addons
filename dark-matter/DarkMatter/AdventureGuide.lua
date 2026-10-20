-- Adventure Guide data layer (0.3.4): our known-good list of every Classic + Forever dungeon and raid
-- (Data_Dungeons.lua: validated on Wowhead WoW Forever) merged with the client's LFG data (read-only, by name or
-- alias), plus account-wide loot learning.
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
-- 0.3.4 loose key for small spelling variants the alias map does not list: doubled letters collapse and a
-- plural "s" drops ("zulfarak" = "zulfarrak", "stockades" = "stockade"). Used only when the exact normalized
-- name, the aliases and the parent names all miss, and only when exactly one of our entries has that loose key.
local function Loose(k)
  if not k then return nil end
  local n
  repeat k, n = k:gsub("(%a)%1", "%1") until n == 0 -- Lua patterns take no quantifier after %1, so loop
  k = k:gsub("s$", "")
  return k
end
AG.Loose = Loose

local seedIdx
local function SeedIndex()
  if seedIdx then return seedIdx end
  -- byName: our name + aliases (Data_Dungeons.lua, from catalog.json) -> one entry. byParent: the LFG row that
  -- lists several of our wings (d.parent, e.g. "Scarlet Monastery") -> those wings. byLoose: unique loose keys.
  seedIdx = { byName = {}, byParent = {}, byLoose = {}, bossByNpc = {} }
  local loose = {}
  local function AddLoose(k, d)
    local lk = Loose(k)
    if not lk then return end
    local cur = loose[lk]
    if cur == nil then loose[lk] = d elseif cur ~= d then loose[lk] = false end -- false: ambiguous, never used
  end
  for _, d in ipairs(NS.AdventureGuideSeed or {}) do
    local k = Norm(d.name)
    if k then seedIdx.byName[k] = d AddLoose(k, d) end
    for _, a in ipairs(d.aliases or {}) do
      local ak = Norm(a)
      if ak and not seedIdx.byName[ak] then seedIdx.byName[ak] = d end
      AddLoose(ak, d)
    end
    local pk = Norm(d.parent)
    if pk then
      local t = seedIdx.byParent[pk] or {}
      t[#t + 1] = d
      seedIdx.byParent[pk] = t
    end
    for _, b in ipairs(d.bosses or {}) do
      if b.npcId then seedIdx.bossByNpc[b.npcId] = { dungeon = d, boss = b } end
    end
  end
  for lk, d in pairs(loose) do if d then seedIdx.byLoose[lk] = d end end
  return seedIdx
end

-- Our entries for an LFG name: list, how ("name" | "parent" | "loose"). Name/alias first, then a parent row
-- (all its wings), then a unique loose match. nil when the name is not ours.
local NOT_DUNGEON = {} -- Classic zones, capitals, battlegrounds (filled below)
local function Match(idx, key)
  if not key then return nil end
  if NOT_DUNGEON and NOT_DUNGEON[key] and not idx.byName[key] then return nil end
  local d = idx.byName[key]
  if d then return { d }, "name" end
  local p = idx.byParent[key]
  if p then return p, "parent" end
  if idx.byParent[Loose(key) or ""] then return idx.byParent[Loose(key)], "parent" end
  d = idx.byLoose[Loose(key) or ""]
  if d then return { d }, "loose" end
  return nil
end
function AG.MatchName(name)
  local l, how = Match(SeedIndex(), Norm(name))
  if not l then return nil end
  local names = {}
  for i, d in ipairs(l) do names[i] = d.name end
  return names, how
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
-- 0.3.1: Forever's LFG id range also holds zone activities and battlegrounds ("Alterac Mountains",
-- "Arathi Basin", ...) that report encounters. An entry is a dungeon/raid only if: its type is not zone /
-- random / world PvP, its name is not a known zone or battleground, it is not a placeholder, and it has at
-- least one real (non-placeholder) encounter name or matches our seed.
---------------------------------------------------------------------------
local SUBTYPE = { [1] = "Dungeon", [2] = "Heroic", [3] = "Raid", [5] = "Raid" }
local MAX_ID = 1300
local REJECT_TYPE = { [4] = "zone", [6] = "random" }   -- typeID
local REJECT_SUBTYPE = { [4] = "scenario", [6] = "pvp" } -- subtypeID

-- Classic zones, capitals and battlegrounds: never dungeons.
-- (NOT_DUNGEON is declared above Match)
for _, n in ipairs({
  "Alterac Mountains", "Arathi Highlands", "Ashenvale", "Ashenvale Forest", "Azshara", "Badlands", "Blasted Lands",
  "Burning Steppes", "Darkshore", "Darnassus", "Deadwind Pass", "Desolace", "Dun Morogh", "Durotar", "Duskwood",
  "Dustwallow Marsh", "Eastern Plaguelands", "Elwynn Forest", "Felwood", "Feralas", "Hillsbrad Foothills",
  "Ironforge", "Loch Modan", "Moonglade", "Mulgore", "Orgrimmar", "Redridge Mountains", "Searing Gorge",
  "Silithus", "Silverpine Forest", "Stonetalon Mountains", "Stormwind", "Stormwind City", "Stranglethorn Vale",
  "Swamp of Sorrows", "Tanaris", "Teldrassil", "The Barrens", "Barrens", "The Hinterlands", "Hinterlands",
  "Thousand Needles", "Thunder Bluff", "Tirisfal Glades", "Undercity", "Un'Goro Crater", "Western Plaguelands",
  "Westfall", "Wetlands", "Winterspring", "Deeprun Tram", "Alterac Valley", "Arathi Basin", "Warsong Gulch",
  "World PvP", "Battlegrounds", "Eastern Kingdoms", "Kalimdor",
}) do NOT_DUNGEON[Norm(n)] = true end
AG._NotDungeon = NOT_DUNGEON

local PLACEHOLDER = { "no longer in use", "unused", "%[ph%]", "^ph[%s:%-]", "zzold", "^zz", "deprecated",
  "do not use", "placeholder", "^secretname", "^test[%s_]", "%(old%)", "^old[%s_]" }
function AG.IsPlaceholder(name)
  name = Str(name)
  if not name then return true end
  local l = name:lower()
  for _, p in ipairs(PLACEHOLDER) do if l:find(p) then return true end end
  return false
end

local function ScanRaw()
  local rows = {}
  if type(GetLFGDungeonInfo) ~= "function" then return rows end
  for id = 1, MAX_ID do
    local ok, name, typeID, subtypeID, minL, maxL, recL, _, _, _, _, _, _, maxP = pcall(GetLFGDungeonInfo, id)
    name = ok and Str(name) or nil
    if name then
      local n = 0
      if type(GetLFGDungeonNumEncounters) == "function" then
        local ok2, c = pcall(GetLFGDungeonNumEncounters, id)
        n = ok2 and Num(c) or 0
      end
      local bosses, dropped, seen = {}, 0, {}
      if n > 0 and type(GetLFGDungeonEncounterInfo) == "function" then
        for i = 1, math.min(n, 40) do
          local ok3, bn = pcall(GetLFGDungeonEncounterInfo, id, i)
          bn = ok3 and Str(bn) or nil
          if bn and not seen[bn] then
            seen[bn] = true
            if AG.IsPlaceholder(bn) then dropped = dropped + 1 else bosses[#bosses + 1] = bn end
          end
        end
      end
      rows[#rows + 1] = { lfgId = id, name = name, key = Norm(name), typeID = Num(typeID), subtypeID = Num(subtypeID),
        minLevel = Num(minL), maxLevel = Num(maxL), recLevel = Num(recL), maxPlayers = Num(maxP),
        numEncounters = n, bosses = bosses, placeholderBosses = dropped }
    end
  end
  return rows
end

-- Why an LFG row is not a dungeon/raid (nil = accepted). 0.3.2: a row matching our list (name or alias) is always
-- kept; LFG rows that report no bosses are kept too (the real client lists 21 such dungeons/raids).
local function RejectReason(e, idx)
  if not e.key then return "noname" end
  if AG.IsPlaceholder(e.name) then return "placeholder" end
  local m, how = Match(idx, e.key)
  if m and not (how == "loose" and NOT_DUNGEON[e.key]) then return nil end -- a loose match never beats the zone list
  if NOT_DUNGEON[e.key] then return "zone" end
  if e.name:lower():find("^random[%s%-]") then return "random" end -- random-queue rows
  if e.typeID and REJECT_TYPE[e.typeID] then return REJECT_TYPE[e.typeID] end
  if e.subtypeID and REJECT_SUBTYPE[e.subtypeID] then return REJECT_SUBTYPE[e.subtypeID] end
  return nil
end

function AG.ScanLFG()
  if AG._lfg then return AG._lfg end
  local idx = SeedIndex()
  local list, byKey = {}, {}
  local stats = { named = 0, accepted = 0, rejected = {} }
  for _, e in ipairs(ScanRaw()) do
    stats.named = stats.named + 1
    local why = RejectReason(e, idx)
    if not why and byKey[e.key] then why = "duplicate" end
    if why then
      stats.rejected[why] = (stats.rejected[why] or 0) + 1
    else
      byKey[e.key] = e
      list[#list + 1] = e
      stats.accepted = stats.accepted + 1
    end
  end
  AG._lfg, AG._stats = list, stats
  return list
end
function AG.ScanStats() AG.ScanLFG() return AG._stats end

-- /dm agscan: raw LFG rows with the accept/reject decision -> DarkMatterDB.agscan; returns a chat summary.
function AG.ScanReport()
  local idx = SeedIndex()
  local rows, out = ScanRaw(), {}
  local stats = { named = #rows, accepted = 0, rejected = {} }
  local byKey = {}
  for i, e in ipairs(rows) do
    local why = RejectReason(e, idx)
    if not why and byKey[e.key] then why = "duplicate" end
    if why then stats.rejected[why] = (stats.rejected[why] or 0) + 1 else stats.accepted = stats.accepted + 1 byKey[e.key] = true end
    if i <= 300 then
      out[#out + 1] = { id = e.lfgId, name = e.name, typeID = e.typeID, subtypeID = e.subtypeID, minLevel = e.minLevel,
        maxLevel = e.maxLevel, recLevel = e.recLevel, maxPlayers = e.maxPlayers, numEncounters = e.numEncounters,
        bosses = e.bosses, placeholderBosses = e.placeholderBosses, accepted = why == nil, reason = why }
    end
  end
  if type(DarkMatterDB) == "table" then
    DarkMatterDB.agscan = { at = date("%Y-%m-%d %H:%M:%S"), stats = stats, rows = out }
  end
  local parts, noBoss, unlisted, mapped, hit = {}, {}, {}, {}, {}
  for k, v in pairs(stats.rejected) do parts[#parts + 1] = k .. " " .. v end
  table.sort(parts)
  for _, r in ipairs(out) do
    if r.accepted and #(r.bosses or {}) == 0 then noBoss[#noBoss + 1] = r.name end
    if r.accepted then
      local l, how = Match(idx, Norm(r.name))
      if l then
        local names = {}
        for i, d in ipairs(l) do hit[d] = true names[i] = d.name end
        r.ours, r.matchedBy = names, how
        if how ~= "name" or Norm(r.name) ~= Norm(l[1].name) then mapped[#mapped + 1] = r.name .. " -> " .. table.concat(names, " / ") end
      else
        unlisted[#unlisted + 1] = r.name
      end
    end
  end
  -- ours only: our entries no LFG row maps to (informational; the dropdown lists them anyway)
  local oursOnly = {}
  for _, d in ipairs(NS.AdventureGuideSeed or {}) do if not hit[d] then oursOnly[#oursOnly + 1] = d.name end end
  if type(DarkMatterDB) == "table" and DarkMatterDB.agscan then
    DarkMatterDB.agscan.noBosses, DarkMatterDB.agscan.notInList = noBoss, unlisted
    DarkMatterDB.agscan.mapped, DarkMatterDB.agscan.oursOnly = mapped, oursOnly
  end
  local lines = { string.format("agscan: %d LFG names, %d dungeons/raids kept (%d of %d match our list); rejected: %s", stats.named,
    stats.accepted, stats.accepted - #unlisted, stats.accepted, #parts > 0 and table.concat(parts, ", ") or "none") }
  -- chat lines stay short: names in chunks
  local function Chunk(label, names)
    if #names == 0 then return end
    local cur = label .. " (" .. #names .. "): "
    for i, n in ipairs(names) do
      local add = n .. (i < #names and ", " or "")
      if #cur + #add > 230 then lines[#lines + 1] = cur cur = "  " end
      cur = cur .. add
    end
    lines[#lines + 1] = cur
  end
  Chunk("kept, not in our list", unlisted)
  Chunk("mapped by alias", mapped)
  Chunk("kept, no LFG bosses (our boss lists are used)", noBoss)
  Chunk("info: ours only, not in the LFG list", oursOnly)
  return table.concat(lines, "\n"), lines
end

local function Kind(e)
  local k = e.subtypeID and SUBTYPE[e.subtypeID]
  if k then return k end
  if e.typeID == 2 then return "Raid" end
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

-- Merged list (0.3.2): every dungeon and raid in our list (always shown), with live LFG data attached where the
-- name or an alias matches (several LFG rows may map to one entry, e.g. Stratholme's two gates), plus any other
-- LFG row that is a real dungeon/raid (zones, battlegrounds and placeholders are filtered in the scan).
function AG.Dungeons()
  local idx = SeedIndex()
  local out, bySeed = {}, {}
  for _, sd in ipairs(NS.AdventureGuideSeed or {}) do
    local k = Norm(sd.name)
    if k and not bySeed[sd] then
      local dropsSeeded = sd.dropsSeeded ~= false
      local d = { name = sd.name, key = k, source = "list", lfg = false, kind = sd.kind or "Dungeon",
        minLevel = sd.levels and sd.levels[1], maxLevel = sd.levels and sd.levels[2], size = sd.size or 5,
        seeded = true, dropsSeeded = dropsSeeded, forever = sd.forever, zone = sd.zone, short = sd.short,
        src = sd.src, bosses = {}, _have = {} }
      for _, b in ipairs(sd.bosses or {}) do
        d._have[Norm(b.name) or ""] = true
        d.bosses[#d.bosses + 1] = { name = b.name, npcId = b.npcId, rare = b.rare, src = b.src, dropSrc = b.dropSrc,
          drops = dropsSeeded and Drops(b) or {}, seeded = dropsSeeded and not b.dropsPending }
      end
      bySeed[sd] = d
      out[#out + 1] = d
    end
  end
  for _, e in ipairs(AG.ScanLFG()) do
    local sds, how = Match(idx, e.key)
    if sds then
      -- a parent row (one LFG "Scarlet Monastery" for our four wings) marks every wing as live but gives none of
      -- them its level or bosses (they belong to no single wing); our names, levels and bosses stay the source.
      for _, sd in ipairs(sds) do
        local d = bySeed[sd]
        if d then
          d.lfg, d.source = true, "list+lfg"
          d.lfgId = d.lfgId or e.lfgId
          d.lfgNames = d.lfgNames or {}
          d.lfgNames[#d.lfgNames + 1] = e.name
          if how ~= "parent" then
            if (not d.recLevel) and e.recLevel and e.recLevel > 0 then d.recLevel = e.recLevel end
            d.numEncounters = (d.numEncounters or 0) + (e.numEncounters or 0)
            for _, bn in ipairs(e.bosses) do
              local bk = Norm(bn) or ""
              if not d._have[bk] then
                d._have[bk] = true
                d.bosses[#d.bosses + 1] = { name = bn, drops = {}, seeded = false, live = true }
              end
            end
          end
        end
      end
    else
      local d
      d = { name = e.name, key = e.key, lfgId = e.lfgId, source = "lfg", lfg = true, kind = Kind(e),
        minLevel = e.minLevel, maxLevel = e.maxLevel, recLevel = e.recLevel, size = e.maxPlayers,
        numEncounters = e.numEncounters, seeded = false, dropsSeeded = false, bosses = {}, _have = {} }
      for _, bn in ipairs(e.bosses) do d.bosses[#d.bosses + 1] = { name = bn, drops = {}, seeded = false, live = true } end
      if d.minLevel and d.minLevel <= 0 then d.minLevel = nil end
      if d.maxLevel and d.minLevel and d.maxLevel < d.minLevel then d.maxLevel = d.minLevel end
      if d.maxLevel and d.maxLevel <= 0 then d.maxLevel = nil end
      out[#out + 1] = d
    end
  end
  for _, d in ipairs(out) do d._have = nil end
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
          if NS.OnBossLooted then pcall(NS.OnBossLooted, npc, guid) end -- achievements: kill fallback, deduped there
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
    local prev = NS.ctx
    NS.ctx = "ag:" .. tostring(event)
    if event == "LOOT_OPENED" then
      pcall(AG.OnLootOpened)
      if AG.onChange then pcall(AG.onChange) end
    elseif event == "ENCOUNTER_END" then
      if a5 == 1 or a5 == true then AG.OnBossKilled(a2) end
    elseif event == "BOSS_KILL" then
      AG.OnBossKilled(a2)
    end
    NS.ctx = prev
  end)
end
function AG._Frame() return ev end
