local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Items = require("items")
local Monsters = require("monsters")
local Level = require("level")
local Builder = require("builder")
local Companions = require("companions")
local Branches = require("branches")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.branchesSeedForIsDeterministicAndVariesWithEitherInput()
  eq(Branches.seedFor(42, 6), Branches.seedFor(42, 6), "the same world seed and depth always derive the same rift seed")
  ok(Branches.seedFor(42, 6) ~= Branches.seedFor(42, 7), "a different origin depth derives a different rift seed")
  ok(Branches.seedFor(42, 6) ~= Branches.seedFor(43, 6), "a different world seed derives a different rift seed")
end

function tests.branchesBuildIsDeterministicAndGeneratesDeeperThanItsOrigin()
  local a = Branches.build(11, 6, {})
  local b = Branches.build(11, 6, {})
  eq(table.concat(a.map.tiles), table.concat(b.map.tiles),
    "the same world seed and origin depth always build the same pocket floor")
  eq(a.depth, 6 + Branches.DEPTH_BONUS, "a pocket floor is generated at its origin depth plus the fixed bonus")
  local c = Branches.build(11, 7, {})
  ok(table.concat(a.map.tiles) ~= table.concat(c.map.tiles), "a different origin depth builds a different pocket floor")
end

function tests.branchesBuildNeverPlacesAChasmOrTheWinningAmulet()
  for seed = 1, 6 do
    for depth = 6, 10 do
      local level = Branches.build(seed, depth, {})
      for _, glyph in ipairs(level.map.tiles) do
        ok(glyph ~= Tiles.CHASM, "a pocket floor never generates a chasm with nowhere lower to fall")
      end
      for _, ground in ipairs(level.floorItems) do
        ok(ground.item.kind ~= Items.AMULET, "a pocket floor never generates the winning amulet")
      end
    end
  end
end

