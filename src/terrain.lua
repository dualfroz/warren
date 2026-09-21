local Tiles = require("tiles")
local Status = require("status")
local Resistances = require("resistances")

local Terrain = {}

Terrain.LAVA_DAMAGE = 8

function Terrain.slide(level, entity, dx, dy)
  local map = level.map
  while map:get(entity.x, entity.y) == Tiles.ICE do
    local nx, ny = entity.x + dx, entity.y + dy
    if not map:isWalkable(nx, ny) then break end
    if level:entityAt(nx, ny) then break end
    entity.x, entity.y = nx, ny
  end
end

function Terrain.afflictLava(level, entity)
  if level.map:get(entity.x, entity.y) ~= Tiles.LAVA then return nil end
  local dealt = Resistances.apply(entity, Terrain.LAVA_DAMAGE, Resistances.FIRE)
  entity.hp = entity.hp - dealt
  if dealt <= 0 then
    return entity.kind == "player" and "you wade through the lava unharmed"
      or string.format("%s wades through the lava unharmed", entity.name)
  end
  Status.apply(entity, Status.BURNING, 2, math.max(1, dealt // 3))
  return string.format("molten rock sears %s for %d", entity.name, dealt)
end

function Terrain.isChasm(level, entity)
  return level.map:get(entity.x, entity.y) == Tiles.CHASM
end

return Terrain
