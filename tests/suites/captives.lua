local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Items = require("items")
local Monsters = require("monsters")
local Level = require("level")
local Builder = require("builder")
local Elites = require("elites")
local Factions = require("factions")
local Captives = require("captives")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.captivesEligibleAcceptsABatteredWildHostileAndRejectsATooHealthyOne()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  rat.hp = 1
  ok(Captives.eligible(rat), "a wild hostile battered down to a sliver of hp is eligible for a net")
  rat.hp = rat.maxHp
  ok(not Captives.eligible(rat), "a target still at full health is too fierce to net")
end

function tests.captivesEligibleExcludesBossesMimicsGravesNemesesAndTheVendingShopkeeper()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 3)
  orc.hp = 1
  orc.isBoss = true
  ok(not Captives.eligible(orc), "a boss is excluded from netting even when battered")
  orc.isBoss = false
  orc.mimic = true
  ok(not Captives.eligible(orc), "a mimic is excluded from netting even when battered")
  orc.mimic = false
  orc.grave = true
  ok(not Captives.eligible(orc), "a grave shade is excluded from netting even when battered")
  orc.grave = false
  orc.nemesis = true
  ok(not Captives.eligible(orc), "a nemesis is excluded from netting even when battered")
  orc.nemesis = false
  ok(Captives.eligible(orc), "the same battered orc becomes eligible again once none of the exclusions apply")
  local shopkeeper = Monsters.create(Monsters.byKey.shopkeeper, 2, 6, 6, 4)
  shopkeeper.hp = 1
  ok(not Captives.eligible(shopkeeper), "the vending shopkeeper is never eligible for a net even when battered")
end

function tests.captivesCanReachRespectsRangeAndLineOfSight()
  local level = arena(21, 11)
  ok(Captives.canReach(level.map, 3, 6, 3 + Captives.RANGE, 6), "a target at exactly max range with a clear line is reachable")
  ok(not Captives.canReach(level.map, 3, 6, 3 + Captives.RANGE + 1, 6), "a target one cell beyond max range is unreachable")
  level.map:set(5, 6, Tiles.WALL)
  ok(not Captives.canReach(level.map, 3, 6, 7, 6), "a wall blocking the line of sight makes an in-range target unreachable")
end

function tests.captivesValueOfMatchesKillXpAndAddsAnEliteBonus()
  local orc = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 3)
  eq(Captives.valueOf(orc), Monsters.xpFor(orc), "a plain monster's capture value equals its kill xp")
  orc.elite = true
  orc.eliteTier = "champion"
  local baseXp = Monsters.xpFor(orc)
  eq(Captives.valueOf(orc), baseXp + Elites.xpBonus(orc, baseXp),
    "an elite's capture value adds the same bonus a kill's xp would")
  ok(Captives.valueOf(orc) > baseXp, "the elite bonus actually raises the capture value above the plain kill xp")
end

function tests.captivesResolveRefusesWithNoClearThrowWithoutSpendingTheNet()
  local game = stagedGame(4, arena(21, 11), 2, 2)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 19, 9, 1)
  rat.hp = 1
  game.level.entities = { rat }
  local net = Items.net()
  local success, lines = Captives.resolve(game, game.player, net, rat)
  eq(success, false, "a net thrown beyond range never leaves the hand")
  ok(contains(lines[1], "clear throw"), "the reason given is the lack of a clear throw")
end

