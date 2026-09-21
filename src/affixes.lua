local Affixes = {}

Affixes.weapon = {
  { key = "sharp",   name = "sharp",   power = 1 },
  { key = "vicious", name = "vicious", power = 2 },
  { key = "flaming", name = "flaming", power = 1, onHit = { status = "burning", duration = 3, potency = 2 }, damageType = "fire" },
  { key = "venomed", name = "venomed", power = 0, onHit = { status = "poison",  duration = 4, potency = 1 }, damageType = "poison" },
}

Affixes.armor = {
  { key = "sturdy",     name = "sturdy",     power = 1 },
  { key = "reinforced", name = "reinforced", power = 2 },
}

local function roll(pool, rng, chanceNumerator, chanceDenominator)
  if not rng:chance(chanceNumerator, chanceDenominator) then return nil end
  return pool[rng:range(1, #pool)]
end

function Affixes.rollWeapon(rng)
  return roll(Affixes.weapon, rng, 1, 2)
end

function Affixes.rollArmor(rng)
  return roll(Affixes.armor, rng, 1, 3)
end

function Affixes.decorate(item, affix)
  if not affix then return item end
  item.affix = { key = affix.key, name = affix.name, power = affix.power, onHit = affix.onHit, damageType = affix.damageType }
  item.power = item.power + affix.power
  item.name = affix.name .. " " .. item.name
  item.damageType = affix.damageType
  return item
end

return Affixes
