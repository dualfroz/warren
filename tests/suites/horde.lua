local helpers = require("helpers")
local Rng = require("rng")
local Tiles = require("tiles")
local Astar = require("astar")
local Entity = require("entity")
local Monsters = require("monsters")
local Game = require("game")
local Companions = require("companions")
local Stealth = require("stealth")
local Corpses = require("corpses")
local Reanimation = require("reanimation")
local Mercenaries = require("mercenaries")
local Horde = require("horde")

local ok, eq, arena = helpers.ok, helpers.eq, helpers.arena

local tests = helpers.suite()

function tests.hordeBuildArenaIsFullyEnclosedWithAClearCentreReachableFromEveryCorner()
  local map, cx, cy = Horde.buildArena(Rng.new(1), Horde.WIDTH, Horde.HEIGHT)
  for x = 1, Horde.WIDTH do
    eq(map:get(x, 1), Tiles.WALL, "the top border is solid wall")
    eq(map:get(x, Horde.HEIGHT), Tiles.WALL, "the bottom border is solid wall")
  end
  for y = 1, Horde.HEIGHT do
    eq(map:get(1, y), Tiles.WALL, "the left border is solid wall")
    eq(map:get(Horde.WIDTH, y), Tiles.WALL, "the right border is solid wall")
  end
  ok(map:isWalkable(cx, cy), "the centre cell the player starts on is always clear")
  for _, anchor in ipairs(Horde.spawnAnchors(Horde.WIDTH, Horde.HEIGHT)) do
    ok(Astar.find(map, cx, cy, anchor.x, anchor.y) ~= nil,
      "every corner anchor is reachable from the centre")
  end
end

function tests.hordeBuildArenaIsDeterministicForAFixedSeedAndDiffersAcrossSeeds()
  local mapA = Horde.buildArena(Rng.new(5), Horde.WIDTH, Horde.HEIGHT)
  local mapB = Horde.buildArena(Rng.new(5), Horde.WIDTH, Horde.HEIGHT)
  eq(table.concat(mapA.tiles), table.concat(mapB.tiles), "the same seed always carves the same pillars")
  local mapC = Horde.buildArena(Rng.new(6), Horde.WIDTH, Horde.HEIGHT)
  ok(table.concat(mapA.tiles) ~= table.concat(mapC.tiles), "a different seed carves a different arena")
end

