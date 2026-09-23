local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Map = require("map")
local Fov = require("fov")
local Los = require("los")
local Light = require("light")
local Astar = require("astar")
local Status = require("status")

local ok, eq, arena, stagedGame = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.mapDeterminism()
  local first = Map.generate(60, 24, Rng.new(2024))
  local firstAgain = Map.generate(60, 24, Rng.new(2024))
  eq(table.concat(first.tiles), table.concat(firstAgain.tiles), "same seed same grid")
  local other = Map.generate(60, 24, Rng.new(2025))
  ok(table.concat(first.tiles) ~= table.concat(other.tiles), "different seed different grid")
  ok(#first.rooms >= 2, "generation places multiple rooms")
  eq(first:get(first.stairsX, first.stairsY), Map.STAIRS, "stairs tile is placed")
  eq(first:isWalkable(first.startX, first.startY), true, "player start is walkable")
end

function tests.tilesRegistry()
  eq(Tiles.isWalkable(Tiles.FLOOR), true, "floor is walkable")
  eq(Tiles.isWalkable(Tiles.WALL), false, "wall is not walkable")
  eq(Tiles.isWalkable(Tiles.DOOR_CLOSED), false, "closed door is not walkable")
  eq(Tiles.isWalkable(Tiles.DOOR_OPEN), true, "open door is walkable")
  eq(Tiles.blocksSight(Tiles.DOOR_CLOSED), true, "closed door blocks sight")
  eq(Tiles.blocksSight(Tiles.DOOR_OPEN), false, "open door lets sight through")
  eq(Tiles.isClosedDoor(Tiles.DOOR_LOCKED), true, "locked door counts as a closed door")
  local map = Map.new(5, 3)
  map:set(2, 2, Tiles.DOOR_LOCKED)
  eq(map:isPassable(2, 2, false), false, "locked door blocks pathing without a key")
  eq(map:isPassable(2, 2, true), true, "locked door opens to pathing with a key")
  map:set(3, 2, Tiles.DOOR_CLOSED)
  eq(map:isPassable(3, 2, false), true, "closed door is passable for pathing")
end

function tests.fovKnownScene()
  local map = Map.new(9, 7)
  for y = 2, 6 do for x = 2, 8 do map:set(x, y, Map.FLOOR) end end
  for y = 1, 7 do map:set(5, y, Map.WALL) end
  local visible = Fov.compute(map, 2, 4, 10)
  ok(visible[map:index(2, 4)], "origin is visible")
  ok(visible[map:index(4, 2)], "open cell in the room is visible")
  ok(visible[map:index(5, 4)], "dividing wall face is visible")
  local leaked = false
  for y = 1, 7 do for x = 6, 9 do if visible[map:index(x, y)] then leaked = true end end end
  ok(not leaked, "nothing behind the solid wall is visible")

  local pillar = Map.new(11, 3)
  for x = 2, 10 do pillar:set(x, 2, Map.FLOOR) end
  pillar:set(6, 2, Map.WALL)
  local pillarVis = Fov.compute(pillar, 2, 2, 10)
  ok(pillarVis[pillar:index(5, 2)], "cell before pillar is visible")
  ok(not pillarVis[pillar:index(7, 2)], "cell directly behind pillar is shadowed")
end

function tests.losSightLine()
  local map = Map.new(9, 3)
  for x = 2, 8 do map:set(x, 2, Map.FLOOR) end
  ok(Los.clear(map, 2, 2, 8, 2), "open corridor gives a clear shot")
  map:set(5, 2, Map.WALL)
  ok(not Los.clear(map, 2, 2, 8, 2), "a wall between endpoints breaks the shot")
  ok(Los.clear(map, 2, 2, 4, 2), "shot before the wall is still clear")
end

function tests.astarPathing()
  local map = Map.new(10, 5)
  for y = 2, 4 do for x = 2, 9 do map:set(x, y, Map.FLOOR) end end
  local path = Astar.find(map, 2, 3, 9, 3)
  ok(path ~= nil, "path is found across open floor")
  eq(path[1].x, 2, "path starts at origin x")
  eq(path[#path].x, 9, "path ends at goal x")
  eq(#path, 8, "shortest path length is manhattan distance plus one")
  local sealed = Map.new(10, 5)
  for y = 2, 4 do for x = 2, 6 do sealed:set(x, y, Map.FLOOR) end end
  sealed:set(8, 3, Map.FLOOR)
  eq(Astar.find(sealed, 2, 3, 8, 3), nil, "no path when goal is cut off")
end

function tests.lightAndDark()
  local map = Map.new(13, 3)
  for x = 2, 12 do map:set(x, 2, Map.FLOOR) end
  local dim = Light.compute(map, 2, 2, 2, {})
  local bright = Light.compute(map, 2, 2, 8, {})
  local dimCount, brightCount = 0, 0
  for _ in pairs(dim) do dimCount = dimCount + 1 end
  for _ in pairs(bright) do brightCount = brightCount + 1 end
  ok(dimCount < brightCount, "a smaller light radius reveals fewer cells")
  ok(not dim[map:index(9, 2)], "a far cell is dark without light")
  local lit = Light.compute(map, 2, 2, 3, { { x = 5, y = 2, radius = 3 } })
  ok(lit[map:index(8, 2)], "a visible emitter lights cells beyond the player's own radius")
end

function tests.effectiveRadiusBlindStatusOverridesLightAndWeatherToAMinimumOfOne()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local clear = game:effectiveRadius()
  ok(clear > 1, "an unblinded, unpenalized floor has more than a radius of one to begin with")

  Status.apply(game.player, Status.BLIND, 6, 1)
  eq(game:effectiveRadius(), 1, "a blinded player's sight radius clamps to one regardless of light or weather")

  game.player.statuses = {}
  eq(game:effectiveRadius(), clear, "sight radius returns to normal once blindness is gone")
end

function tests.tilesClassifyVolatileTerrain()
  eq(Tiles.isLava(Tiles.LAVA), true, "isLava recognizes the lava glyph")
  eq(Tiles.isLava(Tiles.FLOOR), false, "isLava rejects plain floor")
  eq(Tiles.isChasm(Tiles.CHASM), true, "isChasm recognizes the chasm glyph")
  eq(Tiles.isChasm(Tiles.FLOOR), false, "isChasm rejects plain floor")
  eq(Tiles.isIce(Tiles.ICE), true, "isIce recognizes the ice glyph")
  eq(Tiles.isIce(Tiles.FLOOR), false, "isIce rejects plain floor")
  eq(Tiles.isWalkable(Tiles.LAVA), true, "lava is walkable at the player's own risk")
  eq(Tiles.isWalkable(Tiles.CHASM), true, "a chasm is walkable right up until it swallows you")
  eq(Tiles.isWalkable(Tiles.ICE), true, "ice is walkable, if slippery")
end

return tests
