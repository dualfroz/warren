local Monsters = require("monsters")

local Polymorph = {}

function Polymorph.pool(depth)
  local eligible = {}
  for _, spec in ipairs(Monsters.species) do
    if spec.key ~= "shopkeeper" and spec.minDepth <= depth then
      eligible[#eligible + 1] = spec
    end
  end
  return eligible
end

function Polymorph.transform(entity, rng, pool)
  local choices = {}
  for _, spec in ipairs(pool) do
    if spec.key ~= entity.species then choices[#choices + 1] = spec end
  end
  if #choices == 0 then return nil end
  local spec = choices[rng:range(1, #choices)]
  local fraction = entity.maxHp > 0 and (entity.hp / entity.maxHp) or 1
  entity.glyph = spec.glyph
  entity.name = spec.name
  entity.species = spec.key
  entity.ai = spec.ai
  entity.maxHp = spec.hp
  entity.hp = math.max(1, math.floor(spec.hp * fraction + 0.5))
  entity.attack = spec.attack
  entity.defense = spec.defense
  entity.speed = spec.speed
  entity.range = spec.range or 0
  entity.regen = spec.regen
  entity.onDeath = spec.onDeath
  entity.breath = spec.breath
  entity.ability = spec.ability
  entity.summonSpecies = spec.summonSpecies
  entity.cooldown = 0
  entity.resist = spec.resist
  entity.faction = spec.faction
  return spec
end

return Polymorph
