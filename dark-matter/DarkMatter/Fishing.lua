-- Fishing catch tracker. Runs on a private frame from login (stats accrue even if the
-- Journals tab is closed). Per-character SavedVariables (DarkMatterCharDB). No Blizzard
-- UI loads, no secure hooks; every API call is pcall'd and secret-safe.
local _, NS = ...

local CHAR_DEFAULTS = {
  casts = 0,
  catches = 0,
  gotAway = 0,
  junk = 0,
  good = 0,
  timeSec = 0,
  streak = 0,
  bestStreak = 0,
  goldCopper = 0,
  bestGold = nil, -- { name, copper }
  lureCounts = {}, -- [label] = cast count
  lastLure = nil,
  skillHistory = {}, -- { { t = "YYYY-MM-DD", skill = n }, ... } capped
  rares = {}, -- { { name, zone, when }, ... } capped
  zones = {}, -- [zoneName] = { catches = n, items = { [name] = { count, junk, quality, copper } } }
  lastZone = nil,
  ui = { catchMode = "zone", panel = "catches", showAll = false },
}

local state = {
  fishing = false,
  castAt = nil,
  pendingAway = nil,
  lootSeen = false,
  lastSkill = nil,
}

local MAX_RARES = 20
local MAX_HISTORY = 40
local AWAY_WINDOW = 2.5

---------------------------------------------------------------------------
-- char DB
---------------------------------------------------------------------------
local function Ensure()
  if type(DarkMatterCharDB) ~= "table" then DarkMatterCharDB = {} end
  if type(DarkMatterCharDB.fishing) ~= "table" then DarkMatterCharDB.fishing = {} end
  local f = DarkMatterCharDB.fishing
  for k, v in pairs(CHAR_DEFAULTS) do
    if f[k] == nil then
      if type(v) == "table" then f[k] = {} else f[k] = v end
    end
  end
  if type(f.zones) ~= "table" then f.zones = {} end
  if type(f.lureCounts) ~= "table" then f.lureCounts = {} end
  if type(f.rares) ~= "table" then f.rares = {} end
  if type(f.skillHistory) ~= "table" then f.skillHistory = {} end
  if type(f.ui) ~= "table" then f.ui = {} end
  if f.ui.catchMode ~= "fish" and f.ui.catchMode ~= "zone" then f.ui.catchMode = "zone" end
  if f.ui.panel ~= "stats" then f.ui.panel = "catches" end
  if f.ui.showAll ~= true then f.ui.showAll = false end
  NS.cdb = DarkMatterCharDB
  return f
end

function NS.GetFishingDB()
  return Ensure()
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function SafeStr(v)
  return NS.Str(v)
end

local function SafeNum(v)
  return NS.Num(v)
end

local function NowLabel()
  if date then
    local ok, s = pcall(date, "%b %d, %Y")
    if ok and type(s) == "string" then return s end
  end
  return "today"
end

local function DayKey()
  if date then
    local ok, s = pcall(date, "%Y-%m-%d")
    if ok and type(s) == "string" then return s end
  end
  return "unknown"
end

