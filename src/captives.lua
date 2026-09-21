local Los = require("los")
local Items = require("items")
local Monsters = require("monsters")
local Elites = require("elites")
local Factions = require("factions")
local Secrets = require("secrets")

local Captives = {}

Captives.RANGE = 4

Captives.HP_FRACTION_NUMERATOR = 3
Captives.HP_FRACTION_DENOMINATOR = 10

Captives.CATCH_NUMERATOR = 1
Captives.CATCH_DENOMINATOR = 2

Captives.RANSOM_REP_GAIN = 12
Captives.SELL_REP_LOSS = 8
Captives.INTERROGATE_ESSENCE_DIVISOR = 2

function Captives.eligible(target)
  return target ~= nil
    and target:isAlive()
    and target.kind == "monster"
    and target.ai ~= "vend"
    and not target.isBoss
    and not target.mimic
    and not target.grave
    and not target.nemesis
    and target.hp * Captives.HP_FRACTION_DENOMINATOR <= target.maxHp * Captives.HP_FRACTION_NUMERATOR
end

function Captives.canReach(map, x1, y1, x2, y2)
  local dist = math.max(math.abs(x1 - x2), math.abs(y1 - y2))
  return dist <= Captives.RANGE and Los.clear(map, x1, y1, x2, y2)
end

function Captives.valueOf(target)
  local xp = Monsters.xpFor(target)
  return xp + Elites.xpBonus(target, xp)
end

function Captives.resolve(game, thrower, item, target)
  if not item or item.kind ~= Items.NET then
    return false, { "that can't be thrown as a net" }
  end
  if not target or not target:isAlive() then
    return false, { "no target" }
  end
  if not Captives.canReach(game.level.map, thrower.x, thrower.y, target.x, target.y) then
    return false, { "you have no clear throw" }
  end
  if not Captives.eligible(target) then
    return true, { target.name .. " is far too fierce to net while it can still fight like that" }
  end
  if not game.rng:chance(Captives.CATCH_NUMERATOR, Captives.CATCH_DENOMINATOR) then
    return true, { target.name .. " thrashes free of the net" }
  end
  local captive = {
    x = target.x, y = target.y,
    species = target.species, faction = target.faction, name = target.name,
    value = Captives.valueOf(target),
  }
  game.level.captives[#game.level.captives + 1] = captive
  target.hp = 0
  return true, { string.format("the net drops true - %s is bound and struggling", target.name) }
end

function Captives.remove(level, captive)
  for i, candidate in ipairs(level.captives) do
    if candidate == captive then
      table.remove(level.captives, i)
      return
    end
  end
end

function Captives.ransom(level, player, captive)
  Captives.remove(level, captive)
  return Factions.adjust(player, captive.faction, Captives.RANSOM_REP_GAIN)
end

function Captives.sell(level, player, captive)
  Captives.remove(level, captive)
  player.gold = player.gold + captive.value
  Factions.adjust(player, captive.faction, -Captives.SELL_REP_LOSS)
  return captive.value
end

function Captives.interrogate(level, player, captive)
  local revealed = Secrets.revealAll(level)
  Captives.remove(level, captive)
  player.essence = player.essence + math.max(1, captive.value // Captives.INTERROGATE_ESSENCE_DIVISOR)
  return revealed
end

return Captives
