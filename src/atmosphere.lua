local Atmosphere = {}

Atmosphere.FOGGY = "foggy"
Atmosphere.CONSECRATED = "consecrated"
Atmosphere.INFESTED = "infested"

Atmosphere.order = { Atmosphere.FOGGY, Atmosphere.CONSECRATED, Atmosphere.INFESTED }

function Atmosphere.sightPenalty(weather)
  if weather == Atmosphere.FOGGY then return 2 end
  return 0
end

function Atmosphere.regenBonus(weather)
  if weather == Atmosphere.CONSECRATED then return 1 end
  return 0
end

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