--- Map the player's current zone/subzone onto a FishingZones entry when possible.
function NS.ResolveFishingWater()
  local zone, sub, mini = "", "", ""
  if GetRealZoneText then local ok, v = pcall(GetRealZoneText) if ok then zone = SafeStr(v) or "" end end
  if zone == "" and GetZoneText then local ok, v = pcall(GetZoneText) if ok then zone = SafeStr(v) or "" end end
  if GetSubZoneText then local ok, v = pcall(GetSubZoneText) if ok then sub = SafeStr(v) or "" end end
  if GetMinimapZoneText then local ok, v = pcall(GetMinimapZoneText) if ok then mini = SafeStr(v) or "" end end

  local function match(name)
    if not name or name == "" then return end
    for _, z in ipairs(NS.FishingZones or {}) do
      if z.name == name then return z.name end
      if type(z.aliases) == "table" then
        for _, a in ipairs(z.aliases) do
          if a == name then return z.name end
        end
      end
    end
  end
  local hit = match(zone) or match(sub) or match(mini)
  if hit then return hit, true end

  -- soft contains match (subzone often nests under zone / city cavern names)
  local candidates = { zone, sub, mini }
  for _, z in ipairs(NS.FishingZones or {}) do
    local names = { z.name }
    if type(z.aliases) == "table" then
      for _, a in ipairs(z.aliases) do names[#names + 1] = a end
    end
    for _, label in ipairs(names) do
      for _, c in ipairs(candidates) do
        if c ~= "" and label ~= "" and (c:find(label, 1, true) or label:find(c, 1, true)) then
          return z.name, true
        end
      end
    end
  end

  local f = Ensure()
  if zone ~= "" then return zone, false end
  if f.lastZone then return f.lastZone, false end
  return "Unknown", false
end

local function IsFishingChannel()
  if not UnitChannelInfo then return false end
  local ok, name, _, _, _, _, _, _, spellID = pcall(UnitChannelInfo, "player")
  if not ok then return false end
  name = SafeStr(name)
  spellID = SafeNum(spellID)
  -- Classic fishing spell ids commonly seen; also accept a localized name containing "fish".
  if spellID == 7620 or spellID == 131474 or spellID == 131476 or spellID == 131490 then return true end
  if name and name:lower():find("fish", 1, true) then return true end
  return false
end

-- Classic Forever fishing-lure temp-enchants → item id + fallback English name.
-- GetWeaponEnchantInfo returns the enchant id, not an item; resolve via C_Item/GetItemInfo.
local LURE_BY_ENCHANT = {
  [263]  = { item = 6529,  name = "Shiny Bauble" },
  [264]  = { item = 6530,  name = "Nightcrawlers" },
  [265]  = { item = 6532,  name = "Bright Baubles" },
  [266]  = { item = 6533,  name = "Aquadynamic Fish Attractor" },
  [456]  = { item = 6811,  name = "Aquadynamic Fish Lens" },
  [463]  = { item = 7307,  name = "Flesh Eating Worm" },
}

local function ItemNameById(itemId)
  if not itemId then return nil end
  local CI = C_Item
  if CI and CI.GetItemInfo then
    local ok, name = pcall(function()
      local n = CI.GetItemInfo(itemId)
      return SafeStr(n)
    end)
    if ok and name and name ~= "" then return name end
  end
  if GetItemInfo then
    local ok, name = pcall(function()
      local n = GetItemInfo(itemId)
      return SafeStr(n)
    end)
    if ok and name and name ~= "" then return name end
  end
  return nil
end

--- Display name for the current main-hand fishing lure, or "None".
function NS.ResolveLureName(enchantId)
  enchantId = SafeNum(enchantId)
  if not enchantId then return "None" end
  local info = LURE_BY_ENCHANT[enchantId]
  if info then
    return ItemNameById(info.item) or info.name
  end
  -- Unknown enchant: still try nothing item-side; avoid "Lure #id" in the UI.
  return "Fishing lure"
end

local function CurrentLureLabel()
  if not GetWeaponEnchantInfo then return "None" end
  local ok, hasMH, _, _, mhID = pcall(GetWeaponEnchantInfo)
  if not ok or not hasMH then return "None" end
  return NS.ResolveLureName(mhID)
end

local function ParseItemId(link)
  link = SafeStr(link)
  if not link then return nil end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end


--- Player map position for last-catch tagging (Forever: C_Map when present).
-- Returns x, y in 0..1 (or nils). Never requests server data.
function NS.ReadPlayerMapPos()
  local CM = C_Map
  if CM and CM.GetBestMapForUnit and CM.GetPlayerMapPosition then
    local ok, mapId = pcall(CM.GetBestMapForUnit, "player")
    mapId = ok and SafeNum(mapId) or nil
    if mapId then
      local ok2, pos = pcall(CM.GetPlayerMapPosition, mapId, "player")
      if ok2 and pos then
        if pos.GetXY then
          local ok3, x, y = pcall(function() return pos:GetXY() end)
          if ok3 then return SafeNum(x), SafeNum(y) end
        end
        return SafeNum(pos.x), SafeNum(pos.y)
      end
    end
  end
  if GetPlayerMapPosition then
    local ok, x, y = pcall(GetPlayerMapPosition, "player")
    if ok then return SafeNum(x), SafeNum(y) end
  end
  return nil, nil
end

function NS.ParseItemId(link)
  return ParseItemId(link)
end

local function ItemIcon(itemId)
  itemId = SafeNum(itemId)
  if not itemId then return nil end
  if GetItemIcon then
    local ok, tex = pcall(GetItemIcon, itemId)
    if ok then tex = SafeStr(tex) or (type(tex) == "number" and tex) end
    if ok and tex then return tex end
  end
  local CI = C_Item
  if CI and CI.GetItemIconByID then
    local ok, tex = pcall(CI.GetItemIconByID, itemId)
    if ok and tex then return tex end
  end
  if CI and CI.GetItemInfoInstant then
    local ok, _, _, _, icon = pcall(CI.GetItemInfoInstant, itemId)
    if ok and icon then return icon end
  end
  return nil
end

function NS.FishingItemIcon(itemId)
  return ItemIcon(itemId)
end

local function ItemSellCopper(linkOrId)
  local CI = C_Item
  if not (CI and CI.GetItemInfo) then return nil end
  local ok, r = pcall(function()
    return { CI.GetItemInfo(linkOrId) }
  end)
  if not ok or type(r) ~= "table" then return nil end
  -- Classic-style multi-return: vendor price is often index 11. Prefer any numeric tail field.
  for _, idx in ipairs({ 11, 12, 10 }) do
    local n = SafeNum(r[idx])
    if n and n > 0 then return n end
  end
  return SafeNum(r[11])
end

local function ZoneBucket(f, zone)
  local z = f.zones[zone]
  if type(z) ~= "table" then
    z = { catches = 0, items = {} }
    f.zones[zone] = z
  end
  if type(z.items) ~= "table" then z.items = {} end
  return z
end

local function PushRare(f, name, zone)
  local list = f.rares
  for _, r in ipairs(list) do
    if r.name == name then return end -- first-catch only
  end
  list[#list + 1] = { name = name, zone = zone, when = NowLabel() }
  while #list > MAX_RARES do table.remove(list, 1) end
end

local function RecordSkillPoint(f, skill)
  if not skill then return end
  local key = DayKey()
  local hist = f.skillHistory
  local last = hist[#hist]
  if last and last.t == key and last.skill == skill then return end
  if last and last.t == key then
    last.skill = skill
  else
    hist[#hist + 1] = { t = key, skill = skill }
  end
  while #hist > MAX_HISTORY do table.remove(hist, 1) end
end

---------------------------------------------------------------------------
-- recording
---------------------------------------------------------------------------
local function BeginCast()
  local f = Ensure()
  f.casts = (SafeNum(f.casts) or 0) + 1
  state.fishing = true
  state.castAt = GetTime and GetTime() or 0
  state.lootSeen = false
  state.pendingAway = nil

  local zone = NS.ResolveFishingWater()
  f.lastZone = zone

  local lure = CurrentLureLabel()
  f.lastLure = lure
  f.lureCounts[lure] = (SafeNum(f.lureCounts[lure]) or 0) + 1

  local _, rank = NS.ReadFishingSkill()
  if rank then
    if state.lastSkill and rank > state.lastSkill then
      RecordSkillPoint(f, rank)
    elseif not state.lastSkill then
      RecordSkillPoint(f, rank)
    end
    state.lastSkill = rank
  end
end

local function EndChannel()
  if not state.fishing then return end
  local f = Ensure()
  if state.castAt and GetTime then
    local dt = GetTime() - state.castAt
    if dt > 0 and dt < 120 then
      f.timeSec = (SafeNum(f.timeSec) or 0) + dt
    end
  end
  state.fishing = false
  state.castAt = nil
  -- If no fishing loot arrives shortly, count a got-away.
  if not state.lootSeen then
    state.pendingAway = (GetTime and GetTime() or 0) + AWAY_WINDOW
  end
end

local function ConfirmGotAway()
  if state.lootSeen then state.pendingAway = nil return end
  if not state.pendingAway then return end
  local now = GetTime and GetTime() or 0
  if now < state.pendingAway then return end
  state.pendingAway = nil
  local f = Ensure()
  f.gotAway = (SafeNum(f.gotAway) or 0) + 1
  f.streak = 0
end

local function RecordLootSlot(f, zone, itemName, quantity, quality, link)
  quantity = SafeNum(quantity) or 1
  quality = SafeNum(quality) or 1
  itemName = SafeStr(itemName) or "Catch"
  local junk = (quality == 0)
  local copper = link and ItemSellCopper(link) or nil

  f.catches = (SafeNum(f.catches) or 0) + quantity
  if junk then
    f.junk = (SafeNum(f.junk) or 0) + quantity
    f.streak = 0
  else
    f.good = (SafeNum(f.good) or 0) + quantity
    f.streak = (SafeNum(f.streak) or 0) + quantity
    if f.streak > (SafeNum(f.bestStreak) or 0) then f.bestStreak = f.streak end
  end

  if copper and copper > 0 then
    f.goldCopper = (SafeNum(f.goldCopper) or 0) + copper * quantity
    local best = f.bestGold
    if type(best) ~= "table" or (SafeNum(best.copper) or 0) < copper then
      f.bestGold = { name = itemName, copper = copper }
    end
  end

  if quality >= 3 then
    PushRare(f, itemName, zone)
  end

  local zb = ZoneBucket(f, zone)
  zb.catches = (SafeNum(zb.catches) or 0) + quantity
  local itemId = ParseItemId(link)
  local it = zb.items[itemName]
  if type(it) ~= "table" then
    it = { count = 0, junk = junk, quality = quality, copper = copper, itemId = itemId }
    zb.items[itemName] = it
  end
  it.count = (SafeNum(it.count) or 0) + quantity
  it.junk = junk
  it.quality = quality
  if copper then it.copper = copper end
  if itemId then it.itemId = itemId end
  it.lastZone = zone
  local px, py = NS.ReadPlayerMapPos()
  if px and py then
    it.lastX, it.lastY = px, py
  end
end

local function OnFishingLoot()
  local okFish, isFish = pcall(IsFishingLoot)
  if not (okFish and isFish) then return end
  state.lootSeen = true
  state.pendingAway = nil

  local f = Ensure()
  local zone = f.lastZone or NS.ResolveFishingWater()
  f.lastZone = zone

  local n = 0
  if GetNumLootItems then
    local ok, v = pcall(GetNumLootItems)
    n = ok and SafeNum(v) or 0
  end
  for slot = 1, n do
    local ok, _, itemName, quantity, a4, a5 = pcall(GetLootSlotInfo, slot)
    if ok and SafeStr(itemName) then
      -- Classic: texture, item, qty, quality. Retail: texture, item, qty, currencyID, quality.
      local quality
      local q4, q5 = SafeNum(a4), SafeNum(a5)
      if q5 and q5 <= 8 and q4 and q4 > 8 then
        quality = q5
      elseif q4 and q4 <= 8 then
        quality = q4
      else
        quality = q5 or q4 or 1
      end
      local link
      if GetLootSlotLink then
        local ok2, l = pcall(GetLootSlotLink, slot)
        if ok2 then link = SafeStr(l) end
      end
      RecordLootSlot(f, zone, itemName, quantity, quality, link)
    end
  end
end

---------------------------------------------------------------------------
-- public queries for the UI
---------------------------------------------------------------------------
function NS.FishingFormatGold(copper)
  copper = SafeNum(copper) or 0
  if GetMoneyString then
    local ok, s = pcall(GetMoneyString, copper, true)
    if ok and type(s) == "string" then return s end
  end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return string.format("%dg %ds %dc", g, s, c) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

function NS.FishingFormatTime(sec)
  sec = math.floor(SafeNum(sec) or 0)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", m)
end

function NS.FishingZoneStats(zoneName)
  local f = Ensure()
  local z = f.zones[zoneName]
  if type(z) ~= "table" then return 0, {} end
  local items = {}
  for name, it in pairs(z.items or {}) do
    items[#items + 1] = {
      name = name,
      count = SafeNum(it.count) or 0,
      junk = it.junk and true or false,
      quality = SafeNum(it.quality) or 1,
      copper = SafeNum(it.copper),
      itemId = SafeNum(it.itemId),
      lastZone = SafeStr(it.lastZone),
      lastX = SafeNum(it.lastX),
      lastY = SafeNum(it.lastY),
    }
  end
  table.sort(items, function(a, b) return a.count > b.count end)
  return SafeNum(z.catches) or 0, items
end

function NS.FishingFavoriteZoneAndLure()
  local f = Ensure()
  local bestZone, bestN = nil, -1
  for name, z in pairs(f.zones) do
    local n = SafeNum(z.catches) or 0
    if n > bestN then bestN, bestZone = n, name end
  end
  -- Prefer a real lure name over "None". Migrate legacy "Lure #<enchantId>" keys (two-pass).
  do
    local legacy = {}
    for name, n in pairs(f.lureCounts) do
      if type(name) == "string" and name:match("^Lure #%d+$") then
        legacy[#legacy + 1] = { name = name, n = SafeNum(n) or 0 }
      end
    end
    for _, e in ipairs(legacy) do
      local label = NS.ResolveLureName(tonumber(e.name:match("%d+")))
      f.lureCounts[label] = (SafeNum(f.lureCounts[label]) or 0) + e.n
      f.lureCounts[e.name] = nil
    end
  end
  local bestLure, bestL = nil, -1
  local noneN = 0
  for name, n in pairs(f.lureCounts) do
    n = SafeNum(n) or 0
    if name == "None" then
      noneN = n
    elseif n > bestL then
      bestL, bestLure = n, name
    end
  end
  if not bestLure then
    bestLure, bestL = "None", noneN
  end
  return bestZone, bestN, bestLure, bestL
end

---------------------------------------------------------------------------
-- events (always on after login)
---------------------------------------------------------------------------
local frame

local function OnUpdate()
  if state.pendingAway then ConfirmGotAway() end
end

local function OnEvent(_, event, unit)
  if event == "ADDON_LOADED" then return end
  if event == "PLAYER_LOGIN" then
    Ensure()
    local _, rank = NS.ReadFishingSkill()
    state.lastSkill = rank
    return
  end
  if event == "UNIT_SPELLCAST_CHANNEL_START" then
    if unit == "player" and IsFishingChannel() then BeginCast() end
    return
  end
  if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    if unit == "player" then EndChannel() end
    return
  end
  if event == "LOOT_READY" or event == "LOOT_OPENED" then
    OnFishingLoot()
    return
  end
  -- UI_ERROR_MESSAGE is handled by OnError via the SetScript wrapper below.
  if event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
    local f = Ensure()
    local _, rank = NS.ReadFishingSkill()
    if rank and state.lastSkill and rank > state.lastSkill then
      RecordSkillPoint(f, rank)
    end
    state.lastSkill = rank or state.lastSkill
  end
end

-- Separate handler so we can read the message arg correctly.
local function OnError(_, _, message)
  message = SafeStr(message)
  if not message then return end -- message from UI_ERROR_MESSAGE
  local lower = message:lower()
  if lower:find("got away", 1, true) or lower:find("fish", 1, true) and lower:find("away", 1, true) then
    state.lootSeen = false
    local f = Ensure()
    f.gotAway = (SafeNum(f.gotAway) or 0) + 1
    f.streak = 0
    state.pendingAway = nil
  end
end


--- Catch types for Catches-by-fish.
-- showAll false: only items this character has logged.
-- showAll true: full NS.FishingCatchCatalog; caught items highlighted + sorted to top; uncaught below.
function NS.FishingCatchTypes(showAll, search)
  local f = Ensure()
  local caught = {} -- keyed by name
  for zoneName, z in pairs(f.zones or {}) do
    if type(z) == "table" and type(z.items) == "table" then
      for name, it in pairs(z.items) do
        local e = caught[name]
        if not e then
          e = {
            name = name,
            count = 0,
            junk = it.junk and true or false,
            quality = SafeNum(it.quality) or 1,
            copper = SafeNum(it.copper),
            itemId = SafeNum(it.itemId),
            caught = true,
            lastZone = SafeStr(it.lastZone),
            lastX = SafeNum(it.lastX),
            lastY = SafeNum(it.lastY),
            zones = {},
          }
          caught[name] = e
        end
        e.count = e.count + (SafeNum(it.count) or 0)
        if SafeNum(it.itemId) then e.itemId = SafeNum(it.itemId) end
        e.zones[zoneName] = (e.zones[zoneName] or 0) + (SafeNum(it.count) or 0)
        -- prefer most recently written last* on any zone bucket (loot overwrites)
        if it.lastZone then
          e.lastZone = SafeStr(it.lastZone)
          e.lastX = SafeNum(it.lastX)
          e.lastY = SafeNum(it.lastY)
        end
      end
    end
  end

  local list, total = {}, 0
  search = search and tostring(search):lower() or ""

  local function want(name)
    return search == "" or (name and name:lower():find(search, 1, true))
  end

  if showAll then
    local seen = {}
    for _, cat in ipairs(NS.FishingCatchCatalog or {}) do
      local name = cat.name
      if name and want(name) then
        seen[name] = true
        local c = caught[name]
        if c then
          list[#list + 1] = c
          total = total + c.count
        else
          list[#list + 1] = {
            name = name,
            count = 0,
            junk = cat.junk and true or false,
            quality = cat.junk and 0 or 1,
            itemId = cat.itemId,
            caught = false,
            lastZone = nil,
            lastX = nil,
            lastY = nil,
            zones = {},
          }
        end
      end
    end
    -- logged items not in catalog still appear (caught, top)
    for name, c in pairs(caught) do
      if not seen[name] and want(name) then
        list[#list + 1] = c
        total = total + c.count
      end
    end
    table.sort(list, function(a, b)
      if a.caught ~= b.caught then return a.caught end
      if a.count ~= b.count then return a.count > b.count end
      return (a.name or "") < (b.name or "")
    end)
  else
    for _, c in pairs(caught) do
      if want(c.name) then
        list[#list + 1] = c
        total = total + c.count
      end
    end
    table.sort(list, function(a, b) return a.count > b.count end)
  end
  return list, total
end

function NS.FishingFormatCoords(x, y)
  x, y = SafeNum(x), SafeNum(y)
  if not x or not y then return nil end
  -- map positions are 0..1; show as classic percent coords
  return string.format("%.1f, %.1f", x * 100, y * 100)
end

function NS.FishingUIPrefs()
  local f = Ensure()
  return f.ui
end

function NS.FishingSetUIPref(key, value)
  local f = Ensure()
  f.ui[key] = value
end

function NS.StartFishingTracker()
  Ensure()
  if frame then return end
  frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_LOGIN")
  frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
  frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
  frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
  frame:RegisterEvent("LOOT_READY")
  frame:RegisterEvent("LOOT_OPENED")
  pcall(function() frame:RegisterEvent("SKILL_LINES_CHANGED") end)
  pcall(function() frame:RegisterEvent("CHAT_MSG_SKILL") end)
  pcall(function() frame:RegisterEvent("UI_ERROR_MESSAGE") end)
  frame:SetScript("OnEvent", function(self, event, a1, a2, a3)
    if event == "UI_ERROR_MESSAGE" then
      OnError(self, a1, a2)
    else
      OnEvent(self, event, a1, a2, a3)
    end
  end)
  frame:SetScript("OnUpdate", function() OnUpdate() end)
end

-- test hooks (stub suite)
NS._FishingTest = {
  BeginCast = BeginCast,
  EndChannel = EndChannel,
  OnFishingLoot = OnFishingLoot,
  Ensure = Ensure,
  state = state,
  ResolveLureName = NS.ResolveLureName,
  CurrentLureLabel = CurrentLureLabel,
}
