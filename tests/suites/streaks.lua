local helpers = require("helpers")
local Streaks = require("streaks")

local eq = helpers.eq

local tests = helpers.suite()

function tests.streaksCurrentIsZeroAndNilOnAnEmptyHistory()
  local length, outcome = Streaks.current(Streaks.new())
  eq(length, 0, "an empty history has a streak length of zero")
  eq(outcome, nil, "an empty history has no outcome to report")
end

function tests.streaksCurrentCountsOnlyTheUnbrokenRunAtTheEnd()
  local history = Streaks.new()
  Streaks.record(history, true)
  Streaks.record(history, true)
  Streaks.record(history, false)
  Streaks.record(history, false)
  Streaks.record(history, false)
  local length, outcome = Streaks.current(history)
  eq(length, 3, "three losses in a row at the tail end give a streak of three")
  eq(outcome, false, "the current streak's outcome is a loss")

  Streaks.record(history, true)
  length, outcome = Streaks.current(history)
  eq(length, 1, "a single win right after a loss streak is itself a streak of exactly one")
  eq(outcome, true, "the fresh win flips the current outcome to a win")
end

function tests.streaksRecordTrimsHistoryPastItsCap()
  local history = Streaks.new()
  for i = 1, Streaks.HISTORY_CAP + 10 do
    Streaks.record(history, i % 2 == 0)
  end
  eq(#history, Streaks.HISTORY_CAP, "history never grows past its fixed cap")
end

function tests.streaksRecordDropsTheOldestEntryNotTheNewestOnceOverCap()
  local history = Streaks.new()
  for i = 1, Streaks.HISTORY_CAP do
    Streaks.record(history, false)
  end
  eq(#history, Streaks.HISTORY_CAP, "filling exactly to the cap keeps every entry")
  Streaks.record(history, true)
  eq(#history, Streaks.HISTORY_CAP, "one more push still respects the same cap")
  eq(history[#history], true, "the newest push is the one that survives at the tail")
  eq(history[1], false, "the oldest entry was the one dropped to make room")
end

function tests.streaksBestWinStreakFindsTheLongestWinRunAnywhereNotJustTheActiveOne()
  local history = Streaks.new()
  for _, won in ipairs({ true, true, true, false, true, false, true, true }) do
    Streaks.record(history, won)
  end
  eq(Streaks.bestWinStreak(history), 3, "the best win streak is the earlier run of three, not the trailing two")
  local currentLength, currentOutcome = Streaks.current(history)
  eq(currentLength, 2, "the currently active streak is only two long")
  eq(currentOutcome, true, "the currently active streak is a winning one")
end

function tests.streaksBestWinStreakIsZeroWithNoWinsAtAll()
  local history = Streaks.new()
  Streaks.record(history, false)
  Streaks.record(history, false)
  eq(Streaks.bestWinStreak(history), 0, "a history of nothing but losses has a best win streak of zero")
end

return tests
