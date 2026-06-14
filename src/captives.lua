-- Net-and-ransom: throwing a spare net at a wild monster too battered to
-- keep fighting subdues it alive instead of finishing it off with a killing
-- blow. A captured monster never runs through Game:awardKill at all - no
-- xp, no essence, no quest or compendium credit, no faction kill penalty
-- (see factions.lua's registerKill) and no corpse (corpses.lua) - it is
-- simply dropped from level.entities the instant its hp hits zero here, and
-- reborn as a captive: plain data on level.captives, exactly like a chest
-- or a corpse, so it serializes with no special save-format handling.
--
-- A held captive can then be spent exactly one of three ways, each removing
-- it from level.captives for good: ransomed back to its own kind for
-- nothing but goodwill (Captives.ransom), sold off for gold at that same
-- goodwill's expense (Captives.sell), or interrogated for whatever it knows
-- instead of what it is worth (Captives.interrogate, which cashes in
-- secrets.lua's own passive search early). None of the three is strictly
-- better than the others - ransoming is the one move that can pull a
-- tribal faction back from the brink of open hostility (see factions.lua's
-- isWary), selling is the only one that pays gold, and interrogating is the
-- only one that answers to the floor's own layout rather than to gold or
-- reputation at all.
--
-- Capture is a gamble, not a guarantee: even a target already weak enough
-- to try for can still thrash free, and the net itself is spent from the
-- inventory either way, the same one-shot risk a lockpick's own gamble
-- takes against a locked chest. A net never works at all on anything
-- already spoken for by another escalation or special-case system - a
-- boss, a mimic, a grave shade, a nemesis, or the shopkeeper (ai "vend",
-- effectively unkillable loot rather than wild game to begin with).

local Los = require("los")
local Items = require("items")
local Monsters = require("monsters")
local Elites = require("elites")
local Factions = require("factions")
local Secrets = require("secrets")

local Captives = {}

Captives.RANGE = 4

-- A target must be battered down to this fraction of its own max hp or
-- lower before a net is even worth trying - full-health prey just shrugs a
-- net off before Captives.resolve ever rolls the catch itself.
Captives.HP_FRACTION_NUMERATOR = 3
Captives.HP_FRACTION_DENOMINATOR = 10

Captives.CATCH_NUMERATOR = 1
Captives.CATCH_DENOMINATOR = 2

Captives.RANSOM_REP_GAIN = 12
Captives.SELL_REP_LOSS = 8
Captives.INTERROGATE_ESSENCE_DIVISOR = 2

-- Whether `target` is even worth throwing a net at: alive, an ordinary wild
-- hostile (not a boss, mimic, grave shade or nemesis, and not the vending
-- shopkeeper), and hurt down to HP_FRACTION_NUMERATOR/DENOMINATOR of its own
-- max hp or less.
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

-- Same shape as throwing.lua's Throwing.canReach: a net flies no further
-- than RANGE and needs an unbroken line of sight, same as any thrown weapon.
function Captives.canReach(map, x1, y1, x2, y2)
  local dist = math.max(math.abs(x1 - x2), math.abs(y1 - y2))
  return dist <= Captives.RANGE and Los.clear(map, x1, y1, x2, y2)
end

-- Gold/essence baseline shared by every resolution below: the same xp a
-- kill would have paid, elite-boosted the same way Game:awardKill's own xp
-- is (see elites.lua), so a netted champion is worth visibly more than a
-- netted rank-and-file of the same species.
function Captives.valueOf(target)
  local xp = Monsters.xpFor(target)
  return xp + Elites.xpBonus(target, xp)
end

-- Resolves a net thrown from (thrower) at `target`. Returns (true, lines) if
-- the net left the thrower's hand - whether it actually held anything or
-- not - or (false, lines) if it never left the hand at all: the exact same
-- two-outcome shape Throwing.resolve takes for a thrown weapon or potion.
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

-- Drops `captive` off level.captives outright - shared by every way of
-- spending one below, so a captive can never be resolved twice over.
function Captives.remove(level, captive)
  for i, candidate in ipairs(level.captives) do
    if candidate == captive then
      table.remove(level.captives, i)
      return
    end
  end
end

-- Frees a held captive back to its own kind for nothing but goodwill: no
-- gold changes hands, but its faction's standing warms by RANSOM_REP_GAIN -
-- the mirror image of Factions.registerKill's penalty for finishing the
-- same creature off outright, and the one resolution that can actually pull
-- a tribal faction back out of Factions.isWary's hostile cutoff.
function Captives.ransom(level, player, captive)
  Captives.remove(level, captive)
  return Factions.adjust(player, captive.faction, Captives.RANSOM_REP_GAIN)
end

-- Sells a held captive off for its own value in gold: word gets back to its
-- kind either way, so standing sours by SELL_REP_LOSS even though - unlike
-- an outright kill - nothing actually died to earn it.
function Captives.sell(level, player, captive)
  Captives.remove(level, captive)
  player.gold = player.gold + captive.value
  Factions.adjust(player, captive.faction, -Captives.SELL_REP_LOSS)
  return captive.value
end

-- Interrogates a held captive instead of ransoming or selling it: no gold,
-- no reputation swing either way, just whatever it gives up before its
-- usefulness runs out - every currently-hidden secret door on this floor,
-- found outright (see Secrets.revealAll), plus a trickle of essence for the
-- trouble. Returns the doors this actually revealed, same as
-- Secrets.revealAll itself.
function Captives.interrogate(level, player, captive)
  local revealed = Secrets.revealAll(level)
  Captives.remove(level, captive)
  player.essence = player.essence + math.max(1, captive.value // Captives.INTERROGATE_ESSENCE_DIVISOR)
  return revealed
end

return Captives
