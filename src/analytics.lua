local Analytics = {}

function Analytics.winRate(meta)
  if meta.totalRuns == 0 then return 0 end
  return meta.wins / meta.totalRuns
end

function Analytics.averageScore(board)
  if #board == 0 then return 0 end
  local total = 0
  for _, entry in ipairs(board) do total = total + entry.score end
  return total / #board
end

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

function Analytics.percentile(board, score)
  if #board == 0 then return 1 end
  local beaten = 0
  for _, entry in ipairs(board) do
    if score > entry.score then beaten = beaten + 1 end
  end
  return beaten / #board
end

return Analytics
