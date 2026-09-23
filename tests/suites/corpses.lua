local helpers = require("helpers")
local Items = require("items")
local Status = require("status")
local Monsters = require("monsters")
local Level = require("level")
local Bosses = require("bosses")
local Mimics = require("mimics")
local Corpses = require("corpses")
local Render = require("render")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local function corpsePlayer()
  return { inventory = {}, statuses = {} }
end

local tests = helpers.suite()

function tests.corpsesSpawnsForAWildMonsterButNotForUndeadMimicOrBoss()
  local level = { corpses = {} }
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(level, rat)
  eq(#level.corpses, 1, "a wild monster leaves a corpse behind")

  local zombie = Monsters.create(Monsters.byKey.zombie, 2, 6, 6, 4)
  Corpses.spawn(level, zombie)
  eq(#level.corpses, 1, "an undead monster crumbles to dust, leaving no corpse")

  local mimic = Mimics.reveal(3, 7, 7, 4)
  Corpses.spawn(level, mimic)
  eq(#level.corpses, 1, "a mimic was never alive, so it leaves no corpse")

  local warlord = Bosses.create(Bosses.byKey.warlord, 4, 8, 8)
  Corpses.spawn(level, warlord)
  eq(#level.corpses, 1, "a boss's own scripted loot drop replaces a corpse")
end

function tests.corpsesNutritionScalesWithTheFelledSpeciesMaxHpClampedToAFixedBand()
  local bat = Monsters.create(Monsters.byKey.bat, 1, 5, 5, 1)
  local batCorpse = Corpses.new(bat)
  eq(batCorpse.nutrition, Corpses.NUTRITION_MIN, "a frail species clamps to the nutrition floor")

  local troll = Monsters.create(Monsters.byKey.troll, 2, 5, 5, 5)
  local trollCorpse = Corpses.new(troll)
  eq(trollCorpse.nutrition, troll.maxHp * Corpses.NUTRITION_PER_HP, "a tougher species scales nutrition with maxHp")

  local dragon = Monsters.create(Monsters.byKey.dragon, 3, 5, 5, 6)
  local dragonCorpse = Corpses.new(dragon)
  eq(dragonCorpse.nutrition, Corpses.NUTRITION_MAX, "an especially tough species clamps to the nutrition ceiling")
end

function tests.corpsesStepCountsDownAndRotsAwayEntirely()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local level = { corpses = {} }
  Corpses.spawn(level, rat)
  local corpse = level.corpses[1]
  for _ = 1, Corpses.DECAY_TURNS - 1 do Corpses.step(level) end
  eq(#level.corpses, 1, "a corpse survives right up to its final round")
  eq(corpse.decay, 1, "decay counts down by exactly one each step")
  Corpses.step(level)
  eq(#level.corpses, 0, "a corpse vanishes outright once its decay reaches zero")
end

function tests.corpsesGoesRottenPastItsThresholdButStaysButcherableUntilThen()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local corpse = Corpses.new(rat)
  ok(not Corpses.isRotten(corpse), "a freshly spawned corpse is not yet rotten")
  corpse.decay = Corpses.ROT_TURNS
  ok(Corpses.isRotten(corpse), "a corpse right at its rot threshold counts as rotten")
  corpse.decay = Corpses.ROT_TURNS + 1
  ok(not Corpses.isRotten(corpse), "a corpse one round above the threshold is still good")
end

function tests.corpsesButcheringFreshMeatAddsFoodToInventoryAndConsumesTheCorpse()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local level = { corpses = {} }
  Corpses.spawn(level, rat)
  local corpse = level.corpses[1]
  local game = { player = corpsePlayer(), level = level }
  local line = Corpses.butcher(game, corpse)
  eq(#level.corpses, 0, "butchering removes the corpse from the level")
  eq(#game.player.inventory, 1, "butchering fresh meat adds a food item to the inventory")
  eq(game.player.inventory[1].kind, Items.FOOD, "the yield is a food item")
  eq(game.player.inventory[1].nutrition, corpse.nutrition, "the food item carries the corpse's own nutrition value")
  ok(contains(line, "carve"), "a fresh butchering is logged as carving meat")
  ok(#game.player.statuses == 0, "fresh meat never poisons the player")
end

function tests.corpsesButcheringRottenMeatPoisonsThePlayerInsteadAndStillConsumesTheCorpse()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local level = { corpses = {} }
  Corpses.spawn(level, rat)
  local corpse = level.corpses[1]
  corpse.decay = Corpses.ROT_TURNS
  local game = { player = corpsePlayer(), level = level }
  local line = Corpses.butcher(game, corpse)
  eq(#level.corpses, 0, "butchering removes a rotten corpse too")
  eq(#game.player.inventory, 0, "rotten meat yields no food item")
  ok(Status.has(game.player, Status.POISON), "eating rotten meat poisons the player")
  ok(contains(line, "rotted"), "a rotten butchering is logged as such")
end

function tests.corpseFieldsSurviveSerialization()
  local level = arena(21, 11)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(level, rat)
  level.corpses[1].x, level.corpses[1].y = 4, 4
  local restored = Level.fromData(level:toData())
  eq(#restored.corpses, 1, "the corpse list survives a round trip")
  eq(restored.corpses[1].species, "rat", "a corpse's species survives a round trip")
  eq(restored.corpses[1].nutrition, level.corpses[1].nutrition, "a corpse's nutrition survives a round trip")
  eq(restored.corpses[1].decay, level.corpses[1].decay, "a corpse's decay survives a round trip")
end

function tests.corpseRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  Corpses.spawn(rendered.level, rat)
  rendered:computeVisible()
  eq(helpers.glyphAt(rendered, 5, 6), Render.glyphs.corpse, "a corpse on a visible cell renders as its glyph")
  ok(Render.glyphs.corpse ~= Items.glyphs[Items.FOOD], "a corpse never looks like a food ration")
end

function tests.gameAwardKillLeavesACorpseForAWildMonsterButNotForUndeadOrMimic()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 0
  game.level.entities = { rat }
  game:awardKill(rat)
  eq(#game.level.corpses, 1, "killing a wild monster through awardKill leaves a corpse")
  eq(game.level.corpses[1].x, 4, "the corpse sits exactly where the monster fell")

  local zombie = Monsters.create(Monsters.byKey.zombie, 2, 4, 7, 4)
  zombie.hp = 0
  game.level.entities = { zombie }
  game:awardKill(zombie)
  eq(#game.level.corpses, 1, "killing an undead monster through awardKill leaves no new corpse")
end

function tests.gameButcherCorpseAtFreshMeatFeedsThePlayerAndClearsTheCorpse()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local before = #game.player.inventory
  ok(game:butcherCorpse(), "butchering the corpse underfoot succeeds")
  eq(#game.level.corpses, 0, "the corpse is gone after butchering")
  eq(#game.player.inventory, before + 1, "the player's inventory gains the carved meat")
end

function tests.gameButcherCorpseFailsWithoutACorpseUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:butcherCorpse(), "butchering empty ground fails")
end

return tests
