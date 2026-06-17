-- Persistent top-N high score table. A run's own numeric score (see
-- morgue.lua's Morgue.score) only matters across runs if something
-- remembers it - this is that memory, carried inside meta.lua's own save
-- file exactly like renown and achievements already are, so a leaderboard
-- outlives every single run that fed it.

local Leaderboard = {}

Leaderboard.CAPACITY = 10

function Leaderboard.new()
  return {}
end

-- Shifts board's tail down to open a gap for `entry` at the first slot
-- whose current occupant does not outscore it, then drops it there.
-- Returns the 1-based rank entry lands at, counting past Leaderboard.CAPACITY
-- when the board is already full - the caller trims that overflow back off.
local function insertSorted(board, entry)
  local i = #board + 1
  while i > 1 and board[i - 1].score < entry.score do
    board[i] = board[i - 1]
    i = i - 1
  end
  board[i] = entry
  return i
end

-- Inserts `entry` (expects at least a numeric .score field) into `board`,
-- keeping it sorted best-score-first and capped at Leaderboard.CAPACITY.
-- A run that does not crack the cap is dropped outright rather than kept
-- around uncounted - a leaderboard only remembers what actually placed.
-- Returns the rank it landed at, or nil if it did not make the cut.
function Leaderboard.record(board, entry)
  local rank = insertSorted(board, entry)
  while #board > Leaderboard.CAPACITY do
    table.remove(board)
  end
  if rank > Leaderboard.CAPACITY then return nil end
  return rank
end

function Leaderboard.top(board, count)
  local out = {}
  for i = 1, math.min(count or Leaderboard.CAPACITY, #board) do
    out[i] = board[i]
  end
  return out
end

function Leaderboard.bestScore(board)
  return board[1] and board[1].score or 0
end

return Leaderboard
