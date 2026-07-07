-- Dependency-free assert runner. Exit 0 iff every assertion passes. Every engine
-- system is exercised on a fixed seed so a regression flips a concrete assertion.

local scriptDir = arg[0]:match("^(.*)[/\\]") or "."
package.path = scriptDir .. "/../src/?.lua;" .. scriptDir .. "/src/?.lua;" .. package.path

local Rng = require("rng")
local Tiles = require("tiles")
local Map = require("map")
local Fov = require("fov")
local Los = require("los")
local Light = require("light")
local Astar = require("astar")
local Entity = require("entity")
local Combat = require("combat")
local Items = require("items")
local Affixes = require("affixes")
local Shop = require("shop")
local Identify = require("identify")
local Effects = require("effects")
local Status = require("status")
local Scheduler = require("scheduler")
local MessageLog = require("messagelog")
local Monsters = require("monsters")
local Ai = require("ai")
local Gen = require("gen.init")
local Connect = require("gen.connect")
local Level = require("level")
local Dungeon = require("dungeon")
local Builder = require("builder")
local Serialize = require("serialize")
local Game = require("game")
local Progression = require("progression")
local Spells = require("spells")
local Abilities = require("abilities")
local Hazards = require("hazards")
local Shrines = require("shrines")
local Classes = require("classes")
local Skills = require("skills")
local Crafting = require("crafting")
local Companions = require("companions")
local Artifacts = require("artifacts")
local Bosses = require("bosses")
local Elites = require("elites")
local Quests = require("quests")
local Meta = require("meta")
local Alchemy = require("alchemy")
local Resistances = require("resistances")
local Factions = require("factions")
local Encumbrance = require("encumbrance")
local Render = require("render")
local Terrain = require("terrain")
local Vaults = require("vaults")
local Runewords = require("runewords")
local Atmosphere = require("atmosphere")
local Stealth = require("stealth")
local Compendium = require("compendium")
local Nodes = require("nodes")
local Sets = require("sets")
local Mimics = require("mimics")
local Curses = require("curses")
local Momentum = require("momentum")
local Conductivity = require("conductivity")
local Corpses = require("corpses")
local Digging = require("digging")
local Sanity = require("sanity")
local Hunger = require("hunger")
local Events = require("events")
local Graves = require("graves")
local Proficiency = require("proficiency")
local Ascension = require("ascension")
local Durability = require("durability")
local Disarm = require("disarm")
local Chests = require("chests")
local Reanimation = require("reanimation")
local Secrets = require("secrets")
local Mercenaries = require("mercenaries")
local Morgue = require("morgue")
local Leaderboard = require("leaderboard")
local Replay = require("replay")
local Challenges = require("challenges")
local Analytics = require("analytics")
local Titles = require("titles")
local Export = require("export")
local Streaks = require("streaks")
local Nemesis = require("nemesis")
local Biomes = require("biomes")
local Scavenging = require("scavenging")
local Infighting = require("infighting")
local Blocks = require("blocks")
local SaveGame = require("savegame")
local Polymorph = require("polymorph")
local Prefab = require("gen.prefab")
local Noise = require("noise")
local Disease = require("disease")
local Captives = require("captives")
local Horde = require("horde")
local Branches = require("branches")
local Phases = require("phases")
local Commands = require("commands")
local Examine = require("examine")

local passed, failed = 0, 0
local failures = {}

local function ok(condition, name)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = name
  end
end

local function eq(actual, expected, name)
  ok(actual == expected,
    string.format("%s (expected %s, got %s)", name, tostring(expected), tostring(actual)))
end

local function contains(haystack, needle)
  return haystack:find(needle, 1, true) ~= nil
end

local tests = {}

function tests.rngDeterminism()
  local a, b = Rng.new(12345), Rng.new(12345)
  for i = 1, 100 do
    eq(a:nextUint(), b:nextUint(), "rng stream matches at step " .. i)
  end
  local c = Rng.new(99)
  ok(a:nextUint() ~= c:nextUint(), "different seed diverges")
  local low, high, within = math.huge, -math.huge, true
  local ranged = Rng.new(7)
  for _ = 1, 500 do
    local v = ranged:range(3, 9)
    if v < 3 or v > 9 then within = false end
    low, high = math.min(low, v), math.max(high, v)
  end
  ok(within, "range stays inside bounds")
  eq(low, 3, "range reaches its low bound")
  eq(high, 9, "range reaches its high bound")
end

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

function tests.combatResolution()
  local hero = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 2 })
  local foe = Entity.new({ x = 2, y = 1, glyph = "r", name = "rat", kind = "monster", hp = 10, attack = 3, defense = 1 })
  local first = Combat.attack(hero, foe)
  eq(first.damage, 5, "damage is attack minus defense")
  eq(foe.hp, 5, "defender hp drops by damage")
  Combat.attack(hero, foe)
  eq(foe:isAlive(), false, "dead entity reports not alive")
  local tank = Entity.new({ x = 1, y = 1, glyph = "T", name = "troll", kind = "monster", hp = 5, attack = 1, defense = 20 })
  eq(Combat.attack(foe, tank).damage, 1, "damage is floored at one against heavy armor")
end

function tests.itemsAndEquipment()
  local hero = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, maxHp = 30, attack = 5, defense = 1 })
  eq(Items.use(Items.potion(8), hero), 8, "potion reports amount healed")
  eq(hero.hp, 28, "potion restores hp")
  hero.inventory[1] = Items.potion(50)
  Items.useFromInventory(hero, 1)
  eq(hero.hp, hero.maxHp, "healing never exceeds maxHp")
  Items.equipWeapon(Items.weapon("sword", 4), hero)
  eq(hero.attack, 9, "weapon adds to attack")
  Items.equipWeapon(Items.weapon("axe", 7), hero)
  eq(hero.attack, 12, "swapping weapon adjusts attack correctly")
  eq(#hero.inventory, 1, "displaced weapon returns to inventory")
  Items.equipArmor(Items.armor("plate", 3), hero)
  eq(hero.defense, 4, "armor adds to defense")
  Items.equipRing(Items.ring("power", 2, 1), hero)
  eq(hero.attack, 14, "ring adds to attack")
  eq(hero.defense, 5, "ring adds to defense")
end

function tests.affixes()
  local blade = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[3])
  eq(blade.power, 3, "flaming affix raises weapon power")
  eq(blade.name, "flaming dagger", "affix prefixes the item name")
  eq(blade.affix.onHit.status, "burning", "flaming carries an on-hit rider")
  local a = Affixes.rollWeapon(Rng.new(5))
  local b = Affixes.rollWeapon(Rng.new(5))
  eq(a and a.key, b and b.key, "affix rolls are deterministic per seed")
end

function tests.statusEffects()
  local victim = Entity.new({ x = 1, y = 1, glyph = "r", name = "rat", kind = "monster", hp = 10, maxHp = 10, attack = 2, defense = 0 })
  Status.apply(victim, Status.POISON, 3, 2)
  local lines = Status.tick(victim)
  eq(victim.hp, 8, "poison drains hp each tick")
  ok(#lines == 1, "poison tick emits a message")
  Status.tick(victim); Status.tick(victim)
  eq(Status.has(victim, Status.POISON), false, "poison expires after its duration")

  local hurt = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 5, maxHp = 10, attack = 1, defense = 0 })
  Status.apply(hurt, Status.REGEN, 2, 3)
  Status.tick(hurt)
  eq(hurt.hp, 8, "regeneration restores hp each tick")

  local warrior = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 10, attack = 5, defense = 1 })
  eq(warrior:effectiveAttack(), 5, "no status means base attack")
  Status.apply(warrior, Status.STRENGTH, 5, 3)
  eq(warrior:effectiveAttack(), 8, "strength raises effective attack")
  Status.apply(warrior, Status.HASTE, 5, 1)
  eq(warrior:effectiveSpeed(), 160, "haste raises effective speed")
  Status.apply(warrior, Status.STUN, 2, 1)
  eq(Status.skipsTurn(warrior), true, "stun makes an actor skip its turn")

  Status.apply(warrior, Status.STRENGTH, 99, 1)
  local strength
  for _, s in ipairs(warrior.statuses) do if s.kind == Status.STRENGTH then strength = s end end
  eq(strength.duration, 99, "re-applying a status refreshes to the longer duration")
end

