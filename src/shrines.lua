-- Wayside altars the player can pray at for a permanent boon at a gold price.
-- A shrine's favor wears thin with use: each prayer at the same altar is more
-- likely to backfire into a curse than the last, so greedily re-praying at a
-- single shrine is a real risk rather than a free stat pump. Shrines are plain
-- data on level.shrines, keyed by position, so they serialize like traps and
-- hazards do with no special save-format handling.

local Status = require("status")
local Curses = require("curses")

local Shrines = {}

Shrines.WAR = "war"
Shrines.VITALITY = "vitality"
Shrines.WISDOM = "wisdom"
Shrines.FORTUNE = "fortune"

-- Fixed order so a given rng draw always names the same kind.
Shrines.order = { Shrines.WAR, Shrines.VITALITY, Shrines.WISDOM, Shrines.FORTUNE }

Shrines.names = {
  [Shrines.WAR] = "shrine of war",
  [Shrines.VITALITY] = "shrine of vitality",
  [Shrines.WISDOM] = "shrine of wisdom",
  [Shrines.FORTUNE] = "shrine of fortune",
}

local BASE_COST = 20
local COST_STEP = 10

-- Prayer cost climbs with prior use at this specific altar, the same shape as
-- its rising curse risk: the shrine asks more and gives worse odds once its
-- patience with the petitioner is spent.
function Shrines.costFor(shrine)
  return BASE_COST + shrine.uses * COST_STEP
end

-- Numerator over a denominator of 6: the first prayer risks 1-in-6, climbing
-- by one for every prior use, capped at a certainty of 6-in-6.
function Shrines.curseChance(shrine)
  return math.min(shrine.uses + 1, 6), 6
end

local function grantBlessing(player, kind)
  if kind == Shrines.WAR then
    player.attack = player.attack + 1
    player.baseAttack = player.baseAttack + 1
    return "your grip tightens with martial favor"
  elseif kind == Shrines.VITALITY then
    player.maxHp = player.maxHp + 5
    player.hp = player.hp + 5
    return "vigor floods through you"
  elseif kind == Shrines.WISDOM then
    player.maxMana = player.maxMana + 3
    player.mana = player.maxMana
    return "arcane insight fills your mind"
  else
    local cleansed = false
    local kept = {}
    for _, active in ipairs(player.statuses) do
      if active.kind == Status.POISON or active.kind == Status.BURNING
        or active.kind == Status.WEAKEN or active.kind == Status.SLOW then
        cleansed = true
      else
        kept[#kept + 1] = active
      end
    end
    player.statuses = kept
    Status.apply(player, Status.SHIELD, 10, 1)
    if Curses.cleanseWorn(player) > 0 then cleansed = true end
    if cleansed then
      return "fortune cleanses your ailments and wards you"
    end
    return "fortune wards you against harm"
  end
end

local function inflictCurse(player)
  Status.apply(player, Status.WEAKEN, 8, 1)
  Status.apply(player, Status.SLOW, 8, 1)
  return "the shrine's favor turns against you"
end

-- Attempts a prayer at `shrine` for `game.player`. When the price cannot be
-- met nothing is spent and this returns (false, lines). Otherwise the gold is
-- always spent, the shrine's use count always advances (so its price and
-- curse odds keep climbing), and this returns (true, lines) describing
-- whichever of a blessing or a curse landed.
function Shrines.pray(game, shrine)
  local player = game.player
  local cost = Shrines.costFor(shrine)
  if player.gold < cost then
    return false, { "you cannot afford " .. Shrines.names[shrine.kind] .. "'s price" }
  end
  player.gold = player.gold - cost
  local numerator, denominator = Shrines.curseChance(shrine)
  local cursed = game.rng:chance(numerator, denominator)
  shrine.uses = shrine.uses + 1
  local line
  if cursed then
    line = inflictCurse(player)
  else
    line = grantBlessing(player, shrine.kind)
  end
  return true, {
    string.format("you pray at the %s for %d gold", Shrines.names[shrine.kind], cost),
    line,
  }
end

return Shrines
