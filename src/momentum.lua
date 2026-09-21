local Momentum = {}

Momentum.MAX_STACKS = 5
Momentum.BONUS_PER_STACK = 1

function Momentum.stacks(entity)
  return entity.combo or 0
end

function Momentum.onMeleeHit(entity)
  entity.combo = math.min(Momentum.MAX_STACKS, Momentum.stacks(entity) + 1)
end

function Momentum.onDamaged(entity)
  entity.combo = 0
end

function Momentum.attackBonus(entity)
  return Momentum.stacks(entity) * Momentum.BONUS_PER_STACK
end

return Momentum
