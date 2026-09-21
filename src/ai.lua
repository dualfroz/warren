local Status = require("status")
local Infighting = require("infighting")

local Ai = {}

local AGGRO = { chase = 10, pack = 13, ranged = 12, flee = 8, erratic = 8, tunnel = 10 }
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

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
