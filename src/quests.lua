local Monsters = require("monsters")

local Quests = {}

Quests.CULL = "cull"
Quests.HOARD = "hoard"
Quests.DEPTH = "depth"

Quests.order = { Quests.CULL, Quests.HOARD, Quests.DEPTH }

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

function Quests.registerKill(player, species)
  local bounty = player.quest
  if bounty and bounty.kind == Quests.CULL and species == bounty.species and bounty.have < bounty.need then
    bounty.have = bounty.have + 1
  end
end

function Quests.resolved(player, depth)
  local bounty = player.quest
  if not bounty then return false end
  if bounty.kind == Quests.CULL then return bounty.have >= bounty.need end
  if bounty.kind == Quests.HOARD then return player.gold >= bounty.need end
  return depth >= bounty.need
end

return Quests
