local Proficiency = {}

Proficiency.UNARMED = "fists"

Proficiency.RANKS = {
  { hits = 15,  bonus = 1 },
  { hits = 40,  bonus = 2 },
  { hits = 80,  bonus = 3 },
  { hits = 150, bonus = 4 },
}

function Proficiency.keyFor(entity)
  return entity.weapon and entity.weapon.name or Proficiency.UNARMED
end

function Proficiency.hits(entity, key)
  return (entity.proficiency and entity.proficiency[key]) or 0
end

function Proficiency.onHitWith(entity, key)
  entity.proficiency = entity.proficiency or {}
  local before = entity.proficiency[key] or 0
  local after = before + 1
  entity.proficiency[key] = after
  for _, rank in ipairs(Proficiency.RANKS) do
    if before < rank.hits and after >= rank.hits then
      return key, rank.bonus
    end
  end
  return nil
end

function Proficiency.bonusFor(entity, key)
  local hits = Proficiency.hits(entity, key)
  local bonus = 0
  for _, rank in ipairs(Proficiency.RANKS) do
    if hits >= rank.hits then bonus = rank.bonus end
  end
  return bonus
end

function Proficiency.onMeleeHit(entity)
  return Proficiency.onHitWith(entity, Proficiency.keyFor(entity))
end

function Proficiency.attackBonus(entity)
  return Proficiency.bonusFor(entity, Proficiency.keyFor(entity))
end

return Proficiency
