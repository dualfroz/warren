-- A cross-floor hunter. Every other hostile in the bestiary is confined to
-- the one floor builder.lua drops it on (level.lua's own header: "revisiting
-- one restores its exact state, dead monsters and all") - a nemesis is the
-- single exception. Any ordinary monster actually hunting the player the
-- moment they take a stairwell has a chance to follow them through it
-- instead of being left behind; from then on it keeps following, growing
-- stronger each trip, until the player either kills it or dies first.
--
-- Unlike elites.lua's affixed variant (rolled stronger the instant builder.lua
-- places it) or bosses.lua's fixed per-floor set piece, a nemesis is born
-- mid-run from a plain wild monster and its escalation is entirely
-- player-earned: it does not exist at all until a hunt actually happens, and
-- it only ever grows because the player failed to finish it off before
-- reaching the stairs. Bosses, mimics, graves, elites and the shopkeeper are
-- all excluded from ever becoming one - each already has its own dedicated
-- escalation path, and letting them double up would just be two systems
-- fighting over the same monster.

local Monsters = require("monsters")
local Stealth = require("stealth")

local Nemesis = {}

-- Odds a hunting monster actually gives chase down the stairs, rolled once
-- per descent (Game:nemesisTryEmerge) only while no nemesis is following yet.
Nemesis.CHANCE_NUMERATOR = 1
Nemesis.CHANCE_DENOMINATOR = 5

Nemesis.MAX_GRUDGE = 5
Nemesis.HP_BONUS_PER_GRUDGE = 4
Nemesis.ATTACK_BONUS_PER_GRUDGE = 1

-- How much of its lost hp a nemesis recovers between the floor it last fought
-- on and the one it just followed the player onto - capped at full, so a
-- nemesis engaged over and over never shows up weaker than this floor alone
-- would explain, but also never becomes unkillable simply by being ignored.
Nemesis.HEAL_FRACTION_PER_FOLLOW = 0.2

-- One epithet per grudge tier, read by index and clamped to the last entry
-- once grudge outgrows the list - the name keeps escalating in flavour even
-- after Nemesis.MAX_GRUDGE stops raising its stats any further.
Nemesis.EPITHETS = {
  "the Wounded", "the Relentless", "the Scarred", "the Undying", "the Dreaded",
}

-- ai tags eligible to actually give chase: a permanent "flee" species (the
-- cave wretch, the goblin shaman, the necromancer) breaks off the instant it
-- is adjacent so it would never follow anyone down a stairwell, and the
-- shopkeeper's "vend" idles unless provoked into a plain chase of its own -
-- by then it is already just a chaser under a different tag, still excluded
-- here because Nemesis.isEligible also checks awareness below.
Nemesis.ELIGIBLE_AI = { chase = true, pack = true, ranged = true, erratic = true, tunnel = true }

-- Whether `monster` could give chase this descent: alive, a plain hostile
-- under its own self-directed AI, already actively hunting the player (not
-- dormant, not searching, not merely wandering into the stairwell by
-- coincidence), and not already spoken for by another escalation system.
function Nemesis.isEligible(monster)
  return monster:isAlive()
    and monster.kind == "monster"
    and Nemesis.ELIGIBLE_AI[monster.ai] == true
    and monster.awareness == Stealth.HUNTING
    and not monster.isBoss
    and not monster.mimic
    and not monster.grave
    and not monster.elite
    and not monster.nemesis
end

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- The eligible hunter standing closest to the player, ties broken by
-- level.entities order - deterministic without spending any rng draw of its
-- own, since only whether a nemesis emerges at all needs to be a coin flip.
function Nemesis.pickHunter(level, player)
  local best, bestDist
  for _, monster in ipairs(level.entities) do
    if Nemesis.isEligible(monster) then
      local dist = chebyshev(monster.x, monster.y, player.x, player.y)
      if not best or dist < bestDist then
        best, bestDist = monster, dist
      end
    end
  end
  return best
end

-- The persistent descriptor Game keeps between floors (see game.nemesis) -
-- not a live entity, just enough to rebuild one, exactly like graves.lua
-- stores a fallen player's own remnants instead of keeping a live shade
-- around between runs.
function Nemesis.beginFrom(monster)
  return {
    species = monster.species,
    grudge = 1,
    hpFraction = monster.hp / monster.maxHp,
  }
end

-- Called every time the nemesis follows the player through a stairwell
-- without having been killed first: its grudge climbs (capped) and it stews
-- back toward full health (also capped), so each escape makes the next
-- encounter both tougher and a little less finished business than before.
function Nemesis.escalate(pursuit)
  pursuit.grudge = math.min(Nemesis.MAX_GRUDGE, pursuit.grudge + 1)
  pursuit.hpFraction = math.min(1, pursuit.hpFraction + Nemesis.HEAL_FRACTION_PER_FOLLOW)
  return pursuit
end

function Nemesis.bonusHp(grudge)
  return grudge * Nemesis.HP_BONUS_PER_GRUDGE
end

function Nemesis.bonusAttack(grudge)
  return grudge * Nemesis.ATTACK_BONUS_PER_GRUDGE
end

-- Flat xp on top of the species' own plain reward (Monsters.xpFor already
-- applies, since Nemesis.spawn stamps a real species key onto the entity) -
-- mirrors elites.lua's xpBonus riding on top of the same base reward.
function Nemesis.xpBonus(grudge)
  return 10 + grudge * 5
end

-- Gold the nemesis's hoard finally pays out once it is actually put down,
-- credited alongside (not instead of) the ordinary awardKill flow.
function Nemesis.bountyGold(grudge)
  return 10 * grudge
end

function Nemesis.nameFor(baseName, grudge)
  local index = math.min(grudge, #Nemesis.EPITHETS)
  return baseName .. ", " .. Nemesis.EPITHETS[index]
end

-- Rebuilds a live entity from `pursuit` at (x, y) on the floor just reached,
-- depth-scaled exactly like any other freshly created monster of the same
-- species plus its own escalated bonuses. hpFraction survives the trip so a
-- nemesis last seen half-dead still shows up half-dead here, healed only by
-- however much Nemesis.escalate already restored between floors.
function Nemesis.spawn(pursuit, id, x, y, depth)
  local spec = Monsters.byKey[pursuit.species]
  local entity = Monsters.create(spec, id, x, y, depth)
  entity.maxHp = entity.maxHp + Nemesis.bonusHp(pursuit.grudge)
  entity.hp = math.max(1, math.floor(entity.maxHp * pursuit.hpFraction))
  entity.attack = entity.attack + Nemesis.bonusAttack(pursuit.grudge)
  entity.nemesis = true
  entity.nemesisGrudge = pursuit.grudge
  entity.name = Nemesis.nameFor(spec.name, pursuit.grudge)
  return entity
end

return Nemesis
