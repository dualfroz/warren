-- Monster behaviours, one per ai tag. Each takes (game, monster) and fully
-- resolves that monster's turn through game helpers, so all state mutation and
-- rng use stays centralised and deterministic.

local Status = require("status")
local Infighting = require("infighting")

local Ai = {}

local AGGRO = { chase = 10, pack = 13, ranged = 12, flee = 8, erratic = 8, tunnel = 10 }
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- A player-aligned ally standing adjacent to `monster` occupies its cell
-- exactly the way a wall would for Game:stepMonsterToward's own pathfinding
-- (blockedForMonster treats any occupied non-goal cell as impassable) - so a
-- one-wide corridor an ally is plugging leaves every pursuit behaviour below
-- with no route at all, and without this check they simply idle beside it
-- forever rather than fighting the living combatant in their way. Resolves
-- through Infighting.strike, the same generic monster-vs-any-creature combat
-- infighting.lua already uses for rivalries and discord. Returns true once
-- it has spent the monster's turn this way, so each caller can bail out at
-- the same priority Game:playerAdjacent already has over closing distance.
local function attackBlockingAlly(game, monster)
  local ally = game:adjacentAlly(monster)
  if not ally then return false end
  Infighting.strike(game, monster, ally)
  return true
end

local function chase(game, monster)
  if game:playerAdjacent(monster) then
    game:monsterMelee(monster)
    return
  end
  if attackBlockingAlly(game, monster) then return end
  if game:canSeePlayer(monster, AGGRO.chase) then
    game:stepMonsterToward(monster, game.player.x, game.player.y)
  end
end

local function pack(game, monster)
  if game:playerAdjacent(monster) then
    game:monsterMelee(monster)
    return
  end
  if attackBlockingAlly(game, monster) then return end
  if game:canSeePlayer(monster, AGGRO.pack) then
    game:stepMonsterToward(monster, game.player.x, game.player.y)
    return
  end
  local ally = game:nearestAlly(monster)
  if ally then
    game:stepMonsterToward(monster, ally.x, ally.y)
  end
end

local function ranged(game, monster)
  if game:canSeePlayer(monster, monster.range) and game:hasClearShot(monster) then
    if game:playerAdjacent(monster) then
      game:stepMonsterAway(monster, game.player.x, game.player.y)
    else
      game:monsterShoot(monster)
    end
    return
  end
  if attackBlockingAlly(game, monster) then return end
  if game:canSeePlayer(monster, AGGRO.ranged) then
    game:stepMonsterToward(monster, game.player.x, game.player.y)
  end
end

local function flee(game, monster)
  if game:canSeePlayer(monster, AGGRO.flee) then
    game:stepMonsterAway(monster, game.player.x, game.player.y)
  end
end

-- Shopkeepers idle unless game.lua has already flagged them hostile (a theft
-- from their stock), at which point they behave exactly like a chaser.
local function vend(game, monster)
  if monster.hostile then
    chase(game, monster)
  end
end

local function erratic(game, monster)
  if game:playerAdjacent(monster) then
    game:monsterMelee(monster)
    return
  end
  if game:canSeePlayer(monster, AGGRO.erratic) and game.rng:chance(1, 2) then
    game:stepMonsterToward(monster, game.player.x, game.player.y)
  else
    local dir = DIRS[game.rng:range(1, 4)]
    game:moveMonster(monster, dir[1], dir[2])
  end
end

-- A burrower: melee once adjacent, chase like anything else once it can see
-- the player through open floor, otherwise claw straight through whatever
-- rock stands between them (see Game:monsterDig, digging.lua) rather than
-- idling the way a plain chaser out of sight would.
local function tunnel(game, monster)
  if game:playerAdjacent(monster) then
    game:monsterMelee(monster)
    return
  end
  if attackBlockingAlly(game, monster) then return end
  if game:canSeePlayer(monster, AGGRO.tunnel) then
    game:stepMonsterToward(monster, game.player.x, game.player.y)
    return
  end
  game:monsterDig(monster, game.player.x, game.player.y)
end

Ai.behaviours = {
  chase = chase,
  pack = pack,
  ranged = ranged,
  flee = flee,
  erratic = erratic,
  vend = vend,
  tunnel = tunnel,
}

-- A confused monster gets the exact same chance each turn to have its own
-- chosen direction overridden that Game:movePlayer rolls for the player - see
-- status.lua's Status.CONFUSE_NUMERATOR/DENOMINATOR, shared by both sides so
-- neither one confuses more reliably than the other. On a lucky roll (or once
-- confusion wears off) `behaviour` below runs completely untouched.
function Ai.act(game, monster)
  if Status.has(monster, Status.CONFUSE)
    and game.rng:chance(Status.CONFUSE_NUMERATOR, Status.CONFUSE_DENOMINATOR) then
    local dir = DIRS[game.rng:range(1, #DIRS)]
    game:moveMonster(monster, dir[1], dir[2])
    return
  end
  local behaviour = Ai.behaviours[monster.ai] or chase
  behaviour(game, monster)
end

return Ai
