local Tiles = require("tiles")

local Digging = {}

Digging.CAVE_IN_CHANCE_DEN = 8
Digging.CAVE_IN_DAMAGE_MIN = 2
Digging.CAVE_IN_DAMAGE_MAX = 5
Digging.ORE_STRIKE_CHANCE_DEN = 10
Digging.ORE_ESSENCE_MIN = 4
Digging.ORE_ESSENCE_MAX = 9
Digging.DEFAULT_USES = 20

Digging.SENSE_RANGE = 6

function Digging.canDig(map, x, y)
  if not map:inBounds(x, y) then return false end
  local tile = map:get(x, y)
  return tile == Tiles.WALL or tile == Tiles.RUBBLE
end

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
