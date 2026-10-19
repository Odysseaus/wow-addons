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

-- Valid icon: fileID number, or an Interface\... texture path. Rejects item type/subtype strings.
local function CoerceIcon(tex)
  if issecretvalue and issecretvalue(tex) then return nil end
  if type(tex) == "number" and tex > 0 then return tex end
  if type(tex) == "string" and tex ~= "" then
    local low = tex:lower()
    if low:find("^interface[\\/]") then return tex end
  end
  return nil
end

local catalogIconById
local function CatalogIcon(itemId)
  if not catalogIconById then
    catalogIconById = {}
    for _, e in ipairs(NS.FishingCatchCatalog or {}) do
      if e.itemId and e.icon then catalogIconById[e.itemId] = e.icon end
    end
  end
  return catalogIconById[itemId]
end

function NS.FishingCatalogIcon(itemId)
  itemId = SafeNum(itemId)
  return itemId and CatalogIcon(itemId) or nil
end

local function ItemIcon(itemId)
  itemId = SafeNum(itemId)
  if not itemId then return nil end
  local CI = C_Item
  -- 1) GetItemInfoInstant (cache-free): itemID, type, subType, equipLoc, icon, classID, subclassID
  if CI and CI.GetItemInfoInstant then
    local ok, _, _, _, _, icon = pcall(CI.GetItemInfoInstant, itemId)
    icon = ok and CoerceIcon(icon) or nil
    if icon then return icon end
  end
  if GetItemInfoInstant then
    local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, itemId)
    icon = ok and CoerceIcon(icon) or nil
    if icon then return icon end
  end
  -- 2) Icon-by-id APIs
  if CI and CI.GetItemIconByID then
    local ok, tex = pcall(CI.GetItemIconByID, itemId)
    tex = ok and CoerceIcon(tex) or nil
    if tex then return tex end
  end
  if GetItemIcon then
    local ok, tex = pcall(GetItemIcon, itemId)
    tex = ok and CoerceIcon(tex) or nil
    if tex then return tex end
  end
  -- 3) GetItemInfo 10th return (texture) when cached
  if GetItemInfo then
    local ok, tex = pcall(function() return select(10, GetItemInfo(itemId)) end)
    tex = ok and CoerceIcon(tex) or nil
    if tex then return tex end
  end
  -- 4) Static Classic paths from the catalog
  return CatalogIcon(itemId)
end

function NS.FishingItemIcon(itemId)
  return ItemIcon(itemId)
end

