local helpers = require("helpers")
local Items = require("items")
local Game = require("game")
local Encumbrance = require("encumbrance")

local ok, eq, contains, arena, stagedGame, padWith = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame, helpers.padWith

local tests = helpers.suite()

function tests.encumbranceItemWeightScalesWithGearPower()
  eq(Encumbrance.itemWeight(Items.weapon("dagger", 2)), 6, "a weak weapon carries close to its flat base weight")
  eq(Encumbrance.itemWeight(Items.weapon("greatsword", 9)), 9, "a powerful weapon weighs more than a weak one of the same kind")
  eq(Encumbrance.itemWeight(Items.armor("padded vest", 0)), 9, "armor has its own, heavier, flat base")
end

function tests.encumbranceAmmoWeightScalesWithStackCount()
  eq(Encumbrance.itemWeight(Items.ammo("arrow", 1)), 1, "a single arrow weighs its unit weight")
  eq(Encumbrance.itemWeight(Items.ammo("arrow", 5)), 5, "a stack of arrows weighs the unit weight times the count")
end

function tests.encumbranceCapacityGrowsWithLevel()
  eq(Encumbrance.capacityFor({ level = 1 }), 16, "a level 1 carrier's capacity is the flat base plus one level's worth")
  eq(Encumbrance.capacityFor({ level = 5 }), 32, "capacity scales linearly with level")
  eq(Encumbrance.capacityFor({}), 16, "a missing level defaults to level 1's capacity")
end

function tests.encumbranceEquippedGearCountsTowardCarriedWeight()
  local carrier = {
    inventory = {},
    weapon = Items.weapon("sword", 3), armor = Items.armor("mail", 6),
    ring = Items.ring("band", 1, 1), bow = Items.bow("bow", 2, 3),
  }
  eq(Encumbrance.carriedWeight(carrier), 26, "worn and wielded gear counts exactly like the same items in the pack")
end

function tests.encumbranceLightLoadHasNoPenalty()
  local game = Game.new(1)
  eq(game.player:encumbranceTier(), Encumbrance.LIGHT, "a fresh player's starting kit is well under capacity")
  eq(game.player:effectiveSpeed(), 100, "a light load never slows the carrier down")
  eq(game.player:effectiveDefense(), 1, "a light load never costs defense")
end

function tests.encumbranceBurdenedSlowsMovementButNotDefense()
  local game = Game.new(1)
  game.player.inventory = {}
  padWith(game.player, 2)
  ok(Encumbrance.carriedWeight(game.player) > Encumbrance.capacityFor(game.player),
    "two heavy armors alone clear the fresh player's capacity")
  eq(game.player:encumbranceTier(), Encumbrance.BURDENED, "a moderate overage is merely burdened")
  eq(game.player:effectiveSpeed(), 80, "a burdened carrier loses a flat chunk of speed")
  eq(game.player:effectiveDefense(), 1, "a burdened carrier's defense is untouched")
end

function tests.encumbranceOverloadedSlowsMovementAndWeakensDefense()
  local game = Game.new(1)
  game.player.inventory = {}
  padWith(game.player, 3)
  eq(game.player:encumbranceTier(), Encumbrance.OVERLOADED, "a wide overage is overloaded")
  eq(game.player:effectiveSpeed(), 55, "an overloaded carrier loses far more speed than a merely burdened one")
  eq(game.player:effectiveDefense(), -1, "an overloaded carrier also fumbles, losing defense")
end

function tests.gameDropItemReturnsItemToTheFloorAndFreesCapacity()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  game.player.inventory = { Items.potionOf("heal") }
  local before = Encumbrance.carriedWeight(game.player)
  local dropped = game:dropItem(1)
  eq(dropped.effect, "heal", "dropItem returns the item that was shed")
  eq(#game.player.inventory, 0, "the item leaves the inventory")
  eq(#game.level.floorItems, 1, "the item lands on the floor")
  eq(game.level.floorItems[1].x, game.player.x, "the dropped item lands exactly at the player's feet")
  eq(game.level.floorItems[1].y, game.player.y, "the dropped item lands exactly at the player's feet")
  ok(Encumbrance.carriedWeight(game.player) < before, "dropping an item frees up carried weight")
  ok(contains(game.log:last(), "drop"), "dropping an item is logged")
end

function tests.gamePickupWarnsWhenNewWeightTipsIntoOverloaded()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  game.player.inventory = {}
  padWith(game.player, 1)
  eq(game.player:encumbranceTier(), Encumbrance.LIGHT, "one heavy armor alone still fits under capacity")
  game.level.floorItems = {}
  for _ = 1, 2 do
    game.level.floorItems[#game.level.floorItems + 1] = { x = 3, y = 3, item = Items.armor("lockbox", 0) }
  end
  game:pickupHere()
  eq(game.player:encumbranceTier(), Encumbrance.OVERLOADED, "the pickup tips the total weight past the overloaded threshold")
  ok(contains(game.log:last(), "overloaded"), "tipping straight into overloaded is called out by name")
end

function tests.gamePickupWarnsWithALighterMessageWhenOnlyTippingIntoBurdened()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  game.player.inventory = {}
  game.level.floorItems = {}
  for _ = 1, 2 do
    game.level.floorItems[#game.level.floorItems + 1] = { x = 3, y = 3, item = Items.armor("lockbox", 0) }
  end
  game:pickupHere()
  eq(game.player:encumbranceTier(), Encumbrance.BURDENED, "two heavy armors in one pickup lands in the burdened band")
  ok(contains(game.log:last(), "heavy"), "tipping only into burdened gets the softer warning")
end

function tests.encumbranceTierIsDerivedAcrossASaveLoadRoundTrip()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  game.player.inventory = {}
  padWith(game.player, 2)
  local tierBefore = game:encumbranceTier()
  local restored = Game.fromData(game:toData())
  eq(restored:encumbranceTier(), tierBefore, "the same inventory yields the same tier after a save/load round trip")
end

return tests
