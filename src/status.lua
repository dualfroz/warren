-- Data-driven status effects. Each effect ticks once when its host takes a turn:
-- damage-over-time drains hp, regeneration restores it, stun skips the action,
-- and haste/slow/strength feed modifiers into speed and combat. Effects are
-- plain data on entity.statuses so they serialize without special handling.
-- Poison and burning route their tick damage through resistances.lua, so a
-- poison-immune undead shrugs off venom entirely and a fire-resistant hide
-- only smoulders at half the usual potency.

local Resistances = require("resistances")
local Conductivity = require("conductivity")

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

-- Odds, rolled fresh each turn a confused actor tries to act, that its own
-- chosen direction gets overridden by a random one instead - see
-- Game:movePlayer's stumble branch and Ai.act's mirror of it for monsters.
Status.CONFUSE_NUMERATOR = 1
Status.CONFUSE_DENOMINATOR = 2

-- Debuffs a cleansing effect (see effects.lua's "cure" handler) is allowed to
-- strip early. Buffs (REGEN/HASTE/STRENGTH/SHIELD/LEVITATE) are deliberately
-- excluded - a curative should not also strip a buff the entity chose to be
-- carrying.
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
    glyph = "p",
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
    glyph = "b",
    tick = function(entity, potency)
      local dealt = Conductivity.applyFire(entity, potency)
      entity.hp = entity.hp - dealt
      if dealt <= 0 then return string.format("the flames wash over %s harmlessly", entity.name) end
      return string.format("flames sear %s for %d", entity.name, dealt)
    end,
  },
  [Status.REGEN] = {
    glyph = "r",
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
  [Status.STUN] = { glyph = "s", skipsTurn = true },
  [Status.HASTE] = { glyph = "h", speed = 60 },
  [Status.SLOW] = { glyph = "l", speed = -50 },
  [Status.STRENGTH] = { glyph = "S", attack = 3 },
  [Status.SHIELD] = { glyph = "d", defense = 4 },
  [Status.WEAKEN] = { glyph = "c", attack = -3 },
  -- No tick or stat modifier of its own: infighting.lua reads Status.has
  -- directly to decide whether a monster's turn goes to Ai.act at all.
  [Status.DISCORD] = { glyph = "o" },
  -- No tick or stat modifier of its own either: Game:movePlayer and Ai.act
  -- both read Status.has directly, at the point they would otherwise commit
  -- to a chosen direction, to roll whether that direction gets overridden.
  [Status.CONFUSE] = { glyph = "f" },
  -- No tick or stat modifier of its own: Game:effectiveRadius and
  -- Game:canSeePlayer both read Status.has directly, clamping vision instead
  -- of touching hp or combat stats - confuse scrambles where you go, blind
  -- scrambles what you can tell is there in the first place.
  [Status.BLIND] = { glyph = "!" },
  -- No tick or stat modifier of its own: Game:checkTerrainFor and
  -- Game:checkTrapFor (plus movePlayer's own trap check) read Status.has
  -- directly, letting a levitating entity drift clear of lava, a chasm's
  -- drop, an ice tile's slide, and any ground-pressure trap without ever
  -- touching whatever would otherwise trigger them.
  [Status.LEVITATE] = { glyph = "y" },
}

-- Records `kind` as active on `entity` for `duration` more ticks at `potency`,
-- or refreshes an already-active instance of the same kind to whichever of
-- the two durations and potencies is stronger. A soaked entity's own
-- dampness (see conductivity.lua) refuses a BURNING application outright,
-- before anything is recorded - returns nil and leaves entity.statuses
-- untouched, exactly as if the call had never been made.
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

-- Strips one named status outright, independent of its remaining duration.
-- Returns whether anything was actually removed.
function Status.remove(entity, kind)
  for i, active in ipairs(entity.statuses) do
    if active.kind == kind then
      table.remove(entity.statuses, i)
      return true
    end
  end
  return false
end

-- Strips every active status listed in Status.HOSTILE (poison, burning,
-- stun, slow, weaken, discord, confuse, blind), leaving buffs untouched.
-- Returns the kinds actually removed, in the order they were active, for
-- callers that want to report exactly what a cleansing effect lifted.
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
