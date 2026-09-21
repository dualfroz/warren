local Tiles = require("tiles")
local Gen = require("gen.init")
local Monsters = require("monsters")
local Items = require("items")
local Affixes = require("affixes")
local Shop = require("shop")
local Shrines = require("shrines")
local Companions = require("companions")
local Artifacts = require("artifacts")
local Bosses = require("bosses")
local Quests = require("quests")
local Alchemy = require("alchemy")
local Elites = require("elites")
local Vaults = require("vaults")
local Runewords = require("runewords")
local Atmosphere = require("atmosphere")
local Stealth = require("stealth")
local Crafting = require("crafting")
local Nodes = require("nodes")
local Sets = require("sets")
local Mimics = require("mimics")
local Curses = require("curses")
local Graves = require("graves")
local Chests = require("chests")
local Biomes = require("biomes")
local Hazards = require("hazards")
local Blocks = require("blocks")
local Prefab = require("gen.prefab")
local Level = require("level")

local Builder = {}

local WIDTH, HEIGHT = 60, 24

Builder.MAX_DEPTH = 10

Builder.TRAP_EFFECTS = { "dart", "poison", "teleport", "confuse", "blind", "stun" }

function Builder.maxDepth(options)
  return (options and options.maxDepth) or Builder.MAX_DEPTH
end

