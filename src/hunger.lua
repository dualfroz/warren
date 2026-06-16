-- Named bands layered over the player's raw satiation counter, the same
-- shape sanity.lua already gives its own slow-moving meter: a plain number
-- that Game:hungerTorchTick drains by one every round (untouched here),
-- classified into FED/HUNGRY/WEAK/STARVING tiers that a caller reads back
-- instead of re-deriving the cutoffs itself. Falling into WEAK or worse
-- costs real attack and defense - wired into entity.lua's effectiveAttack/
-- effectiveDefense alongside Sanity's own penalty, so a gaunt fighter hits
-- and blocks softer without combat.lua needing to know hunger exists at
-- all - and blocks the passive mending hungerTorchTick already grants from
-- a worn ring, an ironclad set or consecrated ground: a starving adventurer
-- can still down a potion, just not coast on a ring of regeneration while
-- fading. STARVING alone keeps hungerTorchTick's own flat hp drain, exactly
-- as before.
--
-- Eating is the mirror case: Hunger.eat folds fresh nutrition into the same
-- counter, capped at Hunger.CAP, but food eaten while already at that cap
-- is entirely wasted and leaves the diner Status.SLOW for a few turns - the
-- same overfull stumble a real glutton earns, reusing a status the engine
-- already ticks, serializes and renders with no special handling of its own.

local Status = require("status")

local Hunger = {}

Hunger.FED = "fed"
Hunger.HUNGRY = "hungry"
Hunger.WEAK = "weak"
Hunger.STARVING = "starving"

-- Starting ration for a fresh game (Game.new) and the ceiling Hunger.eat
-- refuses to bank past. Comfortably above START so a couple of found
-- rations can stack up before a long dive, without letting the pool grow
-- without bound.
Hunger.START = 1000
Hunger.CAP = 1200

-- Tier ceilings: a value at or below HUNGRY_MAX but above WEAK_MAX reads as
-- HUNGRY, and so on downward. 0 itself is always STARVING regardless of
-- where these ceilings sit.
Hunger.HUNGRY_MAX = 300
Hunger.WEAK_MAX = 100

Hunger.BLOAT_DURATION = 4

local ATTACK_PENALTY = {
  [Hunger.FED] = 0, [Hunger.HUNGRY] = 0, [Hunger.WEAK] = -2, [Hunger.STARVING] = -4,
}
local DEFENSE_PENALTY = {
  [Hunger.FED] = 0, [Hunger.HUNGRY] = 0, [Hunger.WEAK] = -1, [Hunger.STARVING] = -3,
}

-- A fresh entity - or a monster, which never accrues hunger of its own
-- since nothing ever calls Hunger.tick for one - reads as fully fed.
function Hunger.current(entity)
  return entity.satiation or Hunger.CAP
end

function Hunger.tierOf(entity)
  local value = Hunger.current(entity)
  if value <= 0 then return Hunger.STARVING end
  if value <= Hunger.WEAK_MAX then return Hunger.WEAK end
  if value <= Hunger.HUNGRY_MAX then return Hunger.HUNGRY end
  return Hunger.FED
end

function Hunger.attackPenalty(entity)
  return ATTACK_PENALTY[Hunger.tierOf(entity)]
end

function Hunger.defensePenalty(entity)
  return DEFENSE_PENALTY[Hunger.tierOf(entity)]
end

-- WEAK or worse blocks the passive regen hungerTorchTick otherwise grants
-- from a ring, a set bonus or friendly weather - a fading body has nothing
-- left over to spend on mending.
function Hunger.suppressesRegen(entity)
  local tier = Hunger.tierOf(entity)
  return tier == Hunger.WEAK or tier == Hunger.STARVING
end

-- One round of drain. Returns a log line only when the tier actually
-- changes, except STARVING which - matching the flat drain this replaces -
-- reports and bites for 1 hp every single round it holds, not just on the
-- turn it is first reached.
function Hunger.tick(entity)
  local before = Hunger.tierOf(entity)
  entity.satiation = math.max(0, Hunger.current(entity) - 1)
  local after = Hunger.tierOf(entity)
  if after == Hunger.STARVING then
    entity.hp = entity.hp - 1
    return "you are starving"
  end
  if after ~= before then
    return "you feel " .. after
  end
  return nil
end

-- Feeds `nutrition` in, clamped at Hunger.CAP. Returns true when the diner
-- was already at the cap - all of it wasted, and left Status.SLOW for
-- Hunger.BLOAT_DURATION turns - or false for an ordinary meal that landed.
function Hunger.eat(entity, nutrition)
  local wasFull = Hunger.current(entity) >= Hunger.CAP
  entity.satiation = math.min(Hunger.CAP, Hunger.current(entity) + nutrition)
  if wasFull then
    Status.apply(entity, Status.SLOW, Hunger.BLOAT_DURATION, 1)
  end
  return wasFull
end

return Hunger
