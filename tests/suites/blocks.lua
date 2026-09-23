local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Entity = require("entity")
local Level = require("level")
local Builder = require("builder")
local Game = require("game")
local Blocks = require("blocks")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.blocksCanReceiveRefusesWallsDoorsVaultsGatesBlocksAndEntities()
  local level = arena(9, 9)
  level.map:set(4, 4, Tiles.WALL)
  eq(Blocks.canReceive(level, 4, 4), false, "a wall cannot receive a shoved block")
  level.map:set(4, 5, Tiles.DOOR_CLOSED)
  eq(Blocks.canReceive(level, 4, 5), false, "a closed door cannot receive a shoved block")
  level.map:set(4, 6, Tiles.VAULT_DOOR)
  eq(Blocks.canReceive(level, 4, 6), false, "a sealed vault door cannot receive a shoved block")
  level.map:set(4, 7, Tiles.GATE_CLOSED)
  eq(Blocks.canReceive(level, 4, 7), false, "a closed gate cannot receive a shoved block")
  level.blocks = { { x = 3, y = 3 } }
  eq(Blocks.canReceive(level, 3, 3), false, "a cell already holding another block cannot receive a shove")
  level.entities = { Entity.new({ x = 3, y = 4, glyph = "r", name = "rat", kind = "monster", hp = 5, attack = 1, defense = 0 }) }
  eq(Blocks.canReceive(level, 3, 4), false, "a cell occupied by a living entity cannot receive a shove")
  eq(Blocks.canReceive(level, 5, 5), true, "plain open floor can receive a shoved block")
  eq(Blocks.canReceive(level, 20, 20), false, "an out-of-bounds cell cannot receive a shove")
end

function tests.blocksPushRelocatesABlockOntoPlainFloor()
  local level = arena(9, 9)
  local block = { x = 3, y = 3 }
  level.blocks = { block }
  local pushed, line = Blocks.push(level, block, 1, 0)
  eq(pushed, true, "a shove onto open floor succeeds")
  eq(block.x, 4, "the block's own x relocates by the shove")
  eq(block.y, 3, "the block's own y is unchanged by a purely horizontal shove")
  ok(contains(line, "shove"), "a plain shove is logged as a shove")
end

