local helpers = require("helpers")
local Items = require("items")
local Identify = require("identify")
local Effects = require("effects")
local Status = require("status")
local Monsters = require("monsters")
local Game = require("game")
local Hazards = require("hazards")
local Sanity = require("sanity")
local Disease = require("disease")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.effects()
  local game = Game.new(31)
  game.player.hp = 10
  Effects.apply("heal", game, game.player, { power = 8 })
  eq(game.player.hp, 18, "heal effect restores hp")
  Effects.apply("poison", game, game.player, { power = 3 })
  eq(Status.has(game.player, Status.POISON), true, "poison effect afflicts the target")

  Effects.apply("confuse", game, game.player, {})
  eq(Status.has(game.player, Status.CONFUSE), true, "confuse effect afflicts the drinker just like poison")

  Effects.apply("blind", game, game.player, {})
  eq(Status.has(game.player, Status.BLIND), true, "blind effect afflicts the drinker just like confuse")

  Effects.apply("mapping", game, game.player, {})
  local map = game.level.map
  local exploredAll = true
  for idx = 1, map.width * map.height do
    if not game.level.explored[idx] then exploredAll = false end
  end
  ok(exploredAll, "magic mapping reveals the whole level")

  local unknown = Items.potionOf("strength")
  game.player.inventory = { unknown }
  Effects.apply("identify", game, game.player, {})
  eq(Identify.isKnown(game.identify, unknown), true, "identify reveals an inventory item type")

  local ox, oy = game.player.x, game.player.y
  Effects.apply("teleport", game, game.player, {})
  ok(game.player.x ~= ox or game.player.y ~= oy, "teleport relocates the player")
  eq(game.level.map:isWalkable(game.player.x, game.player.y), true, "teleport lands on walkable ground")

  local blastGame = stagedGame(1, arena(21, 11), 6, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 6, 1)
  orc.hp, orc.maxHp = 20, 20
  blastGame.level.entities = { orc }
  eq(Effects.apply("fireball", blastGame, blastGame.player, {})[1], "fire engulfs 1 foe",
    "a single scorched monster is reported in the singular")
  eq(orc.hp, 12, "fireball burns nearby monsters")
  eq(Status.has(orc, Status.BURNING), true, "fireball sets monsters alight")
  ok(Hazards.at(blastGame.level, orc.x, orc.y, Hazards.FIRE) ~= nil,
    "fireball leaves a lingering flame under a scorched monster")
  ok(Hazards.at(blastGame.level, blastGame.player.x, blastGame.player.y, Hazards.FIRE) ~= nil,
    "fireball also ignites the ground at its own point of origin")
end

function tests.effectsMessagesAddressThePlayerInSecondPersonNotThirdPersonSingular()
  local game = Game.new(31)
  game.player.hp = 10
  eq(Effects.apply("heal", game, game.player, { power = 5 })[1], "you heal 5",
    "heal addresses the player correctly, not 'you heals 5'")
  eq(Effects.apply("poison", game, game.player, { power = 3 })[1], "you are poisoned",
    "poison addresses the player correctly, not 'you is poisoned'")
  eq(Effects.apply("strength", game, game.player, {})[1], "you feel mightier",
    "strength addresses the player correctly, not 'you feels mightier'")
  eq(Effects.apply("haste", game, game.player, {})[1], "you speed up",
    "haste addresses the player correctly, not 'you speeds up'")
  eq(Effects.apply("fortify", game, game.player, {})[1], "you feel fortified",
    "fortify addresses the player correctly, not 'you feels fortified'")
  eq(Effects.apply("levitate", game, game.player, {})[1], "you rise off the ground",
    "levitate addresses the player correctly, not 'you rises off the ground'")
  eq(Effects.apply("confuse", game, game.player, {})[1], "your mind reels with confusion",
    "confuse addresses the player possessively, not \"you's mind reels with confusion\"")
  eq(Effects.apply("blind", game, game.player, {})[1], "you are struck blind",
    "blind addresses the player correctly, not 'you is struck blind'")
  eq(Effects.apply("teleport", game, game.player, {})[1], "you blink away",
    "teleport addresses the player correctly, not 'you blinks away'")
end

