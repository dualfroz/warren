local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Items = require("items")
local Level = require("level")
local Builder = require("builder")
local Game = require("game")
local Vaults = require("vaults")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.vaultsPullThrowsALeverAndOpensASingleLeverVaultImmediately()
  local level = { vaultLevers = {}, vaultDoors = {} }
  local lever = { x = 1, y = 1, id = "v1", pulled = false }
  level.vaultLevers = { lever }
  level.vaultDoors = { { x = 2, y = 2, id = "v1", opened = false } }
  local pulled, door = Vaults.pull(level, lever)
  eq(pulled, true, "pulling a fresh lever succeeds")
  eq(lever.pulled, true, "the lever is marked pulled")
  ok(door ~= nil, "a single-lever vault's door opens on its only pull")
  eq(door.id, "v1", "the returned door is the one this puzzle actually gates")
  local pulledAgain, doorAgain = Vaults.pull(level, lever)
  eq(pulledAgain, false, "pulling an already-thrown lever reports failure")
  eq(doorAgain, nil, "a no-op pull reports no door")
end

function tests.vaultsPullOpensTheDoorOnlyOnceEveryLeverIsThrown()
  local level = { vaultLevers = {}, vaultDoors = {} }
  local leverA = { x = 1, y = 1, id = "v2", pulled = false }
  local leverB = { x = 1, y = 2, id = "v2", pulled = false }
  level.vaultLevers = { leverA, leverB }
  level.vaultDoors = { { x = 3, y = 3, id = "v2", opened = false } }
  local pulledA, doorA = Vaults.pull(level, leverA)
  eq(pulledA, true, "pulling the first of two levers succeeds")
  eq(doorA, nil, "the door stays shut until every lever sharing its id is thrown")
  local pulledB, doorB = Vaults.pull(level, leverB)
  eq(pulledB, true, "pulling the second lever succeeds")
  ok(doorB ~= nil, "the door opens the instant the last lever is thrown")
end

function tests.vaultsTreasureRollsAGuaranteedAffixOnABaseStrongerThanAnyFloorDrop()
  for seed = 1, 20 do
    local item = Vaults.treasure(Rng.new(seed), 5)
    ok(item.kind == Items.WEAPON or item.kind == Items.ARMOR,
      "vault treasure is always a weapon or a suit of armor")
    ok(item.affix ~= nil, "vault treasure always carries a guaranteed affix")
    ok(item.power >= 7, "vault treasure's power exceeds anything the depth-5 floor loot table can roll")
  end
end

function tests.gamePullLeverOpensASingleLeverVaultAndTracksTheStat()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(6, 6, Tiles.LEVER)
  game.level.map:set(10, 6, Tiles.VAULT_DOOR)
  local lever = { x = 6, y = 6, id = "v3", pulled = false }
  game.level.vaultLevers = { lever }
  game.level.vaultDoors = { { x = 10, y = 6, id = "v3", opened = false } }
  eq(game.stats.vaultsOpened, 0, "a fresh run has opened no vaults")
  local pulled = game:pullLever(lever)
  eq(pulled, true, "pulling the lever succeeds")
  eq(game.level.map:get(6, 6), Tiles.LEVER_PULLED, "the lever's own tile flips to its pulled glyph")
  eq(game.level.map:get(10, 6), Tiles.DOOR_OPEN, "the vault door swings open once its only lever is thrown")
  eq(game.stats.vaultsOpened, 1, "opening a vault advances the run's vault tally")
  ok(contains(game.log:last(), "grinds open"), "opening the vault is logged")
end

function tests.gamePullLeverOnATwoLeverVaultWaitsForTheSecondPull()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(6, 6, Tiles.LEVER)
  game.level.map:set(7, 6, Tiles.LEVER)
  game.level.map:set(10, 6, Tiles.VAULT_DOOR)
  local leverA = { x = 6, y = 6, id = "v4", pulled = false }
  local leverB = { x = 7, y = 6, id = "v4", pulled = false }
  game.level.vaultLevers = { leverA, leverB }
  game.level.vaultDoors = { { x = 10, y = 6, id = "v4", opened = false } }
  game:pullLever(leverA)
  eq(game.level.map:get(10, 6), Tiles.VAULT_DOOR, "the door stays sealed with a lever still unthrown")
  eq(game.stats.vaultsOpened, 0, "the vault tally does not advance until the puzzle is fully solved")
  ok(contains(game.log:last(), "clunks into place"), "a partial pull is logged as a clunk, not an opening")
  game:pullLever(leverB)
  eq(game.level.map:get(10, 6), Tiles.DOOR_OPEN, "the door opens the instant the last lever is thrown")
  eq(game.stats.vaultsOpened, 1, "the vault tally advances exactly once, on the pull that completes the puzzle")
