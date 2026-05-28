-- Resolves potion and scroll effect keys against the world. Self-contained buffs
-- act on the drinker; teleport, mapping, identify and fireball reach into the
-- game and its current level. Every effect returns log lines in emission order.

local Status = require("status")
local Identify = require("identify")

local Effects = {}

local handlers = {}

handlers.heal = function(game, target, item)
  local before = target.hp
  target.hp = math.min(target.maxHp, target.hp + item.power)
  return { string.format("%s heals %d", target.name, target.hp - before) }
end

handlers.poison = function(game, target, item)
  Status.apply(target, Status.POISON, 6, item.power)
  return { string.format("%s is poisoned", target.name) }
end

handlers.strength = function(game, target, _)
  Status.apply(target, Status.STRENGTH, 30, 3)
  return { string.format("%s feels mightier", target.name) }
end

handlers.haste = function(game, target, _)
  Status.apply(target, Status.HASTE, 20, 1)
  return { string.format("%s speeds up", target.name) }
end

handlers.teleport = function(game, target, _)
  local x, y = game:randomFloorCell()
  if x then
    target.x, target.y = x, y
    return { target.name .. " blinks away" }
  end
  return { "the teleport fizzles" }
end

handlers.mapping = function(game, _, _)
  game:revealWholeLevel()
  return { "the level is revealed" }
end

handlers.identify = function(game, target, _)
  local revealed = Identify.revealFirstUnknown(game.identify, target.inventory)
  if revealed then
    return { "it is " .. revealed.name }
  end
  return { "nothing left to identify" }
end

handlers.fireball = function(game, target, _)
  local radius = 3
  local burned = 0
  for _, monster in ipairs(game:currentEntities()) do
    if monster:isAlive() then
      local dist = math.max(math.abs(monster.x - target.x), math.abs(monster.y - target.y))
      if dist <= radius then
        monster.hp = monster.hp - 8
        Status.apply(monster, Status.BURNING, 3, 2)
        burned = burned + 1
      end
    end
  end
  game:cleanupDead()
  return { string.format("fire engulfs %d foes", burned) }
end

function Effects.apply(effectKey, game, target, item)
  local handler = handlers[effectKey]
  if not handler then return {} end
  return handler(game, target, item)
end

function Effects.has(effectKey)
  return handlers[effectKey] ~= nil
end

return Effects
