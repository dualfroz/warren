local Tiles = require("tiles")

local Carve = {}

function Carve.rect(map, x, y, w, h, glyph)
  glyph = glyph or Tiles.FLOOR
  for cy = y, y + h - 1 do
    for cx = x, x + w - 1 do
      map:set(cx, cy, glyph)
    end
  end
end

function Carve.hTunnel(map, x1, x2, y, glyph)
  glyph = glyph or Tiles.FLOOR
  for x = math.min(x1, x2), math.max(x1, x2) do
    map:set(x, y, glyph)
  end
end

function Carve.vTunnel(map, y1, y2, x, glyph)
  glyph = glyph or Tiles.FLOOR
  for y = math.min(y1, y2), math.max(y1, y2) do
    map:set(x, y, glyph)
  end
end

function Carve.center(room)
  return room.x + room.w // 2, room.y + room.h // 2
end

function Carve.corridor(map, ax, ay, bx, by, rng, glyph)
  if rng:chance(1, 2) then
    Carve.hTunnel(map, ax, bx, ay, glyph)
    Carve.vTunnel(map, ay, by, bx, glyph)
  else
    Carve.vTunnel(map, ay, by, ax, glyph)
    Carve.hTunnel(map, ax, bx, by, glyph)
  end
end

return Carve
