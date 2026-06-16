-- Weapon, armor and bow wear: unlike digging.lua's pick, a single limited-use
-- tool discarded outright once spent, a piece of gear wears down from
-- ordinary use but survives reaching zero - it just stops contributing to
-- combat until repaired, exactly like disenchanting a rune off a weapon
-- strips its bonus without destroying the weapon itself (see crafting.lua).
-- A weapon or armor's power is baked straight into the wielder's
-- attack/defense the instant it is equipped (see items.lua's
-- Items.equipWeapon/equipArmor), so breaking or repairing one here adjusts
-- that same baked total by the identical delta swapping gear already uses -
-- never a separate "effective power" read live in combat. A bow is the one
-- exception: its power is read live at the point of firing (see
-- ranged.lua's Ranged.fire), so Durability.effectivePower covers that
-- instead. Only the player's own gear wears at all - monsters have no
-- inventory management or repair access, so wear is never applied to theirs.

local Durability = {}

Durability.MAX = 30
Durability.WEAR_PER_HIT = 1
Durability.REPAIR_COST_PER_POINT = 2

-- Lazily stamps a fresh durability pair onto `item` the moment anything
-- first asks about it, so an item built before this field existed on it
-- (a raw table assembled somewhere this module cannot see) still gets a
-- sensible default rather than an error.
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

-- A broken bow contributes nothing to a shot's damage; read live in
-- Ranged.fire in place of a bare `bow.power`.
function Durability.effectivePower(item)
  if not item then return 0 end
  if Durability.isBroken(item) then return 0 end
  return item.power or 0
end

local function isPlayerOwned(entity)
  return entity.kind == "player"
end

-- Wears one point off `entity.weapon`, subtracting its power out of
-- entity.attack the instant it actually breaks (never before, and never
-- twice for the same break). A no-op, nil return, for an unarmed entity or
-- one whose weapon already sits at zero.
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

-- A bow's power is never baked into attack, so breaking one touches no stat
-- - Ranged.fire simply stops reading any power out of it via
-- Durability.effectivePower.
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

-- Spends `entity.gold` to restore `entity`'s gear in `slotName` (one of
-- "weapon", "armor", "bow") fully, folding its power back into attack or
-- defense if the break had already stripped it out. Fails without spending
-- anything for an empty slot, an already-pristine item, or too thin a purse.
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
