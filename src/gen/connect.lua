-- Guarantees every walkable cell is reachable. Labels connected components with
-- a deterministic flood fill, then tunnels each secondary component into the
-- largest one along the shortest Manhattan link. Returns the cells of the final
-- reachable region in index order.

local Carve = require("gen.carve")

local Connect = {}

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function label(map)
  local component = {}
  local components = {}
  for y = 1, map.height do
    for x = 1, map.width do
      local idx = map:index(x, y)
      if map:isWalkable(x, y) and not component[idx] then
        local cells = {}
        local stack = { { x, y } }
        component[idx] = #components + 1
        while #stack > 0 do
          local cell = stack[#stack]
          stack[#stack] = nil
          cells[#cells + 1] = { x = cell[1], y = cell[2] }
          for _, step in ipairs(NEIGHBOURS) do
            local nx, ny = cell[1] + step[1], cell[2] + step[2]
            if map:inBounds(nx, ny) and map:isWalkable(nx, ny) then
              local nIdx = map:index(nx, ny)
              if not component[nIdx] then
                component[nIdx] = #components + 1
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
        end
        table.sort(cells, function(a, b)
          return map:index(a.x, a.y) < map:index(b.x, b.y)
        end)
        components[#components + 1] = cells
      end
    end
  end
  return components
end

local function nearestPair(from, to, map)
  local best, bx, by, tx, ty = math.huge
  for _, a in ipairs(from) do
    for _, b in ipairs(to) do
      local dist = math.abs(a.x - b.x) + math.abs(a.y - b.y)
      if dist < best then
        best, bx, by, tx, ty = dist, a.x, a.y, b.x, b.y
      end
    end
  end
  return bx, by, tx, ty
end

function Connect.ensure(map, rng)
  local components = label(map)
  if #components == 0 then return {} end
  table.sort(components, function(a, b)
    if #a ~= #b then return #a > #b end
    return map:index(a[1].x, a[1].y) < map:index(b[1].x, b[1].y)
  end)
  local main = components[1]
  for i = 2, #components do
    local ax, ay, bx, by = nearestPair(components[i], main, map)
    Carve.corridor(map, ax, ay, bx, by, rng)
  end
  local reachable = label(map)[1] or main
  table.sort(reachable, function(a, b)
    return map:index(a.x, a.y) < map:index(b.x, b.y)
  end)
  return reachable
end

return Connect
