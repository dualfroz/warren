local helpers = require("helpers")
local Entity = require("entity")
local Combat = require("combat")
local Items = require("items")
local Affixes = require("affixes")
local Resistances = require("resistances")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.combatResolution()
  local hero = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 2 })
  local foe = Entity.new({ x = 2, y = 1, glyph = "r", name = "rat", kind = "monster", hp = 10, attack = 3, defense = 1 })
  local first = Combat.attack(hero, foe)
  eq(first.damage, 5, "damage is attack minus defense")
  eq(foe.hp, 5, "defender hp drops by damage")
  Combat.attack(hero, foe)
  eq(foe:isAlive(), false, "dead entity reports not alive")
  local tank = Entity.new({ x = 1, y = 1, glyph = "T", name = "troll", kind = "monster", hp = 5, attack = 1, defense = 20 })
  eq(Combat.attack(foe, tank).damage, 1, "damage is floored at one against heavy armor")
end

function tests.combatDefenderResistanceHalvesTheFinalBlow()
  local attacker = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, maxHp = 20, attack = 10, defense = 1 })
  local defender = Entity.new({ x = 2, y = 1, glyph = "o", name = "orc", kind = "monster", hp = 30, maxHp = 30, attack = 4, defense = 2 })
  local baseline = Combat.damage(attacker, defender)
  defender.resist = { physical = Resistances.RESIST }
  local resisted = Combat.damage(attacker, defender)
  eq(resisted, math.floor(baseline / 2), "a physical resist halves combat.damage's own output for the same matchup")
end

function tests.combatWeaponElementOverridesPhysicalAndCanBeFullyImmune()
  local attacker = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, maxHp = 20, attack = 10, defense = 1 })
  attacker.weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[3])
  eq(attacker.weapon.damageType, "fire", "a flaming affix retags the weapon's own damage type")
  local mundane = Entity.new({ x = 2, y = 1, glyph = "o", name = "orc", kind = "monster", hp = 30, maxHp = 30, attack = 4, defense = 2 })
  ok(Combat.damage(attacker, mundane) > 0, "a flaming weapon still hurts an ordinary target")
  local salamander = Entity.new({ x = 2, y = 1, glyph = "s", name = "salamander", kind = "monster", hp = 30, maxHp = 30, attack = 4, defense = 2 })
  salamander.resist = { fire = Resistances.IMMUNE }
  eq(Combat.damage(attacker, salamander), 0, "the same flaming weapon does nothing at all against a fire-immune target")
end

return tests
