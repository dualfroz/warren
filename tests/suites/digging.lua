local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Entity = require("entity")
local Items = require("items")
local Game = require("game")
local Digging = require("digging")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.diggingCanDigAllowsOnlyWallsAndRubble()
  local level = arena(21, 11)
  ok(Digging.canDig(level.map, 1, 5), "the arena's own border wall is diggable")
  ok(not Digging.canDig(level.map, 5, 5), "open floor has nothing left to dig")
  level.map:set(5, 5, Tiles.RUBBLE)
  ok(Digging.canDig(level.map, 5, 5), "rubble left by a prior swing is still diggable")
  level.map:set(5, 5, Tiles.VAULT_DOOR)
  ok(not Digging.canDig(level.map, 5, 5), "a vault's own boundary never yields to a pick")
  ok(not Digging.canDig(level.map, 0, 5), "a cell outside the map is never diggable")
end

function tests.diggingSwingClearsAWallToRubbleOnAnOrdinarySwing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 5, Tiles.WALL)
  game.rng = Rng.new(1)
  local line = Digging.swing(game, game.player, 5, 5)
  eq(game.level.map:get(5, 5), Tiles.RUBBLE, "an ordinary swing crumbles a wall to rubble, not clear")
  ok(contains(line, "carve"), "the log line describes carving through rock")
end

function tests.diggingSwingClearsRubbleToFloorOnASecondSwing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 5, Tiles.RUBBLE)
  game.rng = Rng.new(1)
  local line = Digging.swing(game, game.player, 5, 5)
  eq(game.level.map:get(5, 5), Tiles.FLOOR, "a second swing clears rubble the rest of the way to open floor")
  ok(contains(line, "clear"), "the log line describes clearing rubble away")
end

function tests.diggingSwingCaveInHurtsTheDiggerAndLeavesTheTileUntouched()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 5, Tiles.WALL)
  game.rng = Rng.new(6)
  local hpBefore = game.player.hp
  local line = Digging.swing(game, game.player, 5, 5)
  eq(game.level.map:get(5, 5), Tiles.WALL, "a cave-in wastes the swing; the wall is untouched")
  ok(game.player.hp < hpBefore, "a cave-in deals real damage to the digger")
  ok(contains(line, "buries you"), "the log line names the player directly, not by their entity name")
end

function tests.diggingSwingOreStrikeClearsTheWallOutrightAndPaysEssenceToATrackingDigger()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 5, Tiles.WALL)
  game.rng = Rng.new(2)
  local essenceBefore = game.player.essence
  local line = Digging.swing(game, game.player, 5, 5)
  eq(game.level.map:get(5, 5), Tiles.FLOOR, "a lucky ore strike clears the wall in a single stroke")
  ok(game.player.essence > essenceBefore, "striking a vein pays essence to a digger that tracks it")
  ok(contains(line, "essence"), "the log line reports the essence payout")
end

function tests.diggingSwingOreStrikeSkipsTheEssenceRewardForADiggerThatDoesNotTrackIt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 5, Tiles.WALL)
  local burrower = Entity.new({ id = 1, x = 4, y = 5, glyph = "b", name = "rock burrower", kind = "monster", hp = 12, attack = 4, defense = 2 })
  game.rng = Rng.new(2)
  local line = Digging.swing(game, burrower, 5, 5)
  eq(game.level.map:get(5, 5), Tiles.FLOOR, "the same lucky strike still clears the wall for a monster")
  eq(burrower.essence, nil, "a monster never gains an essence field it never had")
  ok(contains(line, "vein"), "the log line still names the vein even without a payout")
end

function tests.diggingWearPickDepletesDurabilityAndBreaksAtZero()
  local entity = { pick = Items.pick("test pick", 2) }
  eq(Digging.wearPick(entity), nil, "the first swing just wears the edge down")
  eq(entity.pick.uses, 1, "one use is spent")
  local brokenLine = Digging.wearPick(entity)
  ok(contains(brokenLine, "crumbles"), "the swing that empties the pick reports it breaking")
  eq(entity.pick, nil, "a spent pick is discarded outright")
end

function tests.diggingWearPickIsANoOpWithoutAPickEquipped()
  local entity = {}
  eq(Digging.wearPick(entity), nil, "wearing down a pick that was never equipped changes nothing")
end

function tests.diggingDirectionsTowardPrefersTheLongerAxisFirst()
  local dirs = Digging.directionsToward(10, 10, 15, 12)
  eq(#dirs, 2, "a diagonal target yields both an x and a y candidate")
  eq(dirs[1][1], 1, "the longer x delta is offered first")
  eq(dirs[1][2], 0, "the first candidate is a pure x step")
  eq(dirs[2][1], 0, "the second candidate is a pure y step")
  eq(dirs[2][2], 1, "it steps toward the smaller but still positive y delta")

  local vertical = Digging.directionsToward(10, 10, 11, 5)
  eq(vertical[1][1], 0, "when y dominates, the y step comes first")
  eq(vertical[1][2], -1, "stepping toward a smaller y is a negative step")
end

function tests.diggingDirectionsTowardOmitsAZeroDelta()
  local dirs = Digging.directionsToward(10, 10, 15, 10)
  eq(#dirs, 1, "a purely horizontal target yields only one candidate")
  eq(dirs[1][1], 1, "the sole candidate steps toward positive x")
  eq(dirs[1][2], 0, "the sole candidate carries no y component")

  local same = Digging.directionsToward(10, 10, 10, 10)
  eq(#same, 0, "already standing on the target yields no candidate at all")
end

function tests.gameDigFailsWithoutAPickEquipped()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(4, 6, Tiles.WALL)
  local moved = game:dig(1, 0)
  eq(moved, false, "digging without a pick equipped fails outright")
  eq(game.level.map:get(4, 6), Tiles.WALL, "the wall is untouched without a pick")
  ok(contains(game.log:last(), "nothing to dig with"), "the log explains why")
end

function tests.gameDigFailsWhenNothingAheadIsDiggable()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.pick = Items.pick()
  local moved = game:dig(1, 0)
  eq(moved, false, "there is nothing to dig into open floor")
  ok(contains(game.log:last(), "nothing here to dig"), "the log explains why")
end

function tests.gameDigClearsAWallAndWearsThePickDown()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(4, 6, Tiles.WALL)
  game.player.pick = Items.pick("miner's pick", 5)
  game.rng = Rng.new(1)
  local moved = game:dig(1, 0)
  eq(moved, true, "a swing against a wall with a pick readied succeeds")
  eq(game.level.map:get(4, 6), Tiles.RUBBLE, "the wall crumbles to rubble")
  eq(game.player.pick.uses, 4, "the swing spends one use of the pick's durability")
end

function tests.gameDigBreaksThePickOnItsLastUse()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(4, 6, Tiles.WALL)
  game.player.pick = Items.pick("worn pick", 1)
  game.rng = Rng.new(1)
  game:dig(1, 0)
  eq(game.player.pick, nil, "the pick's last use breaks it outright")
  ok(contains(game.log:last(), "crumbles"), "the log reports the pick breaking")
end

function tests.pickFieldSurvivesSerialization()
  local game = Game.new(3)
  game.player.pick = Items.pick("saved pick", 7)
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.pick.name, "saved pick", "the equipped pick's name survives a save/load round trip")
  eq(restored.player.pick.uses, 7, "the equipped pick's remaining durability survives a save/load round trip")
end

return tests
