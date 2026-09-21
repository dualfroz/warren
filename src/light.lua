local Fov = require("fov")

local Light = {}

function Light.compute(map, originX, originY, radius, lights)
  local visible = Fov.compute(map, originX, originY, radius)
  if lights then
    for _, emitter in ipairs(lights) do
      if visible[map:index(emitter.x, emitter.y)] then
        local pool = Fov.compute(map, emitter.x, emitter.y, emitter.radius)
        for idx in pairs(pool) do
          visible[idx] = true
        end
      end
    end
  end
  return visible
end

return Light
