local helpers = require("helpers")
local Entity = require("entity")
local Items = require("items")
local Status = require("status")
local Game = require("game")
local Artifacts = require("artifacts")
local Curses = require("curses")
local Hunger = require("hunger")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.hungerCurrentDefaultsToCapForAFreshEntity()
  eq(Hunger.current({}), Hunger.CAP, "an entity with no satiation field reads as fully fed")
end

function tests.hungerTierOfClassifiesEachBandAtItsBoundaries()
  eq(Hunger.tierOf({ satiation = Hunger.CAP }), Hunger.FED, "a full meter is fed")
  eq(Hunger.tierOf({ satiation = Hunger.HUNGRY_MAX + 1 }), Hunger.FED, "just above the hungry ceiling is still fed")
  eq(Hunger.tierOf({ satiation = Hunger.HUNGRY_MAX }), Hunger.HUNGRY, "the hungry ceiling itself reads as hungry")
  eq(Hunger.tierOf({ satiation = Hunger.WEAK_MAX + 1 }), Hunger.HUNGRY, "just above the weak ceiling is still hungry")
  eq(Hunger.tierOf({ satiation = Hunger.WEAK_MAX }), Hunger.WEAK, "the weak ceiling itself reads as weak")
  eq(Hunger.tierOf({ satiation = 1 }), Hunger.WEAK, "one point above zero is still weak, never starving")
  eq(Hunger.tierOf({ satiation = 0 }), Hunger.STARVING, "zero itself is starving")
end

function tests.hungerAttackAndDefensePenaltiesEscalateByTier()
  eq(Hunger.attackPenalty({ satiation = Hunger.CAP }), 0, "a fed body carries no attack penalty")
  eq(Hunger.attackPenalty({ satiation = Hunger.HUNGRY_MAX }), 0, "merely hungry still carries no attack penalty")
  eq(Hunger.attackPenalty({ satiation = Hunger.WEAK_MAX }), -2, "weak costs two points of attack")
  eq(Hunger.attackPenalty({ satiation = 0 }), -4, "starving costs four points of attack")
  eq(Hunger.defensePenalty({ satiation = Hunger.CAP }), 0, "a fed body carries no defense penalty")
  eq(Hunger.defensePenalty({ satiation = Hunger.HUNGRY_MAX }), 0, "merely hungry still carries no defense penalty")
  eq(Hunger.defensePenalty({ satiation = Hunger.WEAK_MAX }), -1, "weak costs one point of defense")
  eq(Hunger.defensePenalty({ satiation = 0 }), -3, "starving costs three points of defense")
end

function tests.entityEffectiveAttackAndDefenseFoldInTheHungerPenalty()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 4 })
  eq(entity:effectiveAttack(), 6, "a fresh entity with no satiation field carries no penalty")
  entity.satiation = 0
  eq(entity:effectiveAttack(), 2, "a starving body's attack penalty is live in effectiveAttack")
  eq(entity:effectiveDefense(), 1, "a starving body's defense penalty is live in effectiveDefense")
end

function tests.hungerSuppressesRegenOnlyAtWeakOrWorse()
  ok(not Hunger.suppressesRegen({ satiation = Hunger.HUNGRY_MAX }), "merely hungry never blocks passive regen")
  ok(Hunger.suppressesRegen({ satiation = Hunger.WEAK_MAX }), "weak blocks passive regen")
  ok(Hunger.suppressesRegen({ satiation = 0 }), "starving blocks passive regen")
end

function tests.hungerTickDrainsByOneAndLogsOnlyOnATierCrossing()
  local entity = { satiation = Hunger.HUNGRY_MAX + 2, hp = 20 }
  eq(Hunger.tick(entity), nil, "a drain turn that stays within its tier reports no line")
  eq(entity.satiation, Hunger.HUNGRY_MAX + 1, "the drain was still deducted even without a tier crossing")
  eq(Hunger.tick(entity), "you feel hungry", "crossing down into hungry is announced")
  eq(entity.satiation, Hunger.HUNGRY_MAX, "the meter keeps draining turn over turn")
  eq(entity.hp, 20, "hunger alone never costs hp above starving")
