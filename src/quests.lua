-- Bounty boards scattered through the dungeon from depth two on. Each board
-- is built with exactly one bounty already written on it (a cull, a hoard or
-- a depth pact), fixed at generation time from the floor's own rng so a given
-- (worldSeed, depth) always offers the identical bounty. Standing on an
-- unclaimed board binds the player to its pact for free (no turn spent, same
-- as learning a skill); a board only ever grants one bounty in its lifetime,
-- so re-rolling by revisiting an already-claimed board is not possible. A
-- bound pact resolves itself the instant its condition is met - no trip back
-- to the board required - paying out gold, xp and essence in one stroke.

local Monsters = require("monsters")

local Quests = {}

Quests.CULL = "cull"
Quests.HOARD = "hoard"
Quests.DEPTH = "depth"

-- Fixed order so a given rng draw always names the same kind.
Quests.order = { Quests.CULL, Quests.HOARD, Quests.DEPTH }

-- Builds the one bounty a freshly placed board offers on `depth`, clamping any
-- depth target to `maxDepth` so a pact can never demand the unreachable.
function Quests.generate(rng, depth, maxDepth)
  local kind = Quests.order[rng:range(1, #Quests.order)]
  local bounty = {
    kind = kind,
    rewardGold = 15 + depth * 8,
    rewardXp = 10 + depth * 4,
  }
  if kind == Quests.CULL then
    local eligible = Monsters.forDepth(depth)
    local spec = eligible[rng:range(1, #eligible)]
    bounty.species = spec.key
    bounty.speciesName = spec.name
    bounty.need = rng:range(2, 4)
    bounty.have = 0
  elseif kind == Quests.HOARD then
    bounty.need = 40 + depth * 20
  else
    bounty.need = math.min(depth + rng:range(2, 4), maxDepth)
  end
  return bounty
end

function Quests.describe(bounty)
  if bounty.kind == Quests.CULL then
    return string.format("cull %d %s (%d/%d)", bounty.need, bounty.speciesName, bounty.have, bounty.need)
  elseif bounty.kind == Quests.HOARD then
    return string.format("amass %d gold", bounty.need)
  end
  return string.format("reach depth %d", bounty.need)
end

-- Binds `player` to `board`'s bounty, provided the player is not already
-- bound to one and the board has not already been claimed. Returns (true,
-- line) on success or (false, line) explaining why not.
function Quests.accept(player, board)
  if player.quest then
    return false, "you already hold a bounty"
  end
  if board.claimed then
    return false, "this board's ledger is already spent"
  end
  board.claimed = true
  player.quest = board.quest
  return true, "you bind yourself to a bounty: " .. Quests.describe(board.quest)
end

-- Registers a kill toward the player's active cull bounty if the species
-- matches. A no-op for any other kind, an unrelated species, or no bounty.
function Quests.registerKill(player, species)
  local bounty = player.quest
  if bounty and bounty.kind == Quests.CULL and species == bounty.species and bounty.have < bounty.need then
    bounty.have = bounty.have + 1
  end
end

-- True once `player`'s active bounty (if any) is fulfilled by the current
-- state: a cull once its tally is met, a hoard once live gold clears its
-- absolute target, a depth pact once the player has reached it.
function Quests.resolved(player, depth)
  local bounty = player.quest
  if not bounty then return false end
  if bounty.kind == Quests.CULL then return bounty.have >= bounty.need end
  if bounty.kind == Quests.HOARD then return player.gold >= bounty.need end
  return depth >= bounty.need
end

return Quests
