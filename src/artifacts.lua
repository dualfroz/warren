local Items = require("items")

local Artifacts = {}

Artifacts.LIFESTEAL = "lifesteal"
Artifacts.THORNS = "thorns"
Artifacts.REGEN = "regen"
Artifacts.PIERCING = "piercing"

Artifacts.catalog = {
  {
    key = "bloodfang", slot = "weapon", name = "Bloodfang", power = 4,
    unique = Artifacts.LIFESTEAL, value = 0.5,
  },
  {
    key = "aegis_of_embers", slot = "armor", name = "Aegis of Embers", power = 2,
    unique = Artifacts.THORNS, value = 0.5,
  },
  {
    key = "ring_of_the_tide", slot = "ring", name = "Ring of the Tide", attack = 1, defense = 1,
    unique = Artifacts.REGEN, value = 2,
  },
  {
    key = "gale_bow", slot = "bow", name = "Gale Bow", power = 3, range = 6,
    unique = Artifacts.PIERCING, value = 3,
  },
  {
    key = "cinderplate", slot = "armor", name = "Cinderplate", power = 2,
    resist = { fire = "resist" },
  },
  {
    key = "frostband", slot = "ring", name = "Frostband", attack = 0, defense = 1,
    resist = { cold = "resist" },
  },

  {
    key = "warlords_cleaver", slot = "weapon", name = "the Warlord's Cleaver", power = 6,
    unique = Artifacts.LIFESTEAL, value = 0.75, bossOnly = true,
  },
  {
    key = "lich_phylactery", slot = "ring", name = "the Lich's Phylactery", attack = 1, defense = 2,
    unique = Artifacts.REGEN, value = 4, bossOnly = true,
  },
  {
    key = "bone_queen_carapace", slot = "armor", name = "the Bone Queen's Carapace", power = 4,
    unique = Artifacts.THORNS, value = 0.9, bossOnly = true,
  },
}

Artifacts.byKey = {}
Artifacts.order = {}
for _, spec in ipairs(Artifacts.catalog) do
  Artifacts.byKey[spec.key] = spec
  if not spec.bossOnly then
    Artifacts.order[#Artifacts.order + 1] = spec.key
  end
end

function Artifacts.create(key)
  local spec = Artifacts.byKey[key]
  if not spec then return nil end
  local item
  if spec.slot == "weapon" then
    item = Items.weapon(spec.name, spec.power)
  elseif spec.slot == "armor" then
    item = Items.armor(spec.name, spec.power)
  elseif spec.slot == "ring" then
    item = Items.ring(spec.name, spec.attack, spec.defense)
  elseif spec.slot == "bow" then
    item = Items.bow(spec.name, spec.power, spec.range)
  end
  item.artifact = key
  item.unique = spec.unique
  item.value = spec.value
  item.resist = spec.resist
  return item
end

function Artifacts.lifestealAmount(attacker, damage)
  local weapon = attacker.weapon
  if weapon and weapon.unique == Artifacts.LIFESTEAL then
    return math.max(1, math.floor(damage * weapon.value))
  end
  return 0
end

function Artifacts.thornsAmount(defender, damage)
  local armor = defender.armor
  if armor and armor.unique == Artifacts.THORNS then
    return math.max(1, math.floor(damage * armor.value))
  end
  return 0
end

function Artifacts.ringRegen(entity)
  local ring = entity.ring
  if ring and ring.unique == Artifacts.REGEN then return ring.value end
  return 0
end

function Artifacts.bowPierce(entity)
  local bow = entity.bow
  if bow and bow.unique == Artifacts.PIERCING then return bow.value end
  return 0
end

return Artifacts
