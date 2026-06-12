-- Aggregate, read-only statistics over meta.lua's own cross-run history:
-- how often a body of runs actually won, which class shows up most among
-- them, and where a fresh score would land against that history - three
-- questions renown and achievements never answer on their own, since both
-- only ever look at the one run in front of them, never the shape of every
-- run that came before it.

local Analytics = {}

-- Fraction of recorded runs that ended in victory. 0 for a state that has
-- not recorded any runs yet rather than dividing by zero.
function Analytics.winRate(meta)
  if meta.totalRuns == 0 then return 0 end
  return meta.wins / meta.totalRuns
end

-- Mean score across every leaderboard entry (see leaderboard.lua), 0 for an
-- empty board.
function Analytics.averageScore(board)
  if #board == 0 then return 0 end
  local total = 0
  for _, entry in ipairs(board) do total = total + entry.score end
  return total / #board
end

-- The className appearing most often on `board`, ties broken toward
-- whichever class was seen first on the board - so the answer only ever
-- depends on the board's own entry order, never on however pairs() happens
-- to walk a count table. nil for an empty board.
function Analytics.favoriteClass(board)
  local counts, order = {}, {}
  for _, entry in ipairs(board) do
    if not counts[entry.className] then order[#order + 1] = entry.className end
    counts[entry.className] = (counts[entry.className] or 0) + 1
  end
  local best, bestCount = nil, 0
  for _, className in ipairs(order) do
    if counts[className] > bestCount then
      best, bestCount = className, counts[className]
    end
  end
  return best
end

-- How many of `board`'s entries `score` would actually outrank, as a
-- fraction from 0 (worse than or tied with everything) to 1 (better than
-- everything). An empty board always answers 1 - there is nothing left to
-- beat, so nothing holds the score back.
function Analytics.percentile(board, score)
  if #board == 0 then return 1 end
  local beaten = 0
  for _, entry in ipairs(board) do
    if score > entry.score then beaten = beaten + 1 end
  end
  return beaten / #board
end

return Analytics
