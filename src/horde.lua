-- Horde Arena: an optional survival trial layered onto an existing run,
-- entirely separate from the depth-descent dungeon (dungeon.lua/builder.lua
-- never run for it - Game:startHorde builds one closed Level directly, see
-- Horde.buildArena) yet it still runs through every existing turn system
-- untouched: scheduler.lua, ai.lua and combat.lua all just see a Level like
-- any other, since Level.new already defaults every collection an arena has
-- no use for (shrines, nodes, traps, quest boards...) to an empty table.
-- What makes it a *horde* rather than one more static floor is Horde.tick,
-- wired into Game:endPlayerTurn behind a game.horde check: the instant
-- every monster the current wave placed is dead, it banks a reward, heals a
-- slice of damage back, and throws the next wave in immediately - there is
-- never a turn where the arena stands empty. A wave's difficulty is driven
-- by the same Monsters.forDepth/Elites.maybePromote a real floor already
-- uses, just fed the wave number as if it were depth, so it never plateaus:
-- long past the point every species has unlocked, waves just keep growing
-- larger and rolling elites more often, exactly as if still descending.
--
-- Scope: a fresh Game.new never has a game.horde field at all, exactly like
-- game.nemesis before a nemesis has ever spawned. Because the arena level
-- lives outside self.dungeon entirely, Game:toData/fromData snapshot both
-- game.horde and the arena's own Level separately (hordeLevel) so a save
-- taken mid-arena resumes the exact wave in progress rather than silently
-- dropping the player back onto the ordinary floor the arena replaced.

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

-- Chebyshev radius around each corner anchor left pillar-free by
-- Horde.buildArena, and the radius Horde.spawnPoints itself searches within
-- of the very same anchors - the two have to agree, or a spawn queue built
-- wider than the guaranteed-clear zone could try to place a monster on a
-- cell that turned out to be a pillar.
Horde.SPAWN_CLEARANCE = 2

Horde.BASE_COUNT = 3
Horde.COUNT_PER_WAVE = 1
Horde.MAX_COUNT = 12

Horde.REST_HEAL = 4
Horde.ESSENCE_PER_WAVE = 5

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- Fixed corner anchors, inset one cell from the border wall so they are
-- never the border itself and always inside the interior floor Horde.buildArena
-- carves - plain open floor by construction, regardless of anything rolled
-- on the rng that built the rest of the arena.
function Horde.spawnAnchors(width, height)
  return {
    { x = 2, y = 2 }, { x = width - 1, y = 2 },
    { x = 2, y = height - 1 }, { x = width - 1, y = height - 1 },
  }
end

-- The deterministic placement queue Horde.spawnWave fills wave by wave:
-- every walkable cell within Horde.SPAWN_CLEARANCE of any anchor, round-
-- robin across the four anchors (first cell of each, then second cell of
-- each...) rather than anchor-by-anchor, so even a small wave arrives from
-- more than one direction instead of clumping in a single corner. Each
-- underlying map cell can only ever claim one slot in the queue, even if
-- two anchors' clearance zones happened to overlap.
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

-- One fully-enclosed arena: a rectangle of floor ringed by wall, its
-- interior sparsely sown with single-tile pillars for cover - except within
-- Horde.SPAWN_CLEARANCE of any corner anchor, and the centre cell (the
-- player's own start, see Game:startHorde), both deliberately left clear
-- regardless of what the pillar pass would otherwise roll there.
-- Connect.ensure runs last, exactly like every generator gen.init already
-- dispatches to, so a pillar can never wall off a pocket of floor even
-- though placement itself never checks for that. Returns the map plus the
-- centre cell, since Game:startHorde needs it for the player's own start.
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

-- Species eligible for wave `wave`, drawn from Monsters.forDepth at
-- Horde.depthFor(wave) exactly like a real floor's population, minus the
-- passive vend-behaviour shopkeeper - a wave the player can never provoke
-- into fighting back would leave Horde.cleared permanently false.
function Horde.pool(wave)
  local eligible = {}
  for _, spec in ipairs(Monsters.forDepth(Horde.depthFor(wave))) do
    if spec.ai ~= "vend" then eligible[#eligible + 1] = spec end
  end
  return eligible
end

-- True once every hostile monster the arena has ever placed is dead -
-- vacuously true against a still-empty arena too, which is exactly what
-- lets Horde.tick reuse the same check to bootstrap wave 1 as it does to
-- clear every wave after it (see Horde.tick's own comment). Filtered to
-- entity.kind == "monster", the same "hostile" tag every other module
-- (companions.lua/mercenaries.lua/reanimation.lua/abilities.lua...) uses:
-- Game:startHorde can now carry a bonded companion/hireling/thrall into the
-- arena, and an ally that never dies to the wave itself would otherwise
-- keep this permanently false, freezing the arena on wave 0 forever.
function Horde.cleared(level)
  for _, entity in ipairs(level.entities) do
    if entity.kind == "monster" and entity:isAlive() then return false end
  end
  return true
end

-- Populates `game.level` with wave `wave`'s monsters, drawn from
-- Horde.pool and placed one to a cell along Horde.spawnPoints's queue -
-- never doubling two monsters onto the same cell, the one-entity-per-cell
-- invariant every other spawn path in game.lua already relies on. Every
-- spawn is already hunting, exactly like Game:spawnMinion's own summons -
-- an arena has no stealth approach to sneak past. Returns the spawned
-- entities.
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

-- Advances horde state by one player turn, called from Game:endPlayerTurn
-- behind a `game.horde` check. A no-op while the current wave still has a
-- living monster in it; the instant it does not - including the very first
-- call, against the still-empty arena Game:startHorde just built, since
-- Horde.cleared reads that the same way as a genuinely finished wave - it
-- banks Horde.essenceFor(wave) essence (zero the first time, wave still
-- being 0), heals Horde.REST_HEAL, advances the wave counter, and spawns
-- the new wave outright, so the arena is never left standing empty for
-- even a single turn. Returns a log line, or nil when nothing happened.
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
