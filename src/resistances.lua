-- Elemental damage typing. Every hit that lands - melee, a bolt, a thrown
-- weapon, a hazard tick, a status effect's damage-over-time - is tagged with
-- one of the types below, and this module decides how much of it actually
-- gets through. A defender's tier for a type comes from up to two places: its
-- own base profile (bestiary data, e.g. a dragon's own hide) and whatever it
-- has equipped (weapon/armor/ring/bow, e.g. a ring of cold resistance). The
-- single best (most protective) tier across those sources wins - immune beats
-- resist beats weak beats the normal default - so a found ring can cancel out
-- an innate vulnerability, but nothing ever stacks two resists into a second
-- discount or two weaknesses into a bigger penalty.

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

-- Slots checked alongside an entity's own `resist` table, in a fixed order so
-- the result never depends on Lua's unspecified pairs() iteration order.
local EQUIP_SLOTS = { "weapon", "armor", "ring", "bow" }

local function tierFrom(source, damageType)
  return source and source.resist and source.resist[damageType]
end

-- The single tier that governs `damageType` incoming against `entity`, folding
-- in its own base profile and every equipped slot that carries one.
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

-- Scales a already-computed `amount` of `damageType` damage by `entity`'s
-- tier for that type. Immune drops it to nothing outright rather than merely
-- halving it, so it can floor damage below the "always at least 1" guarantee
-- combat.lua's own minimum otherwise enforces.
function Resistances.apply(entity, amount, damageType)
  if amount <= 0 then return amount end
  local tier = Resistances.tierOf(entity, damageType or Resistances.PHYSICAL)
  if tier == Resistances.IMMUNE then return 0 end
  if tier == Resistances.RESIST then return math.floor(amount / 2) end
  if tier == Resistances.WEAK then return math.floor(amount * 1.5) end
  return amount
end

return Resistances
