-- Cellular-automata caves. Seed the interior with random walls, then relax with
-- the classic 4-5 rule so blobs of open space and rock emerge. Connectivity is
-- enforced afterwards by the dungeon layer.

local Map = require("map")
local Tiles = require("tiles")

local Cellular = {}

local function wallNeighbours(grid, width, height, x, y)
  local count = 0
  for dy = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local nx, ny = x + dx, y + dy
        if nx < 1 or ny < 1 or nx > width or ny > height then
          count = count + 1
        elseif grid[(ny - 1) * width + nx] then
          count = count + 1
        end
      end
    end
  end
  return count
end

function Cellular.generate(width, height, rng, options)
  options = options or {}
  local fillChance = options.fillChance or 45
  local steps = options.steps or 5
  local grid = {}
  for y = 1, height do
    for x = 1, width do
      local idx = (y - 1) * width + x
      if x == 1 or y == 1 or x == width or y == height then
        grid[idx] = true
      else
        grid[idx] = rng:range(1, 100) <= fillChance
      end
    end
  end

  for _ = 1, steps do
    local nextGrid = {}
    for y = 1, height do
      for x = 1, width do
        local idx = (y - 1) * width + x
        local walls = wallNeighbours(grid, width, height, x, y)
        if x == 1 or y == 1 or x == width or y == height then
          nextGrid[idx] = true
        else
          nextGrid[idx] = walls >= 5
        end
      end
    end
    grid = nextGrid
  end

  local map = Map.new(width, height)
  for y = 1, height do
    for x = 1, width do
      if not grid[(y - 1) * width + x] then
        map:set(x, y, Tiles.FLOOR)
      end
    end
  end
  return map
end

return Cellular
