-- Optional run-wide difficulty mutators a player opts into before a run
-- starts, in exchange for extra renown once it ends: risk taken on purpose,
-- unlike events.lua's mutators which fire and fade on their own mid-run
-- regardless of anyone's choice. A mutator unlocks once meta.lua's own
-- cross-run tallies (best depth, wins) cross its fixed requirement -
-- computed live off those tallies rather than persisted, since both only
-- ever climb, so nothing here needs its own entry in meta.lua's save shape.
--
-- Active mutators for the run in progress live on game.ascension, a plain
-- array of keys in catalog order (see Ascension.resolve), exactly the shape
-- warren.lua's --mutators flag builds. Plain data, so it serializes with no
-- special save-format handling, and every combat/essence/sight hook that
-- reads it (Game:monsterDamageMultiplier, Game:essenceMultiplier,
-- Game:effectiveRadius) stays a pure function of that array alongside
-- whatever level-scoped event Events.lua itself is contributing.

local Ascension = {}

Ascension.MUTATORS = {
  { key = "bloodbound", name = "Bloodbound", desc = "monsters hit 50% harder",
    renownBonus = 15, requiresDepth = 3, requiresWins = 0, damageMultiplier = 1.5 },
  { key = "famine", name = "Famine", desc = "essence income halved",
    renownBonus = 10, requiresDepth = 2, requiresWins = 0, essenceMultiplier = 0.5 },
  { key = "nightblind", name = "Nightblind", desc = "sight radius reduced by 2",
    renownBonus = 10, requiresDepth = 2, requiresWins = 0, sightPenalty = 2 },
  { key = "frail", name = "Frail", desc = "defense halved",
    renownBonus = 12, requiresDepth = 4, requiresWins = 0,
    applyToPlayer = function(player)
      player.baseDefense = player.baseDefense // 2
      player.defense = player.defense // 2
    end },
  { key = "glasscannon", name = "Glass Cannon", desc = "max hp halved, attack doubled",
    renownBonus = 20, requiresDepth = 0, requiresWins = 1,
    applyToPlayer = function(player)
      player.maxHp = math.max(1, player.maxHp // 2)
      player.hp = math.min(player.hp, player.maxHp)
      player.baseAttack = player.baseAttack * 2
      player.attack = player.attack * 2
    end },
}

Ascension.byKey = {}
Ascension.order = {}
for _, def in ipairs(Ascension.MUTATORS) do
  Ascension.byKey[def.key] = def
  Ascension.order[#Ascension.order + 1] = def.key
end

-- A meta-less caller (no --meta flag at all) can still activate whatever
-- costs nothing to unlock; every other mutator needs a persistent meta file
-- to have already banked the depth or win it requires.
function Ascension.isUnlocked(meta, key)
  local def = Ascension.byKey[key]
  if not def then return false end
  if not meta then return def.requiresDepth == 0 and def.requiresWins == 0 end
  return meta.bestDepth >= def.requiresDepth and meta.wins >= def.requiresWins
end

-- Validates a requested list of mutator keys against both the catalog and
-- `meta`'s own unlock state, returned de-duplicated in catalog order rather
-- than whatever order the caller supplied - so two runs activating the same
-- set always see it identically regardless of how --mutators listed them.
-- An unknown or still-locked key is silently dropped rather than failing
-- the whole run over one bad flag.
function Ascension.resolve(meta, requested)
  if not requested or #requested == 0 then return {} end
  local wanted = {}
  for _, key in ipairs(requested) do wanted[key] = true end
  local active = {}
  for _, key in ipairs(Ascension.order) do
    if wanted[key] and Ascension.isUnlocked(meta, key) then
      active[#active + 1] = key
    end
  end
  return active
end

function Ascension.isActive(active, key)
  for _, k in ipairs(active or {}) do
    if k == key then return true end
  end
  return false
end

function Ascension.damageMultiplier(active)
  local mult = 1
  for _, key in ipairs(active or {}) do
    local def = Ascension.byKey[key]
    if def and def.damageMultiplier then mult = mult * def.damageMultiplier end
  end
  return mult
end

function Ascension.essenceMultiplier(active)
  local mult = 1
  for _, key in ipairs(active or {}) do
    local def = Ascension.byKey[key]
    if def and def.essenceMultiplier then mult = mult * def.essenceMultiplier end
  end
  return mult
end

function Ascension.sightPenalty(active)
  local penalty = 0
  for _, key in ipairs(active or {}) do
    local def = Ascension.byKey[key]
    if def and def.sightPenalty then penalty = penalty + def.sightPenalty end
  end
  return penalty
end

-- Renown bonus percentage this active set adds on top of Meta.renownFor's
-- own base score, summed rather than compounded - three 15% mutators add
-- 45%, not a runaway 1.15^3 - so stacking more of them is always a
-- straightforward trade of more risk for more reward.
function Ascension.renownBonusPercent(active)
  local percent = 0
  for _, key in ipairs(active or {}) do
    local def = Ascension.byKey[key]
    if def then percent = percent + def.renownBonus end
  end
  return percent
end

-- Applies every active mutator's one-time player-stat delta, in catalog
-- order. Meant to run once in Game.new, after Meta.applyAll's perks and any
-- class delta, since a mutator is the final, voluntary layer of difficulty
-- stacked on top of whatever build the player already chose.
function Ascension.applyToPlayer(active, player)
  for _, key in ipairs(active or {}) do
    local def = Ascension.byKey[key]
    if def and def.applyToPlayer then def.applyToPlayer(player) end
  end
end

return Ascension
