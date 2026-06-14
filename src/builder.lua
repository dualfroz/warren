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

-- The dungeon bottoms out here: the Amulet of Warren is guaranteed to be
-- somewhere on this floor, and there is no way to descend past it. Tests
-- override it via options.maxDepth to exercise a full fetch-and-return
-- playthrough without generating nine intervening floors.
Builder.MAX_DEPTH = 10

-- The effects a random floor trap, or a trap kit rolled as loot, can carry -
-- shared by the two draws below and exposed here so tests can assert against
-- the authoritative list instead of a copy that would go stale the next time
-- a new effect is appended.
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

-- Cells reachable from (sx, sy) through walkable terrain and closed doors, and -
-- when allowLocked is true - locked doors too. Used to guarantee the descent is
-- never sealed behind a locked door and that keys always sit on an openable side.
-- When allowVault is also true, a sealed vault door or a closed gate (see
-- below) counts as passable too, so the far side of an unopened vault or
-- gate puzzle can still be found for its treasure's placement.
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

-- Maps a floor item's kind to the wearable slot curses.lua knows how to
-- afflict, so the dead-last curse pass below can find every eligible piece
-- regardless of which earlier system placed it (a plain drop, a set piece,
-- vault treasure, ...).
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
      -- A wild monster starts asleep (see stealth.lua): a plain field set,
      -- never an rng draw, so it cannot perturb any placement roll below.
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

  -- Loose gold piles and the shopkeeper (below) are both gated to depth 4+:
  -- the shopkeeper joins Monsters.forDepth's eligible array from that depth
  -- on, and any new rng draw here would otherwise reshuffle the trap/light/
  -- amulet placement the fixed-maxDepth win-condition tests rely on for the
  -- shallow floors they actually exercise.
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

  -- A shopkeeper occasionally sets up on a floor, guarding a handful of
  -- priced wares. Gold to spend there comes from the loose piles above.
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

  -- Shrines join the shop above at depth 4+, for the same reason: an earlier
  -- rng draw would reshuffle the trap/light/amulet placement the fixed-
  -- maxDepth win-condition tests rely on for the shallow floors they exercise.
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

  -- A companion's bonding charm is the rarest of the depth-gated placements
  -- and, unlike the others, drawn last so it can never perturb the rng
  -- sequence any earlier system (traps, shrines, the shop, the amulet) relies
  -- on for its own placement.
  if depth >= 3 and rng:chance(1, 5) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Companions.order[rng:range(1, #Companions.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.charm(key) }
      mark(x, y)
    end
  end

  -- Rarer still, and drawn last of all for the same rng-ordering reason as
  -- the charm above: a named artifact with a fixed, always-on mechanic.
  if depth >= 5 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Artifacts.order[rng:range(1, #Artifacts.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Artifacts.create(key) }
      mark(x, y)
    end
  end

  -- A trap kit lets the player plant one of these same effects
  -- themselves (see Game:useItem's KIT branch and Game:checkTrapFor, which
  -- springs a planted trap on a monster exactly as a builder-placed one
  -- springs on the player). Drawn last of all so it can never perturb any
  -- earlier system's rng sequence, the charm and artifact included.
  if depth >= 2 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.kit(trapEffects[rng:range(1, #trapEffects)]) }
      mark(x, y)
    end
  end

  -- A named boss rarer still guards the deepest floors, drawn dead last of
  -- all for the same rng-ordering reason as the kit above: it can never
  -- perturb any earlier system's placement, artifacts included.
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

  -- A bounty board rarer than a trap kit but commoner than an artifact,
  -- offering a single fixed pact the moment the player steps onto it (see
  -- Game:tryAcceptQuest). Drawn dead last of all for the same rng-ordering
  -- reason as the boss above: it can never perturb any earlier system's
  -- placement, the boss included.
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

  -- Herbs dot every floor from the first, foraging material rather than a
  -- depth-gated reward. Drawn dead last of all, after the quest board, so
  -- they can never perturb any earlier system's rng sequence.
  local herbCount = rng:range(2, 4)
  for _ = 1, herbCount do
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Alchemy.order[rng:range(1, #Alchemy.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Alchemy.herb(key) }
      mark(x, y)
    end
  end

  -- A cauldron to brew those herbs at, rarer than the herbs themselves and
  -- gated to depth 2+ so the entrance floor is foraging-only. Drawn last of
  -- all for the same rng-ordering reason as the herbs above.
  local cauldrons = {}
  if depth >= 2 and rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      cauldrons[#cauldrons + 1] = { x = x, y = y }
      mark(x, y)
    end
  end

  -- Volatile terrain rarer than a cauldron, gated to depth 4+ so the entry
  -- floors are always safe: a lava pool of two to four adjoining cells that
  -- burns anyone standing on it (see Game:checkTerrainFor), a single chasm
  -- pit that drops the player to the floor below and swallows a monster
  -- whole (capped to floors that still have one to fall onto), and a patch
  -- of ice that sends a traveller sliding. Drawn dead last of all for the
  -- same rng-ordering reason as the cauldron above.
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

  -- Elite promotion rolls last of all, dead after the ice above: it only
  -- edits stats already-placed entities carry, never a position, so it
  -- cannot desync reachability - but rng-ordering discipline still applies,
  -- since it draws from the same stream every earlier placement in this
  -- floor already relied on.
  for _, entity in ipairs(entities) do
    Elites.maybePromote(rng, entity, depth)
  end

  -- A vault seals a treasure behind a lever puzzle instead of a key: a door
  -- set on an unused doorway pinch point that only swings open once every
  -- lever scattered on the side already reachable without it has been
  -- pulled (see vaults.lua). Rarer than a boss and drawn dead last of all so
  -- it can never perturb any earlier system's rng sequence, the boss and
  -- quest board included. Falls back to an ordinary closed door whenever the
  -- floor's geometry cannot host a genuine puzzle (no free doorway, no room
  -- for its levers, or no cell the door actually gates), so a vault never
  -- seals content behind an unsolvable or pointless door.
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
        -- No lever site or no cell the door actually gates: back out to a
        -- plain closed door so the puzzle is never unsolvable or hollow, and
        -- free the lever tiles this attempt already claimed.
        map:set(cell.x, cell.y, Tiles.DOOR_CLOSED)
        for _, lever in ipairs(vaultLevers) do
          map:set(lever.x, lever.y, Tiles.FLOOR)
        end
        vaultLevers = {}
      end
    end
  end

  -- Rune stones dot the dungeon from depth three on, rarer than a herb but
  -- commoner than a trap kit: raw components for runewords.lua's
  -- socket-and-match combo system, found rather than crafted so a build is
  -- bounded by what the floor actually offers. Drawn dead last of all,
  -- after the vault above, so it can never perturb any earlier system's
  -- rng sequence.
  if depth >= 3 and rng:chance(1, 2) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local key = Runewords.RUNES[rng:range(1, #Runewords.RUNES)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Runewords.rune(key) }
      mark(x, y)
    end
  end

  -- A floor-wide weather condition, drawn dead last of all so it can never
  -- perturb any earlier system's rng sequence: an infested reading retroactively
  -- bumps every monster already placed on this floor (exactly like Elites.
  -- maybePromote's own retroactive stat edit above), since only a stat and
  -- never a position is at stake.
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

  -- Ore veins and gem seams dot the dungeon from the second floor on, dead
  -- last of all so they can never perturb any earlier system's rng sequence:
  -- unlike the herbs above, a single visit does not spend a node outright -
  -- it holds a few charges and slowly reopens (see nodes.lua) - so a floor
  -- already cleared of monsters still rewards a return trip.
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

  -- A single item-set piece dots the dungeon from depth three on, rarer
  -- than a rune but commoner than an artifact: unlike an artifact's fixed
  -- always-on mechanic, a set piece is inert alone and only pays off once
  -- its match turns up too (see sets.lua). Drawn dead last of all, after
  -- the nodes above, so it can never perturb any earlier system's rng
  -- sequence.
  if depth >= 3 and rng:chance(1, 5) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      local entry = Sets.order[rng:range(1, #Sets.order)]
      floorItems[#floorItems + 1] = { x = x, y = y, item = Sets.create(entry.set, entry.slot) }
      mark(x, y)
    end
  end

  -- A single mimic disguises itself as loot from depth two on, rarer than
  -- a trap kit: unlike every item placed above, it is inert to look at and
  -- only bites once the player actually reaches for it (see mimics.lua).
  -- Drawn dead last of all, after the set piece above, so it can never
  -- perturb any earlier system's rng sequence.
  if depth >= 2 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Mimics.floorItem(rng) }
      mark(x, y)
    end
  end

  -- A scroll of remove curse turns up rarer than a mimic, the one dedicated
  -- remedy for the curse pass below that a run can actually find rather than
  -- having to gamble on a shrine of fortune. Drawn dead last of all, after
  -- the mimic above, so it can never perturb any earlier system's rng
  -- sequence.
  if depth >= 2 and rng:chance(1, 8) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.scroll("removecurse") }
      mark(x, y)
    end
  end

  -- Curses.lua's dark mirror of affixes.lua rolls dead last of all, after
  -- every item above has already been placed: it only edits the stats of
  -- weapons, armor, rings and bows already sitting in floorItems, never a
  -- position, so it cannot desync reachability - but rng-ordering discipline
  -- still applies, since it draws from the same stream every earlier
  -- placement in this floor already relied on. Skips anything that already
  -- landed a beneficial affix or names its own set/artifact, so a single
  -- drop is never simultaneously a blessing and a curse.
  for _, ground in ipairs(floorItems) do
    local slot = slotForCursableItem[ground.item.kind]
    if slot and not ground.price and not ground.item.affix and not ground.item.set and not ground.item.artifact then
      local curse = Curses.roll(rng, slot)
      if curse then Curses.afflict(ground.item, curse) end
    end
  end

  -- A miner's pick turns up rarer than the remove-curse scroll above, the
  -- one way a run can find its own way into a rock burrower's tunnel or dig
  -- a shortcut through a dead-end wall (see digging.lua). Drawn dead last
  -- of all, after the curse pass above, so it can never perturb any
  -- earlier system's rng sequence.
  if depth >= 2 and rng:chance(1, 10) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.pick() }
      mark(x, y)
    end
  end

  -- A lockpick turns up commoner than the miner's pick above, drawn dead
  -- last of all so it can never perturb any earlier system's rng sequence:
  -- the one way a run can gamble past a locked chest's lock without ever
  -- finding its key (see chests.lua's Chests.pick).
  if rng:chance(1, 4) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.lockpick() }
      mark(x, y)
    end
  end

  -- A single lootable chest dots the dungeon from the first floor on, rarer
  -- than a lockpick, drawn dead last of all so it can never perturb any
  -- earlier system's rng sequence: a locked one may also be trapped (see
  -- Chests.new), so a run either finds a key, gambles a lockpick, or leaves
  -- it be.
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

  -- A secret door hides a single alcove of bonus loot behind an otherwise
  -- ordinary stretch of wall, found only by lingering beside it long enough
  -- (see secrets.lua's passive sweep). Drawn dead last of all before the
  -- grave below - which must stay the true last word, since it is the one
  -- block whose own rng draw count depends on what the caller passed in
  -- (see its own comment) - so this can never perturb any earlier system's
  -- rng sequence either: picks an already-reachable floor cell and a
  -- direction whose neighbour and whose cell two further along are both
  -- still untouched solid rock, then carves that far cell into a one-tile
  -- room holding a single roll of loot. The door itself stays a plain wall
  -- tile until secrets.lua's sweep discovers it - this list only remembers
  -- where to look. Skipped outright whenever 40 random reachable cells in a
  -- row turn up no such spot, so a cramped floor's own geometry never
  -- forces the roll to place nothing.
  local secretDoors = {}
  if depth >= 2 and rng:chance(1, 4) then
    for _ = 1, 40 do
      local cell = reachable[rng:range(1, #reachable)]
      local dir = NEIGHBOURS[rng:range(1, #NEIGHBOURS)]
      local doorX, doorY = cell.x + dir[1], cell.y + dir[2]
      local roomX, roomY = cell.x + dir[1] * 2, cell.y + dir[2] * 2
      if roomX >= 2 and roomY >= 2 and roomX <= map.width - 1 and roomY <= map.height - 1
        and map:get(doorX, doorY) == Tiles.WALL and map:get(roomX, roomY) == Tiles.WALL then
        -- The room's only walkable neighbour may be the door itself: if any
        -- of its other three sides already happens to border open floor
        -- somewhere else in the layout, that side would let the player
        -- wander straight into the alcove without ever finding the door,
        -- so a candidate site with any such back way in is rejected outright.
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

  -- A biome reinforcement and hazard bloom, drawn dead last of all before
  -- the grave below - which must stay the true last word, since it is the
  -- one block whose own rng draw count depends on what the caller passed in
  -- (see its own comment) - so this can never perturb any earlier system's
  -- rng sequence either: see biomes.lua for why a floor's biome is a fixed
  -- function of depth rather than another dice roll like weather. The
  -- reinforcement draws only from natives of the eligible roster already
  -- computed above, so it can never plant a monster too deep for its own
  -- minDepth, and starts dormant exactly like every other wild monster
  -- placed above (see Stealth.DORMANT); the bloom seeds level.hazards the
  -- same way a fire spell or a trap would mid-game, just already
  -- smouldering the moment the floor is first entered.
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

  -- A pressure gate seals a second stash behind a shove puzzle instead of a
  -- lever pull: a gate set on an unused doorway pinch point that only stays
  -- open while a block's weight rests on its linked plate (see blocks.lua),
  -- rather than a lever's one-way, permanently-spent pull. The block always
  -- sits exactly two cells from its plate along a single cardinal direction,
  -- with the cell behind the block itself also free, so a single shove from
  -- that approach cell always lands it on the plate - the puzzle is never a
  -- multi-step arrangement a floor's own cramped geometry might make
  -- unsolvable. Also verifies, after sealing the gate shut, that the stairs
  -- down are still reachable without ever crossing it - exactly the same
  -- guarantee the locked-door pass above gives a key - so a gate can only
  -- ever seal optional treasure, never the one path through the floor.
  -- Falls back to an ordinary closed door whenever the floor's geometry
  -- cannot host a genuine puzzle (no free doorway, no straight three-cell
  -- run for the plate/block/approach, or the gate would seal the only route
  -- to the stairs), so a gate never seals content behind an unsolvable or
  -- pointless door. Drawn dead last of all before the grave below - which
  -- must stay the true last word (see its own comment) - so this can never
  -- perturb any earlier system's rng sequence either.
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

  -- A hand-authored prefab vault dots the deep dungeon from depth three on,
  -- sealed behind solid rock rather than gated by a key or a lever: the one
  -- way in is digging.lua's pick (or a burrower's own claws), swung from
  -- whichever reachable cell happens to border its outer wall. Anchored only
  -- over untouched rock - every cell of its footprint still the generator's
  -- own default fill - so it can never overwrite a corridor or room this
  -- floor's own generator already carved, and only accepted once at least
  -- one of its wall cells actually borders the reachable area, so a vault
  -- can never end up sealed unreachably deep inside solid rock no digger
  -- could ever find. Its monster and loot markers (see gen/prefab.lua) draw
  -- from the same eligible roster and item tables every earlier pass in this
  -- floor already used. Drawn dead last of all before the grave below -
  -- which must stay the true last word (see its own comment) - so this can
  -- never perturb any earlier system's rng sequence either.
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

  -- A net turns up from depth five on, rarer than a miner's pick, drawn dead
  -- last of all - after even the prefab vault pass above - so it can never
  -- perturb any earlier system's rng sequence: the one way a run carries the
  -- means to subdue a battered monster alive instead of finishing it off
  -- (see captives.lua), rather than a strictly worse copy of an ordinary
  -- weapon. Gated this deep so it can never turn up in the fixed shallow
  -- worlds the win-condition tests build with a low --maxDepth.
  if depth >= 5 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.net() }
      mark(x, y)
    end
  end

  -- A rift shard turns up from depth four on, rarer than a net, drawn dead
  -- last of all - after the net above - so it can never perturb any earlier
  -- system's rng sequence: fuel for the one crossing a rift (below) actually
  -- costs (see branches.lua), found a couple of floors ahead of where a rift
  -- can itself first appear so a run always has a real chance to be carrying
  -- one the day it matters.
  if depth >= 4 and rng:chance(1, 6) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      floorItems[#floorItems + 1] = { x = x, y = y, item = Items.riftstone() }
      mark(x, y)
    end
  end

  -- A rift tears open rarer still, only from depth six on, drawn dead last
  -- of all - after the shard above - so it can never perturb any earlier
  -- system's rng sequence: a shimmering, unstable seam in the floor a
  -- carried rift shard alone can stabilize into a crossing onto a short,
  -- harsher pocket floor (see branches.lua and Game:enterRift). Plain
  -- position-keyed level data exactly like a shrine or a node, never a tile
  -- of its own, so it needs no new entry in tiles.lua.
  local rifts = {}
  if depth >= 6 and rng:chance(1, 8) then
    local x, y = pickFree(reachable, rng, freeFloor)
    if x then
      rifts[#rifts + 1] = { x = x, y = y }
      mark(x, y)
    end
  end

  -- A previous run's grave turns up rarer than a pick, dead last of all -
  -- after the lockpick, chest, secret door, biome, gate and net pass above -
  -- so it can never perturb any earlier system's rng sequence: cross-run
  -- bones (see graves.lua), rolled only when the caller actually supplies
  -- any - a run without --meta, or a fresh meta with no recorded deaths
  -- yet, makes no extra rng draw here at all, so its floors stay
  -- byte-identical to a build with no graves system in play.
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
