local Map = require("map")
local Tiles = require("tiles")
local Connect = require("gen.connect")
local Monsters = require("monsters")
local Elites = require("elites")
local Stealth = require("stealth")

local Horde = {}

Horde.WIDTH = 19
Horde.HEIGHT = 13
Horde.PILLAR_NUMERATOR = 1
Horde.PILLAR_DENOMINATOR = 9

Horde.SPAWN_CLEARANCE = 2

Horde.BASE_COUNT = 3
Horde.COUNT_PER_WAVE = 1
Horde.MAX_COUNT = 12

Horde.REST_HEAL = 4
Horde.ESSENCE_PER_WAVE = 5

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

function Horde.spawnAnchors(width, height)
  return {
    { x = 2, y = 2 }, { x = width - 1, y = 2 },
    { x = 2, y = height - 1 }, { x = width - 1, y = height - 1 },
  }
end

function Horde.spawnPoints(map)
  local anchors = Horde.spawnAnchors(map.width, map.height)
  local perAnchor, claimed = {}, {}
  for _, anchor in ipairs(anchors) do
    local cells = {}
    for y = anchor.y - Horde.SPAWN_CLEARANCE, anchor.y + Horde.SPAWN_CLEARANCE do
      for x = anchor.x - Horde.SPAWN_CLEARANCE, anchor.x + Horde.SPAWN_CLEARANCE do
        local idx = map:inBounds(x, y) and map:index(x, y)
        if idx and not claimed[idx] and map:isWalkable(x, y) then
          claimed[idx] = true
          cells[#cells + 1] = { x = x, y = y }
        end
      end
    end
    perAnchor[#perAnchor + 1] = cells
  end
  local points = {}
  local i, more = 1, true
  while more do
    more = false
    for _, cells in ipairs(perAnchor) do
      if cells[i] then
        points[#points + 1] = cells[i]
        more = true
      end
    end
    i = i + 1
  end
  return points
end

function Horde.buildArena(rng, width, height)
  width = width or Horde.WIDTH
  height = height or Horde.HEIGHT
  local map = Map.new(width, height)
  for y = 2, height - 1 do
    for x = 2, width - 1 do
      map:set(x, y, Tiles.FLOOR)
    end
  end
  local anchors = Horde.spawnAnchors(width, height)
  local cx, cy = width // 2 + 1, height // 2 + 1
  for y = 2, height - 1 do
    for x = 2, width - 1 do
      local clear = x == cx and y == cy
      if not clear then
        for _, anchor in ipairs(anchors) do
          if chebyshev(x, y, anchor.x, anchor.y) <= Horde.SPAWN_CLEARANCE then
            clear = true
            break
          end
        end
      end
      if not clear and rng:chance(Horde.PILLAR_NUMERATOR, Horde.PILLAR_DENOMINATOR) then
        map:set(x, y, Tiles.WALL)
      end
    end
  end
  Connect.ensure(map, rng)
  return map, cx, cy
end

function Horde.newState()
  return { wave = 0 }
end

function Horde.depthFor(wave)
  return wave
end

function Horde.countFor(wave)
  local count = Horde.BASE_COUNT + (wave - 1) * Horde.COUNT_PER_WAVE
  if count > Horde.MAX_COUNT then count = Horde.MAX_COUNT end
  return count
end

function Horde.essenceFor(wave)
  return wave * Horde.ESSENCE_PER_WAVE
end

function Horde.pool(wave)
  local eligible = {}
  for _, spec in ipairs(Monsters.forDepth(Horde.depthFor(wave))) do
    if spec.ai ~= "vend" then eligible[#eligible + 1] = spec end
  end
  return eligible
end

function Horde.cleared(level)
  for _, entity in ipairs(level.entities) do
    if entity.kind == "monster" and entity:isAlive() then return false end
  end
  return true
end

function Horde.spawnWave(game, wave)
  local level = game.level
  local points = Horde.spawnPoints(level.map)
  local pool = Horde.pool(wave)
  local count = math.min(Horde.countFor(wave), #points)
  local depth = Horde.depthFor(wave)
  local spawned = {}
  for i = 1, count do
    local point = points[i]
    local spec = game.rng:pick(pool)
    local entity = Monsters.create(spec, game:nextMonsterId(), point.x, point.y, depth)
    entity.awareness = Stealth.HUNTING
    Elites.maybePromote(game.rng, entity, depth)
    level.entities[#level.entities + 1] = entity
    spawned[#spawned + 1] = entity
  end
  return spawned
end

function Horde.tick(game)
  local horde = game.horde
  if not horde then return nil end
  if not Horde.cleared(game.level) then return nil end
  local reward = Horde.essenceFor(horde.wave)
  if reward > 0 then
    game.player.essence = game.player.essence + reward
  end
  game.player.hp = math.min(game.player.maxHp, game.player.hp + Horde.REST_HEAL)
  horde.wave = horde.wave + 1
  Horde.spawnWave(game, horde.wave)
  if horde.wave == 1 then
    return "the horde arena falls silent - wave 1 begins"
  end
  return string.format("the arena falls silent - wave %d begins (+%d essence)", horde.wave, reward)
end

return Horde
