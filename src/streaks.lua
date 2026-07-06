-- Win/loss streak tracking over meta.lua's own run history: not "how many
-- wins in total" (Meta.recordRun's own totalRuns/wins tally already answers
-- that) but how many of the *most recent* runs in a row ended the same
-- way - the number that actually swings the instant a lucky or unlucky run
-- lands, unlike a lifetime win rate that a hundred prior runs already numbs.

local Streaks = {}

Streaks.HISTORY_CAP = 50

function Streaks.new()
  return {}
end

-- Appends `won` (a boolean) as the newest entry, trimming the oldest once
-- history grows past Streaks.HISTORY_CAP - a streak only ever needs to look
-- back so far, and an unbounded history would grow meta.lua's save file
-- forever for no further benefit.
function Streaks.record(history, won)
  history[#history + 1] = won
  while #history > Streaks.HISTORY_CAP do
    table.remove(history, 1)
  end
end

-- Length of the run of identical outcomes ending at the most recent entry,
-- and which outcome that is - (0, nil) for an empty history. A single win
-- right after a loss reads as a streak of exactly 1, not 0: the run just
-- recorded is itself part of its own streak.
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

-- The longest run of consecutive wins anywhere in history, not just the one
-- still active - a player's all-time best winning streak survives even
-- after it eventually breaks.
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
