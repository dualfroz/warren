-- Unique named gear. Unlike a rolled affix (affixes.lua), which stacks a
-- small power bump onto an ordinary base item, an artifact is a fixed,
-- always-on mechanic attached to a fixed item - lifesteal, thorns, a passive
-- regen aura, an armour-ignoring shot. Artifacts are never masked by
-- identification: identify.isConcealable only conceals potions and scrolls,
-- so a found artifact shows its real name and effect immediately.
--
-- Builder places at most one per floor from depth 5 on, its rarity roll
-- appended after every other placement (see builder.lua) so it can never
-- perturb an earlier system's rng sequence. Per-floor rng is independent
-- (dungeon.lua reseeds fresh per depth), so this is a per-floor rarity, not a
-- tracked one-per-run guarantee the way the amulet is.

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

  -- Boss-exclusive drops (bosses.lua): stronger versions of an existing
  -- unique mechanic, flagged bossOnly so the loop below keeps them out of
  -- Artifacts.order and therefore out of builder.lua's ordinary per-floor
  -- roll. The only way to obtain one is felling the boss that guarantees it.
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

-- Builds the dropped item for `key` in the same shape items.lua's own
-- constructors return for that slot, tagged with the fields the equip
-- callers below key their special-case behaviour off (`unique` and `value`).
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

-- Hp returned to `attacker` from a lifesteal weapon's hit, or 0 without one.
function Artifacts.lifestealAmount(attacker, damage)
  local weapon = attacker.weapon
  if weapon and weapon.unique == Artifacts.LIFESTEAL then
    return math.max(1, math.floor(damage * weapon.value))
  end
  return 0
end

-- Damage reflected back at whoever just landed a melee hit on `defender`, or
-- 0 without thorned armour worn.
function Artifacts.thornsAmount(defender, damage)
  local armor = defender.armor
  if armor and armor.unique == Artifacts.THORNS then
    return math.max(1, math.floor(damage * armor.value))
  end
  return 0
end

-- Hp `entity` regenerates this turn from a worn ring, or 0 without one.
function Artifacts.ringRegen(entity)
  local ring = entity.ring
  if ring and ring.unique == Artifacts.REGEN then return ring.value end
  return 0
end

-- Flat defense `entity`'s readied bow ignores on its next shot, or 0 without
-- a piercing bow.
function Artifacts.bowPierce(entity)
  local bow = entity.bow
  if bow and bow.unique == Artifacts.PIERCING then return bow.value end
  return 0
end

return Artifacts
