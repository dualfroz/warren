-- Recursive-backtracker maze: a perfect spanning tree of one-wide corridors
-- over a grid of cells spaced two tiles apart, carved by an iterative
-- depth-first walk (an explicit stack, never Lua's own call stack, so
-- nothing here bounds how large a maze can grow). The result is a topology
-- none of the other generators produce - dense and twisty, with exactly one
-- path between any two cells - unlike the open rooms of gen.rooms/gen.bsp
-- or the organic blobs of gen.cellular/gen.drunkard. A braiding pass
-- afterward knocks down a fixed fraction of the walls still separating two
-- already-carved cells, so a fraction of what would otherwise be dead ends
-- gain a second way out instead. Selectable like any other entry in
-- gen.init's registry, but deliberately left out of Gen.order: nothing
-- downstream (builder.lua's rng-ordering discipline, every seed-pinned
-- depth test) currently expects the auto-cycle to ever hand it a floor, and
-- inserting a fifth entry there would reshuffle which of the existing four
-- generators every depth from five onward gets, and with it every rng draw
-- a builder places afterward. A maze floor is instead reached deliberately,
-- via options.generator = "maze".

local Map = require("map")
local Tiles = require("tiles")

local Maze = {}

Maze.BRAID_NUMERATOR = 1
Maze.BRAID_DENOMINATOR = 5

local DIRS = { { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }

local function shuffledDirs(rng)
  local dirs = { DIRS[1], DIRS[2], DIRS[3], DIRS[4] }
  for i = 4, 2, -1 do
    local j = rng:range(1, i)
    dirs[i], dirs[j] = dirs[j], dirs[i]
  end
  return dirs
end

function Maze.generate(width, height, rng, options)
  options = options or {}
  local braidNumerator = options.braidNumerator or Maze.BRAID_NUMERATOR
  local braidDenominator = options.braidDenominator or Maze.BRAID_DENOMINATOR
  local map = Map.new(width, height)

  local function key(x, y) return y * width + x end
  local visited = {}

  local startX, startY = 2, 2
  visited[key(startX, startY)] = true
  map:set(startX, startY, Tiles.FLOOR)
  local stack = { { startX, startY } }

  while #stack > 0 do
    local top = stack[#stack]
    local cx, cy = top[1], top[2]
    local advanced = false
    for _, dir in ipairs(shuffledDirs(rng)) do
      local nx, ny = cx + dir[1], cy + dir[2]
      if nx >= 2 and ny >= 2 and nx <= width - 1 and ny <= height - 1 and not visited[key(nx, ny)] then
        local wx, wy = cx + dir[1] // 2, cy + dir[2] // 2
        map:set(wx, wy, Tiles.FLOOR)
        map:set(nx, ny, Tiles.FLOOR)
        visited[key(nx, ny)] = true
        stack[#stack + 1] = { nx, ny }
        advanced = true
        break
      end
    end
    if not advanced then stack[#stack] = nil end
  end

  -- Braiding: a wall cell with floor on exactly one opposing pair of sides
  -- (east-west or north-south) sits between two cells the backtracker above
  -- already connected some longer way around; knocking a fixed fraction of
  -- these down trims some, but never all, of the maze's dead ends.
  for y = 3, height - 2 do
    for x = 3, width - 2 do
      if map:get(x, y) == Tiles.WALL then
        local linksEastWest = map:get(x - 1, y) == Tiles.FLOOR and map:get(x + 1, y) == Tiles.FLOOR
        local linksNorthSouth = map:get(x, y - 1) == Tiles.FLOOR and map:get(x, y + 1) == Tiles.FLOOR
        if (linksEastWest or linksNorthSouth) and rng:chance(braidNumerator, braidDenominator) then
          map:set(x, y, Tiles.FLOOR)
        end
      end
    end
  end

  return map
end

return Maze
