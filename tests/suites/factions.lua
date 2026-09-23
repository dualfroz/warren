local helpers = require("helpers")
local Entity = require("entity")
local Items = require("items")
local Monsters = require("monsters")
local Game = require("game")
local Factions = require("factions")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.factionsTierBoundariesReflectReputationScore()
  eq(Factions.tier(0), "neutral", "a fresh reputation reads neutral")
  eq(Factions.tier(-10), "unfriendly", "the unfriendly ceiling is inclusive")
  eq(Factions.tier(-9), "neutral", "one point above the unfriendly ceiling is still neutral")
  eq(Factions.tier(-30), "hostile", "the hostile ceiling is inclusive")
  eq(Factions.tier(25), "friendly", "the friendly floor is inclusive")
  eq(Factions.tier(60), "honored", "the honored floor is inclusive")
end

function tests.factionsAdjustAccumulatesAndClampsToTheHundredBounds()
  local player = {}
  Factions.adjust(player, Factions.GOBLINOID, -40)
  eq(Factions.reputationFor(player, Factions.GOBLINOID), -40, "a first adjustment lands from the implicit zero baseline")
  Factions.adjust(player, Factions.GOBLINOID, -80)
  eq(Factions.reputationFor(player, Factions.GOBLINOID), -100, "reputation floors at -100")
  Factions.adjust(player, Factions.GOBLINOID, 500)
  eq(Factions.reputationFor(player, Factions.GOBLINOID), 100, "reputation caps at 100")
  eq(Factions.reputationFor(player, Factions.MERCHANT), 0, "an untouched faction still reads neutral zero")
end

function tests.factionsRegisterKillSoursOnlyTheFallensFaction()
  local player = {}
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 1, 1, 2)
  Factions.registerKill(player, goblin)
  eq(Factions.reputationFor(player, Factions.GOBLINOID), -5, "felling a goblin sours goblinoid standing")
  eq(Factions.reputationFor(player, Factions.VERMIN), 0, "an unrelated faction is left untouched")
end

function tests.factionsRegisterKillPenalizesABossFarMoreThanARegularKill()
  local player = {}
  local dragon = Monsters.create(Monsters.byKey.dragon, 1, 1, 1, 6)
  dragon.isBoss = true
  Factions.registerKill(player, dragon)
  eq(Factions.reputationFor(player, Factions.DRAKE), -15, "a boss kill costs three times a rank-and-file kill")
end

function tests.factionsRegisterKillIgnoresAFactionlessTarget()
  local player = {}
  Factions.registerKill(player, { faction = nil })
  eq(player.reputation, nil, "a factionless kill never even creates a reputation table")
end

function tests.factionsPriceMultiplierScalesFromHostileToHonored()
  local player = {}
  eq(Factions.priceMultiplier(player, Factions.MERCHANT), 1.0, "a fresh, neutral standing charges catalog price")
  Factions.adjust(player, Factions.MERCHANT, -40)
  eq(Factions.priceMultiplier(player, Factions.MERCHANT), 1.5, "a hostile guild marks its prices up")
  Factions.adjust(player, Factions.MERCHANT, 100)
  eq(Factions.priceMultiplier(player, Factions.MERCHANT), 0.65, "an honored guild discounts its prices")
end

function tests.factionsIsWaryTrueForAFreshGoblinoidAndFalseOnceProvoked()
  local player = {}
  local kobold = Monsters.create(Monsters.byKey.kobold, 1, 1, 1, 1)
  eq(Factions.isWary(player, kobold), true, "an unprovoked goblinoid starts wary of a stranger")
  kobold.provoked = true
  eq(Factions.isWary(player, kobold), false, "a provoked goblinoid is no longer wary")
end

function tests.factionsIsWaryIsFalseForNonTribalFactionsAndOnceTheTribeGoesHostile()
  local player = {}
  local rat = Monsters.create(Monsters.byKey.rat, 1, 1, 1, 1)
  eq(Factions.isWary(player, rat), false, "vermin were never a wary tribe to begin with")
  local kobold = Monsters.create(Monsters.byKey.kobold, 2, 1, 1, 1)
  Factions.adjust(player, Factions.GOBLINOID, -40)
  eq(Factions.isWary(player, kobold), false, "a tribe hated into hostility stops holding back even for a fresh member")
end

function tests.factionsAppeaseSpendsGoldAndRaisesReputationOrFailsWithoutFunds()
  local player = { gold = 10 }
  local success, cost = Factions.appease(player, Factions.GOBLINOID)
  eq(success, false, "an empty purse cannot buy any goodwill")
  eq(cost, 20, "the failure reports the base tribute cost at neutral standing")
  eq(player.gold, 10, "a failed tribute spends nothing")
  player.gold = 100
  local success2, cost2 = Factions.appease(player, Factions.GOBLINOID)
  eq(success2, true, "a well-stocked purse can pay the tribute")
  eq(cost2, 20, "the neutral tribute costs its base amount")
  eq(player.gold, 80, "the tribute's cost is deducted")
  eq(Factions.reputationFor(player, Factions.GOBLINOID), 15, "the tribute raises standing by its fixed amount")
end

