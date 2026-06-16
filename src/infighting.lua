-- Monsters that share no faction bond will occasionally fight each other
-- outright instead of always beelining for the player. Two rival factions
-- (see Factions.RIVALRIES) throw down on sight, and any monster carrying
-- Status.DISCORD - landed by the discord spell, see spells.lua - is
-- compelled to strike whatever creature stands nearest it, friend or foe,
-- for the effect's duration. Either way the fight runs through combat.lua
-- exactly like a player's own attack - same damage formula, same
-- resistances, same Game:applyEliteOnHit hooks (an elite attacker's
-- lifesteal or on-hit status rider fires here too, not just against the
-- player) and the same disease.lua bite chance (a plague-carrier's bite can
-- infect a rival monster or the player's own companion/hireling/thrall,
-- not just the player Game:monsterMelee already covers) - so a discorded
-- troll among goblins is a real threat to both sides, not a scripted
-- distraction. A plain monster felled this way
-- still leaves a corpse (scavenging/reanimation can use it) but pays out no
-- xp, essence, faction standing, or compendium credit - the player didn't
-- land the blow. A companion, hireling, or thrall killed this way (only
-- reachable through discord, since none of them carry a faction) dies
-- exactly as it would to any other monster.

local Combat = require("combat")
local Status = require("status")
local Factions = require("factions")
local Los = require("los")
local Corpses = require("corpses")
local Noise = require("noise")
local Disease = require("disease")

local Infighting = {}

Infighting.SIGHT_RANGE = 8

local function canSee(game, a, b)
  local cheb = math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
  if cheb > Infighting.SIGHT_RANGE then return false end
  return Los.clear(game.level.map, a.x, a.y, b.x, b.y)
end

local function isAlly(actor)
  return actor.kind == "companion" or actor.kind == "hireling" or actor.kind == "thrall"
end

-- The other living, non-player creature `monster` should be fighting this
-- turn instead of following its usual Ai.act behaviour, or nil if none
-- qualifies. A rival-faction monster always qualifies once seen; under
-- Status.DISCORD, the nearest visible creature of any kind - including the
-- player's own companion, hireling, or thrall - qualifies too, since
-- discord scrambles a mind's sense of friend and foe entirely. Ties break
-- toward the lower entity id, matching Game:nearestAlly's own tie rule.
function Infighting.target(game, monster)
  local discorded = Status.has(monster, Status.DISCORD)
  local best, bestDist = nil, math.huge
  for _, other in ipairs(game.level.entities) do
    if other ~= monster and other:isAlive() then
      local qualifies = discorded or Factions.areRivals(monster.faction, other.faction)
      if qualifies and canSee(game, monster, other) then
        local dist = math.max(math.abs(other.x - monster.x), math.abs(other.y - monster.y))
        if dist < bestDist or (dist == bestDist and other.id < best.id) then
          best, bestDist = other, dist
        end
      end
    end
  end
  return best
end

-- Resolves one monster-vs-monster hit through the same damage formula any
-- other attack uses. A defender that falls is swept immediately: a
-- companion/hireling/thrall dies exactly as game.lua already reports that,
-- while a plain hostile monster just drops - Corpses.spawn still leaves
-- remains behind, but no awardKill means no xp/essence/faction/compendium
-- credit for a kill the player never made.
function Infighting.strike(game, attacker, defender)
  local outcome = Combat.attack(attacker, defender)
  game.log:add(string.format("%s hits %s for %d", attacker.name, defender.name, outcome.damage))
  game:applyEliteOnHit(attacker, outcome.damage, defender)
  if attacker.biteDisease and defender:isAlive() and game.rng:chance(1, 4) then
    if Disease.infect(defender, attacker.biteDisease) then
      game.log:add(string.format("%s's bite leaves %s feeling ill", attacker.name, defender.name))
    end
  end
  game:emitNoise(attacker.x, attacker.y, Noise.MELEE)
  if not defender:isAlive() then
    if isAlly(defender) then
      game:onActorDeath(defender)
    else
      game.log:add(defender.name .. " dies")
      Corpses.spawn(game.level, defender)
    end
  end
  return outcome
end

-- Entry point mirroring Abilities.tryAct's contract: returns true when
-- infighting consumed the monster's turn (attacked an adjacent target or
-- stepped toward a farther one), false to let the caller fall through to
-- Ai.act.
function Infighting.tryAct(game, monster)
  local target = Infighting.target(game, monster)
  if not target then return false end
  local dist = math.max(math.abs(target.x - monster.x), math.abs(target.y - monster.y))
  if dist <= 1 then
    Infighting.strike(game, monster, target)
  else
    game:stepMonsterToward(monster, target.x, target.y)
  end
  return true
end

return Infighting
