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

local function damageTypeOf(attacker)
  return (attacker.weapon and attacker.weapon.damageType) or Resistances.PHYSICAL
end

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