function tests.scheduler()
  local player = Entity.new({ id = 0, x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 10, attack = 1, defense = 0, speed = 100 })
  local slow = Entity.new({ id = 1, x = 2, y = 1, glyph = "o", name = "orc", kind = "monster", hp = 10, attack = 1, defense = 0, speed = 100 })
  local fast = Entity.new({ id = 2, x = 3, y = 1, glyph = "v", name = "bat", kind = "monster", hp = 10, attack = 1, defense = 0, speed = 200 })
  local stub = { player = player }
  function stub:currentEntities() return { slow, fast } end
  local function run()
    player.energy, slow.energy, fast.energy = 0, 0, 0
    local tally = { [0] = 0, [1] = 0, [2] = 0 }
    local firstId
    for step = 1, 60 do
      local actor = Scheduler.next(stub)
      if step == 1 then firstId = actor.id end
      tally[actor.id] = tally[actor.id] + 1
      Scheduler.spend(actor)
    end
    return tally, firstId
  end
  local tally, firstId = run()
  eq(firstId, 2, "the fastest actor acts first")
  ok(tally[2] > tally[0], "a double-speed actor acts more often than the player")
  eq(tally[0], tally[1], "equal-speed actors act equally often")
  local tally2 = run()
  ok(tally[0] == tally2[0] and tally[2] == tally2[2], "scheduling is deterministic")
end

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
  -- Braiding deliberately opens a handful of the diagonal cells a pure
  -- backtracker never touches (see mazeGeneratorBraidingOpensSomeDeadEnds...
  -- below), so this checks the unbraided core algorithm's own shape rather
  -- than the default, braided output.
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

function tests.builderCanBeExplicitlySteeredToAMazeFloorAndStillYieldsAPlayableLevel()
  local level = Builder.build(3, Rng.new(11), { generator = "maze" })
  eq(level.generator, "maze", "the level remembers it was built with the maze generator")
  eq(level.map:get(level.upX, level.upY), Tiles.STAIRS_UP, "a maze floor still gets its up stairs")
  eq(level.map:get(level.downX, level.downY), Tiles.STAIRS_DOWN, "a maze floor still gets its down stairs")
  local path = Astar.find(level.map, level.upX, level.upY, level.downX, level.downY, function(x, y)
    return not level.map:isPassable(x, y, true)
  end)
  ok(path ~= nil, "the down stairs are reachable from the up stairs on a maze floor")
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

local function arena(w, h)
  local map = Map.new(w, h)
  for y = 2, h - 1 do for x = 2, w - 1 do map:set(x, y, Map.FLOOR) end end
  return Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = false, explored = {},
    upX = 2, upY = 2, downX = w - 1, downY = h - 1,
  })
end

local function stagedGame(seed, level, px, py)
  local game = Game.new(seed)
  game.level = level
  game.player.x, game.player.y = px, py
  game:computeVisible()
  return game
end

function tests.monsterAiChase()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 12, 6, 1)
  game.level.entities = { orc }
  Ai.act(game, orc)
  eq(orc.x, 11, "a chaser steps one cell toward a visible player")
end

function tests.monsterAiRanged()
  local shootGame = stagedGame(1, arena(21, 11), 3, 6)
  local archer = Monsters.create(Monsters.byKey.archer, 1, 8, 6, 1)
  shootGame.level.entities = { archer }
  local hpBefore = shootGame.player.hp
  Ai.act(shootGame, archer)
  ok(shootGame.player.hp < hpBefore, "an archer in range and line of sight shoots")
  eq(archer.x, 8, "an archer that can shoot holds its ground")

  local kiteGame = stagedGame(1, arena(21, 11), 3, 6)
  local adjacent = Monsters.create(Monsters.byKey.archer, 1, 4, 6, 1)
  kiteGame.level.entities = { adjacent }
  Ai.act(kiteGame, adjacent)
  eq(adjacent.x, 5, "an archer kites away when the player closes in")
end

function tests.monsterAiFlee()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local wretch = Monsters.create(Monsters.byKey.wretch, 1, 5, 6, 1)
  game.level.entities = { wretch }
  Ai.act(game, wretch)
  eq(wretch.x, 6, "a coward flees away from the player")
end

function tests.monsterAiDeterministic()
  local function batRun()
    local game = stagedGame(55, arena(21, 11), 3, 6)
    local bat = Monsters.create(Monsters.byKey.bat, 1, 10, 6, 1)
    game.level.entities = { bat }
    game.rng = Rng.new(55)
    Ai.act(game, bat)
    return bat.x, bat.y
  end
  local x1, y1 = batRun()
  local x2, y2 = batRun()
  ok(x1 >= 2 and x1 <= 20 and y1 >= 2 and y1 <= 10, "erratic bat lands on a valid cell")
  ok(x1 == x2 and y1 == y2, "erratic behaviour is deterministic per seed")
end

-- A confused chaser rolls the exact same override chance every turn that a
-- confused player rolls in Game:movePlayer (see status.lua's shared
-- CONFUSE_NUMERATOR/DENOMINATOR) - some seeds let its own chase behaviour
-- through untouched, others send it stumbling in a random direction instead.
function tests.aiActConfusedMonsterSometimesStumblesInsteadOfChasing()
  local sawChase, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local orc = Monsters.create(Monsters.byKey.orc, 1, 12, 6, 1)
    game.level.entities = { orc }
    Status.apply(orc, Status.CONFUSE, 5, 1)
    Ai.act(game, orc)
    if orc.x == 11 and orc.y == 6 then
      sawChase = true
    else
      sawStumble = true
    end
    if sawChase and sawStumble then break end
  end
  ok(sawChase, "a confused monster's roll sometimes lets its normal behaviour run")
  ok(sawStumble, "a confused monster's roll sometimes overrides its normal behaviour")
end

-- Without the status at all, a chaser's step toward the player is exactly as
-- deterministic and direct as tests.monsterAiChase already established -
-- confusion introduces randomness only once Status.CONFUSE is actually
-- present, never as a side effect of the roll/pick machinery merely existing.
function tests.aiActWithoutConfusionAlwaysRunsTheNormalBehaviour()
  for seed = 1, 20 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local orc = Monsters.create(Monsters.byKey.orc, 1, 12, 6, 1)
    game.level.entities = { orc }
    Ai.act(game, orc)
    eq(orc.x, 11, "an unconfused chaser always steps straight toward the player")
    eq(orc.y, 6, "an unconfused chaser never drifts off its own row")
  end
end

-- Every ai.lua behaviour (chase/pack/ranged/flee/erratic/tunnel) resolves
-- through Game:canSeePlayer, so blinding a monster is a single choke point
-- that mutes every one of them at once - no per-behaviour special casing
-- needed. An archer is the sharpest demonstration: with sight it holds its
-- ground and snipes from range (tests.monsterAiRanged); blinded at the exact
-- same distance it neither shoots nor closes in, it just idles in place.
function tests.aiActBlindedArcherNeitherShootsNorChasesEvenWithAClearShot()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local archer = Monsters.create(Monsters.byKey.archer, 1, 8, 6, 1)
  game.level.entities = { archer }
  Status.apply(archer, Status.BLIND, 6, 1)
  local hpBefore = game.player.hp
  Ai.act(game, archer)
  eq(game.player.hp, hpBefore, "a blinded archer with an otherwise clear shot does not fire")
  eq(archer.x, 8, "a blinded archer does not close the distance either")
  eq(archer.y, 6, "a blinded archer does not drift off its own row")
end

function tests.gameAdjacentAllyFindsACompanionStandingRightNextToAMonster()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local golem = Companions.summon(game, "golem")
  local orc = Monsters.create(Monsters.byKey.orc, 10, golem.x + 1, golem.y, 5)
  game.level.entities[#game.level.entities + 1] = orc
  eq(game:adjacentAlly(orc), golem, "a companion standing right next to a monster is found")
end

function tests.gameAdjacentAllyIgnoresAHostileMonsterAndOnlyCountsCardinalAdjacency()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 10, 10, 6, 1)
  local rat = Monsters.create(Monsters.byKey.rat, 5, 11, 6, 2)
  game.level.entities = { orc, rat }
  eq(game:adjacentAlly(orc), nil, "a hostile monster standing adjacent is never mistaken for an ally")

  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 9, 7
  eq(game:adjacentAlly(orc), nil,
    "a companion only diagonally adjacent does not count - cardinal-only, like Game:playerAdjacent")
  golem.x, golem.y = 9, 6
  eq(game:adjacentAlly(orc), golem, "moving the same companion to cardinal adjacency makes it found")
end

