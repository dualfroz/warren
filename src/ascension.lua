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

function Ascension.isUnlocked(meta, key)
  local def = Ascension.byKey[key]
  if not def then return false end
  if not meta then return def.requiresDepth == 0 and def.requiresWins == 0 end
  return meta.bestDepth >= def.requiresDepth and meta.wins >= def.requiresWins
end

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

function Ascension.renownBonusPercent(active)
  local percent = 0
  for _, key in ipairs(active or {}) do
    local def = Ascension.byKey[key]
    if def then percent = percent + def.renownBonus end
  end
  return percent
end

function Ascension.applyToPlayer(active, player)
  for _, key in ipairs(active or {}) do
    local def = Ascension.byKey[key]
    if def and def.applyToPlayer then def.applyToPlayer(player) end
  end
end

return Ascension
