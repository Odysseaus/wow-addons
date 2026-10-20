-- Dark Matter 0.4.0/0.4.1: achievements.
-- 1. The game's own achievement API (read-only): GetCategoryList / GetCategoryInfo / GetCategoryNumAchievements /
--    GetAchievementInfo / GetAchievementNumCriteria / GetAchievementCriteriaInfo, as used by Blizzard's own Forever
--    Legacy UI (Blizzard_LegacySystem, wow-ui-source "forever" branch, build 1.60.1). On Forever that API carries the
--    Legacy Challenges (65 at launch, 0 achievement points, 1 Legacy Point each via
--    C_Traits.GetTraitCurrencyForAchievement(Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225, id)).
--    We never load Blizzard_AchievementUI / Blizzard_LegacySystem and never call anything that changes state.
-- 2. Dark Matter's own achievements, tracked per character from safe events on our own private frame (no hooks):
--    PLAYER_LEVEL_UP, QUEST_TURNED_IN, ENCOUNTER_END (success) / BOSS_KILL by name and the Adventure Guide's
--    LOOT_OPENED boss-corpse npc id (matched to our Data_Dungeons npc ids), our Fishing module's catch callback, CHAT_MSG_LOOT (self lines only), zone changes and
--    PLAYER_MONEY. Counting starts at install; nothing is awarded retroactively except what the game confirms now
--    (current level).
--    0.4.1: everything is per character. Game achievements count as earned only when GetAchievementInfo's
--    wasEarnedByMe is true (Legacy Challenges are account-wide, so other characters' completions come back
--    "completed"); those show as "earned on another character" and are kept in separate account totals. Criteria a
--    different character completed (GetAchievementCriteriaInfo charName) are not counted for this one.
--    0.4.1: never touch COMBAT_LOG_EVENT_UNFILTERED. On Forever 1.60.1 it is HasRestrictions = true
--    (Blizzard_APIDocumentationGenerated/CombatLogDocumentation.lua); 0.4.0's Un/RegisterEvent of it on every zone
--    change raised ADDON_ACTION_FORBIDDEN "UNKNOWN()" at login. ACH.RESTRICTED_EVENTS lists every restricted event.
-- Mode: the game API with data and a full achievement set (300+ achievements with points) -> "game" (ours off);
-- the game API with data but thin (Forever: the Legacy Challenges only) -> "game+dm" (ours under a "Dark Matter"
-- group); no API or no data -> "dm".
local _, NS = ...
local ACH = {}
NS.Ach = ACH

local function Num(v) return NS.Num and NS.Num(v) or (type(v) == "number" and v or nil) end
local function Str(v) return NS.Str and NS.Str(v) or (type(v) == "string" and v or nil) end
local function Stamp() return date("%Y-%m-%d %H:%M") end

ACH.LEGACY_CURRENCY = 4225 -- Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID (LegacyConstantsDocumentation.lua)
ACH.FULL_MIN = 300         -- a "full" achievement set: at least this many shown achievements and some points

---------------------------------------------------------------------------
-- game API (read-only)
---------------------------------------------------------------------------
-- internal rows the client may return (Wowhead Forever lists e.g. "[DNT] Self-Found Soul (Level 10)" under "Do Not Display")
local PLACEHOLDER = { "^%[DNT%]", "^%[PH%]", "<HIDDEN>", "^DNT ", "^zz" }
function ACH.IsPlaceholder(name)
  name = Str(name)
  if not name or name == "" then return true end
  for _, p in ipairs(PLACEHOLDER) do if name:find(p) then return true end end
  return false
end

function ACH.ApiPresent()
  return type(GetCategoryList) == "function" and type(GetCategoryInfo) == "function"
    and type(GetCategoryNumAchievements) == "function" and type(GetAchievementInfo) == "function"
end

local function LegacyPoints(id)
  if not (C_Traits and type(C_Traits.GetTraitCurrencyForAchievement) == "function") then return nil end
  local ok, v = pcall(C_Traits.GetTraitCurrencyForAchievement, ACH.LEGACY_CURRENCY, id)
  return ok and Num(v) or nil
end

local function DateText(month, day, year)
  month, day, year = Num(month), Num(day), Num(year)
  if not (month and day and year) then return nil end
  if year < 100 then year = 2000 + year end
  return string.format("%04d-%02d-%02d", year, month, day)
end

local gameCache
function ACH.InvalidateGame() gameCache = nil end

