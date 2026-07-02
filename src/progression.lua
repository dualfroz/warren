-- Player experience and leveling. Killing a monster grants xp scaled by the
-- species catalog; once xp clears the threshold for the current level the
-- player levels up, gaining permanent hp/attack/defense and a full heal-up on
-- the hp gained. A single large xp grant can trigger several level-ups in a
-- row, so the gain loops rather than checking once.

local Progression = {}

-- Threshold to advance from `level` to `level + 1`. Linear on purpose: pure
-- and easy to reason about in tests, unlike an exponential curve.
function Progression.xpToNext(level)
  return 20 + (level - 1) * 15
end

local function hpGain(level)
  return 4 + level
end

local function levelUp(player)
  player.level = player.level + 1
  local gain = hpGain(player.level)
  player.maxHp = player.maxHp + gain
  player.hp = player.hp + gain
  player.attack = player.attack + 1
  player.baseAttack = player.baseAttack + 1
  if player.level % 2 == 0 then
    player.defense = player.defense + 1
    player.baseDefense = player.baseDefense + 1
  end
  player.skillPoints = (player.skillPoints or 0) + 1
  player.xp = player.xp - player.xpNext
  player.xpNext = Progression.xpToNext(player.level)
  return string.format("you reach level %d", player.level)
end

-- Applies an xp gain to the player, running as many level-ups as the gain
-- covers. Returns the log lines produced, in order.
function Progression.grantXp(player, amount)
  if amount <= 0 then return {} end
  player.xp = player.xp + amount
  local lines = {}
  while player.xp >= player.xpNext do
    lines[#lines + 1] = levelUp(player)
  end
  return lines
end

return Progression
