local _, NS = ...
if type(NS) ~= "table" then
  WoWActionBarNS = WoWActionBarNS or {}
  NS = WoWActionBarNS
end

WoWActionBar = WoWActionBar or {}
local WA = WoWActionBar

local BARS = {
  { key = "main", label = "Main", first = 1, last = 12, default = true },
  { key = "bottomRight", label = "Bottom right", first = 49, last = 60, default = true },
  { key = "bottomLeft", label = "Bottom left", first = 61, last = 72, default = true },
  { key = "right", label = "Right", first = 25, last = 36, default = false },
  { key = "left", label = "Left", first = 37, last = 48, default = false },
}
NS.BARS = BARS

local DEFAULT_ORDER = { "heal", "instant", "cast", "food" }

function WA.EnsureDB()
  local db = WoWActionBarDB or {}
  WoWActionBarDB = db
  if db.gap == nil then db.gap = 1 end
  if db.locked == nil then db.locked = false end
  if db.organized == nil then db.organized = false end
  db.bars = db.bars or {}
  for i = 1, #BARS do
    local b = BARS[i]
    if db.bars[b.key] == nil then db.bars[b.key] = b.default end
  end
  if type(db.order) ~= "table" or #db.order == 0 then
    db.order = { "heal", "instant", "cast", "food" }
  end
  return db
end

local function say(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WoW Action Bar|r " .. msg)
end
NS.Say = say

local function enabledSlots(db)
  local slots = {}
  for i = 1, #BARS do
    local b = BARS[i]
    if db.bars[b.key] then
      for s = b.first, b.last do
        slots[#slots + 1] = s
      end
    end
  end
  return slots
end

local function placeSpell(slot, index)
  if HasAction(slot) then return false end
  ClearCursor()
  if C_SpellBook and C_SpellBook.PickupSpellBookItem then
    C_SpellBook.PickupSpellBookItem(index, NS.SpellBank or 0)
  elseif type(PickupSpellBookItem) == "function" then
    PickupSpellBookItem(index, "spell")
  else
    return false
  end
  if type(CursorHasSpell) ~= "function" or not CursorHasSpell() or HasAction(slot) then
    ClearCursor()
    return false
  end
  PlaceAction(slot)
  ClearCursor()
  return HasAction(slot)
end

local function placeItem(slot, bag, bagSlot)
  if HasAction(slot) then return false end
  ClearCursor()
  if C_Container and C_Container.PickupContainerItem then
    C_Container.PickupContainerItem(bag, bagSlot)
  elseif type(PickupContainerItem) == "function" then
    PickupContainerItem(bag, bagSlot)
  else
    return false
  end
  if type(CursorHasItem) ~= "function" or not CursorHasItem() or HasAction(slot) then
    ClearCursor()
    return false
  end
  PlaceAction(slot)
  ClearCursor()
  return HasAction(slot)
end

function WA.Organize(force)
  local db = WA.EnsureDB()
  if db.locked and not force then
    say("Locked. Unlock in settings, then organize.")
    return
  end
  if InCombatLockdown() then
    WA._pending = true
    say("In combat. I'll organize when combat ends.")
    return
  end
  if GetCursorInfo() then
    say("Your cursor is holding something. Clear it, then try again.")
    return
  end

  local groups = NS.Collect()
  local placedNames, placedItems = NS.Placed()
  local slots = enabledSlots(db)
  local idx = 1
  local placed = 0
  local gap = tonumber(db.gap) or 0
  if gap < 0 then gap = 0 end
  if gap > 3 then gap = 3 end
  local firstBucket = true

  for oi = 1, #db.order do
    local key = db.order[oi]
    local list = groups[key]
    if list and #list > 0 then
      local usable = {}
      for i = 1, #list do
        local row = list[i]
        if row.kind == "item" then
          if not placedItems[row.itemId] then usable[#usable + 1] = row end
        elseif not placedNames[row.name] then
          usable[#usable + 1] = row
        end
      end
      if #usable > 0 then
        if not firstBucket and gap > 0 then
          local skipped = 0
          while idx <= #slots and skipped < gap do
            if not HasAction(slots[idx]) then skipped = skipped + 1 end
            idx = idx + 1
          end
        end
        firstBucket = false
        for i = 1, #usable do
          while idx <= #slots and HasAction(slots[idx]) do idx = idx + 1 end
          if idx > #slots then break end
          local row = usable[i]
          local ok = false
          if row.kind == "item" then
            ok = placeItem(slots[idx], row.bag, row.slot)
            if ok then placedItems[row.itemId] = true end
          else
            ok = placeSpell(slots[idx], row.index)
            if ok then placedNames[row.name] = true end
          end
          if ok then
            placed = placed + 1
            idx = idx + 1
          else
            idx = idx + 1
          end
        end
      end
    end
  end

  db.organized = true
  db.locked = true
  WA._pending = false
  say("Placed " .. placed .. " into empty slots, then locked. Drag stays normal. /wa opens settings.")
  if NS.RefreshSettings then NS.RefreshSettings() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
  WA.EnsureDB()
  if event == "PLAYER_REGEN_ENABLED" and WA._pending then
    WA.Organize(false)
    return
  end
  if event == "PLAYER_LOGIN" then
    local db = WA.EnsureDB()
    if not db.organized and not db.locked then
      if C_Timer and C_Timer.After then
        C_Timer.After(1.5, function() WA.Organize(false) end)
      else
        WA.Organize(false)
      end
    end
  end
end)

SLASH_WOWACTIONBAR1 = "/wa"
SLASH_WOWACTIONBAR2 = "/wowactionbar"
SlashCmdList.WOWACTIONBAR = function(msg)
  msg = string.lower(msg or "")
  if msg == "organize" then
    local db = WA.EnsureDB()
    if db.locked then
      say("Unlock first, then /wa organize.")
      return
    end
    WA.Organize(true)
    return
  end
  if NS.ToggleSettings then NS.ToggleSettings() end
end
