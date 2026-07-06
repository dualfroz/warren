-- Class skill trees. Each class (classes.lua) unlocks three skills, one
-- learned per skill point (granted on level-up, see progression.lua): an
-- active that spends the player's turn like a spell, and passives that fold
-- straight into combat/spells/ranged. Passive checks all guard on
-- `entity.skills` being present, so calling any of these on a monster (which
-- never has the field) is always a safe no-op - the same shape status.lua
-- uses for its own modifiers.

local Los = require("los")
local Items = require("items")
local Resistances = require("resistances")

local Skills = {}

Skills.active = {
  cleave      = { name = "cleave",       class = "fighter", reqLevel = 1, cooldown = 3 },
  secondWind  = { name = "second wind",  class = "fighter", reqLevel = 3, cooldown = 12 },
  poisonBlade = { name = "poison blade", class = "rogue",   reqLevel = 5, cooldown = 6 },
  meditate    = { name = "meditate",     class = "mage",    reqLevel = 3, cooldown = 0 },
  multishot   = { name = "multishot",    class = "ranger",  reqLevel = 1, cooldown = 5 },
}

Skills.passive = {
  berserk    = { name = "berserk",    class = "fighter", reqLevel = 5 },
  backstab   = { name = "backstab",   class = "rogue",   reqLevel = 1 },
  evasion    = { name = "evasion",    class = "rogue",   reqLevel = 3 },
  overload   = { name = "overload",   class = "mage",    reqLevel = 1 },
  manaShield = { name = "mana shield", class = "mage",   reqLevel = 5 },
  camouflage = { name = "camouflage", class = "ranger",  reqLevel = 3 },
  trueshot   = { name = "trueshot",   class = "ranger",  reqLevel = 5 },
}

local function defOf(key)
  return Skills.active[key] or Skills.passive[key]
end

-- Every skill key belonging to `classKey`, active and passive alike, in a
-- fixed alphabetical order so autopilot and tests see a stable pick sequence
-- regardless of Lua's unordered `pairs` iteration over the catalogs above.
function Skills.forClass(classKey)
  local list = {}
  for key, def in pairs(Skills.active) do
    if def.class == classKey then list[#list + 1] = key end
  end
  for key, def in pairs(Skills.passive) do
    if def.class == classKey then list[#list + 1] = key end
  end
  table.sort(list)
  return list
end

function Skills.has(entity, key)
  return entity.skills ~= nil and entity.skills[key] == true
end

-- Spends one of the player's skill points to permanently learn `key`.
-- Returns (true, message) on success or (false, message) with no state
-- changed - no point spent - on failure.
function Skills.learn(player, key)
  local def = defOf(key)
  if not def then return false, "there is no such skill" end
  if player.class ~= def.class then return false, "that skill is not part of your training" end
  if player.level < def.reqLevel then return false, "you are not experienced enough for that yet" end
  if Skills.has(player, key) then return false, "you already know that" end
  if (player.skillPoints or 0) <= 0 then return false, "you have no skill points to spend" end
  player.skillPoints = player.skillPoints - 1
  player.skills[key] = true
  return true, "you learn " .. def.name
end

function Skills.tickCooldowns(player)
  for key, turns in pairs(player.skillCooldowns) do
    if turns > 0 then player.skillCooldowns[key] = turns - 1 end
  end
end

-- Passive hooks. Each is a small, pure function of entity/game state so
-- combat.lua, spells.lua, ranged.lua and game.lua can call straight into it
-- without either side needing to know about the other's active-skill logic.

-- Rogue: a target still at full hp has not yet reacted to the fight, so the
-- first strike lands twice as hard.
function Skills.meleeDamageMultiplier(attacker, defender)
  if Skills.has(attacker, "backstab") and defender.hp == defender.maxHp then
    return 2
  end
  return 1
end

-- Rogue: a trained dodge fully negates an incoming melee hit one time in
-- four. Checks `has` before touching the rng so an unlearned/unlearnable
-- defender never perturbs the rng stream.
function Skills.evades(game, defender)
  if not Skills.has(defender, "evasion") then return false end
  return game.rng:chance(1, 4)
end

-- Fighter: a flat attack surge once hp drops to a third or less of max.
function Skills.attackBonus(entity)
  if entity.skills and entity.skills.berserk and entity.hp <= entity.maxHp * 0.34 then
    return 4
  end
  return 0
end

-- Mage: an actively maintained ward that lapses once the pool it draws on
-- runs low.
function Skills.defenseBonus(entity)
  if entity.skills and entity.skills.manaShield and (entity.mana or 0) >= 5 then
    return 3
  end
  return 0
end

-- Mage: damaging spells hit a quarter harder.
function Skills.spellDamageMultiplier(caster)
  if Skills.has(caster, "overload") then return 1.25 end
  return 1
end

-- Ranger: a steadier draw adds flat damage to every loosed arrow.
function Skills.rangedDamageBonus(entity)
  if Skills.has(entity, "trueshot") then return 3 end
  return 0
end

-- Ranger: blends into the dark. Only ever shrinks a monster's detection
-- range on a lightless floor - camouflage on a lit one would just be standing
-- in the open.
function Skills.detectionPenalty(player, dark)
  if dark and Skills.has(player, "camouflage") then return 3 end
  return 0
end

-- Active skills. Each takes the live `game` object (duck-typed, mirroring
-- spells.lua's Spells.cast) so it can log, award kills and touch level state
-- without skills.lua ever requiring the game module back.

local EIGHT_DIRS = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

local function statAttack(entity)
  return entity.effectiveAttack and entity:effectiveAttack() or entity.attack
end

local function statDefense(entity)
  return entity.effectiveDefense and entity:effectiveDefense() or entity.defense
end

