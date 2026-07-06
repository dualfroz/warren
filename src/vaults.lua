-- Lever-gated treasure rooms. A vault door only swings open once every lever
-- sharing its id has been pulled; the builder places the door at a doorway
-- pinch point and scatters its levers only on the side already reachable
-- without crossing it, so the puzzle is always solvable and the reward
-- sealed behind the door is always genuinely gated by it (see builder.lua's
-- vault placement, drawn dead last so it never perturbs any earlier
-- system's rng sequence).

local Items = require("items")
local Affixes = require("affixes")

local Vaults = {}

local treasureWeapons = {
  { name = "vault greatsword", power = 7 },
  { name = "vault warhammer",  power = 8 },
}
local treasureArmors = {
  { name = "vault aegis", power = 6 },
}

-- A guaranteed affix on a base already well above anything the floor's own
-- loot table can roll at this depth - the deterministic reward for solving
-- the puzzle, distinct from a normal drop's coin-flip affix (see
-- affixes.rollWeapon/rollArmor).
function Vaults.treasure(rng, depth)
  if rng:chance(1, 2) then
    local base = treasureWeapons[rng:range(1, #treasureWeapons)]
    local item = Items.weapon(base.name, base.power + depth // 3)
    return Affixes.decorate(item, Affixes.weapon[rng:range(1, #Affixes.weapon)])
  end
  local base = treasureArmors[rng:range(1, #treasureArmors)]
  local item = Items.armor(base.name, base.power + depth // 3)
  return Affixes.decorate(item, Affixes.armor[rng:range(1, #Affixes.armor)])
end

function Vaults.doorFor(level, id)
  for _, door in ipairs(level.vaultDoors) do
    if door.id == id then return door end
  end
  return nil
end

local function allPulled(level, id)
  for _, lever in ipairs(level.vaultLevers) do
    if lever.id == id and not lever.pulled then return false end
  end
  return true
end

-- Pulls `lever`, an idempotent no-op returning false if it was already
-- thrown. Returns (true, door) the instant this pull completes every lever
-- sharing its id and the door has not opened yet, or (true, nil) for a pull
-- that leaves the vault still sealed (or already open).
function Vaults.pull(level, lever)
  if lever.pulled then return false end
  lever.pulled = true
  if not allPulled(level, lever.id) then return true, nil end
  local door = Vaults.doorFor(level, lever.id)
  if door and not door.opened then return true, door end
  return true, nil
end

return Vaults