function tests.gameAdjacentAllyBreaksTiesByTheLowerEntityIdAndIgnoresADeadAlly()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 10, 10, 6, 999)
  game.level.entities = { orc }
  local golem = Companions.summon(game, "golem")
  local hireling = Mercenaries.hire(game, "sellsword")
  golem.x, golem.y = 9, 6
  hireling.x, hireling.y = 11, 6
  ok(golem.id < hireling.id, "sanity check: the companion summoned first has the lower entity id")
  eq(game:adjacentAlly(orc), golem, "ties between two equally adjacent allies break toward the lower entity id")
  golem.hp = 0
  eq(game:adjacentAlly(orc), hireling, "a dead ally is skipped even though it is still standing adjacent")
end

-- Reproduces the exact shape Game:aStarNeverRoutesAMonsterThroughABlockedCell
-- already proved for a pushable block: a wall spanning every row except one
-- floor gap leaves stepMonsterToward with no route at all once something is
-- standing in that gap. The difference is what stands there - a living
-- companion, not an inert block - so where a block earns a permanent,
-- correct stalemate, a companion should be fought, not stonewalled forever.
function tests.aiChaseAttacksAnAllyBlockingTheOnlyCorridorToThePlayerInsteadOfIdlingForever()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(11, y, Tiles.WALL) end
  game.level.map:set(11, 6, Tiles.FLOOR)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local orc = Monsters.create(Monsters.byKey.orc, 10, 12, 6, 5)
  game.level.entities[#game.level.entities + 1] = orc
  local hpBefore = golem.hp
  Ai.act(game, orc)
  ok(golem.hp < hpBefore, "a chaser with no route around a blocking ally fights it instead of idling")
  eq(orc.x, 12, "the chaser never steps onto the ally's occupied cell")
  eq(orc.y, 6, "the chaser's y is unchanged - it attacked in place rather than moving")
end

function tests.aiChasePrefersAnAdjacentPlayerOverAnAdjacentAllyWhenBothAreInMeleeRange()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 10, 4, 6, 1)
  game.level.entities = { orc }
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 4, 7
  local playerHpBefore, golemHpBefore = game.player.hp, golem.hp
  Ai.act(game, orc)
  ok(game.player.hp < playerHpBefore, "a monster adjacent to both the player and an ally still attacks the player")
  eq(golem.hp, golemHpBefore, "the ally adjacent to the same monster takes no damage when the player is also in range")
end

