local Tiles = require("tiles")

local Secrets = {}

Secrets.SEARCH_NUMERATOR = 1
Secrets.SEARCH_DENOMINATOR = 5

function Secrets.sweep(level, rng, px, py)
  local found = {}
  for _, door in ipairs(level.secretDoors) do
    if not door.discovered
      and math.max(math.abs(door.x - px), math.abs(door.y - py)) <= 1
      and rng:chance(Secrets.SEARCH_NUMERATOR, Secrets.SEARCH_DENOMINATOR) then
      door.discovered = true
      level.map:set(door.x, door.y, Tiles.DOOR_CLOSED)
      found[#found + 1] = door
    end
  end
  return found
end

function Secrets.revealAll(level)
  local found = {}
  for _, door in ipairs(level.secretDoors) do
    if not door.discovered then
      door.discovered = true
      level.map:set(door.x, door.y, Tiles.DOOR_CLOSED)
      found[#found + 1] = door
    end
  end
  return found
end

return Secrets
