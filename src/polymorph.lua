-- Rewrites an entity's very body into a different bestiary species mid-run.
-- Unlike affixes.lua or runewords.lua, which layer bonuses on top of a fixed
-- body, a polymorph replaces the body outright: name, glyph, ai behaviour,
-- attack, defense, speed, resistances, faction and any ability tag all come
-- from the new species wholesale, the same fields Monsters.create stamps
-- onto a fresh spawn. Only the current hp fraction survives the swap, so a
-- polymorph is never a cheap full heal and never an outright kill either.
-- Mutation happens in place on the entity table already held everywhere
-- else (the turn scheduler, level.entities, a live nemesis reference), so
-- nothing needs to re-look-up or re-insert anything after a transform.

local Monsters = require("monsters")

local Polymorph = {}

-- Species a polymorph may land on at `depth`, in Monsters.species order so a
-- given rng draw is deterministic. Excludes the shopkeeper outright: its
-- "vend" behaviour idles forever once out of the shop context a polymorphed
-- body would never occupy, leaving it neither hostile nor useful to anyone.
function Polymorph.pool(depth)
  local eligible = {}
  for _, spec in ipairs(Monsters.species) do
    if spec.key ~= "shopkeeper" and spec.minDepth <= depth then
      eligible[#eligible + 1] = spec
    end
  end
  return eligible
end

-- Transforms `entity` in place into a random species drawn from `pool`,
-- excluding whatever species it already is so a polymorph always changes
-- something. Returns the species table it became, or nil (entity untouched)
-- if `pool` has nothing left to offer once the current species is excluded.
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
