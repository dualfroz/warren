local helpers = require("helpers")
local Rng = require("rng")
local Items = require("items")
local Level = require("level")
local Chests = require("chests")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.chestsNewLootAlwaysIncludesGoldAndExactlyOneGearPiece()
  for seed = 1, 30 do
    local chest = Chests.new(Rng.new(seed), 3)
    local goldCount, gearCount = 0, 0
    for _, item in ipairs(chest.loot) do
      if item.kind == Items.GOLD then goldCount = goldCount + 1 end
      if item.kind == Items.WEAPON or item.kind == Items.ARMOR then gearCount = gearCount + 1 end
    end
    eq(goldCount, 1, "every chest carries exactly one pile of gold")
    eq(gearCount, 1, "every chest carries exactly one weapon or armor piece")
  end
end

function tests.chestsNewNeverRollsTrappedOnAnUnlockedChest()
  local sawLockedTrapped, sawLockedUntrapped = false, false
  for seed = 1, 100 do
    local chest = Chests.new(Rng.new(seed), 3)
    ok(chest.locked or not chest.trapped, "an unlocked chest is never also trapped")
    if chest.locked and chest.trapped then sawLockedTrapped = true end
    if chest.locked and not chest.trapped then sawLockedUntrapped = true end
  end
  ok(sawLockedTrapped, "a locked chest eventually rolls trapped across a handful of seeds")
  ok(sawLockedUntrapped, "a locked chest eventually rolls untrapped across a handful of seeds")
end

function tests.chestsIsLockedIsTrueForALockedUnopenedChestAndFalseOnceOpened()
  local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  eq(Chests.isLocked(chest), true, "a locked, unopened chest reports locked")
  chest.opened = true
  eq(Chests.isLocked(chest), false, "an opened chest never reports locked, whatever its own flag says")
end

