local helpers = require("helpers")
local Meta = require("meta")
local Leaderboard = require("leaderboard")
local Analytics = require("analytics")

local eq = helpers.eq

local tests = helpers.suite()

function tests.analyticsWinRateIsZeroWithNoRecordedRunsAndFractionalOtherwise()
  eq(Analytics.winRate(Meta.new()), 0, "a state with no recorded runs has a zero win rate")
  local meta = Meta.new()
  Meta.recordRun(meta, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = true })
  Meta.recordRun(meta, { deepestDepth = 1, kills = 0, bossKills = 0, questsCompleted = 0, artifactsFound = 0, won = false })
  eq(Analytics.winRate(meta), 0.5, "one win out of two runs is a 50% win rate")
end

function tests.analyticsAverageScoreIsZeroOnAnEmptyBoardAndTheMeanOtherwise()
  eq(Analytics.averageScore(Leaderboard.new()), 0, "an empty leaderboard has a zero average score")
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 100 })
  Leaderboard.record(board, { score = 200 })
  Leaderboard.record(board, { score = 300 })
  eq(Analytics.averageScore(board), 200, "the average of 100, 200 and 300 is exactly 200")
end

function tests.analyticsFavoriteClassPicksTheMostFrequentTiesBrokenByFirstAppearance()
  eq(Analytics.favoriteClass(Leaderboard.new()), nil, "an empty leaderboard has no favorite class")
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 90, className = "rogue" })
  Leaderboard.record(board, { score = 80, className = "mage" })
  Leaderboard.record(board, { score = 70, className = "mage" })
  eq(Analytics.favoriteClass(board), "mage", "mage appears twice, more than any other class")

  local tied = Leaderboard.new()
  Leaderboard.record(tied, { score = 50, className = "fighter" })
  Leaderboard.record(tied, { score = 40, className = "ranger" })
  eq(Analytics.favoriteClass(tied), "fighter",
    "a tie between equally-frequent classes breaks toward whichever appeared first on the board")
end

function tests.analyticsPercentileRanksAScoreAgainstTheBoardItWouldJoin()
  eq(Analytics.percentile(Leaderboard.new(), 999), 1, "an empty board can never hold anything back")
  local board = Leaderboard.new()
  Leaderboard.record(board, { score = 100 })
  Leaderboard.record(board, { score = 200 })
  Leaderboard.record(board, { score = 300 })
  Leaderboard.record(board, { score = 400 })
  eq(Analytics.percentile(board, 999), 1, "a score above everything beats the entire board")
  eq(Analytics.percentile(board, 1), 0, "a score below everything beats nothing")
  eq(Analytics.percentile(board, 250), 0.5, "a score beating exactly half the board reads as 50%")
  eq(Analytics.percentile(board, 200), 0.25, "a tied score counts as beaten, not beating, its equal")
end

return tests
