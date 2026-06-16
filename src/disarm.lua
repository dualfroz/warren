-- Passive trap sense and the deliberate act of disarming what it finds.
-- Every trap already carries a hidden/revealed pair (level.traps entries -
-- see level.lua and game.lua's Game:springTrap, which flips a trap's
-- `revealed` the instant it is triggered, whether by a footstep or a failed
-- disarm below). This module adds a third state in between the two,
-- `detected`: noticed but not yet sprung. Detection is a passive roll
-- against every still-hidden trap within a step of the player, rolled once
-- per player turn from Game:endPlayerTurn - once per round rather than once
-- per actor, exactly like hazards.step and events.step already advance the
-- world. Disarming a detected trap is the deliberate, risky counterpart:
-- succeed and it is gone for good, plus a handful of essence for the
-- salvaged parts; fail and it springs on the disarmer exactly as if they
-- had blundered onto it outright, through the very same Game:springTrap
-- every other trigger already shares.

local Disarm = {}

Disarm.DETECT_NUMERATOR = 1
Disarm.DETECT_DENOMINATOR = 4

Disarm.DISARM_BASE_NUMERATOR = 3
Disarm.DISARM_BASE_DENOMINATOR = 5
Disarm.LEVEL_BONUS_DIVISOR = 4

Disarm.SALVAGE_MIN = 3
Disarm.SALVAGE_MAX = 6

-- Sweeps every trap within Chebyshev distance 1 of (px, py) - the same
-- adjacency a monster's melee reach and a shrine's own footprint are judged
-- by elsewhere - that is neither already detected nor already sprung, and
-- rolls each independently. Returns the traps newly detected this call (in
-- level.traps order), so a caller can report exactly what was noticed.
function Disarm.sweep(level, rng, px, py)
  local found = {}
  for _, trap in ipairs(level.traps) do
    if not trap.detected and not trap.revealed
      and math.max(math.abs(trap.x - px), math.abs(trap.y - py)) <= 1
      and rng:chance(Disarm.DETECT_NUMERATOR, Disarm.DETECT_DENOMINATOR) then
      trap.detected = true
      found[#found + 1] = trap
    end
  end
  return found
end

-- Odds of successfully disarming a detected trap: a flat base that climbs
-- slightly with player level, capped a point shy of the denominator so
-- disarming never becomes a sure thing no matter how experienced the
-- player gets.
function Disarm.oddsFor(player)
  local numerator = Disarm.DISARM_BASE_NUMERATOR + player.level // Disarm.LEVEL_BONUS_DIVISOR
  if numerator > Disarm.DISARM_BASE_DENOMINATOR - 1 then
    numerator = Disarm.DISARM_BASE_DENOMINATOR - 1
  end
  return numerator, Disarm.DISARM_BASE_DENOMINATOR
end

-- Resolves one disarm attempt against `trap`, already known to `game`'s
-- player (see Game:disarmTrap, which enforces that it was actually
-- detected first). On success the trap is spliced out of level.traps for
-- good and its salvage is credited as essence; on failure it springs on the
-- player through Game:springTrap, the identical consequence a careless
-- footstep would have caused. Returns (true, line) or (false, nil) - a
-- failure logs nothing of its own since springTrap already does.
function Disarm.attempt(game, trap)
  local numerator, denominator = Disarm.oddsFor(game.player)
  if not game.rng:chance(numerator, denominator) then
    game:springTrap(trap, game.player)
    return false, nil
  end
  for i, candidate in ipairs(game.level.traps) do
    if candidate == trap then
      table.remove(game.level.traps, i)
      break
    end
  end
  local salvage = game.rng:range(Disarm.SALVAGE_MIN, Disarm.SALVAGE_MAX)
  game.player.essence = game.player.essence + salvage
  return true, string.format("you carefully disarm the trap, salvaging %d essence", salvage)
end

return Disarm
