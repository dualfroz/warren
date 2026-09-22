local Bosses = require("bosses")
local Text = require("text")

local Phases = {}

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function novaTargets(game, monster, radius)
  local targets = {}
  if chebyshev(game.player.x, game.player.y, monster.x, monster.y) <= radius then
    targets[#targets + 1] = game.player
  end
  for _, other in ipairs(game.level.entities) do
    if other:isAlive() and (other.kind == "companion" or other.kind == "hireling" or other.kind == "thrall")
      and chebyshev(other.x, other.y, monster.x, monster.y) <= radius then
      targets[#targets + 1] = other
    end
  end
  return targets
end

function Phases.tick(game, monster)
  if not monster.isBoss or not monster:isAlive() then return nil, false end
  local spec = Bosses.byKey[monster.bossKey]
  if not spec or not spec.desperateAt then return nil, false end

  if monster.channeling then
    monster.channeling = false
    monster.novaSpent = true
    monster.defense = monster.defense - spec.desperateDefenseBonus
    monster.baseDefense = monster.baseDefense - spec.desperateDefenseBonus
    local hit = {}
    for _, victim in ipairs(novaTargets(game, monster, spec.novaRadius)) do
      victim.hp = victim.hp - spec.novaDamage
      hit[#hit + 1] = victim == game.player and "you" or victim.name
    end
    if #hit == 0 then
      return string.format("%s unleashes a cataclysm that finds no one in range", monster.name), true
    end
    return string.format("%s unleashes a cataclysm on %s for %d", monster.name,
      Text.joinNaturally(hit), spec.novaDamage), true
  end

  if monster.novaSpent or monster.desperate then return nil, false end
  if monster.hp > monster.maxHp * spec.desperateAt then return nil, false end

  monster.desperate = true
  monster.channeling = true
  monster.defense = monster.defense + spec.desperateDefenseBonus
  monster.baseDefense = monster.baseDefense + spec.desperateDefenseBonus
  return string.format("%s reels and begins channeling a desperate cataclysm", monster.name), true
end

return Phases
