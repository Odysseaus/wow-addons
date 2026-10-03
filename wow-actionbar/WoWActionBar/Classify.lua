local _, NS = ...
if type(NS) ~= "table" then
  WoWActionBarNS = WoWActionBarNS or {}
  NS = WoWActionBarNS
end

-- Forever (Interface 16001) is Mainline API. GetNumSpellTabs was removed in 11.0
-- and is nil here, which is the Collect crash. Same for the other spellbook globals.
NS.SpellBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local SPELL_TYPE = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1

local HEAL = {
  "heal", "healing", "rejuvenation", "regrowth", "renew", "lifebloom",
  "wild growth", "swiftmend", "nourish", "tranquility", "efflorescence",
  "penance", "holy light", "flash of light", "lay on hands", "holy shock",
  "chain heal", "healing wave", "lesser wave", "riptide", "prayer of healing",
  "circle of healing", "binding heal",
}

local function isHeal(name)
  local n = string.lower(name)
  for i = 1, #HEAL do
    if string.find(n, HEAL[i], 1, true) then
      return true
    end
  end
  return false
end

local function isConjure(name)
  local n = string.lower(name)
  return string.find(n, "conjure food", 1, true)
    or string.find(n, "conjure water", 1, true)
    or string.find(n, "ritual of refreshment", 1, true)
end

local function spellCastTime(spellId)
  if spellId and C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(spellId)
    if info and type(info.castTime) == "number" then
      return info.castTime
    end
  end
  if spellId and type(GetSpellInfo) == "function" then
    local _, _, _, castTime = GetSpellInfo(spellId)
    if type(castTime) == "number" then
      return castTime
    end
  end
  return 0
end

local function readSpellSlot(i)
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
    local info = C_SpellBook.GetSpellBookItemInfo(i, NS.SpellBank)
    if type(info) ~= "table" or info.itemType ~= SPELL_TYPE or info.isPassive then
      return nil
    end
    local spellId = info.spellID or info.actionID
    local name = info.name
    if (type(name) ~= "string" or name == "") and spellId and C_Spell and C_Spell.GetSpellName then
      name = C_Spell.GetSpellName(spellId)
    end
    if type(name) ~= "string" or name == "" then
      return nil
    end
    return name, spellId, spellCastTime(spellId)
  end
  if type(GetSpellBookItemInfo) ~= "function" then
    return nil
  end
  local skillType, spellId = GetSpellBookItemInfo(i, "spell")
  if skillType ~= "SPELL" then
    return nil
  end
  if type(IsPassiveSpell) == "function" and IsPassiveSpell(i, "spell") then
    return nil
  end
  local name, castTime
  if type(GetSpellInfo) == "function" then
    name, _, _, castTime = GetSpellInfo(i, "spell")
  end
  if type(name) ~= "string" or name == "" then
    return nil
  end
  return name, spellId, (type(castTime) == "number" and castTime) or 0
end

local function spellbookCount()
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    return tonumber(C_SpellBook.GetNumSpellBookSkillLines()) or 0
  end
  if type(GetNumSpellTabs) == "function" then
    return tonumber(GetNumSpellTabs()) or 0
  end
  return 0
end

local function spellbookTab(tab)
  if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo then
    local info = C_SpellBook.GetSpellBookSkillLineInfo(tab)
    if type(info) ~= "table" then
      return nil, nil
    end
    return tonumber(info.itemIndexOffset), tonumber(info.numSpellBookItems)
  end
  if type(GetSpellTabInfo) == "function" then
    local _, _, offset, num = GetSpellTabInfo(tab)
    return tonumber(offset), tonumber(num)
  end
  return nil, nil
end

local function containerSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  if type(GetContainerNumSlots) == "function" then
    return GetContainerNumSlots(bag) or 0
  end
  return 0
end

local function containerItemID(bag, slot)
  if C_Container and C_Container.GetContainerItemID then
    return C_Container.GetContainerItemID(bag, slot)
  end
  if type(GetContainerItemID) == "function" then
    return GetContainerItemID(bag, slot)
  end
end

local function foodName(id)
  local itemType, itemSubType
  if C_Item and C_Item.GetItemInfoInstant then
    local _, t, sub = C_Item.GetItemInfoInstant(id)
    itemType, itemSubType = t, sub
  elseif type(GetItemInfoInstant) == "function" then
    local _, t, sub = GetItemInfoInstant(id)
    itemType, itemSubType = t, sub
  elseif C_Item and C_Item.GetItemInfo then
    local name, _, _, _, _, t, sub = C_Item.GetItemInfo(id)
    if t == "Consumable" and sub == "Food & Drink" then
      return name or "Food"
    end
    return nil
  elseif type(GetItemInfo) == "function" then
    local name, _, _, _, _, t, sub = GetItemInfo(id)
    if t == "Consumable" and sub == "Food & Drink" then
      return name or "Food"
    end
    return nil
  end
  if itemType ~= "Consumable" or itemSubType ~= "Food & Drink" then
    return nil
  end
  local name
  if C_Item and C_Item.GetItemInfo then
    name = C_Item.GetItemInfo(id)
  elseif type(GetItemInfo) == "function" then
    name = GetItemInfo(id)
  end
  return name or "Food"
end

function NS.Collect()
  local best, order = {}, {}
  local tabs = spellbookCount()
  for tab = 1, tabs do
    local offset, num = spellbookTab(tab)
    if offset and num and num > 0 then
      for i = offset + 1, offset + num do
        local name, spellId, castTime = readSpellSlot(i)
        if name then
          local row = best[name]
          if not row then
            row = { name = name, index = i, spellId = spellId, castTime = castTime or 0 }
            best[name] = row
            order[#order + 1] = name
          else
            row.index = i
            row.spellId = spellId or row.spellId
            row.castTime = castTime or row.castTime
          end
        end
      end
    end
  end

  local heal, instant, cast, foodSpells = {}, {}, {}, {}
  for i = 1, #order do
    local row = best[order[i]]
    if isConjure(row.name) then
      foodSpells[#foodSpells + 1] = row
    elseif isHeal(row.name) then
      heal[#heal + 1] = row
    elseif (row.castTime or 0) == 0 then
      instant[#instant + 1] = row
    else
      cast[#cast + 1] = row
    end
  end

  local foods, seen = {}, {}
  for bag = 0, 4 do
    local n = containerSlots(bag)
    for slot = 1, n do
      local id = containerItemID(bag, slot)
      if id and not seen[id] then
        local name = foodName(id)
        if name then
          seen[id] = true
          foods[#foods + 1] = { name = name, bag = bag, slot = slot, itemId = id, kind = "item" }
        end
      end
    end
  end
  for i = 1, #foodSpells do
    foodSpells[i].kind = "spell"
    foods[#foods + 1] = foodSpells[i]
  end

  return { heal = heal, instant = instant, cast = cast, food = foods }
end

local function spellNameById(id)
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    if type(info) == "table" and type(info.name) == "string" then
      return info.name
    end
  end
  if C_Spell and C_Spell.GetSpellName then
    local name = C_Spell.GetSpellName(id)
    if type(name) == "string" then
      return name
    end
  end
  if type(GetSpellInfo) == "function" then
    return GetSpellInfo(id)
  end
end

function NS.Placed()
  local names, items = {}, {}
  for slot = 1, 120 do
    if HasAction(slot) then
      local kind, id = GetActionInfo(slot)
      if kind == "spell" and id then
        local name = spellNameById(id)
        if name then names[name] = true end
      elseif kind == "item" and id then
        items[id] = true
      end
    end
  end
  return names, items
end
