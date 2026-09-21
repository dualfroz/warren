local Noise = {}

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

Noise.MELEE = 6
Noise.RANGED = 6
Noise.THROW = 5
Noise.SPELL = 8
Noise.DIG = 9

function Noise.propagate(map, x, y, loudness)
  local field = {}
  if loudness <= 0 or not map:inBounds(x, y) then return field end
  local startIdx = map:index(x, y)
  field[startIdx] = loudness
  local queue = { { x = x, y = y, intensity = loudness } }
  local head = 1
  while head <= #queue do
    local cur = queue[head]
    head = head + 1
    if cur.intensity > 0 then
      local nextIntensity = cur.intensity - 1
      for _, dir in ipairs(DIRS) do
        local nx, ny = cur.x + dir[1], cur.y + dir[2]
        if map:isWalkable(nx, ny) then
          local idx = map:index(nx, ny)
          if (field[idx] or -1) < nextIntensity then
            field[idx] = nextIntensity
            queue[#queue + 1] = { x = nx, y = ny, intensity = nextIntensity }
          end
        end
      end
    end
  end
  return field
end

function Noise.intensityAt(field, map, x, y)
  if not map:inBounds(x, y) then return 0 end
  return field[map:index(x, y)] or 0
end

return Noise
