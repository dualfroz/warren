local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Status = require("status")
local Level = require("level")
local Builder = require("builder")
local Shrines = require("shrines")
local Curses = require("curses")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local function shrinePlayer(gold)
  return { gold = gold, attack = 5, baseAttack = 5, maxHp = 30, hp = 30, maxMana = 10, mana = 10,
    statuses = {} }
end

local tests = helpers.suite()

function tests.shrinePrayGrantsWarBlessingWhenFavorHolds()
  local player = shrinePlayer(50)
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.WAR, uses = 0 }
  local success, lines = Shrines.pray(game, shrine)
  eq(success, true, "a prayer with enough gold always resolves")
  eq(player.gold, 30, "the shrine's base price is deducted from the wallet")
  eq(player.attack, 6, "a war blessing raises attack")
  eq(player.baseAttack, 6, "a war blessing raises base attack permanently")
  eq(shrine.uses, 1, "a prayer advances the shrine's use count")
  ok(contains(lines[2], "favor"), "the blessing is logged")
end

function tests.shrinePrayGrantsVitalityBlessing()
  local player = shrinePlayer(50)
  player.hp = 20
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.VITALITY, uses = 0 }
  Shrines.pray(game, shrine)
  eq(player.maxHp, 35, "a vitality blessing raises max hp")
  eq(player.hp, 25, "a vitality blessing heals by the same amount as the max hp gain")
end

function tests.shrinePrayGrantsWisdomBlessing()
  local player = shrinePlayer(50)
  player.mana = 2
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.WISDOM, uses = 0 }
  Shrines.pray(game, shrine)
  eq(player.maxMana, 13, "a wisdom blessing raises max mana")
  eq(player.mana, 13, "a wisdom blessing refills mana to the new max")
end

function tests.shrinePrayGrantsFortuneBlessingAndCleansesAilments()
  local player = shrinePlayer(50)
  Status.apply(player, Status.POISON, 5, 2)
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.FORTUNE, uses = 0 }
  Shrines.pray(game, shrine)
  eq(Status.has(player, Status.POISON), false, "a fortune blessing cleanses poison")
  eq(Status.has(player, Status.SHIELD), true, "a fortune blessing also wards the petitioner")
end

function tests.shrinePrayCanCurseInsteadOfBless()
  local player = shrinePlayer(50)
  local game = { player = player, rng = Rng.new(2) }
  local shrine = { x = 1, y = 1, kind = Shrines.WAR, uses = 0 }
  local success, lines = Shrines.pray(game, shrine)
  eq(success, true, "a cursed prayer still resolves and spends its price")
  eq(player.gold, 30, "a curse still costs the shrine's price")
  eq(player.attack, 5, "a curse grants no blessing")
  eq(Status.has(player, Status.WEAKEN), true, "a curse weakens the petitioner")
  eq(Status.has(player, Status.SLOW), true, "a curse slows the petitioner")
  ok(contains(lines[2], "against you"), "the curse is logged")
end

function tests.shrinePrayFailsWithoutEnoughGold()
  local player = shrinePlayer(5)
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.WAR, uses = 0 }
  local success, lines = Shrines.pray(game, shrine)
  eq(success, false, "a prayer the player cannot afford fails outright")
  eq(player.gold, 5, "a failed prayer spends no gold")
  eq(shrine.uses, 0, "a failed prayer does not advance the use count")
  ok(contains(lines[1], "afford"), "the failure is logged")
end

function tests.shrineCostAndCurseOddsRiseWithUse()
  eq(Shrines.costFor({ uses = 0 }), 20, "an untouched shrine charges its base price")
  eq(Shrines.costFor({ uses = 3 }), 50, "the price climbs by a fixed step per prior use")
  local n0, d0 = Shrines.curseChance({ uses = 0 })
  eq(n0, 1, "an untouched shrine risks a curse on one face of the die")
  eq(d0, 6, "curse odds are read against six faces")
  local n5 = Shrines.curseChance({ uses = 10 })
  eq(n5, 6, "curse odds cap out at a certainty rather than exceeding the die")
end

function tests.shrineFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.shrines = { { x = 4, y = 4, kind = Shrines.FORTUNE, uses = 2 } }
  local restored = Level.fromData(level:toData())
  eq(#restored.shrines, 1, "the shrine list survives a round trip")
  eq(restored.shrines[1].kind, Shrines.FORTUNE, "a shrine's kind survives a round trip")
  eq(restored.shrines[1].uses, 2, "a shrine's use count survives a round trip")
end

function tests.shrinesStayOffTheShallowFloors()
  for seed = 1, 5 do
    for depth = 1, 3 do
      local level = Builder.build(depth, Rng.new(seed), {})
      eq(#level.shrines, 0, "no shrine appears above depth 4")
    end
  end
end

function tests.shrineRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  rendered.level.shrines = { { x = 5, y = 6, kind = Shrines.WAR, uses = 0 } }
  rendered:computeVisible()
  ok(contains(rendered:render(), "_"), "a shrine on a visible cell renders as its glyph")
end

function tests.shrinePrayFortuneBlessingAlsoLiftsAnyCurseCurrentlyWorn()
  local player = shrinePlayer(50)
  player.ring = Curses.afflict(Items.ring("ring of power", 0, 0), Curses.pool.ring[1])
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.FORTUNE, uses = 0 }
  local success, lines = Shrines.pray(game, shrine)
  eq(success, true, "the prayer resolves")
  eq(Curses.isCursed(player.ring), false, "fortune's blessing lifts the worn ring's curse too")
  ok(contains(lines[2], "cleanses"), "a lifted curse counts toward the cleansing message")
end

return tests
