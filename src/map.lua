-- Level grid: walls, floors, stairs, doors, traps and other terrain. Tile
-- semantics (walkable, blocks sight, is a door) live in the Tiles registry;
-- the default generator places random non-overlapping rooms and links their
-- centres with L-shaped corridors.

local Tiles = require("tiles")

local Map = {}
Map.__index = Map

Map.WALL = Tiles.WALL
Map.FLOOR = Tiles.FLOOR
Map.STAIRS = Tiles.STAIRS_DOWN
Map.STAIRS_DOWN = Tiles.STAIRS_DOWN
Map.STAIRS_UP = Tiles.STAIRS_UP
Map.DOOR_CLOSED = Tiles.DOOR_CLOSED
Map.DOOR_OPEN = Tiles.DOOR_OPEN
Map.DOOR_LOCKED = Tiles.DOOR_LOCKED
Map.TRAP = Tiles.TRAP
Map.WATER = Tiles.WATER

local function newGrid(width, height, fill)
  local tiles = {}
  for i = 1, width * height do
    tiles[i] = fill
  end
  return tiles
end

function Map.new(width, height)
  return setmetatable({
    width = width,
    height = height,
    tiles = newGrid(width, height, Map.WALL),
    rooms = {},
    stairsX = 0, stairsY = 0,
    startX = 0, startY = 0,
  }, Map)
end

function Map:index(x, y)
  return (y - 1) * self.width + x
end

function Map:inBounds(x, y)
  return x >= 1 and y >= 1 and x <= self.width and y <= self.height
end

function Map:get(x, y)
  if not self:inBounds(x, y) then return Map.WALL end
  return self.tiles[self:index(x, y)]
end

function Map:set(x, y, tile)
  self.tiles[self:index(x, y)] = tile
end

function Map:isWalkable(x, y)
  return Tiles.isWalkable(self:get(x, y))
end

function Map:blocksSight(x, y)
  return Tiles.blocksSight(self:get(x, y))
end

-- Passability for pathing: closed doors count as passable so routes lead through
-- them; a locked door is only passable when the traveller holds a key.
function Map:isPassable(x, y, hasKey)
  local tile = self:get(x, y)
  if Tiles.isWalkable(tile) then return true end
  if tile == Map.DOOR_CLOSED then return true end
  if tile == Map.DOOR_LOCKED then return hasKey == true end
  return false
end

local function carveRoom(map, room)
  for y = room.y, room.y + room.h - 1 do
    for x = room.x, room.x + room.w - 1 do
      map:set(x, y, Map.FLOOR)
    end
  end
end

local function carveHTunnel(map, x1, x2, y)
  for x = math.min(x1, x2), math.max(x1, x2) do
    map:set(x, y, Map.FLOOR)
  end
end

local function carveVTunnel(map, y1, y2, x)
  for y = math.min(y1, y2), math.max(y1, y2) do
    map:set(x, y, Map.FLOOR)
  end
end

local function roomsOverlap(a, b)
  return a.x <= b.x + b.w and a.x + a.w >= b.x
     and a.y <= b.y + b.h and a.y + a.h >= b.y
end

local function roomCenter(room)
  return room.x + room.w // 2, room.y + room.h // 2
end

function Map.generate(width, height, rng, options)
  options = options or {}
  local maxRooms = options.maxRooms or 12
  local minSize = options.minRoomSize or 4
  local maxSize = options.maxRoomSize or 8
  local map = Map.new(width, height)

  for _ = 1, maxRooms do
    local w = rng:range(minSize, maxSize)
    local h = rng:range(minSize, maxSize)
    local room = {
      x = rng:range(2, width - w - 1),
      y = rng:range(2, height - h - 1),
      w = w, h = h,
    }
    local fits = true
    for _, other in ipairs(map.rooms) do
      if roomsOverlap(room, other) then
        fits = false
        break
      end
    end
    if fits then
      carveRoom(map, room)
      if #map.rooms > 0 then
        local prevX, prevY = roomCenter(map.rooms[#map.rooms])
        local newX, newY = roomCenter(room)
        if rng:chance(1, 2) then
          carveHTunnel(map, prevX, newX, prevY)
          carveVTunnel(map, prevY, newY, newX)
        else
          carveVTunnel(map, prevY, newY, prevX)
          carveHTunnel(map, prevX, newX, newY)
        end
      end
      map.rooms[#map.rooms + 1] = room
    end
  end

  map.startX, map.startY = roomCenter(map.rooms[1])
  map.stairsX, map.stairsY = roomCenter(map.rooms[#map.rooms])
  map:set(map.stairsX, map.stairsY, Map.STAIRS)
  return map
end

function Map:toData()
  return {
    width = self.width,
    height = self.height,
    tiles = table.concat(self.tiles),
    rooms = self.rooms,
    stairsX = self.stairsX, stairsY = self.stairsY,
    startX = self.startX, startY = self.startY,
  }
end

function Map.fromData(snapshot)
  local map = setmetatable({}, Map)
  map.width = snapshot.width
  map.height = snapshot.height
  map.tiles = {}
  for i = 1, #snapshot.tiles do
    map.tiles[i] = snapshot.tiles:sub(i, i)
  end
  map.rooms = snapshot.rooms
  map.stairsX, map.stairsY = snapshot.stairsX, snapshot.stairsY
  map.startX, map.startY = snapshot.startX, snapshot.startY
  return map
end

return Map
