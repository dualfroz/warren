-- A boss's second, harder-won escalation beyond bosses.lua's enrage. Enrage
-- is a single instantaneous stat bump that never costs the boss a turn; a
-- desperation phase is a two-turn state machine that consumes both turns
-- outright once the boss is battered all the way down to its catalog
-- desperateAt threshold:
--   1. brace  - the boss telegraphs for one full turn, a visible defense
--      spike (desperateDefenseBonus) warning the player something is coming
--      without yet hurting anyone.
--   2. unleash - on its very next turn the boss reverts that defense spike
--      and detonates a single cataclysm, dealing novaDamage to the player
--      and to every companion, hireling or thrall still within novaRadius.
-- The cataclysm fires at most once per boss: novaSpent latches permanently
-- the moment it lands, so a fight survived past it settles back into the
-- boss's ordinary ability/ai behaviour (abilities.lua) for good. A boss with
-- no desperateAt in its catalog entry (none outside bosses.lua today) never
-- enters this state machine at all.
--
-- Bracing and unleashing both consume the boss's entire turn - the caller
-- (Game:takeMonsterTurn) must skip Stealth.tick, Abilities.tryAct and
-- Ai.act whenever Phases.tick reports the turn consumed, exactly as it
-- already skips them all under Status.skipsTurn.

local Bosses = require("bosses")

local Phases = {}

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- Everyone the cataclysm can reach: the player when in range, plus every
-- living companion, hireling or thrall within the same radius - the same
-- three-way ally kind the rest of the engine treats as a single "player's
-- own side" (see game.lua's isPlayerAlly, infighting.lua, and the noise/
-- confuse/blind symmetry work across companions.lua/mercenaries.lua/
-- reanimation.lua). A wild monster caught nearby is never a target - a
-- boss's desperate gambit is aimed at the party that cornered it, not at
-- whatever else happens to be on the floor (mirrors Bosses itself only ever
-- threatening the player's side).
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

-- Called once per boss turn, at the same point Bosses.tryEnrage already
-- runs in Game:takeMonsterTurn (after status/hazard/regen, before every
-- other action). Returns (line, consumedTurn); consumedTurn true means the
-- caller must skip everything else this turn, bracing and unleashing both
-- being the entire point of the turn they happen on.
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
      table.concat(hit, ", "), spec.novaDamage), true
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
