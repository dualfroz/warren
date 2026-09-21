local Tiles = require("tiles")
local Resistances = require("resistances")

local Conductivity = {}

Conductivity.SOAK_DURATION = 3
Conductivity.LIGHTNING_BONUS_PERCENT = 50
Conductivity.FIRE_DAMPEN_PERCENT = 50

function Conductivity.isWet(entity)
  return (entity.wet or 0) > 0
end

function Conductivity.tick(level, entity)
  if level.map:get(entity.x, entity.y) == Tiles.WATER then
    entity.wet = Conductivity.SOAK_DURATION
  elseif (entity.wet or 0) > 0 then
    entity.wet = entity.wet - 1
  end
end

function Conductivity.applyFire(entity, amount)
  local dealt = Resistances.apply(entity, amount, Resistances.FIRE)
  if dealt > 0 and Conductivity.isWet(entity) then
    dealt = math.max(1, dealt - (dealt * Conductivity.FIRE_DAMPEN_PERCENT) // 100)
  end
  return dealt
end

function Conductivity.applyLightning(entity, amount)
  local dealt = Resistances.apply(entity, amount, Resistances.LIGHTNING)
  if dealt > 0 and Conductivity.isWet(entity) then
    dealt = dealt + (dealt * Conductivity.LIGHTNING_BONUS_PERCENT) // 100
  end
  return dealt
end

function Conductivity.resistsIgnition(entity)
  return Conductivity.isWet(entity)
end

return Conductivity
