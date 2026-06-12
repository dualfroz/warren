-- Turns a depth and a per-level rng into a fully populated Level: it runs a
-- generator, cuts the up and down stairs, hangs doors at corridor pinch points
-- (some locked, with a key seeded on the floor), then scatters monsters, loot,
-- traps and light sources. Everything draws from the passed rng, so a given
-- (worldSeed, depth) always yields the identical floor.

local Tiles = require("tiles")
local Gen = require("gen.init")
local Monsters = require("monsters")
local Items = require("items")
local Affixes = require("affixes")
local Level = require("level")

local Builder = {}

local WIDTH, HEIGHT = 60, 24

local weaponBases = {
  { name = "dagger", power = 2 }, { name = "mace", power = 3 },
  { name = "sword", power = 4 }, { name = "battle axe", power = 5 },
}
local armorBases = {
  { name = "leather armor", power = 1 }, { name = "chain mail", power = 2 },
  { name = "plate armor", power = 3 },
}

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Cells reachable from (sx, sy) through walkable terrain and closed doors, and -
-- when allowLocked is true - locked doors too. Used to guarantee the descent is
-- never sealed behind a locked door and that keys always sit on an openable side.
local function reachSet(map, sx, sy, allowLocked)
  local seen = { [map:index(sx, sy)] = true }
  local stack = { { sx, sy } }
  while #stack > 0 do
    local cell = stack[#stack]
    stack[#stack] = nil
    for _, step in ipairs(NEIGHBOURS) do
      local nx, ny = cell[1] + step[1], cell[2] + step[2]
      if map:inBounds(nx, ny) and map:isPassable(nx, ny, allowLocked) then
        local idx = map:index(nx, ny)
        if not seen[idx] then
          seen[idx] = true
          stack[#stack + 1] = { nx, ny }
        end
      end
    end
  end
  return seen
end

local function pickFree(reachable, rng, predicate)
  for _ = 1, 40 do
    local cell = reachable[rng:range(1, #reachable)]
    if predicate(cell.x, cell.y) then return cell.x, cell.y end
  end
  return nil
end

local function doorwayCandidates(map)
  local cells = {}
  for y = 3, map.height - 2 do
    for x = 3, map.width - 2 do
      if map:get(x, y) == Tiles.FLOOR then
        local wallW = map:get(x - 1, y) == Tiles.WALL
        local wallE = map:get(x + 1, y) == Tiles.WALL
        local wallN = map:get(x, y - 1) == Tiles.WALL
        local wallS = map:get(x, y + 1) == Tiles.WALL
        local openW = map:isWalkable(x - 1, y)
        local openE = map:isWalkable(x + 1, y)
        local openN = map:isWalkable(x, y - 1)
        local openS = map:isWalkable(x, y + 1)
        if (wallW and wallE and openN and openS) or (wallN and wallS and openW and openE) then
          cells[#cells + 1] = { x = x, y = y }
        end
      end
    end
  end
  return cells
end

local function rollItem(rng, depth)
  local roll = rng:range(1, 100)
  if roll <= 24 then
    local effects = { "heal", "heal", "strength", "haste", "poison" }
    return Items.potionOf(effects[rng:range(1, #effects)])
  elseif roll <= 40 then
    local effects = { "teleport", "identify", "mapping", "fireball" }
    return Items.scroll(effects[rng:range(1, #effects)])
  elseif roll <= 60 then
    local base = weaponBases[rng:range(1, #weaponBases)]
    return Affixes.decorate(Items.weapon(base.name, base.power), Affixes.rollWeapon(rng))
  elseif roll <= 76 then
    local base = armorBases[rng:range(1, #armorBases)]
    return Affixes.decorate(Items.armor(base.name, base.power), Affixes.rollArmor(rng))
  elseif roll <= 86 then
    return Items.ring("ring of power", rng:range(0, 1), rng:range(0, 1))
  else
    return Items.food("ration", 400)
  end
end

local function chosenGenerator(depth, options)
  if options and options.generator and Gen.has(options.generator) then
    return options.generator
  end
  return Gen.order[((depth - 1) % #Gen.order) + 1]
end

function Builder.build(depth, rng, options)
  local generator = chosenGenerator(depth, options)
  local map, reachable = Gen.build(generator, WIDTH, HEIGHT, rng)

  local upX, upY = reachable[1].x, reachable[1].y
  local downX, downY = reachable[#reachable].x, reachable[#reachable].y
  map:set(upX, upY, Tiles.STAIRS_UP)
  map:set(downX, downY, Tiles.STAIRS_DOWN)

  local occupied = {}
  local function mark(x, y) occupied[map:index(x, y)] = true end
  local function taken(x, y) return occupied[map:index(x, y)] == true end
  mark(upX, upY)
  mark(downX, downY)

  local traps, lights = {}, {}
  local floorItems = {}

  local candidates = doorwayCandidates(map)
  for i = #candidates, 2, -1 do
    local j = rng:range(1, i)
    candidates[i], candidates[j] = candidates[j], candidates[i]
  end
  local doorBudget = rng:range(2, 5)
  local lockedNeeded = 0
  for i = 1, math.min(doorBudget, #candidates) do
    local cell = candidates[i]
    if not taken(cell.x, cell.y) then
      if rng:chance(1, 4) then
        map:set(cell.x, cell.y, Tiles.DOOR_LOCKED)
        if reachSet(map, upX, upY, false)[map:index(downX, downY)] then
          lockedNeeded = lockedNeeded + 1
        else
          map:set(cell.x, cell.y, Tiles.DOOR_CLOSED)
        end
      else
        map:set(cell.x, cell.y, Tiles.DOOR_CLOSED)
      end
      mark(cell.x, cell.y)
    end
  end

  local openReach = reachSet(map, upX, upY, false)
  local function freeFloor(x, y)
    return map:isWalkable(x, y) and not taken(x, y)
  end
  local function keyable(x, y)
    return freeFloor(x, y) and openReach[map:index(x, y)] == true
  end

  for _ = 1, lockedNeeded do
    local x, y = pickFree(reachable, rng, keyable)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.key() }
      mark(x, y)
    end
  end

  local eligible = Monsters.forDepth(depth)
  local entities = {}
  local monsterCount = rng:range(3, 6) + depth
  for _ = 1, monsterCount do
    local x, y = pickFree(reachable, rng, function(cx, cy)
      if not freeFloor(cx, cy) then return false end
      return math.max(math.abs(cx - upX), math.abs(cy - upY)) > 3
    end)
    if x then
      local spec = eligible[rng:range(1, #eligible)]
      entities[#entities + 1] = Monsters.create(spec, #entities + 1, x, y, depth)
      mark(x, y)
    end
  end

  local itemCount = rng:range(2, 4) + depth // 2
  for _ = 1, itemCount do
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = rollItem(rng, depth) }
      mark(x, y)
    end
  end

  local trapEffects = { "dart", "poison", "teleport" }
  local trapCount = rng:range(1, 3) + depth // 3
  for _ = 1, trapCount do
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      traps[#traps + 1] = { x = x, y = y, effect = trapEffects[rng:range(1, #trapEffects)], revealed = false }
      mark(x, y)
    end
  end

  local dark = depth >= 3
  if dark then
    for _ = 1, rng:range(1, 3) do
      local x, y = pickFree(reachable, rng, function(cx, cy) return map:isWalkable(cx, cy) end)
      if x then lights[#lights + 1] = { x = x, y = y, radius = 4 } end
    end
  end

  return Level.new({
    depth = depth,
    generator = generator,
    map = map,
    entities = entities,
    floorItems = floorItems,
    traps = traps,
    lights = lights,
    dark = dark,
    explored = {},
    upX = upX, upY = upY,
    downX = downX, downY = downY,
  })
end

return Builder
