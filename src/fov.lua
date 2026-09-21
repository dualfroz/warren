local Fov = {}

local mult = {
  { 1, 0, 0, -1, -1, 0, 0, 1 },
  { 0, 1, -1, 0, 0, -1, 1, 0 },
  { 0, 1, 1, 0, 0, -1, -1, 0 },
  { 1, 0, 0, 1, -1, 0, 0, -1 },
}

local function castLight(map, cx, cy, row, start, finish, radius, xx, xy, yx, yy, visible)
  if start < finish then return end
  local radiusSq = radius * radius
  local newStart = 0.0
  for j = row, radius do
    local dx, dy = -j - 1, -j
    local blocked = false
    while dx <= 0 do
      dx = dx + 1
      local mapX = cx + dx * xx + dy * xy
      local mapY = cy + dx * yx + dy * yy
      local leftSlope = (dx - 0.5) / (dy + 0.5)
      local rightSlope = (dx + 0.5) / (dy - 0.5)
      if start < rightSlope then
      elseif finish > leftSlope then
        break
      else
        if dx * dx + dy * dy <= radiusSq and map:inBounds(mapX, mapY) then
          visible[map:index(mapX, mapY)] = true
        end
        if blocked then
          if map:blocksSight(mapX, mapY) then
            newStart = rightSlope
          else
            blocked = false
            start = newStart
          end
        elseif map:blocksSight(mapX, mapY) and j < radius then
          blocked = true
          castLight(map, cx, cy, j + 1, start, leftSlope, radius, xx, xy, yx, yy, visible)
          newStart = rightSlope
        end
      end
    end
    if blocked then break end
  end
end

function Fov.compute(map, originX, originY, radius)
  local visible = {}
  visible[map:index(originX, originY)] = true
  for octant = 1, 8 do
    castLight(map, originX, originY, 1, 1.0, 0.0, radius,
      mult[1][octant], mult[2][octant], mult[3][octant], mult[4][octant], visible)
  end
  return visible
end

return Fov