function ACH.ReadGame()
  if gameCache then return gameCache end
  -- done / legacyDone / cat.done: this character (wasEarnedByMe); accountDone / legacyAccountDone: any character
  local g = { present = ACH.ApiPresent(), cats = {}, byId = {}, catCount = 0, total = 0, done = 0, hidden = 0,
    points = 0, pointsDone = 0, legacy = 0, legacyDone = 0, accountDone = 0, legacyAccountDone = 0, otherDone = 0, byMeSeen = false }
  gameCache = g
  if not g.present then return g end
  local ok, list = pcall(GetCategoryList)
  if not ok or type(list) ~= "table" then g.err = "GetCategoryList failed" return g end
  g.catCount = #list
  local info = {}
  for _, cid in ipairs(list) do
    local okI, name, parent = pcall(GetCategoryInfo, cid)
    info[cid] = { name = okI and Str(name) or nil, parent = okI and Num(parent) or nil }
  end
  for _, cid in ipairs(list) do
    local okN, n = pcall(GetCategoryNumAchievements, cid)
    n = okN and Num(n) or 0
    local ci = info[cid] or {}
    local pi = ci.parent and ci.parent ~= -1 and info[ci.parent]
    local cat = { id = cid, key = "g:" .. tostring(cid), game = true, list = {}, done = 0, accountDone = 0,
      name = ci.name or ("Category " .. tostring(cid)), parentId = (ci.parent and ci.parent ~= -1) and ci.parent or nil }
    cat.short = cat.name
    if pi and pi.name then cat.name = pi.name .. ": " .. cat.name end
    for i = 1, n do
      local okA, id, name, points, completed, month, day, year, desc, _, icon, reward, _, byMe, earnedBy =
        pcall(GetAchievementInfo, cid, i)
      id, name = okA and Num(id) or nil, okA and Str(name) or nil
      if id and name then
        if ACH.IsPlaceholder(name) then
          g.hidden = g.hidden + 1
        else
          local acct = completed == true
          if byMe ~= nil then g.byMeSeen = true end
          local a = { id = id, key = "g" .. id, game = true, name = name, desc = Str(desc) or "", points = Num(points) or 0,
            accountDone = acct, mine = acct and byMe == true, reward = Str(reward),
            icon = (Num(icon) or Str(icon)), catKey = cat.key, catName = cat.name }
          a.completed = a.mine                         -- earned by THIS character
          a.other = acct and not a.mine                -- earned, but on another character of the account
          if a.other then a.earnedBy = Str(earnedBy) end
          if acct then a.accountWhen = DateText(month, day, year) end
          if a.completed then a.when = a.accountWhen end
          a.legacy = LegacyPoints(id)
          cat.list[#cat.list + 1] = a
          g.byId[id] = a
          g.total = g.total + 1
          g.points = g.points + a.points
          if a.legacy then g.legacy = g.legacy + a.legacy end
          if acct then
            g.accountDone = g.accountDone + 1
            cat.accountDone = cat.accountDone + 1
            if a.legacy then g.legacyAccountDone = g.legacyAccountDone + a.legacy end
          end
          if a.completed then
            g.done = g.done + 1
            cat.done = cat.done + 1
            g.pointsDone = (g.pointsDone or 0) + a.points
            if a.legacy then g.legacyDone = g.legacyDone + a.legacy end
          elseif a.other then
            g.otherDone = g.otherDone + 1
          end
        end
      end
    end
    if #cat.list > 0 then g.cats[#g.cats + 1] = cat end
  end
  -- category tree from GetCategoryInfo's parent ids (Blizzard's Legacy UI nests e.g. Classes > Druid): top-level nodes
  -- in list order, each with its own achievements (node.cat) and/or children; deeper levels fold into their top ancestor
  local byCid = {}
  for _, c in ipairs(g.cats) do byCid[c.id] = c end
  local function Top(cid)
    local seen = 0
    while info[cid] and info[cid].parent and info[cid].parent ~= -1 and info[info[cid].parent] and seen < 10 do
      cid = info[cid].parent seen = seen + 1
    end
    return cid
  end
  local nodes, order = {}, {}
  for _, cid in ipairs(list) do
    local top = Top(cid)
    local n = nodes[top]
    if not n then
      n = { key = "n:" .. tostring(top), id = top, name = (info[top] and info[top].name) or ("Category " .. tostring(top)), children = {} }
      nodes[top] = n
      order[#order + 1] = n
    end
    local c = byCid[cid]
    if c then
      if cid == top then n.cat = c else n.children[#n.children + 1] = c end
    end
  end
  g.tree = {}
  for _, n in ipairs(order) do
    if n.cat or #n.children > 0 then
      n.done, n.total = 0, 0
      if n.cat then n.done, n.total = n.cat.done, #n.cat.list end
      for _, c in ipairs(n.children) do n.done, n.total = n.done + c.done, n.total + #c.list end
      g.tree[#g.tree + 1] = n
    end
  end
  g.full = g.total >= ACH.FULL_MIN and g.points > 0
  if type(GetNumCompletedAchievements) == "function" then
    local okC, t, d = pcall(GetNumCompletedAchievements)
    if okC then g.apiTotal, g.apiDone = Num(t), Num(d) end
  end
  return g
end

local function PlayerName()
  if not UnitName then return nil end
  local ok, n = pcall(UnitName, "player")
  return ok and Str(n) or nil
end

-- criteria of a game achievement, for THIS character: { name, done, cur, need, other }. A criterion completed by
-- another character (charName set and not ours), or any completed criterion of an achievement another character
-- earned, is not done here (other = true). Account-shared counters can't be split, so those read 0 here.
function ACH.GameCriteria(id)
  local out = {}
  local ga = ACH.ReadGame().byId[id]
  local me = PlayerName()
  if type(GetAchievementNumCriteria) ~= "function" or type(GetAchievementCriteriaInfo) ~= "function" then return out end
  local okN, n = pcall(GetAchievementNumCriteria, id)
  n = okN and Num(n) or 0
  for i = 1, n do
    local ok, text, _, done, qty, req, charName, _, _, qtyText = pcall(GetAchievementCriteriaInfo, id, i)
    if ok then
      local c = { name = Str(text) or ("Criteria " .. i), done = done == true, cur = Num(qty) or 0,
        need = Num(req) or 0, text = Str(qtyText) }
      charName = Str(charName)
      local byOther = (charName and charName ~= "" and me and charName ~= me) or (ga and ga.other and c.done)
      if byOther and (c.done or c.cur > 0) then
        c.other, c.done, c.cur, c.text = true, false, 0, nil
        c.otherName = charName ~= "" and charName or (ga and ga.earnedBy) or nil
      end
      if ga and ga.completed then c.done = true end
      out[#out + 1] = c
    end
  end
  return out
end

function ACH.Mode()
  local g = ACH.ReadGame()
  if g.present and #g.cats > 0 then return g.full and "game" or "game+dm" end
  return "dm"
end

ACH.MODE_LABEL = {
  game = "game achievements (full API; Dark Matter's own set is off)",
  ["game+dm"] = "game Legacy Challenges + Dark Matter achievements",
  dm = "Dark Matter achievements only (no game achievement data on this client)",
}

---------------------------------------------------------------------------
-- Dark Matter's own achievements
---------------------------------------------------------------------------
ACH.CATS = { "General", "Quests", "Dungeons and Raids", "Fishing", "Exploration", "Loot" }
local CAT_ICON = {
  General = "Interface\\Icons\\Spell_ChargePositive",
  Quests = "Interface\\Icons\\INV_Misc_Note_01",
  ["Dungeons and Raids"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
  Fishing = "Interface\\Icons\\Trade_Fishing",
  Exploration = "Interface\\Icons\\INV_Misc_Map_01",
  Loot = "Interface\\Icons\\INV_Misc_Bag_10",
}
local RAID_ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local GOLD = 10000

-- kind: level (UnitLevel, the one thing confirmed at install), count (counter c[key]), set (#s[key]),
-- boss (criteria = our seed's npc ids), fish (criteria = catalog item ids), quality (best looted quality >= need)
local DEFS = {
  -- General
  { id = "lvl10", cat = "General", name = "Getting Started", desc = "Reach level 10.", points = 5, kind = "level", need = 10 },
  { id = "lvl20", cat = "General", name = "Finding Your Feet", desc = "Reach level 20.", points = 10, kind = "level", need = 20 },
  { id = "lvl30", cat = "General", name = "Seasoned", desc = "Reach level 30.", points = 10, kind = "level", need = 30 },
  { id = "lvl40", cat = "General", name = "Veteran", desc = "Reach level 40.", points = 10, kind = "level", need = 40 },
  { id = "lvl50", cat = "General", name = "Hardened", desc = "Reach level 50.", points = 10, kind = "level", need = 50 },
  { id = "lvl60", cat = "General", name = "The Summit", desc = "Reach level 60.", points = 25, kind = "level", need = 60 },
  { id = "levels5", cat = "General", name = "Growth Spurt", desc = "Gain 5 levels with Dark Matter installed.", points = 10, kind = "count", key = "levels", need = 5 },
  -- Quests
  { id = "q1", cat = "Quests", name = "First Errand", desc = "Turn in a quest.", points = 5, kind = "count", key = "quests", need = 1 },
  { id = "q10", cat = "Quests", name = "Helping Hand", desc = "Turn in 10 quests.", points = 5, kind = "count", key = "quests", need = 10 },
  { id = "q50", cat = "Quests", name = "Dependable", desc = "Turn in 50 quests.", points = 10, kind = "count", key = "quests", need = 50 },
  { id = "q100", cat = "Quests", name = "Quest Runner", desc = "Turn in 100 quests.", points = 10, kind = "count", key = "quests", need = 100 },
  { id = "q250", cat = "Quests", name = "Hero for Hire", desc = "Turn in 250 quests.", points = 25, kind = "count", key = "quests", need = 250 },
  { id = "q500", cat = "Quests", name = "Legend of the Board", desc = "Turn in 500 quests.", points = 25, kind = "count", key = "quests", need = 500 },
  -- Dungeons and Raids (bosses resolve to npc ids in our Wowhead-Forever-cited Data_Dungeons seed)
  { id = "rfc", cat = "Dungeons and Raids", name = "Hunger Quelled", desc = "Defeat Taragaman the Hungerer in Ragefire Chasm.", points = 10, kind = "boss", bosses = { { "Ragefire Chasm", "Taragaman the Hungerer" } } },
  { id = "wc", cat = "Dungeons and Raids", name = "Nightmare's End", desc = "Defeat Mutanus the Devourer in Wailing Caverns.", points = 10, kind = "boss", bosses = { { "Wailing Caverns", "Mutanus the Devourer" } } },
  { id = "dm", cat = "Dungeons and Raids", name = "The Brotherhood Broken", desc = "Defeat Edwin VanCleef in The Deadmines.", points = 10, kind = "boss", bosses = { { "The Deadmines", "Edwin VanCleef" } } },
  { id = "hot", cat = "Dungeons and Raids", name = "Rest for the Thanes", desc = "Defeat Durgen Dirgehammer in The Hall of Thanes.", points = 10, kind = "boss", bosses = { { "The Hall of Thanes", "Durgen Dirgehammer" } } },
  { id = "sfk", cat = "Dungeons and Raids", name = "Arugal's Folly", desc = "Defeat Archmage Arugal in Shadowfang Keep.", points = 10, kind = "boss", bosses = { { "Shadowfang Keep", "Archmage Arugal" } } },
  { id = "bfd", cat = "Dungeons and Raids", name = "Depths Cleansed", desc = "Defeat Aku'mai in Blackfathom Deeps.", points = 10, kind = "boss", bosses = { { "Blackfathom Deeps", "Aku'mai" } } },
  { id = "stocks", cat = "Dungeons and Raids", name = "Riot Quelled", desc = "Defeat Bazil Thredd in The Stockade.", points = 10, kind = "boss", bosses = { { "The Stockade", "Bazil Thredd" } } },
  { id = "gnomer", cat = "Dungeons and Raids", name = "Gnomeregan Reclaimed", desc = "Defeat Mekgineer Thermaplugg in Gnomeregan.", points = 10, kind = "boss", bosses = { { "Gnomeregan", "Mekgineer Thermaplugg" } } },
  { id = "smcath", cat = "Dungeons and Raids", name = "Crusade's End", desc = "Defeat High Inquisitor Whitemane in the Scarlet Monastery Cathedral.", points = 10, kind = "boss", bosses = { { "Scarlet Monastery: Cathedral", "High Inquisitor Whitemane" } } },
  { id = "brd", cat = "Dungeons and Raids", name = "The Emperor Falls", desc = "Defeat Emperor Dagran Thaurissan in Blackrock Depths.", points = 10, kind = "boss", bosses = { { "Blackrock Depths", "Emperor Dagran Thaurissan" } } },
  { id = "scholo", cat = "Dungeons and Raids", name = "School's Out", desc = "Defeat Darkmaster Gandling in Scholomance.", points = 10, kind = "boss", bosses = { { "Scholomance", "Darkmaster Gandling" } } },
  { id = "strat", cat = "Dungeons and Raids", name = "The Baron's Last Stand", desc = "Defeat Baron Rivendare in Stratholme.", points = 10, kind = "boss", bosses = { { "Stratholme", "Baron Rivendare" } } },
  { id = "mc", cat = "Dungeons and Raids", name = "Firelord Extinguished", desc = "Defeat Ragnaros in Molten Core.", points = 25, kind = "boss", icon = RAID_ICON, bosses = { { "Molten Core", "Ragnaros" } } },
  { id = "ony", cat = "Dungeons and Raids", name = "Broodmother Slain", desc = "Defeat Onyxia in Onyxia's Lair.", points = 25, kind = "boss", icon = RAID_ICON, bosses = { { "Onyxia's Lair", "Onyxia" } } },
  { id = "boss10", cat = "Dungeons and Raids", name = "Boss Hunter", desc = "Defeat 10 different dungeon or raid bosses from the Adventure Guide.", points = 10, kind = "set", key = "bosses", need = 10 },
  { id = "kills50", cat = "Dungeons and Raids", name = "Boss Slayer", desc = "Defeat Adventure Guide bosses 50 times.", points = 10, kind = "count", key = "bossKills", need = 50 },
  -- Fishing (from our Fishing module's catch log)
  { id = "fish1", cat = "Fishing", name = "Gone Fishing", desc = "Catch something while fishing.", points = 5, kind = "count", key = "fish", need = 1 },
  { id = "fish50", cat = "Fishing", name = "Patient Angler", desc = "Make 50 catches while fishing.", points = 10, kind = "count", key = "fish", need = 50 },
  { id = "fish250", cat = "Fishing", name = "Reel Talent", desc = "Make 250 catches while fishing.", points = 10, kind = "count", key = "fish", need = 250 },
  { id = "fish1000", cat = "Fishing", name = "Salty", desc = "Make 1,000 catches while fishing.", points = 25, kind = "count", key = "fish", need = 1000 },
  { id = "fishrare", cat = "Fishing", name = "Something Shiny", desc = "Fish up an item of Rare quality or better.", points = 10, kind = "count", key = "fishRare", need = 1 },
  { id = "deviate", cat = "Fishing", name = "Deviant Behavior", desc = "Catch a Deviate Fish.", points = 5, kind = "fish", items = { 6522 } },
  { id = "fireoil", cat = "Fishing", name = "Fire and Oil", desc = "Catch an Oily Blackmouth and a Firefin Snapper.", points = 10, kind = "fish", items = { 6358, 6359 } },
  { id = "eel", cat = "Fishing", name = "Slippery Customer", desc = "Catch a Stonescale Eel.", points = 10, kind = "fish", items = { 13422 } },
  -- Exploration
  { id = "zones5", cat = "Exploration", name = "Wanderer", desc = "Visit 5 different zones.", points = 5, kind = "set", key = "zones", need = 5 },
  { id = "zones15", cat = "Exploration", name = "Traveler", desc = "Visit 15 different zones.", points = 10, kind = "set", key = "zones", need = 15 },
  { id = "zones30", cat = "Exploration", name = "Globetrotter", desc = "Visit 30 different zones.", points = 25, kind = "set", key = "zones", need = 30 },
  { id = "inst5", cat = "Exploration", name = "Dungeon Delver", desc = "Enter 5 different dungeons or raids.", points = 10, kind = "set", key = "inst", need = 5 },
  { id = "inst15", cat = "Exploration", name = "Into the Deep", desc = "Enter 15 different dungeons or raids.", points = 25, kind = "set", key = "inst", need = 15 },
  { id = "raid1", cat = "Exploration", name = "Raid Ready", desc = "Enter a raid instance.", points = 10, kind = "set", key = "raids", need = 1, icon = RAID_ICON },
  -- Loot
  { id = "green", cat = "Loot", name = "Uncommon Find", desc = "Loot an item of Uncommon quality or better.", points = 5, kind = "quality", need = 2 },
  { id = "blue", cat = "Loot", name = "Rare Find", desc = "Loot an item of Rare quality or better.", points = 10, kind = "quality", need = 3 },
  { id = "purple", cat = "Loot", name = "Epic Find", desc = "Loot an item of Epic quality or better.", points = 25, kind = "quality", need = 4 },
  { id = "loot100", cat = "Loot", name = "Pack Rat", desc = "Loot 100 items.", points = 10, kind = "count", key = "loot", need = 100 },
  { id = "gold10", cat = "Loot", name = "Pocket Change", desc = "Gain 10 gold (any source).", points = 5, kind = "count", key = "money", need = 10 * GOLD, money = true, icon = COIN_ICON },
  { id = "gold100", cat = "Loot", name = "Coin Purse", desc = "Gain 100 gold (any source).", points = 10, kind = "count", key = "money", need = 100 * GOLD, money = true, icon = COIN_ICON },
  { id = "gold1000", cat = "Loot", name = "Treasure Hoard", desc = "Gain 1,000 gold (any source).", points = 25, kind = "count", key = "money", need = 1000 * GOLD, money = true, icon = COIN_ICON },
}
ACH._DEFS = DEFS

local defs, bossIndex, broken
local function Norm(s) s = Str(s) return s and s:lower():gsub("^the ", ""):gsub("[^%w]", "") or nil end

local function BuildDefs()
  if defs then return defs end
  defs, broken = {}, {}
  bossIndex = { byNpc = {}, byName = {} }
  local byDungeon = {}
  for _, d in ipairs(NS.AdventureGuideSeed or {}) do
    byDungeon[d.name] = d
    for _, b in ipairs(d.bosses or {}) do
      if Num(b.npcId) then
        bossIndex.byNpc[b.npcId] = { boss = b.name, dungeon = d.name }
        local k = Norm(b.name)
        if k then bossIndex.byName[k] = bossIndex.byName[k] or b.npcId end
      end
    end
  end
  local catalog = {}
  for _, e in ipairs(NS.FishingCatchCatalog or {}) do catalog[e.itemId] = e end
  for _, d in ipairs(DEFS) do
    local a = { id = d.id, key = "dm:" .. d.id, cat = d.cat, catKey = "dm:" .. d.cat, catName = d.cat, name = d.name,
      desc = d.desc, points = d.points, kind = d.kind, key2 = d.key, need = d.need or 1, money = d.money,
      icon = d.icon or CAT_ICON[d.cat] }
    local ok = true
    if d.kind == "boss" then
      a.crit = {}
      for _, pair in ipairs(d.bosses) do
        local dg = byDungeon[pair[1]]
        local npc
        for _, b in ipairs(dg and dg.bosses or {}) do if b.name == pair[2] then npc = Num(b.npcId) end end
        if npc then a.crit[#a.crit + 1] = { name = pair[2], npc = npc, where = pair[1] } else ok = false end
      end
      a.need = #a.crit
    elseif d.kind == "fish" then
      a.crit = {}
      for _, id in ipairs(d.items) do
        local e = catalog[id]
        if e then
          a.crit[#a.crit + 1] = { name = e.name, item = id }
          if #d.items == 1 and e.icon then a.icon = e.icon end
        else ok = false end
      end
      a.need = #a.crit
    end
    if ok then
      defs[#defs + 1] = a
    else
      broken[#broken + 1] = d.id
    end
  end
  return defs
end
function ACH.Defs() return BuildDefs() end
function ACH.Broken() BuildDefs() return broken end
function ACH.BossIndex() BuildDefs() return bossIndex end
function ACH._Reset() defs = nil gameCache = nil end

-- per-character state: DarkMatterCharDB.ach
function ACH.CharKey()
  local n = PlayerName()
  local r
  if GetRealmName then local ok, v = pcall(GetRealmName) r = ok and Str(v) or nil end
  return n and (n .. "-" .. (r or "?")) or nil
end

-- DarkMatterCharDB is SavedVariablesPerCharacter, so this table is already per character. owner records which
-- character it belongs to. Any account-wide copy (DarkMatterDB.ach, never written by 0.4.x but guarded) moves to the
-- first character that loads without its own data, and is then removed from the account DB.
function ACH.DB()
  local c = NS.cdb
  if type(c) ~= "table" then return nil end
  local a = c.ach
  local acct = NS.db and NS.db.ach
  if type(acct) == "table" then
    if type(a) ~= "table" then a = acct a.migrated = Stamp() c.ach = a end
    NS.db.ach = nil
  end
  if type(a) ~= "table" then a = { v = 1, since = Stamp() } c.ach = a end
  if not a.owner then a.owner = ACH.CharKey() end
  if type(a.c) ~= "table" then a.c = {} end
  if type(a.s) ~= "table" then a.s = {} end
  for _, k in ipairs({ "zones", "inst", "raids", "bosses", "fishItems" }) do
    if type(a.s[k]) ~= "table" then a.s[k] = {} end
  end
  if type(a.earned) ~= "table" then a.earned = {} end
  return a
end

local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local function PlayerLevel()
  if ACH._level then return ACH._level end
  if not UnitLevel then return nil end
  local ok, l = pcall(UnitLevel, "player")
  return ok and Num(l) or nil
end

-- cur, need, criteria list ({ name, done, cur, need })
function ACH.Progress(a)
  local db = ACH.DB() or { c = {}, s = { zones = {}, inst = {}, raids = {}, bosses = {}, fishItems = {} } }
  local need = a.need or 1
  local cur, crit = 0, nil
  if a.kind == "level" then
    cur = PlayerLevel() or 0
  elseif a.kind == "count" then
    cur = Num(db.c[a.key2]) or 0
  elseif a.kind == "set" then
    cur = Count(db.s[a.key2])
  elseif a.kind == "quality" then
    cur = ((Num(db.c.lootBest) or -1) >= need) and 1 or 0
    need = 1
  elseif a.kind == "boss" or a.kind == "fish" then
    crit = {}
    for _, cr in ipairs(a.crit) do
      local n = a.kind == "boss" and Num(db.s.bosses[cr.npc]) or Num(db.s.fishItems[cr.item]) or 0
      crit[#crit + 1] = { name = cr.name, done = n > 0, cur = math.min(n, 1), need = 1, count = n }
      if n > 0 then cur = cur + 1 end
    end
  end
  if cur > need then cur = need end
  return cur, need, crit
end

local function Earned(a)
  local db = ACH.DB()
  return db and db.earned[a.id]
end
ACH.Earned = Earned

function ACH.Totals()
  local t = { count = 0, earned = 0, points = 0, pointsEarned = 0, cats = {} }
  for _, a in ipairs(BuildDefs()) do
    t.count = t.count + 1
    t.points = t.points + a.points
    local c = t.cats[a.cat] or { count = 0, earned = 0, points = 0, pointsEarned = 0 }
    t.cats[a.cat] = c
    c.count, c.points = c.count + 1, c.points + a.points
    if Earned(a) then
      t.earned, t.pointsEarned = t.earned + 1, t.pointsEarned + a.points
      c.earned, c.pointsEarned = c.earned + 1, c.pointsEarned + a.points
    end
  end
  return t
end

---------------------------------------------------------------------------
-- toast (our own frame on UIParent; built on first use)
---------------------------------------------------------------------------
local toast, toastQueue = nil, {}
local TOAST_IN, TOAST_HOLD, TOAST_OUT = 0.25, 4.5, 0.8

local function ShowNextToast()
  local a = table.remove(toastQueue, 1)
  if not a then toast:Hide() return end
  toast.cur = a
  toast.icon:SetItem(nil, 1, a.icon)
  toast.name:SetText(a.name)
  toast.sub:SetText(a.points .. " points · " .. a.cat)
  toast.t = 0
  toast:SetAlpha(0)
  toast:Show()
end

local function BuildToast()
  if toast or not (CreateFrame and NS.UI) then return toast end
  local UI = NS.UI
  toast = CreateFrame("Frame", "DarkMatterAchToast", UIParent)
  toast:SetSize(320, 64)
  toast:SetPoint("TOP", UIParent, "TOP", 0, -150)
  pcall(toast.SetFrameStrata, toast, "HIGH")
  local bg = UI.Panel(toast, 320, 64)
  bg:SetPoint("TOPLEFT", toast, "TOPLEFT", 0, 0)
  toast.icon = UI.RoundIcon(toast, 40)
  toast.icon:SetPoint("LEFT", toast, "LEFT", 12, 0)
  toast.head = UI.Text(toast, "OVERLAY", 11, "gold", "LEFT")
  toast.head:SetPoint("TOPLEFT", toast, "TOPLEFT", 62, -10)
  toast.head:SetPoint("RIGHT", toast, "RIGHT", -12, 0)
  toast.head:SetText("Dark Matter achievement earned")
  toast.name = UI.Text(toast, "OVERLAY", 15, "listInk", "LEFT")
  toast.name:SetPoint("TOPLEFT", toast, "TOPLEFT", 62, -25)
  toast.name:SetPoint("RIGHT", toast, "RIGHT", -12, 0)
  toast.sub = UI.Text(toast, "OVERLAY", 11, "listSoft", "LEFT")
  toast.sub:SetPoint("TOPLEFT", toast, "TOPLEFT", 62, -44)
  toast.sub:SetPoint("RIGHT", toast, "RIGHT", -12, 0)
  for _, fs in ipairs({ toast.head, toast.name, toast.sub }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
  toast:EnableMouse(true)
  toast:SetScript("OnMouseDown", function() toast.t = TOAST_IN + TOAST_HOLD end) -- click: fade out now
  toast:SetScript("OnUpdate", function(self, el)
    self.t = (self.t or 0) + (el or 0)
    local t = self.t
    if t < TOAST_IN then self:SetAlpha(t / TOAST_IN)
    elseif t < TOAST_IN + TOAST_HOLD then self:SetAlpha(1)
    elseif t < TOAST_IN + TOAST_HOLD + TOAST_OUT then self:SetAlpha(1 - (t - TOAST_IN - TOAST_HOLD) / TOAST_OUT)
    else ShowNextToast() end
  end)
  toast:Hide()
  return toast
end

function ACH.Toast(a)
  if not BuildToast() then return end
  toastQueue[#toastQueue + 1] = a
  if not toast:IsShown() then ShowNextToast() end
end
function ACH._ToastFrame() return toast end

---------------------------------------------------------------------------
-- award check
---------------------------------------------------------------------------
-- retro = true only for the first check after install: what the game confirms now (level) is recorded as earned at
-- install, without toasts; counters all start at 0 then, so nothing else can be awarded that way.
function ACH.Check(retro)
  local db = ACH.DB()
  if not db or ACH.Mode() == "game" then return {} end
  local new = {}
  for _, a in ipairs(BuildDefs()) do
    if not db.earned[a.id] then
      local cur, need = ACH.Progress(a)
      if need > 0 and cur >= need then
        db.earned[a.id] = { when = Stamp(), retro = retro and true or nil }
        new[#new + 1] = a
      end
    end
  end
  if #new > 0 then
    if retro then
      NS.Print(string.format("achievements: %d earned from your current level (counting everything else starts now).", #new))
    else
      for _, a in ipairs(new) do
        ACH.Toast(a)
        NS.Print("achievement earned: " .. a.name .. " (" .. a.points .. " points)")
      end
    end
  end
  if ACH.onChange then pcall(ACH.onChange) end
  return new
end

---------------------------------------------------------------------------
-- recording (each returns after updating the per-character counters)
---------------------------------------------------------------------------
local function Bump(key, n)
  local db = ACH.DB()
  if not db then return end
  db.c[key] = (Num(db.c[key]) or 0) + (n or 1)
end

local function Now() return (GetTime and Num(GetTime())) or 0 end
local recentKill = {}
function ACH.RecordBossKill(npc)
  npc = Num(npc)
  local db = ACH.DB()
  if not (db and npc and ACH.BossIndex().byNpc[npc]) then return false end
  local t = Now()
  if recentKill[npc] and t - recentKill[npc] < 60 then return false end -- ENCOUNTER_END + BOSS_KILL for one kill
  recentKill[npc] = t
  db.s.bosses[npc] = (Num(db.s.bosses[npc]) or 0) + 1
  Bump("bossKills")
  ACH.Check()
  return true
end

-- Boss corpse looted (Adventure Guide LOOT_OPENED, npc id from GetLootSourceInfo's GUID): counts the kill only when
-- no ENCOUNTER_END / BOSS_KILL counted it in the last 10 minutes, once per corpse GUID.
local lootedCorpse = {}
function ACH.RecordBossLoot(npc, guid)
  npc = Num(npc)
  if not (npc and ACH.BossIndex().byNpc[npc]) then return false end
  guid = Str(guid)
  if guid then
    if lootedCorpse[guid] then return false end
    lootedCorpse[guid] = true
  end
  if recentKill[npc] and Now() - recentKill[npc] < 600 then return false end
  return ACH.RecordBossKill(npc)
end
NS.OnBossLooted = ACH.RecordBossLoot -- called by AdventureGuide.lua's LOOT_OPENED handler

function ACH.RecordBossName(name)
  local k = Norm(name)
  local npc = k and ACH.BossIndex().byName[k]
  if npc then return ACH.RecordBossKill(npc) end
  return false
end

function ACH.OnFishCatch(_, quality, quantity, itemId)
  local db = ACH.DB()
  if not db then return end
  quantity = Num(quantity) or 1
  Bump("fish", quantity)
  if (Num(quality) or 0) >= 3 then Bump("fishRare", quantity) end
  itemId = Num(itemId)
  if itemId then db.s.fishItems[itemId] = (Num(db.s.fishItems[itemId]) or 0) + quantity end
  ACH.Check()
end
NS.OnFishCatch = ACH.OnFishCatch -- called by Fishing.lua after it records a catch

local LINK_Q = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }
function ACH.LinkQuality(link)
  link = Str(link)
  if not link then return nil end
  local id = tonumber(link:match("item:(%d+)") or "")
  if id and C_Item and type(C_Item.GetItemQualityByID) == "function" then
    local ok, q = pcall(C_Item.GetItemQualityByID, id)
    if ok and Num(q) then return q end
  end
  local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
  return hex and LINK_Q[hex:lower()] or nil
end

local lootPatterns
local function Pattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end
-- "You receive loot: %s." / "You receive loot: %sx%d." (the client's own format strings, so any locale)
function ACH.ParseLoot(msg)
  msg = Str(msg)
  if not msg then return nil end
  if not lootPatterns then
    lootPatterns = {}
    for _, f in ipairs({ _G.LOOT_ITEM_SELF_MULTIPLE, _G.LOOT_ITEM_SELF }) do
      local p = Pattern(f)
      if p then lootPatterns[#lootPatterns + 1] = p end
    end
  end
  for _, p in ipairs(lootPatterns) do
    local link, n = msg:match(p)
    if link then return link, tonumber(n) or 1 end
  end
  return nil
end

function ACH.OnLootMessage(msg)
  local link, n = ACH.ParseLoot(msg)
  if not link then return false end
  local db = ACH.DB()
  if not db then return false end
  Bump("loot", n)
  local q = ACH.LinkQuality(link)
  if q and q > (Num(db.c.lootBest) or -1) then db.c.lootBest = q end
  ACH.Check()
  return true
end

local lastMoney
function ACH.OnMoney()
  if not GetMoney then return end
  local ok, m = pcall(GetMoney)
  m = ok and Num(m) or nil
  if not m then return end
  if lastMoney and m > lastMoney then
    Bump("money", m - lastMoney)
    ACH.Check()
  end
  lastMoney = m
end
function ACH._ResetMoney() lastMoney = nil end

local function InstanceType()
  if not GetInstanceInfo then return nil end
  local ok, name, itype = pcall(GetInstanceInfo)
  if not ok then return nil end
  return Str(itype), Str(name)
end

local ev
-- Events the Forever 1.60.1 docs mark HasRestrictions = true. Registering or unregistering them from addon code is
-- forbidden; we never pass them to a frame (enforced by SafeRegister and the stubtest).
ACH.RESTRICTED_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true, MINIMAP_PING = true,
  UNIT_PING_PIN_ADDED = true, UNIT_PING_PIN_REMOVED = true }
local function SafeRegister(frame, e)
  if ACH.RESTRICTED_EVENTS[e] then return false end
  return pcall(frame.RegisterEvent, frame, e)
end

function ACH.OnZone()
  local db = ACH.DB()
  if not db then return end
  local itype, iname = InstanceType()
  local inInst = itype == "party" or itype == "raid"
  if inInst and iname then
    db.s.inst[iname] = true
    if itype == "raid" then db.s.raids[iname] = true end
  elseif itype == nil or itype == "none" then
    local okZ, z = pcall(GetRealZoneText or GetZoneText)
    z = okZ and Str(z) or nil
    if z and z ~= "" then db.s.zones[z] = true end
  end
  ACH.Check()
end

local questSeen = {}
function ACH.OnQuestTurnedIn(questId)
  questId = Num(questId)
  local t = Now()
  if questId and questSeen[questId] and t - questSeen[questId] < 3 then return end
  if questId then questSeen[questId] = t end
  Bump("quests")
  ACH.Check()
end

function ACH.OnLevelUp(newLevel)
  ACH._level = Num(newLevel) -- UnitLevel can lag one frame behind PLAYER_LEVEL_UP
  Bump("levels")
  ACH.Check()
  ACH._level = nil
end

local started
function ACH.OnEnterWorld()
  local db = ACH.DB()
  if not db then return end
  ACH.InvalidateGame()
  if not lastMoney then ACH.OnMoney() end
  if not db.retroDone then
    db.retroDone = true
    ACH.Check(true)
  end
  ACH.OnZone()
end

function ACH.Start()
  if started or not CreateFrame then return end
  started = true
  ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN",
    "PLAYER_MONEY", "CHAT_MSG_LOOT", "ENCOUNTER_END", "BOSS_KILL", "ACHIEVEMENT_EARNED", "CRITERIA_UPDATE" }) do
    SafeRegister(ev, e)
  end
  local function Handle(event, a1, a2, a5)
    if event == "PLAYER_ENTERING_WORLD" then pcall(ACH.OnEnterWorld)
    elseif event == "ZONE_CHANGED_NEW_AREA" then pcall(ACH.OnZone)
    elseif event == "PLAYER_LEVEL_UP" then pcall(ACH.OnLevelUp, a1)
    elseif event == "QUEST_TURNED_IN" then pcall(ACH.OnQuestTurnedIn, a1)
    elseif event == "PLAYER_MONEY" then pcall(ACH.OnMoney)
    elseif event == "CHAT_MSG_LOOT" then pcall(ACH.OnLootMessage, a1)
    elseif event == "ENCOUNTER_END" then
      if a5 == 1 or a5 == true then pcall(ACH.RecordBossName, a2) end
    elseif event == "BOSS_KILL" then pcall(ACH.RecordBossName, a2)
    elseif event == "ACHIEVEMENT_EARNED" or event == "CRITERIA_UPDATE" then
      ACH.InvalidateGame()
      if ACH.onChange then pcall(ACH.onChange) end
    end
  end
  ev:SetScript("OnEvent", function(_, event, a1, a2, _, _, a5)
    -- NS.ctx is named by /dm blocked if anything in here ever trips a restriction (blocked events are synchronous).
    local prev = NS.ctx
    NS.ctx = "ach:" .. tostring(event)
    pcall(Handle, event, a1, a2, a5)
    NS.ctx = prev
  end)
end
function ACH._Frame() return ev end

---------------------------------------------------------------------------
-- /dm achprobe
---------------------------------------------------------------------------
local function GameSampleLine(a)
  local crit = ACH.GameCriteria(a.id)
  local nd = 0
  for _, c in ipairs(crit) do if c.done then nd = nd + 1 end end
  return string.format("  [%d] %s (%s): %s%s", a.id, a.name, a.catName or "?",
    a.completed and ("complete" .. (a.when and (" " .. a.when) or ""))
      or (a.other and ("not yet on this character (earned on " .. (a.earnedBy or "another character")
        .. (a.accountWhen and (" " .. a.accountWhen) or "") .. ")") or "not complete"),
    #crit > 0 and string.format(", criteria %d/%d", nd, #crit) or "")
end

function ACH.ProbeReport()
  ACH.InvalidateGame()
  local g = ACH.ReadGame()
  local mode = ACH.Mode()
  local lines = {}
  local function L(s) lines[#lines + 1] = s end
  L("achprobe: mode = " .. mode .. ": " .. ACH.MODE_LABEL[mode])
  local fns = {}
  for _, n in ipairs({ "GetCategoryList", "GetCategoryInfo", "GetCategoryNumAchievements", "GetAchievementInfo",
    "GetAchievementNumCriteria", "GetAchievementCriteriaInfo", "GetNumCompletedAchievements", "GetTotalAchievementPoints" }) do
    fns[#fns + 1] = n .. "=" .. (type(_G[n]) == "function" and "yes" or "no")
  end
  L("game API: " .. table.concat(fns, " ") .. "; C_Traits.GetTraitCurrencyForAchievement="
    .. ((C_Traits and type(C_Traits.GetTraitCurrencyForAchievement) == "function") and "yes" or "no"))
  if g.present then
    L(string.format("game data: %d categories (%d with achievements), %d achievements, %d points, %d Legacy Points%s",
      g.catCount, #g.cats, g.total, g.points, g.legacy,
      g.hidden > 0 and string.format(", %d placeholder rows skipped", g.hidden) or ""))
    L(string.format("completed: %d account / %d this character (%s); Legacy Points earned: %d account / %d this character%s",
      g.accountDone, g.done, ACH.CharKey() or "?", g.legacyAccountDone, g.legacyDone,
      g.apiTotal and string.format("; GetNumCompletedAchievements = %s/%s (account)", tostring(g.apiDone), tostring(g.apiTotal)) or ""))
    if not g.byMeSeen and g.accountDone > 0 then
      L("  note: GetAchievementInfo returned no wasEarnedByMe, so nothing counts for this character")
    end
    local n = 0
    for _, c in ipairs(g.cats) do
      for _, a in ipairs(c.list) do
        if n < 3 then L(GameSampleLine(a)) n = n + 1 end
      end
    end
  end
  if mode ~= "game" then
    local t = ACH.Totals()
    local db = ACH.DB()
    L(string.format("Dark Matter (this character, %s): %d categories, %d achievements, %d earned, %d / %d points, tracking since %s",
      db and db.owner or "?", #ACH.CATS, t.count, t.earned, t.pointsEarned, t.points, db and db.since or "?"))
    local n = 0
    for _, a in ipairs(BuildDefs()) do
      if n < 3 then
        local cur, need = ACH.Progress(a)
        local e = Earned(a)
        L(string.format("  %s (%s, %d pts): %s", a.name, a.cat, a.points,
          e and ("earned " .. e.when .. (e.retro and " (level confirmed at install)" or "")) or
          (a.money and string.format("%dg / %dg", math.floor(cur / GOLD), math.floor(need / GOLD)) or (cur .. " / " .. need))))
        n = n + 1
      end
    end
  end
  if NS.db then NS.db.achprobe = { when = Stamp(), mode = mode, lines = lines } end
  return mode, lines
end
