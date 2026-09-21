local Tiles = require("tiles")
local Items = require("items")
local Affixes = require("affixes")

local Blocks = {}

local treasureWeapons = {
  { name = "gate-forged blade", power = 7 },
  { name = "gate-forged maul",  power = 8 },
}
local treasureArmors = {
  { name = "gate-forged plate", power = 6 },
}

function Blocks.treasure(rng, depth)
  if rng:chance(1, 2) then
    local base = treasureWeapons[rng:range(1, #treasureWeapons)]
    local item = Items.weapon(base.name, base.power + depth // 3)
    return Affixes.decorate(item, Affixes.weapon[rng:range(1, #Affixes.weapon)])
  end
  local base = treasureArmors[rng:range(1, #treasureArmors)]
  local item = Items.armor(base.name, base.power + depth // 3)
  return Affixes.decorate(item, Affixes.armor[rng:range(1, #Affixes.armor)])
end

function Blocks.canReceive(level, x, y)
  if not level.map:inBounds(x, y) then return false end
  local tile = level.map:get(x, y)
  if tile == Tiles.WALL or Tiles.isDoor(tile) or Tiles.isVaultDoor(tile) or Tiles.isGate(tile) then
    return false
  end
  if level:blockAt(x, y) or level:entityAt(x, y) then return false end
  return true
end

local function remove(level, block)
  for i, b in ipairs(level.blocks) do
    if b == block then
      table.remove(level.blocks, i)
      return
    end
  end
end

function Blocks.push(level, block, dx, dy)
  local nx, ny = block.x + dx, block.y + dy
  if not Blocks.canReceive(level, nx, ny) then return false end
  local tile = level.map:get(nx, ny)
  if tile == Tiles.LAVA then
    level.map:set(nx, ny, Tiles.RUBBLE)
    remove(level, block)
    return true, "the block hisses into the lava and cools into rubble"
  end
  if tile == Tiles.CHASM then
    level.map:set(nx, ny, Tiles.FLOOR)
    remove(level, block)
    return true, "the block tumbles into the chasm and fills it"
  end
  block.x, block.y = nx, ny
  return true, "you shove the block"
end

local function gateHeld(level, gate)
  for _, plate in ipairs(level.plates) do
    if plate.gateX == gate.x and plate.gateY == gate.y and level:blockAt(plate.x, plate.y) then
      return true
    end
  end
  return false
end

function Blocks.updateGates(level)
  for _, gate in ipairs(level.gates) do
    local held = gateHeld(level, gate)
    if held ~= gate.open then
      gate.open = held
      level.map:set(gate.x, gate.y, held and Tiles.GATE_OPEN or Tiles.GATE_CLOSED)
    end
  end
end

return Blocks
