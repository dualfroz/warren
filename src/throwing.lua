local Los = require("los")
local Status = require("status")
local Items = require("items")
local Hazards = require("hazards")
local Resistances = require("resistances")

local Throwing = {}

Throwing.RANGE = 6
local POWER_MULT = 2

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
