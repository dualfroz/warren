local Entity = require("entity")
local Artifacts = require("artifacts")

local Bosses = {}

Bosses.catalog = {
  {
    key = "warlord", glyph = "W", name = "the Orc Warlord",
    hp = 34, attack = 7, defense = 3, speed = 100, ai = "pack",
    minDepth = 6, xp = 40, ability = "rally",
    enrageAt = 0.5, enrageAttack = 4, enrageSpeed = 25, enrageHeal = 6,
    desperateAt = 0.2, desperateDefenseBonus = 5, novaDamage = 12, novaRadius = 2,
    lootKey = "warlords_cleaver",
  },
  {
    key = "lich", glyph = "L", name = "the Lich",
    hp = 28, attack = 5, defense = 2, speed = 100, ai = "flee", range = 6,
    minDepth = 7, xp = 45, ability = "curse",
    enrageAt = 0.5, enrageAttack = 3, enrageSpeed = 20, enrageHeal = 8,
    desperateAt = 0.2, desperateDefenseBonus = 4, novaDamage = 10, novaRadius = 2,
    lootKey = "lich_phylactery",
  },
  {
    key = "bonequeen", glyph = "Q", name = "the Bone Queen",
    hp = 32, attack = 4, defense = 2, speed = 95, ai = "flee",
    minDepth = 8, xp = 50, ability = "summon", summonSpecies = "zombie",
    enrageAt = 0.5, enrageAttack = 3, enrageSpeed = 15, enrageHeal = 10,
    desperateAt = 0.2, desperateDefenseBonus = 4, novaDamage = 11, novaRadius = 2,
    lootKey = "bone_queen_carapace",
  },
}

Bosses.byKey = {}
for _, spec in ipairs(Bosses.catalog) do
  Bosses.byKey[spec.key] = spec
end

function Bosses.forDepth(depth)
  local eligible = {}
  for _, spec in ipairs(Bosses.catalog) do
    if spec.minDepth <= depth then eligible[#eligible + 1] = spec end
  end
  return eligible
end

function Bosses.create(spec, id, x, y)
  local entity = Entity.new({
    id = id, x = x, y = y,
    glyph = spec.glyph, name = spec.name, kind = "monster",
    species = "boss_" .. spec.key, ai = spec.ai,
    hp = spec.hp, maxHp = spec.hp,
    attack = spec.attack, defense = spec.defense,
    speed = spec.speed, range = spec.range or 0,
  })
  entity.ability = spec.ability
  entity.summonSpecies = spec.summonSpecies
  entity.cooldown = 0
  entity.isBoss = true
  entity.bossKey = spec.key
  entity.enraged = false
  entity.awareness = "hunting"
  return entity
end

function Bosses.xpFor(entity)
  local spec = Bosses.byKey[entity.bossKey]
  return spec and spec.xp or 20
end

function Bosses.tryEnrage(monster)
  if not monster.isBoss or monster.enraged or not monster:isAlive() then return nil end
  local spec = Bosses.byKey[monster.bossKey]
  if not spec then return nil end
  if monster.hp > monster.maxHp * spec.enrageAt then return nil end
  monster.enraged = true
  monster.attack = monster.attack + spec.enrageAttack
  monster.baseAttack = monster.baseAttack + spec.enrageAttack
  monster.speed = monster.speed + spec.enrageSpeed
  monster.hp = math.min(monster.maxHp, monster.hp + spec.enrageHeal)
  return string.format("%s flies into a bloodied rage", monster.name)
end

function Bosses.lootFor(entity)
  local spec = Bosses.byKey[entity.bossKey]
  if not spec then return nil end
  return Artifacts.create(spec.lootKey)
end

return Bosses
