-- Elemental terrain interaction between open water and the fire/lightning
-- damage types resistances.lua already defines. Stepping into water leaves an
-- entity soaked for a few turns after it moves on, not just on the exact
-- water tile - the lingering dampness other systems read through Conductivity
-- rather than re-checking the tile underfoot themselves. A soaked entity
-- resists catching fire outright (Status.apply refuses a BURNING application,
-- the same way a water tile already douses tile fire in Hazards.step) and,
-- for damage that already lands, dampens further fire (Conductivity.applyFire,
-- used by hazards.lua's fire tick and status.lua's own BURNING dot) while
-- conducting lightning for a bonus (Conductivity.applyLightning, used by
-- spells.lua's shock bolt) - the water clinging to them is exactly what makes
-- a live wire so much worse to be standing in. This is scoped to fire/
-- lightning that already routes through here; an instantaneous hit like
-- lava contact or a breath attack that computes its own damage inline is
-- left alone - only ignition-prevention (resistsIgnition) reaches those.
--
-- LIGHTNING was previously a fully declared Resistances type with nothing in
-- the game that ever dealt it - elites could roll a resist tier for a damage
-- type nothing ever used. Conductivity.applyLightning plus spells.lua's new
-- shock bolt spell are what makes an elite's rolled lightning resistance
-- (see elites.lua) matter for the first time.

local Tiles = require("tiles")
local Resistances = require("resistances")

local Conductivity = {}

Conductivity.SOAK_DURATION = 3
Conductivity.LIGHTNING_BONUS_PERCENT = 50
Conductivity.FIRE_DAMPEN_PERCENT = 50

function Conductivity.isWet(entity)
  return (entity.wet or 0) > 0
end

-- Refreshes `entity`'s soak counter to the full duration when it ends its
-- turn standing on open water, or counts it down by one otherwise - the same
-- "renew on cause, decay on absence" shape a stacked status.lua effect's own
-- duration follows, but tracked as a plain entity field since it is a terrain
-- reaction rather than something any status.lua effect key describes.
function Conductivity.tick(level, entity)
  if level.map:get(entity.x, entity.y) == Tiles.WATER then
    entity.wet = Conductivity.SOAK_DURATION
  elseif (entity.wet or 0) > 0 then
    entity.wet = entity.wet - 1
  end
end

-- Fire damage against a soaked target is dampened on top of whatever
-- Resistances.tierOf already resolves - drenched cloth or hide smoulders
-- rather than catching properly. Immune still floors it at zero.
function Conductivity.applyFire(entity, amount)
  local dealt = Resistances.apply(entity, amount, Resistances.FIRE)
  if dealt > 0 and Conductivity.isWet(entity) then
    dealt = math.max(1, dealt - (dealt * Conductivity.FIRE_DAMPEN_PERCENT) // 100)
  end
  return dealt
end

-- Lightning damage against a soaked target conducts through the water
-- clinging to them for a bonus on top of whatever Resistances.tierOf already
-- resolves - immune still blocks it outright, same as any other type.
function Conductivity.applyLightning(entity, amount)
  local dealt = Resistances.apply(entity, amount, Resistances.LIGHTNING)
  if dealt > 0 and Conductivity.isWet(entity) then
    dealt = dealt + (dealt * Conductivity.LIGHTNING_BONUS_PERCENT) // 100
  end
  return dealt
end

-- A soaked target's own dampness snuffs any attempt to set them alight
-- outright, before the BURNING effect is ever recorded (see status.lua's
-- Status.apply) - the same protection a water tile already gives tile fire
-- in Hazards.step, extended to an entity that carries its own wetness onto
-- dry ground.
function Conductivity.resistsIgnition(entity)
  return Conductivity.isWet(entity)
end

return Conductivity
