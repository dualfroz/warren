local Resistances = {}

Resistances.PHYSICAL = "physical"
Resistances.FIRE = "fire"
Resistances.COLD = "cold"
Resistances.POISON = "poison"
Resistances.LIGHTNING = "lightning"
Resistances.ARCANE = "arcane"

Resistances.TYPES = {
  Resistances.PHYSICAL, Resistances.FIRE, Resistances.COLD,
  Resistances.POISON, Resistances.LIGHTNING, Resistances.ARCANE,
}

Resistances.IMMUNE = "immune"
Resistances.RESIST = "resist"
Resistances.WEAK = "weak"
Resistances.NORMAL = "normal"

local RANK = { immune = 3, resist = 2, weak = 1, normal = 0 }

local EQUIP_SLOTS = { "weapon", "armor", "ring", "bow" }

local function tierFrom(source, damageType)
  return source and source.resist and source.resist[damageType]
end

function Resistances.tierOf(entity, damageType)
  local best = tierFrom(entity, damageType) or Resistances.NORMAL
  for _, slot in ipairs(EQUIP_SLOTS) do
    local tier = tierFrom(entity[slot], damageType)
    if tier and RANK[tier] > RANK[best] then
      best = tier
    end
  end
  return best
end

function Resistances.apply(entity, amount, damageType)
  if amount <= 0 then return amount end
  local tier = Resistances.tierOf(entity, damageType or Resistances.PHYSICAL)
  if tier == Resistances.IMMUNE then return 0 end
  if tier == Resistances.RESIST then return math.floor(amount / 2) end
  if tier == Resistances.WEAK then return math.floor(amount * 1.5) end
  return amount
end

return Resistances
