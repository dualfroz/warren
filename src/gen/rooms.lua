local Map = require("map")
local Carve = require("gen.carve")

local Rooms = {}

local function overlaps(a, b)
  return a.x <= b.x + b.w and a.x + a.w >= b.x
     and a.y <= b.y + b.h and a.y + a.h >= b.y
end

function Rooms.generate(width, height, rng, options)
  options = options or {}
  local maxRooms = options.maxRooms or 14
  local minSize = options.minRoomSize or 4
  local maxSize = options.maxRoomSize or 9
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
      if overlaps(room, other) then
        fits = false
        break
      end
    end
    if fits then
      Carve.rect(map, room.x, room.y, room.w, room.h)
      if #map.rooms > 0 then
        local prevX, prevY = Carve.center(map.rooms[#map.rooms])
        local newX, newY = Carve.center(room)
        Carve.corridor(map, prevX, prevY, newX, newY, rng)
      end
      map.rooms[#map.rooms + 1] = room
    end
  end

  return map
end

return Rooms
