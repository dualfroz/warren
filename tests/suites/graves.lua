local helpers = require("helpers")
local Entity = require("entity")
local Game = require("game")
local Crafting = require("crafting")
local Meta = require("meta")
local Factions = require("factions")
local Graves = require("graves")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.gravesRecordAppendsNewestFirstAndTrimsToMaxRecorded()
  local meta = Meta.new()
  for i = 1, Graves.MAX_RECORDED + 5 do
    Graves.record(meta, { className = "fighter", depth = i, gold = i, essence = 0, turn = i })
  end
  eq(#meta.graves, Graves.MAX_RECORDED, "recording past the cap trims the oldest graves off")
  eq(meta.graves[1].depth, Graves.MAX_RECORDED + 5, "the most recently recorded grave sits at the front")
end

function tests.gravesEligibleForOnlyIncludesGravesAtOrDeeperThanTheQueriedDepth()
  local graves = {
    { className = "a", depth = 2 },
    { className = "b", depth = 5 },
    { className = "c", depth = 5 },
  }
  local atFive = Graves.eligibleFor(graves, 5)
  eq(#atFive, 2, "only the two graves dug at depth 5 or deeper are eligible for a depth-5 floor")
  local atOne = Graves.eligibleFor(graves, 1)
  eq(#atOne, 3, "every recorded grave is eligible for the entrance floor, however deep it was dug")
  eq(#Graves.eligibleFor(nil, 3), 0, "a caller with no recorded graves at all gets an empty list, not an error")
end

function tests.gravesFloorItemBuildsAnInertGraveMarkerShape()
  local grave = { className = "ranger", depth = 4, gold = 50, essence = 6, turn = 20 }
  local item = Graves.floorItem(grave)
  eq(item.kind, "grave", "a grave's floor item is its own kind, not a real item kind")
  eq(item.grave, true, "a grave's floor item is tagged so pickupHere knows to wake it")
  eq(item.graveClass, "ranger", "the marker carries the fallen's own class")
  eq(item.graveGold, 50, "the marker carries the fallen's gold for Graves.reveal to read later")
  eq(item.graveEssence, 6, "the marker carries the fallen's essence for Graves.reveal to read later")
end

function tests.gravesRevealScalesHpAndAttackWithCarriedWealthAndCaps()
  local poor = Graves.reveal(1, 4, 6, { graveGold = 0, graveEssence = 0 })
  eq(poor.hp, 10, "a penniless grave's shade has no hp bonus at all")
  eq(poor.attack, 4, "a penniless grave's shade has no attack bonus at all")
  eq(poor.faction, Factions.UNDEAD, "a shade is undead like every other restless dead in the bestiary")

  local rich = Graves.reveal(2, 4, 6, { graveGold = 400, graveEssence = 200 })
  eq(rich.hp, 30, "a rich grave's shade hp bonus caps at 20 rather than scaling without bound")
  eq(rich.attack, 10, "a rich grave's shade attack bonus caps at 6 rather than scaling without bound")
end

function tests.gravesLootForReturnsHalfGoldAndAThirdEssenceRoundedDown()
  local shade = Graves.reveal(1, 4, 6, { graveGold = 55, graveEssence = 10 })
  local gold, essence = Graves.lootFor(shade)
  eq(gold, 27, "grave loot pays out half the carried gold, rounded down")
  eq(essence, 3, "grave loot pays out a third of the carried essence, rounded down")
end

function tests.graveFieldsSurviveSerialization()
  local shade = Graves.reveal(1, 4, 6, { graveClass = "ranger", graveGold = 88, graveEssence = 15 })
  local restored = Entity.fromData(shade:toData())
  eq(restored.grave, true, "a revealed shade's grave tag survives a save/load round trip")
  eq(restored.graveClass, "ranger", "the fallen's class survives a save/load round trip")
  eq(restored.graveGold, 88, "the grave's gold survives a save/load round trip")
  eq(restored.graveEssence, 15, "the grave's essence survives a save/load round trip")
end

function tests.gamePickupHereWakesAGraveShadeAndAmbushesThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.defense, game.player.baseDefense = 0, 0
  local grave = { className = "rogue", depth = 3, gold = 0, essence = 0, turn = 10 }
  game.level.floorItems = { { x = 5, y = 5, item = Graves.floorItem(grave) } }
  local hpBefore = game.player.hp
  game:pickupHere()
  eq(#game.level.floorItems, 0, "the grave marker leaves the floor the instant it is disturbed")
  eq(#game.level.entities, 1, "a disturbed grave joins the level as a real hostile monster")
  eq(game.level.entities[1].grave, true, "the spawned monster is tagged as a grave shade")
  eq(game.player.hp, hpBefore - 4, "the shade lands one free ambush hit for its full attack")
  ok(contains(game.log:last(), "damage"), "the ambush hit is logged")
end

function tests.gameKillingARevealedShadeGrantsItsFixedXpAndPaysOutGraveLoot()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shade = Graves.reveal(1, 4, 6, { graveGold = 40, graveEssence = 9 })
  shade.hp = 1
  game.level.entities = { shade }
  local essenceBefore, goldBefore = game.player.essence, game.player.gold
  game:playerAttack(shade)
  eq(game.player.essence, essenceBefore + Crafting.essenceFor(Graves.xpFor()) + 3,
    "felling a shade grants essence scaled to its own fixed xp reward, plus a third of its grave essence")
  eq(game.player.gold, goldBefore + 20, "felling a shade also pays out half its grave gold")
  ok(contains(game.log:last(), "gold"), "the grave payout is logged")
end

function tests.gravesShadeLeavesNoCorpseLikeAnyOtherUndead()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shade = Graves.reveal(1, 4, 6, { graveGold = 0, graveEssence = 0 })
  shade.hp = 1
  game.level.entities = { shade }
  game:playerAttack(shade)
  eq(#game.level.corpses, 0, "a felled shade leaves no corpse behind, same as any other undead")
end

function tests.gameGraveEntryCapturesDepthGoldEssenceAndClassAtTheMomentOfDeath()
  local game = Game.new(4, { class = "mage" })
  game.deepestDepth = 6
  game.player.gold = 77
  game.player.essence = 14
  game.turn = 120
  local entry = game:graveEntry()
  eq(entry.className, "mage", "the grave records the class the run actually played")
  eq(entry.depth, 6, "the grave records the deepest depth reached, not just the current floor")
  eq(entry.gold, 77, "the grave records exactly what gold was still on hand at death")
  eq(entry.essence, 14, "the grave records exactly what essence was still on hand at death")
  eq(entry.turn, 120, "the grave records the turn count at death")
end

function tests.gameGraveEntryDefaultsToWandererForAClasslessRun()
  local game = Game.new(4)
  eq(game:graveEntry().className, "wanderer", "a run that never picked a class leaves a wanderer's grave")
end

return tests
