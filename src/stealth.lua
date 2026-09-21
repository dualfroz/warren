local Los = require("los")
local Skills = require("skills")

local Stealth = {}

Stealth.DORMANT = "dormant"
Stealth.HUNTING = "hunting"
Stealth.SEARCHING = "searching"

Stealth.WAKE_RADIUS = 6
Stealth.TRACK_RADIUS = 20
Stealth.LOST_TURNS_LIMIT = 4
Stealth.SEARCH_TURNS_LIMIT = 4
Stealth.SNEAK_MULTIPLIER = 3

function Stealth.isUnaware(monster)
  return monster.awareness == Stealth.DORMANT
end

function Stealth.sneakMultiplier(monster)
  if Stealth.isUnaware(monster) then return Stealth.SNEAK_MULTIPLIER end
  return 1
end

function Stealth.alert(monster, px, py)
  monster.awareness = Stealth.HUNTING
  monster.lastKnownX, monster.lastKnownY = px, py
  monster.lostTurns = 0
end

function Stealth.hear(monster, x, y)
  if monster.awareness ~= Stealth.DORMANT then return end
  monster.awareness = Stealth.SEARCHING
  monster.lastKnownX, monster.lastKnownY = x, y
  monster.searchTurns = 0
end

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function canSpot(game, monster, radius)
  local penalty = Skills.detectionPenalty(game.player, game.level.dark)
  local effective = radius - penalty
  if effective < 1 then effective = 1 end
  if chebyshev(monster.x, monster.y, game.player.x, game.player.y) > effective then return false end
  return Los.clear(game.level.map, monster.x, monster.y, game.player.x, game.player.y)
end

local function rollWake(game, monster)
  if not canSpot(game, monster, Stealth.WAKE_RADIUS) then return false end
  local dist = chebyshev(monster.x, monster.y, game.player.x, game.player.y)
  if dist <= 1 then return true end
  local penalty = Skills.detectionPenalty(game.player, game.level.dark)
  local radius = math.max(Stealth.WAKE_RADIUS - penalty, 1)
  local roll = game.rng:range(1, radius)
  return roll <= (radius - dist + 1)
end

function Stealth.tick(game, monster)
  local awareness = monster.awareness or Stealth.HUNTING
  if awareness == Stealth.DORMANT then
    if rollWake(game, monster) then
      Stealth.alert(monster, game.player.x, game.player.y)
      game.log:add(string.format("%s stirs awake", monster.name))
      return true
    end
    return false
  end
  if awareness == Stealth.SEARCHING then
    if canSpot(game, monster, Stealth.TRACK_RADIUS) then
      Stealth.alert(monster, game.player.x, game.player.y)
      return true
    end
    monster.searchTurns = (monster.searchTurns or 0) + 1
    if monster.lastKnownX and (monster.x ~= monster.lastKnownX or monster.y ~= monster.lastKnownY) then
      game:stepMonsterToward(monster, monster.lastKnownX, monster.lastKnownY)
    end
    if monster.searchTurns >= Stealth.SEARCH_TURNS_LIMIT then
      monster.awareness = Stealth.DORMANT
      monster.lastKnownX, monster.lastKnownY = nil, nil
      monster.lostTurns, monster.searchTurns = nil, nil
      game.log:add(string.format("%s gives up the search and settles back down", monster.name))
    end
    return false
  end
  if canSpot(game, monster, Stealth.TRACK_RADIUS) then
    monster.lastKnownX, monster.lastKnownY = game.player.x, game.player.y
    monster.lostTurns = 0
    return true
  end
  monster.lostTurns = (monster.lostTurns or 0) + 1
  if monster.lostTurns >= Stealth.LOST_TURNS_LIMIT and monster.lastKnownX then
    monster.awareness = Stealth.SEARCHING
    monster.searchTurns = 0
    game.log:add(string.format("%s loses track of you", monster.name))
    return Stealth.tick(game, monster)
  end
  return true
end

return Stealth
