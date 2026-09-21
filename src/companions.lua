local Entity = require("entity")
local Combat = require("combat")
local Los = require("los")
local Monsters = require("monsters")
local Status = require("status")
local Noise = require("noise")

local Companions = {}

Companions.species = {
  { key = "hound",  glyph = "d", name = "hunting hound", hp = 14, attack = 4, defense = 0, speed = 130, sight = 7,
    evolutions = {
      { level = 2, xp = 12, name = "warhound",   hp = 6,  attack = 2, defense = 1 },
      { level = 3, xp = 40, name = "dire hound", hp = 10, attack = 3, defense = 1 },
    } },
  { key = "golem",  glyph = "G", name = "clay golem",    hp = 26, attack = 5, defense = 3, speed = 70,  sight = 5,
    evolutions = {
      { level = 2, xp = 15, name = "stone golem", hp = 10, attack = 2, defense = 2 },
      { level = 3, xp = 45, name = "iron golem",  hp = 16, attack = 3, defense = 3 },
    } },
  { key = "sprite", glyph = "e", name = "hearth sprite", hp = 8,  attack = 1, defense = 0, speed = 110, sight = 8, heal = 2,
    evolutions = {
      { level = 2, xp = 10, name = "kindled sprite", hp = 4, attack = 1, defense = 0, heal = 1 },
      { level = 3, xp = 35, name = "radiant sprite", hp = 6, attack = 1, defense = 1, heal = 2 },
    } },
}

Companions.byKey = {}
Companions.order = {}
for _, spec in ipairs(Companions.species) do
  Companions.byKey[spec.key] = spec
  Companions.order[#Companions.order + 1] = spec.key
end

local ADJACENT = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

function Companions.summon(game, key)
  local spec = Companions.byKey[key]
  if not spec then return nil end
  for _, other in ipairs(game.level.entities) do
    if other.kind == "companion" and other:isAlive() then other.hp = 0 end
  end
  game:cleanupDead()
  local player = game.player
  for _, dir in ipairs(ADJACENT) do
    local x, y = player.x + dir[1], player.y + dir[2]
    if game.level.map:isWalkable(x, y) and not game.level:entityAt(x, y) then
      local companion = Entity.new({
        id = game:nextMonsterId(), x = x, y = y,
        glyph = spec.glyph, name = spec.name, kind = "companion",
        species = key, hp = spec.hp, attack = spec.attack, defense = spec.defense, speed = spec.speed,
      })
      companion.companionXp = 0
      companion.companionLevel = 1
      game.level.entities[#game.level.entities + 1] = companion
      return companion
    end
  end
  return nil
end

local function adjacent(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

local function nearestHostile(game, companion)
  local spec = Companions.byKey[companion.species]
  local sight = spec.sight
  if Status.has(companion, Status.BLIND) then sight = math.min(sight, 1) end
  local best, bestDist = nil, math.huge
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "monster" and entity:isAlive() then
      local dist = math.max(math.abs(entity.x - companion.x), math.abs(entity.y - companion.y))
      if dist <= sight and Los.clear(game.level.map, companion.x, companion.y, entity.x, entity.y) then
        if dist < bestDist or (dist == bestDist and entity.id < best.id) then
          best, bestDist = entity, dist
        end
      end
    end
  end
  return best
end

local function tendPlayer(game, companion)
  local spec = Companions.byKey[companion.species]
  if spec.heal and game.player.hp < game.player.maxHp then
    local amount = spec.heal + (companion.companionHealBonus or 0)
    game.player.hp = math.min(game.player.maxHp, game.player.hp + amount)
  end
end

function Companions.gainXp(game, companion, amount)
  if not amount or amount <= 0 then return end
  companion.companionXp = (companion.companionXp or 0) + amount
  companion.companionLevel = companion.companionLevel or 1
  local spec = Companions.byKey[companion.species]
  if not spec or not spec.evolutions then return end
  for _, stage in ipairs(spec.evolutions) do
    if companion.companionLevel < stage.level and companion.companionXp >= stage.xp then
      companion.companionLevel = stage.level
      companion.name = stage.name
      companion.maxHp = companion.maxHp + stage.hp
      companion.hp = companion.hp + stage.hp
      companion.attack = companion.attack + stage.attack
      companion.defense = companion.defense + stage.defense
      if stage.heal then
        companion.companionHealBonus = (companion.companionHealBonus or 0) + stage.heal
      end
      game.log:add("your " .. companion.name .. " evolves, growing stronger")
    end
  end
end

function Companions.act(game, companion)
  if game:allyActsConfused(companion) then return end
  local target = nearestHostile(game, companion)
  if target and adjacent(companion, target) then
    local outcome = Combat.attack(companion, target)
    game.log:add(string.format("your %s hits %s for %d", companion.name, target.name, outcome.damage))
    game:emitNoise(companion.x, companion.y, Noise.MELEE)
    if outcome.killed then
      game:awardKill(target)
      Companions.gainXp(game, companion, Monsters.xpFor(target))
    end
    return
  end
  if target then
    game:stepMonsterToward(companion, target.x, target.y)
    return
  end
  tendPlayer(game, companion)
  if not adjacent(companion, game.player) and not (companion.x == game.player.x and companion.y == game.player.y) then
    game:stepMonsterToward(companion, game.player.x, game.player.y)
  end
end

return Companions
