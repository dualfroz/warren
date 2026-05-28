-- Data-driven status effects. Each effect ticks once when its host takes a turn:
-- damage-over-time drains hp, regeneration restores it, stun skips the action,
-- and haste/slow/strength feed modifiers into speed and combat. Effects are
-- plain data on entity.statuses so they serialize without special handling.

local Status = {}

Status.POISON = "poison"
Status.BURNING = "burning"
Status.STUN = "stun"
Status.REGEN = "regen"
Status.HASTE = "haste"
Status.SLOW = "slow"
Status.STRENGTH = "strength"

Status.defs = {
  [Status.POISON] = {
    glyph = "p",
    tick = function(entity, potency)
      entity.hp = entity.hp - potency
      return string.format("poison saps %s for %d", entity.name, potency)
    end,
  },
  [Status.BURNING] = {
    glyph = "b",
    tick = function(entity, potency)
      entity.hp = entity.hp - potency
      return string.format("flames sear %s for %d", entity.name, potency)
    end,
  },
  [Status.REGEN] = {
    glyph = "r",
    tick = function(entity, potency)
      local before = entity.hp
      entity.hp = math.min(entity.maxHp, entity.hp + potency)
      if entity.hp > before then
        return string.format("%s knits flesh for %d", entity.name, entity.hp - before)
      end
      return nil
    end,
  },
  [Status.STUN] = { glyph = "s", skipsTurn = true },
  [Status.HASTE] = { glyph = "h", speed = 60 },
  [Status.SLOW] = { glyph = "l", speed = -50 },
  [Status.STRENGTH] = { glyph = "S", attack = 3 },
}

function Status.apply(entity, kind, duration, potency)
  potency = potency or 1
  for _, active in ipairs(entity.statuses) do
    if active.kind == kind then
      active.duration = math.max(active.duration, duration)
      active.potency = math.max(active.potency, potency)
      return active
    end
  end
  local effect = { kind = kind, duration = duration, potency = potency }
  entity.statuses[#entity.statuses + 1] = effect
  return effect
end

function Status.has(entity, kind)
  for _, active in ipairs(entity.statuses) do
    if active.kind == kind then return true end
  end
  return false
end

-- Advances every effect one step, applying its tick and dropping expired ones.
-- Returns the log lines produced this step, in effect order.
function Status.tick(entity)
  local lines = {}
  local kept = {}
  for _, active in ipairs(entity.statuses) do
    local def = Status.defs[active.kind]
    if def.tick then
      local line = def.tick(entity, active.potency)
      if line then lines[#lines + 1] = line end
    end
    active.duration = active.duration - 1
    if active.duration > 0 then
      kept[#kept + 1] = active
    end
  end
  entity.statuses = kept
  return lines
end

function Status.speedModifier(entity)
  local delta = 0
  for _, active in ipairs(entity.statuses) do
    local def = Status.defs[active.kind]
    if def.speed then delta = delta + def.speed end
  end
  return delta
end

function Status.attackModifier(entity)
  local delta = 0
  for _, active in ipairs(entity.statuses) do
    local def = Status.defs[active.kind]
    if def.attack then delta = delta + def.attack end
  end
  return delta
end

function Status.skipsTurn(entity)
  for _, active in ipairs(entity.statuses) do
    if Status.defs[active.kind].skipsTurn then return true end
  end
  return false
end

return Status