end

function tests.hungerTickBitesForOneHpEveryRoundWhileStarving()
  local entity = { satiation = 1, hp = 10 }
  eq(Hunger.tick(entity), "you are starving", "crossing down into starving is announced")
  eq(entity.satiation, 0, "starving is a floor, not a negative value")
  eq(entity.hp, 9, "reaching starving costs a point of hp immediately")
  eq(Hunger.tick(entity), "you are starving", "starving keeps announcing and biting every round it holds")
  eq(entity.hp, 8, "a second starving round costs a second point of hp")
end

function tests.hungerEatCapsAtTheCeilingAndWastesAnOverfullMealIntoBloat()
  local entity = { satiation = Hunger.CAP, statuses = {} }
  local bloated = Hunger.eat(entity, 400)
  ok(bloated, "eating while already at the cap reports the meal as wasted")
  eq(entity.satiation, Hunger.CAP, "an overfull meal never lifts satiation past the cap")
  ok(Status.has(entity, Status.SLOW), "an overfull meal leaves the diner slowed")
end

function tests.hungerEatBelowTheCeilingBanksNutritionWithNoWaste()
  local entity = { satiation = Hunger.HUNGRY_MAX, statuses = {} }
  local bloated = Hunger.eat(entity, 100)
  ok(not bloated, "an ordinary meal below the cap is never wasted")
  eq(entity.satiation, Hunger.HUNGRY_MAX + 100, "the full nutrition value is banked")
  ok(not Status.has(entity, Status.SLOW), "an ordinary meal never bloats the diner")
end

function tests.hungerEatClampsAMealThatWouldOverflowPastTheCapWithoutBloating()
  local entity = { satiation = Hunger.CAP - 50, statuses = {} }
  local bloated = Hunger.eat(entity, 400)
  ok(not bloated, "a meal eaten while still short of the cap is never wasted, even if it overflows")
  eq(entity.satiation, Hunger.CAP, "the surplus past the cap is simply clamped away")
  ok(not Status.has(entity, Status.SLOW), "clamping alone never bloats the diner")
end

function tests.gameHungerTorchTickSuppressesRingRegenOnceThePlayerIsWeak()
  local game = Game.new(1)
  Items.equipRing(Artifacts.create("ring_of_the_tide"), game.player)
  game.player.hp = game.player.maxHp - 10
  game.player.satiation = Hunger.WEAK_MAX
  local before = game.player.hp
  game:hungerTorchTick()
  eq(game.player.hp, before, "a weak player's ring of the tide grants no regen this turn")
end

function tests.gameUseItemEatingFoodRestoresSatiationAndLogsTheMeal()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.satiation = 200
  game.player.inventory = { Items.food("ration", 400) }
  ok(game:useItem(1), "eating a carried ration succeeds")
  eq(game.player.satiation, 600, "the ration's full nutrition is banked")
  eq(#game.player.inventory, 0, "the eaten ration leaves the inventory")
  ok(contains(game.log:last(), "eat"), "the meal is logged")
end

function tests.gameUseItemEatingFoodWhileAlreadyFullAppliesSlowAndLogsBloat()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.satiation = Hunger.CAP
  game.player.inventory = { Items.food("ration", 400) }
  ok(game:useItem(1), "eating while already full still succeeds")
  eq(game.player.satiation, Hunger.CAP, "an overfull meal never lifts satiation past the cap")
  ok(Status.has(game.player, Status.SLOW), "eating past the cap leaves the player bloated and slow")
  ok(contains(game.log:last(), "bloated"), "the wasted meal is logged as bloating")
end

function tests.gameHungerTorchTickBleedsHpFromACursedRingEachTurn()
  local game = Game.new(1)
  game.player.ring = Curses.afflict(Items.ring("ring of power", 0, 0), Curses.pool.ring[1])
  local before = game.player.hp
  game:hungerTorchTick()
  eq(game.player.hp, before - 1, "a cursed ring's affliction bleeds its fixed drain each turn")
  ok(contains(game.log:last(), "saps"), "the drain is announced in the log")
end

return tests
