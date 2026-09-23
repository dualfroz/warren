local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Identify = require("identify")
local Level = require("level")
local Builder = require("builder")
local Game = require("game")
local Hazards = require("hazards")
local Alchemy = require("alchemy")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.alchemyBrewResolvesAKnownPairToItsFixedPotion()
  local potion = Alchemy.brew(Alchemy.SUNPETAL, Alchemy.SUNPETAL)
  eq(potion.effect, "heal", "a matched pair of the same herb brews that herb's aspect")
  eq(potion.power, 18, "a doubled herb brews a stronger potion than a mixed pair")
end

function tests.alchemyBrewIsOrderIndependent()
  local forward = Alchemy.brew(Alchemy.BLOODROOT, Alchemy.NIGHTCAP)
  local backward = Alchemy.brew(Alchemy.NIGHTCAP, Alchemy.BLOODROOT)
  eq(forward.effect, backward.effect, "brewing a pair does not depend on which herb is named first")
  eq(forward.power, backward.power, "a brewed potion's power does not depend on herb order either")
end

function tests.alchemyBrewCurdlesOnAnOpposedPairing()
  local potion, reason = Alchemy.brew(Alchemy.SUNPETAL, Alchemy.NIGHTCAP)
  eq(potion, nil, "light and shade herbs curdle rather than brewing a potion")
  eq(reason, "curdle", "a curdled brew names its failure")
end

function tests.alchemyLookupRejectsAnUnknownHerb()
  eq(Alchemy.lookup("mud", Alchemy.SUNPETAL), nil, "a nonexistent herb key has no recipe")
end

