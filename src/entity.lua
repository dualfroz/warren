local Status = require("status")
local Encumbrance = require("encumbrance")
local Momentum = require("momentum")
local Sanity = require("sanity")
local Proficiency = require("proficiency")
local Hunger = require("hunger")

local Entity = {}
Entity.__index = Entity

function Entity.new(spec)
  return setmetatable({
    id = spec.id,
    x = spec.x, y = spec.y,
    glyph = spec.glyph,
    name = spec.name,
    kind = spec.kind,
    species = spec.species,
    ai = spec.ai,
    hp = spec.hp,
    maxHp = spec.maxHp or spec.hp,
    attack = spec.attack,
    defense = spec.defense,
    baseAttack = spec.attack,
    baseDefense = spec.defense,
    speed = spec.speed or 100,
    energy = spec.energy or 0,
    range = spec.range or 0,
    inventory = {},
    statuses = {},
    weapon = nil,
    armor = nil,
    ring = nil,
    bow = nil,
    pick = nil,
  }, Entity)
end

function Entity:isAlive()
  return self.hp > 0
end

function Entity:effectiveAttack()
  return self.attack + Status.attackModifier(self) + Momentum.attackBonus(self) + Sanity.attackPenalty(self)
    + Proficiency.attackBonus(self) + Hunger.attackPenalty(self)
end

function Entity:effectiveDefense()
  return self.defense + Status.defenseModifier(self) + Encumbrance.defensePenalty(self) + Sanity.defensePenalty(self)
    + Hunger.defensePenalty(self)
end

function Entity:effectiveSpeed()
  local speed = self.speed + Status.speedModifier(self) + Encumbrance.speedPenalty(self)
  if speed < 10 then speed = 10 end
  return speed
end

function Entity:encumbranceTier()
  return Encumbrance.tierFor(self)
end

function Entity:toData()
  return {
    id = self.id,
    x = self.x, y = self.y,
    glyph = self.glyph, name = self.name, kind = self.kind,
    species = self.species, ai = self.ai,
    hp = self.hp, maxHp = self.maxHp,
    attack = self.attack, defense = self.defense,
    baseAttack = self.baseAttack, baseDefense = self.baseDefense,
    speed = self.speed, energy = self.energy, range = self.range,
    inventory = self.inventory,
    statuses = self.statuses,
    weapon = self.weapon,
    armor = self.armor,
    ring = self.ring,
    bow = self.bow,
    pick = self.pick,
    regen = self.regen,
    onDeath = self.onDeath,
    breath = self.breath,
    ability = self.ability,
    summonSpecies = self.summonSpecies,
    summonedBy = self.summonedBy,
    cooldown = self.cooldown,
    fleeing = self.fleeing,
    stolen = self.stolen,
    splitGen = self.splitGen,
    hostile = self.hostile,
    isBoss = self.isBoss,
    bossKey = self.bossKey,
    enraged = self.enraged,
    desperate = self.desperate,
    channeling = self.channeling,
    novaSpent = self.novaSpent,
    resist = self.resist,
    faction = self.faction,
    provoked = self.provoked,
    elite = self.elite,
    eliteAffixes = self.eliteAffixes,
    eliteTier = self.eliteTier,
    mimic = self.mimic,
    grave = self.grave,
    graveClass = self.graveClass,
    graveGold = self.graveGold,
    graveEssence = self.graveEssence,
    proficiency = self.proficiency,
    awareness = self.awareness,
    lastKnownX = self.lastKnownX,
    lastKnownY = self.lastKnownY,
    lostTurns = self.lostTurns,
    searchTurns = self.searchTurns,
    combo = self.combo,
    decay = self.decay,
    wage = self.wage,
    loyalty = self.loyalty,
    wet = self.wet,
    nemesis = self.nemesis,
    nemesisGrudge = self.nemesisGrudge,
    disease = self.disease,
    biteDisease = self.biteDisease,
    companionXp = self.companionXp,
    companionLevel = self.companionLevel,
    companionHealBonus = self.companionHealBonus,
  }
end

function Entity.fromData(snapshot)
  local entity = setmetatable({}, Entity)
  for field, value in pairs(snapshot) do
    entity[field] = value
  end
  entity.inventory = snapshot.inventory or {}
  entity.statuses = snapshot.statuses or {}
  return entity
end

return Entity
