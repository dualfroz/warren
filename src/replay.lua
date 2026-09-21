local Game = require("game")
local Morgue = require("morgue")

local Replay = {}

function Replay.run(seed, options, steps)
  local game = Game.new(seed, options)
  for _ = 1, steps do
    if not game.player:isAlive() then break end
    game:autoStep()
  end
  return Morgue.build(game)
end

Replay.COMPARED_FIELDS = {
  "won", "alive", "deepestDepth", "turn", "gold", "essence",
  "kills", "bossKills", "questsCompleted", "artifactsFound",
  "vaultsOpened", "setPiecesFound", "chestsOpened", "playerLevel",
}

function Replay.matches(report, replayed)
  for _, field in ipairs(Replay.COMPARED_FIELDS) do
    if report[field] ~= replayed[field] then return false, field end
  end
  return true, nil
end

function Replay.verify(seed, options, steps, report)
  local replayed = Replay.run(seed, options, steps)
  local matches, mismatchField = Replay.matches(report, replayed)
  return matches, mismatchField, Morgue.score(replayed)
end

return Replay
