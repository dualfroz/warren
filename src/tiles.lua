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
Tiles.LAVA = "}"
Tiles.CHASM = "V"
Tiles.ICE = "-"
Tiles.LEVER = "H"
Tiles.LEVER_PULLED = "I"
Tiles.VAULT_DOOR = "K"
Tiles.GATE_CLOSED = "8"
Tiles.GATE_OPEN = "9"

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
  [Tiles.LAVA]        = { walkable = true,  blocksSight = false, door = false, lava = true },
  [Tiles.CHASM]       = { walkable = true,  blocksSight = false, door = false, chasm = true },
  [Tiles.ICE]         = { walkable = true,  blocksSight = false, door = false, ice = true },
  [Tiles.LEVER]        = { walkable = true,  blocksSight = false, door = false },
  [Tiles.LEVER_PULLED] = { walkable = true,  blocksSight = false, door = false },
  [Tiles.VAULT_DOOR]   = { walkable = false, blocksSight = true,  door = false, vault = true },
  [Tiles.GATE_CLOSED]  = { walkable = false, blocksSight = true,  door = false, gate = true },
  [Tiles.GATE_OPEN]    = { walkable = true,  blocksSight = false, door = false, gate = true },
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

function Tiles.isLava(glyph)
  return Tiles.of(glyph).lava == true
end

function Tiles.isChasm(glyph)
  return Tiles.of(glyph).chasm == true
end

function Tiles.isIce(glyph)
  return Tiles.of(glyph).ice == true
end

function Tiles.isVaultDoor(glyph)
  return Tiles.of(glyph).vault == true
end

function Tiles.isGate(glyph)
  return Tiles.of(glyph).gate == true
end

return Tiles
