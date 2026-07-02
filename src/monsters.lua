-- Data-driven bestiary. Each species is a plain table describing stats, the AI
-- behaviour tag that governs its turn, how fast it acts, and the shallowest depth
-- it appears at. The factory stamps a species into an Entity, scaling hp with
-- depth so lower floors bite harder.

local Entity = require("entity")
local Factions = require("factions")
local Disease = require("disease")

local Monsters = {}

Monsters.species = {
  { key = "rat",     glyph = "r", name = "rat",            hp = 4,  attack = 2, defense = 0, speed = 110, ai = "chase",   minDepth = 1, xp = 3, faction = Factions.VERMIN, disease = Disease.PARASITES },
  { key = "bat",     glyph = "v", name = "cave bat",       hp = 3,  attack = 2, defense = 0, speed = 150, ai = "erratic", minDepth = 1, xp = 3, faction = Factions.VERMIN },
  { key = "kobold",  glyph = "k", name = "kobold",         hp = 6,  attack = 3, defense = 1, speed = 100, ai = "pack",    minDepth = 1, xp = 5, faction = Factions.GOBLINOID, disease = Disease.PLAGUE },
  { key = "goblin",  glyph = "g", name = "goblin",         hp = 5,  attack = 3, defense = 0, speed = 110, ai = "pack",    minDepth = 2, xp = 5, faction = Factions.GOBLINOID },
  { key = "archer",  glyph = "a", name = "skeleton archer", hp = 6, attack = 3, defense = 1, speed = 100, ai = "ranged",  minDepth = 2, range = 5, xp = 6, faction = Factions.UNDEAD },
  { key = "orc",     glyph = "o", name = "orc",            hp = 10, attack = 4, defense = 1, speed = 100, ai = "chase",   minDepth = 3, xp = 9, faction = Factions.ORCISH },
  { key = "wretch",  glyph = "w", name = "cave wretch",    hp = 8,  attack = 2, defense = 0, speed = 120, ai = "flee",    minDepth = 3, xp = 6, onDeath = "spores", faction = Factions.BEAST },
  { key = "troll",   glyph = "T", name = "troll",          hp = 16, attack = 6, defense = 2, speed = 80,  ai = "chase",   minDepth = 4, xp = 15, regen = 3, resist = { fire = "weak" }, faction = Factions.BEAST },
  { key = "mage",    glyph = "m", name = "dark mage",      hp = 8,  attack = 2, defense = 0, speed = 100, ai = "ranged",  minDepth = 5, range = 6, xp = 12, faction = Factions.CULT },
  { key = "dragon",  glyph = "D", name = "young dragon",   hp = 30, attack = 8, defense = 3, speed = 90,  ai = "ranged",  minDepth = 6, range = 4, xp = 25, breath = "fire", resist = { fire = "immune", cold = "weak" }, faction = Factions.DRAKE },

  -- Ability bearers: each carries an `ability` tag resolved by abilities.lua's
  -- tryAct dispatch, which runs before the plain ai.lua behaviour listed here
  -- and only falls through to it when the ability is on cooldown or has no
  -- valid target. minDepth is kept at 4+ so these never appear on the shallow
  -- floors exercised by the fixed-maxDepth win-condition tests.
  { key = "zombie",     glyph = "z", name = "shambling zombie", hp = 7,  attack = 3, defense = 1, speed = 90,  ai = "chase", minDepth = 4, xp = 5, faction = Factions.UNDEAD, disease = Disease.ROT },
  { key = "slime",      glyph = "j", name = "gelatinous slime", hp = 10, attack = 2, defense = 0, speed = 90,  ai = "chase", minDepth = 4, xp = 5, ability = "split", faction = Factions.BEAST },
  { key = "footpad",    glyph = "f", name = "footpad",          hp = 6,  attack = 2, defense = 0, speed = 120, ai = "chase", minDepth = 4, xp = 6, ability = "steal", faction = Factions.BANDIT },
  { key = "shaman",     glyph = "s", name = "goblin shaman",    hp = 7,  attack = 2, defense = 0, speed = 100, ai = "flee",  minDepth = 4, xp = 9, ability = "curse", faction = Factions.GOBLINOID },
  { key = "necromancer", glyph = "n", name = "necromancer",     hp = 9,  attack = 2, defense = 0, speed = 95,  ai = "flee",  minDepth = 4, xp = 10, ability = "summon", summonSpecies = "zombie", faction = Factions.CULT },
  { key = "cleric",     glyph = "c", name = "dark cleric",      hp = 8,  attack = 2, defense = 1, speed = 100, ai = "pack",  minDepth = 5, xp = 9, ability = "heal", faction = Factions.CULT },
  { key = "chieftain",  glyph = "C", name = "orc chieftain",    hp = 14, attack = 5, defense = 2, speed = 100, ai = "pack",  minDepth = 6, xp = 14, ability = "rally", faction = Factions.GOBLINOID },
  { key = "banshee",    glyph = "b", name = "banshee",          hp = 7,  attack = 2, defense = 0, speed = 100, ai = "flee",  minDepth = 5, xp = 11, ability = "shriek", faction = Factions.UNDEAD },

  -- Shopkeeper: a passive vendor guarding priced wares (see shop.lua). Its
  -- "vend" behaviour idles until game.lua flags it hostile after a theft, at
  -- which point it falls back to a plain chase like any other monster.
  { key = "shopkeeper", glyph = "h", name = "shopkeeper", hp = 8, attack = 3, defense = 1, speed = 100, ai = "vend", minDepth = 4, xp = 7, faction = Factions.MERCHANT },
}

Monsters.byKey = {}
for _, spec in ipairs(Monsters.species) do
  Monsters.byKey[spec.key] = spec
end

-- Species eligible at a depth, in registry order so callers pick deterministically.
function Monsters.forDepth(depth)
  local eligible = {}
  for _, spec in ipairs(Monsters.species) do
    if spec.minDepth <= depth then
      eligible[#eligible + 1] = spec
    end
  end
  return eligible
end

-- Xp reward for felling an entity, looked up by the species key stamped onto
-- it at creation. Falls back to a flat amount for anything without one.
function Monsters.xpFor(entity)
  local spec = Monsters.byKey[entity.species]
  return spec and spec.xp or 4
end

-- A fresh copy of a species' innate resist table, never the catalog's own
-- object: elites.lua's "warded" affix mutates entity.resist in place once
-- rolled, and a shared reference there would leak that bump onto every
-- other spawn of the same species for the rest of the process, not just
-- the one entity actually promoted.
local function copyResist(resist)
  if not resist then return nil end
  local copy = {}
  for damageType, tier in pairs(resist) do copy[damageType] = tier end
  return copy
end

function Monsters.create(spec, id, x, y, depth)
  local bonusHp = depth - 1
  local entity = Entity.new({
    id = id,
    x = x, y = y,
    glyph = spec.glyph, name = spec.name, kind = "monster",
    species = spec.key, ai = spec.ai,
    hp = spec.hp + bonusHp, maxHp = spec.hp + bonusHp,
    attack = spec.attack, defense = spec.defense,
    speed = spec.speed, range = spec.range or 0,
  })
  entity.regen = spec.regen
  entity.onDeath = spec.onDeath
  entity.breath = spec.breath
  entity.ability = spec.ability
  entity.summonSpecies = spec.summonSpecies
  entity.cooldown = 0
  entity.resist = copyResist(spec.resist)
  entity.faction = spec.faction
  entity.biteDisease = spec.disease
  return entity
end

return Monsters
