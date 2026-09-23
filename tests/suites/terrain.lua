local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Map = require("map")
local Status = require("status")
local Monsters = require("monsters")
local Builder = require("builder")
local Game = require("game")
local Resistances = require("resistances")
local Terrain = require("terrain")

local ok, eq, contains, arena, stagedGame = helpers.ok, helpers.eq, helpers.contains, helpers.arena, helpers.stagedGame

local tests = helpers.suite()

function tests.terrainAfflictLavaDoesNothingOffLava()
  local level = arena(21, 11)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  eq(Terrain.afflictLava(level, rat), nil, "afflictLava does nothing to an entity off any lava cell")
end

function tests.terrainLavaRespectsFireResistanceAndImmunity()
  local level = arena(21, 11)
  level.map:set(5, 5, Tiles.LAVA)

  local resistant = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  resistant.resist = { fire = Resistances.RESIST }
  local hpBefore = resistant.hp
  local line = Terrain.afflictLava(level, resistant)
  eq(resistant.hp, hpBefore - math.floor(Terrain.LAVA_DAMAGE / 2),
    "lava damage is halved for a fire-resistant target")
  ok(contains(line, "sears"), "a damaging lava tick describes itself as searing")
  eq(Status.has(resistant, Status.BURNING), true, "a scorched target is also set alight")

  local immune = Monsters.create(Monsters.byKey.rat, 2, 5, 5, 1)
  immune.resist = { fire = Resistances.IMMUNE }
  local hpBefore2 = immune.hp
  local immuneLine = Terrain.afflictLava(level, immune)
  eq(immune.hp, hpBefore2, "a fire-immune target takes no damage from lava")
  ok(contains(immuneLine, "unharmed"), "a harmless lava tick says so")
  eq(Status.has(immune, Status.BURNING), false, "a fire-immune target is not set alight by lava")
end

function tests.terrainAfflictLavaUnharmedMessageAddressesThePlayerInSecondPerson()
  local level = arena(21, 11)
  level.map:set(5, 5, Tiles.LAVA)
  local game = stagedGame(1, level, 5, 5)
  game.player.resist = { fire = Resistances.IMMUNE }
  eq(Terrain.afflictLava(level, game.player), "you wade through the lava unharmed",
    "an immune player wading through lava is addressed in second person, not 'you wades through the lava unharmed'")
end

function tests.terrainLavaBurnsAndIgnitesAPlayerWhoStepsOnIt()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(4, 6, Tiles.LAVA)
  local hpBefore = game.player.hp
  game:movePlayer(1, 0)
  eq(game.player.hp, hpBefore - Terrain.LAVA_DAMAGE,
    "stepping onto lava deals its full damage to an unresistant player")
  eq(Status.has(game.player, Status.BURNING), true, "lava also sets the player alight")
  ok(contains(game.log:last(), "sears"), "the burn is logged")
end

