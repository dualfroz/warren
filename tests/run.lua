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
local Serialize = require("serialize")
local Game = require("game")

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

function tests.effects()
  local game = Game.new(31)
  game.player.hp = 10
  Effects.apply("heal", game, game.player, { power = 8 })
  eq(game.player.hp, 18, "heal effect restores hp")
  Effects.apply("poison", game, game.player, { power = 3 })
  eq(Status.has(game.player, Status.POISON), true, "poison effect afflicts the target")

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
