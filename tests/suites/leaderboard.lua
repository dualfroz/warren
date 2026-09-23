local helpers = require("helpers")
local Leaderboard = require("leaderboard")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.leaderboardRecordOnAnEmptyBoardLandsAtRankOne()
  local board = Leaderboard.new()
  local rank = Leaderboard.record(board, { score = 100 })
  eq(rank, 1, "the first entry ever recorded ranks first")
  eq(#board, 1, "the board now holds exactly one entry")
end

function tests.leaderboardRecordKeepsTheBoardSortedBestScoreFirst()
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 50, tag = "a" })
  Leaderboard.record(board, { score = 90, tag = "b" })
  Leaderboard.record(board, { score = 70, tag = "c" })
  eq(board[1].tag, "b", "the highest score sorts to the very top")
  eq(board[2].tag, "c", "the middling score lands second")
  eq(board[3].tag, "a", "the lowest score lands last")
  local rank = Leaderboard.record(board, { score = 80, tag = "d" })
  eq(rank, 2, "a fresh entry ranks by where it actually lands, not where it was inserted")
  eq(board[2].tag, "d", "the new entry displaces the weaker one down a slot")
  eq(board[3].tag, "c", "everything below the insertion point shifts down by one")
end

function tests.leaderboardRecordDropsAnEntryThatDoesNotCrackTheCap()
  local board = Leaderboard.new()
  for i = 1, Leaderboard.CAPACITY do
    Leaderboard.record(board, { score = 1000 - i })
  end
  eq(#board, Leaderboard.CAPACITY, "the board fills to exactly its capacity")
  local rank = Leaderboard.record(board, { score = 1 })
  eq(rank, nil, "a score worse than everything already on the board does not crack it")
  eq(#board, Leaderboard.CAPACITY, "the board stays at capacity rather than growing")
  eq(board[Leaderboard.CAPACITY].score, 1000 - Leaderboard.CAPACITY, "the weakest surviving entry is unchanged")
end

function tests.leaderboardRecordBumpsTheWeakestEntryOffOnceFull()
  local board = Leaderboard.new()
  for i = 1, Leaderboard.CAPACITY do
    Leaderboard.record(board, { score = 1000 - i })
  end
  local worst = board[Leaderboard.CAPACITY].score
  local rank = Leaderboard.record(board, { score = 1500 })
  ok(rank ~= nil, "a score that beats the current worst entry cracks the board")
  eq(#board, Leaderboard.CAPACITY, "the board stays at capacity after bumping someone off")
  for _, entry in ipairs(board) do
    ok(entry.score ~= worst, "the previous weakest entry no longer appears on the board")
  end
end

function tests.leaderboardTopReturnsAtMostCountEntriesInOrder()
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 30 })
  Leaderboard.record(board, { score = 10 })
  Leaderboard.record(board, { score = 20 })
  local top2 = Leaderboard.top(board, 2)
  eq(#top2, 2, "top(2) returns exactly two entries")
  eq(top2[1].score, 30, "the first slot is the best score")
  eq(top2[2].score, 20, "the second slot is the next best score")
end

function tests.leaderboardTopDefaultsToTheFullCapacityWhenNoCountIsGiven()
  local board = Leaderboard.new()
  for i = 1, Leaderboard.CAPACITY + 3 do
    Leaderboard.record(board, { score = i })
  end
  local top = Leaderboard.top(board)
  eq(#top, Leaderboard.CAPACITY, "top() with no count returns the board's full capacity, not everything ever recorded")
end

function tests.leaderboardBestScoreReadsTheTopEntryOrZeroWhenEmpty()
  eq(Leaderboard.bestScore(Leaderboard.new()), 0, "an empty board's best score is zero")
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 42 })
  eq(Leaderboard.bestScore(board), 42, "the best score matches the single recorded entry")
end

return tests
