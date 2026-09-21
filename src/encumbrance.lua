local Items = require("items")

local Encumbrance = {}

Encumbrance.BASE_CAPACITY = 12
Encumbrance.CAPACITY_PER_LEVEL = 4
Encumbrance.BURDENED_MULT = 1.5

Encumbrance.LIGHT = "light"
Encumbrance.BURDENED = "burdened"
Encumbrance.OVERLOADED = "overloaded"

Encumbrance.BURDENED_SPEED_PENALTY = -20
Encumbrance.OVERLOADED_SPEED_PENALTY = -45
Encumbrance.OVERLOADED_DEFENSE_PENALTY = -2

local BASE_WEIGHT = {
  [Items.POTION] = 2,
  [Items.SCROLL] = 1,
  [Items.WEAPON] = 6,
  [Items.ARMOR] = 9,
  [Items.RING] = 1,
  [Items.FOOD] = 3,
  [Items.KEY] = 1,
  [Items.TOME] = 4,
  [Items.AMULET] = 2,
  [Items.BOW] = 7,
  [Items.AMMO] = 1,
  [Items.GOLD] = 0,
  [Items.GEM] = 1,
  [Items.CHARM] = 2,
  [Items.KIT] = 3,
  [Items.HERB] = 1,
  [Items.CONTRACT] = 1,
}

local POWER_SCALES = {
  [Items.WEAPON] = true,
  [Items.ARMOR] = true,
  [Items.BOW] = true,
}

local STACK_FIELD = {
  [Items.AMMO] = "count",
  [Items.GOLD] = "amount",
}

function Encumbrance.itemWeight(item)
  local weight = BASE_WEIGHT[item.kind] or 1
  if POWER_SCALES[item.kind] then
    weight = weight + (item.power or 0) // 3
  end
  local stackField = STACK_FIELD[item.kind]
  if stackField then
    weight = weight * (item[stackField] or 1)
  end
  return weight
end

function Encumbrance.carriedWeight(entity)
  local total = 0
  for _, item in ipairs(entity.inventory) do
    total = total + Encumbrance.itemWeight(item)
  end
  for _, slot in ipairs({ "weapon", "armor", "ring", "bow" }) do
    local equipped = entity[slot]
    if equipped then total = total + Encumbrance.itemWeight(equipped) end
  end
  return total
end

function Encumbrance.capacityFor(entity)
  return Encumbrance.BASE_CAPACITY + (entity.level or 1) * Encumbrance.CAPACITY_PER_LEVEL
end

function Encumbrance.tierFor(entity)
  local carried = Encumbrance.carriedWeight(entity)
  local capacity = Encumbrance.capacityFor(entity)
  if carried <= capacity then return Encumbrance.LIGHT end
  if carried <= capacity * Encumbrance.BURDENED_MULT then return Encumbrance.BURDENED end
  return Encumbrance.OVERLOADED
end

function Encumbrance.speedPenalty(entity)
  local tier = Encumbrance.tierFor(entity)
  if tier == Encumbrance.BURDENED then return Encumbrance.BURDENED_SPEED_PENALTY end
  if tier == Encumbrance.OVERLOADED then return Encumbrance.OVERLOADED_SPEED_PENALTY end
  return 0
end

function Encumbrance.defensePenalty(entity)
  if Encumbrance.tierFor(entity) == Encumbrance.OVERLOADED then
    return Encumbrance.OVERLOADED_DEFENSE_PENALTY
  end
  return 0
end

return Encumbrance
