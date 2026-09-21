local Streaks = {}

Streaks.HISTORY_CAP = 50

function Streaks.new()
  return {}
end

function Streaks.record(history, won)
  history[#history + 1] = won
  while #history > Streaks.HISTORY_CAP do
    table.remove(history, 1)
  end
end

function Streaks.current(history)
  if #history == 0 then return 0, nil end
  local outcome = history[#history]
  local length = 0
  for i = #history, 1, -1 do
    if history[i] ~= outcome then break end
    length = length + 1
  end
  return length, outcome
end

function Streaks.bestWinStreak(history)
  local best, running = 0, 0
  for _, won in ipairs(history) do
    if won then
      running = running + 1
      if running > best then best = running end
    else
      running = 0
    end
  end
  return best
end

return Streaks