function tests.captivesResolveWastesTheNetOnATargetStillTooHealthyToSubdue()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  local net = Items.net()
  local success, lines = Captives.resolve(game, game.player, net, rat)
  eq(success, true, "a net thrown at a still-healthy target still leaves the hand")
  eq(#game.level.captives, 0, "no captive is created from a target too healthy to subdue")
  eq(rat.hp, rat.maxHp, "the target takes no damage from a wasted net")
  ok(contains(lines[1], "fierce"), "the log explains the target was too fierce to net")
end

function tests.captivesResolveCanThrashFreeAndStillSpendTheNet()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.rng = Rng.new(1)
  local net = Items.net()
  local success, lines = Captives.resolve(game, game.player, net, rat)
  eq(success, true, "a lost catch roll still leaves the net thrown")
  eq(#game.level.captives, 0, "no captive is created when the target thrashes free")
  eq(rat.hp, 1, "a thrashing target takes no further damage")
  ok(rat:isAlive(), "a target that thrashes free is still alive")
  ok(contains(lines[1], "thrashes free"), "the log reports the target thrashing free")
end

function tests.captivesResolveCatchesABatteredTargetIntoACaptiveAndZeroesItsHp()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.rng = Rng.new(2)
  local net = Items.net()
  local success, lines = Captives.resolve(game, game.player, net, rat)
  eq(success, true, "a successful catch leaves the net thrown")
  eq(#game.level.captives, 1, "a successful catch adds exactly one captive")
  local captive = game.level.captives[1]
  eq(captive.name, rat.name, "the captive keeps the caught monster's name")
  eq(captive.species, rat.species, "the captive keeps the caught monster's species")
  eq(captive.faction, rat.faction, "the captive keeps the caught monster's faction")
  eq(captive.value, Monsters.xpFor(rat), "the captive's value matches Captives.valueOf")
  eq(rat.hp, 0, "the caught monster's hp is zeroed")
  ok(not rat:isAlive(), "the caught monster is no longer alive")
  ok(contains(lines[1], "bound"), "the log reports the net dropping true")
end

function tests.gameCaptureAtRemovesTheCaughtMonsterFromTheLevelWithoutAwardingAKill()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  local before = #game.player.inventory
  game.player.inventory[#game.player.inventory + 1] = Items.net()
  local index = #game.player.inventory
  game.rng = Rng.new(2)
  local xpBefore = game.player.xp
  local killsBefore = game.stats.kills
  local success = game:captureAt(index, rat)
  eq(success, true, "a successful net capture reports the item as thrown")
  eq(#game.player.inventory, before, "the net leaves the inventory once thrown")
  eq(#game.level.entities, 0, "the captured monster is swept from the level's entities")
  eq(#game.level.captives, 1, "the captured monster becomes exactly one level captive")
  eq(game.player.xp, xpBefore, "a capture grants no xp")
  eq(game.stats.kills, killsBefore, "a capture is never counted as a kill")
  eq(#game.level.corpses, 0, "a captured monster leaves no corpse behind")
end

function tests.gameCaptureAtLeavesTheTargetAliveAndTheNetUnspentWhenOutOfRange()
  local game = stagedGame(4, arena(21, 11), 2, 2)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 19, 9, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.net()
  local index = #game.player.inventory
  local before = #game.player.inventory
  local success = game:captureAt(index, rat)
  eq(success, false, "a capture attempt beyond range fails")
  eq(#game.player.inventory, before, "a failed capture attempt does not consume the net")
  ok(rat:isAlive(), "a failed capture attempt leaves the target alive")
end

function tests.gameRansomCaptiveWarmsFactionStandingWithNoGoldChange()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  game.level.captives = { { x = 5, y = 5, species = "rat", faction = Factions.VERMIN, name = "rat", value = 3 } }
  local goldBefore = game.player.gold
  local repBefore = Factions.reputationFor(game.player, Factions.VERMIN)
  local success = game:ransomCaptive()
  eq(success, true, "ransoming a held captive succeeds")
  eq(#game.level.captives, 0, "ransoming removes the captive from the level")
  eq(game.player.gold, goldBefore, "ransoming changes no gold")
  eq(Factions.reputationFor(game.player, Factions.VERMIN), repBefore + Captives.RANSOM_REP_GAIN,
    "ransoming warms the captive's own faction standing")
end

function tests.gameSellCaptivePaysGoldAndCoolsFactionStanding()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  game.level.captives = { { x = 5, y = 5, species = "rat", faction = Factions.VERMIN, name = "rat", value = 7 } }
  local goldBefore = game.player.gold
  local repBefore = Factions.reputationFor(game.player, Factions.VERMIN)
  local success = game:sellCaptive()
  eq(success, true, "selling a held captive succeeds")
  eq(#game.level.captives, 0, "selling removes the captive from the level")
  eq(game.player.gold, goldBefore + 7, "selling pays exactly the captive's own value in gold")
  eq(Factions.reputationFor(game.player, Factions.VERMIN), repBefore - Captives.SELL_REP_LOSS,
    "selling cools the captive's own faction standing")
end

function tests.gameInterrogateCaptiveRevealsEveryHiddenDoorAndGrantsEssence()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  game.level.secretDoors = {
    { x = 8, y = 8, discovered = false },
    { x = 9, y = 9, discovered = false },
    { x = 10, y = 10, discovered = true },
  }
  game.level.captives = { { x = 5, y = 5, species = "rat", faction = Factions.VERMIN, name = "rat", value = 8 } }
  local essenceBefore = game.player.essence
  local success = game:interrogateCaptive()
  eq(success, true, "interrogating a held captive succeeds")
  eq(#game.level.captives, 0, "interrogating removes the captive from the level")
  ok(game.level.secretDoors[1].discovered, "interrogating reveals a previously hidden door")
  ok(game.level.secretDoors[2].discovered, "interrogating reveals every previously hidden door, not just one")
  eq(game.player.essence, essenceBefore + 4, "interrogating grants essence equal to half the captive's value")
  eq(game.log:last(), "rat breaks - 2 hidden doors in this floor give themselves away",
    "several revealed doors are reported in the plural")
end

function tests.gameInterrogateCaptiveReportsASingleRevealedDoorInTheSingular()
  local game = stagedGame(4, arena(21, 11), 5, 5)
  game.level.secretDoors = { { x = 8, y = 8, discovered = false } }
  game.level.captives = { { x = 5, y = 5, species = "rat", faction = Factions.VERMIN, name = "rat", value = 8 } }
  game:interrogateCaptive()
  eq(game.log:last(), "rat breaks - 1 hidden door in this floor gives itself away",
    "a single revealed door takes a singular noun and verb")
end

function tests.captiveFieldsSurviveALevelSerializationRoundTrip()
  local level = arena(21, 11)
  level.captives = { { x = 5, y = 5, species = "rat", faction = Factions.VERMIN, name = "rat", value = 3 } }
  local restored = Level.fromData(level:toData())
  eq(#restored.captives, 1, "a held captive survives a level round trip")
  eq(restored.captives[1].name, "rat", "the captive's name survives a round trip")
  eq(restored.captives[1].faction, Factions.VERMIN, "the captive's faction survives a round trip")
  eq(restored.captives[1].value, 3, "the captive's value survives a round trip")
  eq(restored:captiveAt(5, 5), restored.captives[1], "Level:captiveAt finds the restored captive by position")
end

function tests.netsStayOffFloorsAboveDepthFive()
  for seed = 1, 8 do
    for depth = 1, 4 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        ok(ground.item.kind ~= Items.NET, "no net appears above depth 5")
      end
    end
  end
end

return tests
