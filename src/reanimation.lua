-- Necromancy: consumes a still-fresh corpse underfoot to raise it as a
-- temporary skeletal thrall that fights beside the player until its
-- borrowed animation runs out. Unlike companions.lua's charm-bonded ally,
-- which persists across the whole run once bonded, a thrall is spent the
-- instant it collapses - reduced to inert bones, nothing left to butcher a
-- second time - and raising one costs the player a bite of sanity.lua's own
-- meter, the same currency dread already drains, since bending a corpse
-- back into motion is exactly the kind of wrongness that meter tracks.
-- Only one thrall may walk at a time; raising a second dismisses the first
-- outright, the same one-bond-at-a-time rule companions.lua keeps for its
-- own charm. Thralls are plain entities on level.entities, exactly like
-- companions, so they serialize with no special save-format handling
-- beyond the one extra field (decay) entity.lua's toData whitelist adds.

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

local ADJACENT = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- Combat numbers for the thrall raised from a corpse of `speciesKey`: a
-- fraction of the living species' own hp, attack blunted by one point for
-- fighting with brittle bone instead of flesh, and defense and speed left
-- exactly as they were - an animated skeleton is exactly as easy or hard to
-- land a blow on, and exactly as quick underfoot, as the creature it once
-- was. Falls back to a flat, unremarkable skeleton for any corpse whose
-- species the bestiary no longer recognises (none today, but a save could
-- in principle outlive a species removed from a later build).
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

-- Raises `corpse` beside the player, retiring any earlier thrall first and
-- spending the corpse and a bite of sanity outright. Returns the new
-- thrall, or (nil, line) with nothing changed when the corpse has already
-- rotted past use, the player's own mind cannot bear the cost, or every
-- cell around the player is blocked.
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
    glyph = "Z", name = corpse.name .. " thrall", kind = "thrall",
    species = corpse.species, hp = stats.hp, attack = stats.attack, defense = stats.defense, speed = stats.speed,
  })
  thrall.decay = Reanimation.LIFESPAN
  game.level.entities[#game.level.entities + 1] = thrall
  return thrall
end

local function adjacent(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

-- Nearest living monster the thrall can see within Reanimation.SIGHT, ties
-- broken by ascending id for determinism - the same shape companions.lua's
-- own nearestHostile follows, including its blind clamp (Game:canSeePlayer's
-- own melee-range fallback for a blinded monster).
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

-- The thrall's full turn: its borrowed animation runs out by one turn
-- first, and once it hits zero the thrall collapses back into inert bones
-- through the very same Game:onActorDeath path a slain one already falls
-- through - called directly here, exactly like Game:checkTrapFor calls it
-- directly for a trap kill mid-move, since nothing later in the caller's
-- own takeMonsterTurn pipeline re-checks aliveness once dispatch returns.
-- Otherwise it fights whatever hostile it can already reach, closes on one
-- it can see but not yet reach, or shadows the player - the same
-- three-branch shape as Companions.act, minus any tending since a thrall
-- has nothing of its own to spare.
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
