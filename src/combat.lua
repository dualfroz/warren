-- Deterministic combat: damage is effective attack minus effective defense,
-- floored at 1. Effective stats fold in temporary status modifiers.

local Combat = {}

local function attackOf(entity)
  return entity.effectiveAttack and entity:effectiveAttack() or entity.attack
end

local function defenseOf(entity)
  return entity.effectiveDefense and entity:effectiveDefense() or entity.defense
end

function Combat.damage(attacker, defender)
  local dealt = attackOf(attacker) - defenseOf(defender)
  if dealt < 1 then dealt = 1 end
  return dealt
end

function Combat.attack(attacker, defender)
  local dealt = Combat.damage(attacker, defender)
  defender.hp = defender.hp - dealt
  return { damage = dealt, killed = defender.hp <= 0 }
end

return Combat
