local helpers = require("helpers")
local Game = require("game")
local Morgue = require("morgue")
local Replay = require("replay")

local ok, eq = helpers.ok, helpers.eq

local tests = helpers.suite()

function tests.replayRunIsDeterministicAndMatchesAFreshGamesOwnReport()
  local seed, steps = 55, 60
  local game = Game.new(seed)
  for _ = 1, steps do
    if not game.player:isAlive() then break end
    game:autoStep()
  end
  local expected = Morgue.build(game)
  local replayed = Replay.run(seed, nil, steps)
  local matches, mismatchField = Replay.matches(expected, replayed)
  ok(matches, "replaying the same seed and step count reproduces every compared field (first mismatch: "
    .. tostring(mismatchField) .. ")")
  eq(replayed.turn, expected.turn, "the replay reaches the exact same turn")
  eq(replayed.deepestDepth, expected.deepestDepth, "the replay reaches the exact same depth")
end

function tests.replayVerifyConfirmsAGenuineReportAndReturnsItsScore()
  local seed, steps = 55, 60
  local game = Game.new(seed)
  for _ = 1, steps do
    if not game.player:isAlive() then break end
    game:autoStep()
  end
  local report = Morgue.build(game)
  local matches, mismatchField, score = Replay.verify(seed, nil, steps, report)
  ok(matches, "verify confirms a report that genuinely came from this seed and step count")
  eq(mismatchField, nil, "a matching verify names no mismatched field")
  eq(score, Morgue.score(report), "verify's returned score matches the report's own score")
end

function tests.replayVerifyFlagsATamperedReportAndStillReturnsTheRealScore()
  local seed, steps = 55, 60
  local game = Game.new(seed)
  for _ = 1, steps do
    if not game.player:isAlive() then break end
    game:autoStep()
  end
  local report = Morgue.build(game)
  local tampered = {}
  for k, v in pairs(report) do tampered[k] = v end
  tampered.gold = report.gold + 9999
  local matches, mismatchField, score = Replay.verify(seed, nil, steps, tampered)
  eq(matches, false, "a tampered gold total fails verification")
  eq(mismatchField, "gold", "verify names gold as the field that diverged")
  eq(score, Morgue.score(report), "the replay still reports the real, untampered score")
end

function tests.replayComparedFieldsCoversEveryFieldMorgueScoreActuallyReads()
  local weighed = {
    "deepestDepth", "kills", "bossKills", "questsCompleted", "artifactsFound",
    "vaultsOpened", "setPiecesFound", "chestsOpened", "playerLevel", "gold", "won",
  }
  for _, field in ipairs(weighed) do
    local found = false
    for _, compared in ipairs(Replay.COMPARED_FIELDS) do
      if compared == field then found = true end
    end
    ok(found, "Replay.COMPARED_FIELDS includes '" .. field .. "', every field Morgue.score weighs")
  end
end

function tests.replayMatchesReportsTheFirstDivergingFieldInComparedFieldsOrder()
  local base = {
    won = false, alive = true, deepestDepth = 3, turn = 100, gold = 10, essence = 2,
    kills = 1, bossKills = 0, questsCompleted = 0, artifactsFound = 0,
    vaultsOpened = 0, setPiecesFound = 0, chestsOpened = 0, playerLevel = 1,
  }
  local altered = {}
  for k, v in pairs(base) do altered[k] = v end
  altered.turn = 999
  local matches, field = Replay.matches(base, altered)
  eq(matches, false, "a divergent turn count fails the match")
  eq(field, "turn", "the mismatch is reported against the turn field specifically")
  eq(Replay.matches(base, base), true, "an identical report matches itself")
end

return tests
