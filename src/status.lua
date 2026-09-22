local Resistances = require("resistances")
local Conductivity = require("conductivity")
local Text = require("text")

local Status = {}

Status.POISON = "poison"
Status.BURNING = "burning"
Status.STUN = "stun"
Status.REGEN = "regen"
Status.HASTE = "haste"
Status.SLOW = "slow"
Status.STRENGTH = "strength"
Status.SHIELD = "shield"
Status.WEAKEN = "weaken"
Status.DISCORD = "discord"
Status.CONFUSE = "confuse"
Status.BLIND = "blind"
Status.LEVITATE = "levitate"

Status.CONFUSE_NUMERATOR = 1
Status.CONFUSE_DENOMINATOR = 2

Status.HOSTILE = {
  [Status.POISON] = true,
  [Status.BURNING] = true,
  [Status.STUN] = true,
  [Status.SLOW] = true,
  [Status.WEAKEN] = true,
  [Status.DISCORD] = true,
  [Status.CONFUSE] = true,
  [Status.BLIND] = true,
}

Status.defs = {
  [Status.POISON] = {
    glyph = "p", noun = "poison",
    tick = function(entity, potency)
      local dealt = Resistances.apply(entity, potency, Resistances.POISON)
      entity.hp = entity.hp - dealt
      if dealt <= 0 then
        return entity.kind == "player" and "you shrug off the poison"
          or string.format("%s shrugs off the poison", entity.name)
      end
      return string.format("poison saps %s for %d", entity.name, dealt)
    end,
  },
  [Status.BURNING] = {
    glyph = "b", noun = "burning",
    tick = function(entity, potency)
      local dealt = Conductivity.applyFire(entity, potency)
      entity.hp = entity.hp - dealt
      if dealt <= 0 then return string.format("the flames wash over %s harmlessly", entity.name) end
      return string.format("flames sear %s for %d", entity.name, dealt)
    end,
  },
  [Status.REGEN] = {
    glyph = "r", noun = "regeneration",
    tick = function(entity, potency)
      local before = entity.hp
      entity.hp = math.min(entity.maxHp, entity.hp + potency)
      if entity.hp > before then
        local healed = entity.hp - before
        return entity.kind == "player" and string.format("you knit flesh for %d", healed)
          or string.format("%s knits flesh for %d", entity.name, healed)
      end
      return nil
    end,
  },
  [Status.STUN] = { glyph = "s", noun = "stun", skipsTurn = true },
  [Status.HASTE] = { glyph = "h", noun = "haste", speed = 60 },
  [Status.SLOW] = { glyph = "l", noun = "slowness", speed = -50 },
  [Status.STRENGTH] = { glyph = "S", noun = "strength", attack = 3 },
  [Status.SHIELD] = { glyph = "d", noun = "shield", defense = 4 },
  [Status.WEAKEN] = { glyph = "c", noun = "weakness", attack = -3 },
  [Status.DISCORD] = { glyph = "o", noun = "discord" },
  [Status.CONFUSE] = { glyph = "f", noun = "confusion" },
  [Status.BLIND] = { glyph = "!", noun = "blindness" },
  [Status.LEVITATE] = { glyph = "y", noun = "levitation" },
}

Status.joinNaturally = Text.joinNaturally

function Status.noun(kind)
  return Status.defs[kind].noun
end

function Status.describe(kinds)
  local nouns = {}
  for i, kind in ipairs(kinds) do nouns[i] = Status.noun(kind) end
  return Status.joinNaturally(nouns)
end

function Status.apply(entity, kind, duration, potency)
  if kind == Status.BURNING and Conductivity.resistsIgnition(entity) then
    return nil
  end
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

function Status.remove(entity, kind)
  for i, active in ipairs(entity.statuses) do
    if active.kind == kind then
      table.remove(entity.statuses, i)
      return true
    end
  end
  return false
end

function Status.cureHostile(entity)
  local removed = {}
  local kept = {}
  for _, active in ipairs(entity.statuses) do
    if Status.HOSTILE[active.kind] then
      removed[#removed + 1] = active.kind
    else
      kept[#kept + 1] = active
    end
  end
  entity.statuses = kept
  return removed
end

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

function Status.defenseModifier(entity)
  local delta = 0
  for _, active in ipairs(entity.statuses) do
    local def = Status.defs[active.kind]
    if def.defense then delta = delta + def.defense end
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
