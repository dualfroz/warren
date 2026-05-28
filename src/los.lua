-- Bresenham line of sight. A shot is clear when no cell strictly between the two
-- endpoints blocks sight; the endpoints themselves are never treated as blockers
-- so an actor can fire at something standing in a doorway.

local Los = {}

function Los.line(x0, y0, x1, y1)
  local cells = {}
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx - dy
  local x, y = x0, y0
  while true do
    cells[#cells + 1] = { x = x, y = y }
    if x == x1 and y == y1 then break end
    local e2 = 2 * err
    if e2 > -dy then err = err - dy; x = x + sx end
    if e2 < dx then err = err + dx; y = y + sy end
  end
  return cells
end

function Los.clear(map, x0, y0, x1, y1)
  local cells = Los.line(x0, y0, x1, y1)
  for i = 2, #cells - 1 do
    if map:blocksSight(cells[i].x, cells[i].y) then return false end
  end
  return true
end

return Los
