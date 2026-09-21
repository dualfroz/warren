local Tiles = require("tiles")
local Status = require("status")
local Resistances = require("resistances")
local Conductivity = require("conductivity")

local Hazards = {}

Hazards.FIRE = "fire"
Hazards.GAS = "gas"

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

function Hazards.at(level, x, y, kind)
  for _, hz in ipairs(level.hazards) do
    if hz.x == x and hz.y == y and (not kind or hz.kind == kind) then return hz end
  end
  return nil
end

function Hazards.spawn(level, x, y, kind, duration, potency)
  if not level.map:inBounds(x, y) then return nil end
  if level.map:get(x, y) == Tiles.WALL then return nil end
  local existing = Hazards.at(level, x, y, kind)
  if existing then
    existing.duration = math.max(existing.duration, duration)
    existing.potency = math.max(existing.potency, potency)
    return existing
  end
  local hz = { x = x, y = y, kind = kind, duration = duration, potency = potency }
  level.hazards[#level.hazards + 1] = hz
  return hz
end

function Hazards.ignite(level, x, y, duration, potency)
  return Hazards.spawn(level, x, y, Hazards.FIRE, duration or 3, potency or 2)
end

function Hazards.spawnGas(level, x, y, duration, potency)
  return Hazards.spawn(level, x, y, Hazards.GAS, duration or 4, potency or 2)
end

function Hazards.afflict(level, entity)
  local hz = Hazards.at(level, entity.x, entity.y)
  if not hz then return nil end
  if hz.kind == Hazards.FIRE then
    local dealt = Conductivity.applyFire(entity, hz.potency)
    entity.hp = entity.hp - dealt
    Status.apply(entity, Status.BURNING, 2, math.max(1, hz.potency // 2))
    if Conductivity.isWet(entity) then
      return string.format("flames hiss against %s's soaked skin for %d", entity.name, dealt)
    end
    return string.format("flames engulf %s for %d", entity.name, dealt)
  end
  local dealt = Resistances.apply(entity, hz.potency, Resistances.POISON)
  entity.hp = entity.hp - dealt
  Status.apply(entity, Status.POISON, 2, math.max(1, hz.potency // 2))
  return string.format("choking fumes sicken %s for %d", entity.name, dealt)
end

local function canSpreadInto(level, x, y)
  if not level.map:inBounds(x, y) then return false end
  local tile = level.map:get(x, y)
  return Tiles.isWalkable(tile) and tile ~= Tiles.WATER
end

function Hazards.step(level, rng)
  local spawns = {}
  for _, hz in ipairs(level.hazards) do
    for _, dir in ipairs(DIRS) do
      local nx, ny = hz.x + dir[1], hz.y + dir[2]
      if canSpreadInto(level, nx, ny) and not Hazards.at(level, nx, ny, hz.kind)
        and rng:chance(1, 2) then
        spawns[#spawns + 1] = { nx, ny, hz.kind, hz.duration, hz.potency }
      end
    end
  end
  for _, s in ipairs(spawns) do
    Hazards.spawn(level, s[1], s[2], s[3], s[4], s[5])
  end

  local kept = {}
  for _, hz in ipairs(level.hazards) do
    local doused = hz.kind == Hazards.FIRE and level.map:get(hz.x, hz.y) == Tiles.WATER
    hz.duration = hz.duration - 1
    if hz.duration > 0 and not doused then
      kept[#kept + 1] = hz
    end
  end
  level.hazards = kept
end

return Hazards
