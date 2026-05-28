-- Data-driven bestiary. Each species is a plain table describing stats, the AI
-- behaviour tag that governs its turn, how fast it acts, and the shallowest depth
-- it appears at. The factory stamps a species into an Entity, scaling hp with
-- depth so lower floors bite harder.

local Entity = require("entity")

local Monsters = {}

Monsters.species = {
  { key = "rat",     glyph = "r", name = "rat",            hp = 4,  attack = 2, defense = 0, speed = 110, ai = "chase",   minDepth = 1 },
  { key = "bat",     glyph = "v", name = "cave bat",       hp = 3,  attack = 2, defense = 0, speed = 150, ai = "erratic", minDepth = 1 },
  { key = "kobold",  glyph = "k", name = "kobold",         hp = 6,  attack = 3, defense = 1, speed = 100, ai = "pack",    minDepth = 1 },
  { key = "goblin",  glyph = "g", name = "goblin",         hp = 5,  attack = 3, defense = 0, speed = 110, ai = "pack",    minDepth = 2 },
  { key = "archer",  glyph = "a", name = "skeleton archer", hp = 6, attack = 3, defense = 1, speed = 100, ai = "ranged",  minDepth = 2, range = 5 },
  { key = "orc",     glyph = "o", name = "orc",            hp = 10, attack = 4, defense = 1, speed = 100, ai = "chase",   minDepth = 3 },
  { key = "wretch",  glyph = "w", name = "cave wretch",    hp = 8,  attack = 2, defense = 0, speed = 120, ai = "flee",    minDepth = 3 },
  { key = "troll",   glyph = "T", name = "troll",          hp = 16, attack = 6, defense = 2, speed = 80,  ai = "chase",   minDepth = 4 },
  { key = "mage",    glyph = "m", name = "dark mage",      hp = 8,  attack = 2, defense = 0, speed = 100, ai = "ranged",  minDepth = 5, range = 6 },
  { key = "dragon",  glyph = "D", name = "young dragon",   hp = 30, attack = 8, defense = 3, speed = 90,  ai = "ranged",  minDepth = 6, range = 4 },
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

function Monsters.create(spec, id, x, y, depth)
  local bonusHp = depth - 1
  return Entity.new({
    id = id,
    x = x, y = y,
    glyph = spec.glyph, name = spec.name, kind = "monster",
    species = spec.key, ai = spec.ai,
    hp = spec.hp + bonusHp, maxHp = spec.hp + bonusHp,
    attack = spec.attack, defense = spec.defense,
    speed = spec.speed, range = spec.range or 0,
  })
end

return Monsters