function tests.terrainLavaCanKillAWeakMonsterAndCreditsThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 6, Tiles.LAVA)
  local bat = Monsters.create(Monsters.byKey.bat, 1, 4, 6, 1)
  bat.hp, bat.maxHp = 3, 3
  game.level.entities = { bat }
  local killsBefore = game.stats.kills
  game:moveMonster(bat, 1, 0)
  eq(#game.level.entities, 0, "a monster killed by lava is removed from the level")
  eq(game.stats.kills, killsBefore + 1, "a lava death still credits the player with a kill")
end

function tests.terrainChasmDropsThePlayerToTheFloorBelowWithFallDamage()
  local game = stagedGame(3, arena(21, 11), 5, 6)
  game.level.map:set(6, 6, Tiles.CHASM)
  local hpBefore = game.player.hp
  local depthBefore = game.depth
  game:movePlayer(1, 0)
  ok(game.player.hp < hpBefore, "falling into a chasm deals fall damage")
  eq(game.depth, depthBefore + 1, "falling into a chasm advances to the floor below")
  eq(game.deepestDepth, depthBefore + 1, "falling into a chasm counts toward the deepest depth reached")
  ok(contains(game.log:last(), "plunge"), "the fall is logged")
end

function tests.terrainChasmSwallowsAMonsterAndCreditsTheKill()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(5, 6, Tiles.CHASM)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  game.level.entities = { rat }
  local killsBefore = game.stats.kills
  game:moveMonster(rat, 1, 0)
  eq(#game.level.entities, 0, "a monster that falls into a chasm is removed from the level")
  eq(game.stats.kills, killsBefore + 1, "a chasm death still credits the player with a kill, like a lethal trap")
end

function tests.terrainIceSlidesATravellerUntilSomethingStopsIt()
  local game = stagedGame(1, arena(21, 11), 2, 6)
  for x = 3, 6 do game.level.map:set(x, 6, Tiles.ICE) end
  game:movePlayer(1, 0)
  eq(game.player.x, 7, "stepping onto ice slides the player through every consecutive ice tile")
  eq(game.player.y, 6, "sliding on ice does not drift off the axis of travel")
end

function tests.terrainIceSlideStopsBeforeAWall()
  local game = stagedGame(1, arena(21, 11), 2, 6)
  game.level.map:set(3, 6, Tiles.ICE)
  game.level.map:set(4, 6, Tiles.ICE)
  game.level.map:set(5, 6, Tiles.WALL)
  game:movePlayer(1, 0)
  eq(game.player.x, 4, "an ice slide stops on the last ice tile before a wall")
end

function tests.terrainIceSlideStopsAtAnOccupiedCell()
  local game = stagedGame(1, arena(21, 11), 2, 6)
  game.level.map:set(3, 6, Tiles.ICE)
  game.level.map:set(4, 6, Tiles.ICE)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  game.level.entities = { rat }
  game:movePlayer(1, 0)
  eq(game.player.x, 4, "an ice slide stops just short of another actor")
end

function tests.checkTerrainForSkipsLavaDamageAndIgnitionForALevitatingPlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(4, 6, Tiles.LAVA)
  Status.apply(game.player, Status.LEVITATE, 20, 1)
  local hpBefore = game.player.hp
  game:movePlayer(1, 0)
  eq(game.player.hp, hpBefore, "a levitating player takes no damage crossing lava")
  eq(Status.has(game.player, Status.BURNING), false, "a levitating player is never set alight by lava")
  ok(contains(game.log:last(), "drift"), "the skip over a visible hazard is still logged, not silent")
end

function tests.checkTerrainForSkipsTheChasmFallForALevitatingPlayer()
  local game = stagedGame(3, arena(21, 11), 5, 6)
  game.level.map:set(6, 6, Tiles.CHASM)
  Status.apply(game.player, Status.LEVITATE, 20, 1)
  local hpBefore = game.player.hp
  local depthBefore = game.depth
  game:movePlayer(1, 0)
  eq(game.player.x, 6, "a levitating player actually reaches the chasm cell instead of refusing to enter it")
  eq(game.player.hp, hpBefore, "a levitating player takes no fall damage over a chasm")
  eq(game.depth, depthBefore, "a levitating player drifts over a chasm instead of dropping to the floor below")
end

function tests.checkTerrainForSkipsTheIceSlideForALevitatingPlayer()
  local game = stagedGame(1, arena(21, 11), 2, 6)
  for x = 3, 6 do game.level.map:set(x, 6, Tiles.ICE) end
  Status.apply(game.player, Status.LEVITATE, 20, 1)
  game:movePlayer(1, 0)
  eq(game.player.x, 3, "a levitating player enters the first ice cell but never slides across the rest")
end

function tests.checkTerrainForSkipsLavaForALevitatingMonsterToo()
  local game = stagedGame(1, arena(21, 11), 2, 2)
  game.level.map:set(6, 6, Tiles.LAVA)
  local bat = Monsters.create(Monsters.byKey.bat, 1, 5, 6, 1)
  Status.apply(bat, Status.LEVITATE, 20, 1)
  game.level.entities = { bat }
  local hpBefore = bat.hp
  game:moveMonster(bat, 1, 0)
  eq(bat.x, 6, "the levitating monster still moves onto the lava cell")
  eq(bat.hp, hpBefore, "a levitating monster crossing lava takes no damage either - the guard is not player-only")
end

function tests.terrainGlyphsSurviveMapSerialization()
  local map = Map.new(10, 6)
  for y = 2, 5 do for x = 2, 9 do map:set(x, y, Map.FLOOR) end end
  map:set(4, 4, Tiles.LAVA)
  map:set(5, 4, Tiles.CHASM)
  map:set(6, 4, Tiles.ICE)
  local restored = Map.fromData(map:toData())
  eq(restored:get(4, 4), Tiles.LAVA, "a lava tile survives a map round trip")
  eq(restored:get(5, 4), Tiles.CHASM, "a chasm tile survives a map round trip")
  eq(restored:get(6, 4), Tiles.ICE, "an ice tile survives a map round trip")
end

function tests.chasmFallFieldsSurviveGameSaveLoad()
  local game = stagedGame(3, arena(21, 11), 5, 6)
  game.level.map:set(6, 6, Tiles.CHASM)
  game:movePlayer(1, 0)
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.depth, game.depth, "the depth reached by falling survives a save/load round trip")
  eq(restored.player.hp, game.player.hp, "hp after a chasm fall survives a save/load round trip")
end

function tests.lavaChasmAndIceStayOffTheShallowFloors()
  for seed = 1, 5 do
    for depth = 1, 3 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, tile in ipairs(level.map.tiles) do
        ok(tile ~= Tiles.LAVA and tile ~= Tiles.CHASM and tile ~= Tiles.ICE,
          "no volatile terrain appears above depth 4")
      end
    end
  end
end

function tests.chasmNeverAppearsOnTheFinalFloor()
  for seed = 1, 30 do
    local level = Builder.build(Builder.MAX_DEPTH, Rng.new(seed), {})
    for _, tile in ipairs(level.map.tiles) do
      ok(tile ~= Tiles.CHASM, "no chasm appears on the final floor since there is no floor below it")
    end
  end
end

return tests