function tests.gameBrewAtCombinesTwoHerbsIntoAPotionAtACauldron()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.BLOODROOT) }
  ok(game:brewAt(1, 2), "brewing two herbs at a cauldron underfoot succeeds")
  eq(#game.player.inventory, 1, "both source herbs are spent and one potion is added")
  local brewed = game.player.inventory[1]
  eq(brewed.kind, Items.POTION, "brewing yields an ordinary catalog potion")
  eq(brewed.effect, "heal", "the brewed potion matches the herb pair's fixed recipe")
  eq(brewed.power, 10, "the brewed potion's power matches the recipe, not the catalog default")
  ok(Identify.isKnown(game.identify, brewed), "brewing a potion yourself identifies its type for free")
end

function tests.gameBrewAtFailsWithoutACauldronUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.BLOODROOT) }
  ok(not game:brewAt(1, 2), "brewing away from any cauldron fails")
  eq(#game.player.inventory, 2, "a failed brew for lack of a cauldron spends nothing")
end

function tests.gameBrewAtRequiresTwoHerbItems()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL) }
  ok(not game:brewAt(1, 1), "brewing a herb against itself by index is rejected")
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Items.potion(10) }
  ok(not game:brewAt(1, 2), "a non-herb item cannot stand in for the second half of a brew")
  eq(#game.player.inventory, 2, "a rejected brew attempt spends nothing")
end

function tests.gameBrewAtCurdlesIntoGasInsteadOfAPotion()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.NIGHTCAP) }
  ok(not game:brewAt(1, 2), "a curdled brew reports failure")
  eq(#game.player.inventory, 0, "a curdled brew still spends both herbs")
  ok(Hazards.at(game.level, 5, 5, Hazards.GAS) ~= nil, "a curdled brew vents a gas hazard at the brewer's feet")
  ok(contains(game.log:recent(1)[1] or "", "curdle"), "the curdle is logged")
end

function tests.cauldronsStayOffTheEntranceFloor()
  for seed = 1, 5 do
    local level = Builder.build(1, Rng.new(seed), {})
    eq(#level.cauldrons, 0, "no cauldron appears on the entrance floor")
  end
end

function tests.cauldronFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.cauldrons = { { x = 4, y = 4 } }
  local restored = Level.fromData(level:toData())
  eq(#restored.cauldrons, 1, "the cauldron list survives a round trip")
  eq(restored.cauldrons[1].x, 4, "a cauldron's position survives a round trip")
end

function tests.cauldronRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  rendered.level.cauldrons = { { x = 5, y = 6 } }
  rendered:computeVisible()
  ok(contains(rendered:render(), "U"), "a cauldron on a visible cell renders as its glyph")
end

function tests.herbItemsSurviveSerialization()
  local game = Game.new(5)
  game.player.inventory[#game.player.inventory + 1] = Alchemy.herb(Alchemy.NIGHTCAP)

  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)

  local restoredHerb
  for _, item in ipairs(restored.player.inventory) do
    if item.kind == Items.HERB then restoredHerb = item end
  end
  ok(restoredHerb ~= nil, "a foraged herb survives a save/load round trip")
  eq(restoredHerb.herb, Alchemy.NIGHTCAP, "a herb's species survives a save/load round trip")
end

function tests.alchemyMoonbellPairedWithItselfConcentratesIntoConfusion()
  local potion = Alchemy.brew(Alchemy.MOONBELL, Alchemy.MOONBELL)
  eq(potion.effect, "confuse", "a doubled moonbell brews its own dream-fog aspect")
end

function tests.alchemyMoonbellPairedWithSunpetalCurdlesOnTheDayVersusDreamOpposition()
  local potion, reason = Alchemy.brew(Alchemy.SUNPETAL, Alchemy.MOONBELL)
  eq(potion, nil, "day and dream herbs curdle rather than brewing a potion")
  eq(reason, "curdle", "a curdled moonbell brew names its failure like any other opposed pair")
end

function tests.alchemyMoonbellPairedWithBloodrootBrewsClarity()
  local potion = Alchemy.brew(Alchemy.BLOODROOT, Alchemy.MOONBELL)
  eq(potion.effect, "clarity", "blood grounds the dreaming mind into clarity instead of confusion")
  eq(potion.power, 30, "an unspecified recipe power falls back to the catalog default for its effect")
end

function tests.alchemyMoonbellPairedWithEmberleafBrewsBlindness()
  local potion = Alchemy.brew(Alchemy.EMBERLEAF, Alchemy.MOONBELL)
  eq(potion.effect, "blind", "fire's smoke thickened by dream-fog brews blindness")
end

function tests.alchemyMoonbellPairedWithFrostmossBrewsLevitation()
  local potion = Alchemy.brew(Alchemy.FROSTMOSS, Alchemy.MOONBELL)
  eq(potion.effect, "levitate", "frost's lightness carried by dream-fog brews levitation")
end

function tests.alchemyMoonbellPairedWithNightcapBrewsAStrongerPoisonThanEitherHerbAlone()
  local blended = Alchemy.brew(Alchemy.NIGHTCAP, Alchemy.MOONBELL)
  eq(blended.effect, "poison", "two shade-aspected herbs still blend into poison, like nightcap's other cross pairs")
  ok(blended.power > Alchemy.recipes[Alchemy.pairKey(Alchemy.BLOODROOT, Alchemy.NIGHTCAP)].power,
    "moonbell's nightcap blend is stronger than nightcap's weakest existing poison blend")
  ok(blended.power < Alchemy.recipes[Alchemy.pairKey(Alchemy.NIGHTCAP, Alchemy.NIGHTCAP)].power,
    "moonbell's nightcap blend still falls short of concentrated nightcap's own poison")
end

function tests.alchemyAddingMoonbellLeftEveryPreExistingRecipeUntouched()
  eq(Alchemy.brew(Alchemy.SUNPETAL, Alchemy.SUNPETAL).power, 18, "concentrated sunpetal still heals for its original power")
  local potion, reason = Alchemy.brew(Alchemy.SUNPETAL, Alchemy.NIGHTCAP)
  eq(potion, nil, "sunpetal and nightcap still curdle")
  eq(reason, "curdle", "the pre-existing curdle still names its failure the same way")
  eq(Alchemy.brew(Alchemy.EMBERLEAF, Alchemy.FROSTMOSS), nil, "emberleaf and frostmoss still curdle too")
  eq(Alchemy.brew(Alchemy.NIGHTCAP, Alchemy.NIGHTCAP).power, 7, "concentrated nightcap still brews its original poison power")
end

function tests.gameBrewAtCanBrewAMoonbellPairingAtACauldron()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.MOONBELL), Alchemy.herb(Alchemy.FROSTMOSS) }
  ok(game:brewAt(1, 2), "brewing moonbell with frostmoss at a cauldron underfoot succeeds")
  eq(#game.player.inventory, 1, "both source herbs are spent and one potion is added")
  local brewed = game.player.inventory[1]
  eq(brewed.effect, "levitate", "the brewed potion matches moonbell/frostmoss's fixed recipe")
  ok(Identify.isKnown(game.identify, brewed), "brewing a moonbell potion yourself identifies its type for free, like any other brew")
end

return tests
