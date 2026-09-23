local helpers = require("helpers")
local Tiles = require("tiles")
local Map = require("map")
local Los = require("los")
local Items = require("items")
local Monsters = require("monsters")
local Level = require("level")
local Stealth = require("stealth")
local Noise = require("noise")

local ok, eq, arena, stagedGame, wallSplitArena = helpers.ok, helpers.eq, helpers.arena, helpers.stagedGame, helpers.wallSplitArena

local function noiseCornerArena()
  local map = Map.new(15, 9)
  for x = 2, 5 do map:set(x, 3, Map.FLOOR) end
  for y = 3, 5 do map:set(5, y, Map.FLOOR) end
  return Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = false, explored = {},
    upX = 2, upY = 3, downX = 5, downY = 5,
  })
end

local tests = helpers.suite()

function tests.noisePropagateDecaysByExactlyOneLoudnessPerStepThroughOpenFloor()
  local level = arena(21, 11)
  local field = Noise.propagate(level.map, 5, 5, 4)
  eq(Noise.intensityAt(field, level.map, 5, 5), 4, "the origin itself keeps the full starting loudness")
  eq(Noise.intensityAt(field, level.map, 6, 5), 3, "one step away has decayed by exactly one")
  eq(Noise.intensityAt(field, level.map, 7, 5), 2, "two steps away has decayed by exactly two")
  eq(Noise.intensityAt(field, level.map, 8, 5), 1, "three steps away has decayed by exactly three")
  eq(Noise.intensityAt(field, level.map, 9, 5), 0, "four steps away has decayed to nothing")
  eq(Noise.intensityAt(field, level.map, 10, 5), 0, "five steps away never even carried a trailing zero forward")
end

function tests.noisePropagateNeverCrossesASolidWallEvenWhenTheOtherSideIsCloseByEuclideanDistance()
  local level = wallSplitArena()
  local field = Noise.propagate(level.map, 5, 6, 20)
  ok(Noise.intensityAt(field, level.map, 10, 6) > 0, "loudness reaches all the way up to the dividing wall")
  eq(Noise.intensityAt(field, level.map, 12, 6), 0, "nothing at all gets through to the far side of the wall")
end

function tests.noisePropagateBendsAroundACornerToReachACellWithNoStraightLineAtAll()
  local level = noiseCornerArena()
  ok(not Los.clear(level.map, 2, 3, 5, 5), "no straight sightline exists between the two ends of the bend")
  local field = Noise.propagate(level.map, 2, 3, 10)
  ok(Noise.intensityAt(field, level.map, 5, 5) > 0, "the flood still reaches the far end by turning the corner")
  eq(Noise.intensityAt(field, level.map, 5, 5), 10 - 5, "the intensity there reflects the corridor's actual walked distance, five steps")
end

function tests.noisePropagateFromAWallOriginStillReachesItsWalkableNeighbours()
  local level = arena(21, 11)
  level.map:set(10, 6, Map.WALL)
  local field = Noise.propagate(level.map, 10, 6, 5)
  eq(Noise.intensityAt(field, level.map, 10, 6), 5, "the unwalkable origin itself still records the starting loudness")
  eq(Noise.intensityAt(field, level.map, 11, 6), 4, "a walkable neighbour of the struck wall still hears it one step quieter")
  eq(Noise.intensityAt(field, level.map, 9, 6), 4, "every walkable side of the wall hears it, not just one")
end

function tests.noiseIntensityAtIsZeroOutOfBoundsAndWhereverTheFloodNeverReached()
  local level = arena(21, 11)
  local field = Noise.propagate(level.map, 5, 5, 3)
  eq(Noise.intensityAt(field, level.map, -3, 5), 0, "a cell outside the map bounds reads as silent")
  eq(Noise.intensityAt(field, level.map, 5, 5000), 0, "a wildly out of range cell reads as silent rather than erroring")
  eq(Noise.intensityAt(field, level.map, 19, 9), 0, "a cell the flood never reached reads as silent")