function tests.aiPackAttacksAnAllyBlockingTheOnlyCorridorToThePlayerInsteadOfIdlingForever()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(11, y, Tiles.WALL) end
  game.level.map:set(11, 6, Tiles.FLOOR)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local kobold = Monsters.create(Monsters.byKey.kobold, 10, 12, 6, 5)
  game.level.entities[#game.level.entities + 1] = kobold
  local hpBefore = golem.hp
  Ai.act(game, kobold)
  ok(golem.hp < hpBefore, "a pack monster with no route around a blocking ally fights it instead of idling")
end

function tests.aiTunnelAttacksAnAllyBlockingItsOnlyGapInsteadOfIdling()
  local level = arena(21, 11)
  for y = 2, 10 do level.map:set(11, y, Tiles.WALL) end
  level.map:set(11, 6, Tiles.FLOOR)
  local game = stagedGame(1, level, 3, 6)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local burrower = Entity.new({
    id = game:nextMonsterId(), x = 12, y = 6, glyph = "b", name = "rock burrower", kind = "monster",
    ai = "tunnel", hp = 20, maxHp = 20, attack = 5, defense = 0, speed = 100,
  })
  game.level.entities[#game.level.entities + 1] = burrower
  local hpBefore = golem.hp
  Ai.act(game, burrower)
  ok(golem.hp < hpBefore, "a burrower blocked by a living ally fights it rather than trying (and failing) to path around")
  eq(burrower.x, 12, "the burrower stays put while it attacks - it never steps onto the ally's cell")
end

function tests.aiRangedAttacksABlockingAllyWhenItHasNoLineOfSightToThePlayerAtAll()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  for y = 2, 10 do game.level.map:set(8, y, Tiles.WALL) end
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 11, 6
  local archer = Monsters.create(Monsters.byKey.archer, 6, 12, 6, 5)
  game.level.entities[#game.level.entities + 1] = archer
  local hpBefore, playerHpBefore = golem.hp, game.player.hp
  Ai.act(game, archer)
  ok(golem.hp < hpBefore, "an archer with no line of sight to the player still fights an ally standing next to it")
  eq(game.player.hp, playerHpBefore, "the archer never reaches or harms the player while its view is fully walled off")
end

function tests.gameMoveMonsterAttacksAnAllyItBumpsIntoInsteadOfDoingNothing()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local golem = Companions.summon(game, "golem")
  local orc = Monsters.create(Monsters.byKey.orc, 10, golem.x + 1, golem.y, 5)
  game.level.entities[#game.level.entities + 1] = orc
  local hpBefore = golem.hp
  game:moveMonster(orc, -1, 0)
  ok(golem.hp < hpBefore, "bumping into an ally's cell fights it rather than silently doing nothing")
  eq(orc.x, golem.x + 1, "the bumping monster does not step onto the ally's occupied cell")
end

-- Mirrors aiActConfusedMonsterSometimesStumblesInsteadOfChasing's own seed
-- loop: a confused monster's random stumble (Ai.act -> Game:moveMonster) can
-- land it squarely on a blocking ally's cell exactly as often as the
-- player's, so the fix belongs in Game:moveMonster itself, not only in the
-- deliberate per-behaviour pathing checks above.
-- Isolates the stumble path from chase()'s own independent attackBlockingAlly
-- check: Ai.behaviours.chase is swapped for a stub that only records whether
-- it ran, so a turn where the confusion roll fails (falling through to real
-- chase) is detectable and excluded - any hp drop counted here can only have
-- come from the top-of-Ai.act stumble branch calling Game:moveMonster
-- directly, never from chase's own fix a few lines below it.
function tests.aiActConfusedMonsterCanStumbleIntoAttackingABlockingAllyInsteadOfIdling()
  local sawAttack = false
  local realChase = Ai.behaviours.chase
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local orc = Monsters.create(Monsters.byKey.orc, 10, 12, 6, 1)
    local golem = Companions.summon(game, "golem")
    golem.x, golem.y = 11, 6
    game.level.entities[#game.level.entities + 1] = orc
    Status.apply(orc, Status.CONFUSE, 5, 1)
    local hpBefore = golem.hp
    local behaviourRan = false
    Ai.behaviours.chase = function() behaviourRan = true end
    Ai.act(game, orc)
    Ai.behaviours.chase = realChase
    if not behaviourRan and golem.hp < hpBefore then
      sawAttack = true
      break
    end
  end
  ok(sawAttack, "a confused monster's stumble (Ai.act's own branch, not chase's) can land an attack on a blocking ally via Game:moveMonster")
end

function tests.doorsAndKeys()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.inventory = {}
  game.level.map:set(4, 6, Tiles.DOOR_CLOSED)
  game:movePlayer(1, 0)
  eq(game.level.map:get(4, 6), Tiles.DOOR_OPEN, "bumping a closed door opens it")
  eq(game.player.x, 3, "opening a door does not move the player")

  game.level.map:set(2, 6, Tiles.FLOOR)
  game.level.map:set(4, 6, Tiles.DOOR_LOCKED)
  game:movePlayer(1, 0)
  eq(game.level.map:get(4, 6), Tiles.DOOR_LOCKED, "a locked door stays shut without a key")
  eq(game.log:last(), "the door is locked", "the game reports a locked door")
  game.player.inventory[#game.player.inventory + 1] = Items.key()
  game:movePlayer(1, 0)
  eq(game.level.map:get(4, 6), Tiles.DOOR_OPEN, "a key unlocks the door")
  eq(#game.player.inventory, 0, "unlocking consumes the key")
end

function tests.traps()
  local dartGame = stagedGame(1, arena(21, 11), 3, 6)
  dartGame.level.traps = { { x = 4, y = 6, effect = "dart", revealed = false } }
  local hpBefore = dartGame.player.hp
  dartGame:movePlayer(1, 0)
  ok(dartGame.player.hp < hpBefore, "a dart trap wounds the stepper")
  eq(dartGame.level.traps[1].revealed, true, "a sprung trap becomes revealed")
  eq(dartGame.level.map:get(4, 6), Tiles.TRAP, "a sprung trap shows on the map")

  local poisonGame = stagedGame(1, arena(21, 11), 3, 6)
  poisonGame.level.traps = { { x = 4, y = 6, effect = "poison", revealed = false } }
  poisonGame:movePlayer(1, 0)
  eq(Status.has(poisonGame.player, Status.POISON), true, "a poison trap poisons the stepper")

  local confuseGame = stagedGame(1, arena(21, 11), 3, 6)
  confuseGame.level.traps = { { x = 4, y = 6, effect = "confuse", revealed = false } }
  confuseGame:movePlayer(1, 0)
  eq(Status.has(confuseGame.player, Status.CONFUSE), true, "a confuse trap confuses the stepper")
  eq(confuseGame.level.traps[1].revealed, true, "a sprung confuse trap becomes revealed too")

  local blindGame = stagedGame(1, arena(21, 11), 3, 6)
  blindGame.level.traps = { { x = 4, y = 6, effect = "blind", revealed = false } }
  blindGame:movePlayer(1, 0)
  eq(Status.has(blindGame.player, Status.BLIND), true, "a blind trap blinds the stepper")
  eq(blindGame.level.traps[1].revealed, true, "a sprung blind trap becomes revealed too")
  eq(blindGame:effectiveRadius(), 1, "the freshly blinded stepper's own sight radius is clamped straight away")

  local stunGame = stagedGame(1, arena(21, 11), 3, 6)
  stunGame.level.traps = { { x = 4, y = 6, effect = "stun", revealed = false } }
  stunGame:movePlayer(1, 0)
  eq(Status.has(stunGame.player, Status.STUN), true, "a stun trap stuns the stepper")
  eq(stunGame.level.traps[1].revealed, true, "a sprung stun trap becomes revealed too")
end

-- Game:springTrap is written to work against whatever `victim` it is handed,
-- not just self.player - the same generic shape a builder-placed trap needs
-- to also harm a monster that blunders into a player-planted trap kit.
function tests.gameSpringTrapConfuseEffectAppliesToAnyVictimNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 10, 6, 1)
  game.level.entities = { rat }
  local trap = { x = 10, y = 6, effect = "confuse", revealed = false }
  game:springTrap(trap, rat)
  eq(Status.has(rat, Status.CONFUSE), true, "a confuse trap sprung on a monster confuses that monster")
  eq(Status.has(game.player, Status.CONFUSE), false, "the player is untouched by a trap sprung on someone else")
end

function tests.gameSpringTrapBlindEffectAppliesToAnyVictimNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 10, 6, 1)
  game.level.entities = { rat }
  local trap = { x = 10, y = 6, effect = "blind", revealed = false }
  game:springTrap(trap, rat)
  eq(Status.has(rat, Status.BLIND), true, "a blind trap sprung on a monster blinds that monster")
  eq(Status.has(game.player, Status.BLIND), false, "the player is untouched by a trap sprung on someone else")
end

-- STUN previously had the opposite gap from BLIND (see abilities.lua's
-- tryShriek comment): a player's crafted weapon could already stun a
-- monster, but nothing on the environment/monster side could ever stun the
-- player. A trap is a fitting, low-risk source for that missing direction -
-- rare and avoidable/disarmable, unlike say an elite's on-hit rider firing
-- on every single blow it lands.
function tests.gameSpringTrapStunEffectAppliesToAnyVictimNotJustThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 10, 6, 1)
  game.level.entities = { rat }
  local trap = { x = 10, y = 6, effect = "stun", revealed = false }
  game:springTrap(trap, rat)
  eq(Status.has(rat, Status.STUN), true, "a stun trap sprung on a monster stuns that monster")
  eq(Status.has(game.player, Status.STUN), false, "the player is untouched by a trap sprung on someone else")
end

-- A confused player's every attempted move rolls the same override chance a
-- confused monster's Ai.act does (status.lua's shared CONFUSE_NUMERATOR/
-- DENOMINATOR): in the middle of an open arena every one of the 8 compass
-- directions leads to open floor, so either outcome always still moves the
-- player somewhere and always spends the turn.
function tests.gameMovePlayerConfusionEitherFollowsTheChosenDirectionOrStumblesElsewhere()
  local sawStraight, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 10, 6)
    Status.apply(game.player, Status.CONFUSE, 5, 1)
    local consumesTurn = game:movePlayer(1, 0)
    ok(consumesTurn, "a confused player's attempted move always spends the turn on open floor")
    if game.player.x == 11 and game.player.y == 6 then
      sawStraight = true
    else
      sawStumble = true
    end
    if sawStraight and sawStumble then break end
  end
  ok(sawStraight, "confusion sometimes lets the chosen direction through untouched")
  ok(sawStumble, "confusion sometimes overrides the chosen direction")
end

-- The turn-spending contract that makes confusion different from an ordinary
-- rejected move: bumping a wall on purpose spends nothing (see
-- tests.doorsAndKeys's locked-door case and moveHandler's own "you cannot go
-- that way"), but a confused player who stumbles into a wall instead of their
-- own chosen direction still spent the turn on the stumble itself.
function tests.gameMovePlayerConfusionStumbleIntoAWallStillSpendsTheTurn()
  local level = arena(21, 11)
  -- Wall off every neighbour of (10, 6) except due east, so any redirect
  -- other than the player's own chosen direction bumps a wall in place.
  for _, cell in ipairs({ { 9, 5 }, { 10, 5 }, { 11, 5 }, { 9, 6 }, { 9, 7 }, { 10, 7 }, { 11, 7 } }) do
    level.map:set(cell[1], cell[2], Tiles.WALL)
  end
  local sawBlockedStumble = false
  for seed = 1, 500 do
    local game = stagedGame(seed, level, 10, 6)
    Status.apply(game.player, Status.CONFUSE, 5, 1)
    local consumesTurn = game:movePlayer(1, 0)
    ok(consumesTurn, "a confused move, straight or stumbled into this walled-off pocket, always spends the turn")
    if game.player.x == 10 and game.player.y == 6 then
      sawBlockedStumble = true
    end
  end
  ok(sawBlockedStumble, "at least one seed in range stumbled into a wall instead of moving east")
end

-- Without Status.CONFUSE present at all, Game:movePlayer never consults the
-- rng for a redirect - the roll/pick machinery added for confusion must be a
-- true no-op for every unconfused move the engine already relied on.
function tests.gameMovePlayerWithoutConfusionNeverStumbles()
  for seed = 1, 20 do
    local game = stagedGame(seed, arena(21, 11), 10, 6)
    game:movePlayer(1, 0)
    eq(game.player.x, 11, "an unconfused move always lands exactly where it was aimed")
    eq(game.player.y, 6, "an unconfused move never drifts off its own row")
  end
end

-- Game:allyActsConfused is the companion/hireling/thrall counterpart of the
-- confusion machinery above - unlike Game:movePlayer and Ai.act, it is never
-- called at all unless a caller opts in, so an entity without Status.CONFUSE
-- must bail out before it ever touches the rng (companionsAct*/mercenaryAct*/
-- reanimationAct* below cover the roll actually firing).
function tests.gameAllyActsConfusedReturnsFalseImmediatelyWithoutTheStatus()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local golem = Companions.summon(game, "golem")
  local rollsBefore = game.rng.state
  eq(game:allyActsConfused(golem), false, "an ally without Status.CONFUSE never triggers a stumble")
  eq(game.rng.state, rollsBefore, "checking an unconfused ally never advances the rng")
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

function tests.identification()
  local a = Identify.new(Rng.new(7))
  local b = Identify.new(Rng.new(7))
  local healing = Items.potionOf("heal")
  eq(Identify.label(a, healing), Identify.label(b, healing), "appearances are deterministic per seed")
  ok(not contains(Identify.label(a, healing), "healing"), "an unidentified potion hides its true name")
  ok(contains(Identify.label(a, healing), "potion"), "an unidentified potion still reads as a potion")
  local c = Identify.new(Rng.new(8))
  local differs = Identify.label(a, healing) ~= Identify.label(c, healing)
    or Identify.label(a, Items.potionOf("poison")) ~= Identify.label(c, Items.potionOf("poison"))
  ok(differs, "a different world scrambles appearances differently")
  Identify.reveal(a, healing)
  eq(Identify.label(a, healing), "potion of healing", "identifying reveals the true name")
end

function tests.identifyGivesEveryPotionTypeItsOwnDistinctUnidentifiedLook()
  local state = Identify.new(Rng.new(3))
  local seen = {}
  for _, entry in ipairs(Items.potionTypes) do
    local label = Identify.label(state, Items.potionOf(entry.effect))
    ok(seen[label] == nil, "no two potion types share an unidentified look (collided on " .. label .. ")")
    seen[label] = true
  end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  eq(count, #Items.potionTypes, "every potion type, including confuse, got its own look")
end

function tests.effects()
  local game = Game.new(31)
  game.player.hp = 10
  Effects.apply("heal", game, game.player, { power = 8 })
  eq(game.player.hp, 18, "heal effect restores hp")
  Effects.apply("poison", game, game.player, { power = 3 })
  eq(Status.has(game.player, Status.POISON), true, "poison effect afflicts the target")

  Effects.apply("confuse", game, game.player, {})
  eq(Status.has(game.player, Status.CONFUSE), true, "confuse effect afflicts the drinker just like poison")

  Effects.apply("blind", game, game.player, {})
  eq(Status.has(game.player, Status.BLIND), true, "blind effect afflicts the drinker just like confuse")

  Effects.apply("mapping", game, game.player, {})
  local map = game.level.map
  local exploredAll = true
  for idx = 1, map.width * map.height do
    if not game.level.explored[idx] then exploredAll = false end
  end
  ok(exploredAll, "magic mapping reveals the whole level")

  local unknown = Items.potionOf("strength")
  game.player.inventory = { unknown }
  Effects.apply("identify", game, game.player, {})
  eq(Identify.isKnown(game.identify, unknown), true, "identify reveals an inventory item type")

  local ox, oy = game.player.x, game.player.y
  Effects.apply("teleport", game, game.player, {})
  ok(game.player.x ~= ox or game.player.y ~= oy, "teleport relocates the player")
  eq(game.level.map:isWalkable(game.player.x, game.player.y), true, "teleport lands on walkable ground")

  local blastGame = stagedGame(1, arena(21, 11), 6, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 7, 6, 1)
  orc.hp, orc.maxHp = 20, 20
  blastGame.level.entities = { orc }
  Effects.apply("fireball", blastGame, blastGame.player, {})
  eq(orc.hp, 12, "fireball burns nearby monsters")
  eq(Status.has(orc, Status.BURNING), true, "fireball sets monsters alight")
  ok(Hazards.at(blastGame.level, orc.x, orc.y, Hazards.FIRE) ~= nil,
    "fireball leaves a lingering flame under a scorched monster")
  ok(Hazards.at(blastGame.level, blastGame.player.x, blastGame.player.y, Hazards.FIRE) ~= nil,
    "fireball also ignites the ground at its own point of origin")
end

-- Effects.apply's only real caller (Game:useItem) always hands it the
-- player, whose entity.name is the pronoun "you" - a subject that takes the
-- plain verb form English gives second person ("you heal"), not the
-- third-person-singular form ("heals") a named monster like "orc" would take
-- through the exact same handler. Before this fix every line below actually
-- read "you heals 5", "you is poisoned", etc. on every real potion/scroll
-- use in the game - these are the literal strings a real player sees.
function tests.effectsMessagesAddressThePlayerInSecondPersonNotThirdPersonSingular()
  local game = Game.new(31)
  game.player.hp = 10
  eq(Effects.apply("heal", game, game.player, { power = 5 })[1], "you heal 5",
    "heal addresses the player correctly, not 'you heals 5'")
  eq(Effects.apply("poison", game, game.player, { power = 3 })[1], "you are poisoned",
    "poison addresses the player correctly, not 'you is poisoned'")
  eq(Effects.apply("strength", game, game.player, {})[1], "you feel mightier",
    "strength addresses the player correctly, not 'you feels mightier'")
  eq(Effects.apply("haste", game, game.player, {})[1], "you speed up",
    "haste addresses the player correctly, not 'you speeds up'")
  eq(Effects.apply("fortify", game, game.player, {})[1], "you feel fortified",
    "fortify addresses the player correctly, not 'you feels fortified'")
  eq(Effects.apply("levitate", game, game.player, {})[1], "you rise off the ground",
    "levitate addresses the player correctly, not 'you rises off the ground'")
  eq(Effects.apply("confuse", game, game.player, {})[1], "your mind reels with confusion",
    "confuse addresses the player possessively, not \"you's mind reels with confusion\"")
  eq(Effects.apply("blind", game, game.player, {})[1], "you are struck blind",
    "blind addresses the player correctly, not 'you is struck blind'")
  eq(Effects.apply("teleport", game, game.player, {})[1], "you blink away",
    "teleport addresses the player correctly, not 'you blinks away'")
end

function tests.effectsClarityMessageAddressesThePlayerPossessively()
  local game = Game.new(31)
  Sanity.adjust(game.player, -20)
  local line = Effects.apply("clarity", game, game.player, { power = 10 })[1]
  ok(contains(line, "your mind steadies"), "clarity addresses the player possessively, not \"you's mind steadies\"")
end

function tests.effectsCureMessagesAddressThePlayerPossessivelyForAllFourOutcomes()
  local game = Game.new(31)
  Disease.infect(game.player, Disease.ROT)
  Status.apply(game.player, Status.POISON, 5, 2)
  eq(Effects.apply("cure", game, game.player, {})[1], "your affliction is cleansed away, and the poison fades",
    "curing both addresses the player possessively, not \"you's affliction ... you's poison\"")

  Disease.infect(game.player, Disease.ROT)
  eq(Effects.apply("cure", game, game.player, {})[1], "your affliction is cleansed away",
    "curing disease alone addresses the player possessively, not \"you's affliction\"")

  Status.apply(game.player, Status.POISON, 5, 2)
  eq(Effects.apply("cure", game, game.player, {})[1], "your poison fades",
    "curing a status alone addresses the player possessively, not \"you's poison fades\"")

  eq(Effects.apply("cure", game, game.player, {})[1], "you feel a faint tingle, but had nothing to cleanse",
    "curing nothing addresses the player correctly, not 'you feels a faint tingle'")
end

-- The exact same pronoun problem effects.lua had also lived in status.lua's
-- own POISON/REGEN tick messages, disease.lua's tick messages, and
-- terrain.lua's lava message - every one of them templated a
-- third-person-singular verb onto entity.name with no branch at all for the
-- player, whose name is "you". These four tests cover each of those sites
-- directly against a real player entity.
function tests.statusPoisonShrugAndRegenKnitMessagesAddressThePlayerInSecondPerson()
  local immunePlayer = Entity.new({
    x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 10, maxHp = 10, attack = 1, defense = 0,
  })
  immunePlayer.resist = { poison = Resistances.IMMUNE }
  Status.apply(immunePlayer, Status.POISON, 3, 4)
  eq(Status.tick(immunePlayer)[1], "you shrug off the poison",
    "an immune player shrugs off poison in second person, not 'you shrugs off the poison'")

  local hurtPlayer = Entity.new({
    x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 5, maxHp = 10, attack = 1, defense = 0,
  })
  Status.apply(hurtPlayer, Status.REGEN, 2, 3)
  eq(Status.tick(hurtPlayer)[1], "you knit flesh for 3",
    "a regenerating player knits flesh in second person, not 'you knits flesh for 3'")
end

function tests.diseaseTickMessagesAddressThePlayerInSecondPersonForEruptionDamageAndEscalation()
  local player = Entity.new({
    x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 1000, maxHp = 1000, attack = 1, defense = 0,
  })
  Disease.infect(player, Disease.PARASITES)
  local incubation = Disease.defs[Disease.PARASITES].incubation
  for _ = 1, incubation - 1 do Disease.tick(player) end
  eq(Disease.tick(player), "you break out in gut parasites",
    "eruption addresses the player in second person, not 'you breaks out in gut parasites'")
  eq(Disease.tick(player), "you are wracked by gut parasites for 1",
    "a damaging tick addresses the player in second person, not 'you is wracked by gut parasites for 1'")

  local stageTurns = Disease.defs[Disease.PARASITES].stageTurns
  for _ = 2, stageTurns - 1 do Disease.tick(player) end
  eq(Disease.tick(player), "your gut parasites worsens",
    "escalation addresses the player possessively, not \"you's gut parasites worsens\"")
end

function tests.terrainAfflictLavaUnharmedMessageAddressesThePlayerInSecondPerson()
  local level = arena(21, 11)
  level.map:set(5, 5, Tiles.LAVA)
  local game = stagedGame(1, level, 5, 5)
  game.player.resist = { fire = Resistances.IMMUNE }
  eq(Terrain.afflictLava(level, game.player), "you wade through the lava unharmed",
    "an immune player wading through lava is addressed in second person, not 'you wades through the lava unharmed'")
end

function tests.hazards()
  local level = arena(21, 11)

  local fire = Hazards.ignite(level, 5, 5, 3, 4)
  eq(fire.kind, Hazards.FIRE, "ignite drops a fire hazard")
  eq(Hazards.at(level, 5, 5, Hazards.FIRE), fire, "the hazard is found by its cell and kind")

  Hazards.ignite(level, 5, 5, 5, 1)
  eq(#level.hazards, 1, "re-igniting the same cell refreshes it instead of stacking a duplicate")
  eq(fire.duration, 5, "refreshing a hazard keeps the stronger of the two durations")
  eq(fire.potency, 4, "refreshing a hazard keeps the stronger of the two potencies")

  local victim = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local hpBefore = victim.hp
  local line = Hazards.afflict(level, victim)
  ok(contains(line, "flames"), "afflict describes a fire hazard as flames")
  eq(victim.hp, hpBefore - fire.potency, "standing in fire deals its potency in damage")
  eq(Status.has(victim, Status.BURNING), true, "fire afflict also lays down a burning status")

  local elsewhere = Monsters.create(Monsters.byKey.rat, 2, 9, 9, 1)
  eq(Hazards.afflict(level, elsewhere), nil, "afflict does nothing to an entity off any hazard cell")

  local gas = Hazards.spawnGas(level, 12, 8, 4, 2)
  eq(gas.kind, Hazards.GAS, "spawnGas drops a gas hazard")
  local choker = Monsters.create(Monsters.byKey.rat, 3, 12, 8, 1)
  local gasLine = Hazards.afflict(level, choker)
  ok(contains(gasLine, "fumes"), "afflict describes a gas hazard as fumes")
  eq(Status.has(choker, Status.POISON), true, "gas afflict lays down a poison status")

  local wet = arena(21, 11)
  wet.map:set(6, 6, Tiles.WATER)
  Hazards.ignite(wet, 6, 6, 3, 2)
  Hazards.step(wet, Rng.new(1))
  eq(Hazards.at(wet, 6, 6, Hazards.FIRE), nil,
    "fire sitting on water is doused on the very next environmental step")

  local fading = arena(21, 11)
  Hazards.spawn(fading, 15, 5, Hazards.FIRE, 1, 2)
  Hazards.step(fading, Rng.new(1))
  eq(Hazards.at(fading, 15, 5, Hazards.FIRE), nil, "a hazard is removed once its duration runs out")

  local spread = false
  for seed = 1, 200 do
    local field = arena(21, 11)
    Hazards.ignite(field, 10, 5, 3, 2)
    Hazards.step(field, Rng.new(seed))
    if Hazards.at(field, 11, 5) or Hazards.at(field, 9, 5)
      or Hazards.at(field, 10, 4) or Hazards.at(field, 10, 6) then
      spread = true
      break
    end
  end
  ok(spread, "fire eventually spreads into open neighbouring floor on some seed")

  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  Hazards.ignite(rendered.level, 5, 6, 3, 2)
  rendered:computeVisible()
  ok(contains(rendered:render(), "`"), "a fire hazard on a visible cell renders as its glyph")
end

local function shrinePlayer(gold)
  return { gold = gold, attack = 5, baseAttack = 5, maxHp = 30, hp = 30, maxMana = 10, mana = 10,
    statuses = {} }
end

function tests.shrinePrayGrantsWarBlessingWhenFavorHolds()
  local player = shrinePlayer(50)
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.WAR, uses = 0 }
  local success, lines = Shrines.pray(game, shrine)
  eq(success, true, "a prayer with enough gold always resolves")
  eq(player.gold, 30, "the shrine's base price is deducted from the wallet")
  eq(player.attack, 6, "a war blessing raises attack")
  eq(player.baseAttack, 6, "a war blessing raises base attack permanently")
  eq(shrine.uses, 1, "a prayer advances the shrine's use count")
  ok(contains(lines[2], "favor"), "the blessing is logged")
end

function tests.shrinePrayGrantsVitalityBlessing()
  local player = shrinePlayer(50)
  player.hp = 20
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.VITALITY, uses = 0 }
  Shrines.pray(game, shrine)
  eq(player.maxHp, 35, "a vitality blessing raises max hp")
  eq(player.hp, 25, "a vitality blessing heals by the same amount as the max hp gain")
end

function tests.shrinePrayGrantsWisdomBlessing()
  local player = shrinePlayer(50)
  player.mana = 2
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.WISDOM, uses = 0 }
  Shrines.pray(game, shrine)
  eq(player.maxMana, 13, "a wisdom blessing raises max mana")
  eq(player.mana, 13, "a wisdom blessing refills mana to the new max")
end

function tests.shrinePrayGrantsFortuneBlessingAndCleansesAilments()
  local player = shrinePlayer(50)
  Status.apply(player, Status.POISON, 5, 2)
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.FORTUNE, uses = 0 }
  Shrines.pray(game, shrine)
  eq(Status.has(player, Status.POISON), false, "a fortune blessing cleanses poison")
  eq(Status.has(player, Status.SHIELD), true, "a fortune blessing also wards the petitioner")
end

function tests.shrinePrayCanCurseInsteadOfBless()
  local player = shrinePlayer(50)
  local game = { player = player, rng = Rng.new(2) }
  local shrine = { x = 1, y = 1, kind = Shrines.WAR, uses = 0 }
  local success, lines = Shrines.pray(game, shrine)
  eq(success, true, "a cursed prayer still resolves and spends its price")
  eq(player.gold, 30, "a curse still costs the shrine's price")
  eq(player.attack, 5, "a curse grants no blessing")
  eq(Status.has(player, Status.WEAKEN), true, "a curse weakens the petitioner")
  eq(Status.has(player, Status.SLOW), true, "a curse slows the petitioner")
  ok(contains(lines[2], "against you"), "the curse is logged")
end

function tests.shrinePrayFailsWithoutEnoughGold()
  local player = shrinePlayer(5)
  local game = { player = player, rng = Rng.new(1) }
  local shrine = { x = 1, y = 1, kind = Shrines.WAR, uses = 0 }
  local success, lines = Shrines.pray(game, shrine)
  eq(success, false, "a prayer the player cannot afford fails outright")
  eq(player.gold, 5, "a failed prayer spends no gold")
  eq(shrine.uses, 0, "a failed prayer does not advance the use count")
  ok(contains(lines[1], "afford"), "the failure is logged")
end

function tests.shrineCostAndCurseOddsRiseWithUse()
  eq(Shrines.costFor({ uses = 0 }), 20, "an untouched shrine charges its base price")
  eq(Shrines.costFor({ uses = 3 }), 50, "the price climbs by a fixed step per prior use")
  local n0, d0 = Shrines.curseChance({ uses = 0 })
  eq(n0, 1, "an untouched shrine risks a curse on one face of the die")
  eq(d0, 6, "curse odds are read against six faces")
  local n5 = Shrines.curseChance({ uses = 10 })
  eq(n5, 6, "curse odds cap out at a certainty rather than exceeding the die")
end

function tests.shrineFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.shrines = { { x = 4, y = 4, kind = Shrines.FORTUNE, uses = 2 } }
  local restored = Level.fromData(level:toData())
  eq(#restored.shrines, 1, "the shrine list survives a round trip")
  eq(restored.shrines[1].kind, Shrines.FORTUNE, "a shrine's kind survives a round trip")
  eq(restored.shrines[1].uses, 2, "a shrine's use count survives a round trip")
end

function tests.builderOccasionallyPlacesAShrineFromDepthFour()
  local level = Builder.build(4, Rng.new(1), {})
  ok(#level.shrines >= 1, "this seed's depth-4 floor places a shrine")
  eq(level.shrines[1].uses, 0, "a freshly built shrine starts unused")
end

function tests.shrinesStayOffTheShallowFloors()
  for seed = 1, 5 do
    for depth = 1, 3 do
      local level = Builder.build(depth, Rng.new(seed), {})
      eq(#level.shrines, 0, "no shrine appears above depth 4")
    end
  end
end

function tests.autopilotPraysAtAnUnspentShrineWhenAffordable()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.gold = 50
  game.level.shrines = { { x = 5, y = 5, kind = Shrines.WAR, uses = 0 } }
  game:choosePlayerAction()
  eq(game.level.shrines[1].uses, 1, "the autopilot prays at an unspent shrine it stands on")
  ok(game.player.gold < 50, "the autopilot's prayer spends the shrine's price")
end

function tests.autopilotSkipsAnAlreadyUsedShrine()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.gold = 50
  game.level.shrines = { { x = 5, y = 5, kind = Shrines.WAR, uses = 1 } }
  game:choosePlayerAction()
  eq(game.level.shrines[1].uses, 1, "the autopilot never re-prays at a shrine it has already used")
end

function tests.shrineRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  rendered.level.shrines = { { x = 5, y = 6, kind = Shrines.WAR, uses = 0 } }
  rendered:computeVisible()
  ok(contains(rendered:render(), "_"), "a shrine on a visible cell renders as its glyph")
end

function tests.messageLog()
  local log = MessageLog.new(3)
  for i = 1, 5 do log:add("line " .. i) end
  eq(#log.lines, 3, "the log keeps only its capacity")
  eq(log:last(), "line 5", "the newest line is retained")
  local recent = log:recent(2)
  eq(recent[1], "line 4", "recent returns the tail in order")
  eq(recent[2], "line 5", "recent ends on the newest line")
end

function tests.weaponAffixOnHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[3])
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 30, 30
  game.level.entities = { orc }
  game:playerAttack(orc)
  eq(Status.has(orc, Status.BURNING), true, "a flaming weapon ignites what it hits")
end

function tests.progressionLeveling()
  local player = {
    level = 1, xp = 0, xpNext = Progression.xpToNext(1),
    hp = 20, maxHp = 20, attack = 5, baseAttack = 5, defense = 1, baseDefense = 1,
  }
  local lines = Progression.grantXp(player, 5)
  eq(#lines, 0, "an xp gain under the threshold produces no level-up")
  eq(player.xp, 5, "xp accumulates")

  lines = Progression.grantXp(player, 100)
  eq(player.level > 1, true, "a large xp gain levels the player up")
  eq(#lines, player.level - 1, "one log line is produced per level gained")
  eq(player.maxHp > 20, true, "leveling raises max hp")
  eq(player.hp, player.maxHp, "leveling tops up hp by the same amount as the max hp gain")
  eq(player.attack > 5, true, "leveling raises attack")
  ok(player.xp < player.xpNext, "leftover xp after leveling stays below the new threshold")
end

function tests.progressionMonsterKillGrantsXp()
  local game = stagedGame(9, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:playerAttack(rat)
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "felling a monster in melee grants its xp")
  eq(#game.level.entities, 0, "the dead monster is swept from the level")
end

function tests.spellCastMissileKillsAndGrantsXp()
  local game = stagedGame(5, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  local manaBefore = game.player.mana
  local success = game:castSpell("missile", rat)
  eq(success, true, "a known spell in range with a clear shot casts successfully")
  eq(game.player.mana, manaBefore - Spells.catalog.missile.cost, "casting spends mana")
  eq(#game.level.entities, 0, "the missile kills the rat and sweeps it from the level")
  eq(game.player.xp, Monsters.xpFor(rat), "a spell kill grants xp same as a melee kill")
end

function tests.spellCastFailsWithoutSpendingState()
  local game = stagedGame(5, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.mana = 0
  local success = game:castSpell("missile", rat)
  eq(success, false, "casting without enough mana fails")
  eq(game.player.mana, 0, "a failed cast does not touch mana")
  eq(rat.hp, rat.maxHp, "a failed cast deals no damage")

  game.player.mana = 10
  local success2 = game:castSpell("heal")
  eq(success2, false, "casting a spell that exists but was never learned fails")
  eq(game.player.mana, 10, "an unlearned spell cast spends no mana")

  local success3 = game:castSpell("fireball", rat)
  eq(success3, false, "casting a key that matches no spell in the catalog fails")
end

function tests.spellLearnFromTome()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  eq(Spells.knows(game.player, "heal"), false, "the starting kit does not know heal")
  game.player.inventory[#game.player.inventory + 1] = Items.tome("heal")
  game:useItem(#game.player.inventory)
  eq(Spells.knows(game.player, "heal"), true, "reading a tome permanently learns its spell")

  local before = #game.player.inventory
  game.player.inventory[#game.player.inventory + 1] = Items.tome("heal")
  game:useItem(#game.player.inventory)
  eq(#game.player.inventory, before, "the tome is consumed whether or not the spell was new")
end

function tests.spellHealAndShield()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  Spells.learn(game.player, "heal")
  Spells.learn(game.player, "shield")
  game.player.hp = 10
  local manaBefore = game.player.mana
  game:castSpell("heal")
  eq(game.player.hp > 10, true, "the heal spell restores hp")
  eq(game.player.mana, manaBefore - Spells.catalog.heal.cost, "casting heal spends its mana cost")

  local defenseBefore = game.player:effectiveDefense()
  game:castSpell("shield")
  eq(game.player:effectiveDefense() > defenseBefore, true, "the shield spell raises effective defense")
  ok(Status.has(game.player, Status.SHIELD), "shield applies the shield status")
end

function tests.spellBlinkMovesWithinRadius()
  local game = stagedGame(3, arena(21, 11), 10, 6)
  Spells.learn(game.player, "blink")
  local startX, startY = game.player.x, game.player.y
  local success = game:castSpell("blink")
  eq(success, true, "blink casts when mana and known")
  local moved = game.player.x ~= startX or game.player.y ~= startY
  ok(moved, "blink relocates the caster")
  local dist = math.max(math.abs(game.player.x - startX), math.abs(game.player.y - startY))
  ok(dist <= 5, "blink lands within its radius")
  eq(game.level.map:isWalkable(game.player.x, game.player.y), true, "blink lands on walkable ground")
end

function tests.manaRegeneratesEachTurn()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.mana = 0
  game.level.entities = {}
  game:endPlayerTurn()
  eq(game.player.mana, 1, "mana regenerates by one per player turn")
  game.player.mana = game.player.maxMana
  game:endPlayerTurn()
  eq(game.player.mana, game.player.maxMana, "mana regeneration is capped at max mana")
end

function tests.throwWeaponHitsAndLands()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  local dagger = Items.weapon("dagger", 2)
  game.player.inventory[#game.player.inventory + 1] = dagger
  local index = #game.player.inventory
  local before = #game.player.inventory
  local success = game:throwAt(index, rat)
  eq(success, true, "a weapon throw with a clear line succeeds")
  eq(#game.player.inventory, before - 1, "the thrown weapon leaves the inventory")
  eq(rat.hp, rat.maxHp - dagger.power * 2, "a thrown weapon deals double its melee power")
  local landed = game.level:itemsAt(rat.x, rat.y)
  eq(#landed, 1, "the thrown weapon lands on the ground at the target")
  eq(landed[1].item, dagger, "the landed item is the same weapon that was thrown")
end

function tests.throwWeaponKillGrantsXp()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.weapon("battle axe", 5)
  local xpBefore = game.player.xp
  game:throwAt(#game.player.inventory, rat)
  eq(#game.level.entities, 0, "a lethal throw sweeps the monster from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "a thrown-weapon kill grants xp")
end

function tests.throwPotionAppliesHostileEffect()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("poison", 3)
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.POISON), true, "a thrown poison potion poisons the target instead of the thrower")
  eq(Status.has(game.player, Status.POISON), false, "the thrower is untouched by their own thrown potion")
  eq(Hazards.at(game.level, rat.x, rat.y, Hazards.GAS) ~= nil, true,
    "a shattered poison potion leaves a lingering cloud of fumes")
end

function tests.throwConfusePotionAppliesTheStatusToTheTargetNotTheThrower()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("confuse")
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a confuse potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.CONFUSE), true, "a thrown confuse potion confuses the target instead of the thrower")
  eq(Status.has(game.player, Status.CONFUSE), false, "the thrower is untouched by their own thrown potion")
end

function tests.throwBlindPotionAppliesTheStatusToTheTargetNotTheThrower()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("blind")
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a blind potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.BLIND), true, "a thrown blind potion blinds the target instead of the thrower")
  eq(Status.has(game.player, Status.BLIND), false, "the thrower is untouched by their own thrown potion")
end

function tests.throwLevitatePotionAppliesTheStatusToTheTargetNotTheThrower()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 6, 6, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.potionOf("levitate")
  local success = game:throwAt(#game.player.inventory, rat)
  eq(success, true, "a levitation potion throw with a clear line succeeds")
  eq(Status.has(rat, Status.LEVITATE), true, "a thrown levitation potion lifts the target instead of the thrower")
  eq(Status.has(game.player, Status.LEVITATE), false, "the thrower is untouched by their own thrown potion")
end

function tests.throwOutOfRangeFails()
  local game = stagedGame(4, arena(21, 11), 2, 2)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 19, 9, 1)
  game.level.entities = { rat }
  game.player.inventory[#game.player.inventory + 1] = Items.weapon("dagger", 2)
  local index = #game.player.inventory
  local before = #game.player.inventory
  local success = game:throwAt(index, rat)
  eq(success, false, "a throw beyond range fails")
  eq(#game.player.inventory, before, "a failed throw does not consume the item")
  eq(rat.hp, rat.maxHp, "a failed throw deals no damage")
end

function tests.rangedShotHitsAtRangeAndConsumesAmmo()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game.level.entities = { orc }
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  local expected = game.player.baseAttack + 2 - orc:effectiveDefense()
  local success = game:fireAt(orc)
  eq(success, true, "firing at a target within range and line of sight succeeds")
  eq(orc.hp, orc.maxHp - expected, "the shot deals baseAttack plus bow power minus target defense")
  local stack
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then stack = item end
  end
  eq(stack.count, 1, "firing consumes one arrow from the stack")
  local landed = game.level:itemsAt(orc.x, orc.y)
  eq(#landed, 1, "the spent arrow lands where the target stood")
  eq(landed[1].item.kind, Items.AMMO, "the landed item is a spent arrow")
end

function tests.rangedShotKillGrantsXp()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 9, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  game.player.bow = Items.bow("long bow", 3, 7)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 1)
  local xpBefore = game.player.xp
  game:fireAt(rat)
  eq(#game.level.entities, 0, "a lethal shot sweeps the monster from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "a ranged kill grants xp")
end

function tests.rangedFailsWithoutAmmo()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 9, 6, 1)
  game.level.entities = { rat }
  game.player.bow = Items.bow("short bow", 2, 6)
  local success = game:fireAt(rat)
  eq(success, false, "firing without arrows fails")
  eq(rat.hp, rat.maxHp, "a failed shot deals no damage")
end

function tests.rangedFailsOutOfRange()
  local game = stagedGame(4, arena(21, 11), 2, 2)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 19, 9, 1)
  game.level.entities = { rat }
  game.player.bow = Items.bow("short bow", 2, 3)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 3)
  local success = game:fireAt(rat)
  eq(success, false, "firing beyond the bow's range fails")
  local stack
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then stack = item end
  end
  eq(stack.count, 3, "a failed shot does not consume ammunition")
end

function tests.ammoStacksOnPickup()
  local game = stagedGame(4, arena(21, 11), 3, 3)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  game.level.floorItems[#game.level.floorItems + 1] = { x = 3, y = 3, item = Items.ammo("arrow", 5) }
  game:pickupHere()
  local stacks, total = 0, 0
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then
      stacks = stacks + 1
      total = item.count
    end
  end
  eq(stacks, 1, "picking up matching ammo merges into a single stack")
  eq(total, 7, "the merged stack sums both counts")
end

function tests.trollRegenerateUnlessBurning()
  local troll = Monsters.create(Monsters.byKey.troll, 1, 5, 5, 1)
  troll.hp = troll.maxHp - 5
  local line = Abilities.regenTick(troll)
  ok(line ~= nil, "a damaged troll regenerates and logs it")
  eq(troll.hp, troll.maxHp - 5 + Monsters.byKey.troll.regen, "regen heals by the species regen amount")

  troll.hp = troll.maxHp
  eq(Abilities.regenTick(troll), nil, "a troll already at full hp produces no regen line")

  troll.hp = troll.maxHp - 5
  Status.apply(troll, Status.BURNING, 3, 2)
  eq(Abilities.regenTick(troll), nil, "burning suppresses troll regeneration")
end

function tests.ratHasNoRegen()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  rat.hp = 1
  eq(Abilities.regenTick(rat), nil, "a species without a regen tag never heals passively")
end

function tests.wretchDeathBurstsPoisonSpores()
  local game = stagedGame(1, arena(21, 11), 4, 6)
  local wretch = Monsters.create(Monsters.byKey.wretch, 1, 5, 6, 1)
  wretch.hp = 1
  game.level.entities = { wretch }
  eq(Status.has(game.player, Status.POISON), false, "the player starts unpoisoned")
  game:playerAttack(wretch)
  eq(Status.has(game.player, Status.POISON), true, "a wretch's death burst poisons an adjacent player")
  ok(contains(game.log:recent(3)[1] or "", "spores") or contains(game.log:recent(3)[2] or "", "spores")
    or contains(game.log:recent(3)[3] or "", "spores"), "the spore burst is logged")
end

function tests.dragonBreathIgnitesPlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local dragon = Monsters.create(Monsters.byKey.dragon, 1, 6, 6, 1)
  game.level.entities = { dragon }
  local hpBefore = game.player.hp
  Ai.act(game, dragon)
  ok(game.player.hp < hpBefore, "a dragon in range breathes fire for damage")
  eq(Status.has(game.player, Status.BURNING), true, "dragon breath ignites the player")
end

-- Layered special abilities: summon/curse/heal/rally run through
-- Abilities.tryAct, which gates on cooldown and range before falling through
-- to the species' ordinary ai.lua behaviour; split reacts to a survived hit;
-- steal is a stateful chase-steal-flee sequence with no cooldown at all.

function tests.necromancerSummonsZombie()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  game.level.entities = { necro }
  local acted = Abilities.tryAct(game, necro)
  eq(acted, true, "a necromancer in range summons instead of moving")
  eq(#game.level.entities, 2, "summoning adds a minion to the level")
  local minion = game.level.entities[2]
  eq(minion.species, "zombie", "the necromancer summons its configured species")
  eq(minion.summonedBy, necro.id, "the minion is tagged with its summoner's id")
  eq(necro.cooldown, 6, "summoning starts the ability's cooldown")
  ok(contains(game.log:last(), "calls forth"), "the summon is logged")
end

function tests.summonRespectsPopulationCap()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  local minionA = Monsters.create(Monsters.byKey.zombie, 2, 7, 6, 4)
  local minionB = Monsters.create(Monsters.byKey.zombie, 3, 6, 7, 4)
  minionA.summonedBy = necro.id
  minionB.summonedBy = necro.id
end

function tests.saveLoadRoundTrip()
  local game = Game.new(2024)
  for _ = 1, 80 do
    if not game.player:isAlive() then break end
    game:autoStep()
  end
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(Serialize.encode(restored:toData()), Serialize.encode(game:toData()), "state is byte-identical after round trip")
  eq(restored.player.hp, game.player.hp, "player hp survives round trip")
  eq(restored.depth, game.depth, "depth survives round trip")
  eq(restored.turn, game.turn, "turn survives round trip")
  eq(table.concat(restored.level.map.tiles), table.concat(game.level.map.tiles), "current map survives round trip")
  eq(#restored.level.entities, #game.level.entities, "monster count survives round trip")
  eq(restored:render(), game:render(), "render is identical after round trip")
end

function tests.deterministicPlaythrough()
  local a = Game.new(1337)
  local b = Game.new(1337)
  for _ = 1, 120 do
    if a.player:isAlive() then a:autoStep() end
    if b.player:isAlive() then b:autoStep() end
  end
  eq(a:render(), b:render(), "same seed yields the same playthrough")
  eq(a.player.hp, b.player.hp, "same seed yields the same player hp")
  eq(a.depth, b.depth, "same seed yields the same depth")
  local c = Game.new(4242)
  for _ = 1, 120 do if c.player:isAlive() then c:autoStep() end end
  ok(a:render() ~= c:render(), "a different seed diverges")
end

function tests.autoplayDescends()
  local function playout(seed)
    local game = Game.new(seed)
    for _ = 1, 600 do
      if not game.player:isAlive() then break end
      game:autoStep()
    end
    return game
  end
  local run = playout(2024)
  ok(run.depth >= 3, "the autopilot descends several levels")
  local again = playout(2024)
  eq(again.depth, run.depth, "the autopilot reaches the same depth on the same seed")
  eq(again.turn, run.turn, "the autopilot takes the same number of turns")
end

local order = {
  "rngDeterminism", "mapDeterminism", "tilesRegistry", "fovKnownScene", "losSightLine",
  "astarPathing", "combatResolution", "itemsAndEquipment", "affixes", "statusEffects",
  "scheduler", "generators", "connectivityRepair", "dungeonPersistence", "monsterAiChase", "monsterAiRanged",
  "monsterAiFlee", "monsterAiDeterministic", "doorsAndKeys", "traps", "lightAndDark",
  "identification", "effects", "messageLog", "weaponAffixOnHit", "saveLoadRoundTrip",
  "deterministicPlaythrough", "autoplayDescends",
}

for _, name in ipairs(order) do
  tests[name]()
  io.write(string.format("  %-26s ok\n", name))
end

io.write(string.format("\n%d tests, %d asserts, %d failed\n", #order, passed + failed, failed))
if failed > 0 then
  io.write("FAILURES:\n")
  for _, name in ipairs(failures) do
    io.write("  - " .. name .. "\n")
  end
  os.exit(1)
end
os.exit(0)
