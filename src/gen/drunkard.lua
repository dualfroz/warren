local Map = require("map")
local Tiles = require("tiles")

local Drunkard = {}

local STEPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Drunkard.generate(width, height, rng, options)
  options = options or {}
  local coverage = options.coverage or 0.42
  local target = math.floor((width - 2) * (height - 2) * coverage)
  local map = Map.new(width, height)
  local x, y = width // 2, height // 2
  map:set(x, y, Tiles.FLOOR)
  local carved = 1
  local budget = width * height * 40

  while carved < target and budget > 0 do
    budget = budget - 1
    local dir = STEPS[rng:range(1, 4)]
    local nx, ny = x + dir[1], y + dir[2]
    if nx >= 2 and ny >= 2 and nx <= width - 1 and ny <= height - 1 then
      x, y = nx, ny
      if map:get(x, y) ~= Tiles.FLOOR then
        map:set(x, y, Tiles.FLOOR)
        carved = carved + 1
      end
    end
  end
  return map
end

return Drunkard
