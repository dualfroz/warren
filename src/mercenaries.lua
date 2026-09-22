local Entity = require("entity")
local Combat = require("combat")
local Los = require("los")
local Status = require("status")
local Noise = require("noise")

local Mercenaries = {}

Mercenaries.roster = {
  { key = "sellsword",  glyph = "l", name = "sellsword",    hp = 24, attack = 6, defense = 2, speed = 100,
    sight = 6, hireCost = 60, wage = 14 },
  { key = "skirmisher", glyph = "y", name = "skirmisher",   hp = 15, attack = 5, defense = 1, speed = 115,
    sight = 8, hireCost = 50, wage = 11 },
  { key = "medic",      glyph = "p", name = "field medic",  hp = 13, attack = 2, defense = 1, speed = 100,
    sight = 6, hireCost = 70, wage = 16, heal = 3 },
}

Mercenaries.byKey = {}
Mercenaries.order = {}
for _, spec in ipairs(Mercenaries.roster) do
  Mercenaries.byKey[spec.key] = spec
  Mercenaries.order[#Mercenaries.order + 1] = spec.key
end

Mercenaries.WAGE_INTERVAL = 25
Mercenaries.START_LOYALTY = 100
Mercenaries.MAX_LOYALTY = 100
Mercenaries.LOYALTY_LOSS_UNPAID = 40
Mercenaries.LOYALTY_GAIN_PAID = 15
Mercenaries.SULKING_THRESHOLD = 30

local ADJACENT = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

function Mercenaries.hire(game, key)
  local spec = Mercenaries.byKey[key]
  if not spec then return nil end
  for _, other in ipairs(game.level.entities) do
    if other.kind == "hireling" and other:isAlive() then other.hp = 0 end
  end
  game:cleanupDead()
  local player = game.player
  for _, dir in ipairs(ADJACENT) do
    local x, y = player.x + dir[1], player.y + dir[2]
    if game.level.map:isWalkable(x, y) and not game.level:entityAt(x, y) then
      local hireling = Entity.new({
        id = game:nextMonsterId(), x = x, y = y,
        glyph = spec.glyph, name = spec.name, kind = "hireling",
        species = key, hp = spec.hp, attack = spec.attack, defense = spec.defense, speed = spec.speed,
      })
      hireling.wage = spec.wage
      hireling.loyalty = Mercenaries.START_LOYALTY
      game.level.entities[#game.level.entities + 1] = hireling
      return hireling
    end
  end
  return nil
end

function Mercenaries.dismiss(game)
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "hireling" and entity:isAlive() then
      local name = entity.name
      entity.hp = 0
      game:cleanupDead()
      return name
    end
  end
  return nil
end

function Mercenaries.payWage(game)
  local hireling
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "hireling" and entity:isAlive() then hireling = entity end
  end
  if not hireling then return nil end
  if game.player.gold >= hireling.wage then
    game.player.gold = game.player.gold - hireling.wage
    hireling.loyalty = math.min(Mercenaries.MAX_LOYALTY, hireling.loyalty + Mercenaries.LOYALTY_GAIN_PAID)
    return "you pay your " .. hireling.name .. " " .. hireling.wage .. " gold"
  end
  hireling.loyalty = hireling.loyalty - Mercenaries.LOYALTY_LOSS_UNPAID
  if hireling.loyalty <= 0 then
    hireling.hp = 0
    game:cleanupDead()
    return "your " .. hireling.name .. " deserts, unpaid and unwilling to go on"
  end
  return "your " .. hireling.name .. " grumbles, unpaid this floor"
end

local function adjacent(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

local function nearestHostile(game, hireling)
  local spec = Mercenaries.byKey[hireling.species]
  local sight = spec.sight
  if Status.has(hireling, Status.BLIND) then sight = math.min(sight, 1) end
  local best, bestDist = nil, math.huge
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "monster" and entity:isAlive() then
      local dist = math.max(math.abs(entity.x - hireling.x), math.abs(entity.y - hireling.y))
      if dist <= sight and Los.clear(game.level.map, hireling.x, hireling.y, entity.x, entity.y) then
        if dist < bestDist or (dist == bestDist and entity.id < best.id) then
          best, bestDist = entity, dist
        end
      end
    end
  end
  return best
end

local function tendPlayer(game, hireling)
  local spec = Mercenaries.byKey[hireling.species]
  if spec.heal and game.player.hp < game.player.maxHp then
    game.player.hp = math.min(game.player.maxHp, game.player.hp + spec.heal)
  end
end

function Mercenaries.act(game, hireling)
  if game:allyActsConfused(hireling) then return end
  local target = nearestHostile(game, hireling)
  if target and adjacent(hireling, target) then
    local outcome = Combat.attack(hireling, target)
    game.log:add(string.format("your %s hits %s for %d", hireling.name, target.name, outcome.damage))
    game:emitNoise(hireling.x, hireling.y, Noise.MELEE)
    if outcome.killed then game:awardKill(target) end
    return
  end
  if hireling.loyalty <= Mercenaries.SULKING_THRESHOLD then
    return
  end
  if target then
    game:stepMonsterToward(hireling, target.x, target.y)
    return
  end
  tendPlayer(game, hireling)
  if not adjacent(hireling, game.player) and not (hireling.x == game.player.x and hireling.y == game.player.y) then
    game:stepMonsterToward(hireling, game.player.x, game.player.y)
  end
end

return Mercenaries
