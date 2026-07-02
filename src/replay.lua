-- Re-simulates a run from nothing but its own seed, options and step count
-- to confirm it actually reproduces a recorded outcome - the same guarantee
-- rngDeterminism and mapDeterminism already lean on internally, spelled out
-- here as a standalone check a caller can run against any (seed, options,
-- steps) triple, e.g. to confirm a regression fix left a known-good seed's
-- ending untouched, or to flag a leaderboard entry whose recorded report no
-- longer matches what that seed actually plays out to.
--
-- Scope: this replays purely from (seed, options, steps) - it says nothing
-- about a run that also carried mutable meta.lua state (perks already
-- owned, a compendium already partway filled), since that state moves
-- forward with every run and is never itself snapshotted. Call it only for
-- a plain run, or pass the exact historical options a meta-bearing run
-- actually started with.

local Game = require("game")
local Morgue = require("morgue")

local Replay = {}

-- Runs a fresh game for exactly `steps` auto-steps (or until the player
-- dies first) and returns its final Morgue.build report.
function Replay.run(seed, options, steps)
  local game = Game.new(seed, options)
  for _ = 1, steps do
    if not game.player:isAlive() then break end
    game:autoStep()
  end
  return Morgue.build(game)
end

-- Every field Morgue.score actually reads, plus won/alive - deliberately not
-- equipment/killTally/finalMessages, which are free-form listings a caller
-- rarely wants compared byte-for-byte.
Replay.COMPARED_FIELDS = {
  "won", "alive", "deepestDepth", "turn", "gold", "essence",
  "kills", "bossKills", "questsCompleted", "artifactsFound",
  "vaultsOpened", "setPiecesFound", "chestsOpened", "playerLevel",
}

-- True iff `report` and `replayed` agree on every Replay.COMPARED_FIELDS
-- entry. Returns (false, field) naming the first mismatch found, in
-- Replay.COMPARED_FIELDS order, so a caller can say exactly what diverged
-- rather than just that something did.
function Replay.matches(report, replayed)
  for _, field in ipairs(Replay.COMPARED_FIELDS) do
    if report[field] ~= replayed[field] then return false, field end
  end
  return true, nil
end

-- Re-simulates (seed, options, steps) and checks whether it reproduces
-- `report` (see Replay.matches). Always returns the score the replay itself
-- earned, whether or not it matched, so a caller can tell a merely-outdated
-- record from one whose replay actually played worse.
function Replay.verify(seed, options, steps, report)
  local replayed = Replay.run(seed, options, steps)
  local matches, mismatchField = Replay.matches(report, replayed)
  return matches, mismatchField, Morgue.score(replayed)
end

return Replay
