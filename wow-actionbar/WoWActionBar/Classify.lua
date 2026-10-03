local _, NS = ...
if type(NS) ~= "table" then
  WoWActionBarNS = WoWActionBarNS or {}
  NS = WoWActionBarNS
end

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

function NS.Collect()
  local best, order = {}, {}
  local tabs = GetNumSpellTabs()
  for tab = 1, tabs do
    local _, _, offset, num = GetSpellTabInfo(tab)
    for i = offset + 1, offset + num do
      local skillType, spellId = GetSpellBookItemInfo(i, "spell")
      if skillType == "SPELL" and not IsPassiveSpell(i, "spell") then
        local name, _, _, castTime = GetSpellInfo(i, "spell")
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
    local n = GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local id = GetContainerItemID(bag, slot)
      if id and not seen[id] then
        local name, _, _, _, _, itemType, itemSubType = GetItemInfo(id)
        if itemType == "Consumable" and itemSubType == "Food & Drink" then
          seen[id] = true
          foods[#foods + 1] = { name = name or "Food", bag = bag, slot = slot, itemId = id, kind = "item" }
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

function NS.Placed()
  local names, items = {}, {}
  for slot = 1, 120 do
    if HasAction(slot) then
      local kind, id = GetActionInfo(slot)
      if kind == "spell" and id then
        local name = GetSpellInfo(id)
        if name then names[name] = true end
      elseif kind == "item" and id then
        items[id] = true
      end
    end
  end
  return names, items
end
