local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Shop = require("shop")
local Monsters = require("monsters")
local Ai = require("ai")
local Builder = require("builder")
local Factions = require("factions")
local Mercenaries = require("mercenaries")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.shopPriceCatalogScalesWithPower()
  local base = Shop.priceOf(Items.weapon("dagger", 2))
  local strong = Shop.priceOf(Items.weapon("battle axe", 5))
  ok(strong > base, "a more powerful weapon costs more at the shop")
  eq(Shop.priceOf(Items.potionOf("heal")), 15, "a catalogued potion has its fixed price")
  eq(Shop.sellValue(Items.potionOf("heal")), 7, "selling nets half the catalog price, rounded down")
end

function tests.shopStockRollsAffordableWares()
  local wares = Shop.stock(Rng.new(7))
  ok(#wares >= 3 and #wares <= 5, "a shop rolls three to five wares")
  for _, item in ipairs(wares) do
    ok(Shop.priceOf(item) > 0, "every ware has a positive price")
  end
end

function tests.goldPickupAddsToWalletNotInventory()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local before = #game.player.inventory
  local goldBefore = game.player.gold
  game.level.floorItems = { { x = 4, y = 3, item = Items.gold(35) } }
  game:movePlayer(1, 0)
  eq(game.player.gold, goldBefore + 35, "walking onto gold adds it to the wallet")
  eq(#game.player.inventory, before, "gold never occupies an inventory slot")
  eq(#game.level.floorItems, 0, "the gold pile is removed from the floor")
end

function tests.affordableWareIsBoughtAutomaticallyOnPickup()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 50
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 35, "the ware's stamped price is deducted from the wallet")
  eq(#game.player.inventory, before + 1, "the bought ware joins the inventory")
  eq(#game.level.floorItems, 0, "the purchased ware leaves the ground")
end

function tests.unaffordableWareStaysOnTheGround()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 5
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 5, "an unaffordable ware is never bought, so no gold changes hands")
  eq(#game.player.inventory, before, "the ware never reaches the inventory")
  eq(#game.level.floorItems, 1, "the unbought ware is left in place")
end

function tests.deadKeeperMakesWaresFreeToLoot()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  keeper.hp = 0
  game.level.entities = { keeper }
  game.player.gold = 0
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 0, "looting a dead keeper's stock costs nothing")
  eq(#game.player.inventory, before + 1, "the ware is picked up normally once its keeper is dead")
end

function tests.stealingFromShopTurnsTheKeeperHostile()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 0
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.scroll("identify"), price = 18, shopId = keeper.id } }
  local stolen = game:stealFromShop(1)
  eq(stolen, true, "stealing succeeds against a live keeper's ware")
  eq(game.player.gold, 0, "theft costs no gold")
  eq(#game.player.inventory, before + 1, "the stolen item joins the inventory")
  eq(keeper.hostile, true, "the keeper turns hostile after the theft")
  ok(contains(game.log:last(), "steal"), "the theft is logged")
end

function tests.hostileShopkeeperChasesLikeAnyMonster()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 8, 6, 4)
  keeper.hostile = true
  game.level.entities = { keeper }
  Ai.act(game, keeper)
  eq(keeper.x, 7, "a hostile shopkeeper closes in on the player like a chaser")
end

function tests.passiveShopkeeperIgnoresTheAdjacentPlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 4, 6, 4)
  game.level.entities = { keeper }
  local hpBefore = game.player.hp
  Ai.act(game, keeper)
  eq(keeper.x, 4, "an un-robbed shopkeeper does not move")
  eq(game.player.hp, hpBefore, "an un-robbed shopkeeper does not attack even when adjacent")
end

function tests.sellItemGrantsHalfPriceAndRemovesIt()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local index = #game.player.inventory
  local item = game.player.inventory[index]
  local expected = Shop.sellValue(item)
  local goldBefore = game.player.gold
  local value = game:sellItem(index)
  eq(value, expected, "selling returns the catalog half-price")
  eq(game.player.gold, goldBefore + expected, "the sale proceeds land in the wallet")
  eq(#game.player.inventory, index - 1, "the sold item leaves the inventory")
end

function tests.shopAndLooseGoldStayOffTheShallowFloors()
  for depth = 1, 3 do
    local level = Builder.build(depth, Rng.new(1), {})
    for _, ground in ipairs(level.floorItems) do
      ok(ground.item.kind ~= Items.GOLD, "no loose gold appears above depth 4")
      ok(not ground.price, "no shop ware appears above depth 4")
    end
    for _, e in ipairs(level.entities) do
      ok(e.species ~= "shopkeeper", "no shopkeeper appears above depth 4")
    end
  end
end

function tests.shopBuyIsMarkedUpWhenMerchantsAreHostile()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 100
  Factions.adjust(game.player, Factions.MERCHANT, -40)
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 78, "a hostile guild marks the stamped price up by half, floored")
end

function tests.shopBuyIsDiscountedWhenMerchantsAreHonored()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 100
  Factions.adjust(game.player, Factions.MERCHANT, 60)
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 91, "an honored guild discounts the stamped price, floored")
end

function tests.shopSellValueRisesWithMerchantStanding()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  game.player.inventory = { Items.potionOf("heal") }
  local goldBefore = game.player.gold
  Factions.adjust(game.player, Factions.MERCHANT, 60)
  local value = game:sellItem(1)
  eq(value, 10, "an honored guild pays more than the neutral half-price for the same ware")
  eq(game.player.gold, goldBefore + 10, "the sale proceeds land in the wallet")
end

function tests.shopPicksHaveAPositiveCatalogPrice()
  ok(Shop.priceOf(Items.pick()) > 0, "a miner's pick has a positive catalog price")
end

function tests.shopPriceOfAContractMatchesItsRosterHireCost()
  eq(Shop.priceOf(Items.contract("sellsword")), Mercenaries.byKey.sellsword.hireCost,
    "a contract's catalog price matches its roster hire cost")
end

function tests.shopStockCanRollAContractWithAPositiveCatalogPrice()
  local sawContract = false
  for seed = 1, 40 do
    for _, item in ipairs(Shop.stock(Rng.new(seed))) do
      if item.kind == Items.CONTRACT then
        sawContract = true
        ok(Shop.priceOf(item) > 0, "a rolled contract carries a positive catalog price")
        ok(Mercenaries.byKey[item.hireling] ~= nil, "a rolled contract names a real roster key")
      end
    end
  end
  ok(sawContract, "shop stock can roll a mercenary contract across a handful of seeds")
end

return tests