local weaponBases = {
  { name = "dagger", power = 2 }, { name = "mace", power = 3 },
  { name = "sword", power = 4 }, { name = "battle axe", power = 5 },
}
local armorBases = {
  { name = "leather armor", power = 1 }, { name = "chain mail", power = 2 },
  { name = "plate armor", power = 3 },
}
local bowBases = {
  { name = "short bow", power = 2, range = 5 },
  { name = "long bow", power = 3, range = 7 },
  { name = "crossbow", power = 4, range = 6 },
}

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function reachSet(map, sx, sy, allowLocked, allowVault)
  local seen = { [map:index(sx, sy)] = true }
  local stack = { { sx, sy } }
  while #stack > 0 do
    local cell = stack[#stack]
    stack[#stack] = nil
    for _, step in ipairs(NEIGHBOURS) do
      local nx, ny = cell[1] + step[1], cell[2] + step[2]
      if map:inBounds(nx, ny) then
        local passable = map:isPassable(nx, ny, allowLocked)
          or (allowVault and (Tiles.isVaultDoor(map:get(nx, ny)) or Tiles.isGate(map:get(nx, ny))))
        if passable then
          local idx = map:index(nx, ny)
          if not seen[idx] then
            seen[idx] = true
            stack[#stack + 1] = { nx, ny }
          end
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
  if roll <= 22 then
    local effects = { "heal", "heal", "strength", "haste", "poison", "clarity", "cure", "confuse", "blind", "levitate" }
    return Items.potionOf(effects[rng:range(1, #effects)])
  elseif roll <= 36 then
    local effects = { "teleport", "identify", "mapping", "fireball" }
    return Items.scroll(effects[rng:range(1, #effects)])
  elseif roll <= 54 then
    local base = weaponBases[rng:range(1, #weaponBases)]
    return Affixes.decorate(Items.weapon(base.name, base.power), Affixes.rollWeapon(rng))
  elseif roll <= 68 then
    local base = armorBases[rng:range(1, #armorBases)]
    return Affixes.decorate(Items.armor(base.name, base.power), Affixes.rollArmor(rng))
  elseif roll <= 76 then
    return Items.ring("ring of power", rng:range(0, 1), rng:range(0, 1))
  elseif roll <= 80 then
    local learnable = { "heal", "shield", "blink", "shock", "discord", "polymorph", "confuse", "blind", "levitate", "weaken", "cleanse" }
    return Items.tome(learnable[rng:range(1, #learnable)])
  elseif roll <= 84 then
    local base = bowBases[rng:range(1, #bowBases)]
    return Items.bow(base.name, base.power, base.range)
  elseif roll <= 92 then
    return Items.ammo("arrow", rng:range(4, 8))
  else
    return Items.food("ration", 400)
  end
end

local slotForCursableItem = {
  [Items.WEAPON] = "weapon", [Items.ARMOR] = "armor",
  [Items.RING] = "ring", [Items.BOW] = "bow",
}

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
      local monster = Monsters.create(spec, #entities + 1, x, y, depth)
      monster.awareness = Stealth.DORMANT
      entities[#entities + 1] = monster
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

  if depth >= 4 then
    local goldCount = rng:range(1, 3)
    for _ = 1, goldCount do
      local x, y = pickFree(reachable, rng, freeFloor)
      if x then
        floorItems[#floorItems + 1] = { x = x, y = y, item = Items.gold(rng:range(8, 20) + depth * 4) }
        mark(x, y)
      end
    end
  end

  if depth >= 4 and rng:chance(1, 3) then
    local sx, sy = pickFree(reachable, rng, freeFloor)
    if sx then
      local keeper = Monsters.create(Monsters.byKey.shopkeeper, #entities + 1, sx, sy, depth)
      entities[#entities + 1] = keeper
      mark(sx, sy)
      for _, item in ipairs(Shop.stock(rng)) do
        local x, y = pickFree(reachable, rng, freeFloor)
        if x then
          floorItems[#floorItems + 1] = {
            x = x, y = y, item = item, price = Shop.priceOf(item), shopId = keeper.id,
          }
          mark(x, y)
        end
      end
    end
  end

  local shrines = {}
  if depth >= 4 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local kind = Shrines.order[rng:range(1, #Shrines.order)]
      shrines[#shrines + 1] = { x = x, y = y, kind = kind, uses = 0 }
      mark(x, y)
    end
  end

  local trapEffects = Builder.TRAP_EFFECTS
  local trapCount = rng:range(1, 3) + depth // 3
  for _ = 1, trapCount do
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      traps[#traps + 1] = { x = x, y = y, effect = trapEffects[rng:range(1, #trapEffects)], revealed = false }
      mark(x, y)
    end
  end

  if depth == Builder.maxDepth(options) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.amulet() }
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

  if depth >= 3 and rng:chance(1, 5) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Companions.order[rng:range(1, #Companions.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.charm(key) }
      mark(x, y)
    end
  end

  if depth >= 5 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Artifacts.order[rng:range(1, #Artifacts.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Artifacts.create(key) }
      mark(x, y)
    end
  end

  if depth >= 2 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.kit(trapEffects[rng:range(1, #trapEffects)]) }
      mark(x, y)
    end
  end

  if depth >= 6 and rng:chance(1, 5) then
    local eligible = Bosses.forDepth(depth)
    if #eligible > 0 then
      local x, y = pickFree(reachable, rng, freeFloor)
      if x then
        local spec = eligible[rng:range(1, #eligible)]
        entities[#entities + 1] = Bosses.create(spec, #entities + 1, x, y)
        mark(x, y)
      end
    end
  end

  local questBoards = {}
  if depth >= 2 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      questBoards[#questBoards + 1] = {
        x = x, y = y, claimed = false,
        quest = Quests.generate(rng, depth, Builder.maxDepth(options)),
      }
    end
  end

  local herbCount = rng:range(2, 4)
  for _ = 1, herbCount do
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Alchemy.order[rng:range(1, #Alchemy.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Alchemy.herb(key) }
      mark(x, y)
    end
  end

  local cauldrons = {}
  if depth >= 2 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      cauldrons[#cauldrons + 1] = { x = x, y = y }
      mark(x, y)
    end
  end

  if depth >= 4 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      map:set(x, y, Tiles.LAVA)
      mark(x, y)
      for _ = 1, rng:range(1, 3) do
        local dir = NEIGHBOURS[rng:range(1, #NEIGHBOURS)]
        local nx, ny = x + dir[1], y + dir[2]
        if freeFloor(nx, ny) then
          map:set(nx, ny, Tiles.LAVA)
          mark(nx, ny)
        end
      end
    end
  end

  if depth >= 4 and depth < Builder.maxDepth(options) and rng:chance(1, 5) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      map:set(x, y, Tiles.CHASM)
      mark(x, y)
    end
  end

  if depth >= 4 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      map:set(x, y, Tiles.ICE)
      mark(x, y)
      for _ = 1, rng:range(1, 4) do
        local dir = NEIGHBOURS[rng:range(1, #NEIGHBOURS)]
        local nx, ny = x + dir[1], y + dir[2]
        if freeFloor(nx, ny) then
          map:set(nx, ny, Tiles.ICE)
          mark(nx, ny)
        end
      end
    end
  end

  for _, entity in ipairs(entities) do
    Elites.maybePromote(rng, entity, depth)
  end

  local vaultLevers, vaultDoors = {}, {}
  if depth >= 5 and rng:chance(1, 6) then
    local doorCandidates = doorwayCandidates(map)
    for i = #doorCandidates, 1, -1 do
      if taken(doorCandidates[i].x, doorCandidates[i].y) then
        table.remove(doorCandidates, i)
      end
    end
    if #doorCandidates > 0 then
      local cell = doorCandidates[rng:range(1, #doorCandidates)]
      map:set(cell.x, cell.y, Tiles.VAULT_DOOR)
      mark(cell.x, cell.y)
      local vaultId = "vault" .. depth
      local openSide = reachSet(map, upX, upY, false, false)
      local leverCount = rng:range(2, 3)
      for _ = 1, leverCount do
        local x, y = pickFree(reachable, rng, function(cx, cy)
          return freeFloor(cx, cy) and openSide[map:index(cx, cy)] == true
        end)
        if x then
          map:set(x, y, Tiles.LEVER)
          vaultLevers[#vaultLevers + 1] = { x = x, y = y, id = vaultId, pulled = false }
          mark(x, y)
        end
      end
      local farSide = reachSet(map, upX, upY, false, true)
      local tx, ty
      if #vaultLevers > 0 then
        tx, ty = pickFree(reachable, rng, function(cx, cy)
          return freeFloor(cx, cy) and farSide[map:index(cx, cy)] == true
            and openSide[map:index(cx, cy)] ~= true
        end)
      end
      if tx then
        vaultDoors[#vaultDoors + 1] = { x = cell.x, y = cell.y, id = vaultId, opened = false }
        floorItems[#floorItems + 1] = { x = tx, y = ty, item = Vaults.treasure(rng, depth) }
        mark(tx, ty)
      else
        map:set(cell.x, cell.y, Tiles.DOOR_CLOSED)
        for _, lever in ipairs(vaultLevers) do
          map:set(lever.x, lever.y, Tiles.FLOOR)
        end
        vaultLevers = {}
      end
    end
  end

  if depth >= 3 and rng:chance(1, 2) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Runewords.RUNES[rng:range(1, #Runewords.RUNES)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Runewords.rune(key) }
      mark(x, y)
    end
  end

  local weather
  if depth >= 2 and rng:chance(1, 3) then
    weather = Atmosphere.order[rng:range(1, #Atmosphere.order)]
    local attackBonus = Atmosphere.monsterAttackBonus(weather)
    if attackBonus > 0 then
      for _, entity in ipairs(entities) do
        entity.attack = entity.attack + attackBonus
        entity.baseAttack = entity.baseAttack + attackBonus
      end
    end
  end

  local nodes = {}
  if depth >= 2 then
    local veinCount = rng:range(1, 2)
    for _ = 1, veinCount do
      local x, y = pickFree(reachable, rng, freeFloor)
      if x then
        local kind = rng:chance(1, 2) and Nodes.ORE or Nodes.GEM
        local element = kind == Nodes.GEM and Crafting.elements[rng:range(1, #Crafting.elements)] or nil
        local node = Nodes.new(kind, element)
        node.x, node.y = x, y
        nodes[#nodes + 1] = node
        mark(x, y)
      end
    end
  end

  if depth >= 3 and rng:chance(1, 5) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local entry = Sets.order[rng:range(1, #Sets.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Sets.create(entry.set, entry.slot) }
      mark(x, y)
    end
  end

  if depth >= 2 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Mimics.floorItem(rng) }
      mark(x, y)
    end
  end

  if depth >= 2 and rng:chance(1, 8) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.scroll("removecurse") }
      mark(x, y)
    end
  end

  for _, ground in ipairs(floorItems) do
    local slot = slotForCursableItem[ground.item.kind]
    if slot and not ground.price and not ground.item.affix and not ground.item.set and not ground.item.artifact then
      local curse = Curses.roll(rng, slot)
      if curse then Curses.afflict(ground.item, curse) end
    end
  end

  if depth >= 2 and rng:chance(1, 10) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.pick() }
      mark(x, y)
    end
  end

  if rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.lockpick() }
      mark(x, y)
    end
  end

  local chests = {}
  if rng:chance(1, 3) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local chest = Chests.new(rng, depth)
      chest.x, chest.y = x, y
      chests[#chests + 1] = chest
      mark(x, y)
    end
  end

  local secretDoors = {}
  if depth >= 2 and rng:chance(1, 4) then
    for _ = 1, 40 do
      local cell = reachable[rng:range(1, #reachable)]
      local dir = NEIGHBOURS[rng:range(1, #NEIGHBOURS)]
      local doorX, doorY = cell.x + dir[1], cell.y + dir[2]
      local roomX, roomY = cell.x + dir[1] * 2, cell.y + dir[2] * 2
      if roomX >= 2 and roomY >= 2 and roomX <= map.width - 1 and roomY <= map.height - 1
        and map:get(doorX, doorY) == Tiles.WALL and map:get(roomX, roomY) == Tiles.WALL then
        local isolated = true
        for _, side in ipairs(NEIGHBOURS) do
          local ax, ay = roomX + side[1], roomY + side[2]
          if not (ax == doorX and ay == doorY) and map:isWalkable(ax, ay) then
            isolated = false
            break
          end
        end
        if isolated then
          map:set(roomX, roomY, Tiles.FLOOR)
          secretDoors[#secretDoors + 1] = { x = doorX, y = doorY, discovered = false }
          floorItems[#floorItems + 1] = { x = roomX, y = roomY, item = rollItem(rng, depth) }
          break
        end
      end
    end
  end

  local biome = Biomes.forDepth(depth)
  local natives = Biomes.nativesAmong(biome, eligible)
  if #natives > 0 and rng:chance(1, 3) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local spec = natives[rng:range(1, #natives)]
      local monster = Monsters.create(spec, #entities + 1, x, y, depth)
      monster.awareness = Stealth.DORMANT
      entities[#entities + 1] = monster
      mark(x, y)
    end
  end

  local hazards = {}
  if rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      hazards[#hazards + 1] = { x = x, y = y, kind = biome.hazardKind, duration = 4, potency = 2 }
    end
  end

  local blocks, plates, gates = {}, {}, {}
  if depth >= 3 and rng:chance(1, 5) then
    local doorCandidates = doorwayCandidates(map)
    for i = #doorCandidates, 1, -1 do
      if taken(doorCandidates[i].x, doorCandidates[i].y) then
        table.remove(doorCandidates, i)
      end
    end
    if #doorCandidates > 0 then
      local cell = doorCandidates[rng:range(1, #doorCandidates)]
      map:set(cell.x, cell.y, Tiles.GATE_CLOSED)
      mark(cell.x, cell.y)
      local sealsTheOnlyRoute = not reachSet(map, upX, upY, false)[map:index(downX, downY)]
      local openSide = reachSet(map, upX, upY, false, false)
      local function onOpenSide(cx, cy)
        return freeFloor(cx, cy) and openSide[map:index(cx, cy)] == true
      end
      local px, py = pickFree(reachable, rng, onOpenSide)
      local siteDirs = {}
      if px then
        for _, dir in ipairs(NEIGHBOURS) do
          local bx, by = px - dir[1], py - dir[2]
          local ax, ay = bx - dir[1], by - dir[2]
          if onOpenSide(bx, by) and onOpenSide(ax, ay) then
            siteDirs[#siteDirs + 1] = { bx = bx, by = by }
          end
        end
      end
      local tx, ty
      if not sealsTheOnlyRoute and #siteDirs > 0 then
        local farSide = reachSet(map, upX, upY, false, true)
        tx, ty = pickFree(reachable, rng, function(cx, cy)
          return freeFloor(cx, cy) and farSide[map:index(cx, cy)] == true
            and openSide[map:index(cx, cy)] ~= true
        end)
      end
      if tx then
        local site = siteDirs[rng:range(1, #siteDirs)]
        plates[#plates + 1] = { x = px, y = py, gateX = cell.x, gateY = cell.y }
        blocks[#blocks + 1] = { x = site.bx, y = site.by }
        gates[#gates + 1] = { x = cell.x, y = cell.y, open = false }
        mark(px, py)
        mark(site.bx, site.by)
        floorItems[#floorItems + 1] = { x = tx, y = ty, item = Blocks.treasure(rng, depth) }
        mark(tx, ty)
      else
        map:set(cell.x, cell.y, Tiles.DOOR_CLOSED)
      end
    end
  end

  local prefabVaults = {}
  if depth >= 3 and rng:chance(1, 5) then
    local vault = Prefab.vaults[rng:range(1, #Prefab.vaults)]
    local w, h = Prefab.size(vault)
    local vaultReach = reachSet(map, upX, upY, false)
    for _ = 1, 40 do
      local ox = rng:range(2, map.width - w)
      local oy = rng:range(2, map.height - h)
      if Prefab.fits(map, vault, ox, oy) then
        local untouched = true
        for y = oy, oy + h - 1 do
          for x = ox, ox + w - 1 do
            if map:get(x, y) ~= Tiles.WALL then untouched = false end
          end
        end
        local bordersReachable = false
        for y = oy - 1, oy + h do
          for x = ox - 1, ox + w do
            local onPerimeter = x < ox or x > ox + w - 1 or y < oy or y > oy + h - 1
            if onPerimeter and map:inBounds(x, y) and vaultReach[map:index(x, y)] then
              bordersReachable = true
            end
          end
        end
        if untouched and bordersReachable then
          local stamp = Prefab.stamp(map, vault, ox, oy)
          for _, spot in ipairs(stamp.treasure) do
            floorItems[#floorItems + 1] = { x = spot.x, y = spot.y, item = Vaults.treasure(rng, depth) }
            mark(spot.x, spot.y)
          end
          for _, spot in ipairs(stamp.loot) do
            floorItems[#floorItems + 1] = { x = spot.x, y = spot.y, item = rollItem(rng, depth) }
            mark(spot.x, spot.y)
          end
          for _, spot in ipairs(stamp.monsters) do
            local spec = eligible[rng:range(1, #eligible)]
            local monster = Monsters.create(spec, #entities + 1, spot.x, spot.y, depth)
            monster.awareness = Stealth.DORMANT
            entities[#entities + 1] = monster
            mark(spot.x, spot.y)
          end
          prefabVaults[#prefabVaults + 1] = { name = stamp.name, x = ox, y = oy, w = w, h = h }
          break
        end
      end
    end
  end

  if depth >= 5 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.net() }
      mark(x, y)
    end
  end

  if depth >= 4 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.riftstone() }
      mark(x, y)
    end
  end

  local rifts = {}
  if depth >= 6 and rng:chance(1, 8) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      rifts[#rifts + 1] = { x = x, y = y }
      mark(x, y)
    end
  end

  if options and options.graves and #options.graves > 0 then
    local eligibleGraves = Graves.eligibleFor(options.graves, depth)
    if #eligibleGraves > 0 and rng:chance(1, 5) then
      local x, y = pickFree(reachable, rng, freeFloor)
      if x then
        local grave = eligibleGraves[rng:range(1, #eligibleGraves)]
        floorItems[#floorItems + 1] = { x = x, y = y, item = Graves.floorItem(grave) }
        mark(x, y)
      end
    end
  end

  return Level.new({
    depth = depth,
    generator = generator,
    weather = weather,
    biome = biome.key,
    map = map,
    entities = entities,
    floorItems = floorItems,
    traps = traps,
    lights = lights,
    hazards = hazards,
    shrines = shrines,
    questBoards = questBoards,
    cauldrons = cauldrons,
    nodes = nodes,
    chests = chests,
    vaultLevers = vaultLevers,
    vaultDoors = vaultDoors,
    secretDoors = secretDoors,
    blocks = blocks,
    plates = plates,
    gates = gates,
    prefabVaults = prefabVaults,
    rifts = rifts,
    dark = dark,
    explored = {},
    upX = upX, upY = upY,
    downX = downX, downY = downY,
  })
end

return Builder
