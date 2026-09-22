local Resistances = require("resistances")

local Disease = {}

Disease.ROT = "rot"
Disease.PLAGUE = "plague"
Disease.PARASITES = "parasites"

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
    name = "gut parasites", plural = true, incubation = 3, stageTurns = 10,
    stagePotency = { 1, 3, 5 },
  },
}

function Disease.isInfected(entity)
  return entity.disease ~= nil
end

function Disease.hasErupted(entity)
  return entity.disease ~= nil and entity.disease.stage > 0
end

function Disease.infect(entity, key)
  if Disease.isInfected(entity) then return false end
  local def = Disease.defs[key]
  if not def then return false end
  entity.disease = { key = key, incubation = def.incubation, stage = 0, sinceStage = 0 }
  return true
end

function Disease.cure(entity)
  if not Disease.isInfected(entity) then return false end
  entity.disease = nil
  return true
end

function Disease.stagePotency(entity)
  local infection = entity.disease
  if not infection or infection.stage == 0 then return 0 end
  return Disease.defs[infection.key].stagePotency[infection.stage]
end

local function isPlayer(entity)
  return entity.kind == "player"
end

local function worsens(def)
  return def.plural and "worsen" or "worsens"
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
    line = isPlayer(entity) and string.format("your %s %s", def.name, worsens(def))
      or string.format("%s's %s %s", entity.name, def.name, worsens(def))
  end
  return line
end

return Disease
