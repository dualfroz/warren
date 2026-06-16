-- Resolves potion and scroll effect keys against the world. Self-contained buffs
-- act on the drinker; teleport, mapping, identify and fireball reach into the
-- game and its current level. Every effect returns log lines in emission order.

local Status = require("status")
local Identify = require("identify")
local Hazards = require("hazards")
local Resistances = require("resistances")
local Curses = require("curses")
local Sanity = require("sanity")
local Disease = require("disease")

local Effects = {}

local handlers = {}

-- Every handler below phrases its own log line by hand rather than always
-- templating a bare "%s <third-person-singular-verb>" onto target.name,
-- because Effects.apply's only call site (Game:useItem) always hands it the
-- player, whose name is the pronoun "you" - a subject that takes the plain
-- ("you heal", "you are poisoned") verb form English gives second person,
-- not the third-person-singular form ("heals", "is") a named monster like
-- "orc" would take. Kept branching on target.kind rather than hardcoding
-- "you" outright so a future non-player caller (a companion drinking its
-- own potion, say) still reads correctly without touching this file - the
-- same isPlayer-branch convention Game:springTrap and Game:checkTerrainFor
-- already use for the identical pronoun problem.
local function isPlayer(target)
  return target.kind == "player"
end

handlers.heal = function(game, target, item)
  local before = target.hp
  target.hp = math.min(target.maxHp, target.hp + item.power)
  local healed = target.hp - before
  return { isPlayer(target) and string.format("you heal %d", healed)
    or string.format("%s heals %d", target.name, healed) }
end

handlers.poison = function(game, target, item)
  Status.apply(target, Status.POISON, 6, item.power)
  return { isPlayer(target) and "you are poisoned" or string.format("%s is poisoned", target.name) }
end

handlers.strength = function(game, target, _)
  Status.apply(target, Status.STRENGTH, 30, 3)
  return { isPlayer(target) and "you feel mightier" or string.format("%s feels mightier", target.name) }
end

handlers.haste = function(game, target, _)
  Status.apply(target, Status.HASTE, 20, 1)
  return { isPlayer(target) and "you speed up" or string.format("%s speeds up", target.name) }
end

handlers.fortify = function(game, target, _)
  Status.apply(target, Status.SHIELD, 15, 1)
  return { isPlayer(target) and "you feel fortified" or string.format("%s feels fortified", target.name) }
end

-- Same shape as haste/fortify - a timed self-buff, not a hostile effect -
-- but see status.lua's Status.LEVITATE for what it actually unlocks: a
-- levitating target ignores lava, chasms, ice, and ground-pressure traps
-- entirely until it wears off (Game:checkTerrainFor/checkTrapFor).
handlers.levitate = function(game, target, _)
  Status.apply(target, Status.LEVITATE, 20, 1)
  return { isPlayer(target) and "you rise off the ground" or string.format("%s rises off the ground", target.name) }
end

handlers.clarity = function(game, target, item)
  Sanity.adjust(target, item.power)
  return { isPlayer(target) and string.format("your mind steadies (sanity %d/%d)", Sanity.current(target), Sanity.MAX)
    or string.format("%s's mind steadies (sanity %d/%d)", target.name, Sanity.current(target), Sanity.MAX) }
end

-- "Cleansing" always meant purging disease; it never touched the status
-- effects (poison, burning, stun, slow, weaken, discord, confuse, blind)
-- that every other cure-shaped word in the game implies, leaving those
-- curable only by waiting out their duration. Now strips both.
handlers.cure = function(game, target, _)
  local diseaseCured = Disease.cure(target)
  local liftedStatuses = Status.cureHostile(target)
  local statusList = table.concat(liftedStatuses, ", ")
  if diseaseCured and #liftedStatuses > 0 then
    return { isPlayer(target)
      and string.format("your affliction is cleansed away, and the %s fades", statusList)
      or string.format("%s's affliction is cleansed away, and the %s fades", target.name, statusList) }
  elseif diseaseCured then
    return { isPlayer(target) and "your affliction is cleansed away"
      or string.format("%s's affliction is cleansed away", target.name) }
  elseif #liftedStatuses > 0 then
    return { isPlayer(target) and string.format("your %s fades", statusList)
      or string.format("%s's %s fades", target.name, statusList) }
  end
  return { isPlayer(target) and "you feel a faint tingle, but had nothing to cleanse"
    or string.format("%s feels a faint tingle, but had nothing to cleanse", target.name) }
end

-- Same duration/potency as the confuse spell and trap (see status.lua's
-- Status.CONFUSE and its mirrors in Game:movePlayer/Ai.act) so drinking an
-- unidentified potion of confusion is exactly as bad as walking into a
-- confuse trap, not a weaker or stronger flavor of the same status.
handlers.confuse = function(game, target, _)
  Status.apply(target, Status.CONFUSE, 6, 1)
  return { isPlayer(target) and "your mind reels with confusion"
    or string.format("%s's mind reels with confusion", target.name) }
end

-- Same duration/potency as the blind trap (see Game:springTrap) so drinking
-- an unidentified potion of blindness is exactly as bad as walking into a
-- flash trap, not a weaker or stronger flavor of the same status.
handlers.blind = function(game, target, _)
  Status.apply(target, Status.BLIND, 6, 1)
  return { isPlayer(target) and "you are struck blind" or string.format("%s is struck blind", target.name) }
end

handlers.teleport = function(game, target, _)
  local x, y = game:randomFloorCell()
  if x then
    target.x, target.y = x, y
    return { isPlayer(target) and "you blink away" or (target.name .. " blinks away") }
  end
  return { "the teleport fizzles" }
end

handlers.mapping = function(game, _, _)
  game:revealWholeLevel()
  return { "the level is revealed" }
end

handlers.identify = function(game, target, _)
  local lines = {}
  local revealed = Identify.revealFirstUnknown(game.identify, target.inventory)
  if revealed then
    lines[#lines + 1] = "it is " .. revealed.name
  end
  local cursedFind = Curses.revealFirstUnknown(target)
  if cursedFind then
    lines[#lines + 1] = "you sense a curse upon your " .. cursedFind.name
  end
  if #lines == 0 then
    lines[#lines + 1] = "nothing left to identify"
  end
  return lines
end

handlers.removecurse = function(game, target, _)
  local count = Curses.cleanseWorn(target)
  if count == 0 then
    return { "you feel a faint tingle, but nothing you wear is cursed" }
  end
  return { string.format("a wave of purifying light lifts %d curse%s from your gear",
    count, count == 1 and "" or "s") }
end

handlers.fireball = function(game, target, _)
  local radius = 3
  local burned = 0
  for _, monster in ipairs(game:currentEntities()) do
    if monster:isAlive() then
      local dist = math.max(math.abs(monster.x - target.x), math.abs(monster.y - target.y))
      if dist <= radius then
        monster.hp = monster.hp - Resistances.apply(monster, 8, Resistances.FIRE)
        Status.apply(monster, Status.BURNING, 3, 2)
        Hazards.ignite(game.level, monster.x, monster.y, 3, 2)
        burned = burned + 1
      end
    end
  end
  Hazards.ignite(game.level, target.x, target.y, 3, 2)
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