function tests.effectsClarityMessageAddressesThePlayerPossessively()
  local game = Game.new(31)
  Sanity.adjust(game.player, -20)
  local line = Effects.apply("clarity", game, game.player, { power = 10 })[1]
  ok(contains(line, "your mind steadies"), "clarity addresses the player possessively, not \"you's mind steadies\"")
end

function tests.effectsCureMessagesAddressThePlayerPossessivelyForAllFourOutcomes()
  local game = Game.new(31)
  Disease.infect(game.player, Disease.ROT)
  Status.apply(game.player, Status.POISON, 5, 2)
  eq(Effects.apply("cure", game, game.player, {})[1], "your affliction is cleansed away, and the poison fades",
    "curing both addresses the player possessively, not \"you's affliction ... you's poison\"")

  Disease.infect(game.player, Disease.ROT)
  eq(Effects.apply("cure", game, game.player, {})[1], "your affliction is cleansed away",
    "curing disease alone addresses the player possessively, not \"you's affliction\"")

  Status.apply(game.player, Status.POISON, 5, 2)
  eq(Effects.apply("cure", game, game.player, {})[1], "your poison fades",
    "curing a status alone addresses the player possessively, not \"you's poison fades\"")

  eq(Effects.apply("cure", game, game.player, {})[1], "you feel a faint tingle, but had nothing to cleanse",
    "curing nothing addresses the player correctly, not 'you feels a faint tingle'")
end

function tests.effectsCureNamesOneTwoAndThreeLiftedStatusesAsNounsInANaturalList()
  local game = Game.new(31)
  Status.apply(game.player, Status.CONFUSE, 6, 1)
  eq(Effects.apply("cure", game, game.player, {})[1], "your confusion fades",
    "one lifted status reads as a noun, never the verb \"confuse\"")
  Status.apply(game.player, Status.POISON, 5, 2)
  Status.apply(game.player, Status.CONFUSE, 6, 1)
  eq(Effects.apply("cure", game, game.player, {})[1], "your poison and confusion fade",
    "two lifted statuses are joined with \"and\" and take a plural verb")
  Status.apply(game.player, Status.POISON, 5, 2)
  Status.apply(game.player, Status.CONFUSE, 6, 1)
  Status.apply(game.player, Status.BLIND, 6, 1)
  eq(Effects.apply("cure", game, game.player, {})[1], "your poison, confusion and blindness fade",
    "three lifted statuses read as \"a, b and c\"")

  local rat = Monsters.create(Monsters.byKey.rat, 1, 1, 1, 1)
  Disease.infect(rat, Disease.ROT)
  Status.apply(rat, Status.BURNING, 3, 1)
  Status.apply(rat, Status.DISCORD, 3, 1)
  eq(Effects.apply("cure", game, rat, {})[1], "rat's affliction is cleansed away, and the burning and discord fade",
    "a monster's cured statuses use the same nouns and natural list")
end

function tests.potionOfFortificationAppliesAShield()
  local game = Game.new(31)
  Effects.apply("fortify", game, game.player, {})
  ok(Status.has(game.player, Status.SHIELD), "a fortify effect wards the drinker")
end

function tests.usingAFortifyPotionAppliesShieldAndConsumesIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local potion = Items.potionOf("fortify")
  game.player.inventory = { potion }
  ok(game:useItem(1), "drinking a fortify potion succeeds")
  eq(#game.player.inventory, 0, "drinking the potion consumes it")
  ok(Status.has(game.player, Status.SHIELD), "the fortify potion wards the player")
end

function tests.potionOfLevitationAppliesTheLevitateStatus()
  local game = Game.new(31)
  Effects.apply("levitate", game, game.player, {})
  ok(Status.has(game.player, Status.LEVITATE), "a levitate effect lifts the drinker off the ground")
end

function tests.usingAPotionOfLevitationAppliesLevitateAndConsumesIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local potion = Items.potionOf("levitate")
  game.player.inventory = { potion }
  ok(game:useItem(1), "drinking a levitation potion succeeds")
  eq(#game.player.inventory, 0, "drinking the potion consumes it")
  ok(Status.has(game.player, Status.LEVITATE), "the levitation potion lifts the player off the ground")
end

return tests
