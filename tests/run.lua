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
  game.level.entities = { necro, minionA, minionB }
  local acted = Abilities.tryAct(game, necro)
  eq(acted, false, "a necromancer already at its summon cap does not summon a third")
  eq(#game.level.entities, 3, "the level still has exactly the two existing minions")
end

function tests.curseAtRangeHurtsAndWeakens()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  local hpBefore = game.player.hp
  local acted = Abilities.tryAct(game, shaman)
  eq(acted, true, "a shaman with a clear shot curses instead of moving")
  eq(game.player.hp, hpBefore - 1, "the curse bolt runs through Combat.damage (shaman attack 2 minus the player's base defense 1)")
  eq(Status.has(game.player, Status.WEAKEN), true, "the curse also weakens the player")
  eq(shaman.cooldown, 4, "casting the curse starts its cooldown")
  ok(contains(game.log:last(), "curses you for 1"), "the logged amount matches the mitigated damage, not a flat number")
end

-- The curse bolt used to bypass Combat.damage entirely (a flat, unmitigated
-- subtraction from hp), so a shaman hit for the same 3 no matter how armored
-- the player was, never broke a melee combo, and never wore armor - every
-- other monster-on-player attack (monsterMelee, monsterShoot, mimic/grave
-- ambush) already ran through Combat.damage + Momentum.onDamaged +
-- Durability.wearArmor. These three lock in the fix.
function tests.curseDamageIsMitigatedByThePlayersDefenseLikeAnyOtherAttack()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  game.player.defense = game.player.defense + 10
  local hpBefore = game.player.hp
  Abilities.tryAct(game, shaman)
  eq(game.player.hp, hpBefore - 1, "a shaman's attack (2) minus a heavily-defended player floors at Combat.damage's minimum of 1, not a flat 3")
end

function tests.curseBreaksThePlayersMeleeMomentumStack()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  game.player.combo = 4
  Abilities.tryAct(game, shaman)
  eq(Momentum.stacks(game.player), 0, "a landed curse bolt snaps momentum to zero exactly like a melee hit or a breath attack")
end

function tests.curseWearsThePlayersEquippedArmor()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  game.player.armor = { name = "chainmail", kind = Items.ARMOR, power = 2, defense = 2 }
  Durability.ensure(game.player.armor)
  local durabilityBefore = game.player.armor.durability
  Abilities.tryAct(game, shaman)
  eq(game.player.armor.durability, durabilityBefore - 1, "the curse wears equipped armor exactly like a landed melee or breath hit does")
end

function tests.curseWithheldWhenAdjacent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 4, 6, 4)
  game.level.entities = { shaman }
  local acted = Abilities.tryAct(game, shaman)
  eq(acted, false, "a shaman standing next to the player withholds its curse")
end

function tests.shriekAtRangeBlindsThePlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 7, 6, 5)
  game.level.entities = { banshee }
  eq(Status.has(game.player, Status.BLIND), false, "the player starts able to see")
  local acted = Abilities.tryAct(game, banshee)
  eq(acted, true, "a banshee with a clear shot shrieks instead of moving")
  eq(Status.has(game.player, Status.BLIND), true, "the shriek blinds the player")
  eq(banshee.cooldown, 6, "shrieking starts its cooldown")
  ok(contains(game.log:last(), "blinds you"), "the shriek is logged")
end

function tests.shriekWithheldWhenAdjacent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 4, 6, 5)
  game.level.entities = { banshee }
  local acted = Abilities.tryAct(game, banshee)
  eq(acted, false, "a banshee standing next to the player withholds its shriek")
  eq(Status.has(game.player, Status.BLIND), false, "no shriek means no blindness")
end

function tests.shriekIsUnavailableOutOfRange()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 20, 6, 5)
  game.level.entities = { banshee }
  local acted = Abilities.tryAct(game, banshee)
  eq(acted, false, "a banshee out of shriek range falls through to its base ai")
  eq(Status.has(game.player, Status.BLIND), false, "no shriek means no blindness")
end

function tests.shriekBlindnessReducesTheVictimsEffectiveSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local banshee = Monsters.create(Monsters.byKey.banshee, 1, 7, 6, 5)
  game.level.entities = { banshee }
  Abilities.tryAct(game, banshee)
  eq(game:effectiveRadius(), 1, "blind (also inflicted by a banshee) still narrows sight to game.lua's own radius")
end

function tests.abilityCooldownBlocksImmediateReuse()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local shaman = Monsters.create(Monsters.byKey.shaman, 1, 7, 6, 4)
  game.level.entities = { shaman }
  Abilities.tryAct(game, shaman)
  local hpAfterFirst = game.player.hp
  local acted = Abilities.tryAct(game, shaman)
  eq(acted, false, "an ability on cooldown does not fire again")
  eq(game.player.hp, hpAfterFirst, "no further damage is dealt while on cooldown")
  for _ = 1, 4 do Abilities.tickCooldown(shaman) end
  eq(shaman.cooldown, 0, "four ticks fully drains a four-turn cooldown")
  local actedAgain = Abilities.tryAct(game, shaman)
  eq(actedAgain, true, "the ability is usable again once its cooldown has ticked down")
end

function tests.healerMendsNeediestAlly()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local cleric = Monsters.create(Monsters.byKey.cleric, 1, 6, 6, 5)
  local hurt = Monsters.create(Monsters.byKey.rat, 2, 8, 6, 5)
  hurt.hp = 1
  game.level.entities = { cleric, hurt }
  local acted = Abilities.tryAct(game, cleric)
  eq(acted, true, "a cleric with a hurt ally in sight heals instead of moving")
  eq(hurt.hp, 7, "healing restores the fixed amount, capped at max hp")
  eq(cleric.cooldown, 5, "healing starts its cooldown")
end

function tests.healerSkipsWhenAlliesAreHealthy()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local cleric = Monsters.create(Monsters.byKey.cleric, 1, 6, 6, 5)
  local ally = Monsters.create(Monsters.byKey.rat, 2, 8, 6, 5)
  game.level.entities = { cleric, ally }
  local acted = Abilities.tryAct(game, cleric)
  eq(acted, false, "a cleric with no hurt allies falls through to its base ai")
end

function tests.rallyBuffsAdjacentAllies()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 10, 6, 6)
  local grunt = Monsters.create(Monsters.byKey.goblin, 2, 11, 6, 6)
  game.level.entities = { chieftain, grunt }
  eq(Status.has(grunt, Status.STRENGTH), false, "the grunt starts unbuffed")
  local acted = Abilities.tryAct(game, chieftain)
  eq(acted, true, "a chieftain next to an unbuffed ally rallies instead of moving")
  eq(Status.has(grunt, Status.STRENGTH), true, "rallying buffs the adjacent ally")
  eq(Status.has(chieftain, Status.STRENGTH), true, "rallying also buffs the chieftain itself")
  eq(chieftain.cooldown, 8, "rallying starts its cooldown")
end

function tests.rallySkipsWhenNoUnbuffedAlliesAdjacent()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 10, 6, 6)
  game.level.entities = { chieftain }
  local acted = Abilities.tryAct(game, chieftain)
  eq(acted, false, "a chieftain with no adjacent allies falls through to its base ai")
end

function tests.healerNeverMendsThePlayersOwnCompanionHirelingOrThrall()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local cleric = Monsters.create(Monsters.byKey.cleric, 1, 6, 6, 5)
  local companion = Companions.summon(game, "hound")
  companion.x, companion.y = 8, 6
  companion.hp = 1
  game.level.entities = { cleric, companion }
  local acted = Abilities.tryAct(game, cleric)
  eq(acted, false, "a hurt companion is not a valid heal target, so the cleric falls through instead")
  eq(companion.hp, 1, "the player's own companion is left exactly as hurt as it was")
end

function tests.rallyNeverBuffsThePlayersOwnCompanionHirelingOrThrall()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 10, 6, 6)
  local companion = Companions.summon(game, "hound")
  companion.x, companion.y = 11, 6
  game.level.entities = { chieftain, companion }
  local acted = Abilities.tryAct(game, chieftain)
  eq(acted, false, "an adjacent companion is not a valid rally target, so the chieftain falls through instead")
  eq(Status.has(companion, Status.STRENGTH), false, "the player's own companion is never buffed by a hostile chieftain")
  eq(Status.has(chieftain, Status.STRENGTH), false, "the chieftain does not even buff itself when it has no monster ally to rally")
end

