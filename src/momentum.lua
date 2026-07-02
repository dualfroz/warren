-- A player-only combo meter that rewards sustained melee aggression: every
-- landed melee swing raises the stack by one, up to a hard cap, and each
-- stack adds a flat attack bonus that reads live through
-- Entity:effectiveAttack - the very next swing already hits harder, not
-- just some future one. Taking a hit from a monster's claw, breath or
-- ambush snaps the whole stack back to zero outright - unlike a status
-- effect's timed decay, there is no partial forgiveness, so holding a combo
-- against several foes at once is a far harder rhythm than a lone duel. An
-- evaded attack (see skills.lua) never reaches Combat.attack at all, so it
-- never breaks the stack either - only a blow that actually lands does.
-- Ranged shots, thrown items and environmental damage (traps, poison,
-- lava) neither build nor break it: momentum is specifically a melee-vs-
-- monster reward, not a universal combat buff.

local Momentum = {}

Momentum.MAX_STACKS = 5
Momentum.BONUS_PER_STACK = 1

function Momentum.stacks(entity)
  return entity.combo or 0
end

-- Raises `entity`'s stack by one landed melee hit, capped at MAX_STACKS.
function Momentum.onMeleeHit(entity)
  entity.combo = math.min(Momentum.MAX_STACKS, Momentum.stacks(entity) + 1)
end

-- Snaps the stack back to zero the instant `entity` takes a hit.
function Momentum.onDamaged(entity)
  entity.combo = 0
end

-- The flat attack bonus `entity`'s current stack grants.
function Momentum.attackBonus(entity)
  return Momentum.stacks(entity) * Momentum.BONUS_PER_STACK
end

return Momentum
