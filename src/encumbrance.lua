-- Carry weight. Every item kind has a physical weight (gear scales a little
-- with its power, the way a heavier blade hits harder); a carrier's capacity
-- grows with level, the same knob progression.lua turns for hp. Exceeding
-- capacity does not block a pickup outright - it slows the carrier down
-- instead (see Entity:effectiveSpeed), and a wide overage on top of that also
-- costs defense, the same shape a status.lua debuff takes (see
-- Entity:effectiveDefense). Nothing here is persisted: weight is entirely a
-- function of entity.inventory and entity.level, both already serialized, so
-- a save/load round trip recomputes the identical tier for free.
--
-- Monsters are never excluded from these checks (there is no species flag to
-- opt out), but their inventory is always empty in practice - abilities.lua
-- and combat.lua never stash loot on a monster - so in play this only ever
-- matters for the player.

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

-- Base weight per item kind, before any power-scaling below. Kinds absent
-- here (gold, keys) default to a flat 1 rather than 0: even a featherweight
-- trinket takes up some of the pack, and a strictly-zero-weight kind would
-- let a hoard of them carry for free.
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

-- Kinds whose power rating (a straightforward proxy for how much metal went
-- into them) adds a little extra weight on top of the flat base.
local POWER_SCALES = {
  [Items.WEAPON] = true,
  [Items.ARMOR] = true,
  [Items.BOW] = true,
}

-- Kinds that stack into one inventory slot via a `count`/`amount` field, so
-- their weight must scale with the stack rather than being charged once.
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

-- Loose inventory plus whatever is currently worn or wielded: a sword on
-- your belt weighs exactly as much as one in your pack.
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