-- Async load: request item data once; GET_ITEM_INFO_RECEIVED refreshes the open fishing list.
local iconRequested = {}
local iconEv
function NS.FishingRequestItemIcon(itemId)
  itemId = SafeNum(itemId)
  if not itemId or iconRequested[itemId] then return end
  iconRequested[itemId] = true
  local CI = C_Item
  if CI and CI.RequestLoadItemDataByID then
    pcall(CI.RequestLoadItemDataByID, itemId)
  end
  if not iconEv and CreateFrame then
    iconEv = CreateFrame("Frame")
    pcall(function() iconEv:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
    pcall(function() iconEv:RegisterEvent("ITEM_DATA_LOAD_RESULT") end)
    iconEv:SetScript("OnEvent", function()
      if NS._iconRefreshPending then return end
      NS._iconRefreshPending = true
      local function run()
        NS._iconRefreshPending = false
        local t = NS.tabs and NS.tabs.journals
        local fr = t and t.frame
        if t and t.Refresh and fr and fr.IsShown and fr:IsShown() then t.Refresh() end
      end
      if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
    end)
  end
end

-- Quality 0..5 for rarity border (prefer stored, then catalog junk, then item APIs).
function NS.FishingItemQuality(itemId, stored)
  local q = SafeNum(stored)
  if q then return q end
  itemId = SafeNum(itemId)
  if not itemId then return 1 end
  local byId = NS.FishingCatalogById and NS.FishingCatalogById()
  local cat = byId and byId[itemId]
  if cat and cat.junk then return 0 end
  if GetItemInfo then
    local ok, qual = pcall(function()
      local _, _, q2 = GetItemInfo(itemId)
      return SafeNum(q2)
    end)
    if ok and qual then return qual end
  end
  local CI = C_Item
  if CI and CI.GetItemInfo then
    local ok, qual = pcall(function()
      local t = { CI.GetItemInfo(itemId) }
      return SafeNum(t[3])
    end)
    if ok and qual then return qual end
  end
  return 1
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

---------------------------------------------------------------------------
-- Catalog: static (Data_FishingCatches.lua) + per-account learned catalog
---------------------------------------------------------------------------
-- Per-account store of fishing loot that is not in the static catalog.
-- DarkMatterDB.fishingCatalogLearned[itemId] = { itemId, name, icon, quality, firstZone, firstSeen }
local function LearnedDB()
  if type(DarkMatterDB) ~= "table" then return nil end
  if type(DarkMatterDB.fishingCatalogLearned) ~= "table" then DarkMatterDB.fishingCatalogLearned = {} end
  return DarkMatterDB.fishingCatalogLearned
end

function NS.FishingLearnedCatalog()
  return LearnedDB() or {}
end

-- Add a fished item to the learned catalog the first time it is seen (static catalog items are skipped).
local function LearnCatalogItem(itemId, name, icon, quality, zone)
  itemId = SafeNum(itemId)
  name = SafeStr(name)
  if not itemId or not name then return false end
  local byId = NS.FishingCatalogById and NS.FishingCatalogById() or {}
  if byId[itemId] then return false end
  local db = LearnedDB()
  if not db then return false end
  local e = db[itemId]
  if type(e) == "table" then
    -- fill gaps only; first zone / first seen stay as recorded
    if not CoerceIcon(e.icon) and CoerceIcon(icon) then e.icon = CoerceIcon(icon) end
    if not SafeNum(e.quality) and SafeNum(quality) then e.quality = SafeNum(quality) end
    return false
  end
  db[itemId] = {
    itemId = itemId,
    name = name,
    icon = CoerceIcon(icon),
    quality = SafeNum(quality),
    firstZone = SafeStr(zone),
    firstSeen = DayKey(),
  }
  return true
end
NS._FishingLearn = LearnCatalogItem

-- classicOnly entries are hidden unless this client confirms the item exists (cached per session).
local existsCache = {}
local function ClientHasItem(itemId)
  local v = existsCache[itemId]
  if v ~= nil then return v end
  v = false
  local CI = C_Item
  if CI and CI.DoesItemExistByID then
    local ok, r = pcall(CI.DoesItemExistByID, itemId)
    v = (ok and r == true) and true or false
  end
  existsCache[itemId] = v
  return v
end

function NS.FishingCatalogEntryVisible(e)
  if type(e) ~= "table" or not e.itemId then return false end
  if not e.classicOnly then return true end
  return ClientHasItem(e.itemId)
end

function NS._FishingResetExistsCache() existsCache = {} end

-- ---------------------------------------------------------------------------
-- Row tooltips (0.2.8, placement 0.2.10). Plain GameTooltip use from our own rows: SetOwner +
-- SetHyperlink/SetItemByID, then our lines. No hooks, no secure frames.
-- ---------------------------------------------------------------------------

-- Extract a bare "item:..." string from a loot link (or accept one); nil otherwise.
function NS.FishingItemString(link)
  link = SafeStr(link)
  if not link then return nil end
  local s = link:match("|H(item:[%-%d:]+)|h") or link:match("^(item:[%-%d:]+)$")
  return s
end

local QUALITY_NAMES = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
local QUALITY_RGB = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
  [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}
local function QualityRGB(q)
  if GetItemQualityColor then
    local ok, r, g, b = pcall(GetItemQualityColor, q)
    if ok and type(r) == "number" then return r, g, b end
  end
  local c = QUALITY_RGB[q] or QUALITY_RGB[1]
  return c[1], c[2], c[3]
end

-- True when the client has item data in cache (so SetItemByID fills the tooltip now).
local function ItemCached(itemId)
  if not itemId then return false end
  local CI = C_Item
  if CI and CI.IsItemDataCachedByID then
    local ok, v = pcall(CI.IsItemDataCachedByID, itemId)
    if ok and v ~= nil then return v and true or false end
  end
  if GetItemInfo then
    local ok, name = pcall(GetItemInfo, itemId)
    return ok and type(name) == "string" and name ~= ""
  end
  return false
end
NS._FishingItemCached = ItemCached

-- Name as the client knows it (only when item data is cached); nil otherwise.
function NS.FishingClientItemName(itemId)
  itemId = SafeNum(itemId)
  if not (itemId and ItemCached(itemId) and GetItemInfo) then return nil end
  local ok, name = pcall(GetItemInfo, itemId)
  if ok and type(name) == "string" and name ~= "" then return name end
  return nil
end

-- Rows show the client name; any difference from our catalog name is logged for /dm fishcheck.
function NS.FishingNoteNameMismatch(itemId, ours, client)
  local db = NS.db
  if not (db and itemId and ours and client) or ours == client then return end
  db.fishcheck = db.fishcheck or {}
  db.fishcheck.seen = db.fishcheck.seen or {}
  db.fishcheck.seen[itemId] = { itemId = itemId, catalog = ours, client = client, date = DayKey() }
end

-- /dm fishcheck: compare every static + learned catalog name with the client's item name.
-- Writes DarkMatterDB.fishcheck = { at, checked, uncached, mismatches = { {itemId, catalog, client} } }.
function NS.FishingCheckCatalog()
  local res = { at = DayKey(), checked = 0, uncached = 0, mismatches = {}, uncachedIds = {} }
  local function one(itemId, name)
    itemId = SafeNum(itemId)
    if not (itemId and name) then return end
    res.checked = res.checked + 1
    local client = NS.FishingClientItemName(itemId)
    if not client then
      res.uncached = res.uncached + 1
      res.uncachedIds[#res.uncachedIds + 1] = itemId
      if NS.FishingRequestItemIcon then NS.FishingRequestItemIcon(itemId) end
    elseif client ~= name then
      res.mismatches[#res.mismatches + 1] = { itemId = itemId, catalog = name, client = client }
    end
  end
  for _, e in ipairs(NS.FishingCatchCatalog or {}) do
    if NS.FishingCatalogEntryVisible(e) then one(e.itemId, e.name) end
  end
  for itemId, l in pairs(NS.FishingLearnedCatalog()) do
    if type(l) == "table" then one(itemId, l.name) end
  end
  table.sort(res.mismatches, function(a, b) return a.itemId < b.itemId end)
  if NS.db then
    local prev = NS.db.fishcheck
    res.seen = prev and prev.seen or nil
    NS.db.fishcheck = res
  end
  return res
end

-- Fill GameTooltip for one catch-type row entry. total = all logged catches (for share %).
-- Returns "item" when the client item tooltip was used, "fallback" otherwise.
-- Tooltip placement (0.2.15 rule, replaces all earlier ones). Anchor = the row's item ICON.
--  default (with or without compare): the leftmost tooltip of the set (the main GameTooltip; compares chain to
--    its right, bottoms aligned) has its BOTTOMLEFT 4 units (visible, inset-corrected) right of and above the
--    icon's TOPRIGHT.
--  set would run off the right edge: mirror - the rightmost tooltip (main) has its BOTTOMRIGHT 4 units left of
--    and above the icon's TOPLEFT, compares chained to its LEFT.
--  no room above: below the icon, corners mirrored vertically (TOP* at the icon's BOTTOM*, tops aligned).
-- We own GameTooltip with ANCHOR_PRESERVE so GameTooltip_AnchorComparisonTooltips never slides it
-- (it only calls SetAnchorType when the type is not ANCHOR_PRESERVE). No hooks; we just re-point frames.
local TIP_GAP = 4
NS.FISH_TIP_GAP = TIP_GAP
-- The classic tooltip border art (backdrop insets) is drawn ~3 units inside the frame edge, so a frame placed
-- 4 units from the item showed its visible border ~7 units away (measured on the 0.2.12 screenshot). SetPoint
-- offsets are reduced by this inset so the *visible* edge is TIP_GAP from the item corner.
local TIP_INSET = 3
NS.FISH_TIP_INSET = TIP_INSET
local function Num(f, m)
  local fn = f and f[m]
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, f)
  if ok and type(v) == "number" then return v end
  return nil
end

-- cw/ch: total width / max height of shown compare tooltips (0/nil when none).
-- Returns point, relPoint, x, y, compareSide ("right"/"left"), vertical ("up"/"down").
function NS.FishingTooltipAnchor(tt, owner, cw, ch)
  cw = cw or 0
  local hasCompare = cw > 0
  local os, ts = Num(owner, "GetEffectiveScale") or 1, Num(tt, "GetEffectiveScale") or 1
  local us = Num(UIParent, "GetEffectiveScale") or 1
  local left, right, top = Num(owner, "GetLeft"), Num(owner, "GetRight"), Num(owner, "GetTop")
  local w, h = Num(tt, "GetWidth"), Num(tt, "GetHeight")
  local screenW, screenH = Num(UIParent, "GetWidth"), Num(UIParent, "GetHeight")
  local g = TIP_GAP * ts
  -- room for the "up-left" set (main left of the row's left edge; compares further left)
  local function fitsLeftSet()
    if not (left and w) then return true end
    return left * os - g - (w + cw) * ts >= 0
  end
  -- room for the "up-right" set (main right of the row's right edge; compares further right)
  local function fitsRightSet()
    if not (right and w and screenW) then return true end
    return right * os + g + (w + cw) * ts <= screenW * us
  end
  -- free space on each side of the row (screen units); used when neither set fits
  local function roomLeft() return left and (left * os) or 0 end
  local function roomRight() return (right and screenW) and (screenW * us - right * os) or 0 end
  -- default right of the icon; mirror only when the set runs off the right edge (and the left is better)
  local fl, fr = fitsLeftSet(), fitsRightSet()
  local useRight = fr or (not fl and roomRight() >= roomLeft())
  local fitsTop = true
  local hh = math.max(h or 0, ch or 0)
  if top and h and screenH then fitsTop = (top * os + g + hh * ts) <= screenH * us end
  -- why this side was chosen (screen units), for /dm tipdebug
  NS._FishingLastDecision = {
    roomLeft = roomLeft(), roomRight = roomRight(), need = (w and (w + cw) * ts or 0) + g,
    fitsLeft = fl, fitsRight = fr, fitsTop = fitsTop, compare = hasCompare,
    scales = { ui = us, tip = ts, anchor = os },
  }
  local v1, v2 = fitsTop and "BOTTOM" or "TOP", fitsTop and "TOP" or "BOTTOM"
  local y = fitsTop and TIP_GAP or -TIP_GAP
  if useRight then
    return v1 .. "LEFT", v2 .. "RIGHT", TIP_GAP, y, "right", fitsTop and "up" or "down"
  end
  return v1 .. "RIGHT", v2 .. "LEFT", -TIP_GAP, y, "left", fitsTop and "up" or "down"
end

-- Compare tooltips Blizzard showed for our GameTooltip (ShoppingTooltip1/2), in chain order.
local function ShownCompares(tt)
  local list, cw, ch = {}, 0, 0
  for i = 1, 2 do
    local st = _G["ShoppingTooltip" .. i]
    if st and st.IsShown and st:IsShown() then
      local owned = true
      if st.GetOwner then
        local ok, o = pcall(st.GetOwner, st)
        owned = ok and o == tt
        if not owned and st.IsOwned then
          local ok2, yes = pcall(st.IsOwned, st, tt)
          owned = ok2 and yes and true or false
        end
      end
      if owned then
        list[#list + 1] = st
        cw = cw + (Num(st, "GetWidth") or 0)
        ch = math.max(ch, Num(st, "GetHeight") or 0)
      end
    end
  end
  return list, cw, ch
end

-- The placement anchor is the row's item icon (a Frame); rows without one use the row itself.
local function AnchorOf(owner)
  local ic = owner and owner.icon
  if type(ic) == "table" and type(ic.GetRight) == "function" then return ic end
  return owner
end
NS._FishingAnchorOf = AnchorOf

-- /dm tipdebug: after each placement, record the final points/rects of the tooltips and the anchor
local function FrameLabel(f, owner, anchor)
  if f == nil then return "nil" end
  if f == anchor and anchor ~= owner then return "icon" end
  if f == owner then return "row" end
  local ok, n = pcall(function() return f:GetName() end)
  if ok and n then return n end
  if f == UIParent then return "UIParent" end
  return tostring(f)
end
local function R(v) return v and math.floor(v * 10 + 0.5) / 10 or nil end
local function DescribeFrame(f, owner, anchor)
  if not f then return nil end
  local d = { shown = (f.IsShown and f:IsShown()) and true or false, points = {} }
  local okN, n = pcall(function() return f:GetNumPoints() end)
  n = (okN and type(n) == "number") and n or 0
  for i = 1, n do
    local ok, p, rel, rp, x, y = pcall(f.GetPoint, f, i)
    if ok and p then
      d.points[#d.points + 1] = string.format("%s>%s:%s %s,%s", p, FrameLabel(rel, owner, anchor), tostring(rp), tostring(R(x)), tostring(R(y)))
    end
  end
  local ok, l, b, w, h = pcall(function() return f:GetRect() end)
  if ok and l then d.rect = { R(l), R(b), R(w), R(h) } end
  d.scale = R(Num(f, "GetEffectiveScale"))
  return d
end
local tipDebugPrinted = 0
local function TipDebugRecord(tt, owner, anchor, reason, side, vert, nc)
  local db = NS.db
  local td = db and db.tipdebug
  if not (td and td.on) then return end
  local rec = {
    at = date("%H:%M:%S"), reason = reason, side = side, vert = vert, compares = nc,
    item = owner and owner.catchName,
    frames = {
      GameTooltip = DescribeFrame(tt, owner, anchor),
      ShoppingTooltip1 = DescribeFrame(_G.ShoppingTooltip1, owner, anchor),
      ShoppingTooltip2 = DescribeFrame(_G.ShoppingTooltip2, owner, anchor),
      anchor = DescribeFrame(anchor, owner, anchor),
      row = DescribeFrame(owner, owner, anchor),
      UIParent = DescribeFrame(UIParent, owner, anchor),
    },
  }
  -- visible gap estimate: frame gap between the tooltip and the icon, plus the border inset
  local ar, gr = rec.frames.anchor and rec.frames.anchor.rect, rec.frames.GameTooltip and rec.frames.GameTooltip.rect
  if ar and gr and ar[1] and gr[1] then
    local aL, aB, aR, aT = ar[1], ar[2], ar[1] + ar[3], ar[2] + ar[4]
    local gL, gB, gR, gT = gr[1], gr[2], gr[1] + gr[3], gr[2] + gr[4]
    local dx = side == "right" and (gL - aR) or (aL - gR)
    local dy = vert == "up" and (gB - aT) or (aB - gT)
    rec.delta = { frameX = R(dx), frameY = R(dy), visibleX = R(dx + TIP_INSET), visibleY = R(dy + TIP_INSET), inset = TIP_INSET }
  end
  rec.decision = NS._FishingLastDecision
  td.last = rec
  td.log = td.log or {}
  table.insert(td.log, rec)
  while #td.log > 40 do table.remove(td.log, 1) end
  td.count = (td.count or 0) + 1
  if tipDebugPrinted < 6 and NS.Print then
    tipDebugPrinted = tipDebugPrinted + 1
    local function rs(d) return d and d.rect and string.format("%s,%s %sx%s", d.rect[1], d.rect[2], d.rect[3], d.rect[4]) or "-" end
    local g, s1 = rec.frames.GameTooltip, rec.frames.ShoppingTooltip1
    NS.Print(string.format("tipdebug %s %s/%s: tip %s [%s] icon %s cmp1 %s [%s]", reason, tostring(side), tostring(vert),
      g and g.points[1] or "-", rs(g), rs(rec.frames.anchor), (s1 and s1.shown) and (s1.points[1] or "-") or "hidden", rs(s1)))
    local dc, fr = rec.decision, rec.frames
    if dc then
      local function sc(d) return d and tostring(d.scale) or "-" end
      NS.Print(string.format("tipdebug scale ui %s tip %s icon %s row %s | row %s icon %s | room L %s R %s need %s -> %s%s",
        sc(fr.UIParent), sc(fr.GameTooltip), sc(fr.anchor), sc(fr.row), rs(fr.row), rs(fr.anchor),
        tostring(R(dc.roomLeft)), tostring(R(dc.roomRight)), tostring(R(dc.need)), tostring(side),
        (side == "left") and " (mirrored: no room on the right)" or ""))
    end
    local d = rec.delta
    if d then
      NS.Print(string.format("tipdebug icon %s vs tip %s: frame gap x=%s y=%s, visible ~x=%s y=%s (inset %s, target 4)",
        rs(rec.frames.anchor), rs(g), tostring(d.frameX), tostring(d.frameY), tostring(d.visibleX), tostring(d.visibleY), tostring(d.inset)))
    end
  end
end
NS._FishingTipDebugRecord = TipDebugRecord

function NS.FishingToggleTipDebug()
  local db = NS.db
  if not db then return nil end
  db.tipdebug = db.tipdebug or {}
  db.tipdebug.on = not db.tipdebug.on
  tipDebugPrinted = 0
  return db.tipdebug.on
end

local expected = {} -- frame -> { point, relativeTo } we last set
local function PlaceTooltip(tt, owner, reason)
  local compares, cw, ch = ShownCompares(tt)
  local anchor = AnchorOf(owner)
  local point, rel, x, y, side, vert = NS.FishingTooltipAnchor(tt, anchor, cw, ch)
  expected = {}
  local px = x > 0 and (x - TIP_INSET) or (x + TIP_INSET)
  local py = y > 0 and (y - TIP_INSET) or (y + TIP_INSET)
  tt:ClearAllPoints()
  tt:SetPoint(point, anchor, rel, px, py)
  expected[tt] = { point, anchor }
  local prev = tt
  for _, st in ipairs(compares) do
    st:ClearAllPoints()
    local v = vert == "up" and "BOTTOM" or "TOP"
    local sp = v .. (side == "right" and "LEFT" or "RIGHT")
    st:SetPoint(sp, prev, v .. (side == "right" and "RIGHT" or "LEFT"), 0, 0)
    expected[st] = { sp, prev }
    prev = st
  end
  if reason then TipDebugRecord(tt, owner, anchor, reason, side, vert, #compares) end
  return side, vert, #compares
end

-- Something else (the client's compare code, a late size change) moved a tooltip: true if our points are gone.
local function PointsChanged()
  for f, want in pairs(expected) do
    local ok, p, rel = pcall(f.GetPoint, f, 1)
    if not ok or p ~= want[1] or rel ~= want[2] then return true end
    if f.GetNumPoints then
      local ok2, n = pcall(f.GetNumPoints, f)
      if ok2 and type(n) == "number" and n > 1 then return true end
    end
  end
  return false
end

-- size/visibility signature of the main + compare tooltips
local function Signature(tt)
  local t = {}
  for _, f in ipairs({ tt, _G.ShoppingTooltip1, _G.ShoppingTooltip2 }) do
    local shown = f and f.IsShown and f:IsShown()
    t[#t + 1] = shown and string.format("%d:%d", math.floor((Num(f, "GetWidth") or 0) + 0.5), math.floor((Num(f, "GetHeight") or 0) + 0.5)) or "-"
  end
  return table.concat(t, ",")
end

-- While one of our rows owns the tooltip, re-apply placement whenever the client re-anchors a tooltip or a
-- size changes (compare tooltips fill and resize after Show). Own hidden frame; stops when the tooltip goes.
local watch
local function StartWatch(tt, owner)
  if not CreateFrame then return end
  if not watch then
    watch = CreateFrame("Frame")
    watch:Hide()
    watch:SetScript("OnUpdate", function(self)
      local w = self.target
      if not w then self:Hide() return end
      local ok, owned = pcall(w.tt.IsOwned, w.tt, w.owner)
      if not (ok and owned and w.tt:IsShown()) then self.target = nil self:Hide() return end
      local sig = Signature(w.tt)
      local moved = PointsChanged()
      w.frames = (w.frames or 0) + 1
      local changed = sig ~= w.sig or moved
      -- re-apply on any change, and every frame for the first 10 frames after show (settling)
      if changed or w.frames <= 10 then
        PlaceTooltip(w.tt, w.owner, changed and (moved and "repoint" or "resize") or nil)
        w.sig = Signature(w.tt)
        if changed then w.fixes = (w.fixes or 0) + 1 end
      end
    end)
  end
  watch.target = { tt = tt, owner = owner, sig = Signature(tt) }
  watch:Show()
end
NS._FishingTooltipWatch = function() return watch end
NS._FishingPlaceTooltip = PlaceTooltip

-- Shift-compare: this client's GameTooltip has no MODIFIER_STATE_CHANGED handler; compare is decided in
-- OnTooltipSetItem. While one of our rows is hovered we rebuild the tooltip on modifier changes (own frame).
local hover -- { owner, e, total }
local modEv
local function EnsureModifierWatch()
  if modEv or not CreateFrame then return end
  modEv = CreateFrame("Frame")
  pcall(function() modEv:RegisterEvent("MODIFIER_STATE_CHANGED") end)
  modEv:SetScript("OnEvent", function()
    local h = hover
    if not h then return end
    local tt = GameTooltip
    local owned = tt and tt.IsOwned and select(2, pcall(tt.IsOwned, tt, h.owner))
    if owned then NS.FishingShowCatchTooltip(h.owner, h.e, h.total) else hover = nil end
  end)
end

function NS.FishingShowCatchTooltip(owner, e, total)
  local tt = GameTooltip
  if not (tt and owner and type(e) == "table") then return nil end
  -- ANCHOR_PRESERVE: Blizzard's compare code leaves our points alone (no slide onto the cursor)
  tt:SetOwner(owner, "ANCHOR_PRESERVE")
  PlaceTooltip(tt, owner)
  hover = { owner = owner, e = e, total = total }
  EnsureModifierWatch()
  local itemId = SafeNum(e.itemId)
  local mode = "fallback"
  if itemId and ItemCached(itemId) then
    local ok
    if e.link and tt.SetHyperlink then
      ok = pcall(tt.SetHyperlink, tt, e.link)
    end
    if not ok and tt.SetItemByID then
      ok = pcall(tt.SetItemByID, tt, itemId)
    end
    if ok then mode = "item" end
  end
  local q = NS.FishingItemQuality and NS.FishingItemQuality(itemId, e.quality) or (SafeNum(e.quality) or 1)
  if mode == "fallback" then
    local r, g, b = QualityRGB(q)
    tt:AddLine(e.name or "?", r, g, b)
    tt:AddLine(QUALITY_NAMES[q] or "Item", 0.8, 0.8, 0.8)
    if itemId and NS.FishingRequestItemIcon then NS.FishingRequestItemIcon(itemId) end
    -- no item on the tooltip: drop any compare tooltips left from a previous row
    if GameTooltip_HideShoppingTooltips and tt.shoppingTooltips then pcall(GameTooltip_HideShoppingTooltips, tt) end
  end
  -- Dark Matter lines
  tt:AddLine(" ")
  tt:AddLine("Dark Matter", 1, 0.82, 0)
  local caught = e.caught and (SafeNum(e.count) or 0) > 0
  if caught then
    local count = SafeNum(e.count) or 0
    local pct = (SafeNum(total) or 0) > 0 and string.format(" (%.0f%%)", 100 * count / total) or ""
    tt:AddDoubleLine("Caught", tostring(count) .. pct, 0.9, 0.9, 0.9, 1, 1, 1)
    local where = e.lastZone or "unknown"
    local coords = NS.FishingFormatCoords(e.lastX, e.lastY)
    if coords then where = where .. " (" .. coords .. ")" end
    tt:AddDoubleLine("Last caught", where, 0.9, 0.9, 0.9, 1, 1, 1)
  else
    tt:AddLine("Not caught yet", 0.75, 0.75, 0.75)
    if e.learned then
      tt:AddDoubleLine("First seen", (e.firstZone or "this account") .. (e.firstSeen and (" · " .. e.firstSeen) or ""), 0.9, 0.9, 0.9, 1, 1, 1)
    end
  end
  if not caught or e.waters then
    if e.waters then tt:AddDoubleLine("Typical waters", e.waters, 0.9, 0.9, 0.9, 1, 1, 1) end
    if e.skill then tt:AddDoubleLine("Fishing skill", tostring(e.skill), 0.9, 0.9, 0.9, 1, 1, 1) end
  end
  if e.junk then tt:AddLine("Junk", 0.62, 0.62, 0.62) end
  tt:Show()
  -- sizes are known after Show: place main + compare tooltips; the watcher keeps them there
  tipDebugPrinted = 0
  PlaceTooltip(tt, owner, "show")
  StartWatch(tt, owner)
  return mode
end

function NS.FishingHideCatchTooltip(owner)
  local tt = GameTooltip
  if not tt then return end
  if tt.IsOwned then
    local ok, owned = pcall(tt.IsOwned, tt, owner)
    if ok and not owned then return end
  end
  hover = nil
  if watch then watch.target = nil watch:Hide() end
  tt:Hide()
end

local function RecordLootSlot(f, zone, itemName, quantity, quality, link, lootTex)
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
  local itemString = NS.FishingItemString(link)
  if itemString then it.link = itemString end
  local iconTex = CoerceIcon(lootTex)
  if iconTex then it.icon = iconTex end
  if itemId then LearnCatalogItem(itemId, itemName, iconTex, quality, zone) end
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
    local ok, lootTex, itemName, quantity, a4, a5 = pcall(GetLootSlotInfo, slot)
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
      RecordLootSlot(f, zone, itemName, quantity, quality, link, lootTex)
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
-- showAll true: static catalog (classicOnly gated by DoesItemExistByID) + learned catalog + own catches,
-- deduped by itemId; caught, then learned, then uncaught. Third return: { catalog, caught, learned, static }.
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
            icon = CoerceIcon(it.icon),
            link = NS.FishingItemString(it.link),
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
        if not e.icon then e.icon = CoerceIcon(it.icon) end
        if not e.link then e.link = NS.FishingItemString(it.link) end
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

  -- Older records may lack itemId (no loot link): resolve from catalog by name.
  local byName = NS.FishingCatalogByName and NS.FishingCatalogByName() or {}
  for name, e in pairs(caught) do
    local cat = byName[name]
    if cat then
      if not e.itemId then e.itemId = cat.itemId end
      if cat.junk then e.junk = true end
    end
  end

  search = search and tostring(search):lower() or ""
  local function want(name)
    return search == "" or (name and name:lower():find(search, 1, true)) and true or false
  end

  -- Own catches, keyed by itemId when known (else by name) so every source dedupes on itemId.
  local merged, order = {}, {}
  local function key(itemId, name) return itemId and ("i" .. itemId) or ("n" .. tostring(name)) end
  local function put(k, e)
    if not merged[k] then order[#order + 1] = k end
    merged[k] = e
  end
  local byNameKey = {}
  for name, e in pairs(caught) do
    local k = key(e.itemId, name)
    if merged[k] then
      -- same item logged under two names: fold counts
      merged[k].count = merged[k].count + e.count
    else
      e.source = "caught"
      put(k, e)
    end
    byNameKey[name] = k
  end

  local stats = { catalog = 0, caught = 0, learned = 0, static = 0 }

  if showAll then
    -- Learned (per-account) catalog
    for itemId, l in pairs(NS.FishingLearnedCatalog()) do
      itemId = SafeNum(itemId) or SafeNum(type(l) == "table" and l.itemId)
      local name = type(l) == "table" and SafeStr(l.name)
      if itemId and name then
        local k = byNameKey[name] or key(itemId, name)
        local c = merged[k]
        if c then
          c.learned = true
          c.firstZone = c.firstZone or SafeStr(l.firstZone)
          c.firstSeen = c.firstSeen or SafeStr(l.firstSeen)
        else
          put(k, {
            name = name, count = 0, itemId = itemId, caught = false, learned = true, source = "learned",
            icon = CoerceIcon(l.icon), quality = SafeNum(l.quality) or 1, junk = (SafeNum(l.quality) == 0),
            firstZone = SafeStr(l.firstZone), firstSeen = SafeStr(l.firstSeen), zones = {},
          })
        end
      end
    end
    -- Static catalog (classicOnly entries need client confirmation)
    for _, cat in ipairs(NS.FishingCatchCatalog or {}) do
      local k = byNameKey[cat.name] or key(cat.itemId, cat.name)
      local c = merged[k]
      if c then
        c.waters = c.waters or cat.waters
        c.skill = c.skill or cat.skill
        c.cat = c.cat or cat.cat
        if not c.icon then c.icon = cat.icon end
        stats.static = stats.static + 1
      elseif NS.FishingCatalogEntryVisible(cat) then
        put(k, {
          name = cat.name, count = 0, itemId = cat.itemId, caught = false, source = "static",
          junk = cat.junk and true or false, quality = cat.quality or (cat.junk and 0 or nil),
          icon = cat.icon, waters = cat.waters, skill = cat.skill, cat = cat.cat, zones = {},
        })
        stats.static = stats.static + 1
      end
    end
  end

  local list, total = {}, 0
  for _, k in ipairs(order) do
    local e = merged[k]
    stats.catalog = stats.catalog + 1
    if e.caught then stats.caught = stats.caught + 1 end
    if e.learned then stats.learned = stats.learned + 1 end
    if e.caught then total = total + (e.count or 0) end
    if want(e.name) then list[#list + 1] = e end
  end
  -- caught first, then learned (seen on this account), then the rest of the catalog
  local function rank(e) return e.caught and 0 or (e.learned and 1 or 2) end
  table.sort(list, function(a, b)
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
    return (a.name or "") < (b.name or "")
  end)
  return list, total, stats
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
