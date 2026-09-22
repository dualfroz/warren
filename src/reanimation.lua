local Entity = require("entity")
local Combat = require("combat")
local Los = require("los")
local Monsters = require("monsters")
local Corpses = require("corpses")
local Status = require("status")
local Noise = require("noise")

local Reanimation = {}

Reanimation.LIFESPAN = 40
Reanimation.SANITY_COST = 15
Reanimation.HP_FRACTION = 0.6
Reanimation.ATTACK_PENALTY = 1
Reanimation.SIGHT = 6
Reanimation.thrallGlyph = "Z"

local ADJACENT = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function statsFor(speciesKey)
  local spec = Monsters.byKey[speciesKey]
  if not spec then return { hp = 8, attack = 2, defense = 0, speed = 100 } end
  return {
    hp = math.max(4, math.floor(spec.hp * Reanimation.HP_FRACTION)),
    attack = math.max(1, spec.attack - Reanimation.ATTACK_PENALTY),
    defense = spec.defense,
    speed = spec.speed,
  }
end

function Reanimation.raise(game, corpse)
  if Corpses.isRotten(corpse) then
    return nil, "this corpse has rotted too far to answer the call"
  end
  if game.player.sanity < Reanimation.SANITY_COST then
    return nil, "your grip on your own mind is too frail for this"
  end
  local player = game.player
  local x, y
  for _, dir in ipairs(ADJACENT) do
    local cx, cy = player.x + dir[1], player.y + dir[2]
    if game.level.map:isWalkable(cx, cy) and not game.level:entityAt(cx, cy) then
      x, y = cx, cy
      break
    end
  end
  if not x then
    return nil, "there is nowhere for a thrall to rise"
  end
  for _, other in ipairs(game.level.entities) do
    if other.kind == "thrall" and other:isAlive() then other.hp = 0 end
  end
  game:cleanupDead()
  for i, candidate in ipairs(game.level.corpses) do
    if candidate == corpse then
      table.remove(game.level.corpses, i)
      break
    end
  end
  player.sanity = math.max(0, player.sanity - Reanimation.SANITY_COST)
  local stats = statsFor(corpse.species)
  local thrall = Entity.new({
    id = game:nextMonsterId(), x = x, y = y,
    glyph = Reanimation.thrallGlyph, name = corpse.name .. " thrall", kind = "thrall",
    species = corpse.species, hp = stats.hp, attack = stats.attack, defense = stats.defense, speed = stats.speed,
  })
  thrall.decay = Reanimation.LIFESPAN
  game.level.entities[#game.level.entities + 1] = thrall
  return thrall
end

local function adjacent(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

local function nearestHostile(game, thrall)
  local sight = Reanimation.SIGHT
  if Status.has(thrall, Status.BLIND) then sight = math.min(sight, 1) end
  local best, bestDist = nil, math.huge
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "monster" and entity:isAlive() then
      local dist = math.max(math.abs(entity.x - thrall.x), math.abs(entity.y - thrall.y))
      if dist <= sight and Los.clear(game.level.map, thrall.x, thrall.y, entity.x, entity.y) then
        if dist < bestDist or (dist == bestDist and entity.id < best.id) then
          best, bestDist = entity, dist
        end
      end
    end
  end
  return best
end

function Reanimation.act(game, thrall)
  thrall.decay = thrall.decay - 1
  if thrall.decay <= 0 then
    thrall.hp = 0
    game:onActorDeath(thrall)
    return
  end
  if game:allyActsConfused(thrall) then return end
  local target = nearestHostile(game, thrall)
  if target and adjacent(thrall, target) then
    local outcome = Combat.attack(thrall, target)
    game.log:add(string.format("your %s claws %s for %d", thrall.name, target.name, outcome.damage))
    game:emitNoise(thrall.x, thrall.y, Noise.MELEE)
    if outcome.killed then game:awardKill(target) end
    return
  end
  if target then
    game:stepMonsterToward(thrall, target.x, target.y)
    return
  end
  if not adjacent(thrall, game.player) and not (thrall.x == game.player.x and thrall.y == game.player.y) then
    game:stepMonsterToward(thrall, game.player.x, game.player.y)
  end
end

return Reanimation
