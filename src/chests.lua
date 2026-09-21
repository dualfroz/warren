local Items = require("items")
local Affixes = require("affixes")
local Status = require("status")

local Chests = {}

Chests.LOCK_CHANCE_NUMERATOR = 1
Chests.LOCK_CHANCE_DENOMINATOR = 2

Chests.TRAP_CHANCE_NUMERATOR = 1
Chests.TRAP_CHANCE_DENOMINATOR = 3

Chests.PICK_BASE_NUMERATOR = 1
Chests.PICK_BASE_DENOMINATOR = 2
Chests.PICK_LEVEL_BONUS_DIVISOR = 5

Chests.TRAP_DART_MIN = 2
Chests.TRAP_DART_MAX = 5

Chests.GOLD_MIN_BONUS = 0
Chests.GOLD_MAX_BONUS = 10
Chests.GOLD_BASE = 10
Chests.GOLD_PER_DEPTH = 6

local chestWeapons = {
  { name = "ornate rapier", power = 4 },
  { name = "gilded axe",    power = 5 },
}
local chestArmors = {
  { name = "banded mail", power = 3 },
}

local function rollLoot(rng, depth)
  local loot = { Items.gold(Chests.GOLD_BASE + depth * Chests.GOLD_PER_DEPTH
    + rng:range(Chests.GOLD_MIN_BONUS, Chests.GOLD_MAX_BONUS)) }
  if rng:chance(1, 2) then
    local base = chestWeapons[rng:range(1, #chestWeapons)]
    loot[#loot + 1] = Affixes.decorate(Items.weapon(base.name, base.power + depth // 4), Affixes.rollWeapon(rng))
  else
    local base = chestArmors[rng:range(1, #chestArmors)]
    loot[#loot + 1] = Affixes.decorate(Items.armor(base.name, base.power + depth // 4), Affixes.rollArmor(rng))
  end
  if rng:chance(1, 2) then
    loot[#loot + 1] = Items.potionOf("heal")
  end
  return loot
end

function Chests.new(rng, depth)
  local locked = rng:chance(Chests.LOCK_CHANCE_NUMERATOR, Chests.LOCK_CHANCE_DENOMINATOR)
  local trapped = locked and rng:chance(Chests.TRAP_CHANCE_NUMERATOR, Chests.TRAP_CHANCE_DENOMINATOR)
  return {
    locked = locked,
    trapped = trapped,
    opened = false,
    loot = rollLoot(rng, depth),
  }
end

function Chests.isLocked(chest)
  return chest.locked and not chest.opened
end

function Chests.oddsFor(player)
  local numerator = Chests.PICK_BASE_NUMERATOR + player.level // Chests.PICK_LEVEL_BONUS_DIVISOR
  if numerator > Chests.PICK_BASE_DENOMINATOR - 1 then
    numerator = Chests.PICK_BASE_DENOMINATOR - 1
  end
  return numerator, Chests.PICK_BASE_DENOMINATOR
end

local function grant(player, chest)
  for _, item in ipairs(chest.loot) do
    player.inventory[#player.inventory + 1] = item
  end
  chest.opened = true
  chest.loot = {}
end

function Chests.open(player, chest)
  if chest.opened then return false, "this chest is already empty" end
  if Chests.isLocked(chest) then return false, "the chest is locked" end
  grant(player, chest)
  return true, "you open the chest and take its hoard"
end

function Chests.unlockWithKey(player, chest)
  if not Chests.isLocked(chest) then return false, "this chest has no lock to open" end
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.KEY then
      table.remove(player.inventory, i)
      chest.locked = false
      grant(player, chest)
      return true, "you unlock the chest with your key"
    end
  end
  return false, "you have no key"
end

function Chests.springTrap(game, chest)
  chest.trapped = false
  local player = game.player
  if game.rng:chance(1, 2) then
    local dealt = game.rng:range(Chests.TRAP_DART_MIN, Chests.TRAP_DART_MAX)
    player.hp = player.hp - dealt
    return string.format("a needle trap jabs you for %d", dealt)
  end
  Status.apply(player, Status.POISON, 5, 2)
  return "a cloud of poison bursts from the lock"
end

function Chests.pick(game, chest)
  local player = game.player
  if not Chests.isLocked(chest) then return false, "this chest has no lock to pick" end
  local pickIndex
  for i, item in ipairs(player.inventory) do
    if item.kind == Items.LOCKPICK then pickIndex = i; break end
  end
  if not pickIndex then return false, "you have no lockpicks" end
  table.remove(player.inventory, pickIndex)
  local numerator, denominator = Chests.oddsFor(player)
  if not game.rng:chance(numerator, denominator) then
    if chest.trapped then return false, Chests.springTrap(game, chest) end
    return false, "your lockpick slips and the lock holds"
  end
  chest.locked = false
  grant(player, chest)
  return true, "your lockpick clicks the lock open"
end

return Chests