function tests.factionsAppeaseCostsMoreTheDeeperTheGrudge()
  local player = { gold = 1000 }
  Factions.adjust(player, Factions.BANDIT, -30)
  local _, cost = Factions.appease(player, Factions.BANDIT)
  eq(cost, 80, "the tribute cost climbs with how negative the standing already is")
end

function tests.factionsAppeaseFailsOnceAFactionIsAlreadyMaxedOut()
  local player = { gold = 1000, reputation = { [Factions.GOBLINOID] = 100 } }
  local success, cost = Factions.appease(player, Factions.GOBLINOID)
  eq(success, false, "an already-maxed relationship has nothing left to buy")
  eq(cost, 0, "the failure reports there was no cost, not an unaffordable one")
  eq(player.gold, 1000, "nothing is spent when there is nothing to buy")
end

function tests.factionAndProvokedFieldsSurviveEntitySerialization()
  local kobold = Monsters.create(Monsters.byKey.kobold, 1, 1, 1, 1)
  kobold.provoked = true
  local restored = Entity.fromData(kobold:toData())
  eq(restored.faction, Factions.GOBLINOID, "a monster's faction tag survives a round trip")
  eq(restored.provoked, true, "a monster's provoked flag survives a round trip")
end

function tests.gameTakeMonsterTurnLeavesAWaryGoblinoidAloneUntilProvoked()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local kobold = Monsters.create(Monsters.byKey.kobold, 1, 4, 6, 1)
  game.level.entities = { kobold }
  local hpBefore = game.player.hp
  game:takeMonsterTurn(kobold)
  eq(kobold.x, 4, "an unprovoked kobold does not close in")
  eq(game.player.hp, hpBefore, "an unprovoked kobold does not attack even when adjacent")
end

function tests.gamePlayerAttackProvokesAWaryGoblinoidSoItFightsBackNextTurn()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local kobold = Monsters.create(Monsters.byKey.kobold, 1, 4, 6, 1)
  kobold.hp = 100
  game.level.entities = { kobold }
  game:playerAttack(kobold)
  eq(kobold.provoked, true, "aiming a melee attack at a wary goblinoid provokes it")
  local hpBefore = game.player.hp
  game:takeMonsterTurn(kobold)
  ok(game.player.hp < hpBefore, "a provoked, adjacent kobold now fights back")
end

function tests.gameAwardKillSoursFactionReputationWithTheFallensFaction()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp = 1
  game.level.entities = { orc }
  game:playerAttack(orc)
  eq(orc:isAlive(), false, "the orc dies to the hit")
  eq(Factions.reputationFor(game.player, Factions.ORCISH), -5, "the kill sours standing with the orc's faction")
end

function tests.stealingFromShopAlsoSoursMerchantReputation()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.level.floorItems = { { x = 4, y = 3, item = Items.scroll("identify"), price = 18, shopId = keeper.id } }
  game:stealFromShop(1)
  eq(Factions.reputationFor(game.player, Factions.MERCHANT), -20, "a theft sours the merchant guild's opinion of the player")
end

function tests.gameAppeaseFactionSpendsGoldAndLogsTheOutcome()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  game.player.gold = 100
  local success = game:appeaseFaction(Factions.GOBLINOID)
  eq(success, true, "a well-funded tribute succeeds")
  eq(game.player.gold, 80, "the tribute's cost is deducted from the wallet")
  eq(Factions.reputationFor(game.player, Factions.GOBLINOID), 15, "the tribute raises standing")
  ok(contains(game.log:last(), "goblinoid"), "the successful tribute is logged")

  game.player.gold = 0
  local failure = game:appeaseFaction(Factions.BANDIT)
  eq(failure, false, "an empty purse cannot pay any tribute")
  ok(contains(game.log:last(), "gold"), "the failed tribute explains the shortfall")
end

function tests.playerReputationSurvivesGameSaveLoadRoundTrip()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  Factions.adjust(game.player, Factions.GOBLINOID, -40)
  Factions.adjust(game.player, Factions.MERCHANT, 10)
  local restored = Game.fromData(game:toData())
  eq(Factions.reputationFor(restored.player, Factions.GOBLINOID), -40, "goblinoid standing survives a save/load round trip")
  eq(Factions.reputationFor(restored.player, Factions.MERCHANT), 10, "merchant standing survives a save/load round trip")
end

function tests.factionsAreRivalsChecksBothDirectionsAndExcludesSameFactionAndNil()
  ok(Factions.areRivals(Factions.GOBLINOID, Factions.ORCISH), "goblinoid and orcish are a listed rivalry")
  ok(Factions.areRivals(Factions.ORCISH, Factions.GOBLINOID), "the rivalry check reads either direction")
  ok(not Factions.areRivals(Factions.GOBLINOID, Factions.GOBLINOID), "a faction is never its own rival")
  ok(not Factions.areRivals(Factions.MERCHANT, Factions.DRAKE), "an unlisted pair is not a rivalry")
  ok(not Factions.areRivals(nil, Factions.ORCISH), "a nil faction on either side never counts as a rival")
  ok(not Factions.areRivals(Factions.GOBLINOID, nil), "a nil faction on either side never counts as a rival")
end

return tests