function tests.chestsOpenGrantsEveryLootItemAndEmptiesTheChest()
  local player = { inventory = {} }
  local chest = { locked = false, trapped = false, opened = false, loot = { Items.gold(5), Items.potionOf("heal") } }
  local success, line = Chests.open(player, chest)
  ok(success, "opening an unlocked chest succeeds")
  eq(#player.inventory, 2, "every loot item lands in the inventory")
  eq(chest.opened, true, "the chest is marked opened")
  eq(#chest.loot, 0, "the chest's own loot list is emptied")
  ok(contains(line, "open"), "the opening is reported")
end

function tests.chestsOpenRefusesAnAlreadyEmptiedChest()
  local player = { inventory = {} }
  local chest = { locked = false, trapped = false, opened = true, loot = {} }
  local success, line = Chests.open(player, chest)
  eq(success, false, "opening an already-emptied chest fails")
  eq(#player.inventory, 0, "nothing is granted from an already-emptied chest")
  ok(contains(line, "empty"), "the refusal explains the chest is already empty")
end

function tests.chestsOpenRefusesALockedChestAndLeavesItsLootUntouched()
  local player = { inventory = {} }
  local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  local success, line = Chests.open(player, chest)
  eq(success, false, "opening a locked chest outright fails")
  eq(#player.inventory, 0, "a refused open grants nothing")
  eq(#chest.loot, 1, "a refused open leaves the chest's loot untouched")
  ok(contains(line, "locked"), "the refusal explains the chest is locked")
end

function tests.chestsUnlockWithKeySpendsExactlyOneKeyAndGrantsTheHoard()
  local player = { inventory = { Items.key(), Items.key() } }
  local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  local success, line = Chests.unlockWithKey(player, chest)
  ok(success, "unlocking with a carried key succeeds")
  eq(#player.inventory, 2, "exactly one key is spent, leaving the spare behind")
  eq(player.inventory[1].kind, Items.KEY, "the surviving inventory item is still a key")
  eq(chest.locked, false, "the chest's own lock flag is cleared")
  eq(chest.opened, true, "the chest is opened in the same stroke")
  ok(contains(line, "unlock"), "the unlock is reported")
end

function tests.chestsUnlockWithKeyFailsWithoutAKeyAndLeavesTheChestLocked()
  local player = { inventory = {} }
  local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  local success, line = Chests.unlockWithKey(player, chest)
  eq(success, false, "unlocking without a key fails")
  eq(chest.locked, true, "the chest stays locked")
  eq(#chest.loot, 1, "nothing is granted without a key")
  ok(contains(line, "no key"), "the refusal explains there is no key")
end

function tests.chestsUnlockWithKeyRefusesAChestThatIsNotLocked()
  local player = { inventory = { Items.key() } }
  local chest = { locked = false, trapped = false, opened = false, loot = { Items.gold(5) } }
  local success = Chests.unlockWithKey(player, chest)
  eq(success, false, "a key is never spent forcing a lock that was never there")
  eq(#player.inventory, 1, "the key is not spent")
end

function tests.chestsPickFailsImmediatelyWithoutALockpickAndSpendsNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  local success, line = Chests.pick(game, chest)
  eq(success, false, "picking without a lockpick fails")
  eq(chest.locked, true, "the lock is untouched without a lockpick")
  eq(#chest.loot, 1, "nothing is granted without a lockpick")
  ok(contains(line, "no lockpicks"), "the refusal explains there are no lockpicks")
end

function tests.chestsPickOnSuccessOpensTheChestAndGrantsTheHoard()
  local succeeded = false
  for seed = 1, 100 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    game.player.inventory = { Items.lockpick() }
    local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
    local success, line = Chests.pick(game, chest)
    if success then
      eq(chest.opened, true, "a successful pick opens the chest")
      eq(#game.player.inventory, 1, "the hoard lands in the inventory alongside the spent pick's empty slot")
      ok(contains(line, "click"), "the success is reported")
      succeeded = true
      break
    end
  end
  ok(succeeded, "picking eventually succeeds across a handful of seeds")
end

function tests.chestsPickAlwaysSpendsTheLockpickWhetherItWinsOrLoses()
  for seed = 1, 20 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    game.player.inventory = { Items.lockpick() }
    local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
    Chests.pick(game, chest)
    local stillHasPick = false
    for _, item in ipairs(game.player.inventory) do
      if item.kind == Items.LOCKPICK then stillHasPick = true end
    end
    ok(not stillHasPick, "a pick attempt spends the lockpick regardless of outcome")
  end
end

function tests.chestsPickOnFailureAgainstATrappedChestSpringsItAndLeavesTheLockStanding()
  local failed = false
  for seed = 1, 100 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    game.player.inventory = { Items.lockpick() }
    local chest = { locked = true, trapped = true, opened = false, loot = { Items.gold(5) } }
    local hpBefore, poisonBefore = game.player.hp, #game.player.statuses
    local success, line = Chests.pick(game, chest)
    if not success then
      eq(chest.locked, true, "a failed pick leaves the lock standing")
      eq(chest.trapped, false, "a sprung trap is spent for good")
      ok(game.player.hp < hpBefore or #game.player.statuses > poisonBefore,
        "a trapped chest's failed pick actually harms the player")
      ok(contains(line, "trap") or contains(line, "poison") or contains(line, "needle"),
        "the trap's bite is reported")
      failed = true
      break
    end
  end
  ok(failed, "picking a trapped chest eventually fails across a handful of seeds")
end

function tests.chestsPickOnFailureAgainstAnUntrappedChestJustWastesThePick()
  local failed = false
  for seed = 1, 100 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    game.player.inventory = { Items.lockpick() }
    local chest = { locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
    local hpBefore = game.player.hp
    local success, line = Chests.pick(game, chest)
    if not success then
      eq(chest.locked, true, "a failed pick leaves the lock standing")
      eq(game.player.hp, hpBefore, "an untrapped chest's failed pick costs nothing but the pick itself")
      ok(contains(line, "slips"), "the failure is reported")
      failed = true
      break
    end
  end
  ok(failed, "picking an untrapped chest eventually fails across a handful of seeds")
end

function tests.chestsOddsForClimbsWithLevelButNeverReachesTheDenominator()
  local num1, den1 = Chests.oddsFor({ level = 1 })
  eq(num1, Chests.PICK_BASE_NUMERATOR, "a fresh level-one player rolls the catalog's base odds")
  local num2, den2 = Chests.oddsFor({ level = 100 })
  eq(den2, den1, "the denominator never changes with level")
  ok(num2 < den2, "even an extremely high level never reaches a guaranteed pick")
  eq(num2, Chests.PICK_BASE_DENOMINATOR - 1, "the numerator caps a single point shy of the denominator")
end

function tests.gameOpenChestOpensAnUnlockedChestOnSightAndCountsIt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chest = { x = 3, y = 6, locked = false, trapped = false, opened = false, loot = { Items.gold(5) } }
  game.level.chests = { chest }
  local before = game.stats.chestsOpened
  local success = game:openChest()
  ok(success, "opening an unlocked chest under the player succeeds")
  eq(chest.opened, true, "the chest is marked opened")
  eq(game.stats.chestsOpened, before + 1, "a successful open is tallied for meta scoring")
end

function tests.gameOpenChestUnlocksWithACarriedKeyBeforeEverTryingALockpick()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chest = { x = 3, y = 6, locked = true, trapped = true, opened = false, loot = { Items.gold(5) } }
  game.level.chests = { chest }
  game.player.inventory = { Items.key(), Items.lockpick() }
  local success = game:openChest()
  ok(success, "opening a locked chest with a key on hand succeeds")
  eq(chest.opened, true, "the chest opens")
  local stillHasPick, stillHasKey = false, false
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.LOCKPICK then stillHasPick = true end
    if item.kind == Items.KEY then stillHasKey = true end
  end
  ok(stillHasPick, "the lockpick is never touched once a key is on hand")
  ok(not stillHasKey, "the key is the one actually spent")
end

function tests.gameOpenChestFallsBackToALockpickWhenNoKeyIsCarried()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chest = { x = 3, y = 6, locked = true, trapped = false, opened = false, loot = { Items.gold(5) } }
  game.level.chests = { chest }
  game.player.inventory = { Items.lockpick() }
  game:openChest()
  local stillHasPick = false
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.LOCKPICK then stillHasPick = true end
  end
  ok(not stillHasPick, "the lockpick is spent gambling against the lock with no key on hand")
end

function tests.gameOpenChestRefusesWhenNothingIsHereOrItIsAlreadyEmpty()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.chests = {}
  eq(game:openChest(), false, "opening with no chest underfoot fails")
  local chest = { x = 3, y = 6, locked = false, trapped = false, opened = true, loot = {} }
  game.level.chests = { chest }
  eq(game:openChest(), false, "opening an already-emptied chest fails")
end

function tests.chestsFieldsSurviveSerialization()
  local level = arena(21, 11)
  local chest = Chests.new(Rng.new(4), 3)
  chest.x, chest.y = 5, 5
  chest.locked = true
  chest.trapped = true
  level.chests = { chest }
  local restored = Level.fromData(level:toData())
  eq(#restored.chests, 1, "the chest list survives a round trip")
  eq(restored.chests[1].locked, true, "a chest's locked flag survives a round trip")
  eq(restored.chests[1].trapped, true, "a chest's trapped flag survives a round trip")
  eq(restored.chests[1].opened, false, "a chest's opened flag survives a round trip")
  eq(#restored.chests[1].loot, #chest.loot, "a chest's loot list survives a round trip intact")
  eq(restored.chests[1].loot[1].kind, chest.loot[1].kind, "a chest's loot items keep their own kind")
end

return tests