function tests.blocksPushIntoLavaSolidifiesTheCellAndConsumesTheBlock()
  local level = arena(9, 9)
  level.map:set(4, 3, Tiles.LAVA)
  local block = { x = 3, y = 3 }
  level.blocks = { block }
  local pushed, line = Blocks.push(level, block, 1, 0)
  eq(pushed, true, "a shove into lava still succeeds")
  eq(level.map:get(4, 3), Tiles.RUBBLE, "the lava cell solidifies into rubble")
  eq(#level.blocks, 0, "the block is consumed by the lava it just quenched")
  ok(contains(line, "lava"), "quenching lava is logged")
end

function tests.blocksPushIntoAChasmFillsTheGapAndConsumesTheBlock()
  local level = arena(9, 9)
  level.map:set(4, 3, Tiles.CHASM)
  local block = { x = 3, y = 3 }
  level.blocks = { block }
  local pushed, line = Blocks.push(level, block, 1, 0)
  eq(pushed, true, "a shove into a chasm still succeeds")
  eq(level.map:get(4, 3), Tiles.FLOOR, "the chasm cell fills into plain floor")
  eq(#level.blocks, 0, "the block is consumed filling in the chasm")
  ok(contains(line, "chasm"), "filling a chasm is logged")
end

function tests.blocksPushFailsAgainstAWallOrAnotherBlockOrAnEntity()
  local level = arena(9, 9)
  level.map:set(4, 3, Tiles.WALL)
  local block = { x = 3, y = 3 }
  level.blocks = { block }
  eq(Blocks.push(level, block, 1, 0), false, "a shove into a wall fails outright")
  eq(block.x, 3, "a failed shove leaves the block exactly where it was")

  level.map:set(4, 3, Tiles.FLOOR)
  level.blocks = { block, { x = 4, y = 3 } }
  eq(Blocks.push(level, block, 1, 0), false, "a shove into another block fails outright")

  level.blocks = { block }
  level.entities = { Entity.new({ x = 4, y = 3, glyph = "r", name = "rat", kind = "monster", hp = 5, attack = 1, defense = 0 }) }
  eq(Blocks.push(level, block, 1, 0), false, "a shove into a living entity fails outright")
end

function tests.blocksUpdateGatesOpensOnlyWhileAPlatedBlockHoldsItAndReseals()
  local level = arena(9, 9)
  level.map:set(6, 3, Tiles.GATE_CLOSED)
  level.gates = { { x = 6, y = 3, open = false } }
  level.plates = { { x = 4, y = 3, gateX = 6, gateY = 3 } }
  local block = { x = 3, y = 3 }
  level.blocks = { block }
  Blocks.updateGates(level)
  eq(level.map:get(6, 3), Tiles.GATE_CLOSED, "the gate stays sealed with no block on its plate")
  eq(level.gates[1].open, false, "the gate's own open field matches its sealed tile")

  Blocks.push(level, block, 1, 0)
  Blocks.updateGates(level)
  eq(level.map:get(6, 3), Tiles.GATE_OPEN, "the gate swings open the instant its plate takes the block's weight")
  eq(level.gates[1].open, true, "the gate's own open field matches its opened tile")

  Blocks.push(level, block, 1, 0)
  Blocks.updateGates(level)
  eq(level.map:get(6, 3), Tiles.GATE_CLOSED, "the gate reseals the instant the block is shoved off its plate")
  eq(level.gates[1].open, false, "the gate's own open field matches its resealed tile")
end

function tests.movePlayerShovesABlockAheadAndTheGateItHoldsOpenReactsImmediately()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(6, 6, Tiles.GATE_CLOSED)
  game.level.gates = { { x = 6, y = 6, open = false } }
  game.level.plates = { { x = 5, y = 6, gateX = 6, gateY = 6 } }
  game.level.blocks = { { x = 4, y = 6 } }
  game:movePlayer(1, 0)
  eq(game.player.x, 4, "the player steps into the cell the block just vacated")
  eq(game.level.blocks[1].x, 5, "the shove relocates the block by exactly one cell")
  eq(game.level.blocks[1].y, 6, "the shove does not drift off the push axis")
  eq(game.level.map:get(6, 6), Tiles.GATE_OPEN, "the linked gate opens the instant the block lands on its plate")
  ok(contains(game.log:last(), "shove"), "shoving the block is logged")
end

function tests.movePlayerCannotShoveABlockIntoAWallAndDoesNotMoveEither()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 6, Tiles.WALL)
  game.level.blocks = { { x = 4, y = 6 } }
  local moved = game:movePlayer(1, 0)
  eq(moved, false, "the player's own step fails along with the blocked shove")
  eq(game.player.x, 3, "the player does not move when the shove it would trigger fails")
  eq(game.level.blocks[1].x, 4, "the block stays put when its shove fails")
end

function tests.movePlayerCannotShoveOneBlockIntoAnother()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.blocks = { { x = 4, y = 6 }, { x = 5, y = 6 } }
  local moved = game:movePlayer(1, 0)
  eq(moved, false, "shoving a block into another block fails the whole step")
  eq(game.player.x, 3, "the player does not move when the chained shove fails")
end

function tests.gatesAndBlocksStayOffFloorsAboveDepthTwo()
  for seed = 1, 4 do
    for depth = 1, 2 do
      local level = Builder.build(depth, Rng.new(seed), {})
      eq(#level.gates, 0, "no gate appears above depth three")
      eq(#level.blocks, 0, "no pushable block appears above depth three")
      eq(#level.plates, 0, "no pressure plate appears above depth three")
    end
  end
end

function tests.blockPlateAndGateFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.map:set(6, 6, Tiles.GATE_OPEN)
  level.blocks = { { x = 5, y = 5 } }
  level.plates = { { x = 4, y = 6, gateX = 6, gateY = 6 } }
  level.gates = { { x = 6, y = 6, open = true } }
  local restored = Level.fromData(level:toData())
  eq(#restored.blocks, 1, "the block list survives a round trip")
  eq(restored.blocks[1].x, 5, "a block's position survives a round trip")
  eq(#restored.plates, 1, "the plate list survives a round trip")
  eq(restored.plates[1].gateX, 6, "a plate's gate link survives a round trip")
  eq(#restored.gates, 1, "the gate list survives a round trip")
  eq(restored.gates[1].open, true, "a gate's open state survives a round trip")
end

function tests.gameBlockPuzzleStateSurvivesSaveLoad()
  local game = Game.new(1)
  local bx, by = game.player.x + 2, game.player.y
  game.level.map:set(bx + 1, by, Tiles.GATE_OPEN)
  game.level.blocks = { { x = bx, y = by } }
  game.level.plates = { { x = bx + 1, y = by, gateX = bx + 1, gateY = by } }
  game.level.gates = { { x = bx + 1, y = by, open = true } }
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(#restored.level.blocks, 1, "the block list survives a save/load round trip")
  eq(restored.level.blocks[1].x, bx, "a block's position survives a save/load round trip")
  eq(restored.level.gates[1].open, true, "a gate's open state survives a save/load round trip")
end

return tests