function tests.hordeSpawnPointsAreUniqueWalkableCellsAndAlwaysCoverAMaxWave()
  local map = Horde.buildArena(Rng.new(3), Horde.WIDTH, Horde.HEIGHT)
  local points = Horde.spawnPoints(map)
  ok(#points >= Horde.MAX_COUNT, "the spawn queue always has room for a maximum-size wave")
  local seen = {}
  for _, point in ipairs(points) do
    local key = point.x .. "," .. point.y
    ok(not seen[key], "no spawn cell is ever offered twice")
    seen[key] = true
    ok(map:isWalkable(point.x, point.y), "every offered spawn cell is walkable")
  end
end

function tests.hordeCountForClimbsWithWaveThenCapsAtMaxCount()
  eq(Horde.countFor(1), Horde.BASE_COUNT, "wave one spawns the base count")
  eq(Horde.countFor(4), Horde.BASE_COUNT + 3, "count climbs by one per wave")
  eq(Horde.countFor(50), Horde.MAX_COUNT, "count never exceeds the maximum")
end

function tests.hordeEssenceForIsZeroBeforeTheFirstWaveAndProportionalAfter()
  eq(Horde.essenceFor(0), 0, "no reward is owed before any wave has been cleared")
  eq(Horde.essenceFor(3), 3 * Horde.ESSENCE_PER_WAVE, "reward scales linearly with the wave cleared")
end

function tests.hordePoolExcludesThePassiveVendingShopkeeperEvenAtAQualifyingDepth()
  local pool = Horde.pool(Monsters.byKey.shopkeeper.minDepth)
  for _, spec in ipairs(pool) do
    ok(spec.key ~= "shopkeeper", "the arena never draws the passive shopkeeper into a wave")
  end
  ok(#pool > 0, "other species at the same depth still populate the pool")
end

function tests.hordeClearedIsVacuouslyTrueOnAnEmptyArenaAndFalseWhileAnyMonsterLives()
  local level = arena(Horde.WIDTH, Horde.HEIGHT)
  ok(Horde.cleared(level), "an arena that never had a monster placed counts as cleared")
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  level.entities = { rat }
  ok(not Horde.cleared(level), "a living monster keeps the arena from counting as cleared")
  rat.hp = 0
  ok(Horde.cleared(level), "the arena counts as cleared again once its last monster dies")
end

function tests.hordeClearedIgnoresCarriedAlliesAndOnlyCountsHostileMonsters()
  local level = arena(Horde.WIDTH, Horde.HEIGHT)
  local golem = Entity.new({ kind = "companion", name = "clay golem", x = 3, y = 3, hp = 26, maxHp = 26 })
  local hireling = Entity.new({ kind = "hireling", name = "sellsword", x = 4, y = 3, hp = 20, maxHp = 20 })
  local thrall = Entity.new({ kind = "thrall", name = "rat thrall", x = 5, y = 3, hp = 4, maxHp = 4 })
  level.entities = { golem, hireling, thrall }
  ok(Horde.cleared(level), "three living allies with no hostile monster among them still count as cleared")
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  level.entities[#level.entities + 1] = rat
  ok(not Horde.cleared(level), "a living hostile monster still blocks clearance even alongside living allies")
  rat.hp = 0
  ok(Horde.cleared(level), "clearance returns once the monster dies, regardless of the allies still standing")
end

function tests.hordeSpawnWaveNeverStacksTwoMonstersOnOneCellAndEverySpawnStartsHunting()
  local game = Game.new(11)
  game:startHorde()
  local level = game.level
  local seen = {}
  eq(#level.entities, Horde.countFor(1), "the first wave spawns exactly its own count")
  for _, entity in ipairs(level.entities) do
    local key = entity.x .. "," .. entity.y
    ok(not seen[key], "no two monsters ever spawn on the same cell")
    seen[key] = true
    eq(entity.awareness, Stealth.HUNTING, "an arena spawn starts already hunting, never asleep")
  end
end

function tests.gameStartHordeBeginsAtWaveOneCenteredAndWithoutAStartingReward()
  local game = Game.new(11)
  local essenceBefore, hpBefore = game.player.essence, game.player.hp
  game:startHorde()
  eq(game.horde.wave, 1, "starting a horde run begins at wave one")
  eq(game.level.generator, "horde", "the arena level is tagged as a horde level")
  eq(game.player.essence, essenceBefore, "bootstrapping wave one owes no essence reward")
  eq(game.player.hp, hpBefore, "a player already at full health is not over-healed on entry")
  ok(game.level.map:isWalkable(game.player.x, game.player.y), "the player starts on a walkable cell")
end

function tests.gameStartHordeCarriesEveryLivingAllyIntoTheArenaInsteadOfAbandoningThem()
  local game = Game.new(11)
  local oldLevel = game.level
  local golem = Companions.summon(game, "golem")
  local hireling = Mercenaries.hire(game, "sellsword")
  local rat = Monsters.create(Monsters.byKey.rat, 99, game.player.x + 1, game.player.y, 1)
  Corpses.spawn(game.level, rat)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  ok(golem ~= nil and hireling ~= nil and thrall ~= nil, "all three allies bond before entering the arena")

  game:startHorde()
  ok(game:hasCompanion(), "the companion is with the player in the arena")
  ok(game:hasHireling(), "the hireling is with the player in the arena")
  local thrallFound
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "thrall" then thrallFound = entity end
  end
  eq(thrallFound, thrall, "the very same thrall instance enters the arena, not a rebuilt one")

  local leftBehind = 0
  for _, entity in ipairs(oldLevel.entities) do
    if entity.kind == "companion" or entity.kind == "hireling" or entity.kind == "thrall" then
      leftBehind = leftBehind + 1
    end
  end
  eq(leftBehind, 0, "none of the three allies are stranded on the abandoned floor")
end

function tests.gameEndPlayerTurnStillAdvancesHordeWavesWithACarriedCompanionPresent()
  local game = Game.new(11)
  Companions.summon(game, "golem")
  game:startHorde()
  ok(game:hasCompanion(), "the companion made it into wave one's arena")
  for _, entity in ipairs(game.level.entities) do
    if entity.kind == "monster" then entity.hp = 0 end
  end
  game:cleanupDead()
  game:endPlayerTurn()
  eq(game.horde.wave, 2, "a living companion in the arena never blocks wave clearance from advancing")
  ok(game:hasCompanion(), "the companion survives into wave two alongside the player")
end

function tests.gameEndPlayerTurnAdvancesTheHordeWaveBanksEssenceAndHealsOnceEveryMonsterDies()
  local game = Game.new(11)
  game:startHorde()
  game.player.hp = game.player.maxHp - 1
  local essenceBefore = game.player.essence
  for _, entity in ipairs(game.level.entities) do entity.hp = 0 end
  game:cleanupDead()
  game:endPlayerTurn()
  eq(game.horde.wave, 2, "clearing wave one advances to wave two")
  eq(game.player.essence, essenceBefore + Horde.essenceFor(1), "clearing a wave banks its essence reward")
  eq(game.player.hp, game.player.maxHp, "clearing a wave heals a rest slice, capped at max hp")
  eq(#game.level.entities, Horde.countFor(2), "wave two spawns its own larger count")
end

function tests.gameEndPlayerTurnLeavesAnUnclearedHordeWaveUntouched()
  local game = Game.new(11)
  game:startHorde()
  local countBefore = #game.level.entities
  game:endPlayerTurn()
  eq(game.horde.wave, 1, "a wave still holding a living monster never advances")
  eq(#game.level.entities, countBefore, "an uncleared wave's monster count is untouched")
end

function tests.hordeNeverPromotesAnEliteInEitherOfTheFirstTwoWavesRegardlessOfSeed()
  for seed = 1, 5 do
    local game = Game.new(seed)
    game:startHorde()
    for _, entity in ipairs(game.level.entities) do
      ok(not entity.elite, "no wave-one monster is ever promoted to elite, depth is below the minimum")
    end
    for _, e in ipairs(game.level.entities) do e.hp = 0 end
    game:cleanupDead()
    game:endPlayerTurn()
    for _, entity in ipairs(game.level.entities) do
      ok(not entity.elite, "no wave-two monster is ever promoted to elite either")
    end
  end
end

function tests.hordeEventuallyPromotesElitesOnceWavesCrossTheMinimumDepth()
  local game = Game.new(7)
  game:startHorde()
  local sawElite = false
  for _ = 2, 6 do
    for _, e in ipairs(game.level.entities) do e.hp = 0 end
    game:cleanupDead()
    game:endPlayerTurn()
    for _, entity in ipairs(game.level.entities) do
      if entity.elite then sawElite = true end
    end
  end
  ok(sawElite, "this fixed seed rolls at least one elite once waves reach the minimum depth")
end

return tests
