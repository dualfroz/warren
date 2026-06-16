-- Player-aligned allies bonded from a charm found on the floor. Once summoned
-- a companion joins the turn scheduler exactly like a monster (see game.lua's
-- takeMonsterTurn), but its own turn logic below hunts nearby hostile
-- monsters instead of the player and never turns hostile itself. Only one
-- companion may be bonded at a time - summoning a second retires the first.
--
-- Static per-species numbers (sight radius, heal rate) are looked up from
-- Companions.byKey by species key rather than copied onto the entity, the
-- same convention monsters.lua uses for xp: one source of truth, and nothing
-- extra to add to entity.lua's serialization whitelist. A companion's own
-- battle-earned progress (companionXp/companionLevel/companionHealBonus
-- below) is the opposite: per-instance and mutable, so unlike the static
-- table above it does need its own prefixed trio in that whitelist, the same
-- way mercenaries.lua's wage/loyalty or reanimation.lua's decay already do.

local Entity = require("entity")
local Combat = require("combat")
local Los = require("los")
local Monsters = require("monsters")
local Status = require("status")
local Noise = require("noise")

local Companions = {}

-- `evolutions` entries are climbed in order, each permanently once
-- companionXp first reaches its `xp` (a running total, not a delta - the
-- same shape titles.lua's own ladder uses): the companion is renamed and its
-- hp/attack/defense grow by that entry's own flat amount, on top of
-- whatever an earlier stage already added rather than replacing it. A
-- hearth sprite's `heal` entries stack the same way into companionHealBonus,
-- read by tendPlayer below alongside the species' own static heal rate.
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

-- Bonds a fresh companion of `key` onto a free cell next to the player,
-- retiring any earlier bond first. Returns the new companion, or nil if
-- every cell around the player is blocked.
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

-- Chebyshev-1 (8-directional), matching mercenaries.lua's and reanimation.lua's
-- own "adjacent" helpers exactly - both of those modules explicitly describe
-- their combat branch as "the same three-branch shape as Companions.act", so
-- this was meant to be one shared rule, not three independently-typed copies.
-- This one alone used Manhattan-1 (4-directional) until now, so a companion
-- caught diagonally next to a hostile monster fell through to
-- stepMonsterToward instead of attacking - the exact same geometry a hireling
-- or thrall standing in already engages without moving.
local function adjacent(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) == 1
end

-- Nearest living monster the companion can see within its species' sight
-- radius, ties broken by ascending id for determinism. A blinded companion
-- loses every longer-ranged sighting and falls back to melee range only,
-- the same clamp Game:canSeePlayer applies to a blinded hostile monster.
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

-- A hearth sprite mends its bonded player a little on any turn it does not
-- spend fighting - the only companion with a passive off-turn effect. An
-- evolved sprite's companionHealBonus (see Companions.gainXp) tops up its
-- species' own static rate rather than replacing it.
local function tendPlayer(game, companion)
  local spec = Companions.byKey[companion.species]
  if spec.heal and game.player.hp < game.player.maxHp then
    local amount = spec.heal + (companion.companionHealBonus or 0)
    game.player.hp = math.min(game.player.maxHp, game.player.hp + amount)
  end
end

-- Credits a companion's own kill tally with `amount` xp and, in the same
-- call, permanently applies every evolution stage (see Companions.species)
-- its running companionXp total first reaches - possibly more than one at
-- once, if a single grant vaults it clean past an intermediate threshold.
-- Entirely separate from the xp Game:awardKill still credits the player for
-- that identical kill (see Companions.act): the player's own level and this
-- companion's are two independent ladders climbed off the same battles.
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

-- The companion's full turn: engage the nearest visible monster if one is in
-- reach, close the distance to one it can see but not yet reach, otherwise
-- stay within a step of the player.
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
