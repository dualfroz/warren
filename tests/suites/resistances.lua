local helpers = require("helpers")
local Entity = require("entity")
local Items = require("items")
local Monsters = require("monsters")
local Artifacts = require("artifacts")
local Resistances = require("resistances")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.resistancesDefaultTierPassesDamageThroughUnchanged()
  local plain = Entity.new({ x = 1, y = 1, glyph = "r", name = "rat", kind = "monster", hp = 10, maxHp = 10, attack = 2, defense = 0 })
  eq(Resistances.tierOf(plain, Resistances.FIRE), Resistances.NORMAL, "an entity with no resist table is normal to every type")
  eq(Resistances.apply(plain, 7, Resistances.FIRE), 7, "normal tier leaves the amount untouched")
  eq(Resistances.apply(plain, 0, Resistances.FIRE), 0, "zero damage stays zero regardless of tier")
end

function tests.resistancesResistHalvesAndFloors()
  local warded = Entity.new({ x = 1, y = 1, glyph = "@", name = "warded one", kind = "monster", hp = 20, maxHp = 20, attack = 2, defense = 0 })
  warded.resist = { fire = Resistances.RESIST }
  eq(Resistances.apply(warded, 9, Resistances.FIRE), 4, "resist halves and floors an odd amount")
  eq(Resistances.apply(warded, 1, Resistances.FIRE), 0, "resist can floor a small hit all the way to zero")
  eq(Resistances.apply(warded, 9, Resistances.COLD), 9, "a resist entry for one type does not bleed into another")
end

function tests.resistancesWeakAmplifies()
  local frail = Entity.new({ x = 1, y = 1, glyph = "@", name = "frail one", kind = "monster", hp = 20, maxHp = 20, attack = 2, defense = 0 })
  frail.resist = { cold = Resistances.WEAK }
  eq(Resistances.apply(frail, 4, Resistances.COLD), 6, "weak deals 1.5x, floored")
  eq(Resistances.apply(frail, 4, Resistances.FIRE), 4, "an unrelated type is unaffected by a cold weakness")
end

function tests.resistancesImmuneZeroesEvenAHugeHit()
  local warded = Entity.new({ x = 1, y = 1, glyph = "@", name = "warded one", kind = "monster", hp = 20, maxHp = 20, attack = 2, defense = 0 })
  warded.resist = { poison = Resistances.IMMUNE }
  eq(Resistances.apply(warded, 500, Resistances.POISON), 0, "immune drops even a massive hit to nothing")
end

function tests.resistancesEquipmentGrantsATierOnTopOfABaseProfile()
  local wearer = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, maxHp = 20, attack = 5, defense = 1 })
  eq(Resistances.tierOf(wearer, Resistances.COLD), Resistances.NORMAL, "an unequipped entity has no resist from thin air")
  wearer.ring = Items.ring("frost band", 0, 0)
  wearer.ring.resist = { cold = Resistances.RESIST }
  eq(Resistances.tierOf(wearer, Resistances.COLD), Resistances.RESIST, "a worn ring grants its resist tier")
  eq(Resistances.apply(wearer, 10, Resistances.COLD), 5, "the granted tier scales incoming damage of that type")
  wearer.armor = Items.armor("plate", 2)
  wearer.armor.resist = { cold = Resistances.IMMUNE }
  eq(Resistances.tierOf(wearer, Resistances.COLD), Resistances.IMMUNE, "the best tier across every equipped slot wins")
end

function tests.resistancesInnateWeaknessIsMaskedByAResistantItem()
  local dragon = Entity.new({ x = 1, y = 1, glyph = "D", name = "young dragon", kind = "monster", hp = 30, maxHp = 30, attack = 8, defense = 3 })
  dragon.resist = { cold = Resistances.WEAK }
  eq(Resistances.tierOf(dragon, Resistances.COLD), Resistances.WEAK, "the innate weakness applies with nothing worn")
  dragon.ring = Items.ring("frost band", 0, 0)
  dragon.ring.resist = { cold = Resistances.RESIST }
  eq(Resistances.tierOf(dragon, Resistances.COLD), Resistances.RESIST, "a resistant ring outranks and masks an innate weakness")
end

function tests.equippingCinderplateAndFrostbandGrantsTheirResist()
  local wearer = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, maxHp = 20, attack = 5, defense = 1 })
  Items.equipArmor(Artifacts.create("cinderplate"), wearer)
  eq(Resistances.tierOf(wearer, Resistances.FIRE), Resistances.RESIST, "cinderplate grants fire resist while worn")
  Items.equipRing(Artifacts.create("frostband"), wearer)
  eq(Resistances.tierOf(wearer, Resistances.COLD), Resistances.RESIST, "frostband grants cold resist while worn")
  eq(Resistances.tierOf(wearer, Resistances.POISON), Resistances.NORMAL, "neither artifact grants a resist it was not built for")
end

function tests.resistFieldsSurviveEntitySerialization()
  local dragon = Monsters.create(Monsters.byKey.dragon, 1, 5, 5, 6)
  local restored = Entity.fromData(dragon:toData())
  eq(Resistances.tierOf(restored, Resistances.FIRE), Resistances.IMMUNE, "a restored entity keeps its innate resist profile")
end

function tests.monstersCreateNeverAliasesTheSpeciesCatalogsInnateResistTable()
  local first = Monsters.create(Monsters.byKey.troll, 1, 5, 5, 1)
  local second = Monsters.create(Monsters.byKey.troll, 2, 6, 5, 1)
  ok(first.resist ~= Monsters.byKey.troll.resist, "an entity's resist table is its own, not the catalog's")
  first.resist.fire = Resistances.RESIST
  eq(second.resist.fire, "weak", "mutating one troll's resist never leaks onto another troll of the same species")
  eq(Monsters.byKey.troll.resist.fire, "weak", "mutating an entity's resist never corrupts the species catalog itself")
end

return tests
