-- Visibility with light. The player sees out to their carried light radius via
-- shadowcasting; on top of that, any static emitter the player can already see
-- casts its own pool of light, so a lit room reveals itself the moment the
-- player glimpses its brazier. Darkness is simply a smaller player radius.

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
