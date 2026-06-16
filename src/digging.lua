-- Tunneling through plain rock, player-driven with a limited-use pick and
-- monster-driven for a burrower born to it (see monsters.lua's "burrower"
-- species and ai.lua's "tunnel" behaviour). A dug wall never clears in one
-- swing: it crumbles to Tiles.RUBBLE first - already walkable and already
-- open to sight, unlike the wall it replaced - and only a second swing
-- against that same cell clears it the rest of the way to open floor, so a
-- tunnel always costs two hits, never one, whoever is swinging. A vault's
-- own boundary (Tiles.VAULT_DOOR) never yields no matter how many swings it
-- takes - only the lever it guards opens it (see Game:pullLever). Every
-- swing risks a cave-in that buries the digger for damage instead of
-- yielding progress, and a lucky one strikes a raw vein outright - clearing
-- the wall in a single stroke and paying out essence exactly like a spent
-- nodes.lua vein, but only for a digger that tracks essence at all (the
-- player; a no-op reward for anything else, i.e. a monster).
-- Digging mutates the map tile grid directly, exactly like terrain.lua's
-- hazards bake straight into it, so a dug tunnel needs no special
-- save-format handling of its own - the map already serializes.

local Tiles = require("tiles")

local Digging = {}

Digging.CAVE_IN_CHANCE_DEN = 8
Digging.CAVE_IN_DAMAGE_MIN = 2
Digging.CAVE_IN_DAMAGE_MAX = 5
Digging.ORE_STRIKE_CHANCE_DEN = 10
Digging.ORE_ESSENCE_MIN = 4
Digging.ORE_ESSENCE_MAX = 9
Digging.DEFAULT_USES = 20

-- A burrower senses the player's direction straight through solid rock out
-- to this many Chebyshev cells - beyond it, it idles exactly like "flee"
-- idles once it loses sight, rather than clawing forever from across the map.
Digging.SENSE_RANGE = 6

-- Only a plain wall or the rubble left by a prior swing can be dug further;
-- open floor has nothing left to carve and a vault door never yields.
function Digging.canDig(map, x, y)
  if not map:inBounds(x, y) then return false end
  local tile = map:get(x, y)
  return tile == Tiles.WALL or tile == Tiles.RUBBLE
end

-- Resolves one swing of `digger`'s pick (or a burrower's own claws) against
-- (x, y), already known diggable by the caller. Mutates the map tile in
-- place on progress, deals cave-in damage to the digger on bad luck, and
-- always returns a log line describing what happened.
function Digging.swing(game, digger, x, y)
  local map = game.level.map
  local tile = map:get(x, y)
  local isPlayer = digger == game.player
  if game.rng:chance(1, Digging.CAVE_IN_CHANCE_DEN) then
    local dealt = game.rng:range(Digging.CAVE_IN_DAMAGE_MIN, Digging.CAVE_IN_DAMAGE_MAX)
    digger.hp = digger.hp - dealt
    if isPlayer then return string.format("the rock groans and buries you for %d", dealt) end
    return string.format("the rock groans and buries %s for %d", digger.name, dealt)
  end
  if tile == Tiles.WALL then
    if game.rng:chance(1, Digging.ORE_STRIKE_CHANCE_DEN) then
      map:set(x, y, Tiles.FLOOR)
      if digger.essence ~= nil then
        local amount = game.rng:range(Digging.ORE_ESSENCE_MIN, Digging.ORE_ESSENCE_MAX)
        digger.essence = digger.essence + amount
        return string.format("you strike a vein and pocket %d essence", amount)
      end
      return string.format("%s claws straight through a vein of ore", digger.name)
    end
    map:set(x, y, Tiles.RUBBLE)
    if isPlayer then return "you carve through the rock" end
    return string.format("%s carves through the rock", digger.name)
  end
  map:set(x, y, Tiles.FLOOR)
  if isPlayer then return "you clear the rubble away" end
  return string.format("%s clears the rubble away", digger.name)
end

-- Consumes one use from `entity.pick`'s durability, discarding the tool
-- once its edge dulls past use. A no-op (returns nil) for anything without
-- a pick equipped - a burrower digs with its own claws instead, which never
-- wear out. Returns a log line only on the swing that breaks the tool.
function Digging.wearPick(entity)
  local pick = entity.pick
  if not pick then return nil end
  pick.uses = pick.uses - 1
  if pick.uses <= 0 then
    entity.pick = nil
    return "your " .. pick.name .. " crumbles apart from the strain"
  end
  return nil
end

-- Orthogonal step directions from (mx, my) toward (tx, ty), longer axis
-- first, in the same 4-connected grid every monster already moves and
-- paths on (see game.lua's MONSTER_DIRS, astar.lua's DIRS) - never a
-- diagonal, so a dug tunnel is always walkable by the same step logic that
-- carved it. Returns an empty list when already on the target cell.
function Digging.directionsToward(mx, my, tx, ty)
  local ddx = tx - mx
  local ddy = ty - my
  local dx = ddx > 0 and 1 or (ddx < 0 and -1 or 0)
  local dy = ddy > 0 and 1 or (ddy < 0 and -1 or 0)
  local dirs = {}
  if math.abs(ddx) >= math.abs(ddy) then
    if dx ~= 0 then dirs[#dirs + 1] = { dx, 0 } end
    if dy ~= 0 then dirs[#dirs + 1] = { 0, dy } end
  else
    if dy ~= 0 then dirs[#dirs + 1] = { 0, dy } end
    if dx ~= 0 then dirs[#dirs + 1] = { dx, 0 } end
  end
  return dirs
end

return Digging
