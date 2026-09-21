local Disarm = {}

Disarm.DETECT_NUMERATOR = 1
Disarm.DETECT_DENOMINATOR = 4

Disarm.DISARM_BASE_NUMERATOR = 3
Disarm.DISARM_BASE_DENOMINATOR = 5
Disarm.LEVEL_BONUS_DIVISOR = 4

Disarm.SALVAGE_MIN = 3
Disarm.SALVAGE_MAX = 6

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

function Disarm.oddsFor(player)
  local numerator = Disarm.DISARM_BASE_NUMERATOR + player.level // Disarm.LEVEL_BONUS_DIVISOR
  if numerator > Disarm.DISARM_BASE_DENOMINATOR - 1 then
    numerator = Disarm.DISARM_BASE_DENOMINATOR - 1
  end
  return numerator, Disarm.DISARM_BASE_DENOMINATOR
end

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
