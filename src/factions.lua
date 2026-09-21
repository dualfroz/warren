local Factions = {}

Factions.MERCHANT = "merchant"
Factions.GOBLINOID = "goblinoid"
Factions.VERMIN = "vermin"
Factions.ORCISH = "orcish"
Factions.UNDEAD = "undead"
Factions.BEAST = "beast"
Factions.CULT = "cult"
Factions.DRAKE = "drake"
Factions.BANDIT = "bandit"

Factions.neutralFactions = { [Factions.GOBLINOID] = true }

Factions.RIVALRIES = {
  { Factions.GOBLINOID, Factions.ORCISH },
  { Factions.BANDIT, Factions.MERCHANT },
  { Factions.VERMIN, Factions.BEAST },
}

function Factions.areRivals(factionA, factionB)
  if not factionA or not factionB or factionA == factionB then return false end
  for _, pair in ipairs(Factions.RIVALRIES) do
    if (pair[1] == factionA and pair[2] == factionB) or (pair[1] == factionB and pair[2] == factionA) then
      return true
    end
  end
  return false
end

local HOSTILE_MAX = -30
local UNFRIENDLY_MAX = -10
local FRIENDLY_MIN = 25
local HONORED_MIN = 60

local PRICE_MULTIPLIER = {
  hostile = 1.5, unfriendly = 1.15, neutral = 1.0, friendly = 0.85, honored = 0.65,
}

local KILL_PENALTY = 5
local BOSS_KILL_PENALTY = 15
local BASE_APPEASE_COST = 20
local APPEASE_GAIN = 15

function Factions.reputationFor(player, faction)
  return (player.reputation and player.reputation[faction]) or 0
end

function Factions.tier(rep)
  if rep <= HOSTILE_MAX then return "hostile" end
  if rep <= UNFRIENDLY_MAX then return "unfriendly" end
  if rep >= HONORED_MIN then return "honored" end
  if rep >= FRIENDLY_MIN then return "friendly" end
  return "neutral"
end

function Factions.adjust(player, faction, delta)
  player.reputation = player.reputation or {}
  local updated = Factions.reputationFor(player, faction) + delta
  if updated > 100 then updated = 100 end
  if updated < -100 then updated = -100 end
  player.reputation[faction] = updated
  return updated
end

function Factions.registerKill(player, target)
  if not target.faction then return end
  Factions.adjust(player, target.faction, target.isBoss and -BOSS_KILL_PENALTY or -KILL_PENALTY)
end

function Factions.isWary(player, monster)
  local faction = monster.faction
  if not (faction and Factions.neutralFactions[faction]) then return false end
  if monster.provoked then return false end
  return Factions.tier(Factions.reputationFor(player, faction)) ~= "hostile"
end

function Factions.priceMultiplier(player, faction)
  return PRICE_MULTIPLIER[Factions.tier(Factions.reputationFor(player, faction))]
end

function Factions.appeaseCost(player, faction)
  return BASE_APPEASE_COST + math.max(0, -Factions.reputationFor(player, faction)) * 2
end

function Factions.appease(player, faction)
  if Factions.reputationFor(player, faction) >= 100 then return false, 0 end
  local cost = Factions.appeaseCost(player, faction)
  if player.gold < cost then return false, cost end
  player.gold = player.gold - cost
  Factions.adjust(player, faction, APPEASE_GAIN)
  return true, cost
end

return Factions
