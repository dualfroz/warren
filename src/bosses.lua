-- Named floor bosses: rare, sturdier variants of the bestiary that phase-shift
-- once bloodied ("enrage") and always drop a superior, boss-exclusive
-- artifact on death. A boss is otherwise a plain monster entity - it rides
-- the same scheduler, ai.lua behaviour and abilities.lua dispatch as every
-- other creature - so this module only adds what is genuinely new: the
-- catalog, the enrage phase check, and the guaranteed drop.
--
-- A boss's second, harder-won phase - the brace-then-unleash cataclysm once
-- it is battered all the way down to desperateAt - lives in phases.lua
-- instead of here, since unlike enrage it spends whole turns and needs its
-- own two-state machine; this module only supplies the catalog numbers
-- (desperateAt, desperateDefenseBonus, novaDamage, novaRadius) it reads.
--
-- Builder places at most one per floor from depth 6 on, its rarity roll
-- appended after every other placement (artifacts included) so it can never
-- perturb an earlier system's rng sequence, exactly like artifacts.lua does
-- for its own roll. Gating at depth 6+ also keeps bosses off every floor the
-- fixed-maxDepth win-condition tests generate (those use maxDepth <= 3).

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

-- Boss species eligible at a depth, in registry order, mirroring
-- Monsters.forDepth so builder.lua can roll among them the same way.
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
  -- Always alert: sneaking up on a named boss is not part of the design
  -- (see stealth.lua's header for how this differs from a wild monster).
  entity.awareness = "hunting"
  return entity
end

-- Xp reward for felling a boss, looked up by the bossKey stamped onto it at
-- creation. Falls back to a flat amount for a boss entity missing one, which
-- should not happen outside of a malformed save.
function Bosses.xpFor(entity)
  local spec = Bosses.byKey[entity.bossKey]
  return spec and spec.xp or 20
end

-- Checked at the start of a boss's own turn, after status ticks, hazards and
-- regen but before its ability or plain ai runs: once bloodied past its
-- enrageAt threshold it permanently gains attack and speed and takes a
-- one-time heal, exactly once for the rest of the fight. Mirrors the direct
-- stat-field mutation classes.lua uses for a permanent delta, rather than a
-- status.lua effect, since this should never expire or be cleansed.
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

-- The guaranteed superior artifact a boss drops on death, dropped straight
-- onto the floor at its corpse's feet by Game:awardKill rather than rolled
-- into the ordinary loot table builder.lua scatters at level generation.
function Bosses.lootFor(entity)
  local spec = Bosses.byKey[entity.bossKey]
  if not spec then return nil end
  return Artifacts.create(spec.lootKey)
end

return Bosses