end

function tests.noisePropagateWithZeroOrNegativeLoudnessReachesNothing()
  local level = arena(21, 11)
  eq(next(Noise.propagate(level.map, 5, 5, 0)), nil, "zero loudness produces an entirely empty field")
  eq(next(Noise.propagate(level.map, 5, 5, -3)), nil, "negative loudness produces an entirely empty field too")
end

function tests.gameEmitNoiseEventuallyStirsADormantMonsterWithinRangeIntoSearchingAtTheNoisesOrigin()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 6, 1)
  orc.awareness = Stealth.DORMANT
  game.level.entities = { orc }
  local stirred = false
  for _ = 1, 200 do
    game:emitNoise(3, 6, Noise.MELEE)
    if orc.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a dormant monster within the flood's reach eventually stirs across enough noisy bursts")
  eq(orc.awareness, Stealth.SEARCHING, "hearing a noise only starts a search, unlike Stealth.alert's outright hunting")
  eq(orc.lastKnownX, 3, "the search heads for the noise's own origin")
  eq(orc.lastKnownY, 6, "the search heads for the noise's own origin")
end

function tests.gameEmitNoiseNeverStirsADormantMonsterTheFloodCannotReach()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 19, 6, 1)
  orc.awareness = Stealth.DORMANT
  game.level.entities = { orc }
  for _ = 1, 200 do
    game:emitNoise(3, 6, Noise.MELEE)
  end
  eq(orc.awareness, Stealth.DORMANT, "a monster far outside even the loudest reach used here never stirs")
end

function tests.gameEmitNoiseNeverAffectsAMonsterThatIsAlreadyAware()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.awareness = Stealth.HUNTING
  orc.lastKnownX, orc.lastKnownY = 99, 99
  game.level.entities = { orc }
  game:emitNoise(3, 6, Noise.MELEE)
  eq(orc.awareness, Stealth.HUNTING, "an already-aware monster is untouched by a noise burst")
  eq(orc.lastKnownX, 99, "its existing last-known position is left exactly as it was")
end

function tests.gamePlayerAttackCanStirADormantBystanderThatIsNotEvenTheTarget()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local target = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local bystander = Monsters.create(Monsters.byKey.orc, 2, 8, 6, 1)
  bystander.awareness = Stealth.DORMANT
  game.level.entities = { target, bystander }
  local stirred = false
  for _ = 1, 200 do
    target.hp = target.maxHp
    game:playerAttack(target)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a sustained melee fight eventually stirs a wild bystander who was never the target")
  eq(bystander.awareness, Stealth.SEARCHING, "the bystander only starts searching, having merely heard the clash")
end

function tests.gameMonsterMeleeCanStirADormantBystanderTooNotJustPlayerActions()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local attacker = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local bystander = Monsters.create(Monsters.byKey.orc, 2, 8, 6, 1)
  bystander.awareness = Stealth.DORMANT
  game.level.entities = { attacker, bystander }
  local stirred = false
  for _ = 1, 200 do
    game.player.hp = game.player.maxHp
    game:monsterMelee(attacker)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a monster hitting the player is exactly as loud as the player hitting back")
end

function tests.gameDigEmitsNoiseFromTheStruckCellEvenThoughItStartsUnwalkable()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.level.map:set(4, 6, Tiles.WALL)
  game.player.pick = Items.pick("miner's pick", 20)
  local bystander = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  bystander.awareness = Stealth.DORMANT
  game.level.entities = { bystander }
  local stirred = false
  for _ = 1, 200 do
    game:dig(1, 0)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
    if not game.player.pick then game.player.pick = Items.pick("miner's pick", 20) end
    if game.level.map:get(4, 6) == Tiles.FLOOR then game.level.map:set(4, 6, Tiles.WALL) end
  end
  ok(stirred, "the racket of a pick striking solid rock still carries even though the struck cell starts unwalkable")
end

return tests
