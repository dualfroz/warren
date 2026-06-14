-- Lockable loot containers scattered through the dungeon: an unlocked chest
-- yields its hoard the instant it is opened, a locked one demands either a
-- spent key (Items.KEY, the same key a locked door already consumes) or a
-- lockpick gamble (Items.LOCKPICK) that risks springing the chest's own trap
-- on a failed pick - a second, riskier route into the same treasure rather
-- than a strictly worse one, since a lockpick is commoner floor loot than a
-- key. Only a locked chest can be trapped at all: there is no lock to punish
-- fumbling with on one that was never going to resist in the first place.
-- A chest never moves and never decays; once opened it stays on the map as
-- an emptied husk exactly like a corpse past its last butchering, so a
-- second visit finds nothing left to take. Chests are plain data on
-- level.chests, exactly like level.corpses and level.nodes, so they
-- serialize with no special save-format handling.

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

-- One chest's hoard: always some gold plus a coin flip between a lightly
-- affixed weapon or armor piece (see affixes.lua) and, half the time on top
-- of that, a spare healing potion. Richer on average than a single floor
-- drop (builder.lua's rollItem), since reaching it costs a key or a
-- lockpick gamble rather than a free step onto its tile.
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

-- A freshly rolled chest at (unassigned) x/y, exactly like Nodes.new -
-- builder.lua stamps x/y directly onto the returned table once it finds a
-- free cell for it. Trapped is only ever rolled for a locked chest (see
-- above), so the rng stream is never touched by the trap roll at all on an
-- unlocked one.
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

-- A chest still worth forcing: locked and not already emptied. An opened
-- chest reports unlocked regardless of its own `locked` flag, since nothing
-- is left inside to gate.
function Chests.isLocked(chest)
  return chest.locked and not chest.opened
end

-- Odds of a lockpick attempt succeeding: a flat coin flip that improves
-- slightly with player level, capped a point shy of the denominator so a
-- pick attempt is never a sure thing no matter how experienced the player
-- gets - mirrors disarm.lua's Disarm.oddsFor.
function Chests.oddsFor(player)
  local numerator = Chests.PICK_BASE_NUMERATOR + player.level // Chests.PICK_LEVEL_BONUS_DIVISOR
  if numerator > Chests.PICK_BASE_DENOMINATOR - 1 then
    numerator = Chests.PICK_BASE_DENOMINATOR - 1
  end
  return numerator, Chests.PICK_BASE_DENOMINATOR
end

-- Pours every item in `chest`'s hoard into `player`'s inventory and marks
-- the chest spent for good.
local function grant(player, chest)
  for _, item in ipairs(chest.loot) do
    player.inventory[#player.inventory + 1] = item
  end
  chest.opened = true
  chest.loot = {}
end

-- Opens an already-unlocked (or never-locked) chest outright. Refuses with
-- (false, line) and no state change against one still locked or already
-- emptied - the caller (Game:openChest) routes a locked chest through
-- Chests.unlockWithKey or Chests.pick instead.
function Chests.open(player, chest)
  if chest.opened then return false, "this chest is already empty" end
  if Chests.isLocked(chest) then return false, "the chest is locked" end
  grant(player, chest)
  return true, "you open the chest and take its hoard"
end

-- Spends a key from `player`'s inventory to force the lock outright, no
-- roll involved - the same certain trade a locked door already makes for
-- one of Items.KEY. Returns (false, line) with nothing spent if the player
-- is not carrying one, or against a chest that is not actually locked.
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

-- A trapped chest's punishment for a failed pick: a dart to the ribs or a
-- dose of poison, the same two effects a floor trap can spring (see
-- game.lua's Game:springTrap) but resolved locally since a chest is not a
-- level.traps entry. Spends the trap the instant it springs - a chest only
-- ever bites back once.
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

-- Gambles a lockpick against `chest`'s lock. Always spends the pick, win or
-- lose, once one is found. On success the chest opens exactly like
-- Chests.unlockWithKey; on failure a trapped chest springs on the player
-- (Chests.springTrap) while an untrapped one merely wastes the pick, the
-- lock still standing for a later key or another pick.
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
