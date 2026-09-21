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
