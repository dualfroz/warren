-- Pushable blocks: a block occupies a floor cell and blocks movement and
-- pathing exactly like a wall, but shoving it (see Game:movePlayer) relocates
-- it one cell in the push direction instead of just refusing the move, the
-- same "walk into it to interact" shape a closed door or a vault lever
-- already has. A block shoved into lava solidifies into rubble and one
-- shoved into a chasm fills the gap into plain floor - both permanently
-- consume the block, since it has nothing left to rest on once the hazard
-- it corrected is gone. Shoved onto a pressure plate instead, the block
-- survives and holds its linked gate open for as long as it stays put (see
-- Blocks.updateGates) - unlike vaults.lua's lever, a gate reseals the
-- instant the weight holding it open moves off the plate again.

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

-- A guaranteed affix on a base already well above anything the floor's own
-- loot table can roll at this depth, mirroring vaults.lua's own Vaults.
-- treasure but with names that never claim to come from a vault.
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

-- Whether a cell a block might be shoved into can actually receive it: in
-- bounds, not a wall, a door of any kind, or a gate, and not already host to
-- another block or a living entity. Lava and chasm cells count as
-- receiving even though Blocks.push special-cases what happens to them
-- next, rather than refusing the shove outright.
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

-- Shoves `block` by (dx, dy) if the far cell can receive it. Returns
-- (true, message) on a successful shove, resolving whatever lava or chasm
-- it lands in along the way (Blocks.remove), or (false) when the far cell
-- refuses it, exactly like bumping into a wall.
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

-- Whether any plate linked to `gate` currently carries a block's weight.
local function gateHeld(level, gate)
  for _, plate in ipairs(level.plates) do
    if plate.gateX == gate.x and plate.gateY == gate.y and level:blockAt(plate.x, plate.y) then
      return true
    end
  end
  return false
end

-- Re-evaluates every gate on the level against its own plates' current
-- weight, flipping both its tile glyph and its `open` field the instant a
-- plate gains or loses a block. Called after any block shove (Game:
-- movePlayer) so a gate reacts immediately rather than waiting for a full
-- turn tick, the same way Vaults.pull's door flip is immediate on the pull
-- that completes it.
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
