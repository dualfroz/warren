-- Deterministic combat: damage is effective attack minus effective defense,
-- floored at 1. Effective stats fold in temporary status modifiers, plus
-- conditional skill bonuses (berserk/mana shield - see skills.lua, a no-op
-- for any entity without a `skills` table, i.e. monsters) and any completed
-- runeword on the wielder's own weapon/armor (see runewords.lua, a no-op for
-- any item without a matching rune chain), plus any item-set threshold the
-- wielder's current gear happens to meet (see sets.lua, a no-op below its
-- lowest 2-piece threshold).
-- The attack-minus-defense minimum-1 floor happens before elemental
-- resistance (resistances.lua) gets a say, so a defender immune to the
-- attack's damage type can still shrug off a hit that combat itself
-- guaranteed would land.

local Skills = require("skills")
local Resistances = require("resistances")
local Runewords = require("runewords")
local Sets = require("sets")

local Combat = {}

local function attackOf(entity)
  local base = entity.effectiveAttack and entity:effectiveAttack() or entity.attack
  return base + Skills.attackBonus(entity) + Runewords.attackBonus(entity) + Sets.attackBonus(entity)
end

local function defenseOf(entity)
  local base = entity.effectiveDefense and entity:effectiveDefense() or entity.defense
  return base + Skills.defenseBonus(entity) + Runewords.defenseBonus(entity) + Sets.defenseBonus(entity)
end

-- The type of an attacker's raw damage: a weapon retagged by an elemental
-- affix (flaming/venomed - see affixes.lua) fights with that element instead
-- of a bare fist or claw's plain physical.
local function damageTypeOf(attacker)
  return (attacker.weapon and attacker.weapon.damageType) or Resistances.PHYSICAL
end

-- `multiplier` scales the raw attack-minus-defense difference before the
-- floor-at-1 minimum is applied, so a backstab still guarantees at least 1
-- rather than 2x-ing an already-clamped hit. `damageType` defaults to the
-- attacker's own weapon typing when omitted.
function Combat.damage(attacker, defender, multiplier, damageType)
  local dealt = (attackOf(attacker) - defenseOf(defender)) * (multiplier or 1)
  if dealt < 1 then dealt = 1 end
  dealt = math.floor(dealt)
  return Resistances.apply(defender, dealt, damageType or damageTypeOf(attacker))
end

function Combat.attack(attacker, defender, multiplier, damageType)
  local dealt = Combat.damage(attacker, defender, multiplier, damageType)
  defender.hp = defender.hp - dealt
  return { damage = dealt, killed = defender.hp <= 0 }
end

return Combat