function tests.footpadStealsThenFlees()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local footpad = Monsters.create(Monsters.byKey.footpad, 1, 4, 6, 4)
  game.level.entities = { footpad }
  local before = #game.player.inventory
  local acted = Abilities.tryAct(game, footpad)
  eq(acted, true, "an adjacent footpad steals instead of attacking")
  eq(#game.player.inventory, before - 1, "the stolen item leaves the player's inventory")
  eq(footpad.fleeing, true, "the footpad starts fleeing after the theft")
  ok(contains(game.log:last(), "steals"), "the theft is logged")

  local xBefore = footpad.x
  local actedAgain = Abilities.tryAct(game, footpad)
  eq(actedAgain, true, "a fleeing footpad keeps acting through its ability")
  eq(#game.player.inventory, before - 1, "a fleeing footpad does not steal again")
  ok(footpad.x ~= xBefore, "a fleeing footpad moves away from the player")
end

function tests.footpadWithNothingToStealStillFlees()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.inventory = {}
  local footpad = Monsters.create(Monsters.byKey.footpad, 1, 4, 6, 4)
  game.level.entities = { footpad }
  local acted = Abilities.tryAct(game, footpad)
  eq(acted, true, "a footpad with nothing to steal still consumes its turn")
  eq(footpad.fleeing, true, "it flees even without a prize")
  ok(contains(game.log:last(), "nothing worth stealing"), "the empty-handed theft attempt is logged")
end

function tests.slimeSplitsOnSurvivedHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local slime = Monsters.create(Monsters.byKey.slime, 1, 4, 6, 4)
  game.level.entities = { slime }
  eq(slime.hp, 13, "a depth-4 slime spawns with its bonus hp")
  game:playerAttack(slime)
  eq(slime:isAlive(), true, "the slime survives a single hit")
  eq(slime.maxHp, 6, "a surviving split halves the slime's max hp")
  eq(slime.hp, 6, "the split slime is left at its new max hp")
  eq(#game.level.entities, 2, "the split spawns a clone next to the original")
  local clone = game.level.entities[2]
  eq(clone.species, "slime", "the clone is the same species as the original")
  eq(clone.maxHp, 6, "the clone shares the halved max hp")
  eq(clone.splitGen, 1, "the clone is tagged as a first-generation split")
  ok(contains(game.log:last(), "splits in two"), "the split is logged")
end

function tests.splitCapsAtTwoGenerations()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local slime = Monsters.create(Monsters.byKey.slime, 1, 4, 6, 4)
  slime.splitGen = 2
  game.level.entities = { slime }
  local before = #game.level.entities
  local line = Abilities.onHit(game, slime)
  eq(line, nil, "a slime that already split twice does not split again")
  eq(#game.level.entities, before, "no clone is added once the split cap is reached")
end

function tests.takeMonsterTurnPrefersAbilityOverMovement()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  game.level.entities = { necro }
  game:takeMonsterTurn(necro)
  eq(necro.x, 6, "summoning consumes the turn instead of the necromancer's flee movement")
  eq(necro.y, 6, "summoning leaves the necromancer's y unchanged too")
  eq(#game.level.entities, 2, "the full turn pipeline invokes the summon ability")
end

function tests.takeMonsterTurnFallsBackToAiWhenOnCooldown()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local necro = Monsters.create(Monsters.byKey.necromancer, 1, 6, 6, 4)
  necro.cooldown = 3
  game.level.entities = { necro }
  game:takeMonsterTurn(necro)
  eq(#game.level.entities, 1, "no minion is summoned while the ability is on cooldown")
  eq(necro.cooldown, 2, "the cooldown ticks down even on a turn spent fleeing")
  ok(necro.x ~= 6 or necro.y ~= 6, "the necromancer falls back to its flee ai instead")
end

function tests.abilityFieldsSurviveSerialization()
  local necro = Monsters.create(Monsters.byKey.necromancer, 5, 6, 6, 4)
  necro.cooldown = 3
  necro.fleeing = true
  necro.splitGen = 1
  necro.summonedBy = 2
  necro.stolen = Items.potion(10)
  local restored = Entity.fromData(necro:toData())
  eq(restored.ability, "summon", "the ability tag survives a round trip")
  eq(restored.summonSpecies, "zombie", "the summon species survives a round trip")
  eq(restored.cooldown, 3, "cooldown survives a round trip")
  eq(restored.fleeing, true, "the fleeing flag survives a round trip")
  eq(restored.splitGen, 1, "the split generation survives a round trip")
  eq(restored.summonedBy, 2, "the summoner id survives a round trip")
  eq(restored.stolen.name, "potion of healing", "a stolen item's data survives a round trip")
end

function tests.statusEffectKillGrantsXpAndLogsDeath()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 15, 9, 1)
  Status.apply(rat, Status.POISON, 1, 50)
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:takeMonsterTurn(rat)
  eq(#game.level.entities, 0, "a monster that dies to its own status tick is swept from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "dying to a status effect still grants its xp")
  ok(contains(game.log:recent(4)[1] or "", "dies") or contains(game.log:recent(4)[2] or "", "dies")
    or contains(game.log:recent(4)[3] or "", "dies") or contains(game.log:recent(4)[4] or "", "dies"),
    "the status-effect kill is logged as a death")
end

function tests.hazardKillDuringMonsterTurnGrantsXp()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 15, 9, 1)
  rat.hp = 1
  Hazards.ignite(game.level, rat.x, rat.y, 3, 50)
  game.level.entities = { rat }
  local xpBefore = game.player.xp
  game:takeMonsterTurn(rat)
  eq(#game.level.entities, 0, "a monster that dies standing in fire is swept from the level")
  eq(game.player.xp, xpBefore + Monsters.xpFor(rat), "dying to a hazard still grants its xp")
end

function tests.hazardStepRunsOncePerPlayerRound()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local px, py = game.player.x, game.player.y
  Hazards.ignite(game.level, px, py, 1, 3)
  local hpBefore = game.player.hp
  game:autoStep()
  eq(game.player.hp, hpBefore - 3, "the player takes hazard damage while standing in fire on their turn")
  eq(Hazards.at(game.level, px, py, Hazards.FIRE), nil,
    "the hazard's duration is spent by the environmental step at the end of the round")
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
  -- Seed re-picked when the blind potion/trap effect joined the shared loot
  -- and trap-effect tables (builder.lua): appending a new outcome changes the
  -- denominator of every rng:range(1, #effects) draw those tables feed, which
  -- reshuffles the whole downstream procedural sequence for any fixed seed -
  -- 2024 itself did not get more dangerous, its particular draw just moved.
  local run = playout(2025)
  ok(run.depth >= 3, "the autopilot descends several levels")
  local again = playout(2025)
  eq(again.depth, run.depth, "the autopilot reaches the same depth on the same seed")
  eq(again.turn, run.turn, "the autopilot takes the same number of turns")
end

function tests.amuletSpawnsOnFinalFloorOnly()
  local finalLevel = Builder.build(Builder.MAX_DEPTH, Rng.new(999), {})
  local finalCount = 0
  for _, ground in ipairs(finalLevel.floorItems) do
    if ground.item.kind == Items.AMULET then finalCount = finalCount + 1 end
  end
  eq(finalCount, 1, "exactly one amulet is placed on the final floor")

  local shallowLevel = Builder.build(Builder.MAX_DEPTH - 1, Rng.new(999), {})
  local shallowCount = 0
  for _, ground in ipairs(shallowLevel.floorItems) do
    if ground.item.kind == Items.AMULET then shallowCount = shallowCount + 1 end
  end
  eq(shallowCount, 0, "no amulet appears above the final floor")
end

function tests.descendIsBlockedAtTheFinalFloor()
  local game = Game.new(555)
  game.depth = game.maxDepth
  game.level = game.dungeon:get(game.maxDepth)
  game.player.x, game.player.y = game.level.downX, game.level.downY
  local result = game:descend()
  eq(result, false, "descend fails once at the final floor")
  eq(game.depth, game.maxDepth, "depth is unchanged after a blocked descend")
  ok(contains(game.log:last(), "rock"), "a message explains why the descent is blocked")
end

function tests.ascendWithoutAmuletDoesNotWin()
  local game = Game.new(7)
  game.player.x, game.player.y = game.level.upX, game.level.upY
  local result = game:ascend()
  eq(result, true, "climbing out at depth 1 is still a valid move")
  eq(game.won, false, "climbing out without the amulet does not win the game")
end

function tests.ascendWithAmuletWinsTheGame()
  local game = Game.new(7)
  game.player.inventory[#game.player.inventory + 1] = Items.amulet()
  game.player.x, game.player.y = game.level.upX, game.level.upY
  local result = game:ascend()
  eq(result, true, "climbing out at depth 1 with the amulet succeeds")
  eq(game.won, true, "carrying the amulet to the surface wins the game")
  ok(contains(game.log:last(), "win"), "the victory is logged")
end

function tests.wonGameHaltsTheAutopilot()
  local game = Game.new(7)
  game.won = true
  local turnBefore = game.turn
  game:autoStep()
  eq(game.turn, turnBefore, "autoStep is a no-op once the game is already won")
end

function tests.autopilotFetchesTheAmuletAndWins()
  local function playout(seed)
    local game = Game.new(seed, { maxDepth = 3 })
    for _ = 1, 900 do
      if not game.player:isAlive() or game.won then break end
      game:autoStep()
    end
    return game
  end
  local run = playout(67)
  ok(run.player:isAlive(), "the autopilot survives the round trip on this seed")
  eq(run.won, true, "the autopilot retrieves the amulet and escapes")
  eq(run.depth, 1, "winning leaves the player back at depth 1")
  ok(run:hasAmulet(), "the amulet is still in the winning player's inventory")
  local again = playout(67)
  eq(again.turn, run.turn, "the winning playthrough takes the same number of turns on the same seed")
end

function tests.shopPriceCatalogScalesWithPower()
  local base = Shop.priceOf(Items.weapon("dagger", 2))
  local strong = Shop.priceOf(Items.weapon("battle axe", 5))
  ok(strong > base, "a more powerful weapon costs more at the shop")
  eq(Shop.priceOf(Items.potionOf("heal")), 15, "a catalogued potion has its fixed price")
  eq(Shop.sellValue(Items.potionOf("heal")), 7, "selling nets half the catalog price, rounded down")
end

function tests.shopStockRollsAffordableWares()
  local wares = Shop.stock(Rng.new(7))
  ok(#wares >= 3 and #wares <= 5, "a shop rolls three to five wares")
  for _, item in ipairs(wares) do
    ok(Shop.priceOf(item) > 0, "every ware has a positive price")
  end
end

function tests.goldPickupAddsToWalletNotInventory()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local before = #game.player.inventory
  local goldBefore = game.player.gold
  game.level.floorItems = { { x = 4, y = 3, item = Items.gold(35) } }
  game:movePlayer(1, 0)
  eq(game.player.gold, goldBefore + 35, "walking onto gold adds it to the wallet")
  eq(#game.player.inventory, before, "gold never occupies an inventory slot")
  eq(#game.level.floorItems, 0, "the gold pile is removed from the floor")
end

function tests.affordableWareIsBoughtAutomaticallyOnPickup()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 50
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 35, "the ware's stamped price is deducted from the wallet")
  eq(#game.player.inventory, before + 1, "the bought ware joins the inventory")
  eq(#game.level.floorItems, 0, "the purchased ware leaves the ground")
end

function tests.unaffordableWareStaysOnTheGround()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 5
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 5, "an unaffordable ware is never bought, so no gold changes hands")
  eq(#game.player.inventory, before, "the ware never reaches the inventory")
  eq(#game.level.floorItems, 1, "the unbought ware is left in place")
end

function tests.deadKeeperMakesWaresFreeToLoot()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  keeper.hp = 0
  game.level.entities = { keeper }
  game.player.gold = 0
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.potionOf("heal"), price = 15, shopId = keeper.id } }
  game:movePlayer(1, 0)
  eq(game.player.gold, 0, "looting a dead keeper's stock costs nothing")
  eq(#game.player.inventory, before + 1, "the ware is picked up normally once its keeper is dead")
end

function tests.stealingFromShopTurnsTheKeeperHostile()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 10, 10, 4)
  game.level.entities = { keeper }
  game.player.gold = 0
  local before = #game.player.inventory
  game.level.floorItems = { { x = 4, y = 3, item = Items.scroll("identify"), price = 18, shopId = keeper.id } }
  local stolen = game:stealFromShop(1)
  eq(stolen, true, "stealing succeeds against a live keeper's ware")
  eq(game.player.gold, 0, "theft costs no gold")
  eq(#game.player.inventory, before + 1, "the stolen item joins the inventory")
  eq(keeper.hostile, true, "the keeper turns hostile after the theft")
  ok(contains(game.log:last(), "steal"), "the theft is logged")
end

function tests.hostileShopkeeperChasesLikeAnyMonster()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 8, 6, 4)
  keeper.hostile = true
  game.level.entities = { keeper }
  Ai.act(game, keeper)
  eq(keeper.x, 7, "a hostile shopkeeper closes in on the player like a chaser")
end

function tests.passiveShopkeeperIgnoresTheAdjacentPlayer()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local keeper = Monsters.create(Monsters.byKey.shopkeeper, 1, 4, 6, 4)
  game.level.entities = { keeper }
  local hpBefore = game.player.hp
  Ai.act(game, keeper)
  eq(keeper.x, 4, "an un-robbed shopkeeper does not move")
  eq(game.player.hp, hpBefore, "an un-robbed shopkeeper does not attack even when adjacent")
end

function tests.sellItemGrantsHalfPriceAndRemovesIt()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local index = #game.player.inventory
  local item = game.player.inventory[index]
  local expected = Shop.sellValue(item)
  local goldBefore = game.player.gold
  local value = game:sellItem(index)
  eq(value, expected, "selling returns the catalog half-price")
  eq(game.player.gold, goldBefore + expected, "the sale proceeds land in the wallet")
  eq(#game.player.inventory, index - 1, "the sold item leaves the inventory")
end

function tests.builderOccasionallySeedsAShopWithMatchingWares()
  local level = Builder.build(4, Rng.new(1), {})
  local keeper
  for _, e in ipairs(level.entities) do
    if e.species == "shopkeeper" then keeper = e end
  end
  ok(keeper ~= nil, "this seed's depth-4 floor spawns a shopkeeper")
  local waresFound = 0
  for _, ground in ipairs(level.floorItems) do
    if ground.price then
      waresFound = waresFound + 1
      eq(ground.shopId, keeper.id, "every priced ware is tagged with its shopkeeper's id")
      ok(ground.price > 0, "every priced ware has a positive price")
    end
  end
  ok(waresFound >= 3, "the shop stocks at least three wares")
end

function tests.shopAndLooseGoldStayOffTheShallowFloors()
  for depth = 1, 3 do
    local level = Builder.build(depth, Rng.new(1), {})
    for _, ground in ipairs(level.floorItems) do
      ok(ground.item.kind ~= Items.GOLD, "no loose gold appears above depth 4")
      ok(not ground.price, "no shop ware appears above depth 4")
    end
    for _, e in ipairs(level.entities) do
      ok(e.species ~= "shopkeeper", "no shopkeeper appears above depth 4")
    end
  end
end

local function arenaDark(w, h)
  local map = Map.new(w, h)
  for y = 2, h - 1 do for x = 2, w - 1 do map:set(x, y, Map.FLOOR) end end
  return Level.new({
    depth = 1, generator = "arena", map = map,
    entities = {}, floorItems = {}, traps = {}, lights = {}, dark = true, explored = {},
    upX = 2, upY = 2, downX = w - 1, downY = h - 1,
  })
end

function tests.classApplyGrantsFighterStatBonuses()
  local base = Game.new(9)
  local fighter = Game.new(9, { class = "fighter" })
  eq(fighter.player.class, "fighter", "the requested class is stamped onto the player")
  eq(fighter.player.maxHp, base.player.maxHp + 8, "fighter grants a flat max hp bonus")
  eq(fighter.player.hp, base.player.hp + 8, "the hp bonus also tops up current hp")
  eq(fighter.player.attack, base.player.attack + 2, "fighter grants a flat attack bonus")
end

function tests.classApplyGrantsRogueGoldAndAttack()
  local base = Game.new(9)
  local rogue = Game.new(9, { class = "rogue" })
  eq(rogue.player.gold, base.player.gold + 15, "rogue starts with extra gold")
  eq(rogue.player.attack, base.player.attack + 1, "rogue grants a small attack bonus")
end

function tests.classApplyGrantsMageManaAndAttack()
  local base = Game.new(9)
  local mage = Game.new(9, { class = "mage" })
  eq(mage.player.maxMana, base.player.maxMana + 8, "mage grants a flat mana bonus")
  eq(mage.player.mana, base.player.mana + 8, "the mana bonus also tops up current mana")
  eq(mage.player.attack, base.player.attack - 1, "mage trades some attack for its mana pool")
end

function tests.classApplyGrantsRangerBowAndAmmo()
  local ranger = Game.new(9, { class = "ranger" })
  ok(ranger.player.bow ~= nil, "ranger starts with a bow equipped")
  local hasAmmo = false
  for _, item in ipairs(ranger.player.inventory) do
    if item.kind == Items.AMMO then hasAmmo = true end
  end
  ok(hasAmmo, "ranger starts with a stack of arrows")
end

function tests.invalidClassIsIgnored()
  local base = Game.new(9)
  local weird = Game.new(9, { class = "wizard" })
  eq(weird.player.class, nil, "an unrecognised class name is not applied")
  eq(weird.player.maxHp, base.player.maxHp, "stats are unaffected by an invalid class")
end

function tests.skillLearnRespectsClassLevelAndPoints()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skillPoints = 0
  eq(game:learnSkill("cleave"), false, "learning fails without a banked skill point")
  game.player.skillPoints = 1
  eq(game:learnSkill("backstab"), false, "learning a skill from another class fails")
  eq(game.player.skillPoints, 1, "a failed learn spends no point")
  eq(game:learnSkill("berserk"), false, "learning fails below the skill's level requirement")
  eq(game:learnSkill("cleave"), true, "a same-class, level-eligible skill with a point banked learns")
  eq(game.player.skillPoints, 0, "learning spends the point")
  eq(Skills.has(game.player, "cleave"), true, "the skill is now known")
  game.player.skillPoints = 1
  eq(game:learnSkill("cleave"), false, "an already-known skill cannot be learned twice")
  eq(game.player.skillPoints, 1, "re-learning a known skill spends no point")
end

function tests.skillCooldownBlocksImmediateReuseAndTicksDown()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.secondWind = true
  game.player.hp = game.player.maxHp - 10
  eq(game:useSkill("secondWind"), true, "second wind activates while off cooldown")
  eq(game:useSkill("secondWind"), false, "an immediate reuse fails while on cooldown")
  for _ = 1, Skills.active.secondWind.cooldown do
    game:endPlayerTurn()
  end
  eq(game.player.skillCooldowns.secondWind, 0, "the cooldown ticks down to zero over that many player turns")
  game.player.hp = game.player.maxHp - 10
  eq(game:useSkill("secondWind"), true, "second wind is usable again once its cooldown fully elapses")
end

function tests.fighterCleaveHitsPrimaryAndAdjacentMonsters()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.cleave = true
  local primary = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local splash = Monsters.create(Monsters.byKey.orc, 2, 3, 5, 1)
  game.level.entities = { primary, splash }
  local success = game:useSkill("cleave", primary)
  eq(success, true, "cleave lands on an adjacent primary target")
  ok(primary.hp < primary.maxHp, "the primary target takes damage")
  ok(splash.hp < splash.maxHp, "a second monster adjacent to the player also takes splash damage")
  ok((splash.maxHp - splash.hp) < (primary.maxHp - primary.hp), "the splash hit deals less than the primary hit")
  eq(game.player.skillCooldowns.cleave, Skills.active.cleave.cooldown, "cleave starts its own cooldown")
end

-- Cleave's splash targets must be mitigated by the wielder's own weapon
-- damage type exactly like the primary target already is through
-- Combat.damage/Combat.attack (see combat.lua's damageTypeOf and affixes.lua's
-- own comment that a flaming sword "can do nothing at all against something
-- fire-immune") - before this test the splash loop subtracted a raw
-- attack-minus-defense number straight off hp with no Resistances.apply call
-- at all, so a flaming weapon's cleave splash burned through fire immunity
-- that the very same swing's primary hit already respected.
function tests.fighterCleaveSplashRespectsAFireImmuneTargetLikeThePrimaryHitAlreadyDoes()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.cleave = true
  game.player.weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[3])
  eq(game.player.weapon.damageType, "fire", "the flaming affix retags the dagger's swing as fire")
  local primary = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local immune = Monsters.create(Monsters.byKey.dragon, 2, 3, 5, 6)
  game.level.entities = { primary, immune }
  game:useSkill("cleave", primary)
  ok(primary.hp < primary.maxHp, "the primary target still burns for full mitigated damage")
  eq(immune.hp, immune.maxHp, "a fire-immune splash target takes zero cleave splash from a flaming weapon")
end

function tests.fighterSecondWindRestoresPortionOfMaxHp()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.secondWind = true
  game.player.hp = 5
  game:useSkill("secondWind")
  eq(game.player.hp, 5 + math.floor(game.player.maxHp * 0.3), "second wind restores three tenths of max hp")

  game.player.skillCooldowns.secondWind = 0
  game.player.hp = game.player.maxHp - 1
  game:useSkill("secondWind")
  eq(game.player.hp, game.player.maxHp, "second wind never heals past max hp")
end

function tests.fighterBerserkBoostsAttackAtLowHp()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skills.berserk = true
  local full = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  game.level.entities = { full }
  game.player.hp = game.player.maxHp
  game:playerAttack(full)
  local dmgFull = full.maxHp - full.hp

  local game2 = stagedGame(1, arena(21, 11), 3, 6)
  game2.player.class = "fighter"
  game2.player.skills.berserk = true
  local low = Monsters.create(Monsters.byKey.orc, 2, 4, 6, 1)
  game2.level.entities = { low }
  game2.player.hp = math.floor(game2.player.maxHp * 0.3)
  game2:playerAttack(low)
  local dmgLow = low.maxHp - low.hp

  ok(dmgLow > dmgFull, "berserk raises attack once hp drops to a third of max")
end

function tests.rogueBackstabDoublesDamageOnFullHpTarget()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "rogue"
  game.player.skills.backstab = true
  local fresh = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  game.level.entities = { fresh }
  game:playerAttack(fresh)
  local dmgFresh = fresh.maxHp - fresh.hp

  local game2 = stagedGame(1, arena(21, 11), 3, 6)
  game2.player.class = "rogue"
  game2.player.skills.backstab = true
  local hurt = Monsters.create(Monsters.byKey.rat, 2, 4, 6, 1)
  hurt.hp = hurt.hp - 1
  game2.level.entities = { hurt }
  game2:playerAttack(hurt)
  local dmgHurt = (hurt.maxHp - 1) - hurt.hp

  eq(dmgFresh, dmgHurt * 2, "backstab doubles damage against a target still at full hp")
end

function tests.rogueEvasionCanFullyNegateMeleeHit()
  local defender = { skills = { evasion = true } }
  local sawDodge, sawHit = false, false
  local rng = Rng.new(1)
  for _ = 1, 60 do
    if Skills.evades({ rng = rng }, defender) then sawDodge = true else sawHit = true end
  end
  ok(sawDodge, "evasion dodges at least once over enough attempts")
  ok(sawHit, "evasion is a chance, not a guarantee, over enough attempts")
  eq(Skills.evades({ rng = Rng.new(1) }, {}), false, "a defender without the skill never evades")
end

function tests.poisonBladeAppliesPoisonOnNextMeleeHitOnly()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "rogue"
  game.player.skills.poisonBlade = true
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 100, 100
  game.level.entities = { orc }
  eq(game:useSkill("poisonBlade"), true, "poison blade readies without needing a target")
  game:playerAttack(orc)
  ok(Status.has(orc, Status.POISON), "the readied venom lands on the very next melee hit")
  orc.statuses = {}
  game:playerAttack(orc)
  eq(Status.has(orc, Status.POISON), false, "poison blade is spent after one hit, not reapplied on the next")
end

-- pendingPoisonBlade lives on the player between "ready the venom" and "land
-- the next swing" - a window a save/quit can happen inside, exactly like
-- reputation, sanity or the skill tree already have to survive Game:toData.
function tests.pendingPoisonBladeReadinessSurvivesAGameSaveLoadRoundTrip()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "rogue"
  game.player.skills.poisonBlade = true
  eq(game:useSkill("poisonBlade"), true, "poison blade readies without needing a target")
  eq(game.player.pendingPoisonBlade, true, "readying the skill sets the pending flag before any save/load happens")
  local restored = Game.fromData(game:toData())
  eq(restored.player.pendingPoisonBlade, true, "a poison blade readied before a save is still primed after loading it back")
  ok(Skills.consumePoisonBlade(restored.player), "the restored pending venom is still consumable on the very next swing")
end

function tests.mageOverloadBoostsMissileDamage()
  local game = stagedGame(5, arena(21, 11), 3, 6)
  local base = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game.level.entities = { base }
  game:castSpell("missile", base)
  local dmgBase = base.maxHp - base.hp

  local game2 = stagedGame(5, arena(21, 11), 3, 6)
  game2.player.class = "mage"
  game2.player.skills.overload = true
  local boosted = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  game2.level.entities = { boosted }
  game2:castSpell("missile", boosted)
  local dmgBoosted = boosted.maxHp - boosted.hp

  ok(dmgBoosted > dmgBase, "overload raises missile spell damage")
end

function tests.mageMeditateRestoresManaWithinCap()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "mage"
  game.player.skills.meditate = true
  game.player.mana = 2
  game:useSkill("meditate")
  eq(game.player.mana, 8, "meditate restores a flat amount of mana")

  game.player.mana = game.player.maxMana - 1
  game:useSkill("meditate")
  eq(game.player.mana, game.player.maxMana, "meditate never overfills the mana pool")
end

function tests.mageManaShieldRaisesDefenseWhileManaHeld()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "mage"
  game.player.skills.manaShield = true
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  local before = game.player.hp
  game.player.mana = 10
  game:monsterMelee(orc)
  local dmgWithShield = before - game.player.hp

  game.player.hp = before
  game.player.mana = 0
  game:monsterMelee(orc)
  local dmgWithoutShield = before - game.player.hp

  ok(dmgWithoutShield > dmgWithShield, "mana shield reduces damage taken while mana holds")
end

function tests.rangerMultishotHitsTwoTargetsForOneArrow()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "ranger"
  game.player.skills.multishot = true
  game.player.bow = Items.bow("shortbow", 3, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 5)
  local first = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
  local second = Monsters.create(Monsters.byKey.orc, 2, 3, 8, 1)
  game.level.entities = { first, second }
  local success = game:useSkill("multishot", first, second)
  eq(success, true, "multishot succeeds with two reachable targets")
  ok(first.hp < first.maxHp, "the primary target takes damage")
  ok(second.hp < second.maxHp, "the secondary target takes damage")
  local stack
  for _, item in ipairs(game.player.inventory) do
    if item.kind == Items.AMMO then stack = item end
  end
  eq(stack.count, 4, "multishot consumes only a single arrow for both targets")
end

-- Multishot's split arrows must run through Resistances.apply exactly like a
-- single Ranged.fire shot does (both always tag physical - arrows never
-- carry an elemental damageType) - before this test the loop subtracted a
-- raw attack-minus-defense number straight off hp for both targets with no
-- mitigation call at all, so a physically resistant monster took a full,
-- unresisted hit from a skill that is supposed to be "an arrow that splits",
-- not a different damage model than the bow it comes out of.
function tests.rangerMultishotRespectsPhysicalResistanceOnBothSplitArrows()
  local function primaryDamageDealt(resistant)
    local game = stagedGame(1, arena(21, 11), 3, 6)
    game.player.class = "ranger"
    game.player.skills.multishot = true
    game.player.bow = Items.bow("shortbow", 3, 6)
    game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 5)
    local first = Monsters.create(Monsters.byKey.orc, 1, 6, 6, 1)
    first.hp, first.maxHp = 100, 100
    if resistant then first.resist = { physical = Resistances.RESIST } end
    local second = Monsters.create(Monsters.byKey.orc, 2, 3, 8, 1)
    second.hp, second.maxHp = 100, 100
    game.level.entities = { first, second }
    game:useSkill("multishot", first, second)
    return 100 - first.hp
  end
  local plain = primaryDamageDealt(false)
  local resisted = primaryDamageDealt(true)
  ok(resisted < plain, "a physically resistant target takes measurably less multishot damage than an unresisted one")
  eq(resisted, math.floor(plain / 2), "physical resistance halves the split-arrow hit, the same mitigation Resistances.apply gives a single Ranged.fire shot")
end

function tests.rangerCamouflageShrinksDetectionOnDarkFloors()
  local game = stagedGame(1, arenaDark(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 11, 6, 1)
  eq(game:canSeePlayer(orc, 10), true, "without camouflage a dark floor does not shrink detection")

  game.player.class = "ranger"
  game.player.skills.camouflage = true
  eq(game:canSeePlayer(orc, 10), false, "camouflage shrinks a monster's detection range on a dark floor")

  game.level.dark = false
  eq(game:canSeePlayer(orc, 10), true, "camouflage does nothing once the floor is lit")
end

-- Blindness overrides Game:effectiveRadius outright rather than stacking as
-- another penalty term (contrast Atmosphere.sightPenalty/Events.sightPenalty/
-- Ascension.sightPenalty, which all just shave a fixed amount off) - a fully
-- lit, unpenalized floor still clamps to a radius of one the instant the
-- player is blinded, and returns to normal the instant the status is gone.
function tests.effectiveRadiusBlindStatusOverridesLightAndWeatherToAMinimumOfOne()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local clear = game:effectiveRadius()
  ok(clear > 1, "an unblinded, unpenalized floor has more than a radius of one to begin with")

  Status.apply(game.player, Status.BLIND, 6, 1)
  eq(game:effectiveRadius(), 1, "a blinded player's sight radius clamps to one regardless of light or weather")

  game.player.statuses = {}
  eq(game:effectiveRadius(), clear, "sight radius returns to normal once blindness is gone")
end

-- A blinded monster keeps its ordinary listed detection range on paper, but
-- Game:canSeePlayer clamps every one of ai.lua's behaviours (chase/pack/
-- ranged/flee/erratic/tunnel all route through this same helper) down to
-- melee-only awareness while it lasts.
function tests.canSeePlayerBlindedMonsterOnlyDetectsThePlayerAtMeleeRange()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local orc = Monsters.create(Monsters.byKey.orc, 1, 8, 6, 1)
  eq(game:canSeePlayer(orc, 10), true, "an unblinded monster within its listed range sees the player")

  Status.apply(orc, Status.BLIND, 6, 1)
  eq(game:canSeePlayer(orc, 10), false, "a blinded monster loses a five-cell-away sighting despite its listed range")

  local adjacentOrc = Monsters.create(Monsters.byKey.orc, 2, 4, 6, 1)
  Status.apply(adjacentOrc, Status.BLIND, 6, 1)
  eq(game:canSeePlayer(adjacentOrc, 10), true, "a blinded monster still senses the player once adjacent")
end

function tests.rangerTrueshotAddsFlatRangedDamage()
  local game = stagedGame(4, arena(21, 11), 3, 6)
  local base = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game.level.entities = { base }
  game.player.bow = Items.bow("short bow", 2, 6)
  game.player.inventory[#game.player.inventory + 1] = Items.ammo("arrow", 2)
  game:fireAt(base)
  local dmgBase = base.maxHp - base.hp

  local game2 = stagedGame(4, arena(21, 11), 3, 6)
  game2.player.class = "ranger"
  game2.player.skills.trueshot = true
  local boosted = Monsters.create(Monsters.byKey.orc, 1, 9, 6, 1)
  game2.level.entities = { boosted }
  game2.player.bow = Items.bow("short bow", 2, 6)
  game2.player.inventory[#game2.player.inventory + 1] = Items.ammo("arrow", 2)
  game2:fireAt(boosted)
  local dmgTrueshot = boosted.maxHp - boosted.hp

  eq(dmgTrueshot, dmgBase + 3, "trueshot adds a flat +3 to every ranged hit")
end

function tests.autopilotLearnsSkillsAutomaticallyAsPointsAllow()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.class = "fighter"
  game.player.skillPoints = 1
  game:choosePlayerAction()
  ok(Skills.has(game.player, "cleave"),
    "the autopilot spends a banked point on the first level-eligible skill in class order")
  eq(game.player.skillPoints, 0, "learning the skill spends the banked point")
end

function tests.skillFieldsSurviveSerialization()
  local game = Game.new(5, { class = "mage" })
  game.player.skills.overload = true
  game.player.skillCooldowns.meditate = 2
  game.player.skillPoints = 3
  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)
  eq(restored.player.class, "mage", "class survives a save/load round trip")
  eq(restored.player.skillPoints, 3, "skill points survive a save/load round trip")
  eq(Skills.has(restored.player, "overload"), true, "learned skills survive a save/load round trip")
  eq(restored.player.skillCooldowns.meditate, 2, "skill cooldowns survive a save/load round trip")
end

function tests.craftingForgeSpendsEssenceForATierOneGem()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.essence = Crafting.FORGE_COST - 1
  local shortSuccess, shortReason = Crafting.forge(game.player, Crafting.FIRE)
  eq(shortSuccess, false, "forging refuses when essence is short of the cost")
  eq(shortReason, "not enough essence", "the refusal names the reason")

  game.player.essence = Crafting.FORGE_COST
  local success, gem = Crafting.forge(game.player, Crafting.FIRE)
  ok(success, "forging succeeds with exactly the cost in essence")
  eq(gem.tier, 1, "a forged gem starts at tier one")
  eq(gem.element, Crafting.FIRE, "the gem carries the requested element")
  eq(game.player.essence, 0, "the forge cost is spent")

  local badSuccess, badReason = Crafting.forge(game.player, "shadow")
  eq(badSuccess, false, "an unknown element is refused")
  eq(badReason, "no such element", "the refusal names the reason")
end

function tests.craftingMergeGemsCombinesMatchingPairsIntoTheNextTier()
  local success, _, merged = Crafting.mergeGems(Crafting.gem(Crafting.FIRE, 1), Crafting.gem(Crafting.FIRE, 1))
  ok(success, "two matching chip gems merge")
  eq(merged.tier, 2, "the merged gem is one tier higher")
  eq(merged.element, Crafting.FIRE, "the merged gem keeps the shared element")
  eq(merged.power, 2, "a gem's power always matches its tier")

  local mismatchElement, elementReason = Crafting.mergeGems(Crafting.gem(Crafting.FIRE, 1), Crafting.gem(Crafting.FROST, 1))
  eq(mismatchElement, false, "gems of different elements refuse to merge")
  eq(elementReason, "elements do not match", "the refusal names the reason")

  local mismatchTier, tierReason = Crafting.mergeGems(Crafting.gem(Crafting.FIRE, 1), Crafting.gem(Crafting.FIRE, 2))
  eq(mismatchTier, false, "gems of different tiers refuse to merge")
  eq(tierReason, "tiers do not match", "the refusal names the reason")

  local atCap, capReason = Crafting.mergeGems(
    Crafting.gem(Crafting.FIRE, Crafting.MAX_TIER), Crafting.gem(Crafting.FIRE, Crafting.MAX_TIER))
  eq(atCap, false, "a gem already at the maximum tier cannot merge further")
  eq(capReason, "already at maximum tier", "the refusal names the reason")
end

function tests.craftingSocketAddsPowerAndSwapsRiderOnResocket()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack

  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.FIRE, 1)),
    "a gem sockets into an equipped weapon")
  eq(weapon.power, 3, "the gem's power lands on the item")
  eq(game.player.attack, attackBaseline + 1, "socketing an equipped weapon updates attack immediately")
  eq(weapon.socket.element, Crafting.FIRE, "the socket records its element")

  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.FROST, 2)),
    "resocketing replaces the previous gem")
  eq(weapon.power, 4, "power reflects only the new gem, not a stack of both")
  eq(game.player.attack, attackBaseline + 2, "attack reflects the swap, not an accumulation")
  eq(weapon.socket.element, Crafting.FROST, "the new gem's element replaces the old one")

  local success, reason = Crafting.socket(game.player, weapon, { kind = Items.WEAPON })
  eq(success, false, "a non-gem refuses to socket")
  eq(reason, "not a gem", "the refusal names the reason")
end

function tests.craftingTemperRaisesPowerAtRisingCostUpToACap()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack
  local totalCost = 0
  for level = 0, Crafting.TEMPER_MAX - 1 do
    totalCost = totalCost + (level + 1) * 4
  end
  game.player.essence = totalCost

  for level = 1, Crafting.TEMPER_MAX do
    ok(Crafting.temper(game.player, weapon), "temper step " .. level .. " succeeds with enough essence")
  end
  eq(weapon.power, 2 + Crafting.TEMPER_MAX, "each temper step adds exactly one flat power")
  eq(game.player.attack, attackBaseline + Crafting.TEMPER_MAX,
    "tempering an equipped weapon updates attack immediately")
  eq(game.player.essence, 0, "the full ladder of rising costs is spent exactly")

  local success, reason = Crafting.temper(game.player, weapon)
  eq(success, false, "a fully tempered item refuses a further step")
  eq(reason, "fully tempered", "the refusal names the reason")
end

function tests.craftingTemperRefusesWithoutEnoughEssence()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("mace", 3)
  Items.equipWeapon(weapon, game.player)
  game.player.essence = 3
  local success, reason = Crafting.temper(game.player, weapon)
  eq(success, false, "tempering fails when essence is short of the cost")
  eq(reason, "not enough essence", "the refusal names the reason")
  eq(weapon.power, 3, "a failed temper leaves power untouched")
  eq(game.player.essence, 3, "a failed temper spends nothing")
end

function tests.craftingEnchantGrantsAChosenAffixOnce()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack
  game.player.essence = Crafting.ENCHANT_COST

  ok(Crafting.enchant(game.player, weapon, "flaming"), "enchanting an unaffixed weapon succeeds")
  eq(weapon.affix.key, "flaming", "the chosen affix is attached, not a random roll")
  eq(weapon.power, 3, "the affix's power lands on the item")
  eq(weapon.name, "flaming dagger", "the affix prefix is applied to the name")
  eq(game.player.attack, attackBaseline + 1, "enchanting an equipped weapon updates attack immediately")
  eq(game.player.essence, 0, "the enchant cost is spent")

  local repeatSuccess, repeatReason = Crafting.enchant(game.player, weapon, "vicious")
  eq(repeatSuccess, false, "an already-affixed weapon refuses a second enchant")
  eq(repeatReason, "already bears an affix", "the refusal names the reason")

  local badSuccess, badReason = Crafting.enchant(game.player, Items.armor("leather armor", 1), "not-a-real-affix")
  eq(badSuccess, false, "an unknown affix key is refused")
  eq(badReason, "unknown affix", "the refusal names the reason")

  local ringSuccess, ringReason = Crafting.enchant(game.player, Items.ring("ring of power", 1, 1), "sharp")
  eq(ringSuccess, false, "gear without an affix pool cannot be enchanted")
  eq(ringReason, "cannot be enchanted", "the refusal names the reason")
end

function tests.craftingDisenchantStripsAffixAndRefundsEssence()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local armor = Affixes.decorate(Items.armor("chain mail", 2), Affixes.armor[2])
  Items.equipArmor(armor, game.player)
  local defenseBaseline = game.player.defense
  eq(armor.name, "reinforced chain mail", "sanity check: the drop rolled the expected affix")

  local success, refund = Crafting.disenchant(game.player, armor)
  ok(success, "disenchanting an affixed armor succeeds")
  eq(refund, Crafting.FORGE_COST + 2 * 3, "the refund scales with the stripped affix's power")
  eq(armor.power, 2, "power drops back to its base value")
  eq(armor.name, "chain mail", "the affix prefix is removed from the name")
  eq(armor.affix, nil, "the affix is gone")
  eq(game.player.defense, defenseBaseline - 2, "disenchanting an equipped armor updates defense immediately")
  eq(game.player.essence, refund, "the refund lands in the player's essence")

  local again, reason = Crafting.disenchant(game.player, armor)
  eq(again, false, "an already-plain item has nothing left to disenchant")
  eq(reason, "nothing to disenchant", "the refusal names the reason")
end

function tests.craftingSocketedGemRidersStackWithARolledAffixOnHit()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Affixes.decorate(Items.weapon("dagger", 2), Affixes.weapon[4])
  Items.equipWeapon(weapon, game.player)
  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.SHOCK, 1)),
    "a shock gem sockets alongside the rolled affix")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 30, 30
  game.level.entities = { orc }
  game:playerAttack(orc)
  eq(Status.has(orc, Status.POISON), true, "the rolled venomed affix still lands its rider")
  eq(Status.has(orc, Status.STUN), true, "the socketed shock gem lands its own rider on the same hit")
end

-- Regression: a shock rider applied during the PLAYER's turn is ticked for
-- the first time on the very same round, inside the victim's own upcoming
-- Game:takeMonsterTurn (Status.tick runs there before Status.skipsTurn is
-- ever checked) - so a duration of 1 would already read 0 and be gone
-- before skipsTurn saw it, and the "stun" would silently never do anything.
-- This confirms the fix (duration 2, see crafting.lua) actually skips the
-- victim's very next turn, not just that the status gets attached.
function tests.craftingShockRiderActuallyStunsTheVictimOnItsNextTurnNotJustOnPaper()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  ok(Crafting.socket(game.player, weapon, Crafting.gem(Crafting.SHOCK, 1)),
    "a bare shock gem sockets onto an unaffixed weapon")
  local orc = Monsters.create(Monsters.byKey.orc, 1, 4, 6, 1)
  orc.hp, orc.maxHp = 30, 30
  game.level.entities = { orc }

  game:playerAttack(orc)
  eq(Status.has(orc, Status.STUN), true, "the shock rider lands immediately on the hit")

  local hpBefore, xBefore, yBefore = game.player.hp, orc.x, orc.y
  game:takeMonsterTurn(orc)
  eq(game.player.hp, hpBefore, "a stunned orc's very next turn deals no melee damage")
  eq(orc.x, xBefore, "a stunned orc's very next turn does not move")
  eq(orc.y, yBefore, "a stunned orc's very next turn does not move")

  game:takeMonsterTurn(orc)
  eq(Status.has(orc, Status.STUN), false, "the stun has fully expired by the turn after that")
  ok(game.player.hp < hpBefore, "once unstunned the orc resumes attacking normally")
end

function tests.gameCraftingWrappersDriveTheFullPipeline()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  local attackBaseline = game.player.attack

  game.player.essence = Crafting.FORGE_COST * 2
  ok(game:forgeGem(Crafting.FIRE), "forging a gem through the game wrapper succeeds")
  ok(game:forgeGem(Crafting.FIRE), "forging a second matching gem succeeds")
  local invBefore = #game.player.inventory

  local firstGemIndex, secondGemIndex
  for i, item in ipairs(game.player.inventory) do
    if item.kind == Items.GEM then
      if not firstGemIndex then firstGemIndex = i else secondGemIndex = i end
    end
  end
  ok(game:mergeGemsAt(firstGemIndex, secondGemIndex), "merging through the game wrapper succeeds")
  eq(#game.player.inventory, invBefore - 1, "merging removes both source gems and adds one merged gem")

  local mergedIndex
  for i, item in ipairs(game.player.inventory) do
    if item.kind == Items.GEM then mergedIndex = i end
  end
  ok(game:socketItem("weapon", mergedIndex), "socketing the equipped weapon through the game wrapper succeeds")
  eq(weapon.socket.element, Crafting.FIRE, "the socketed gem's element lands on the weapon")
  eq(game.player.attack, attackBaseline + 2, "socketing a tier-2 gem adds its power to attack")
  ok(not game:socketItem("weapon", mergedIndex), "the gem slot is consumed and cannot be socketed twice")

  game.player.essence = Crafting.temperCost(weapon)
  ok(game:temperItem("weapon"), "tempering the equipped weapon through the game wrapper succeeds")
  eq(weapon.power, 2 + 2 + 1, "temper stacks on top of the socket's power")
  eq(game.player.attack, attackBaseline + 3, "tempering the equipped weapon updates attack immediately")

  game.player.essence = Crafting.ENCHANT_COST
  ok(game:enchantItem("weapon", "vicious"), "enchanting the equipped weapon through the game wrapper succeeds")
  eq(weapon.affix.key, "vicious", "the chosen affix lands on the weapon")

  local beforeDisenchant = game.player.attack
  local expectedRefund = Crafting.FORGE_COST + 2 * 3
  ok(game:disenchantItem("weapon"), "disenchanting the equipped weapon through the game wrapper succeeds")
  eq(game.player.attack, beforeDisenchant - 2, "disenchanting removes the affix's power from attack")
  eq(game.player.essence, expectedRefund, "the disenchant refund lands in essence")
  ok(contains(game.log:recent(1)[1] or "", "disenchant"), "the disenchant is logged")
end

function tests.monsterKillsGrantEssenceScaledToTheirXpReward()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 1
  game.level.entities = { rat }
  local essenceBefore = game.player.essence
  game:playerAttack(rat)
  eq(game.player.essence, essenceBefore + Crafting.essenceFor(Monsters.xpFor(rat)),
    "a kill grants essence scaled to the monster's xp reward")
end

function tests.craftingFieldsSurviveSerialization()
  local game = Game.new(5)
  local weapon = Items.weapon("dagger", 2)
  Items.equipWeapon(weapon, game.player)
  Crafting.socket(game.player, weapon, Crafting.gem(Crafting.VENOM, 2))
  game.player.essence = 37
  game.player.inventory[#game.player.inventory + 1] = Crafting.gem(Crafting.SHOCK, 1)

  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)

  eq(restored.player.essence, 37, "essence survives a save/load round trip")
  eq(restored.player.weapon.socket.element, Crafting.VENOM, "a socketed gem's element survives a save/load round trip")
  eq(restored.player.weapon.socket.tier, 2, "a socketed gem's tier survives a save/load round trip")
  local restoredGem
  for _, item in ipairs(restored.player.inventory) do
    if item.kind == Items.GEM then restoredGem = item end
  end
  ok(restoredGem ~= nil, "a loose gem in the inventory survives a save/load round trip")
  eq(restoredGem.element, Crafting.SHOCK, "the loose gem's element survives a save/load round trip")
end

function tests.alchemyBrewResolvesAKnownPairToItsFixedPotion()
  local potion = Alchemy.brew(Alchemy.SUNPETAL, Alchemy.SUNPETAL)
  eq(potion.effect, "heal", "a matched pair of the same herb brews that herb's aspect")
  eq(potion.power, 18, "a doubled herb brews a stronger potion than a mixed pair")
end

function tests.alchemyBrewIsOrderIndependent()
  local forward = Alchemy.brew(Alchemy.BLOODROOT, Alchemy.NIGHTCAP)
  local backward = Alchemy.brew(Alchemy.NIGHTCAP, Alchemy.BLOODROOT)
  eq(forward.effect, backward.effect, "brewing a pair does not depend on which herb is named first")
  eq(forward.power, backward.power, "a brewed potion's power does not depend on herb order either")
end

function tests.alchemyBrewCurdlesOnAnOpposedPairing()
  local potion, reason = Alchemy.brew(Alchemy.SUNPETAL, Alchemy.NIGHTCAP)
  eq(potion, nil, "light and shade herbs curdle rather than brewing a potion")
  eq(reason, "curdle", "a curdled brew names its failure")
end

function tests.alchemyLookupRejectsAnUnknownHerb()
  eq(Alchemy.lookup("mud", Alchemy.SUNPETAL), nil, "a nonexistent herb key has no recipe")
end

function tests.gameBrewAtCombinesTwoHerbsIntoAPotionAtACauldron()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.BLOODROOT) }
  ok(game:brewAt(1, 2), "brewing two herbs at a cauldron underfoot succeeds")
  eq(#game.player.inventory, 1, "both source herbs are spent and one potion is added")
  local brewed = game.player.inventory[1]
  eq(brewed.kind, Items.POTION, "brewing yields an ordinary catalog potion")
  eq(brewed.effect, "heal", "the brewed potion matches the herb pair's fixed recipe")
  eq(brewed.power, 10, "the brewed potion's power matches the recipe, not the catalog default")
  ok(Identify.isKnown(game.identify, brewed), "brewing a potion yourself identifies its type for free")
end

function tests.gameBrewAtFailsWithoutACauldronUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.BLOODROOT) }
  ok(not game:brewAt(1, 2), "brewing away from any cauldron fails")
  eq(#game.player.inventory, 2, "a failed brew for lack of a cauldron spends nothing")
end

function tests.gameBrewAtRequiresTwoHerbItems()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL) }
  ok(not game:brewAt(1, 1), "brewing a herb against itself by index is rejected")
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Items.potion(10) }
  ok(not game:brewAt(1, 2), "a non-herb item cannot stand in for the second half of a brew")
  eq(#game.player.inventory, 2, "a rejected brew attempt spends nothing")
end

function tests.gameBrewAtCurdlesIntoGasInsteadOfAPotion()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.cauldrons = { { x = 5, y = 5 } }
  game.player.inventory = { Alchemy.herb(Alchemy.SUNPETAL), Alchemy.herb(Alchemy.NIGHTCAP) }
  ok(not game:brewAt(1, 2), "a curdled brew reports failure")
  eq(#game.player.inventory, 0, "a curdled brew still spends both herbs")
  ok(Hazards.at(game.level, 5, 5, Hazards.GAS) ~= nil, "a curdled brew vents a gas hazard at the brewer's feet")
  ok(contains(game.log:recent(1)[1] or "", "curdle"), "the curdle is logged")
end

function tests.buildersScatterHerbsFromTheFirstFloor()
  local level = Builder.build(1, Rng.new(1), {})
  local herbs = 0
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.HERB then herbs = herbs + 1 end
  end
  ok(herbs >= 2, "the entrance floor already scatters foraging herbs")
end

function tests.cauldronsStayOffTheEntranceFloor()
  for seed = 1, 5 do
    local level = Builder.build(1, Rng.new(seed), {})
    eq(#level.cauldrons, 0, "no cauldron appears on the entrance floor")
  end
end

function tests.buildersOccasionallyPlaceACauldronFromDepthTwo()
  local level = Builder.build(2, Rng.new(14), {})
  eq(#level.cauldrons, 1, "this seed's depth-2 floor places a cauldron")
end

function tests.cauldronFieldsSurviveSerialization()
  local level = arena(21, 11)
  level.cauldrons = { { x = 4, y = 4 } }
  local restored = Level.fromData(level:toData())
  eq(#restored.cauldrons, 1, "the cauldron list survives a round trip")
  eq(restored.cauldrons[1].x, 4, "a cauldron's position survives a round trip")
end

function tests.cauldronRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  rendered.level.cauldrons = { { x = 5, y = 6 } }
  rendered:computeVisible()
  ok(contains(rendered:render(), "U"), "a cauldron on a visible cell renders as its glyph")
end

local function nodePlayer()
  return { essence = 0, inventory = {} }
end

local function nodeGame(seed)
  local game = { player = nodePlayer(), rng = Rng.new(seed), level = { event = nil }, ascension = {} }
  function game:essenceMultiplier()
    return Events.essenceMultiplier(self.level.event) * Ascension.essenceMultiplier(self.ascension)
  end
  return game
end

function tests.nodesHarvestingAnOreVeinPaysEssenceAndSpendsACharge()
  local node = Nodes.new(Nodes.ORE)
  local game = nodeGame(3)
  local success, line = Nodes.harvest(game, node)
  ok(success, "harvesting a fresh ore vein succeeds")
  eq(node.charges, Nodes.MAX_CHARGES - 1, "a harvest spends exactly one charge")
  ok(game.player.essence >= Nodes.ORE_YIELD_MIN and game.player.essence <= Nodes.ORE_YIELD_MAX,
    "the essence paid out falls within the vein's yield range")
  ok(contains(line, "essence"), "the harvest is logged")
end

function tests.nodesHarvestingAnOreVeinDoublesItsYieldDuringRichVeins()
  local node = Nodes.new(Nodes.ORE)
  local game = nodeGame(3)
  game.level.event = { key = Events.RICHVEINS, turnsLeft = 5 }
  Nodes.harvest(game, node)
  ok(game.player.essence >= Nodes.ORE_YIELD_MIN * 2 and game.player.essence <= Nodes.ORE_YIELD_MAX * 2,
    "rich veins doubles the vein's ordinary yield range")
end

function tests.nodesHarvestingAGemSeamYieldsARawTierOneGemOfItsElement()
  local node = Nodes.new(Nodes.GEM, Crafting.FIRE)
  local game = nodeGame(3)
  local success = Nodes.harvest(game, node)
  ok(success, "harvesting a fresh gem seam succeeds")
  eq(#game.player.inventory, 1, "a gem lands in the inventory")
  local gem = game.player.inventory[1]
  eq(gem.kind, Items.GEM, "the yield is a gem item")
  eq(gem.element, Crafting.FIRE, "the gem matches the seam's own element")
  eq(gem.tier, 1, "a freshly pried gem is raw, tier one")
end

function tests.nodesGoingFallowRefusesFurtherHarvestsUntilItReopens()
  local node = Nodes.new(Nodes.ORE)
  node.charges = 1
  local game = nodeGame(9)
  ok(Nodes.harvest(game, node), "the last charge still pays out")
  eq(node.charges, 0, "spending the last charge empties the vein")
  eq(node.cooldown, Nodes.REGEN_TURNS, "emptying a vein starts its regen cooldown")
  local success, line = Nodes.harvest(game, node)
  eq(success, false, "a fallow vein refuses to be harvested again")
  ok(contains(line, "played out"), "the refusal is logged")
end

function tests.nodesStepCountsDownAndReopensAFallowNode()
  local level = { nodes = { Nodes.new(Nodes.ORE) } }
  local node = level.nodes[1]
  node.charges = 0
  node.cooldown = 2
  Nodes.step(level)
  eq(node.cooldown, 1, "each step counts the cooldown down by one")
  eq(node.charges, 0, "the vein stays fallow until its cooldown reaches zero")
  Nodes.step(level)
  eq(node.cooldown, 0, "the cooldown reaches zero on schedule")
  eq(node.charges, Nodes.MAX_CHARGES, "reaching zero cooldown fully reopens the vein")
end

function tests.nodesFieldsSurviveSerialization()
  local level = arena(21, 11)
  local node = Nodes.new(Nodes.GEM, Crafting.FROST)
  node.x, node.y = 4, 4
  node.charges = 1
  node.cooldown = 5
  level.nodes = { node }
  local restored = Level.fromData(level:toData())
  eq(#restored.nodes, 1, "the node list survives a round trip")
  eq(restored.nodes[1].kind, Nodes.GEM, "a node's kind survives a round trip")
  eq(restored.nodes[1].element, Crafting.FROST, "a node's element survives a round trip")
  eq(restored.nodes[1].charges, 1, "a node's charges survive a round trip")
  eq(restored.nodes[1].cooldown, 5, "a node's cooldown survives a round trip")
end

function tests.nodeRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y = 5, 6
  rendered.level.nodes = { ore }
  rendered:computeVisible()
  ok(contains(rendered:render(), "O"), "an ore vein on a visible cell renders as its glyph")
end

function tests.gameHarvestNodeAtAnOreVeinAddsEssenceAndSpendsACharge()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y = 5, 5
  game.level.nodes = { ore }
  local before = game.player.essence
  ok(game:harvestNode(), "harvesting the ore vein underfoot succeeds")
  ok(game.player.essence > before, "harvesting an ore vein raises the player's essence")
  eq(ore.charges, Nodes.MAX_CHARGES - 1, "harvesting spends one of the vein's charges")
end

function tests.gameHarvestNodeFailsWithoutANodeUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:harvestNode(), "harvesting empty ground fails")
end

function tests.gameHarvestNodeOnAFallowVeinFails()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y, ore.charges = 5, 5, 0
  game.level.nodes = { ore }
  ok(not game:harvestNode(), "a fallow vein cannot be harvested")
end

function tests.autopilotHarvestsAnOreVeinWhenIdleAndStandingOnIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y = 5, 5
  game.level.nodes = { ore }
  local before = game.player.essence
  game:choosePlayerAction()
  eq(ore.charges, Nodes.MAX_CHARGES - 1, "the autopilot harvests an unspent vein it stands on")
  ok(game.player.essence > before, "the autopilot's harvest actually pays out essence")
end

function tests.autopilotSkipsAFallowNode()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local ore = Nodes.new(Nodes.ORE)
  ore.x, ore.y, ore.charges = 5, 5, 0
  game.level.nodes = { ore }
  game:choosePlayerAction()
  eq(ore.charges, 0, "the autopilot never touches a fallow node")
end

function tests.buildersNeverPlaceANodeOnTheEntranceFloor()
  for seed = 1, 5 do
    local level = Builder.build(1, Rng.new(seed), {})
    eq(#level.nodes, 0, "no resource node appears on the entrance floor")
  end
end

function tests.buildersAlwaysPlaceAtLeastOneNodeFromDepthTwoOn()
  for seed = 1, 5 do
    for depth = 2, 5 do
      local level = Builder.build(depth, Rng.new(seed), {})
      ok(#level.nodes >= 1, "every depth-2-and-deeper floor places at least one resource node")
      ok(#level.nodes <= 2, "no floor places more than two resource nodes")
      for _, node in ipairs(level.nodes) do
        ok(node.kind == Nodes.ORE or node.kind == Nodes.GEM, "every placed node is a known kind")
      end
    end
  end
end

local function corpsePlayer()
  return { inventory = {}, statuses = {} }
end

function tests.corpsesSpawnsForAWildMonsterButNotForUndeadMimicOrBoss()
  local level = { corpses = {} }
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(level, rat)
  eq(#level.corpses, 1, "a wild monster leaves a corpse behind")

  local zombie = Monsters.create(Monsters.byKey.zombie, 2, 6, 6, 4)
  Corpses.spawn(level, zombie)
  eq(#level.corpses, 1, "an undead monster crumbles to dust, leaving no corpse")

  local mimic = Mimics.reveal(3, 7, 7, 4)
  Corpses.spawn(level, mimic)
  eq(#level.corpses, 1, "a mimic was never alive, so it leaves no corpse")

  local warlord = Bosses.create(Bosses.byKey.warlord, 4, 8, 8)
  Corpses.spawn(level, warlord)
  eq(#level.corpses, 1, "a boss's own scripted loot drop replaces a corpse")
end

function tests.corpsesNutritionScalesWithTheFelledSpeciesMaxHpClampedToAFixedBand()
  local bat = Monsters.create(Monsters.byKey.bat, 1, 5, 5, 1)
  local batCorpse = Corpses.new(bat)
  eq(batCorpse.nutrition, Corpses.NUTRITION_MIN, "a frail species clamps to the nutrition floor")

  local troll = Monsters.create(Monsters.byKey.troll, 2, 5, 5, 5)
  local trollCorpse = Corpses.new(troll)
  eq(trollCorpse.nutrition, troll.maxHp * Corpses.NUTRITION_PER_HP, "a tougher species scales nutrition with maxHp")

  local dragon = Monsters.create(Monsters.byKey.dragon, 3, 5, 5, 6)
  local dragonCorpse = Corpses.new(dragon)
  eq(dragonCorpse.nutrition, Corpses.NUTRITION_MAX, "an especially tough species clamps to the nutrition ceiling")
end

function tests.corpsesStepCountsDownAndRotsAwayEntirely()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local level = { corpses = {} }
  Corpses.spawn(level, rat)
  local corpse = level.corpses[1]
  for _ = 1, Corpses.DECAY_TURNS - 1 do Corpses.step(level) end
  eq(#level.corpses, 1, "a corpse survives right up to its final round")
  eq(corpse.decay, 1, "decay counts down by exactly one each step")
  Corpses.step(level)
  eq(#level.corpses, 0, "a corpse vanishes outright once its decay reaches zero")
end

function tests.corpsesGoesRottenPastItsThresholdButStaysButcherableUntilThen()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local corpse = Corpses.new(rat)
  ok(not Corpses.isRotten(corpse), "a freshly spawned corpse is not yet rotten")
  corpse.decay = Corpses.ROT_TURNS
  ok(Corpses.isRotten(corpse), "a corpse right at its rot threshold counts as rotten")
  corpse.decay = Corpses.ROT_TURNS + 1
  ok(not Corpses.isRotten(corpse), "a corpse one round above the threshold is still good")
end

function tests.corpsesButcheringFreshMeatAddsFoodToInventoryAndConsumesTheCorpse()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local level = { corpses = {} }
  Corpses.spawn(level, rat)
  local corpse = level.corpses[1]
  local game = { player = corpsePlayer(), level = level }
  local line = Corpses.butcher(game, corpse)
  eq(#level.corpses, 0, "butchering removes the corpse from the level")
  eq(#game.player.inventory, 1, "butchering fresh meat adds a food item to the inventory")
  eq(game.player.inventory[1].kind, Items.FOOD, "the yield is a food item")
  eq(game.player.inventory[1].nutrition, corpse.nutrition, "the food item carries the corpse's own nutrition value")
  ok(contains(line, "carve"), "a fresh butchering is logged as carving meat")
  ok(#game.player.statuses == 0, "fresh meat never poisons the player")
end

function tests.corpsesButcheringRottenMeatPoisonsThePlayerInsteadAndStillConsumesTheCorpse()
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  local level = { corpses = {} }
  Corpses.spawn(level, rat)
  local corpse = level.corpses[1]
  corpse.decay = Corpses.ROT_TURNS
  local game = { player = corpsePlayer(), level = level }
  local line = Corpses.butcher(game, corpse)
  eq(#level.corpses, 0, "butchering removes a rotten corpse too")
  eq(#game.player.inventory, 0, "rotten meat yields no food item")
  ok(Status.has(game.player, Status.POISON), "eating rotten meat poisons the player")
  ok(contains(line, "rotted"), "a rotten butchering is logged as such")
end

function tests.corpseFieldsSurviveSerialization()
  local level = arena(21, 11)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(level, rat)
  level.corpses[1].x, level.corpses[1].y = 4, 4
  local restored = Level.fromData(level:toData())
  eq(#restored.corpses, 1, "the corpse list survives a round trip")
  eq(restored.corpses[1].species, "rat", "a corpse's species survives a round trip")
  eq(restored.corpses[1].nutrition, level.corpses[1].nutrition, "a corpse's nutrition survives a round trip")
  eq(restored.corpses[1].decay, level.corpses[1].decay, "a corpse's decay survives a round trip")
end

function tests.corpseRendersItsGlyphWhenVisible()
  local rendered = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 6, 1)
  Corpses.spawn(rendered.level, rat)
  rendered:computeVisible()
  ok(contains(rendered:render(), "%"), "a corpse on a visible cell renders as its glyph")
end

function tests.gameAwardKillLeavesACorpseForAWildMonsterButNotForUndeadOrMimic()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 4, 6, 1)
  rat.hp = 0
  game.level.entities = { rat }
  game:awardKill(rat)
  eq(#game.level.corpses, 1, "killing a wild monster through awardKill leaves a corpse")
  eq(game.level.corpses[1].x, 4, "the corpse sits exactly where the monster fell")

  local zombie = Monsters.create(Monsters.byKey.zombie, 2, 4, 7, 4)
  zombie.hp = 0
  game.level.entities = { zombie }
  game:awardKill(zombie)
  eq(#game.level.corpses, 1, "killing an undead monster through awardKill leaves no new corpse")
end

function tests.gameButcherCorpseAtFreshMeatFeedsThePlayerAndClearsTheCorpse()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local before = #game.player.inventory
  ok(game:butcherCorpse(), "butchering the corpse underfoot succeeds")
  eq(#game.level.corpses, 0, "the corpse is gone after butchering")
  eq(#game.player.inventory, before + 1, "the player's inventory gains the carved meat")
end

function tests.gameButcherCorpseFailsWithoutACorpseUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:butcherCorpse(), "butchering empty ground fails")
end

function tests.autopilotButchersAFreshCorpseWhenIdleAndStandingOnIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local before = #game.player.inventory
  game:choosePlayerAction()
  eq(#game.level.corpses, 0, "the autopilot butchers a fresh corpse it stands on")
  eq(#game.player.inventory, before + 1, "the autopilot's butchering actually yields food")
end

function tests.autopilotLeavesARottenCorpseAloneRatherThanRiskingPoison()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.level.corpses[1].decay = Corpses.ROT_TURNS
  game:choosePlayerAction()
  eq(#game.level.corpses, 1, "the autopilot never touches a rotten corpse")
  ok(not Status.has(game.player, Status.POISON), "the autopilot never risks poisoning itself on rotten meat")
end

function tests.hungerCurrentDefaultsToCapForAFreshEntity()
  eq(Hunger.current({}), Hunger.CAP, "an entity with no satiation field reads as fully fed")
end

function tests.hungerTierOfClassifiesEachBandAtItsBoundaries()
  eq(Hunger.tierOf({ satiation = Hunger.CAP }), Hunger.FED, "a full meter is fed")
  eq(Hunger.tierOf({ satiation = Hunger.HUNGRY_MAX + 1 }), Hunger.FED, "just above the hungry ceiling is still fed")
  eq(Hunger.tierOf({ satiation = Hunger.HUNGRY_MAX }), Hunger.HUNGRY, "the hungry ceiling itself reads as hungry")
  eq(Hunger.tierOf({ satiation = Hunger.WEAK_MAX + 1 }), Hunger.HUNGRY, "just above the weak ceiling is still hungry")
  eq(Hunger.tierOf({ satiation = Hunger.WEAK_MAX }), Hunger.WEAK, "the weak ceiling itself reads as weak")
  eq(Hunger.tierOf({ satiation = 1 }), Hunger.WEAK, "one point above zero is still weak, never starving")
  eq(Hunger.tierOf({ satiation = 0 }), Hunger.STARVING, "zero itself is starving")
end

function tests.hungerAttackAndDefensePenaltiesEscalateByTier()
  eq(Hunger.attackPenalty({ satiation = Hunger.CAP }), 0, "a fed body carries no attack penalty")
  eq(Hunger.attackPenalty({ satiation = Hunger.HUNGRY_MAX }), 0, "merely hungry still carries no attack penalty")
  eq(Hunger.attackPenalty({ satiation = Hunger.WEAK_MAX }), -2, "weak costs two points of attack")
  eq(Hunger.attackPenalty({ satiation = 0 }), -4, "starving costs four points of attack")
  eq(Hunger.defensePenalty({ satiation = Hunger.CAP }), 0, "a fed body carries no defense penalty")
  eq(Hunger.defensePenalty({ satiation = Hunger.HUNGRY_MAX }), 0, "merely hungry still carries no defense penalty")
  eq(Hunger.defensePenalty({ satiation = Hunger.WEAK_MAX }), -1, "weak costs one point of defense")
  eq(Hunger.defensePenalty({ satiation = 0 }), -3, "starving costs three points of defense")
end

function tests.entityEffectiveAttackAndDefenseFoldInTheHungerPenalty()
  local entity = Entity.new({ x = 1, y = 1, glyph = "@", name = "you", kind = "player", hp = 20, attack = 6, defense = 4 })
  eq(entity:effectiveAttack(), 6, "a fresh entity with no satiation field carries no penalty")
  entity.satiation = 0
  eq(entity:effectiveAttack(), 2, "a starving body's attack penalty is live in effectiveAttack")
  eq(entity:effectiveDefense(), 1, "a starving body's defense penalty is live in effectiveDefense")
end

function tests.hungerSuppressesRegenOnlyAtWeakOrWorse()
  ok(not Hunger.suppressesRegen({ satiation = Hunger.HUNGRY_MAX }), "merely hungry never blocks passive regen")
  ok(Hunger.suppressesRegen({ satiation = Hunger.WEAK_MAX }), "weak blocks passive regen")
  ok(Hunger.suppressesRegen({ satiation = 0 }), "starving blocks passive regen")
end

function tests.hungerTickDrainsByOneAndLogsOnlyOnATierCrossing()
  local entity = { satiation = Hunger.HUNGRY_MAX + 2, hp = 20 }
  eq(Hunger.tick(entity), nil, "a drain turn that stays within its tier reports no line")
  eq(entity.satiation, Hunger.HUNGRY_MAX + 1, "the drain was still deducted even without a tier crossing")
  eq(Hunger.tick(entity), "you feel hungry", "crossing down into hungry is announced")
  eq(entity.satiation, Hunger.HUNGRY_MAX, "the meter keeps draining turn over turn")
  eq(entity.hp, 20, "hunger alone never costs hp above starving")
end

function tests.hungerTickBitesForOneHpEveryRoundWhileStarving()
  local entity = { satiation = 1, hp = 10 }
  eq(Hunger.tick(entity), "you are starving", "crossing down into starving is announced")
  eq(entity.satiation, 0, "starving is a floor, not a negative value")
  eq(entity.hp, 9, "reaching starving costs a point of hp immediately")
  eq(Hunger.tick(entity), "you are starving", "starving keeps announcing and biting every round it holds")
  eq(entity.hp, 8, "a second starving round costs a second point of hp")
end

function tests.hungerEatCapsAtTheCeilingAndWastesAnOverfullMealIntoBloat()
  local entity = { satiation = Hunger.CAP, statuses = {} }
  local bloated = Hunger.eat(entity, 400)
  ok(bloated, "eating while already at the cap reports the meal as wasted")
  eq(entity.satiation, Hunger.CAP, "an overfull meal never lifts satiation past the cap")
  ok(Status.has(entity, Status.SLOW), "an overfull meal leaves the diner slowed")
end

function tests.hungerEatBelowTheCeilingBanksNutritionWithNoWaste()
  local entity = { satiation = Hunger.HUNGRY_MAX, statuses = {} }
  local bloated = Hunger.eat(entity, 100)
  ok(not bloated, "an ordinary meal below the cap is never wasted")
  eq(entity.satiation, Hunger.HUNGRY_MAX + 100, "the full nutrition value is banked")
  ok(not Status.has(entity, Status.SLOW), "an ordinary meal never bloats the diner")
end

function tests.hungerEatClampsAMealThatWouldOverflowPastTheCapWithoutBloating()
  local entity = { satiation = Hunger.CAP - 50, statuses = {} }
  local bloated = Hunger.eat(entity, 400)
  ok(not bloated, "a meal eaten while still short of the cap is never wasted, even if it overflows")
  eq(entity.satiation, Hunger.CAP, "the surplus past the cap is simply clamped away")
  ok(not Status.has(entity, Status.SLOW), "clamping alone never bloats the diner")
end

function tests.gameHungerTorchTickSuppressesRingRegenOnceThePlayerIsWeak()
  local game = Game.new(1)
  Items.equipRing(Artifacts.create("ring_of_the_tide"), game.player)
  game.player.hp = game.player.maxHp - 10
  game.player.satiation = Hunger.WEAK_MAX
  local before = game.player.hp
  game:hungerTorchTick()
  eq(game.player.hp, before, "a weak player's ring of the tide grants no regen this turn")
end

function tests.gameUseItemEatingFoodRestoresSatiationAndLogsTheMeal()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.satiation = 200
  game.player.inventory = { Items.food("ration", 400) }
  ok(game:useItem(1), "eating a carried ration succeeds")
  eq(game.player.satiation, 600, "the ration's full nutrition is banked")
  eq(#game.player.inventory, 0, "the eaten ration leaves the inventory")
  ok(contains(game.log:last(), "eat"), "the meal is logged")
end

function tests.gameUseItemEatingFoodWhileAlreadyFullAppliesSlowAndLogsBloat()
  local game = stagedGame(1, arena(21, 11), 3, 6)
  game.player.satiation = Hunger.CAP
  game.player.inventory = { Items.food("ration", 400) }
  ok(game:useItem(1), "eating while already full still succeeds")
  eq(game.player.satiation, Hunger.CAP, "an overfull meal never lifts satiation past the cap")
  ok(Status.has(game.player, Status.SLOW), "eating past the cap leaves the player bloated and slow")
  ok(contains(game.log:last(), "bloated"), "the wasted meal is logged as bloating")
end

function tests.reanimationRaiseCreatesAThrallAdjacentToThePlayerAndSpendsTheCorpseAndSanity()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local corpse = game.level.corpses[1]
  local sanityBefore = game.player.sanity
  local thrall = Reanimation.raise(game, corpse)
  ok(thrall ~= nil, "raising a fresh corpse succeeds")
  eq(thrall.kind, "thrall", "a raised thrall is tagged with the thrall kind")
  eq(math.max(math.abs(thrall.x - 5), math.abs(thrall.y - 5)), 1, "the thrall rises adjacent to the player")
  eq(#game.level.corpses, 0, "raising the corpse consumes it")
  eq(game.player.sanity, sanityBefore - Reanimation.SANITY_COST, "raising a thrall costs a fixed bite of sanity")
end

function tests.reanimationRaiseRefusesARottenCorpseWithoutSpendingAnything()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.level.corpses[1].decay = Corpses.ROT_TURNS
  local sanityBefore = game.player.sanity
  local thrall, line = Reanimation.raise(game, game.level.corpses[1])
  eq(thrall, nil, "a rotten corpse cannot be raised")
  eq(#game.level.corpses, 1, "a refused raise leaves the corpse in place")
  eq(game.player.sanity, sanityBefore, "a refused raise spends no sanity")
  ok(contains(line, "rotted"), "the refusal explains the corpse has rotted too far")
end

function tests.reanimationRaiseRefusesWithoutEnoughSanityAndLeavesTheCorpseAlone()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.player.sanity = Reanimation.SANITY_COST - 1
  local thrall, line = Reanimation.raise(game, game.level.corpses[1])
  eq(thrall, nil, "raising fails when sanity is too low to pay the cost")
  eq(#game.level.corpses, 1, "a refused raise for lack of sanity leaves the corpse untouched")
  ok(contains(line, "mind"), "the refusal blames the player's own frail grip on their mind")
end

function tests.reanimationRaiseScalesThrallStatsDownFromTheOriginSpecies()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local troll = Monsters.create(Monsters.byKey.troll, 1, 5, 5, 5)
  Corpses.spawn(game.level, troll)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  eq(thrall.hp, math.floor(Monsters.byKey.troll.hp * Reanimation.HP_FRACTION),
    "a thrall's hp is a fixed fraction of the living species' own hp")
  eq(thrall.attack, Monsters.byKey.troll.attack - Reanimation.ATTACK_PENALTY,
    "a thrall's attack is blunted by a fixed amount from the living species")
  eq(thrall.defense, Monsters.byKey.troll.defense, "a thrall keeps the living species' own defense")
end

function tests.reanimationRaiseFallsBackToAPlainSkeletonForAnUnrecognisedSpecies()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.corpses[1] = { x = 5, y = 5, species = "unknown-thing", name = "unknown-thing", decay = Corpses.DECAY_TURNS }
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  ok(thrall ~= nil, "a corpse of an unrecognised species can still be raised")
  eq(thrall.hp, 8, "an unrecognised species falls back to a flat skeleton hp")
  eq(thrall.attack, 2, "an unrecognised species falls back to a flat skeleton attack")
end

function tests.reanimationRaiseRetiresAnEarlierThrallWhenRaisingAnother()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat1 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat1)
  local first = Reanimation.raise(game, game.level.corpses[1])
  local rat2 = Monsters.create(Monsters.byKey.rat, 2, 6, 5, 1)
  Corpses.spawn(game.level, rat2)
  local second = Reanimation.raise(game, game.level.corpses[1])
  ok(not first:isAlive(), "raising a new thrall retires the earlier one")
  ok(second:isAlive(), "the freshly raised thrall is alive")
  local alive = 0
  for _, e in ipairs(game.level.entities) do
    if e.kind == "thrall" and e:isAlive() then alive = alive + 1 end
  end
  eq(alive, 1, "only one thrall is ever alive at a time")
end

function tests.reanimationActAttacksAnAdjacentHostileMonsterAndCanKillIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 5, 5, 6)
  Corpses.spawn(game.level, chieftain)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local rat = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Reanimation.act(game, thrall)
  eq(rat.hp, 0, "a thrall's hit kills the weak rat standing next to it")
  ok(game.player.xp > xpBefore, "the player is credited xp for its thrall's kill")
end

function tests.reanimationActAdvancesOnAVisibleMonsterItCannotYetReach()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local orc = Monsters.create(Monsters.byKey.orc, 50, thrall.x + 5, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX = thrall.x
  Reanimation.act(game, thrall)
  ok(thrall.x > startX, "the thrall closes the distance to a monster it can see but not reach")
end

function tests.reanimationActIgnoresAMonsterBeyondItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 3, 3, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local orc = Monsters.create(Monsters.byKey.orc, 50, 19, 9, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX, startY = thrall.x, thrall.y
  Reanimation.act(game, thrall)
  eq(thrall.x, startX, "a monster far outside sight range does not pull the thrall off course (x)")
  eq(thrall.y, startY, "a monster far outside sight range does not pull the thrall off course (y)")
end

-- Same gap as companionActBlindedCompanionOnlyDetectsAnAdjacentHostileNot
-- OneWithinItsSightRadius, but for Reanimation.act's own nearestHostile.
function tests.reanimationActBlindedThrallOnlyDetectsAnAdjacentHostileNotOneWithinItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local farOrc = Monsters.create(Monsters.byKey.orc, 50, thrall.x + 5, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = farOrc
  Status.apply(thrall, Status.BLIND, 6, 1)
  local startX = thrall.x
  Reanimation.act(game, thrall)
  eq(thrall.x, startX, "a blinded thrall loses a sighting well within its listed sight radius")

  local rat = Monsters.create(Monsters.byKey.rat, 51, thrall.x + 1, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local ratHpBefore = rat.hp
  Reanimation.act(game, thrall)
  ok(rat.hp < ratHpBefore, "a blinded thrall still fights a hostile once it stands adjacent")
end

-- Same gap as companionActAttackingAnAdjacentMonsterEmitsNoise..., mirrored
-- onto the thrall side. Fresh game per seed rather than a shared one both to
-- match that sibling test's shape and because Reanimation.act decrements
-- thrall.decay on every call, so a single thrall could not absorb 200 calls
-- regardless.
function tests.reanimationActAttackingAnAdjacentMonsterEmitsNoiseThatCanStirADormantBystander()
  local stirred = false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local corpseSource = Monsters.create(Monsters.byKey.rat, 40, game.player.x + 1, game.player.y, 1)
    Corpses.spawn(game.level, corpseSource)
    local thrall = Reanimation.raise(game, game.level.corpses[1])
    local target = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
    local bystander = Monsters.create(Monsters.byKey.orc, 51, thrall.x + 4, thrall.y, 1)
    bystander.awareness = Stealth.DORMANT
    game.level.entities[#game.level.entities + 1] = target
    game.level.entities[#game.level.entities + 1] = bystander
    Reanimation.act(game, thrall)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a thrall's own melee is exactly as loud as any other ally's or the player's")
end

function tests.reanimationActFollowsThePlayerWhenNoMonsterIsVisible()
  local game = stagedGame(1, arena(21, 11), 10, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 10, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  thrall.x, thrall.y = 3, 5
  local startDist = math.abs(thrall.x - game.player.x)
  Reanimation.act(game, thrall)
  ok(math.abs(thrall.x - game.player.x) < startDist, "a thrall with no monster in sight closes in on the player")
end

-- Same wiring proof as the companion/hireling versions above, but for
-- Reanimation.act - placed after its own decay tick/death check (upkeep
-- the confusion roll must never skip), just before the behaviour it can
-- override.
function tests.reanimationActConfusedThrallSometimesStumblesInsteadOfFightingAnAdjacentHostile()
  local sawAttack, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local rat0 = Monsters.create(Monsters.byKey.rat, 1, 3, 6, 1)
    Corpses.spawn(game.level, rat0)
    local thrall = Reanimation.raise(game, game.level.corpses[1])
    local rat = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
    game.level.entities[#game.level.entities + 1] = rat
    Status.apply(thrall, Status.CONFUSE, 5, 1)
    local hpBefore = rat.hp
    Reanimation.act(game, thrall)
    if rat.hp < hpBefore then
      sawAttack = true
    else
      sawStumble = true
    end
    if sawAttack and sawStumble then break end
  end
  ok(sawAttack, "a confused thrall's roll sometimes lets it fight an adjacent hostile as normal")
  ok(sawStumble, "a confused thrall's roll sometimes overrides even a point-blank attack")
end

function tests.reanimationActCollapsesOnceItsBorrowedAnimationRunsOut()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat0 = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat0)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  thrall.decay = 1
  game:takeMonsterTurn(thrall)
  eq(#game.level.entities, 0, "a thrall whose animation runs out is swept from the level")
  ok(contains(game.log:last(), "crumbles"), "a collapsing thrall's fate is logged")
end

function tests.takeMonsterTurnRoutesAThrallThroughReanimationAct()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local chieftain = Monsters.create(Monsters.byKey.chieftain, 1, 5, 5, 6)
  Corpses.spawn(game.level, chieftain)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  local rat = Monsters.create(Monsters.byKey.rat, 50, thrall.x + 1, thrall.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  game:takeMonsterTurn(thrall)
  eq(rat.hp, 0, "the full monster-turn pipeline dispatches a thrall's turn to reanimation.act")
end

function tests.gameRaiseCorpseSucceedsAndLogsTheCallAnswered()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  ok(game:raiseCorpse(), "raising the corpse underfoot succeeds")
  eq(#game.level.corpses, 0, "the corpse is gone after raising")
  local hasThrall = false
  for _, e in ipairs(game.level.entities) do
    if e.kind == "thrall" then hasThrall = true end
  end
  ok(hasThrall, "a thrall joins the level once raised through the game action")
  ok(contains(game.log:last(), "answers the call"), "a successful raise is logged")
end

function tests.gameRaiseCorpseFailsWithoutACorpseUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:raiseCorpse(), "raising empty ground fails")
  ok(contains(game.log:last(), "nothing here"), "the failure is logged")
end

function tests.scavengingHerbForMapsEachWildFactionToItsOwnFixedHerb()
  eq(Scavenging.herbFor({ species = "rat" }), Alchemy.NIGHTCAP, "vermin always yields nightcap")
  eq(Scavenging.herbFor({ species = "goblin" }), Alchemy.BLOODROOT, "goblinoids always yield bloodroot")
  eq(Scavenging.herbFor({ species = "troll" }), Alchemy.EMBERLEAF, "beasts always yield emberleaf")
  eq(Scavenging.herbFor({ species = "dragon" }), Alchemy.EMBERLEAF, "drakes yield the same herb as any other beast-aspected foe")
end

function tests.scavengingHerbForReturnsNilForACorpseWithNoBestiaryEntry()
  eq(Scavenging.herbFor({ species = "hound" }), nil,
    "a bonded companion's own remains carry no bestiary-mapped herb")
end

function tests.gameScavengeCorpseCarvesTheMatchingHerbAndClearsTheCorpse()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local goblin = Monsters.create(Monsters.byKey.goblin, 1, 5, 5, 2)
  Corpses.spawn(game.level, goblin)
  local before = #game.player.inventory
  ok(game:scavengeCorpse(), "scavenging the corpse underfoot succeeds")
  eq(#game.level.corpses, 0, "the corpse is gone after scavenging")
  eq(#game.player.inventory, before + 1, "the player's inventory gains the carved herb")
  local herb = game.player.inventory[#game.player.inventory]
  eq(herb.herb, Alchemy.BLOODROOT, "the carved herb matches the goblin's own goblinoid aspect")
  ok(contains(game.log:last(), "carve"), "a successful scavenge is logged")
end

function tests.gameScavengeCorpseFailsWithoutACorpseUnderfoot()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  ok(not game:scavengeCorpse(), "scavenging empty ground fails")
  ok(contains(game.log:last(), "nothing here"), "the failure is logged")
end

function tests.gameScavengeCorpseFailsOnARottenCorpse()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  game.level.corpses[1].decay = Corpses.ROT_TURNS
  local before = #game.player.inventory
  ok(not game:scavengeCorpse(), "a rotten corpse yields no herb")
  eq(#game.level.corpses, 1, "a failed scavenge leaves the corpse in place rather than spending it")
  eq(#game.player.inventory, before, "no herb is added on a failed scavenge")
end

function tests.gameScavengeCorpseFailsForASpeciesWithNoKnownHerb()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.level.corpses = { { x = 5, y = 5, species = "hound", name = "hound", nutrition = 40, decay = Corpses.DECAY_TURNS } }
  ok(not game:scavengeCorpse(), "a companion's own remains carry nothing worth carving")
  eq(#game.level.corpses, 1, "a failed scavenge leaves the corpse in place")
end

function tests.reanimationFieldsSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local rat = Monsters.create(Monsters.byKey.rat, 1, 5, 5, 1)
  Corpses.spawn(game.level, rat)
  local thrall = Reanimation.raise(game, game.level.corpses[1])
  thrall.decay = 17
  local restoredLevel = Level.fromData(game.level:toData())
  eq(#restoredLevel.entities, 1, "the thrall survives a level round trip")
  eq(restoredLevel.entities[1].kind, "thrall", "the thrall's kind survives a round trip")
  eq(restoredLevel.entities[1].decay, 17, "the thrall's remaining animation survives a round trip")
end

function tests.herbItemsSurviveSerialization()
  local game = Game.new(5)
  game.player.inventory[#game.player.inventory + 1] = Alchemy.herb(Alchemy.NIGHTCAP)

  local path = os.tmpname()
  game:save(path)
  local restored = Game.load(path)
  os.remove(path)

  local restoredHerb
  for _, item in ipairs(restored.player.inventory) do
    if item.kind == Items.HERB then restoredHerb = item end
  end
  ok(restoredHerb ~= nil, "a foraged herb survives a save/load round trip")
  eq(restoredHerb.herb, Alchemy.NIGHTCAP, "a herb's species survives a save/load round trip")
end

function tests.potionOfFortificationAppliesAShield()
  local game = Game.new(31)
  Effects.apply("fortify", game, game.player, {})
  ok(Status.has(game.player, Status.SHIELD), "a fortify effect wards the drinker")
end

function tests.usingAFortifyPotionAppliesShieldAndConsumesIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local potion = Items.potionOf("fortify")
  game.player.inventory = { potion }
  ok(game:useItem(1), "drinking a fortify potion succeeds")
  eq(#game.player.inventory, 0, "drinking the potion consumes it")
  ok(Status.has(game.player, Status.SHIELD), "the fortify potion wards the player")
end

function tests.potionOfLevitationAppliesTheLevitateStatus()
  local game = Game.new(31)
  Effects.apply("levitate", game, game.player, {})
  ok(Status.has(game.player, Status.LEVITATE), "a levitate effect lifts the drinker off the ground")
end

function tests.usingAPotionOfLevitationAppliesLevitateAndConsumesIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local potion = Items.potionOf("levitate")
  game.player.inventory = { potion }
  ok(game:useItem(1), "drinking a levitation potion succeeds")
  eq(#game.player.inventory, 0, "drinking the potion consumes it")
  ok(Status.has(game.player, Status.LEVITATE), "the levitation potion lifts the player off the ground")
end

function tests.companionSummonPlacesItAdjacentToThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  ok(hound ~= nil, "summoning a valid species succeeds next to the player")
  eq(hound.kind, "companion", "a summoned companion is tagged with the companion kind")
  eq(math.max(math.abs(hound.x - 5), math.abs(hound.y - 5)), 1, "the companion lands adjacent to the player")
  eq(#game.level.entities, 1, "the companion joins the level's entity list")
end

function tests.companionSummonRejectsAnUnknownSpecies()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  eq(Companions.summon(game, "wyrm"), nil, "an unknown species key summons nothing")
  eq(#game.level.entities, 0, "no entity is added for an unknown species")
end

function tests.companionSummonReplacesAnEarlierBond()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local first = Companions.summon(game, "hound")
  local second = Companions.summon(game, "golem")
  ok(not first:isAlive(), "bonding a new companion retires the earlier one")
  ok(second:isAlive(), "the freshly bonded companion is alive")
  local alive = 0
  for _, e in ipairs(game.level.entities) do
    if e.kind == "companion" and e:isAlive() then alive = alive + 1 end
  end
  eq(alive, 1, "only one companion is ever alive at a time")
end

function tests.companionAttacksAdjacentHostileMonsterAndCanKillIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Companions.act(game, hound)
  eq(rat.hp, 0, "a hound's hit kills the weak rat standing next to it")
  ok(game.player.xp > xpBefore, "the player is credited xp for its companion's kill")
end

-- Before this fix, companions.lua's own "adjacent" helper was Manhattan-1
-- (cardinal only) while mercenaries.lua's and reanimation.lua's were
-- Chebyshev-1 (8-directional) despite both explicitly claiming to mirror
-- Companions.act's "same three-branch shape" - a hound diagonally next to a
-- monster fell through to stepMonsterToward instead of attacking, unlike a
-- hireling or thrall caught in the identical geometry.
function tests.companionAttacksADiagonallyAdjacentHostileMonsterJustLikeACardinalOne()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y + 1, 1)
  game.level.entities[#game.level.entities + 1] = rat
  Companions.act(game, hound)
  eq(rat.hp, 0, "a hound's hit kills a weak rat standing diagonally next to it, not just cardinally")
end

function tests.companionAdvancesOnAVisibleMonsterItCannotYetReach()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local orc = Monsters.create(Monsters.byKey.orc, 50, hound.x + 5, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX = hound.x
  Companions.act(game, hound)
  ok(hound.x > startX, "the companion closes the distance to a monster it can see but not reach")
end

function tests.companionIgnoresAMonsterBeyondItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local hound = Companions.summon(game, "hound")
  local orc = Monsters.create(Monsters.byKey.orc, 50, 19, 9, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX, startY = hound.x, hound.y
  Companions.act(game, hound)
  eq(hound.x, startX, "a monster far outside sight range does not pull the companion off course (x)")
  eq(hound.y, startY, "a monster far outside sight range does not pull the companion off course (y)")
end

-- Before Companions.act's own nearestHostile clamped its sight to melee
-- range under Status.BLIND, a blinded companion kept its full listed sight
-- radius - the same gap Game:canSeePlayer's own clamp already closed for a
-- blinded hostile monster (canSeePlayerBlindedMonsterOnlyDetectsThePlayer
-- AtMeleeRange), just never mirrored onto the ally side.
function tests.companionActBlindedCompanionOnlyDetectsAnAdjacentHostileNotOneWithinItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local farOrc = Monsters.create(Monsters.byKey.orc, 50, hound.x + 5, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = farOrc
  Status.apply(hound, Status.BLIND, 6, 1)
  local startX = hound.x
  Companions.act(game, hound)
  eq(hound.x, startX, "a blinded companion loses a sighting well within its listed sight radius")

  local rat = Monsters.create(Monsters.byKey.rat, 51, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local ratHpBefore = rat.hp
  Companions.act(game, hound)
  ok(rat.hp < ratHpBefore, "a blinded companion still fights a hostile once it stands adjacent")
end

-- Companions.act called Combat.attack directly without ever routing through
-- Game:emitNoise, unlike Game:playerAttack/Game:monsterMelee which both do
-- (see gamePlayerAttackCanStirADormantBystanderThatIsNotEvenTheTarget and
-- gameMonsterMeleeCanStirADormantBystanderTooNotJustPlayerActions) - a
-- companion's own melee was silent to every dormant monster nearby, no
-- matter how loud its species' attack would be for the player or a hostile.
-- Fresh game per seed (unlike those two tests' single reused game) since a
-- companion attack, unlike a repeatable playerAttack/monsterMelee call, can
-- kill its one-hp-pool rat target outright.
function tests.companionActAttackingAnAdjacentMonsterEmitsNoiseThatCanStirADormantBystander()
  local stirred = false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local hound = Companions.summon(game, "hound")
    local target = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
    local bystander = Monsters.create(Monsters.byKey.orc, 51, hound.x + 4, hound.y, 1)
    bystander.awareness = Stealth.DORMANT
    game.level.entities[#game.level.entities + 1] = target
    game.level.entities[#game.level.entities + 1] = bystander
    Companions.act(game, hound)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a companion's own melee is exactly as loud as the player's or a hostile monster's")
end

function tests.companionFollowsThePlayerWhenNoMonsterIsVisible()
  local game = stagedGame(1, arena(21, 11), 10, 5)
  local golem = Companions.summon(game, "golem")
  golem.x, golem.y = 3, 5
  local startDist = math.abs(golem.x - game.player.x)
  Companions.act(game, golem)
  ok(math.abs(golem.x - game.player.x) < startDist, "a companion with no monster in sight closes in on the player")
end

-- Companions.act never dispatches through ai.lua, so without Game:allyActs
-- Confused wired in first it would leave Status.CONFUSE completely inert on
-- a companion despite Game:springTrap already applying it to "any victim".
-- Mirrors tests.aiActConfusedMonsterSometimesStumblesInsteadOfChasing's own
-- loop-over-seeds shape, but for a point-blank melee decision instead of a
-- chase step.
function tests.companionActConfusedCompanionSometimesStumblesInsteadOfFightingAnAdjacentHostile()
  local sawAttack, sawStumble = false, false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local golem = Companions.summon(game, "golem")
    local rat = Monsters.create(Monsters.byKey.rat, 50, golem.x + 1, golem.y, 1)
    game.level.entities[#game.level.entities + 1] = rat
    Status.apply(golem, Status.CONFUSE, 5, 1)
    local hpBefore = rat.hp
    Companions.act(game, golem)
    if rat.hp < hpBefore then
      sawAttack = true
    else
      sawStumble = true
    end
    if sawAttack and sawStumble then break end
  end
  ok(sawAttack, "a confused companion's roll sometimes lets it fight an adjacent hostile as normal")
  ok(sawStumble, "a confused companion's roll sometimes overrides even a point-blank attack")
end

-- Unlike a confused monster's stumble (Ai.act -> Game:moveMonster, which
-- treats a step onto the player's cell as an attack), a confused companion
-- must never land a hit on the very player it is bonded to defend - the
-- companion spawns due east of the player (Companions.summon's own
-- ADJACENT order), so a westward stumble roll aims exactly at the player's
-- cell across this seed range, and the player's hp must stay untouched
-- every single time regardless of which of the 4 directions actually rolls.
function tests.companionActConfusedCompanionNeverAttacksThePlayerEvenIfTheStumbleAimsAtItsCell()
  local sawMoved = false
  for seed = 1, 300 do
    local game = stagedGame(seed, arena(21, 11), 5, 5)
    local golem = Companions.summon(game, "golem")
    Status.apply(golem, Status.CONFUSE, 5, 1)
    local hpBefore = game.player.hp
    Companions.act(game, golem)
    eq(game.player.hp, hpBefore, "a confused companion never attacks the player even when its stumble aims at their cell")
    ok(not (golem.x == game.player.x and golem.y == game.player.y),
      "a confused companion's stumble is blocked, not allowed to share the player's own cell")
    if golem.x ~= 6 or golem.y ~= 5 then sawMoved = true end
  end
  ok(sawMoved, "the confused companion's stumble roll actually moves it somewhere across many seeds")
end

function tests.hearthSpriteMendsThePlayerWhenIdle()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.hp = game.player.maxHp - 5
  local sprite = Companions.summon(game, "sprite")
  local before = game.player.hp
  Companions.act(game, sprite)
  eq(game.player.hp, before + Companions.byKey.sprite.heal, "a hearth sprite mends its bonded player each idle turn")
end

function tests.useItemOnACharmBondsACompanionAndConsumesIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.inventory = { Items.charm("hound") }
  ok(game:useItem(1), "using a charm succeeds")
  eq(#game.player.inventory, 0, "the charm leaves the inventory once bonded")
  eq(#game.level.entities, 1, "the bonded hound is added to the level")
  eq(game.level.entities[1].species, "hound", "the bonded companion matches the charm's species")
end

function tests.takeMonsterTurnRoutesACompanionThroughCompanionsAct()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  game:takeMonsterTurn(hound)
  eq(rat.hp, 0, "the full monster-turn pipeline dispatches a companion's turn to companions.act")
end

-- Game:hungerTorchTick already ticks Disease.tick(self.player) every player
-- turn; Game:takeMonsterTurn never called the same generic, entity-agnostic
-- function for anyone else, so an ally infected through the new
-- infighting.lua bite chance above would sit permanently incubating -
-- never erupting, never escalating, never curable by anything that reads
-- disease state - since nothing ever advanced its clock.
function tests.gameTakeMonsterTurnTicksAnInfectedCompanionsDiseaseExactlyLikeThePlayersOwnEndOfTurnDoes()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  hound.hp, hound.maxHp = 1000, 1000
  Disease.infect(hound, Disease.PARASITES)
  local incubation = Disease.defs[Disease.PARASITES].incubation
  for _ = 1, incubation - 1 do
    game:takeMonsterTurn(hound)
    eq(hound.disease.stage, 0, "the companion's infection keeps quietly incubating turn by turn")
  end
  game:takeMonsterTurn(hound)
  eq(hound.disease.stage, 1, "the companion's infection erupts on schedule, exactly like the player's own would")
  ok(contains(game.log:last(), "breaks out in gut parasites"), "the eruption is logged with the companion's own name")
end

function tests.aFallenCompanionIsLoggedAndSweptWithoutAwardingXp()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  hound.hp = 1
  Status.apply(hound, Status.POISON, 1, 5)
  local xpBefore = game.player.xp
  game:takeMonsterTurn(hound)
  eq(#game.level.entities, 0, "a companion that dies to its own status tick is swept from the level")
  eq(game.player.xp, xpBefore, "a fallen companion grants the player no xp")
  ok(contains(game.log:last(), "falls"), "a fallen companion's death is logged")
end

function tests.builderOccasionallyPlacesACharmFromDepthThree()
  local level = Builder.build(3, Rng.new(1), {})
  local found
  for _, ground in ipairs(level.floorItems) do
    if ground.item.kind == Items.CHARM then found = ground.item end
  end
  ok(found ~= nil, "this seed's depth-3 floor places a companion's charm")
  ok(Companions.byKey[found.companion] ~= nil, "the charm names a real companion species")
end

function tests.charmsStayOffTheShallowestFloors()
  for seed = 1, 5 do
    for depth = 1, 2 do
      local level = Builder.build(depth, Rng.new(seed), {})
      for _, ground in ipairs(level.floorItems) do
        ok(ground.item.kind ~= Items.CHARM, "no charm appears above depth 3")
      end
    end
  end
end

function tests.companionFieldsSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  Companions.summon(game, "sprite")
  local restoredLevel = Level.fromData(game.level:toData())
  eq(#restoredLevel.entities, 1, "the companion survives a level round trip")
  eq(restoredLevel.entities[1].kind, "companion", "the companion's kind survives a round trip")
  eq(restoredLevel.entities[1].species, "sprite", "the companion's species survives a round trip")
end

function tests.companionGainXpBelowFirstThresholdBanksXpWithoutEvolving()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 5)
  eq(hound.companionXp, 5, "xp below the first threshold still accumulates")
  eq(hound.companionLevel, 1, "a companion under its first threshold stays at level 1")
  eq(hound.name, "hunting hound", "an unevolved companion keeps its base name")
  eq(hound.attack, 4, "an unevolved companion keeps its base attack")
end

function tests.companionGainXpAtFirstThresholdEvolvesRenamesAndGrowsStats()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 12)
  eq(hound.companionLevel, 2, "reaching the first threshold advances the companion to level 2")
  eq(hound.name, "warhound", "the first evolution renames the companion")
  eq(hound.maxHp, 20, "the first evolution's hp bonus raises max hp")
  eq(hound.hp, 20, "the first evolution's hp bonus also heals the same amount")
  eq(hound.attack, 6, "the first evolution's attack bonus is applied")
  eq(hound.defense, 1, "the first evolution's defense bonus is applied")
  ok(contains(game.log:last(), "evolves"), "an evolution is logged")
end

function tests.companionGainXpCrossingBothThresholdsAtOnceAppliesBothStagesCumulatively()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 40)
  eq(hound.companionLevel, 3, "a single large xp grant can vault past an intermediate threshold")
  eq(hound.name, "dire hound", "the companion carries the highest stage's name, not the first")
  eq(hound.maxHp, 30, "both stages' hp bonuses stack (14 base + 6 + 10)")
  eq(hound.attack, 9, "both stages' attack bonuses stack (4 base + 2 + 3)")
  eq(hound.defense, 2, "both stages' defense bonuses stack (0 base + 1 + 1)")
end

function tests.companionGainXpNeverReappliesAnAlreadyCrossedStage()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 12)
  Companions.gainXp(game, hound, 1)
  eq(hound.companionXp, 13, "further xp below the next threshold keeps accumulating")
  eq(hound.companionLevel, 2, "a companion does not advance again before its next threshold")
  eq(hound.attack, 6, "an already-crossed stage's bonus is never applied a second time")
end

function tests.companionGainXpAtMaxLevelJustBanksFurtherXpWithNoFurtherEvolution()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 40)
  Companions.gainXp(game, hound, 100)
  eq(hound.companionXp, 140, "xp keeps accumulating past the last stage")
  eq(hound.companionLevel, 3, "a fully evolved companion caps out at its last stage")
  eq(hound.attack, 9, "stats hold steady once every stage has already been crossed")
end

function tests.companionGainXpIgnoresAZeroOrNegativeAmount()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  Companions.gainXp(game, hound, 0)
  Companions.gainXp(game, hound, -5)
  eq(hound.companionXp, 0, "a zero or negative grant leaves companion xp untouched")
end

function tests.companionActCreditsItsOwnKillWithXpOnTopOfThePlayers()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local hound = Companions.summon(game, "hound")
  local rat = Monsters.create(Monsters.byKey.rat, 50, hound.x + 1, hound.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Companions.act(game, hound)
  eq(rat.hp, 0, "the hound's hit still kills the rat")
  eq(hound.companionXp, Monsters.xpFor(rat), "the companion banks the felled monster's own xp value")
  ok(game.player.xp > xpBefore, "the player is still separately credited xp for the companion's kill")
end

function tests.companionEvolutionBoostsAHearthSpriteHealingOnTopOfItsStaticRate()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  game.player.hp = game.player.maxHp - 10
  local sprite = Companions.summon(game, "sprite")
  Companions.gainXp(game, sprite, 10)
  eq(sprite.name, "kindled sprite", "the sprite's first evolution renames it")
  local before = game.player.hp
  Companions.act(game, sprite)
  eq(game.player.hp, before + Companions.byKey.sprite.heal + 1,
    "an evolved sprite heals its species rate plus its own evolution bonus")
end

function tests.companionLevelXpAndHealBonusSurviveSerialization()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sprite = Companions.summon(game, "sprite")
  Companions.gainXp(game, sprite, 10)
  local restoredLevel = Level.fromData(game.level:toData())
  local restored = restoredLevel.entities[1]
  eq(restored.companionLevel, 2, "the companion's level survives a round trip")
  eq(restored.companionXp, 10, "the companion's banked xp survives a round trip")
  eq(restored.companionHealBonus, 1, "the companion's evolved heal bonus survives a round trip")
  eq(restored.name, "kindled sprite", "the companion's evolved name survives a round trip")
end

function tests.mercenaryHireTakesOnAKnownRosterEntryAdjacentToThePlayer()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  ok(sellsword ~= nil, "hiring a valid roster key succeeds next to the player")
  eq(sellsword.kind, "hireling", "a hired mercenary is tagged with the hireling kind")
  eq(math.max(math.abs(sellsword.x - 5), math.abs(sellsword.y - 5)), 1, "the hireling lands adjacent to the player")
  eq(sellsword.loyalty, Mercenaries.START_LOYALTY, "a freshly hired mercenary starts at full loyalty")
  eq(sellsword.wage, Mercenaries.byKey.sellsword.wage, "the hireling carries its roster wage")
end

function tests.mercenaryHireRejectsAnUnknownRosterKey()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  eq(Mercenaries.hire(game, "dragon"), nil, "an unknown roster key hires nobody")
  eq(#game.level.entities, 0, "no entity is added for an unknown roster key")
end

function tests.mercenaryHireReplacesAnEarlierHireling()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local first = Mercenaries.hire(game, "sellsword")
  local second = Mercenaries.hire(game, "medic")
  ok(not first:isAlive(), "hiring a new mercenary retires the earlier one")
  ok(second:isAlive(), "the freshly hired mercenary is alive")
  local alive = 0
  for _, e in ipairs(game.level.entities) do
    if e.kind == "hireling" and e:isAlive() then alive = alive + 1 end
  end
  eq(alive, 1, "only one hireling is ever alive at a time")
end

function tests.mercenaryAttacksAdjacentHostileMonsterAndCanKillIt()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local rat = Monsters.create(Monsters.byKey.rat, 50, sellsword.x + 1, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local xpBefore = game.player.xp
  Mercenaries.act(game, sellsword)
  ok(rat.hp <= 0, "a sellsword's hit kills the weak rat standing next to it")
  ok(game.player.xp > xpBefore, "the player is credited xp for its hireling's kill")
end

function tests.mercenaryAdvancesOnAVisibleMonsterItCannotYetReach()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local orc = Monsters.create(Monsters.byKey.orc, 50, sellsword.x + 5, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX = sellsword.x
  Mercenaries.act(game, sellsword)
  ok(sellsword.x > startX, "the hireling closes the distance to a monster it can see but not reach")
end

function tests.mercenaryIgnoresAMonsterBeyondItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 3, 3)
  local medic = Mercenaries.hire(game, "medic")
  local orc = Monsters.create(Monsters.byKey.orc, 50, 19, 9, 1)
  game.level.entities[#game.level.entities + 1] = orc
  local startX, startY = medic.x, medic.y
  Mercenaries.act(game, medic)
  eq(medic.x, startX, "a monster far outside sight range does not pull the hireling off course (x)")
  eq(medic.y, startY, "a monster far outside sight range does not pull the hireling off course (y)")
end

-- Same gap as companionActBlindedCompanionOnlyDetectsAnAdjacentHostileNot
-- OneWithinItsSightRadius, but for Mercenaries.act's own nearestHostile.
function tests.mercenaryActBlindedHirelingOnlyDetectsAnAdjacentHostileNotOneWithinItsSightRadius()
  local game = stagedGame(1, arena(21, 11), 5, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  local farOrc = Monsters.create(Monsters.byKey.orc, 50, sellsword.x + 5, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = farOrc
  Status.apply(sellsword, Status.BLIND, 6, 1)
  local startX = sellsword.x
  Mercenaries.act(game, sellsword)
  eq(sellsword.x, startX, "a blinded hireling loses a sighting well within its listed sight radius")

  local rat = Monsters.create(Monsters.byKey.rat, 51, sellsword.x + 1, sellsword.y, 1)
  game.level.entities[#game.level.entities + 1] = rat
  local ratHpBefore = rat.hp
  Mercenaries.act(game, sellsword)
  ok(rat.hp < ratHpBefore, "a blinded hireling still fights a hostile once it stands adjacent")
end

-- Same gap as companionActAttackingAnAdjacentMonsterEmitsNoise..., mirrored
-- onto the hireling side: Mercenaries.act's own Combat.attack call never
-- routed through Game:emitNoise either.
function tests.mercenaryActAttackingAnAdjacentMonsterEmitsNoiseThatCanStirADormantBystander()
  local stirred = false
  for seed = 1, 200 do
    local game = stagedGame(seed, arena(21, 11), 3, 6)
    local sellsword = Mercenaries.hire(game, "sellsword")
    local target = Monsters.create(Monsters.byKey.rat, 50, sellsword.x + 1, sellsword.y, 1)
    local bystander = Monsters.create(Monsters.byKey.orc, 51, sellsword.x + 4, sellsword.y, 1)
    bystander.awareness = Stealth.DORMANT
    game.level.entities[#game.level.entities + 1] = target
    game.level.entities[#game.level.entities + 1] = bystander
    Mercenaries.act(game, sellsword)
    if bystander.awareness ~= Stealth.DORMANT then stirred = true; break end
  end
  ok(stirred, "a hireling's own melee is exactly as loud as a companion's or the player's")
end

function tests.mercenaryFollowsThePlayerWhenNoMonsterIsVisible()
  local game = stagedGame(1, arena(21, 11), 10, 5)
  local sellsword = Mercenaries.hire(game, "sellsword")
  sellsword.x, sellsword.y = 3, 5
  local startDist = math.abs(sellsword.x - game.player.x)
  Mercenaries.act(game, sellsword)
  ok(math.abs(sellsword.x - game.player.x) < startDist, "a hireling with no monster in sight closes in on the player")
end

-- Same wiring proof as tests.companionActConfusedCompanionSometimesStumbles
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
