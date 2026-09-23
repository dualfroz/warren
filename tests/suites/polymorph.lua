local helpers = require("helpers")
local Rng = require("rng")
local Monsters = require("monsters")
local Polymorph = require("polymorph")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.polymorphPoolExcludesTheShopkeeperAndRespectsDepth()
  local shallow = Polymorph.pool(1)
  local shallowKeys = {}
  for _, spec in ipairs(shallow) do shallowKeys[spec.key] = true end
  ok(shallowKeys.rat and shallowKeys.bat and shallowKeys.kobold, "a depth-one pool offers every depth-one species")
  ok(not shallowKeys.orc, "a depth-one pool excludes a species that first appears deeper")

  local deep = Polymorph.pool(4)
  local deepKeys = {}
  for _, spec in ipairs(deep) do deepKeys[spec.key] = true end
  ok(deepKeys.zombie and deepKeys.necromancer, "a depth-four pool offers species that first appear at depth four")
  ok(not deepKeys.shopkeeper, "the shopkeeper is never offered by a polymorph, at any depth")
end

function tests.polymorphTransformPicksADifferentSpeciesAndPreservesTheHpFraction()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  rat.hp = 2
  local pool = Polymorph.pool(1)
  local spec = Polymorph.transform(rat, Rng.new(7), pool)
  ok(spec ~= nil, "a pool with other species on offer always yields a transform")
  ok(rat.species ~= "rat", "the entity is no longer its original species")
  eq(rat.species, spec.key, "the entity's species now matches whatever transform returned")
  eq(rat.maxHp, spec.hp, "max hp is replaced wholesale from the new species")
  local expectedHp = math.max(1, math.floor(spec.hp * 0.5 + 0.5))
  eq(rat.hp, expectedHp, "current hp is rescaled to the same fraction the old body carried")
  eq(rat.attack, spec.attack, "attack is replaced wholesale from the new species")
  eq(rat.ai, spec.ai, "ai behaviour is replaced wholesale from the new species")
end

function tests.polymorphTransformReturnsNilWhenThePoolOffersNothingButTheCurrentSpecies()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local spec = Polymorph.transform(rat, Rng.new(3), { Monsters.byKey.rat })
  ok(spec == nil, "a pool with nothing but the entity's own species transforms nothing")
  eq(rat.species, "rat", "the entity is left untouched when there is nowhere else to go")
end

return tests