function tests.riftsAndShardsStayOffFloorsAboveTheirOwnThreshold()
  for seed = 1, 6 do
    for depth = 1, 3 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        ok(ground.item.kind ~= Items.RIFTSTONE, "no rift shard appears above depth 4")
      end
    end
    for depth = 1, 5 do
      local level = Builder.build(depth, Rng.new(seed), {})
      eq(#level.rifts, 0, "no rift appears above depth 6")
    end
  end
end

function tests.riftFieldsSurviveALevelSerializationRoundTrip()
  local level = arena(21, 11)
  level.rifts = { { x = 6, y = 5 } }
  eq(level:riftAt(6, 5), level.rifts[1], "Level:riftAt finds the rift by position")
  ok(level:riftAt(1, 1) == nil, "Level:riftAt finds nothing off-position")
  local restored = Level.fromData(level:toData())
  eq(#restored.rifts, 1, "a rift survives a level round trip")
  eq(restored.rifts[1].x, 6, "the rift's position survives a round trip")
  eq(restored:riftAt(6, 5), restored.rifts[1], "Level:riftAt finds the restored rift by position")
end

function tests.gameEnterRiftFailsWithoutARiftUnderfootOrWithoutAShard()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:enterRift(), "entering fails with no rift on the current cell")
  game.level.rifts = { { x = 5, y = 5 } }
  ok(not game:enterRift(), "a first crossing fails without a carried shard")
  eq(game.rift or false, false, "a failed crossing never sets the rift flag")
end

function tests.gameEnterRiftSpendsTheShardAndSwapsToTheCachedPocketFloor()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.rifts = { { x = 5, y = 5 } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  local invBefore = #game.player.inventory
  local mainLevel = game.level
  ok(game:enterRift(), "entering a rift underfoot with a shard in hand succeeds")
  eq(#game.player.inventory, invBefore - 1, "the shard is spent on the first crossing")
  eq(game.rift, true, "the rift flag is set while across a crossing")
  eq(game.level.depth, game.depth + Branches.DEPTH_BONUS, "the pocket floor is generated deeper than the origin")
  eq(game.player.x, game.level.upX, "the player lands on the pocket floor's own entry point")
  eq(game.player.y, game.level.upY, "the player lands on the pocket floor's own entry point")
  ok(game.riftReturn ~= nil, "a return point is remembered")
  eq(game.riftReturn.level, mainLevel, "the return point remembers the exact main-track level object")
end

function tests.gameDescendAndAscendAreBothBlockedWhileAcrossARift()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.rifts = { { x = 5, y = 5 } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  game:enterRift()
  local depthBefore, levelBefore = game.depth, game.level
  game.player.x, game.player.y = game.level.downX, game.level.downY
  ok(not game:descend(), "descend refuses to fire while the player is across a rift")
  game.player.x, game.player.y = game.level.upX, game.level.upY
  ok(not game:ascend(), "ascend refuses to fire while the player is across a rift")
  eq(game.depth, depthBefore, "depth is untouched by either refusal")
  eq(game.level, levelBefore, "the active level is untouched by either refusal")
end

function tests.gameExitRiftRestoresTheExactMainTrackLevelDepthAndPosition()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local mainLevel = game.level
  game.level.rifts = { { x = 5, y = 5 } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  game:enterRift()
  ok(not game:exitRift(), "exiting fails before the player reaches the pocket floor's own exit")
  game.player.x, game.player.y = game.level.downX, game.level.downY
  ok(game:exitRift(), "exiting at the pocket floor's own exit point succeeds")
  eq(game.rift, false, "the rift flag clears on exit")
  eq(game.riftReturn, nil, "the return point is cleared once used")
  eq(game.level, mainLevel, "the exact original level object is restored, not a rebuilt copy")
  eq(game.depth, 1, "the origin depth is restored")
  eq(game.player.x, 5, "the player's exact departure position is restored")
  eq(game.player.y, 5, "the player's exact departure position is restored")
end

function tests.gameReenteringAStabilizedRiftNeverSpendsASecondShard()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.rifts = { { x = 5, y = 5 } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  game:enterRift()
  local pocketLevel = game.level
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:exitRift()
  local invBefore = #game.player.inventory
  game:enterRift()
  eq(game.level, pocketLevel, "re-entering the same rift restores the exact cached pocket floor")
  eq(#game.player.inventory, invBefore, "re-entering an already-stabilized rift spends no second shard")
end

function tests.gameRiftPocketFloorPersistsStateAcrossALeaveAndReturn()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.rifts = { { x = 5, y = 5 } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  game:enterRift()
  local orc = Monsters.create(Monsters.byKey.orc, 1, game.level.upX, game.level.upY, game.level.depth)
  orc.hp = 0
  game.level.entities = { orc }
  game.player.x, game.player.y = game.level.downX, game.level.downY
  game:exitRift()
  game.player.x, game.player.y = 5, 5
  game:enterRift()
  eq(game.level.entities[1].hp, 0, "the pocket floor remembers a monster killed on an earlier crossing")
end

function tests.gameEnterRiftAndExitRiftBothCarryALivingCompanionAcrossTheCrossing()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.rifts = { { x = 5, y = 5 } }
  game.player.inventory[#game.player.inventory + 1] = Items.riftstone()
  local mainLevel = game.level
  local golem = Companions.summon(game, "golem")
  ok(golem ~= nil, "the companion bonds before crossing")

  ok(game:enterRift(), "entering the rift succeeds with a shard in hand")
  eq(game.rift, true, "the game is now across the rift")
  ok(game:hasCompanion(), "the companion crosses into the rift's pocket floor too")
  local strandedOnMain = 0
  for _, entity in ipairs(mainLevel.entities) do
    if entity.kind == "companion" then strandedOnMain = strandedOnMain + 1 end
  end
  eq(strandedOnMain, 0, "the companion is not left stranded on the main-track floor")

  game.player.x, game.player.y = game.level.downX, game.level.downY
  local pocketLevel = game.level
  ok(game:exitRift(), "exiting the rift succeeds at its own downstairs")
  eq(game.rift, false, "back on the main track")
  ok(game:hasCompanion(), "the companion follows back out of the rift as well")
  local strandedInPocket = 0
  for _, entity in ipairs(pocketLevel.entities) do
    if entity.kind == "companion" then strandedInPocket = strandedInPocket + 1 end
  end
  eq(strandedInPocket, 0, "the companion is not left stranded on the pocket floor either")
end

return tests
