-- Elite monsters: rare, affixed variants of the ordinary bestiary. Builder
-- rolls promotion once a floor's entities are already fully placed (appended
-- dead last in Builder.build, after every other placement - artifacts, the
-- boss, the quest board - so it can never perturb an earlier system's rng
-- sequence, exactly like those do for their own rolls). An elite still rides
-- the same ai.lua/abilities.lua dispatch and scheduler as any other creature;
-- only its stats, its name, and the on-hit/on-death/lifesteal hooks Game
-- wires in separately set it apart from a plain spawn of the same species.
-- A floor deep enough for a second affix ("champion") draws it from the
-- remaining pool, so a champion never doubles up on the same one.

local Resistances = require("resistances")

local Elites = {}

Elites.MIN_DEPTH = 3
Elites.CHAMPION_DEPTH = 7

Elites.affixes = {
  { key = "brutal",       name = "brutal",       hpMult = 1.2, attack = 3 },
  { key = "armored",      name = "armored",      hpMult = 1.3, defense = 3 },
  { key = "swift",        name = "swift",        speed = 30 },
  { key = "regenerating", name = "regenerating", regen = 3 },
  { key = "warded",       name = "warded",       resist = Resistances.RESIST },
  { key = "vampiric",     name = "vampiric",     lifesteal = 0.5 },
  { key = "chilling",     name = "chilling",     onHit = { status = "slow", duration = 3, potency = 1 } },
  { key = "volatile",     name = "volatile",     onDeathDamage = 8, onDeathType = Resistances.FIRE },
}

Elites.byKey = {}
for _, affix in ipairs(Elites.affixes) do
  Elites.byKey[affix.key] = affix
end

-- Elemental types a "warded" roll can pick from - physical is excluded since
-- every hit already respects the plain attack/defense floor in combat.lua.
local RESISTABLE = {
  Resistances.FIRE, Resistances.COLD, Resistances.POISON,
  Resistances.LIGHTNING, Resistances.ARCANE,
}

local function applyAffix(entity, affix, rng)
  entity.eliteAffixes[#entity.eliteAffixes + 1] = affix.key
  if affix.hpMult then
    local bonus = math.floor(entity.maxHp * (affix.hpMult - 1))
    entity.maxHp = entity.maxHp + bonus
    entity.hp = entity.hp + bonus
  end
  if affix.attack then
    entity.attack = entity.attack + affix.attack
    entity.baseAttack = entity.baseAttack + affix.attack
  end
  if affix.defense then
    entity.defense = entity.defense + affix.defense
    entity.baseDefense = entity.baseDefense + affix.defense
  end
  if affix.speed then entity.speed = entity.speed + affix.speed end
  if affix.regen then entity.regen = (entity.regen or 0) + affix.regen end
  if affix.resist then
    local element = RESISTABLE[rng:range(1, #RESISTABLE)]
    entity.resist = entity.resist or {}
    if entity.resist[element] ~= Resistances.IMMUNE then
      entity.resist[element] = affix.resist
    end
  end
  entity.name = affix.name .. " " .. entity.name
end

-- Eligible for promotion: a plain bestiary spawn, never a boss (already the
-- rarer, sturdier variant) or the passive shopkeeper.
function Elites.eligible(entity)
  return entity.kind == "monster" and not entity.isBoss and entity.ai ~= "vend"
end

-- Rolled once per eligible monster after a floor's entities are already
-- placed. Mutates `entity` in place; a no-op below Elites.MIN_DEPTH, on an
-- ineligible entity, or when the roll simply misses.
function Elites.maybePromote(rng, entity, depth)
  if depth < Elites.MIN_DEPTH or not Elites.eligible(entity) then return end
  if not rng:chance(1, 6) then return end
  entity.elite = true
  entity.eliteAffixes = {}
  local pool = {}
  for i, affix in ipairs(Elites.affixes) do pool[i] = affix end
  local rolls = 1
  if depth >= Elites.CHAMPION_DEPTH and rng:chance(1, 3) then rolls = 2 end
  for _ = 1, rolls do
    if #pool == 0 then break end
    local idx = rng:range(1, #pool)
    applyAffix(entity, pool[idx], rng)
    table.remove(pool, idx)
  end
  entity.eliteTier = #entity.eliteAffixes >= 2 and "champion" or "elite"
end

-- The first volatile affix on `entity`, if any - the death burst
-- Game:awardKill triggers right after Abilities.onDeath.
function Elites.explosionFor(entity)
  if not entity.eliteAffixes then return nil end
  for _, key in ipairs(entity.eliteAffixes) do
    local affix = Elites.byKey[key]
    if affix and affix.onDeathDamage then return affix end
  end
  return nil
end

-- The status rider (if any) a hit landed by `entity` should apply to its
-- victim - same shape as a weapon affix's onHit (see affixes.lua), so Game
-- can hand it straight to Status.apply.
function Elites.onHitRider(entity)
  if not entity.eliteAffixes then return nil end
  for _, key in ipairs(entity.eliteAffixes) do
    local affix = Elites.byKey[key]
    if affix and affix.onHit then return affix.onHit end
  end
  return nil
end

-- Fraction of dealt damage `entity` heals back on a hit it lands, summed
-- across its affixes (never more than one vampiric roll in practice).
function Elites.lifestealFraction(entity)
  if not entity.eliteAffixes then return 0 end
  local total = 0
  for _, key in ipairs(entity.eliteAffixes) do
    local affix = Elites.byKey[key]
    if affix and affix.lifesteal then total = total + affix.lifesteal end
  end
  return total
end

-- Bonus xp a felled elite is worth on top of its plain species reward: half
-- again for a single-affix elite, a full second helping for a champion.
function Elites.xpBonus(entity, baseXp)
  if not entity.elite then return 0 end
  local mult = entity.eliteTier == "champion" and 1.0 or 0.5
  return math.floor(baseXp * mult)
end

-- Fired from Game:awardKill right after Abilities.onDeath: a volatile
-- elite's corpse bursts, scorching the player and any companion or monster
-- adjacent to it (itself excluded) for its cataloged damage and type.
function Elites.onDeath(game, monster)
  local affix = Elites.explosionFor(monster)
  if not affix then return nil end
  local hit = {}
  local targets = { game.player }
  for _, other in ipairs(game:currentEntities()) do targets[#targets + 1] = other end
  for _, victim in ipairs(targets) do
    if victim ~= monster and victim:isAlive()
      and math.abs(victim.x - monster.x) <= 1 and math.abs(victim.y - monster.y) <= 1 then
      local dealt = Resistances.apply(victim, affix.onDeathDamage, affix.onDeathType)
      if dealt > 0 then
        victim.hp = victim.hp - dealt
        hit[#hit + 1] = string.format("%s for %d", victim.name, dealt)
      end
    end
  end
  if #hit == 0 then return nil end
  return string.format("%s bursts, scorching %s", monster.name, table.concat(hit, ", "))
end

return Elites
