-- Player and monster actors. attack/defense are the effective values already
-- including equipment; baseAttack/baseDefense keep the unequipped totals. Energy
-- and speed drive the turn scheduler; statuses layer temporary modifiers on top.

local Status = require("status")

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
  }, Entity)
end

function Entity:isAlive()
  return self.hp > 0
end

function Entity:effectiveAttack()
  return self.attack + Status.attackModifier(self)
end

function Entity:effectiveDefense()
  return self.defense
end

function Entity:effectiveSpeed()
  local speed = self.speed + Status.speedModifier(self)
  if speed < 10 then speed = 10 end
  return speed
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
