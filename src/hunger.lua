local Status = require("status")

local Hunger = {}

Hunger.FED = "fed"
Hunger.HUNGRY = "hungry"
Hunger.WEAK = "weak"
Hunger.STARVING = "starving"

Hunger.START = 1000
Hunger.CAP = 1200

Hunger.HUNGRY_MAX = 300
Hunger.WEAK_MAX = 100

Hunger.BLOAT_DURATION = 4

local ATTACK_PENALTY = {
  [Hunger.FED] = 0, [Hunger.HUNGRY] = 0, [Hunger.WEAK] = -2, [Hunger.STARVING] = -4,
}
local DEFENSE_PENALTY = {
  [Hunger.FED] = 0, [Hunger.HUNGRY] = 0, [Hunger.WEAK] = -1, [Hunger.STARVING] = -3,
}

function Hunger.current(entity)
  return entity.satiation or Hunger.CAP
end

function Hunger.tierOf(entity)
  local value = Hunger.current(entity)
  if value <= 0 then return Hunger.STARVING end
  if value <= Hunger.WEAK_MAX then return Hunger.WEAK end
  if value <= Hunger.HUNGRY_MAX then return Hunger.HUNGRY end
  return Hunger.FED
end

function Hunger.attackPenalty(entity)
  return ATTACK_PENALTY[Hunger.tierOf(entity)]
end

function Hunger.defensePenalty(entity)
  return DEFENSE_PENALTY[Hunger.tierOf(entity)]
end

function Hunger.suppressesRegen(entity)
  local tier = Hunger.tierOf(entity)
  return tier == Hunger.WEAK or tier == Hunger.STARVING
end

function Hunger.tick(entity)
  local before = Hunger.tierOf(entity)
  entity.satiation = math.max(0, Hunger.current(entity) - 1)
  local after = Hunger.tierOf(entity)
  if after == Hunger.STARVING then
    entity.hp = entity.hp - 1
    return "you are starving"
  end
  if after ~= before then
    return "you feel " .. after
  end
  return nil
end

function Hunger.eat(entity, nutrition)
  local wasFull = Hunger.current(entity) >= Hunger.CAP
  entity.satiation = math.min(Hunger.CAP, Hunger.current(entity) + nutrition)
  if wasFull then
    Status.apply(entity, Status.SLOW, Hunger.BLOAT_DURATION, 1)
  end
  return wasFull
end

return Hunger
