-- Sound propagation. Unlike los.lua's straight sightline, a noisy action's
-- racket bends around corners: it floods outward from its origin through
-- open, walkable cells only, using the same four-directional adjacency
-- astar.lua's own pathing already assumes (see its DIRS and game.lua's
-- MONSTER_DIRS), and fades by exactly one point of loudness for every step
-- the flood has to take to get there. A closed door or a solid wall stops
-- it dead - nothing leaks through a wall diagonally the way it might with
-- an eight-directional flood, so a noise never reaches anywhere a monster
-- could not actually have walked to investigate it.
--
-- The flood itself has no idea what a monster or a player is; it is a pure
-- function of the map, an origin and a starting loudness. game.lua's
-- Game:emitNoise is what turns a resulting field into a dormant monster
-- actually stirring (see stealth.lua's Stealth.hear).

local Noise = {}

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Loudness constants for the actions game.lua wires up to emitNoise, tuned
-- so a whisper-quiet action (nothing currently that quiet) would decay
-- within a couple of cells while a pick striking stone carries the length
-- of a small floor.
Noise.MELEE = 6
Noise.RANGED = 6
Noise.THROW = 5
Noise.SPELL = 8
Noise.DIG = 9

-- Floods outward from (x, y) through walkable cells, returning a table
-- keyed by map:index(nx, ny) -> the loudness still remaining once the sound
-- has traveled there (loudness itself at the origin, decaying by one per
-- step, never revisiting a cell at an intensity no better than one already
-- recorded there). A cell the flood never reaches simply has no entry. The
-- origin itself need not be walkable - a pick striking solid rock (see
-- game.lua's Game:dig) is exactly as loud as one striking rubble - only the
-- cells the flood actually spreads into have to be open for anything to
-- ever stand in them and hear it.
function Noise.propagate(map, x, y, loudness)
  local field = {}
  if loudness <= 0 or not map:inBounds(x, y) then return field end
  local startIdx = map:index(x, y)
  field[startIdx] = loudness
  local queue = { { x = x, y = y, intensity = loudness } }
  local head = 1
  while head <= #queue do
    local cur = queue[head]
    head = head + 1
    if cur.intensity > 0 then
      local nextIntensity = cur.intensity - 1
      for _, dir in ipairs(DIRS) do
        local nx, ny = cur.x + dir[1], cur.y + dir[2]
        if map:isWalkable(nx, ny) then
          local idx = map:index(nx, ny)
          if (field[idx] or -1) < nextIntensity then
            field[idx] = nextIntensity
            queue[#queue + 1] = { x = nx, y = ny, intensity = nextIntensity }
          end
        end
      end
    end
  end
  return field
end

-- Remaining loudness a previously computed field still carries at (x, y),
-- or 0 for anywhere the flood never reached (including out of bounds, which
-- map:index would otherwise happily compute an index for).
function Noise.intensityAt(field, map, x, y)
  if not map:inBounds(x, y) then return 0 end
  return field[map:index(x, y)] or 0
end

return Noise
