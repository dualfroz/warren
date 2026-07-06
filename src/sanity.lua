-- The player's grip on their own mind, tracked as a slow-moving meter
-- alongside hp and mana rather than a temporary status.lua effect: nothing
-- brews or casts sanity away in a single stroke, it only bleeds out from
-- sustained exposure to dread (standing in the dark with a spent torch,
-- corpses piling up nearby, undead in plain sight, a curse whose bite is
-- already known, an infested floor's own creeping wrongness) and claws
-- back just as slowly, one calm turn - or one potion of clarity - at a
-- time. Falling tiers cost real attack and defense, exactly like
-- encumbrance.lua's overloaded penalty, and the worst tier risks losing a
-- turn outright to panic or giving the player's own position away with an
-- involuntary scream, so the meter is never just flavour text on the
-- status panel.

local Factions = require("factions")
local Curses = require("curses")
local Atmosphere = require("atmosphere")
local Stealth = require("stealth")

local Sanity = {}

Sanity.MAX = 100

Sanity.COMPOSED = "composed"
Sanity.SHAKEN = "shaken"
Sanity.TERRIFIED = "terrified"
Sanity.BROKEN = "broken"

-- Tier ceilings: a value at or below TERRIFIED_MAX but above 0 reads as
-- TERRIFIED, and so on upward. 0 itself is always BROKEN regardless of
-- where these ceilings sit.
Sanity.TERRIFIED_MAX = 30
Sanity.SHAKEN_MAX = 60

Sanity.DARKNESS_DREAD = 2
Sanity.CORPSE_DREAD_PER = 1
Sanity.CORPSE_DREAD_CAP = 4
Sanity.UNDEAD_DREAD_PER = 2
Sanity.UNDEAD_DREAD_CAP = 6
Sanity.CURSE_DREAD = 2
Sanity.WEATHER_DREAD = 2

-- Passive drift back toward composure on any turn that accrued no dread
-- at all - never enough on its own to outrun a floor still actively
-- haunting the player, but reliable once they step clear of it.
Sanity.CALM_RECOVERY = 1

Sanity.PANIC_NUMERATOR = 1
Sanity.PANIC_DENOMINATOR = 3

Sanity.SCREAM_NUMERATOR = 1
Sanity.SCREAM_DENOMINATOR = 4
Sanity.SCREAM_RADIUS = 6

local ATTACK_PENALTY = {
  [Sanity.COMPOSED] = 0, [Sanity.SHAKEN] = -1, [Sanity.TERRIFIED] = -3, [Sanity.BROKEN] = -5,
}
local DEFENSE_PENALTY = {
  [Sanity.COMPOSED] = 0, [Sanity.SHAKEN] = -1, [Sanity.TERRIFIED] = -2, [Sanity.BROKEN] = -4,
}

local function chebyshev(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- A fresh entity - or a monster, which never accrues any dread of its own
-- since nothing ever calls Sanity.tick for one - reads as fully composed.
function Sanity.current(entity)
  return entity.sanity or Sanity.MAX
end

function Sanity.tierOf(entity)
  local value = Sanity.current(entity)
  if value <= 0 then return Sanity.BROKEN end
  if value <= Sanity.TERRIFIED_MAX then return Sanity.TERRIFIED end
  if value <= Sanity.SHAKEN_MAX then return Sanity.SHAKEN end
  return Sanity.COMPOSED
end

function Sanity.adjust(entity, delta)
  local updated = Sanity.current(entity) + delta
  if updated > Sanity.MAX then updated = Sanity.MAX end
  if updated < 0 then updated = 0 end
  entity.sanity = updated
  return updated
end

function Sanity.attackPenalty(entity)
  return ATTACK_PENALTY[Sanity.tierOf(entity)]
end

function Sanity.defensePenalty(entity)
  return DEFENSE_PENALTY[Sanity.tierOf(entity)]
end

-- Each dread source below mirrors the vocabulary an existing module already
-- uses (Atmosphere's weather keys, Factions' undead tag, Curses' reveal
-- flag) rather than inventing a parallel one, and every source caps its own
-- contribution so no single cause can spike the meter to zero in one turn.

function Sanity.darknessDread(game)
  if not game.level.dark then return 0 end
  if game.player.light.fuel > 0 then return 0 end
  return Sanity.DARKNESS_DREAD
end

function Sanity.corpseDread(game)
  local count = 0
  for _, corpse in ipairs(game.level.corpses) do
    if chebyshev(corpse.x, corpse.y, game.player.x, game.player.y) <= 1 then
      count = count + 1
    end
  end
  return math.min(count * Sanity.CORPSE_DREAD_PER, Sanity.CORPSE_DREAD_CAP)
end

-- Only the undead currently visible weigh on the mind - one lurking
-- somewhere unseen on the floor cannot, unlike a nearby corpse the player
-- can smell without looking.
function Sanity.undeadDread(game)
  local count = 0
  local map = game.level.map
  for _, monster in ipairs(game.level.entities) do
    if monster:isAlive() and monster.faction == Factions.UNDEAD
      and game.visible[map:index(monster.x, monster.y)] then
      count = count + 1
    end
  end
  return math.min(count * Sanity.UNDEAD_DREAD_PER, Sanity.UNDEAD_DREAD_CAP)
end

-- A curse still hiding behind an ordinary appearance has not yet given its
-- wearer anything to dread - only a revealed one gnaws at the mind.
function Sanity.curseDread(entity)
  for _, slot in ipairs(Curses.SLOTS) do
    local item = entity[slot]
    if Curses.isCursed(item) and Curses.isRevealed(item) then return Sanity.CURSE_DREAD end
  end
  return 0
end

function Sanity.weatherDread(weather)
  if weather == Atmosphere.INFESTED then return Sanity.WEATHER_DREAD end
  return 0
end

function Sanity.totalDread(game)
  return Sanity.darknessDread(game)
    + Sanity.corpseDread(game)
    + Sanity.undeadDread(game)
    + Sanity.curseDread(game.player)
    + Sanity.weatherDread(game.level.weather)
end

-- Advances the player's sanity by one turn: every dread source at once, or
-- - on a turn none of them fired at all - a small step back toward
-- composure instead. Returns a log line the instant the player's tier
-- actually changes, in either direction, or nil while it holds.
function Sanity.tick(game)
  local before = Sanity.tierOf(game.player)
  local dread = Sanity.totalDread(game)
  local worsening = dread > 0
  if worsening then
    Sanity.adjust(game.player, -dread)
  else
    Sanity.adjust(game.player, Sanity.CALM_RECOVERY)
  end
  local after = Sanity.tierOf(game.player)
  if after == before then return nil end
  if worsening then
    if after == Sanity.BROKEN then return "your mind gives way to raw terror" end
    if after == Sanity.TERRIFIED then return "dread claws at the edges of your sanity" end
    return "your nerves begin to fray"
  end
  if after == Sanity.COMPOSED then return "your mind is your own again" end
  return "your nerves start to steady"
end

-- BROKEN alone risks losing the turn outright to a fit of terror; every
-- other tier always lets the player act. Rolls against `rng` so a seeded
-- run always panics on the identical turns.
function Sanity.rollPanic(rng, entity)
  if Sanity.tierOf(entity) ~= Sanity.BROKEN then return false end
  return rng:chance(Sanity.PANIC_NUMERATOR, Sanity.PANIC_DENOMINATOR)
end

-- TERRIFIED or worse risks an involuntary scream that alerts every living
-- monster within earshot (reuses stealth.lua's own wake path) - the fear
-- itself becomes a hazard to whoever else is on the floor.
function Sanity.rollScream(rng, game)
  local tier = Sanity.tierOf(game.player)
  if tier ~= Sanity.TERRIFIED and tier ~= Sanity.BROKEN then return false end
  if not rng:chance(Sanity.SCREAM_NUMERATOR, Sanity.SCREAM_DENOMINATOR) then return false end
  for _, monster in ipairs(game.level.entities) do
    if monster:isAlive() and chebyshev(monster.x, monster.y, game.player.x, game.player.y) <= Sanity.SCREAM_RADIUS then
      Stealth.alert(monster, game.player.x, game.player.y)
    end
  end
  return true
end

return Sanity
