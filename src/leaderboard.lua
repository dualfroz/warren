local Leaderboard = {}

Leaderboard.CAPACITY = 10

function Leaderboard.new()
  return {}
end

local function insertSorted(board, entry)
  local i = #board + 1
  while i > 1 and board[i - 1].score < entry.score do
    board[i] = board[i - 1]
    i = i - 1
  end
  board[i] = entry
  return i
end

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
