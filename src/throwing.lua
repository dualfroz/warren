-- Player ranged option that costs no mana: any spare weapon or potion sitting
-- in the inventory (not the one currently wielded) can be hurled at a monster
-- in range and line of sight. A thrown weapon hits harder than a melee swing
-- and lands where it struck, ready to be picked back up; a thrown potion
-- shatters and visits its effect on the target instead of the thrower, which
-- only makes sense for potions with a hostile reading.

local Los = require("los")
local Status = require("status")
local Items = require("items")
local Hazards = require("hazards")
local Resistances = require("resistances")

local Throwing = {}

Throwing.RANGE = 6
local POWER_MULT = 2

-- Hostile reading of each potion effect. Potions with no meaningful effect on
-- an enemy (healing, strength) just shatter harmlessly rather than helping
-- whoever they were thrown at.
local hostileEffects = {
  poison = function(game, target)
    Status.apply(target, Status.POISON, 6, 3)
    Hazards.spawnGas(game.level, target.x, target.y, 4, 2)
    return string.format("the potion shatters, poisoning %s in a cloud of fumes", target.name)
  end,
  haste = function(_, target)
    Status.apply(target, Status.HASTE, 10, 1)
    return string.format("the potion shatters, and %s bolts away", target.name)
  end,
  confuse = function(_, target)
    Status.apply(target, Status.CONFUSE, 6, 1)
    return string.format("the potion shatters, and %s reels in confusion", target.name)
  end,
  blind = function(_, target)
    Status.apply(target, Status.BLIND, 6, 1)
    return string.format("the potion shatters in a blinding flash, and %s is struck blind", target.name)
  end,
  -- Same hostile reading as haste above: lifting a dangerous target off the
  -- ground lets it drift clear of whatever lava, chasm, or trap the thrower
  -- was counting on to block or punish it (see status.lua's Status.LEVITATE),
  -- so handing it to an enemy is a liability, not a gift.
  levitate = function(_, target)
    Status.apply(target, Status.LEVITATE, 10, 1)
    return string.format("the potion shatters, and %s rises off the ground", target.name)
  end,
}

function Throwing.canThrow(item)
  return item.kind == Items.WEAPON or item.kind == Items.POTION
end

function Throwing.canReach(game, x1, y1, x2, y2)
  local dist = math.max(math.abs(x1 - x2), math.abs(y1 - y2))
  return dist <= Throwing.RANGE and Los.clear(game.level.map, x1, y1, x2, y2)
end

-- Resolves a thrown item against a target. Returns (true, lines) if the item
-- left the thrower's hand - whether or not it did anything useful on arrival
-- - or (false, lines) if the throw never happened at all.
function Throwing.resolve(game, thrower, item, target)
  if not Throwing.canThrow(item) then
    return false, { "that can't be thrown" }
  end
  if not target or not target:isAlive() then
    return false, { "no target" }
  end
  if not Throwing.canReach(game, thrower.x, thrower.y, target.x, target.y) then
    return false, { "you have no clear throw" }
  end
  if item.kind == Items.WEAPON then
    local dmg = Resistances.apply(target, item.power * POWER_MULT, item.damageType or Resistances.PHYSICAL)
    target.hp = target.hp - dmg
    local lines = { string.format("your thrown %s hits %s for %d", item.name, target.name, dmg) }
    game.level.floorItems[#game.level.floorItems + 1] = { x = target.x, y = target.y, item = item }
    if not target:isAlive() then game:awardKill(target) end
    return true, lines
  end
  local handler = hostileEffects[item.effect]
  local line = handler and handler(game, target) or "the potion shatters harmlessly"
  return true, { line }
end

return Throwing
