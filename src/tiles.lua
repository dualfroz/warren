-- Central registry of tile glyphs and their terrain properties. Every module
-- that needs to know whether a cell can be stood on, blocks sight, or is a door
-- consults this table instead of hardcoding glyph comparisons.

local Tiles = {}

Tiles.WALL = "#"
Tiles.FLOOR = "."
Tiles.STAIRS_DOWN = ">"
Tiles.STAIRS_UP = "<"
Tiles.DOOR_CLOSED = "+"
Tiles.DOOR_OPEN = "'"
Tiles.DOOR_LOCKED = "x"
Tiles.TRAP = "^"
Tiles.WATER = "~"
Tiles.RUBBLE = ":"

local props = {
  [Tiles.WALL]        = { walkable = false, blocksSight = true,  door = false },
  [Tiles.FLOOR]       = { walkable = true,  blocksSight = false, door = false },
  [Tiles.STAIRS_DOWN] = { walkable = true,  blocksSight = false, door = false },
  [Tiles.STAIRS_UP]   = { walkable = true,  blocksSight = false, door = false },
  [Tiles.DOOR_CLOSED] = { walkable = false, blocksSight = true,  door = true },
  [Tiles.DOOR_LOCKED] = { walkable = false, blocksSight = true,  door = true, locked = true },
  [Tiles.DOOR_OPEN]   = { walkable = true,  blocksSight = false, door = true },
  [Tiles.TRAP]        = { walkable = true,  blocksSight = false, door = false },
  [Tiles.WATER]       = { walkable = true,  blocksSight = false, door = false },
  [Tiles.RUBBLE]      = { walkable = true,  blocksSight = false, door = false },
}

local wallProps = props[Tiles.WALL]

function Tiles.of(glyph)
  return props[glyph] or wallProps
end

function Tiles.isWalkable(glyph)
  return Tiles.of(glyph).walkable
end

function Tiles.blocksSight(glyph)
  return Tiles.of(glyph).blocksSight
end

function Tiles.isDoor(glyph)
  return Tiles.of(glyph).door
end

function Tiles.isClosedDoor(glyph)
  return glyph == Tiles.DOOR_CLOSED or glyph == Tiles.DOOR_LOCKED
end

return Tiles
