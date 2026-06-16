-- Progressive affliction caught from a carrier's bite, distinct from both
-- status.lua's per-turn buffs/debuffs (a fixed potency for a fixed
-- duration) and curses.lua's item-bound penalties (permanent until a
-- specific remedy). A disease sits silently through its incubation with no
-- outward sign at all, then erupts and starts dealing damage every turn,
-- worsening to a harsher stage on a fixed clock if nothing cures it first.
-- Its tick damage routes through resistances.lua exactly like poison's own
-- damage-over-time (see status.lua's POISON tick), so a plague-resistant
-- survivor shrugs off what would gut anyone else. A disease is plain data
-- on entity.disease, so it serializes with no special handling; the carrier
-- tag a species bite leaves on entity.biteDisease (see monsters.lua) is
-- copied on exactly like breath or ability already are.

local Resistances = require("resistances")

local Disease = {}

Disease.ROT = "rot"
Disease.PLAGUE = "plague"
Disease.PARASITES = "parasites"

-- Fixed order so a given rng draw always names the same affliction.
Disease.order = { Disease.ROT, Disease.PLAGUE, Disease.PARASITES }

Disease.MAX_STAGE = 3

Disease.defs = {
  [Disease.ROT] = {
    name = "wound rot", incubation = 4, stageTurns = 8,
    stagePotency = { 2, 4, 7 },
  },
  [Disease.PLAGUE] = {
    name = "black plague", incubation = 6, stageTurns = 6,
    stagePotency = { 3, 6, 10 },
  },
  [Disease.PARASITES] = {
    name = "gut parasites", incubation = 3, stageTurns = 10,
    stagePotency = { 1, 3, 5 },
  },
}

function Disease.isInfected(entity)
  return entity.disease ~= nil
end

-- Whether the infection has finished incubating and is actively dealing
-- damage each tick, as opposed to sitting silent and undetected.
function Disease.hasErupted(entity)
  return entity.disease ~= nil and entity.disease.stage > 0
end

-- Seeds a fresh infection of `key` on `entity`, refusing to pile a second
-- affliction on top of one already incubating or erupted - the same
-- one-at-a-time rule status.lua's own stacking already enforces for e.g.
-- poison overwriting duration rather than compounding. Returns whether the
-- infection actually took hold.
function Disease.infect(entity, key)
  if Disease.isInfected(entity) then return false end
  local def = Disease.defs[key]
  if not def then return false end
  entity.disease = { key = key, incubation = def.incubation, stage = 0, sinceStage = 0 }
  return true
end

-- Lifts whatever infection `entity` is carrying, incubating or already
-- erupted alike. Returns false without state change when there was nothing
-- to cure.
function Disease.cure(entity)
  if not Disease.isInfected(entity) then return false end
  entity.disease = nil
  return true
end

-- The stage's flat tick damage before resistance is applied, or 0 while
-- still incubating (no outward symptom yet) or entirely uninfected.
function Disease.stagePotency(entity)
  local infection = entity.disease
  if not infection or infection.stage == 0 then return 0 end
  return Disease.defs[infection.key].stagePotency[infection.stage]
end

-- One tick per turn on the host's own clock: counts incubation down in
-- silence, breaks out into stage one the moment it reaches zero, then
-- deals that stage's potency each further tick and escalates to the next
-- stage once it has lingered untreated for its full stageTurns window (the
-- top stage simply keeps ticking rather than escalating further). Returns a
-- log line for anything a player would actually notice - the eruption
-- itself, an escalation, or a nonzero tick of damage - and nil for a turn
-- that only ticked incubation down uneventfully.
-- True only for the player, whose entity.name is the pronoun "you" - a
-- subject that takes plain ("you break out", "you are wracked") verb forms
-- in English rather than the third-person-singular ("breaks out", "is
-- wracked") a named host like "orc" takes. Every message below branches on
-- this exactly like Game:springTrap and Game:checkTerrainFor already branch
-- on the same pronoun problem elsewhere in the engine.
local function isPlayer(entity)
  return entity.kind == "player"
end

function Disease.tick(entity)
  local infection = entity.disease
  if not infection then return nil end
  local def = Disease.defs[infection.key]
  if infection.stage == 0 then
    infection.incubation = infection.incubation - 1
    if infection.incubation <= 0 then
      infection.stage = 1
      infection.sinceStage = 0
      return isPlayer(entity) and string.format("you break out in %s", def.name)
        or string.format("%s breaks out in %s", entity.name, def.name)
    end
    return nil
  end
  local dealt = Resistances.apply(entity, def.stagePotency[infection.stage], Resistances.POISON)
  entity.hp = entity.hp - dealt
  infection.sinceStage = infection.sinceStage + 1
  local line = nil
  if dealt > 0 then
    line = isPlayer(entity) and string.format("you are wracked by %s for %d", def.name, dealt)
      or string.format("%s is wracked by %s for %d", entity.name, def.name, dealt)
  end
  if infection.sinceStage >= def.stageTurns and infection.stage < Disease.MAX_STAGE then
    infection.stage = infection.stage + 1
    infection.sinceStage = 0
    line = isPlayer(entity) and string.format("your %s worsens", def.name)
      or string.format("%s's %s worsens", entity.name, def.name)
  end
  return line
end

return Disease
