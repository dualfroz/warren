local Monsters = require("monsters")
local Stealth = require("stealth")

local Nemesis = {}

Nemesis.CHANCE_NUMERATOR = 1
Nemesis.CHANCE_DENOMINATOR = 5

Nemesis.MAX_GRUDGE = 5
Nemesis.HP_BONUS_PER_GRUDGE = 4
Nemesis.ATTACK_BONUS_PER_GRUDGE = 1

Nemesis.HEAL_FRACTION_PER_FOLLOW = 0.2

Nemesis.EPITHETS = {
  "the Wounded", "the Relentless", "the Scarred", "the Undying", "the Dreaded",
}

Nemesis.ELIGIBLE_AI = { chase = true, pack = true, ranged = true, erratic = true, tunnel = true }

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

function Nemesis.beginFrom(monster)
  return {
    species = monster.species,
    grudge = 1,
    hpFraction = monster.hp / monster.maxHp,
  }
end

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

function Nemesis.xpBonus(grudge)
  return 10 + grudge * 5
end

function Nemesis.bountyGold(grudge)
  return 10 * grudge
end

function Nemesis.nameFor(baseName, grudge)
  local index = math.min(grudge, #Nemesis.EPITHETS)
  return baseName .. ", " .. Nemesis.EPITHETS[index]
end

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
