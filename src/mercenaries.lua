-- Paid allies hired from a shop's contract rather than bonded for free like
-- companions.lua's charm or spent raising reanimation.lua's thrall. A
-- hireling costs nothing further to take on - its hireCost is already paid
-- the instant the contract itself is bought from a shopkeeper (see
-- shop.lua's CONTRACT pricing) - but it keeps demanding a wage every
-- Mercenaries.WAGE_INTERVAL turns (Game:endPlayerTurn) for as long as it
-- lives. Gold covers it, the hireling's loyalty tops back up; gold falls
-- short, loyalty takes a hit instead, and a hireling whose loyalty bottoms
-- out deserts outright. A merely sulking hireling (loyalty still positive
-- but under Mercenaries.SULKING_THRESHOLD) keeps defending itself if a fight
-- finds it, but stops chasing distant prey or shadowing the player - the
-- one place loyalty reaches into combat, and it does so entirely inside
-- Mercenaries.act rather than through combat.lua or entity.lua, so hiring
-- one never risks a require cycle with either.
-- Only one hireling walks at a time, the same one-bond-at-a-time rule
-- companions.lua keeps for its own charm - but a hireling and a companion
-- may walk together, since they are bonded through entirely separate
-- currencies (gold contract vs. found charm) and tagged with distinct kinds.
-- Hirelings are plain entities on level.entities, exactly like companions
-- and thralls, so they serialize with no special save-format handling
-- beyond the two extra fields (wage, loyalty) entity.lua's toData whitelist
-- adds.

local Entity = require("entity")
local Combat = require("combat")
local Los = require("los")
local Status = require("status")
local Noise = require("noise")

local Mercenaries = {}

Mercenaries.roster = {
  { key = "sellsword",  glyph = "w", name = "sellsword",    hp = 24, attack = 6, defense = 2, speed = 100,
    sight = 6, hireCost = 60, wage = 14 },
  { key = "skirmisher", glyph = "k", name = "skirmisher",   hp = 15, attack = 5, defense = 1, speed = 115,
    sight = 8, hireCost = 50, wage = 11 },
  { key = "medic",      glyph = "m", name = "field medic",  hp = 13, attack = 2, defense = 1, speed = 100,
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

-- Takes `key` into service on a free cell next to the player, retiring any
-- earlier hireling first. Returns the new hireling, or nil for an unknown
-- roster key or when every cell around the player is blocked.
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

-- Releases the live hireling (if any) with no penalty to either side.
-- Returns its name for the caller to log, or nil when nobody is under
-- contract.
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

-- Charges the live hireling's wage, or shorts it: paid tops loyalty back up
-- (capped at MAX_LOYALTY), unpaid knocks it down by LOYALTY_LOSS_UNPAID and,
-- once it bottoms out, the hireling deserts outright - removed from the
-- level exactly like a voluntary dismiss, just for the opposite reason.
-- Returns a log line, or nil when no hireling is currently in the party to
-- bill.
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

-- Nearest living monster the hireling can see within its species' sight
-- radius, ties broken by ascending id for determinism - the same shape
-- companions.lua's own nearestHostile follows, including its blind clamp
-- (Game:canSeePlayer's own melee-range fallback for a blinded monster).
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

-- A field medic mends its employer a little on any turn it does not spend
-- fighting or sulking - the only roster entry with a passive off-turn
-- effect, the same shape companions.lua's hearth sprite follows.
local function tendPlayer(game, hireling)
  local spec = Mercenaries.byKey[hireling.species]
  if spec.heal and game.player.hp < game.player.maxHp then
    game.player.hp = math.min(game.player.maxHp, game.player.hp + spec.heal)
  end
end

-- The hireling's full turn: engage the nearest visible monster if one is in
-- reach regardless of loyalty, but once loyalty has sunk to
-- SULKING_THRESHOLD or below, stop there - no chasing a target it can see
-- but not yet reach, no shadowing the player, no tending. A loyal hireling
-- gets the full three-branch shape companions.act and Reanimation.act both
-- follow: engage, close in, or stay within a step of the player.
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
