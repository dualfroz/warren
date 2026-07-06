-- Permanent map terrain that punishes careless movement, as opposed to
-- hazards.lua's fire and gas which are timed and spawned mid-game. Lava
-- scorches whoever stands on it every time they step there, a chasm drops
-- the player to the floor below (or swallows a monster outright), and ice
-- keeps sliding a traveller in the direction they started moving until
-- something stops them. None of it spreads, fades, or needs saving beyond
-- the glyph already baked into the map by the builder.

local Tiles = require("tiles")
local Status = require("status")
local Resistances = require("resistances")

local Terrain = {}

Terrain.LAVA_DAMAGE = 8

-- Slides entity through consecutive ice tiles in direction (dx, dy), from
-- wherever it just came to rest. Stops the instant the current tile isn't
-- ice, the next cell is unwalkable, or another actor already occupies it -
-- so ice never carries a traveller through a wall or on top of someone else.
function Terrain.slide(level, entity, dx, dy)
  local map = level.map
  while map:get(entity.x, entity.y) == Tiles.ICE do
    local nx, ny = entity.x + dx, entity.y + dy
    if not map:isWalkable(nx, ny) then break end
    if level:entityAt(nx, ny) then break end
    entity.x, entity.y = nx, ny
  end
end

-- Applies lava's burn to whoever is currently standing on it. Returns a log
-- line, or nil when the tile underfoot isn't lava.
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
