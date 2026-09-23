local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Map = require("map")
local Gen = require("gen.init")
local Connect = require("gen.connect")
local Level = require("level")
local Dungeon = require("dungeon")
local Builder = require("builder")
local Prefab = require("gen.prefab")

local ok, eq, arena = helpers.ok, helpers.eq, helpers.arena

local tests = helpers.suite()

function tests.generators()
  for _, name in ipairs(Gen.order) do
    local m1, reach1 = Gen.build(name, 60, 24, Rng.new(2024))
    local m2 = Gen.build(name, 60, 24, Rng.new(2024))
    eq(table.concat(m1.tiles), table.concat(m2.tiles), name .. " is deterministic")
    local other = Gen.build(name, 60, 24, Rng.new(2025))
    ok(table.concat(m1.tiles) ~= table.concat(other.tiles), name .. " differs across seeds")
    local walkable = 0
    for y = 1, m1.height do for x = 1, m1.width do if m1:isWalkable(x, y) then walkable = walkable + 1 end end end
    ok(walkable > 0, name .. " carves open floor")
    eq(#reach1, walkable, name .. " leaves every floor cell reachable")
  end
end

function tests.mazeGeneratorIsDeterministicDiffersAcrossSeedsAndLeavesEveryFloorCellReachable()
  local m1, reach1 = Gen.build("maze", 60, 24, Rng.new(2024))
  local m2 = Gen.build("maze", 60, 24, Rng.new(2024))
  eq(table.concat(m1.tiles), table.concat(m2.tiles), "maze is deterministic")
  local other = Gen.build("maze", 60, 24, Rng.new(2025))
  ok(table.concat(m1.tiles) ~= table.concat(other.tiles), "maze differs across seeds")
  local walkable = 0
  for y = 1, m1.height do for x = 1, m1.width do if m1:isWalkable(x, y) then walkable = walkable + 1 end end end
  ok(walkable > 0, "maze carves open floor")
  eq(#reach1, walkable, "maze leaves every floor cell reachable without gen.connect stitching anything extra")
end

function tests.mazeGeneratorIsRegisteredButExcludedFromTheDepthCycle()
  ok(Gen.has("maze"), "maze is a selectable generator")
  local found = false
  for _, name in ipairs(Gen.order) do
    if name == "maze" then found = true end
  end
  ok(not found, "maze is deliberately absent from the auto-cycled depth order")
end

function tests.mazeGeneratorProducesOneWideCorridorsRatherThanOpenRooms()
  local map = Gen.generators.maze(60, 24, Rng.new(7), { braidNumerator = 0, braidDenominator = 1 })
  local openTwoByTwoBlocks = 0
  for y = 2, map.height - 2 do
    for x = 2, map.width - 2 do
      if map:isWalkable(x, y) and map:isWalkable(x + 1, y)
        and map:isWalkable(x, y + 1) and map:isWalkable(x + 1, y + 1) then
        openTwoByTwoBlocks = openTwoByTwoBlocks + 1
      end
    end
  end
  eq(openTwoByTwoBlocks, 0, "a maze never opens a 2x2 block of floor the way a room-based generator does")
end

function tests.mazeGeneratorBraidingOpensSomeDeadEndsWithoutTouchingConnectivity()
  local braided = Gen.generators.maze(60, 24, Rng.new(3), { braidNumerator = 1, braidDenominator = 1 })
  local unbraided = Gen.generators.maze(60, 24, Rng.new(3), { braidNumerator = 0, braidDenominator = 1 })
  local function walkableCount(map)
    local total = 0
    for y = 1, map.height do for x = 1, map.width do if map:isWalkable(x, y) then total = total + 1 end end end
    return total
  end
  ok(walkableCount(braided) > walkableCount(unbraided), "raising the braid odds opens strictly more floor")
  local reachable = Connect.ensure(unbraided, Rng.new(3))
  eq(#reachable, walkableCount(unbraided), "an unbraided perfect maze is already fully connected on its own")
end

function tests.prefabVaultSizeMatchesItsWidestRowAndItsRowCount()
  local vault = { rows = { "####", "#..#", "####" } }
  local w, h = Prefab.size(vault)
  eq(w, 4, "size reports the width of a template row")
  eq(h, 3, "size reports the number of template rows")
end

function tests.prefabVaultFitsAcceptsAnAnchorWithAWallGapToEveryBorderAndRejectsOneWithout()
  local map = Map.new(20, 15)
  local vault = { rows = { "###", "#.#", "###" } }
  ok(Prefab.fits(map, vault, 2, 2), "an anchor two cells in on every side leaves a wall gap to the border")
  ok(not Prefab.fits(map, vault, 1, 2), "an anchor flush against the west border is rejected")
  ok(not Prefab.fits(map, vault, 2, 1), "an anchor flush against the north border is rejected")
  local w, h = Prefab.size(vault)
  ok(not Prefab.fits(map, vault, map.width - w + 2, 2), "an anchor that spills past the east border is rejected")
  ok(not Prefab.fits(map, vault, 2, map.height - h + 2), "an anchor that spills past the south border is rejected")
end

function tests.prefabVaultStampWritesEveryGlyphAndCollectsTreasureMonsterAndLootMarkersInMapOrder()
  local map = Map.new(20, 15)
  local vault = {
    name = "testVault",
    rows = {
      "#####",
      "#*M+#",
      "#.L.#",
      "#####",
    },
  }
  local result = Prefab.stamp(map, vault, 3, 4)
  eq(result.name, "testVault", "the stamp result remembers the template's own name")
  eq(map:get(3, 4), Tiles.WALL, "a '#' glyph becomes a wall tile")
  eq(map:get(4, 5), Tiles.FLOOR, "a '*' treasure marker still becomes walkable floor")
  eq(map:get(5, 5), Tiles.FLOOR, "an 'M' monster marker still becomes walkable floor")
  eq(map:get(6, 5), Tiles.DOOR_CLOSED, "a '+' glyph becomes a closed door")
  eq(map:get(5, 6), Tiles.FLOOR, "an 'L' loot marker still becomes walkable floor")
  eq(#result.treasure, 1, "exactly one treasure anchor is collected")
  eq(result.treasure[1].x, 4, "the treasure anchor's x is offset by the stamp's own anchor")
  eq(result.treasure[1].y, 5, "the treasure anchor's y is offset by the stamp's own anchor")
  eq(#result.monsters, 1, "exactly one monster anchor is collected")
  eq(result.monsters[1].x, 5, "the monster anchor's x is offset by the stamp's own anchor")
  eq(#result.loot, 1, "exactly one loot anchor is collected")
  eq(result.loot[1].x, 5, "the loot anchor's x is offset by the stamp's own anchor")
  eq(result.loot[1].y, 6, "the loot anchor's y is offset by the stamp's own anchor")
end

function tests.prefabVaultStampIsDeterministicForAFixedAnchor()
  local vault = Prefab.vaults[1]
  local m1, m2 = Map.new(20, 15), Map.new(20, 15)
  Prefab.stamp(m1, vault, 3, 3)
  Prefab.stamp(m2, vault, 3, 3)
  eq(table.concat(m1.tiles), table.concat(m2.tiles), "stamping the same vault at the same anchor twice is byte-identical")
end

function tests.connectivityRepair()
  local map = Map.new(15, 7)
  for y = 2, 4 do for x = 2, 4 do map:set(x, y, Map.FLOOR) end end
  for y = 2, 4 do for x = 10, 12 do map:set(x, y, Map.FLOOR) end end
  local function walkableCount()
    local total = 0
    for y = 1, map.height do for x = 1, map.width do
      if map:isWalkable(x, y) then total = total + 1 end
    end end
    return total
  end
  eq(walkableCount(), 18, "the two rooms start disconnected")
  local reachable = Connect.ensure(map, Rng.new(1))
  ok(walkableCount() > 18, "connect carves new corridor to join regions")
  eq(#reachable, walkableCount(), "after repair every floor cell is reachable")
end

function tests.dungeonPersistence()
  local dungeon = Dungeon.new(4242)
  local level3 = dungeon:get(3)
  local tiles3 = table.concat(level3.map.tiles)
  local fresh = Dungeon.new(4242)
  eq(table.concat(fresh:get(3).map.tiles), tiles3, "layout depends only on world seed and depth")
  ok(dungeon:get(3) == level3, "revisiting returns the cached level object")
  local before = #level3.entities
  ok(before > 0, "levels spawn monsters")
  table.remove(level3.entities)
  eq(#dungeon:get(3).entities, before - 1, "level state persists across revisits")
  ok(table.concat(dungeon:get(4).map.tiles) ~= tiles3, "different depth yields a different layout")
  ok(table.concat(Dungeon.new(9999):get(3).map.tiles) ~= tiles3, "different world seed yields a different layout")
  eq(level3.map:get(level3.upX, level3.upY), Tiles.STAIRS_UP, "up stairs are cut")
  eq(level3.map:get(level3.downX, level3.downY), Tiles.STAIRS_DOWN, "down stairs are cut")
end

function tests.prefabVaultsNeverAppearBeforeDepthThree()
  for seed = 1, 40 do
    for depth = 1, 2 do
      local level = Builder.build(depth, Rng.new(seed), {})
      eq(#level.prefabVaults, 0, "no hand-authored vault appears above the first two floors")
    end
  end
end

function tests.prefabVaultFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.prefabVaults = { { name = "guardPost", x = 5, y = 4, w = 7, h = 5 } }
  local restored = Level.fromData(level:toData())
  eq(#restored.prefabVaults, 1, "the prefab vault list survives a round trip")
  eq(restored.prefabVaults[1].name, "guardPost", "a placed vault's template name survives a round trip")
  eq(restored.prefabVaults[1].x, 5, "a placed vault's anchor x survives a round trip")
  eq(restored.prefabVaults[1].w, 7, "a placed vault's footprint width survives a round trip")
end

return tests
