-- Faction standing. Every hostile species in the bestiary carries a `faction`
-- tag; the player carries a `reputation` table scoring how each faction feels
-- about them, starting neutral (an absent entry reads as 0). Killing a
-- faction's members sours that score; paying tribute or turning in a bounty
-- sweetens it. Reputation then feeds back into the world two ways: a
-- tribal faction tagged "neutral" (see neutralFactions) leaves its members
-- passively unprovoked until the player either strikes first or has enraged
-- the whole tribe by other means, and the merchant guild's prices rise or
-- fall with how the player stands with it.

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

-- Factions whose rank-and-file stay passive - see Factions.isWary - unless
-- provoked in melee/at range or already hated into open hostility.
Factions.neutralFactions = { [Factions.GOBLINOID] = true }

-- Faction pairs that loathe each other regardless of the player: two
-- monsters from an unrelated pair here fight on sight if they ever share a
-- floor (see infighting.lua), no discord spell required. Listed once per
-- pair; Factions.areRivals checks both directions. Deliberately excludes any
-- faction pairing with a summon relationship (CULT raises UNDEAD minions)
-- so a caster is never made to loathe its own summoned brood.
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

-- The named tier a raw reputation score falls into, from most soured to most
-- warm. Ties resolve toward the harsher tier so a score sitting exactly on a
-- boundary reads as the tier it just reached rather than the one it left.
function Factions.tier(rep)
  if rep <= HOSTILE_MAX then return "hostile" end
  if rep <= UNFRIENDLY_MAX then return "unfriendly" end
  if rep >= HONORED_MIN then return "honored" end
  if rep >= FRIENDLY_MIN then return "friendly" end
  return "neutral"
end

-- Nudges `faction`'s standing by `delta`, clamped to +-100, creating the
-- player's reputation table on first use.
function Factions.adjust(player, faction, delta)
  player.reputation = player.reputation or {}
  local updated = Factions.reputationFor(player, faction) + delta
  if updated > 100 then updated = 100 end
  if updated < -100 then updated = -100 end
  player.reputation[faction] = updated
  return updated
end

-- Called once per monster a player action fells: unfactioned kills (traps,
-- hazards with no owning species) are simply ignored.
function Factions.registerKill(player, target)
  if not target.faction then return end
  Factions.adjust(player, target.faction, target.isBoss and -BOSS_KILL_PENALTY or -KILL_PENALTY)
end

-- Whether `faction`'s members currently hold back from attacking on sight.
-- Non-tribal factions are never wary; a tribal one stops being wary the
-- instant the whole faction's standing curdles into open hostility.
function Factions.isWary(player, monster)
  local faction = monster.faction
  if not (faction and Factions.neutralFactions[faction]) then return false end
  if monster.provoked then return false end
  return Factions.tier(Factions.reputationFor(player, faction)) ~= "hostile"
end

function Factions.priceMultiplier(player, faction)
  return PRICE_MULTIPLIER[Factions.tier(Factions.reputationFor(player, faction))]
end

-- Gold cost of the next tribute to `faction`: a flat base that climbs the
-- deeper the grudge already runs, so digging out of "hostile" costs more
-- than smoothing over a merely "unfriendly" one.
function Factions.appeaseCost(player, faction)
  return BASE_APPEASE_COST + math.max(0, -Factions.reputationFor(player, faction)) * 2
end

-- Spends gold to buy `faction`'s standing up by a fixed amount. Returns
-- (true, costPaid) on success; (false, cost) when the player cannot afford
-- it; (false, 0) when the faction is already maxed out and has nothing left
-- to sell.
function Factions.appease(player, faction)
  if Factions.reputationFor(player, faction) >= 100 then return false, 0 end
  local cost = Factions.appeaseCost(player, faction)
  if player.gold < cost then return false, cost end
  player.gold = player.gold - cost
  Factions.adjust(player, faction, APPEASE_GAIN)
  return true, cost
end

return Factions
