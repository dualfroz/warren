local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Game = require("game")
local Secrets = require("secrets")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.secretsSweepDiscoversAnAdjacentHiddenDoorEventuallyAcrossAHandfulOfSeeds()
  local discovered = false
  for seed = 1, 100 do
    local level = arena(21, 11)
    level.secretDoors = { { x = 5, y = 5, discovered = false } }
    if #Secrets.sweep(level, Rng.new(seed), 5, 6) > 0 then discovered = true break end
  end
  ok(discovered, "an adjacent secret door is eventually discovered across a handful of seeds")
end

function tests.secretsSweepNeverDiscoversADoorTwoStepsAway()
  for seed = 1, 200 do
    local level = arena(21, 11)
    level.secretDoors = { { x = 5, y = 5, discovered = false } }
    eq(#Secrets.sweep(level, Rng.new(seed), 7, 7), 0,
      "a secret door two steps away is never discovered regardless of the roll")
  end
end

function tests.secretsSweepNeverRediscoversAnAlreadyDiscoveredDoor()
  local level = arena(21, 11)
  level.secretDoors = { { x = 5, y = 5, discovered = true } }
  for seed = 1, 50 do
    eq(#Secrets.sweep(level, Rng.new(seed), 5, 5), 0, "an already-discovered door is never swept again")
  end
end

function tests.secretsSweepOpensTheWallIntoAPlainClosedDoorOnDiscovery()
  local level = arena(21, 11)
  level.map:set(5, 5, Tiles.WALL)
  level.secretDoors = { { x = 5, y = 5, discovered = false } }
  local found
  for seed = 1, 100 do
    local door = Secrets.sweep(level, Rng.new(seed), 5, 6)[1]
    if door then found = door break end
  end
  ok(found ~= nil, "the door is eventually discovered")
  eq(found.discovered, true, "the discovered door's own flag is flipped")
  eq(level.map:get(5, 5), Tiles.DOOR_CLOSED, "the wall tile becomes a plain closed door once discovered")
end

function tests.gameEndPlayerTurnEventuallyDiscoversAnAdjacentSecretDoorAcrossAHandfulOfSeeds()
  local discovered = false
  for seed = 1, 100 do
    local game = stagedGame(1, arena(21, 11), 3, 6)
    game.rng = Rng.new(seed)
    game.level.map:set(4, 6, Tiles.WALL)
    game.level.secretDoors = { { x = 4, y = 6, discovered = false } }
    game:endPlayerTurn()
    if game.level.secretDoors[1].discovered then
      local reported = false
      for _, line in ipairs(game.log:recent(6)) do
        if contains(line, "hidden door") then reported = true end
      end
      ok(reported, "a freshly discovered secret door is reported somewhere in the turn's log lines")
      eq(game.level.map:get(4, 6), Tiles.DOOR_CLOSED, "the discovered door's tile is a plain closed door")
      discovered = true
      break
    end
  end
  ok(discovered, "an adjacent secret door is eventually discovered over a handful of seeded turns")
end

function tests.secretDoorFieldsSurviveSerialization()
  local game = Game.new(5)
  game.level.secretDoors = { { x = 3, y = 3, discovered = false } }
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(#restored.level.secretDoors, 1, "the secret door list survives a save/load round trip")
  eq(restored.level.secretDoors[1].discovered, false, "a secret door's discovered flag survives a round trip")
end

return tests