end

function tests.pullingAnAlreadyThrownLeverAgainDoesNotInflateTheVaultTally()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(6, 6, Tiles.LEVER)
  game.level.map:set(10, 6, Tiles.VAULT_DOOR)
  local lever = { x = 6, y = 6, id = "v5", pulled = false }
  game.level.vaultLevers = { lever }
  game.level.vaultDoors = { { x = 10, y = 6, id = "v5", opened = false } }
  game:pullLever(lever)
  eq(game.stats.vaultsOpened, 1, "the first pull opens the vault")
  local pulledAgain = game:pullLever(lever)
  eq(pulledAgain, false, "re-pulling an already-thrown lever reports failure")
  eq(game.stats.vaultsOpened, 1, "re-pulling an already-thrown lever does not inflate the vault tally")
end

function tests.movePlayerAutoPullsALeverItStepsOnto()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.map:set(6, 5, Tiles.LEVER)
  local lever = { x = 6, y = 5, id = "v6", pulled = false }
  game.level.vaultLevers = { lever }
  game.level.vaultDoors = { { x = 15, y = 5, id = "v6", opened = false } }
  game:movePlayer(1, 0)
  eq(game.player.x, 6, "the player actually steps onto the lever's cell")
  eq(lever.pulled, true, "stepping onto a lever automatically throws it")
end

function tests.vaultDoorBlocksMovementUntilItsLeversOpenIt()
  local game = stagedGame(1, arena(21, 11), 9, 5)
  game.level.map:set(10, 5, Tiles.VAULT_DOOR)
  local moved = game:movePlayer(1, 0)
  eq(moved, false, "an unopened vault door blocks the step onto it")
  eq(game.player.x, 9, "the player does not pass through a sealed vault door")
  game.level.map:set(10, 5, Tiles.DOOR_OPEN)
  local movedAfter = game:movePlayer(1, 0)
  eq(movedAfter, true, "once opened, the door's tile behaves like any plain open door")
  eq(game.player.x, 10, "the player steps onto the formerly sealed cell")
end

function tests.vaultsStayOffFloorsAboveDepthFive()
  for seed = 1, 4 do
    for depth = 1, 4 do
      local level = Builder.build(depth, Rng.new(seed), {})
      eq(#level.vaultDoors, 0, "no vault door appears above depth five")
      eq(#level.vaultLevers, 0, "no vault lever appears above depth five")
    end
  end
end

function tests.vaultFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.map:set(6, 6, Tiles.LEVER_PULLED)
  level.map:set(10, 6, Tiles.DOOR_OPEN)
  level.vaultLevers = { { x = 6, y = 6, id = "v7", pulled = true } }
  level.vaultDoors = { { x = 10, y = 6, id = "v7", opened = true } }
  local restored = Level.fromData(level:toData())
  eq(#restored.vaultLevers, 1, "the vault lever list survives a round trip")
  eq(restored.vaultLevers[1].pulled, true, "a lever's pulled state survives a round trip")
  eq(#restored.vaultDoors, 1, "the vault door list survives a round trip")
  eq(restored.vaultDoors[1].opened, true, "a door's opened state survives a round trip")
end

function tests.gameVaultsOpenedStatSurvivesSaveLoad()
  local game = Game.new(1)
  local lx, ly = game.player.x + 1, game.player.y
  game.level.map:set(lx, ly, Tiles.LEVER)
  local lever = { x = lx, y = ly, id = "v8", pulled = false }
  game.level.vaultLevers = { lever }
  game.level.vaultDoors = { { x = game.player.x + 2, y = game.player.y, id = "v8", opened = false } }
  game:pullLever(lever)
  eq(game.stats.vaultsOpened, 1, "pulling the lever opens the vault")
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.stats.vaultsOpened, 1, "the vault-opened tally survives a save/load round trip")
  eq(#restored.level.vaultLevers, 1, "the level's vault lever list survives a save/load round trip")
  eq(restored.level.vaultLevers[1].pulled, true, "a pulled lever's state survives a save/load round trip")
end

return tests
