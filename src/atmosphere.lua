-- Floor-wide weather: a single condition drawn once at generation (like
-- `dark`) that colors the whole level rather than one cell of it. Unlike
-- terrain.lua's per-tile hazards (lava, chasm, ice), a floor's weather has no
-- position of its own - every numeric hook below is a flat, floor-lifetime
-- modifier the caller applies once per turn or once at generation, never
-- something a player can step in or out of.

local Atmosphere = {}

Atmosphere.FOGGY = "foggy"
Atmosphere.CONSECRATED = "consecrated"
Atmosphere.INFESTED = "infested"

-- Fixed order so a given rng draw always names the same condition.
Atmosphere.order = { Atmosphere.FOGGY, Atmosphere.CONSECRATED, Atmosphere.INFESTED }

-- A thick, clinging fog: everyone's sight radius shrinks, monsters and traps
-- included, before the darkness/torch radius in Game:effectiveRadius is
-- even considered.
function Atmosphere.sightPenalty(weather)
  if weather == Atmosphere.FOGGY then return 2 end
  return 0
end

-- Consecrated ground mends the living each turn they linger on it, exactly
-- like an artifact's fixed regen (see artifacts.ringRegen) but floor-wide
-- and free of any equipment.
function Atmosphere.regenBonus(weather)
  if weather == Atmosphere.CONSECRATED then return 1 end
  return 0
end

-- An infested floor's monsters hit harder from the moment they are placed -
-- a flat, permanent bump baked into their stats at generation time (see
-- builder.lua), the same way an elite affix or a boss's own catalog entry
-- already sets a monster's power once and for all.
function Atmosphere.monsterAttackBonus(weather)
  if weather == Atmosphere.INFESTED then return 2 end
  return 0
end

function Atmosphere.describe(weather)
  if weather == Atmosphere.FOGGY then return "a thick fog blankets this floor" end
  if weather == Atmosphere.CONSECRATED then return "this floor is consecrated ground" end
  if weather == Atmosphere.INFESTED then return "this floor teems with infestation" end
  return nil
end

return Atmosphere
