local Durability = {}

Durability.MAX = 30
Durability.WEAR_PER_HIT = 1
Durability.REPAIR_COST_PER_POINT = 2

function Durability.ensure(item)
  if not item.durability then
    item.durability = Durability.MAX
    item.maxDurability = Durability.MAX
  end
  return item
end

function Durability.isBroken(item)
  Durability.ensure(item)
  return item.durability <= 0
end

function Durability.effectivePower(item)
  if not item then return 0 end
  if Durability.isBroken(item) then return 0 end
  return item.power or 0
end

local function isPlayerOwned(entity)
  return entity.kind == "player"
end

function Durability.wearWeapon(entity)
  local item = entity.weapon
  if not item then return nil end
  Durability.ensure(item)
  if item.durability <= 0 then return nil end
  item.durability = item.durability - Durability.WEAR_PER_HIT
  if item.durability <= 0 then
    entity.attack = entity.attack - item.power
    return isPlayerOwned(entity) and ("your " .. item.name .. " breaks apart from wear")
      or (entity.name .. "'s " .. item.name .. " breaks apart from wear")
  end
  return nil
end

function Durability.wearArmor(entity)
  local item = entity.armor
  if not item then return nil end
  Durability.ensure(item)
  if item.durability <= 0 then return nil end
  item.durability = item.durability - Durability.WEAR_PER_HIT
  if item.durability <= 0 then
    entity.defense = entity.defense - item.power
    return isPlayerOwned(entity) and ("your " .. item.name .. " is battered to uselessness")
      or (entity.name .. "'s " .. item.name .. " is battered to uselessness")
  end
  return nil
end

function Durability.wearBow(entity)
  local item = entity.bow
  if not item then return nil end
  Durability.ensure(item)
  if item.durability <= 0 then return nil end
  item.durability = item.durability - Durability.WEAR_PER_HIT
  if item.durability <= 0 then
    return isPlayerOwned(entity) and ("your " .. item.name .. " snaps from wear")
      or (entity.name .. "'s " .. item.name .. " snaps from wear")
  end
  return nil
end

function Durability.missing(item)
  Durability.ensure(item)
  return item.maxDurability - item.durability
end

function Durability.repairCost(item)
  return Durability.missing(item) * Durability.REPAIR_COST_PER_POINT
end

function Durability.repair(entity, slotName)
  local item = entity[slotName]
  if not item then return false, "nothing equipped there" end
  Durability.ensure(item)
  if item.durability >= item.maxDurability then return false, "already in perfect condition" end
  local cost = Durability.repairCost(item)
  if entity.gold < cost then return false, "not enough gold" end
  local wasBroken = item.durability <= 0
  entity.gold = entity.gold - cost
  item.durability = item.maxDurability
  if wasBroken and slotName == "weapon" then entity.attack = entity.attack + item.power end
  if wasBroken and slotName == "armor" then entity.defense = entity.defense + item.power end
  return true, cost
end

return Durability
